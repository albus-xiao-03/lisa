// Whether this device is paired with a host, as the connection screen shows it; never the credential itself.

import Foundation

/// Whether this device is paired with a Lisa host (plan §6.3). It never carries the device credential.
public enum PairingState: Hashable, Sendable {
    /// Not read yet.
    case unknown
    /// No pairing is stored.
    case notPaired
    /// Paired as the host's device `deviceID`.
    case paired(deviceID: String)
    /// The host removed this device: its credential was rejected, its cached data cleared. It must pair again.
    case revoked

    /// Whether a pairing is stored and was not rejected.
    public var isPaired: Bool {
        if case .paired = self { return true }
        return false
    }
}
