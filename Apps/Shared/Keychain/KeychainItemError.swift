// A Keychain call that did not succeed, described by its status and the system's message, never by an item's value.

import Foundation
import Security

/// A failed Keychain call. The description names the status code and the system's message for it, which never contain
/// an item's value.
struct KeychainItemError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The status the Security framework returned.
    let status: OSStatus

    var description: String {
        let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "no description"
        return "Keychain status \(status) (\(message))"
    }
}
