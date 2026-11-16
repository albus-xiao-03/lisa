// Why a host could not be opened. Messages are actionable and contain no secrets.

import Foundation

public enum HostError: Error, Hashable, Sendable, CustomStringConvertible {
    /// Live delivery is configured for a channel whose adapter is not available, so nothing could actually be sent.
    case liveDeliveryUnavailable(channel: String)
    case storeUnavailable(String)

    public var description: String {
        switch self {
        case .liveDeliveryUnavailable(let channel):
            "live \(channel) delivery is configured, but this build has no \(channel) adapter; set the \(channel) mode to dryRun"
        case .storeUnavailable(let reason): "the data store could not be opened: \(reason)"
        }
    }
}
