// The reader monitor (plan §8.15.2). The live WAL grows while any reader holds an old snapshot, so every long reader
// belongs to Lisa and runs on a read-only connection registered here with its purpose and start time. While readers
// are active the monitor samples free space and the WAL size, and acts when free space falls below the reserve plus
// twice the WAL size (releasing every reader) or a reader has been open longer than its budget (releasing that one):
// it interrupts the reader, waits for its read transaction to end, and runs a truncating checkpoint on the writer
// (D-55). A released reader returns its error only after that checkpoint, so a retry can't pin the WAL again before
// it is truncated; its owner retries later. The sample only decides when to release readers; it never decides whether
// a save succeeded.

import Foundation

/// Registers, samples and releases long readers of one WAL database.
public final class SQLiteReaderMonitor: @unchecked Sendable {
    private struct Reader {
        let connection: SQLiteDatabase
        let purpose: SQLiteReaderPurpose
        let started: ContinuousClock.Instant
        /// Signaled once the monitor has checkpointed and recorded this reader's release.
        let handled: DispatchSemaphore
        var released = false
    }

    /// The capture reserve the monitor protects.
    public let reserveBytes: Int64
    private let database: SQLiteWALDatabase
    private let freeSpace: @Sendable () -> Int64?
    private let clock = ContinuousClock()
    private let lock = NSLock()
    private var readers: [Int: Reader] = [:]
    private var nextToken = 0
    private var recorded: [SQLiteReaderRelease] = []
    private var running = false

    /// - Parameter freeSpace: the available bytes, read fresh at each sample; by default `statvfs` on the database's
    ///   file system.
    public init(database: SQLiteWALDatabase, reserveBytes: Int64, freeSpace: (@Sendable () -> Int64?)? = nil) {
        self.database = database
        self.reserveBytes = reserveBytes
        let path = database.path
        self.freeSpace = freeSpace ?? { SQLiteFreeSpace.availableBytes(at: path) }
    }

    /// The live WAL's size in bytes; 0 when there is none.
    public var walBytes: Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: database.path + "-wal"))?[.size] as? NSNumber)?
            .int64Value ?? 0
    }

    /// Readers registered now.
    public var activeReaders: Int { lock.withLock { readers.count } }

    /// Every release so far, oldest first.
    public var releases: [SQLiteReaderRelease] { lock.withLock { recorded } }

    /// Runs `body` in a read transaction on a new read-only connection registered under `purpose`. When the monitor
    /// releases it, the running statement fails with `SQLITE_INTERRUPT` (`SQLiteError.isInterrupted`), the read
    /// transaction ends, and the error is returned once the monitor has run its truncating checkpoint (at most 5 s
    /// later); the caller retries later.
    public func withReader<T>(_ purpose: SQLiteReaderPurpose, _ body: (SQLiteSession) throws -> T) throws -> T {
        let connection = try database.openReader()
        let handled = DispatchSemaphore(value: 0)
        let token = lock.withLock { () -> Int in
            nextToken += 1
            readers[nextToken] = Reader(connection: connection, purpose: purpose, started: clock.now, handled: handled)
            return nextToken
        }
        defer {
            let released = lock.withLock { readers.removeValue(forKey: token)?.released ?? false }
            if released { _ = handled.wait(timeout: .now() + 5) }
        }
        return try connection.readTransaction(body)
    }

    /// One sample: releases every reader when space is low, otherwise each reader over its budget, then runs a
    /// truncating checkpoint. Returns the releases.
    @discardableResult
    public func sample() -> [SQLiteReaderRelease] {
        let now = clock.now
        let wal = walBytes
        let available = freeSpace()
        var releases: [SQLiteReaderRelease] = []
        var pending: [Int: SQLiteDatabase] = [:]
        var waiting: [DispatchSemaphore] = []
        lock.withLock {
            let lowSpace = available.map { $0 < reserveBytes + 2 * wal } ?? false
            for (token, reader) in readers where !reader.released {
                let openFor = now - reader.started
                let reason: SQLiteReaderRelease.Reason
                if lowSpace, let available {
                    reason = .lowSpace(availableBytes: available, walBytes: wal)
                } else if openFor > reader.purpose.budget {
                    reason = .overBudget
                } else {
                    continue
                }
                readers[token]?.released = true
                pending[token] = reader.connection
                waiting.append(reader.handled)
                releases.append(
                    SQLiteReaderRelease(purpose: reader.purpose, reason: reason, openFor: openFor, checkpoint: nil))
            }
        }
        guard !releases.isEmpty else { return [] }
        // An interrupt between two statements is a no-op, so it is repeated until each read transaction has ended.
        let deadline = clock.now + .seconds(2)
        while !pending.isEmpty, clock.now < deadline {
            for connection in pending.values { connection.interrupt() }
            Thread.sleep(forTimeInterval: 0.005)
            pending = lock.withLock { pending.filter { readers[$0.key] != nil } }
        }
        pending = [:]
        let checkpoint = try? database.checkpoint(.truncate)
        releases = releases.map {
            SQLiteReaderRelease(purpose: $0.purpose, reason: $0.reason, openFor: $0.openFor, checkpoint: checkpoint)
        }
        lock.withLock { recorded.append(contentsOf: releases) }
        for semaphore in waiting { semaphore.signal() }
        return releases
    }

    /// Samples every `interval` while readers are active, on its own thread, until `stop()` or until the monitor is
    /// released; the thread never keeps the monitor or its database alive.
    public func start(interval: Duration = .seconds(1)) {
        let begin = lock.withLock { () -> Bool in
            guard !running else { return false }
            running = true
            return true
        }
        guard begin else { return }
        let seconds = Double(interval.components.seconds) + Double(interval.components.attoseconds) / 1e18
        let thread = Thread { [weak self] in
            while true {
                Thread.sleep(forTimeInterval: seconds)
                guard let monitor = self, monitor.isRunning else { return }
                if monitor.activeReaders > 0 { monitor.sample() }
            }
        }
        thread.name = "lisa-reader-monitor"
        thread.start()
    }

    /// Stops sampling after the current interval.
    public func stop() {
        lock.withLock { running = false }
    }

    private var isRunning: Bool { lock.withLock { running } }
}
