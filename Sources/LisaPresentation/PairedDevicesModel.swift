// The paired-devices section of the settings screen: each device and its notification state, removing a device, and
// one-time pairing codes with their expiry.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// Paired devices on the Mac app's settings screen (UI-01: paired devices and notification status; plan §6.3).
///
/// - The list comes from the host (`GET /v1/devices`), with each device's notification state (`summaries`). It is not
///   cached: while the host is unreachable the screen keeps what it last read, marked as not current.
/// - Removing a device revokes its credential on the host (`DELETE /v1/devices/{id}`); this device unpairs itself on
///   the connection screen instead, which also clears its data. Removal cannot be queued: offline it is
///   `.unavailable`.
/// - A pairing code (`POST /v1/devices/pairing-codes`) is created only by the owner on the host, which the Mac app is;
///   it is kept in memory with its expiry and shown until it expires or the owner hides it.
@MainActor
@Observable
public final class PairedDevicesModel {
    /// What the section shows.
    public private(set) var state: LoadState<[DeviceDTO]> = .idle
    /// The latest pairing code, until it expires or is hidden.
    public private(set) var pairingCode: PairingCodeDTO?
    /// Whether a pairing code is being created.
    public private(set) var isCreatingCode = false
    /// Devices being removed.
    public private(set) var removingDeviceIDs: Set<String> = []
    /// The outcome of the latest action.
    public private(set) var lastOutcome: ActionOutcome?

    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let contacts: (any HostContactReporting)?
    @ObservationIgnored private var generation = 0

    /// What the section says when no device is paired.
    public static let emptyMessage = "No devices are paired. Create a pairing code to pair your iPhone or iPad."

    /// A model that reads and acts through `context` and reports connectivity to `contacts`.
    public init(context: ClientContext, contacts: (any HostContactReporting)? = nil) {
        self.context = context
        self.contacts = contacts
    }

    /// The devices shown, in pairing order, removed ones included.
    public var devices: [DeviceDTO] { state.value ?? [] }

    /// The devices shown, in plain words.
    public var summaries: [PairedDeviceSummary] { devices.map(PairedDeviceSummary.init) }

    /// The devices shown that are still paired.
    public var activeDevices: [DeviceDTO] { devices.filter { $0.state == "active" } }

    /// Whether the list was read and no device is still paired.
    public var isEmpty: Bool { state.value != nil && activeDevices.isEmpty }

    /// Reads the paired devices; a pairing code that has expired is hidden. A load started later wins.
    public func load() async {
        if let code = pairingCode, code.expiresAt <= context.now() { pairingCode = nil }
        generation += 1
        let current = generation
        let previous = state.result
        state = .loading(previous: previous)
        let client = context.client
        let now = context.now
        let next = await ReadRunner.load(previous: previous, contacts: contacts) {
            () async throws(ClientError) -> ReadResult<[DeviceDTO]> in
            ReadResult(value: try await client.devices(), fetchedAt: now(), source: .host)
        }
        guard current == generation else { return }
        state = next
    }

    /// Removes `device` on the host and revokes its credential, then reads the list again.
    @discardableResult
    public func remove(_ device: DeviceDTO) async -> ActionOutcome {
        guard !device.isCurrent else {
            return refuse("this is the device you are using; unpair it in Connection settings")
        }
        guard device.state == "active" else { return refuse("this device was already removed") }
        removingDeviceIDs.insert(device.id)
        defer { removingDeviceIDs.remove(device.id) }
        let outcome: ActionOutcome
        do throws(ClientError) {
            try await context.client.removeDevice(id: device.id)
            await contacts?.record(.reached)
            outcome = .done
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            hideDataIfRemoved(LoadFailure(error))
            outcome = ActionOutcome(unqueuedFailure: error)
        }
        lastOutcome = outcome
        if outcome.isDone { await load() }
        return outcome
    }

    /// Creates a one-time pairing code for a new device; only the owner on the host may. The code is shown until it
    /// expires (`pairingCodeExpiry(at:)`).
    @discardableResult
    public func createPairingCode() async -> ActionOutcome {
        guard !isCreatingCode else { return refuse("a pairing code is already being created") }
        isCreatingCode = true
        defer { isCreatingCode = false }
        let outcome: ActionOutcome
        do throws(ClientError) {
            pairingCode = try await context.client.createPairingCode()
            await contacts?.record(.reached)
            outcome = .done
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            hideDataIfRemoved(LoadFailure(error))
            outcome =
                error.status == 403
                ? .failed(reason: "pairing codes are created on the Mac that runs your Lisa host")
                : ActionOutcome(unqueuedFailure: error)
        }
        lastOutcome = outcome
        return outcome
    }

    /// Whether the pairing code shown can still be used at `now`.
    public func pairingCodeIsValid(at now: Date) -> Bool {
        pairingCode.map { $0.expiresAt > now } ?? false
    }

    /// When the pairing code shown expires, in words such as "Expires in 9 minutes.", or that it has expired; `nil`
    /// when no code is shown.
    public func pairingCodeExpiry(at now: Date) -> String? {
        guard let pairingCode else { return nil }
        let remaining = pairingCode.expiresAt.timeIntervalSince(now)
        guard remaining > 0 else { return "This code has expired. Create a new one." }
        return "Expires in \(AgePhrase.english(remaining))."
    }

    /// Stops showing the pairing code.
    public func hidePairingCode() {
        pairingCode = nil
    }

    // MARK: - Internals

    /// Reports an action refused before anything was sent.
    private func refuse(_ reason: String) -> ActionOutcome {
        let outcome = ActionOutcome.failed(reason: reason)
        lastOutcome = outcome
        return outcome
    }

    /// Stops showing the devices when this device is not paired or the host removed it.
    private func hideDataIfRemoved(_ failure: LoadFailure) {
        guard failure.hidesData else { return }
        generation += 1
        state = .failed(failure, previous: nil)
        pairingCode = nil
    }
}
