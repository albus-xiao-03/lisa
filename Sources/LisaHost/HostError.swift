// Why a host could not be opened. Messages are actionable and contain no secrets.

import Foundation

public enum HostError: Error, Hashable, Sendable, CustomStringConvertible {
    /// Live delivery is configured for a channel whose adapter is not available, so nothing could actually be sent.
    case liveDeliveryUnavailable(channel: String, reason: String)
    case storeUnavailable(String)
    /// The network API could not be started: an unusable listener, TLS identity or address.
    case apiUnavailable(String)

    public var description: String {
        switch self {
        case .liveDeliveryUnavailable(let channel, let reason):
            "live \(channel) delivery is configured, but its adapter cannot be used: \(reason); fix it or set the "
                + "\(channel) mode to dryRun"
        case .storeUnavailable(let reason): "the data store could not be opened: \(reason)"
        case .apiUnavailable(let reason): "the network API could not be started: \(reason)"
        }
    }
}
