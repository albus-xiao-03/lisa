// The `lisa` exit codes (CLI-01): stable numbers scripts can rely on.

import ArgumentParser

/// Exit codes. Usage errors use swift-argument-parser's code 64.
enum LisaExit {
    static let success = ExitCode(0)
    /// The operation failed; the message says why.
    static let failure = ExitCode(1)
    /// The configuration file is missing, unreadable or invalid.
    static let invalidConfiguration = ExitCode(3)
    /// Another Lisa runtime owns the data directory (single-writer rule).
    static let dataDirectoryInUse = ExitCode(4)
    /// Checks ran and at least one failed (`doctor`, `demo`).
    static let checksFailed = ExitCode(5)
    /// The host refused to start, for example live delivery without an adapter.
    static let hostRefused = ExitCode(6)
}
