// The settings and health screen: runtime state, sources, delivery modes and delivery preferences, the model
// configuration, and paired devices with their notification status.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// The Mac app's settings and health screen (UI-01: sources, delivery policy, model configuration, runtime state,
/// paired devices and notification status).
///
/// - Health (`GET /v1/health`) gives the runtime state, the sources, each channel's delivery mode, the model
///   configuration and the devices that cannot receive notifications. It is read when the screen asks; nothing polls
///   the host, and while the host is unreachable the screen keeps what it last read, marked as not current.
/// - `devices` lists the paired devices with their notification state, removes devices and creates pairing codes.
/// - `preferences` holds the delivery preferences (`deliveryPreferences`) and changes them as the memory screen does,
///   with the host's refusals shown per preference. Settings that come only from the host's configuration file are
///   not readable through the API.
@MainActor
@Observable
public final class SettingsHealthModel {
    /// The host's health as last read.
    public private(set) var health: LoadState<HealthDTO> = .idle
    /// The paired devices.
    public let devices: PairedDevicesModel
    /// The preferences, of which the screen shows the delivery group.
    public let preferences: MemoryModel

    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let contacts: (any HostContactReporting)?
    @ObservationIgnored private var generation = 0

    /// - Parameters:
    ///   - context: the client services.
    ///   - contacts: where connectivity is reported.
    ///   - preferences: the preferences model to share with the memory screen; a new one when `nil`.
    public init(
        context: ClientContext, contacts: (any HostContactReporting)? = nil, preferences: MemoryModel? = nil
    ) {
        self.context = context
        self.contacts = contacts
        devices = PairedDevicesModel(context: context, contacts: contacts)
        self.preferences = preferences ?? MemoryModel(context: context, contacts: contacts)
    }

    // MARK: - What the screen shows

    /// The runtime state, once health was read.
    public var runtime: RuntimeStateSummary? { health.value.map(RuntimeStateSummary.init) }

    /// The sources, in name order.
    public var sources: [SourceHealthSummary] { (health.value?.sources ?? []).map(SourceHealthSummary.init) }

    /// The sources that are on and failing or out of date.
    public var sourcesNeedingAttention: [SourceHealthSummary] { sources.filter(\.needsAttention) }

    /// Each channel's delivery mode: live, or a dry run that sends nothing.
    public var deliveryChannels: [DeliveryChannelMode] {
        DeliveryChannelMode.channels(health.value?.deliveryModes ?? [:])
    }

    /// The stored preferences about who Lisa may contact and how (`PreferenceDescriptor.Group.delivery`).
    public var deliveryPreferences: [PreferenceDTO] { preferences.preferences(in: .delivery) }

    /// The model configuration, once health was read; it says so when the host does not report one.
    public var model: ModelConfigurationSummary? { health.value.map { ModelConfigurationSummary($0.model) } }

    /// The host's explanations of paired devices that cannot receive notifications.
    public var notificationWarnings: [String] { health.value?.deviceWarnings ?? [] }

    // MARK: - Reading

    /// Reads health, the paired devices and the preferences.
    public func load() async {
        await refreshHealth()
        await devices.load()
        await preferences.load()
    }

    /// Reads health again. A refresh started later wins over an earlier one still running.
    public func refreshHealth() async {
        generation += 1
        let current = generation
        let previous = health.result
        health = .loading(previous: previous)
        let client = context.client
        let now = context.now
        let next = await ReadRunner.load(previous: previous, contacts: contacts) {
            () async throws(ClientError) -> ReadResult<HealthDTO> in
            ReadResult(value: try await client.health(), fetchedAt: now(), source: .host)
        }
        guard current == generation else { return }
        health = next
    }
}
