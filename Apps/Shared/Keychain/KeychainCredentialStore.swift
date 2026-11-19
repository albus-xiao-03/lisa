// The device's pairing identity in Keychain: one generic-password item holding the identity document.

import Foundation
import LisaClient

/// Keeps this installation's identity, including the device credential, in Keychain (SEC-01, API-01, plan §6.3).
///
/// The identity is one item of the service `<bundle identifier>.client-identity`, stored as a versioned JSON document
/// like the command-line client's file. The item is available after first unlock on this device only and never
/// synchronized (`KeychainItemAccess`), so a device restored from a backup or another device must pair again.
/// Failures are `ClientStorageError` values that name the item and the Keychain status, never the credential.
struct KeychainCredentialStore: CredentialStore {
    private static let account = "current"
    private static let format = "lisa-client-identity"
    private static let version = 1
    private static let maxBytes = 65_536

    private let item: KeychainItemAccess

    /// The identity item of the app with `bundleIdentifier`.
    init(bundleIdentifier: String) {
        item = KeychainItemAccess(service: KeychainServiceName.clientIdentity(bundleIdentifier: bundleIdentifier))
    }

    /// The identity item of this app.
    static func forThisApp() throws -> KeychainCredentialStore {
        KeychainCredentialStore(bundleIdentifier: try ThisAppBuild.requiredBundleIdentifier())
    }

    func load() throws -> ClientIdentity? {
        let stored: Data?
        do throws(KeychainItemError) {
            stored = try item.read(account: Self.account)
        } catch {
            throw failure(error)
        }
        guard let stored else { return nil }
        guard stored.count <= Self.maxBytes else {
            throw ClientStorageError.tooLarge(path: label, limit: Self.maxBytes)
        }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: stored), header.format == Self.format else {
            throw ClientStorageError.corrupted(path: label, reason: "not a \(Self.format) item")
        }
        guard header.version == Self.version else {
            throw ClientStorageError.unsupportedVersion(path: label, version: header.version)
        }
        guard let document = try? decoder.decode(Document.self, from: stored) else {
            throw ClientStorageError.corrupted(path: label, reason: "the \(Self.format) document is malformed")
        }
        return document.identity
    }

    func save(_ identity: ClientIdentity) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(Document(format: Self.format, version: Self.version, identity: identity))
        } catch {
            throw ClientStorageError.corrupted(path: label, reason: "the identity could not be encoded")
        }
        do throws(KeychainItemError) {
            try item.write(data, account: Self.account)
        } catch {
            throw failure(error)
        }
    }

    func clear() throws {
        do throws(KeychainItemError) {
            try item.delete(account: Self.account)
        } catch {
            throw failure(error)
        }
    }

    /// How errors name the item: by its service, never by its content.
    private var label: String { "Keychain item \(item.service)" }

    private func failure(_ error: KeychainItemError) -> ClientStorageError {
        .ioFailure(path: label, reason: error.description)
    }

    private struct Header: Decodable {
        var format: String
        var version: Int
    }

    private struct Document: Codable {
        var format: String
        var version: Int
        var identity: ClientIdentity
    }
}
