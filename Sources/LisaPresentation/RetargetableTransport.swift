// The app's single transport to its Lisa host: it forwards to the host the app is set up for and is re-pointed when
// the owner changes the host's address.

import Foundation
import LisaAPIContract

/// Forwards requests to the transport of the host the app is set up for, such as a `URLSessionTransport` to the
/// owner's address or the Mac app's embedded host (NOTIFY-07: a configurable host endpoint).
///
/// An app keeps one client, one offline queue and one cache for its whole process over this transport, and re-points
/// it when the host changes. A request already sent finishes on the transport it started on. While no host is set,
/// every request is refused before anything is sent (`APITransportError.refused`): queued actions stay pending, and
/// reads report the host as unavailable.
public final class RetargetableTransport: APITransport, @unchecked Sendable {
    /// Why requests are refused while no host is set.
    public static let noHostReason = "no Lisa host is set up on this device"

    // `target` is read and written only while `lock` is held.
    private let lock = NSLock()
    private var target: (any APITransport)?

    /// A transport that forwards to `target`, or refuses every request until a target is set.
    public init(target: (any APITransport)? = nil) {
        self.target = target
    }

    /// Whether requests currently have a host transport to go to.
    public var hasTarget: Bool {
        lock.withLock { target != nil }
    }

    /// Sends later requests through `target`; `nil` refuses them until another target is set.
    public func retarget(to target: (any APITransport)?) {
        lock.withLock { self.target = target }
    }

    public func send(_ request: APIRequest) async throws -> APIResponse {
        guard let current = lock.withLock({ target }) else { throw APITransportError.refused(Self.noHostReason) }
        return try await current.send(request)
    }
}
