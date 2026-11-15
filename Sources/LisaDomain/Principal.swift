// Who performs an action: the local owner, a paired device, the runtime, a model suggestion or the demonstration.

/// The actor behind an action, used for authorization and audit records.
public enum Principal: Hashable, Codable, Sendable, CustomStringConvertible {
    /// The owner acting on the host itself: the Mac app in-process or the command line on the host.
    case localOwner
    /// A paired companion device acting with its own credential.
    case pairedDevice(DeviceID)
    /// Lisa's own scheduled processing.
    case runtime
    /// A model suggestion; never authorized to change consequential state by itself.
    case model
    /// The synthetic demonstration scenario.
    case demonstration

    public var description: String {
        switch self {
        case .localOwner: "local-owner"
        case .pairedDevice(let id): "device:\(id.rawValue)"
        case .runtime: "runtime"
        case .model: "model"
        case .demonstration: "demonstration"
        }
    }

    /// Whether the principal may change consequential settings such as recipients, call enablement or model routing.
    public var mayChangeConsequentialSettings: Bool {
        switch self {
        case .localOwner, .demonstration: true
        case .pairedDevice, .runtime, .model: false
        }
    }
}
