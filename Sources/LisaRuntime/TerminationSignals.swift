// Graceful shutdown on SIGINT and SIGTERM: the signal ends the loop after the current cycle.

import Dispatch
import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// Turns termination signals into an async stream.
public enum TerminationSignals {
    /// A stream that yields each SIGINT or SIGTERM received after this call.
    public static func stream() -> AsyncStream<Int32> {
        AsyncStream { continuation in
            let sources = [SIGINT, SIGTERM].map { number -> any DispatchSourceSignal in
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
                source.setEventHandler { continuation.yield(number) }
                source.resume()
                return source
            }
            let holder = SignalSources(sources)
            continuation.onTermination = { _ in holder.cancel() }
        }
    }
}

/// Keeps the dispatch sources alive for the stream's lifetime.
final class SignalSources: @unchecked Sendable {
    private let sources: [any DispatchSourceSignal]

    init(_ sources: [any DispatchSourceSignal]) {
        self.sources = sources
    }

    func cancel() {
        for source in sources { source.cancel() }
    }
}
