// A client's pairing identity and where it is kept: Keychain on Apple devices, an owner-only file for the CLI.

import Foundation

/// The identity a paired client presents. The credential is a secret and is never described, reflected or logged.
public struct ClientIdentity: Codable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    /// A random identifier created once per installation.
    public var installationID: String
    /// The host's identifier for this device, once paired.
    public var deviceID: String?
    /// The device credential the host issued at pairing. It is a secret.
    public var credential: String?

    /// An identity; the device ID and credential are known once the installation is paired.
    public init(installationID: String, deviceID: String? = nil, credential: String? = nil) {
        self.installationID = installationID
        self.deviceID = deviceID
        self.credential = credential
    }

    /// A new, unpaired identity with a random installation identifier (a lowercase UUID).
    public static func newInstallation() -> ClientIdentity {
        ClientIdentity(installationID: UUID().uuidString.lowercased())
    }

    /// Whether the installation holds a device ID and a credential.
    public var isPaired: Bool { deviceID != nil && credential != nil }

    /// This installation without its pairing: the device identifier and the credential are dropped, and the
    /// installation identifier is kept so the device can pair again as the same installation.
    public func unpaired() -> ClientIdentity {
        ClientIdentity(installationID: installationID)
    }

    public var description: String {
        let device = deviceID ?? "unpaired"
        let secret = credential == nil ? "none" : "<redacted>"
        return "ClientIdentity(installation: \(installationID), device: \(device), credential: \(secret))"
    }

    public var debugDescription: String { description }

    /// Reflection, as used by `dump` and debuggers, shows the credential redacted.
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "installationID": installationID, "deviceID": deviceID ?? "unpaired",
                "credential": credential == nil ? "none" : "<redacted>",
            ],
            displayStyle: .struct)
    }
}

/// What a client may show about its installation and pairing. It never carries the credential.
public struct ClientInstallation: Hashable, Sendable {
    /// The installation's random identifier.
    public var installationID: String
    /// The host's identifier for this device, once paired.
    public var deviceID: String?
    /// Whether a device credential is stored.
    public var isPaired: Bool

    /// The installation view of `identity`, without its credential.
    public init(_ identity: ClientIdentity) {
        installationID = identity.installationID
        deviceID = identity.deviceID
        isPaired = identity.isPaired
    }
}

/// Stores the client identity. Apple apps implement this with Keychain (an accessibility class available after first
/// unlock); the CLI uses `FileCredentialStore`.
public protocol CredentialStore: Sendable {
    /// The stored identity, or `nil` when none is stored.
    func load() throws -> ClientIdentity?
    /// Replaces the stored identity.
    func save(_ identity: ClientIdentity) throws
    /// Removes the stored identity, including the installation identifier.
    func clear() throws
}
