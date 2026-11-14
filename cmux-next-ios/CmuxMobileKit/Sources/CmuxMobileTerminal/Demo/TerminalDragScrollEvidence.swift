// DEBUG and Demo builds only: an evidence harness, never compiled into Production.
#if os(iOS) && DEBUG
import Foundation
import QuartzCore

/// DEBUG evidence harness for T-SCROLL-12 (PR #42798): a terminal that needs
/// no Mac, put into one terminal mode by
/// `-CmuxMobileTerminalDemo -CmuxDragScrollEvidence MODE`, that records every
/// byte the phone sends it and scrolls its own numbered document on wheel
/// reports and cursor keys, so a recording shows what each gesture did.
///
/// MODE: `mouse` (1049 + 1000/1002/1003 + 1006), `alt` (1049 only: Ghostty's
/// default alternate scroll), `altapp` (1049 + DECCKM, application cursor),
/// `alt1007off` (1049 + DECRST 1007), `shell` (the primary screen with 400
/// lines of output), `widealt` / `widemouse` (`alt` / `mouse` on a 120×40
/// Mac grid, wider than the phone).
@MainActor
public final class TerminalDragScrollEvidenceSession: TerminalSession {
    public enum Mode: String, CaseIterable, Sendable {
        case mouse, alt, altapp, alt1007off, shell, widealt, widemouse

        var alternate: Bool { self != .shell }
        var mouse: Bool { self == .mouse || self == .widemouse }
        var wide: Bool { self == .widealt || self == .widemouse }
        /// What the program writes on entering its screen.
        var modes: String {
            switch self {
            case .mouse, .widemouse: "\u{1B}[?1049h\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1003h\u{1B}[?1006h"
            case .alt, .widealt: "\u{1B}[?1049h"
            case .altapp: "\u{1B}[?1049h\u{1B}[?1h\u{1B}="
            case .alt1007off: "\u{1B}[?1049h\u{1B}[?1007l"
            case .shell: ""
            }
        }
    }

    public let mode: Mode
    public var programName: String { mode.alternate ? "evidence-\(mode.rawValue)" : "zsh" }
    public var isAlternateScreen: Bool { mode.alternate }
    public var remoteColumns: Int? { mode.wide ? 120 : nil }
    public var remoteRows: Int? { mode.wide ? 40 : nil }

    private var handler: (@MainActor (TerminalSessionEvent) -> Void)?
    private var columns = 50
    private var rows = 40
    private let documentLines = 400
    private var top = 200
    private var pending: [UInt8] = []
    private let started = CACurrentMediaTime()

    // What the phone sent, for the UI test (``bytesLabel``).
    private(set) var totalBytes = 0
    private(set) var chunks: [String] = []
    private(set) var wheelUp = 0, wheelDown = 0, arrowUp = 0, arrowDown = 0, clicks = 0, motion = 0, other = 0

    public init(mode: Mode) {
        self.mode = mode
        if mode.wide { columns = 120; rows = 40 }
    }

    public static var requestedMode: Mode? {
        UserDefaults.standard.string(forKey: "CmuxDragScrollEvidence").flatMap(Mode.init(rawValue:))
    }

    public func start(_ handler: @escaping @MainActor (TerminalSessionEvent) -> Void) {
        self.handler = handler
        handler(.connection(.attached))
        if mode.alternate {
            write("\u{1B}c" + mode.modes + "\u{1B}[H\u{1B}[2J")
            handler(.alternateScreen(true))
            handler(.title("\(programName) — evidence"))
            render()
        } else {
            handler(.title("zsh — evidence"))
            var text = "\u{1B}c"
            for line in 1...documentLines {
                text += String(format: "out %04d \u{1B}[3%dm%@\u{1B}[0m\r\n", line, 1 + line % 6, String(repeating: "#", count: line % 30))
            }
            text += "\u{1B}[32m❯\u{1B}[0m "
            write(text)
        }
    }

    public func send(_ bytes: Data) {
        totalBytes += bytes.count
        chunks.append(String(format: "%.3f:", CACurrentMediaTime() - started) + Self.escape(bytes))
        pending.append(contentsOf: bytes)
        parse()
        // The header counts every byte, so redraw on each write.
        if mode.alternate { render() }
    }

    public func resize(columns: Int, rows: Int) {
        guard !mode.wide, columns > 0, rows > 0 else { return }
        self.columns = columns
        self.rows = rows
        if mode.alternate { render() }
    }

    public func stop() { handler = nil }

    // MARK: Input

    private func parse() {
        while !pending.isEmpty {
            guard pending[0] == 0x1B else { pending.removeFirst(); other += 1; continue }
            guard pending.count >= 3 else { return }
            if pending[1] == 0x5B, pending[2] == 0x3C {
                // SGR mouse: ESC [ < b ; x ; y M|m
                guard let end = pending.firstIndex(where: { $0 == 0x4D || $0 == 0x6D }) else {
                    if pending.count > 24 { pending.removeAll() }
                    return
                }
                let body = String(decoding: pending[3..<end], as: UTF8.self).split(separator: ";").compactMap { Int($0) }
                let press = pending[end] == 0x4D
                pending.removeFirst(end + 1)
                guard let button = body.first else { continue }
                switch button {
                case 64: wheelUp += 1; scroll(-1)
                case 65: wheelDown += 1; scroll(1)
                case 0...2: if press { clicks += 1 }
                case 32...35: motion += 1
                default: other += 1
                }
            } else if pending[1] == 0x5B || pending[1] == 0x4F {
                switch pending[2] {
                case 0x41: arrowUp += 1; scroll(-1)
                case 0x42: arrowDown += 1; scroll(1)
                default: other += 1
                }
                pending.removeFirst(3)
            } else {
                other += 1
                pending.removeFirst()
            }
        }
    }

    private func scroll(_ by: Int) {
        top = min(max(0, top + by), max(0, documentLines - (rows - 1)))
    }

    // MARK: Output

    private func write(_ text: String) {
        handler?(.output(Data(text.utf8)))
    }

    private func render() {
        var text = "\u{1B}[?25l\u{1B}[H"
        let header = " \(mode.rawValue) top=\(top + 1) wheel↑\(wheelUp)↓\(wheelDown) key↑\(arrowUp)↓\(arrowDown) click\(clicks) mv\(motion) B\(totalBytes)"
        text += "\u{1B}[1;1H\u{1B}[7m" + String(header.padding(toLength: columns, withPad: " ", startingAt: 0).prefix(columns)) + "\u{1B}[0m"
        for row in 2...max(2, rows) {
            let line = top + row - 1
            var body = String(format: "line %04d ", line)
            if mode.wide {
                body += (body.count..<columns).map { $0 % 10 == 0 ? "|" : String($0 % 10) }.joined()
            } else {
                body += String(repeating: line % 2 == 0 ? "=" : "-", count: line % 25)
            }
            text += "\u{1B}[\(row);1H\u{1B}[3\(1 + line % 6)m" + String(body.prefix(columns)) + "\u{1B}[0m\u{1B}[K"
        }
        write(text)
    }

    // MARK: Labels for the UI test

    /// `n=<bytes> c=<chunks> wu= wd= au= ad= click= mv= other= top=` then `¦`
    /// and each chunk the phone sent, `<seconds>:<escaped bytes>`.
    var bytesLabel: String {
        "n=\(totalBytes) c=\(chunks.count) wu=\(wheelUp) wd=\(wheelDown) au=\(arrowUp) ad=\(arrowDown) click=\(clicks) mv=\(motion) other=\(other) top=\(top + 1)"
            + (chunks.isEmpty ? "" : "¦" + chunks.joined(separator: "¦"))
    }

    var now: Double { CACurrentMediaTime() - started }

    static func escape(_ bytes: Data) -> String {
        var out = ""
        for byte in bytes {
            switch byte {
            case 0x1B: out += "\\e"
            case 0x20...0x7E where byte != 0x5C: out += String(UnicodeScalar(byte))
            default: out += String(format: "\\x%02X", byte)
            }
        }
        return out
    }
}

/// DEBUG: every display frame's interval on the main run loop, for the
/// evidence harness (a hitch is a frame later than 1.5 display intervals).
@MainActor
final class TerminalDragScrollPacing: NSObject {
    private var link: CADisplayLink?
    private var previous: CFTimeInterval = 0
    private let started = CACurrentMediaTime()
    private(set) var frames = 0
    private(set) var hitches = 0
    private(set) var longestMs = 0.0
    /// Each hitch: seconds since start (the session's clock origin is within
    /// a frame of this one) and its interval in ms. The last 200.
    private(set) var hitchList: [(at: Double, ms: Double)] = []

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = .terminal
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        if previous > 0 {
            let interval = link.timestamp - previous
            let expected = link.targetTimestamp - link.timestamp
            frames += 1
            longestMs = max(longestMs, interval * 1000)
            if expected > 0, interval > expected * 1.5 {
                hitches += 1
                hitchList.append((CACurrentMediaTime() - started, interval * 1000))
                if hitchList.count > 200 { hitchList.removeFirst() }
            }
        }
        previous = link.timestamp
    }

    var label: String {
        "frames=\(frames) hitches=\(hitches) longestMs=\(String(format: "%.1f", longestMs)) list="
            + hitchList.map { String(format: "%.3f/%.1f", $0.at, $0.ms) }.joined(separator: ",")
    }
}
#endif
