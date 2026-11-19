// Keychain service names of Lisa's items, derived from the app's bundle identifier so that each app keeps its own.

import Foundation

/// The Keychain service names of this app's items. Each starts with the app's bundle identifier, so the companion's
/// and the Mac app's items stay apart, and the device identity can never be read as a secret or the other way round.
enum KeychainServiceName {
    /// The service of the device identity item: `<bundle identifier>.client-identity`.
    static func clientIdentity(bundleIdentifier: String) -> String {
        "\(bundleIdentifier).client-identity"
    }

    /// The service of the secret referenced as `keychain:<service>/<account>`:
    /// `<bundle identifier>.secrets.<service>`.
    static func secret(_ service: String, bundleIdentifier: String) -> String {
        "\(bundleIdentifier).secrets.\(service)"
    }
}
