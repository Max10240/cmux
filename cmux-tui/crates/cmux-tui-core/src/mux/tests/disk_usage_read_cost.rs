//! The `server-stats` `disk` section reads the registry; it must not write
//! a copy of the sealed segments to a temporary file.
//!
//! On one Mac (a 10.7 GB registry, 2,816 segments holding 2,012 MiB,
//! 2026-11-13) the daemon wrote 2,438 MiB in the minute of one
//! `server-stats` request that took 33 s. The section summed the segments
//! with `GROUP BY codec`, and SQLite sorts for that: its sorter took every
//! column the sums read, the whole `content` blob included, and spilled
//! them to a temporary file. The sums are kept per daemon, so each daemon
//! start paid it once, and the nightly restarts the daemon several times a
//! day.
//!
//! The test runs a real `Mux` on an on-disk registry with 48 MiB of
//! segments and counts the bytes the process wrote (`proc_pid_rusage`,
//! logical writes; nextest runs each test in a process of its own) during
//! the first read of the section. A count, not a time.

use super::*;

const SEGMENTS: u64 = 48;
const SEGMENT_BYTES: u64 = 1024 * 1024;
/// Bytes the process may write while the section is read: far under the
/// segments' 48 MiB, with room for what an idle daemon writes meanwhile.
const READ_WRITE_BUDGET: u64 = 4 * 1024 * 1024;

/// Bytes this process has written so far, to any file (`ri_logical_writes`
/// of `struct rusage_info_v4`: after the 16-byte uuid, the 28th `uint64_t`).
fn logical_bytes_written() -> u64 {
    let mut info = [0_u64; 64];
    // SAFETY: the buffer is larger than a rusage_info_v4, which flavor 4 writes.
    let read = unsafe {
        libc::proc_pid_rusage(
            i32::try_from(std::process::id()).unwrap(),
            4,
            info.as_mut_ptr().cast::<libc::rusage_info_t>(),
        )
    };
    assert_eq!(read, 0, "proc_pid_rusage failed");
    info[29]
}

#[cfg(target_vendor = "apple")]
#[test]
fn the_disk_section_does_not_copy_the_segments_to_a_temporary_file() {
    let root = std::env::temp_dir()
        .join(format!("cmux-disk-read-cost-{}", crate::workspace_registry::new_uuid_v4()));
    let mux = open_persistent_test_mux("disk-read-cost", &root);
    mux.stop_journal_maintenance();
    {
        let db = mux.registry_connection.get();
        for index in 0..SEGMENTS {
            let start = 1_000_000 + index * 10;
            db.execute(
                "INSERT INTO journal_segments(
                   segment_id, start_sequence, end_sequence, record_count, codec, content,
                   uncompressed_bytes, sha256, sealed_at_ms
                 ) VALUES(?1, ?2, ?3, 10, 'zstd', randomblob(?4), ?5, randomblob(32), 1)",
                rusqlite::params![
                    format!("segment_test_{index}"),
                    i64::try_from(start).unwrap(),
                    i64::try_from(start + 9).unwrap(),
                    i64::try_from(SEGMENT_BYTES).unwrap(),
                    i64::try_from(2 * SEGMENT_BYTES).unwrap(),
                ],
            )
            .unwrap();
        }
        // The rows leave the WAL now, not while the read is measured.
        db.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);").unwrap();
    }

    let before = logical_bytes_written();
    let first = mux.disk_usage_stats().expect("an on-disk registry");
    let first_read_wrote = logical_bytes_written() - before;
    let before = logical_bytes_written();
    let second = mux.disk_usage_stats().expect("an on-disk registry");
    let second_read_wrote = logical_bytes_written() - before;
    println!(
        "disk_usage_read_cost: segments={SEGMENTS} segment_bytes={} \
         first_read_wrote={first_read_wrote} second_read_wrote={second_read_wrote}",
        SEGMENTS * SEGMENT_BYTES
    );
    mux.shutdown();
    let _ = std::fs::remove_dir_all(&root);

    for (name, disk) in [("first", &first), ("second", &second)] {
        let segments = disk.segments.as_ref().unwrap_or_else(|| panic!("{name}: {disk:?}"));
        assert_eq!(segments.segments, SEGMENTS, "{name} read: {segments:?}");
        assert_eq!(segments.records, SEGMENTS * 10, "{name} read: {segments:?}");
        assert_eq!(segments.compressed_bytes, SEGMENTS * SEGMENT_BYTES, "{name} read");
        assert_eq!(segments.uncompressed_bytes, SEGMENTS * 2 * SEGMENT_BYTES, "{name} read");
        assert_eq!(segments.by_codec.len(), 1, "{name} read: {segments:?}");
    }
    assert!(
        first_read_wrote <= READ_WRITE_BUDGET,
        "reading the disk section of a registry with {} bytes of segments wrote \
         {first_read_wrote} bytes (budget {READ_WRITE_BUDGET}): a read must not copy the \
         segments",
        SEGMENTS * SEGMENT_BYTES
    );
}
