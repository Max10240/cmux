import ObjectiveC
import XCTest

/// Evidence harness for T-SCROLL-12 (PR #42798, "a drag over a full-screen app
/// is Ghostty's scroll"): real XCUITest drags, flings, taps and pans over the
/// terminal demo's evidence session (`-CmuxDragScrollEvidence MODE`, DEBUG),
/// which records every byte the phone sends and scrolls its numbered document
/// on wheel reports and cursor keys. Each gesture attaches the exact bytes,
/// the counts, the frame pacing in its window and the screen's debugState,
/// with a screenshot before and after. It records; it asserts nothing about
/// the behavior (a separate verifier judges the evidence).
///
/// The app is never left to go idle between a fling and the touch that should
/// stop it: XCUITest's wait for quiescence is turned off for this suite, so a
/// tap lands while the fling still runs.
final class TerminalDragScrollUITests: XCTestCase {
    private var summary: [String] = []
    private var mode = ""

    override func setUp() {
        continueAfterFailure = true
        Self.skipQuiescence()
    }

    override func tearDown() {
        let attachment = XCTAttachment(string: summary.joined(separator: "\n") + "\n")
        attachment.name = "SUMMARY-\(mode).txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Modes

    @MainActor func test1MouseReporting() {
        let app = launch("mouse")
        slow(app, "s2-mouse-slow-drag-down", from: 0.3, to: 0.6)
        slow(app, "s2-mouse-slow-drag-up", from: 0.6, to: 0.3)
        fling(app, "s2-mouse-fling-down", from: 0.3, to: 0.55)
        fling(app, "s2-mouse-fling-up", from: 0.6, to: 0.35)
        idle(1.5)
        tap(app, "s6-mouse-tap-after-idle", at: 0.45)
        idle(1.5)
        record(app, "s6-mouse-drag-then-immediate-tap-41913", settle: 2) {
            self.drag(app, from: 0.3, to: 0.55, velocity: 400, hold: 0)
            self.point(app, 0.45).tap()
        }
        idle(1.5)
        record(app, "s6-mouse-drag-then-tap-after-0.7s", settle: 2) {
            self.drag(app, from: 0.3, to: 0.55, velocity: 400, hold: 0)
            self.idle(0.7)
            self.point(app, 0.45).tap()
        }
        flingThenTap(app, "s6-mouse-fling-then-tap")
        app.terminate()
    }

    @MainActor func test2AlternateScrollNormalCursor() {
        let app = launch("alt")
        slow(app, "s3-alt-slow-drag-down", from: 0.3, to: 0.6)
        slow(app, "s3-alt-slow-drag-up", from: 0.6, to: 0.3)
        fling(app, "s3-alt-fling-down", from: 0.3, to: 0.55)
        fling(app, "s3-alt-fling-up", from: 0.6, to: 0.35)
        idle(1.5)
        tap(app, "s6-alt-tap", at: 0.45)
        flingWithoutTap(app, "s6-alt-fling-control-no-tap")
        flingThenTap(app, "s6-alt-fling-then-tap")
        app.terminate()
    }

    @MainActor func test3AlternateScrollApplicationCursor() {
        let app = launch("altapp")
        slow(app, "s3-altapp-slow-drag-down", from: 0.3, to: 0.6)
        slow(app, "s3-altapp-slow-drag-up", from: 0.6, to: 0.3)
        fling(app, "s3-altapp-fling-down", from: 0.3, to: 0.55)
        fling(app, "s3-altapp-fling-up", from: 0.6, to: 0.35)
        app.terminate()
    }

    @MainActor func test4AlternateScrollOff() {
        let app = launch("alt1007off")
        slow(app, "s4-1007off-slow-drag-down", from: 0.3, to: 0.6)
        slow(app, "s4-1007off-slow-drag-up", from: 0.6, to: 0.3)
        fling(app, "s4-1007off-fling-down", from: 0.3, to: 0.55)
        fling(app, "s4-1007off-fling-up", from: 0.6, to: 0.35)
        app.terminate()
    }

    @MainActor func test5PrimaryScreenShell() {
        let app = launch("shell")
        slow(app, "s5-shell-slow-drag-down", from: 0.3, to: 0.6)
        slow(app, "s5-shell-slow-drag-up", from: 0.6, to: 0.3)
        fling(app, "s5-shell-fling-down", from: 0.3, to: 0.55)
        fling(app, "s5-shell-fling-up", from: 0.6, to: 0.35)
        app.terminate()
    }

    @MainActor func test6WideGridHorizontalPan() {
        let app = launch("widealt")
        horizontal(app, "s6-widealt-horizontal-pan-left", from: 0.85, to: 0.15)
        horizontal(app, "s6-widealt-horizontal-pan-right", from: 0.15, to: 0.85)
        slow(app, "s6-widealt-vertical-drag-control", from: 0.3, to: 0.6)
        app.terminate()
    }

    @MainActor func test7WideGridHorizontalPanMouse() {
        let app = launch("widemouse")
        horizontal(app, "s6-widemouse-horizontal-pan-left", from: 0.85, to: 0.15)
        horizontal(app, "s6-widemouse-horizontal-pan-right", from: 0.15, to: 0.85)
        slow(app, "s6-widemouse-vertical-drag-control", from: 0.3, to: 0.6)
        app.terminate()
    }

    // MARK: Gestures

    @MainActor private func slow(_ app: XCUIApplication, _ name: String, from: CGFloat, to: CGFloat) {
        record(app, name, settle: 1.5) { self.drag(app, from: from, to: to, velocity: 250, hold: 0.4) }
    }

    @MainActor private func fling(_ app: XCUIApplication, _ name: String, from: CGFloat, to: CGFloat) {
        record(app, name, settle: 3.5) { self.drag(app, from: from, to: to, velocity: 3000, hold: 0) }
    }

    @MainActor private func tap(_ app: XCUIApplication, _ name: String, at y: CGFloat) {
        record(app, name, settle: 1.5) { self.point(app, y).tap() }
    }

    @MainActor private func horizontal(_ app: XCUIApplication, _ name: String, from: CGFloat, to: CGFloat) {
        record(app, name, settle: 1.5) {
            self.point(app, 0.45, x: from).press(forDuration: 0.05, thenDragTo: self.point(app, 0.45, x: to),
                                                 withVelocity: XCUIGestureVelocity(400), thenHoldForDuration: 0.3)
        }
    }

    /// A fling, the bytes just after its release, then the same 1.5 s later
    /// with no touch: how long a fling keeps sending (control for the tap).
    @MainActor private func flingWithoutTap(_ app: XCUIApplication, _ name: String) {
        idle(1.5)
        let before = read(app)
        screenshot(app, "\(name)-before")
        drag(app, from: 0.3, to: 0.55, velocity: 3000, hold: 0)
        let released = read(app)
        idle(1.5)
        let later = read(app)
        report(app, name, [("before", before), ("just after release", released), ("1.5 s later, no touch", later)])
    }

    /// A fling, then a tap while it runs: the bytes up to the tap and after it.
    @MainActor private func flingThenTap(_ app: XCUIApplication, _ name: String) {
        idle(1.5)
        let before = read(app)
        screenshot(app, "\(name)-before")
        drag(app, from: 0.3, to: 0.55, velocity: 3000, hold: 0)
        point(app, 0.45).tap()
        let tapped = read(app)
        idle(1.5)
        let later = read(app)
        report(app, name, [("before", before), ("just after the tap", tapped), ("1.5 s after the tap", later)])
    }

    @MainActor private func drag(_ app: XCUIApplication, from: CGFloat, to: CGFloat, velocity: CGFloat, hold: TimeInterval) {
        point(app, from).press(forDuration: 0.05, thenDragTo: point(app, to),
                               withVelocity: XCUIGestureVelocity(velocity), thenHoldForDuration: hold)
    }

    @MainActor private func point(_ app: XCUIApplication, _ y: CGFloat, x: CGFloat = 0.5) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private func idle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: Recording

    @MainActor private func launch(_ mode: String) -> XCUIApplication {
        self.mode = mode
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_MOBILE_MOCK_AUTH"] = "1"
        app.launchArguments += ["-cmuxMobile.setupComplete", "YES", "-CmuxMobileTerminalDemo", "-CmuxDragScrollEvidence", mode]
        app.launch()
        let bytes = app.staticTexts["debug.dragscroll.bytes"]
        XCTAssertTrue(bytes.waitForExistence(timeout: 30), "the evidence session's byte label\n\(app.debugDescription)")
        // The surface attached, sized and drew the mode's first frame.
        idle(4)
        let first = read(app)
        summary.append("mode \(mode) launched: \(first.header) | \(first.state)")
        screenshot(app, "\(mode)-00-launched")
        return app
    }

    struct Reading {
        var header: String
        var counts: [String: Int]
        var chunks: [String]
        var state: String
        var now: Double
        var hitches: Int
        var frames: Int
        var hitchList: [(at: Double, ms: Double)]
        /// Finger events from the app's passive touch log: kind (d, u, x) and app seconds.
        var touches: [(kind: Character, at: Double, raw: String)]
    }

    @MainActor private func read(_ app: XCUIApplication) -> Reading {
        let bytes = app.staticTexts["debug.dragscroll.bytes"].label
        let state = app.staticTexts["debug.dragscroll.state"].label
        var parts = bytes.components(separatedBy: "¦")
        let header = parts.isEmpty ? "" : parts.removeFirst()
        var counts: [String: Int] = [:]
        for field in header.split(separator: " ") {
            let kv = field.split(separator: "=", maxSplits: 1)
            if kv.count == 2, let value = Int(kv[1]) { counts[String(kv[0])] = value }
        }
        func number(_ key: String) -> Double? {
            guard let range = state.range(of: key + "=") else { return nil }
            let rest = state[range.upperBound...].prefix { "0123456789.".contains($0) }
            return Double(rest)
        }
        var list: [(Double, Double)] = []
        if let range = state.range(of: "list=") {
            let rest = state[range.upperBound...].prefix { $0 != " " }
            for item in rest.split(separator: ",") {
                let pair = item.split(separator: "/").compactMap { Double($0) }
                if pair.count == 2 { list.append((pair[0], pair[1])) }
            }
        }
        var touches: [(Character, Double, String)] = []
        if let range = state.range(of: "touches=") {
            let rest = state[range.upperBound...].prefix { $0 != " " }
            for item in rest.split(separator: ",") {
                guard let kind = item.first, let at = Double(item.dropFirst().prefix { $0 != "@" }) else { continue }
                touches.append((kind, at, String(item)))
            }
        }
        return Reading(header: header, counts: counts, chunks: parts, state: state, now: number("now") ?? 0,
                       hitches: Int(number("hitches") ?? 0), frames: Int(number("frames") ?? 0), hitchList: list,
                       touches: touches)
    }

    /// One gesture: a reading and screenshot before, the gesture, `settle`
    /// seconds, a reading and screenshot after, all attached.
    @MainActor private func record(_ app: XCUIApplication, _ name: String, settle: TimeInterval, _ gesture: @MainActor () -> Void) {
        let before = read(app)
        screenshot(app, "\(name)-before")
        let started = Date()
        gesture()
        let gestureSeconds = Date().timeIntervalSince(started)
        idle(settle)
        let after = read(app)
        screenshot(app, "\(name)-after")
        report(app, name, [("before", before), ("after (gesture \(String(format: "%.2f", gestureSeconds)) s + settle \(settle) s)", after)], shot: false)
    }

    @MainActor private func report(_ app: XCUIApplication, _ name: String, _ readings: [(String, Reading)], shot: Bool = true) {
        if shot { screenshot(app, "\(name)-end") }
        var text = "gesture: \(name)\nmode: \(mode)\n"
        for (index, (label, reading)) in readings.enumerated() {
            text += "\n[\(label)] app now=\(String(format: "%.3f", reading.now))\n  counts: \(reading.header)\n"
            guard index > 0 else { continue }
            let previous = readings[index - 1].1
            let deltas = ["n", "c", "wu", "wd", "au", "ad", "click", "mv", "other"].map { key in
                "\(key)+\((reading.counts[key] ?? 0) - (previous.counts[key] ?? 0))"
            }.joined(separator: " ")
            let top = "top \(previous.counts["top"] ?? 0)->\(reading.counts["top"] ?? 0)"
            let chunks = Array(reading.chunks.dropFirst(previous.chunks.count))
            let window = reading.hitchList.filter { $0.at > previous.now && $0.at <= reading.now }
            let line = "\(name) [\(readings[index - 1].0) -> \(label)]: \(deltas) \(top) | frames+\(reading.frames - previous.frames) hitches+\(reading.hitches - previous.hitches) worst=\(String(format: "%.1f", window.map(\.ms).max() ?? 0)) ms"
            summary.append(line)
            text += "  delta: \(deltas) \(top)\n"
            text += "  pacing: frames+\(reading.frames - previous.frames) hitches+\(reading.hitches - previous.hitches)"
                + " hitches in window: " + (window.isEmpty ? "none" : window.map { String(format: "%.3f s %.1f ms", $0.at, $0.ms) }.joined(separator: ", ")) + "\n"
            // The fingers in this window, and the frames from the first touch to
            // the last touch or byte (the gesture and its fling, not the
            // test's screenshots and reads around it).
            let touches = reading.touches.filter { $0.at > previous.now && $0.at <= reading.now }
            let chunkTimes = chunks.compactMap { Double($0.prefix { $0 != ":" }) }
            text += "  touches: " + (touches.isEmpty ? "none" : touches.map(\.raw).joined(separator: ", ")) + "\n"
            if let first = touches.first?.at {
                let last = max(touches.last?.at ?? first, chunkTimes.max() ?? first)
                let during = reading.hitchList.filter { $0.at >= first && $0.at <= last + 0.05 }
                text += String(format: "  in-gesture span %.3f-%.3f s (%.0f ms): hitches %d", first, last, (last - first) * 1000, during.count)
                    + (during.isEmpty ? "" : ": " + during.map { String(format: "%.3f s %.1f ms", $0.at, $0.ms) }.joined(separator: ", ")) + "\n"
                summary.append("  \(name) in-gesture: \(String(format: "%.0f", (last - first) * 1000)) ms, hitches \(during.count), worst \(String(format: "%.1f", during.map(\.ms).max() ?? 0)) ms")
            }
            // Each finger down: how long after the last scroll byte the phone sent.
            let all = reading.chunks.compactMap { chunk -> Double? in
                let scroll = ["<64;", "<65;", "\\e[A", "\\e[B", "\\eOA", "\\eOB"].contains { chunk.contains($0) }
                return scroll ? Double(chunk.prefix { $0 != ":" }) : nil
            }
            for down in touches where down.kind == "d" {
                if let wheel = all.last(where: { $0 < down.at }) {
                    let line = String(format: "  touch down at %.3f s: %.0f ms after the last scroll byte (%.3f s)", down.at, (down.at - wheel) * 1000, wheel)
                    text += line + "\n"
                    summary.append("  \(name)" + line)
                }
            }
            text += "  bytes the phone sent (\(chunks.count) writes, app-seconds:escaped bytes):\n"
            text += chunks.isEmpty ? "    (none)\n" : chunks.map { "    " + $0 }.joined(separator: "\n") + "\n"
        }
        text += "\n[debugState first] \(readings.first?.1.state ?? "-")\n[debugState last] \(readings.last?.1.state ?? "-")\n"
        let attachment = XCTAttachment(string: text)
        attachment.name = "\(name).txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Quiescence

    /// XCUITest waits for the app to go idle before each event, so a tap
    /// would land only after a fling ends. This suite needs the tap mid-fling.
    nonisolated(unsafe) private static var quiescenceSkipped = false
    private static func skipQuiescence() {
        guard !quiescenceSkipped, let process = NSClassFromString("XCUIApplicationProcess") else { return }
        quiescenceSkipped = true
        if let method = class_getInstanceMethod(process, NSSelectorFromString("waitForQuiescenceIncludingAnimationsIdle:")) {
            let none: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
            method_setImplementation(method, imp_implementationWithBlock(none))
        }
        if let method = class_getInstanceMethod(process, NSSelectorFromString("waitForQuiescenceIncludingAnimationsIdle:isPreEvent:")) {
            let none: @convention(block) (AnyObject, Bool, Bool) -> Void = { _, _, _ in }
            method_setImplementation(method, imp_implementationWithBlock(none))
        }
    }
}
