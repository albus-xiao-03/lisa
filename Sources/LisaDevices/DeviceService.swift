// Paired-device lifecycle (NOTIFY-02): pairing, credentials, APNs tokens, permission status, preferences.

import Foundation
import LisaCrypto
import LisaDomain
import LisaLogging
import LisaPorts
import LisaTime
import Synchronization

/// Why a device operation was refused.
public enum DeviceError: Error, Hashable, Sendable, CustomStringConvertible {
    case invalidPairingCode
    case pairingAttemptsExceeded
    case unknownDevice
    case revoked
    case topicNotAllowed(String)
    case environmentNotAllowed(String)
    case invalidToken

    public var description: String {
        switch self {
        case .invalidPairingCode: "the pairing code is invalid or expired"
        case .pairingAttemptsExceeded: "too many pairing attempts; create a new pairing code"
        case .unknownDevice: "the device is not paired"
        case .revoked: "the device was removed"
        case .topicNotAllowed(let topic): "the app identifier \(topic) is not configured for notifications"
        case .environmentNotAllowed(let environment): "the APNs environment \(environment) is not enabled"
        case .invalidToken: "the push token is not a valid hexadecimal device token"
        }
    }
}

/// A one-time pairing code shown on the host.
public struct PairingCode: Hashable, Sendable {
    public var code: String
    public var expiresAt: Date
}

/// The credential issued once to a newly paired device.
public struct IssuedCredential: Sendable {
    public var registration: DeviceRegistration
    /// Shown to the device once; the host keeps only its SHA-256 verifier.
    public var credential: String
}

/// What the host accepts for push registrations.
public struct PushRegistrationPolicy: Hashable, Sendable {
    /// App identifiers (APNs topics) the host sends to.
    public var allowedTopics: Set<String>
    public var allowedEnvironments: Set<APNsEnvironment>

    public init(allowedTopics: Set<String>, allowedEnvironments: Set<APNsEnvironment>) {
        self.allowedTopics = allowedTopics
        self.allowedEnvironments = allowedEnvironments
    }
}

/// The device registry. Pairing codes live only in memory: they are short-lived, single-use and die with the host.
public final class DeviceService: DeviceTokenFeedback {
    private struct PendingCode {
        var verifier: String
        var expiresAt: Date
        var attempts: Int
    }

    private let store: any RecordStore
    private let clock: any WallClock
    private let logger: Logger
    private let codes = Mutex<[PendingCode]>([])
    /// How long a pairing code stays valid.
    public let codeLifetime: TimeInterval = 600
    /// Failed attempts allowed per code before it is discarded.
    public let maxAttempts = 5

    public init(store: any RecordStore, clock: any WallClock, logger: Logger) {
        self.store = store
        self.clock = clock
        self.logger = logger
    }

    /// Creates a one-time pairing code. Only the local owner may call this (enforced by the application facade).
    public func createPairingCode() -> PairingCode {
        let code = RandomTokens.code(length: 8)
        let now = clock.now()
        codes.withLock { pending in
            pending.removeAll { $0.expiresAt <= now }
            pending.append(
                PendingCode(
                    verifier: Digests.sha256Hex(code), expiresAt: now.addingTimeInterval(codeLifetime), attempts: 0))
        }
        return PairingCode(code: code, expiresAt: now.addingTimeInterval(codeLifetime))
    }

    /// Pairs a device with a pairing code and issues its credential. The code is consumed.
    public func pair(
        code: String, installationID: String, name: String, deviceClass: DeviceClass, appBundleID: String,
        environment: APNsEnvironment
    ) throws -> IssuedCredential {
        let now = clock.now()
        let normalized = code.uppercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(
            of: " ", with: "")
        let verifier = Data(Digests.sha256Hex(normalized).utf8)
        let matched: Bool = try codes.withLock { pending in
            pending.removeAll { $0.expiresAt <= now }
            if let index = pending.firstIndex(where: { Digests.constantTimeEquals(Data($0.verifier.utf8), verifier) }) {
                pending.remove(at: index)
                return true
            }
            for index in pending.indices { pending[index].attempts += 1 }
            let exhausted = pending.contains { $0.attempts >= maxAttempts }
            pending.removeAll { $0.attempts >= maxAttempts }
            if exhausted { throw DeviceError.pairingAttemptsExceeded }
            return false
        }
        guard matched else { throw DeviceError.invalidPairingCode }
        let credential = RandomTokens.credential()
        let credentialVerifier = Digests.sha256Hex(credential)
        let registration = try store.write { tx -> DeviceRegistration in
            if var existing = try tx.first(
                DeviceRegistration.self, RecordQuery.all.filter("installation_id", equals: installationID))
            {
                existing.credentialVerifier = credentialVerifier
                existing.state = .active
                existing.revokedAt = nil
                existing.name = name
                existing.environment = environment
                existing.updatedAt = now
                let saved = try tx.update(existing)
                try tx.insert(
                    AuditEvent(
                        action: "device.repaired", actor: .localOwner, at: now, affected: [saved.id.rawValue],
                        outcome: .succeeded, detail: deviceClass.rawValue))
                return saved
            }
            let registration = DeviceRegistration(
                installationID: installationID, name: String(name.prefix(80)), deviceClass: deviceClass,
                appBundleID: appBundleID,
                environment: environment, transport: .apns, credentialVerifier: credentialVerifier, now: now)
            try tx.insert(registration)
            try tx.insert(
                AuditEvent(
                    action: "device.paired", actor: .localOwner, at: now, affected: [registration.id.rawValue],
                    outcome: .succeeded, detail: deviceClass.rawValue))
            return registration
        }
        logger.notice(
            "device paired", ["device": .public(registration.id.rawValue), "class": .public(deviceClass.rawValue)])
        return IssuedCredential(registration: registration, credential: credential)
    }

    /// Registers the Mac app's own installation, which receives local notifications from its embedded host.
    public func registerLocalInstallation(installationID: String, name: String, appBundleID: String) throws
        -> DeviceRegistration
    {
        let now = clock.now()
        return try store.write { tx in
            if let existing = try tx.first(
                DeviceRegistration.self, RecordQuery.all.filter("installation_id", equals: installationID))
            {
                return existing
            }
            var registration = DeviceRegistration(
                installationID: installationID, name: name, deviceClass: .mac, appBundleID: appBundleID,
                environment: .production,
                transport: .local, credentialVerifier: "local:\(installationID)", now: now)
            registration.authorization = .notDetermined
            return try tx.insert(registration)
        }
    }

    /// The active registration for a device credential, or `nil`. Possessing a push token never authenticates.
    public func authenticate(credential: String) throws -> DeviceRegistration? {
        let verifier = Digests.sha256Hex(credential)
        return try store.read { tx in
            guard
                let device = try tx.first(
                    DeviceRegistration.self, RecordQuery.all.filter("credential_verifier", equals: verifier)),
                device.state == .active,
                Digests.constantTimeEquals(Data(device.credentialVerifier.utf8), Data(verifier.utf8))
            else { return nil }
            return device
        }
    }

    /// Binds an APNs device token to an authenticated registration for an allowed topic and environment.
    public func registerPushToken(
        deviceID: DeviceID, token: String, environment: APNsEnvironment, topic: String, policy: PushRegistrationPolicy
    ) throws -> DeviceRegistration {
        // ASCII hexadecimal bytes; Apple says not to assume a token length, so only an upper bound applies.
        let cleaned = token.lowercased().filter { !$0.isWhitespace }
        guard !cleaned.isEmpty, cleaned.count <= 1_024, cleaned.count % 2 == 0,
            cleaned.unicodeScalars.allSatisfy({ (0x30...0x39).contains($0.value) || (0x61...0x66).contains($0.value) })
        else {
            throw DeviceError.invalidToken
        }
        guard policy.allowedTopics.contains(topic) else { throw DeviceError.topicNotAllowed(topic) }
        guard policy.allowedEnvironments.contains(environment) else {
            throw DeviceError.environmentNotAllowed(environment.rawValue)
        }
        let now = clock.now()
        return try store.write { tx in
            var device = try tx.require(DeviceRegistration.self, id: deviceID)
            guard device.state == .active else { throw DeviceError.revoked }
            if device.pushToken?.token.revealed == cleaned, device.pushToken?.state == .active { return device }
            if var previous = device.pushToken {
                previous.state = .replaced
                previous.stateChangedAt = now
                device.tokenHistory = Array(([previous] + device.tokenHistory).prefix(5))
            }
            device.pushToken = PushTokenRecord(
                token: cleaned, environment: environment, topic: topic, registeredAt: now)
            device.environment = environment
            device.updatedAt = now
            let saved = try tx.update(device)
            try tx.insert(
                AuditEvent(
                    action: "device.push-token-registered", actor: .pairedDevice(deviceID), at: now,
                    affected: [deviceID.rawValue], outcome: .succeeded, detail: "environment=\(environment.rawValue)"))
            return saved
        }
    }

    /// Records the notification permission and settings a device reports.
    public func reportNotificationStatus(
        deviceID: DeviceID, authorization: NotificationAuthorization, settings: [String: String]
    ) throws -> DeviceRegistration {
        let now = clock.now()
        return try store.write { tx in
            var device = try tx.require(DeviceRegistration.self, id: deviceID)
            guard device.state == .active else { throw DeviceError.revoked }
            let changed = device.authorization != authorization
            device.authorization = authorization
            device.authorizationReportedAt = now
            device.reportedSettings = settings.filter { $0.key.count <= 40 && $0.value.count <= 40 }
            device.lastSeenAt = now
            device.updatedAt = now
            let saved = try tx.update(device)
            if changed {
                try tx.insert(
                    AuditEvent(
                        action: "device.notification-permission", actor: .pairedDevice(deviceID), at: now,
                        affected: [deviceID.rawValue], outcome: .succeeded, detail: authorization.rawValue))
            }
            return saved
        }
    }

    /// Replaces a device's notification preferences, checking the revision the caller saw.
    public func updatePreferences(
        deviceID: DeviceID, preferences: DeviceNotificationPreferences, expectedRevision: Revision?
    ) throws -> DeviceRegistration {
        let now = clock.now()
        return try store.write { tx in
            var device = try tx.require(DeviceRegistration.self, id: deviceID)
            if let expectedRevision, expectedRevision != device.revision {
                throw StoreError.conflict(
                    collection: DeviceRegistration.collectionName, id: deviceID.rawValue, expected: expectedRevision,
                    actual: device.revision)
            }
            device.preferences = preferences
            device.updatedAt = now
            return try tx.update(device)
        }
    }

    /// Revokes a device: its credential stops working and its token is removed. Pending deliveries are cancelled by
    /// the application facade.
    public func revoke(deviceID: DeviceID, by principal: Principal) throws -> DeviceRegistration {
        let now = clock.now()
        return try store.write { tx in
            var device = try tx.require(DeviceRegistration.self, id: deviceID)
            device.state = .revoked
            device.revokedAt = now
            device.pushToken = nil
            device.credentialVerifier = "revoked:\(device.id.rawValue):\(now.millisecondsSince1970)"
            device.updatedAt = now
            let saved = try tx.update(device)
            try tx.insert(
                AuditEvent(
                    action: "device.revoked", actor: principal, at: now, affected: [deviceID.rawValue],
                    outcome: .succeeded, detail: ""))
            return saved
        }
    }

    /// Applies provider feedback about a token. An "unregistered" report counts only when the provider's timestamp is
    /// newer than the token's registration, so a fresh re-registration is never undone by a stale report.
    public func tokenRejected(deviceID: DeviceID, token: String, providerTimestamp: Date?, permanentlyInvalid: Bool)
        throws
    {
        let now = clock.now()
        try store.write { tx in
            guard var device = try tx.get(DeviceRegistration.self, id: deviceID), var current = device.pushToken,
                current.token.revealed == token, current.state == .active
            else { return }
            if !permanentlyInvalid, let providerTimestamp, providerTimestamp <= current.registeredAt { return }
            current.state = permanentlyInvalid ? .invalid : .unregistered
            current.stateChangedAt = now
            device.pushToken = current
            device.updatedAt = now
            try tx.update(device)
            try tx.insert(
                AuditEvent(
                    action: "device.push-token-deactivated", actor: .runtime, at: now, affected: [deviceID.rawValue],
                    outcome: .succeeded, detail: current.state.rawValue))
        }
        logger.notice("push token deactivated", ["device": .public(deviceID.rawValue)])
    }
}
