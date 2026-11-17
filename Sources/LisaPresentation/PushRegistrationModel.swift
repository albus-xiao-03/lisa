// APNs registration at every launch: the device token the system returns, sent to the host for this paired device,
// with the truthful result.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// Sends this device's APNs token to the host (`PUT /v1/devices/current/push-registration`, NOTIFY-02, plan §6.5).
///
/// The app registers for remote notifications at every launch and passes each token the system returns to
/// `receive(deviceToken:)`, so a token that changed is replaced on the host; the host keeps an identical token as it is.
/// Registration needs a paired device: before pairing the token is kept in memory only, and `registerIfNeeded()`
/// sends it once pairing succeeds or the host can be reached again. It is a direct request, never queued. The token is
/// never shown, described or logged.
@MainActor
@Observable
public final class PushRegistrationModel {
    /// Whether the system returned a token in this process.
    public private(set) var hasToken = false
    /// The outcome of the latest registration attempt.
    public private(set) var lastOutcome: ActionOutcome?
    /// When the host last accepted the token.
    public private(set) var lastRegisteredAt: Date?

    @ObservationIgnored private var token: String?
    @ObservationIgnored private var registeredToken: String?
    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let environment: APNsEnvironmentValue
    @ObservationIgnored private let topic: String
    @ObservationIgnored private let contacts: (any HostContactReporting)?

    /// - Parameters:
    ///   - context: the client services.
    ///   - environment: the APNs environment of this build: development for Debug, production for Release, matching
    ///     the app's entitlements.
    ///   - topic: the app's bundle identifier.
    ///   - contacts: where connectivity is reported.
    public init(
        context: ClientContext, environment: APNsEnvironmentValue, topic: String,
        contacts: (any HostContactReporting)? = nil
    ) {
        self.context = context
        self.environment = environment
        self.topic = topic
        self.contacts = contacts
    }

    /// Keeps the token the system returned at registration and sends it to the host.
    @discardableResult
    public func receive(deviceToken: Data) async -> ActionOutcome {
        guard let hex = PushTokenText.hex(deviceToken) else {
            return finish(.failed(reason: "the system returned a push token Lisa cannot use"))
        }
        if hex != token { registeredToken = nil }
        token = hex
        hasToken = true
        return await register()
    }

    /// Records that the system could not register for remote notifications, for example because the build has no
    /// push entitlement. `reason` is the system's description of the error.
    @discardableResult
    public func registrationFailed(reason: String) -> ActionOutcome {
        finish(.failed(reason: "the system could not register this device for notifications: \(reason)"))
    }

    /// Sends the token when the host has not accepted it in this process yet, for example after pairing or on
    /// reconnecting; `nil` when there is no token or the host already has it.
    @discardableResult
    public func registerIfNeeded() async -> ActionOutcome? {
        guard let token, token != registeredToken else { return nil }
        return await register()
    }

    private func register() async -> ActionOutcome {
        guard let token else { return finish(.unavailable(reason: "the system has not returned a push token yet")) }
        if context.requiresPairing, (try? await context.client.installation())?.isPaired != true {
            return finish(.unavailable(reason: ActionOutcome.notPairedReason))
        }
        do throws(ClientError) {
            _ = try await context.client.registerPush(
                PushRegistrationRequest(token: token, environment: environment, topic: topic))
            registeredToken = token
            lastRegisteredAt = context.now()
            await contacts?.record(.reached)
            return finish(.done)
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            return finish(ActionOutcome(unqueuedFailure: error))
        }
    }

    private func finish(_ outcome: ActionOutcome) -> ActionOutcome {
        lastOutcome = outcome
        return outcome
    }
}
