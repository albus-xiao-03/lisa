// The owner credential of the loopback owner listener, used by the CLI in client mode: issued when the host starts
// serving, checked by digest in constant time, revoked when serving stops. Only the digest is kept.

import Foundation
import LisaCrypto
import Synchronization

/// Issues and verifies the owner credential of one running host.
public final class OwnerAccess: Sendable {
    private let digest = Mutex<Data?>(nil)

    public init() {}

    /// A new random credential, replacing any earlier one. It is returned only here.
    public func issue() -> String {
        let credential = RandomTokens.credential()
        let issued = Digests.sha256(Data(credential.utf8))
        digest.withLock { $0 = issued }
        return credential
    }

    /// Refuses every owner credential from now on.
    public func revoke() {
        digest.withLock { $0 = nil }
    }

    /// Whether `credential` is the one currently issued.
    public func verify(_ credential: String) -> Bool {
        guard let expected = digest.withLock({ $0 }) else { return false }
        return Digests.constantTimeEquals(Digests.sha256(Data(credential.utf8)), expected)
    }
}
