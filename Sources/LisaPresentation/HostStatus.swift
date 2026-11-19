// The connection to the host as last observed: unknown, reachable, unreachable, incompatible, not paired, removed.

import Foundation

/// The connection to the host as the app last observed it (NOTIFY-07: cached data and queued actions are outage
/// behavior, so the app shows whether the host can be reached).
public enum HostStatus: Hashable, Sendable {
    /// Nothing has been exchanged with the host yet.
    case unknown
    /// The host answered the latest exchange.
    case reachable
    /// The host could not be reached at the latest exchange; cached data and queued actions apply.
    case unreachable(reason: String)
    /// The host speaks an API version this app does not support.
    case incompatible(version: String)
    /// This device is not paired with a host.
    case notPaired
    /// The host removed this device; its cached data was cleared and it must pair again. This lasts until the host
    /// answers again after pairing.
    case revoked

    /// A sentence for the connectivity screen, without credentials.
    public var message: String {
        switch self {
        case .unknown: "Not checked yet."
        case .reachable: "Connected to your Lisa host."
        case .unreachable(let reason):
            "Your Lisa host can't be reached (\(reason)). Saved data and queued actions apply."
        case .incompatible(let version):
            "Your Lisa host uses API version \(version), which this app does not support."
        case .notPaired: "This device is not paired with a Lisa host."
        case .revoked: "Your Lisa host removed this device. Pair it again."
        }
    }
}
