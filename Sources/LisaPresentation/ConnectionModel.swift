// The connection screen: the host address, pairing with a one-time code, the pairing state without the credential,
// unpairing, and removal by the host.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// Connection and device credentials (UI-02, plan §6.3, NOTIFY-07).
///
/// - The host address is checked as a `HostEndpoint` (https, or http only to a loopback host) before the app's
///   transport is pointed at it.
/// - Pairing presents the one-time code shown on the host with this installation's ID, the device class, the app's
///   bundle ID and its APNs environment. The credential the host returns goes straight to the credential store; the
///   model never holds or shows it, and the code is cleared once it was used.
/// - Unpairing asks the host to revoke this device, then clears the cached data and delivered notifications. When the
///   host is gone for good, `forgetPairing` drops the pairing on this device only. Queued actions are kept unless the
///   owner discards them.
/// - When the host rejects the credential (401) the device was removed: `state` is `.revoked` until it pairs again.
@MainActor
@Observable
public final class ConnectionModel {
    /// The host address as the owner types it.
    public var addressText = ""
    /// Why the typed address cannot be used, after the last check.
    public private(set) var addressIssue: String?
    /// The address requests go to.
    public private(set) var endpoint: HostEndpoint?
    /// The one-time pairing code as the owner types it.
    public var pairingCode = ""
    /// This installation's identifier, which the host sees; not a secret.
    public private(set) var installationID: String?
    /// This device as the host shows it, once read; it never contains the credential or the push token.
    public private(set) var device: DeviceDTO?
    /// Whether pairing or unpairing is in progress.
    public private(set) var isWorking = false
    /// The outcome of the latest pairing operation.
    public private(set) var lastOutcome: ActionOutcome?
    private var storedState: PairingState = .unknown

    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let credentials: any CredentialStore
    @ObservationIgnored private let pairingDevice: PairingDevice
    @ObservationIgnored private let endpoints: any HostEndpointConfiguring
    @ObservationIgnored private let connectivity: ConnectivityModel?
    @ObservationIgnored private let cleanup: DeviceDataCleanup

    /// - Parameters:
    ///   - context: the client services; its client pairs and holds the credential through `credentials`.
    ///   - credentials: the credential store the client uses, to forget a pairing locally.
    ///   - device: what this device presents when it pairs.
    ///   - endpoints: points the app's transport at the host address.
    ///   - connectivity: the connectivity hub, which also tells when the host removed this device.
    ///   - notifications: removes delivered notifications when the device is unpaired.
    public init(
        context: ClientContext, credentials: any CredentialStore, device: PairingDevice,
        endpoints: any HostEndpointConfiguring, connectivity: ConnectivityModel? = nil,
        notifications: (any DeliveredNotificationRemoving)? = nil
    ) {
        self.context = context
        self.credentials = credentials
        pairingDevice = device
        self.endpoints = endpoints
        self.connectivity = connectivity
        cleanup = DeviceDataCleanup(cache: context.cache, notifications: notifications)
    }

    /// Whether this device is paired; `.revoked` while the host's removal of it is the latest news.
    public var state: PairingState {
        if connectivity?.status == .revoked { return .revoked }
        return storedState
    }

    /// Reads the configured address and this installation's pairing.
    public func refresh() async {
        endpoint = endpoints.configuredEndpoint
        if addressText.isEmpty, let endpoint { addressText = endpoint.description }
        do throws(ClientError) {
            let installation = try await context.client.installation()
            installationID = installation.installationID
            if installation.isPaired, let deviceID = installation.deviceID {
                if storedState != .revoked { storedState = .paired(deviceID: deviceID) }
            } else {
                storedState = storedState == .revoked ? .revoked : .notPaired
                device = nil
            }
        } catch {
            lastOutcome = .failed(reason: error.description)
        }
    }

    // MARK: - Address

    /// Checks the typed address; returns it as an endpoint, or `nil` with `addressIssue` saying why.
    @discardableResult
    public func validateAddress() -> HostEndpoint? {
        do throws(HostEndpointError) {
            let parsed = try HostEndpoint(parsing: addressText.trimmingCharacters(in: .whitespacesAndNewlines))
            addressIssue = nil
            return parsed
        } catch {
            addressIssue = error.description
            return nil
        }
    }

    /// Checks the typed address and points the app at it. Returns whether it was saved. A pairing is kept: when the
    /// new address leads to another host, that host rejects the credential and the device must pair there.
    @discardableResult
    public func saveAddress() -> Bool {
        guard let parsed = validateAddress() else { return false }
        do {
            try endpoints.configure(parsed)
        } catch {
            addressIssue = "This address can't be used: \(error)"
            return false
        }
        endpoint = parsed
        addressText = parsed.description
        return true
    }

    // MARK: - Pairing

    /// Pairs with the typed one-time code. Offline pairing is unavailable: it cannot be queued.
    @discardableResult
    public func pair() async -> ActionOutcome {
        guard !isWorking else { return .failed(reason: "pairing is already in progress") }
        let code = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return finish(.failed(reason: "enter the pairing code shown on your Lisa host")) }
        guard code.count <= 64 else { return finish(.failed(reason: "that is not a pairing code")) }
        guard endpoints.configuredEndpoint != nil else {
            return finish(.failed(reason: "enter and save your Lisa host's address first"))
        }
        isWorking = true
        defer { isWorking = false }
        do throws(ClientError) {
            let installation = try await context.client.installation()
            installationID = installation.installationID
            guard !installation.isPaired else {
                return finish(.failed(reason: "this device is already paired; unpair it before pairing again"))
            }
            let paired = try await context.client.pair(
                PairDeviceRequest(
                    code: code, installationID: installation.installationID, name: pairingDevice.name,
                    deviceClass: pairingDevice.deviceClass, appBundleID: pairingDevice.appBundleID,
                    environment: pairingDevice.environment))
            pairingCode = ""
            device = paired
            storedState = .paired(deviceID: paired.id)
            await connectivity?.record(.reached)
            return finish(.done)
        } catch {
            switch HostContact(error) {
            case .unreachable(let reason)?: await connectivity?.record(.unreachable(reason: reason))
            case .incompatible(let version)?: await connectivity?.record(.incompatible(version: version))
            case .some: await connectivity?.record(.notPaired)
            case nil: break
            }
            return finish(Self.pairingOutcome(error))
        }
    }

    /// Reads this device's registration from the host: its name, notification state and token state.
    public func refreshDevice() async {
        guard case .paired(let deviceID) = storedState else { return }
        do throws(ClientError) {
            let devices = try await context.client.devices()
            device = devices.first(where: { $0.isCurrent }) ?? devices.first(where: { $0.id == deviceID })
            await connectivity?.record(.reached)
        } catch {
            if let contact = HostContact(error) { await connectivity?.record(contact) }
            if error.isUnauthenticated {
                storedState = .revoked
                device = nil
            }
        }
    }

    // MARK: - Removal

    /// Asks the host to revoke this device, then clears its cached data and delivered notifications (plan §6.3). When
    /// the host cannot be reached the device stays paired and the outcome is `.unavailable`.
    ///
    /// - Parameter discardingQueuedActions: also removes the queued actions; otherwise they are kept and sent after
    ///   pairing again.
    @discardableResult
    public func unpair(discardingQueuedActions: Bool = false) async -> ActionOutcome {
        guard !isWorking else { return .failed(reason: "pairing is already in progress") }
        isWorking = true
        defer { isWorking = false }
        let installation: ClientInstallation
        do throws(ClientError) {
            installation = try await context.client.installation()
        } catch {
            return finish(.failed(reason: error.description))
        }
        if installation.isPaired, let deviceID = installation.deviceID {
            do throws(ClientError) {
                try await context.client.removeDevice(id: deviceID)
            } catch {
                guard error.isUnauthenticated || error.status == 404 else {
                    if let contact = HostContact(error) { await connectivity?.record(contact) }
                    if case .unavailable = ActionOutcome(unqueuedFailure: error) {
                        return finish(
                            .unavailable(
                                reason: "your Lisa host can't be reached, so this device stays paired; try again when "
                                    + "connected, or remove the device on the host and choose Forget"))
                    }
                    return finish(ActionOutcome(unqueuedFailure: error))
                }
                // The host no longer knows this device: drop the pairing here as well.
                do {
                    try forgetLocally()
                } catch {
                    return finish(.failed(reason: "the pairing could not be removed from this device"))
                }
            }
        }
        await completeRemoval(discardingQueuedActions: discardingQueuedActions)
        return finish(.done)
    }

    /// Drops the pairing on this device only, for a host that is gone; then clears the cached data and delivered
    /// notifications. The host still lists the device until the owner removes it there.
    @discardableResult
    public func forgetPairing(discardingQueuedActions: Bool = false) async -> ActionOutcome {
        guard !isWorking else { return .failed(reason: "pairing is already in progress") }
        do {
            try forgetLocally()
        } catch {
            return finish(.failed(reason: "the pairing could not be removed from this device"))
        }
        await completeRemoval(discardingQueuedActions: discardingQueuedActions)
        return finish(.done)
    }

    // MARK: - Internals

    private func finish(_ outcome: ActionOutcome) -> ActionOutcome {
        lastOutcome = outcome
        return outcome
    }

    /// Replaces the stored identity with the same installation without its device ID and credential.
    private func forgetLocally() throws {
        guard let identity = try credentials.load() else { return }
        try credentials.save(identity.unpaired())
    }

    private func completeRemoval(discardingQueuedActions: Bool) async {
        await cleanup.run()
        if discardingQueuedActions {
            for entry in await context.queue.allEntries {
                try? await context.queue.discard(entry.id)
            }
        }
        device = nil
        storedState = .notPaired
        await connectivity?.record(.notPaired)
        await connectivity?.refreshCachedData()
    }

    /// The outcome of a failed pairing request.
    private static func pairingOutcome(_ error: ClientError) -> ActionOutcome {
        if error.isUnauthenticated {
            return .failed(reason: "the pairing code is invalid or has expired; create a new code on your Lisa host")
        }
        if error.status == 429 {
            return .failed(
                reason: "too many pairing attempts; create a new pairing code on your Lisa host and try again")
        }
        if case .credentialStore = error {
            return .failed(
                reason: "the host paired this device, but its credential could not be saved here; remove the extra "
                    + "device on the host, create a new code and pair again")
        }
        return ActionOutcome(unqueuedFailure: error)
    }
}
