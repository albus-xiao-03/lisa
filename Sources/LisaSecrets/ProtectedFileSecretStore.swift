// Resolves file:/path references, refusing files that other users could read or that the owner does not own.

import Foundation
import LisaRedaction

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// Reads secrets from files that only the current user can read (mode 0600 or 0400, owned by the user).
public struct ProtectedFileSecretStore: SecretStore {
    public init() {}

    public func secret(for reference: SecretReference) throws -> Sensitive<String> {
        guard case .file(let path) = reference else {
            throw SecretStoreError.unsupported(reference.description)
        }
        var info = stat()
        guard stat(path, &info) == 0 else { throw SecretStoreError.notFound(reference.description) }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw SecretStoreError.unreadable(reference.description) }
        guard info.st_uid == geteuid(), (info.st_mode & 0o077) == 0 else {
            throw SecretStoreError.unprotectedFile(reference.description)
        }
        guard info.st_size <= 65_536 else { throw SecretStoreError.tooLarge(reference.description) }
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8)
        else { throw SecretStoreError.unreadable(reference.description) }
        let value = text.hasSuffix("\n") ? String(text.dropLast()) : text
        guard !value.isEmpty else { throw SecretStoreError.notFound(reference.description) }
        return Sensitive(value)
    }
}
