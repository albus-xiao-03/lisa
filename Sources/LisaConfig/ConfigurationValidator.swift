// Cross-setting rules: live-delivery prerequisites, TLS beyond loopback, Lisa's own identities, model routing, limits.

import LisaDomain

/// Rules that involve more than one setting (CFG-01, CFG-02, API-01, MAIL-01, EMAIL-01, CALL-01, NOTIFY-04, SEC-03).
/// A rule is skipped when one of its settings was already reported, so one mistake produces one issue.
struct ConfigurationValidator {
    let context: DecodingContext

    func validate(_ configuration: LisaConfiguration) {
        validateAPI(configuration.api)
        validateEmailDelivery(configuration)
        validateCallDelivery(configuration)
        validatePushDelivery(configuration)
        validateLisaIdentities(configuration)
        validateModel(configuration.model)
        validateDeliveryLimits(configuration.delivery)
        validateResourceLimits(configuration.limits)
    }

    // MARK: - API (API-01)

    private func validateAPI(_ api: APIConfiguration) {
        let bindAddress = ConfigurationPath("api", "bindAddress")
        let tls = ConfigurationPath("api", "tls")
        guard isClean(bindAddress, tls) else { return }
        if api.tls.mode == .native {
            var missing: [String] = []
            if api.tls.certificateSecret == nil { missing.append("api.tls.certificateSecret") }
            if api.tls.privateKeySecret == nil { missing.append("api.tls.privateKeySecret") }
            if !missing.isEmpty {
                report(
                    tls.appending(key: "mode"), "native TLS needs " + Self.joined(missing),
                    fix: "reference the PEM certificate chain and private key, such as file:/path/to/certificate.pem")
            }
        }
        switch (api.bindScope, api.tls.mode) {
        case (.loopback, _), (_, .native), (.privateNetwork, .reverseProxy):
            return
        case (_, .reverseProxy):
            report(
                bindAddress,
                "must be a loopback or private-network address when tls.mode is reverseProxy, because Lisa then "
                    + "serves plain HTTP that only the proxy may reach",
                fix: "bind to 127.0.0.1 when the proxy runs on this machine, or to the private address it connects to")
        case (_, .none):
            report(
                bindAddress,
                "is reachable from other machines, which requires api.tls.mode native (with certificateSecret and "
                    + "privateKeySecret) or reverseProxy",
                fix: "bind to 127.0.0.1, or configure api.tls")
        }
    }

    // MARK: - Delivery prerequisites (CFG-02, EMAIL-01, CALL-01, NOTIFY-04)

    private func validateEmailDelivery(_ configuration: LisaConfiguration) {
        let delivery = configuration.delivery
        let mode = ConfigurationPath("delivery", "modes", "email")
        let enabled = ConfigurationPath("delivery", "emailEnabled")
        let addresses = ConfigurationPath("delivery", "approvedEmailAddresses")
        guard isClean(mode, enabled, addresses, ConfigurationPath("email")) else { return }
        if delivery.modes.email == .live {
            var missing: [String] = []
            if configuration.email == nil { missing.append("the email section (the SMTP adapter)") }
            if !delivery.emailEnabled { missing.append("delivery.emailEnabled set to true") }
            if delivery.approvedEmailAddresses.isEmpty {
                missing.append("at least one delivery.approvedEmailAddresses entry")
            }
            if !missing.isEmpty {
                report(
                    mode, "live email delivery needs " + Self.joined(missing),
                    fix: "complete these, or set delivery.modes.email back to \"dryRun\"")
            }
        } else if delivery.emailEnabled, delivery.approvedEmailAddresses.isEmpty {
            report(
                enabled, "email is enabled, but delivery.approvedEmailAddresses is empty",
                fix: "add the owner's address, such as owner@example.com, or set emailEnabled to false")
        }
    }

    private func validateCallDelivery(_ configuration: LisaConfiguration) {
        let delivery = configuration.delivery
        let mode = ConfigurationPath("delivery", "modes", "call")
        let enabled = ConfigurationPath("delivery", "callsEnabled")
        let number = ConfigurationPath("delivery", "approvedPhoneNumber")
        guard isClean(mode, enabled, number, ConfigurationPath("calls")) else { return }
        if delivery.modes.call == .live {
            var missing: [String] = []
            if configuration.calls == nil { missing.append("the calls section (the Twilio adapter)") }
            if !delivery.callsEnabled { missing.append("delivery.callsEnabled set to true") }
            if delivery.approvedPhoneNumber == nil { missing.append("delivery.approvedPhoneNumber") }
            if !missing.isEmpty {
                report(
                    mode, "live calls need " + Self.joined(missing),
                    fix: "complete these, or set delivery.modes.call back to \"dryRun\"")
            }
        } else if delivery.callsEnabled, delivery.approvedPhoneNumber == nil {
            report(
                enabled, "calls are enabled, but delivery.approvedPhoneNumber is not set",
                fix: "set the owner's number in E.164 form, such as +15555550100, or set callsEnabled to false")
        }
    }

    private func validatePushDelivery(_ configuration: LisaConfiguration) {
        let mode = ConfigurationPath("delivery", "modes", "push")
        guard configuration.delivery.modes.push == .live, isClean(mode, ConfigurationPath("notifications", "apns"))
        else { return }
        guard let apns = configuration.notifications.apns else {
            report(
                mode,
                "live push delivery needs notifications.apns: the signing key reference, team ID, key ID, at least "
                    + "one topic and at least one environment",
                fix: "configure notifications.apns, or set delivery.modes.push back to \"dryRun\"")
            return
        }
        var missing: [String] = []
        if apns.topics.isEmpty { missing.append("at least one notifications.apns.topics entry") }
        if apns.environments.isEmpty { missing.append("at least one enabled notifications.apns.environments entry") }
        if !missing.isEmpty {
            report(
                mode, "live push delivery needs " + Self.joined(missing),
                fix: "complete notifications.apns, or set delivery.modes.push back to \"dryRun\"")
        }
    }

    // MARK: - Lisa's own identities (MAIL-01, EMAIL-01)

    /// Lisa sends from, and reads, her own mailbox only; the owner's approved addresses are never hers.
    private func validateLisaIdentities(_ configuration: LisaConfiguration) {
        guard isClean(ConfigurationPath("delivery", "approvedEmailAddresses")) else { return }
        let ownerAddresses = Set(configuration.delivery.approvedEmailAddresses)
        guard !ownerAddresses.isEmpty else { return }
        if let email = configuration.email, isClean(ConfigurationPath("email")),
            ownerAddresses.contains(email.fromAddress)
        {
            report(
                ConfigurationPath("email", "fromAddress"),
                "is one of the owner's approved addresses; Lisa must send from her own address",
                fix: "use the address of Lisa's dedicated mailbox, such as lisa@example.com")
        }
        // Source indexes match the file only when every source decoded.
        guard isClean(ConfigurationPath("sources")) else { return }
        let ownMailbox = "Lisa reads only her own dedicated mailbox, never the owner's personal mailbox"
        let fix = "create a separate mailbox for Lisa, and forward or copy messages to it"
        for (index, source) in configuration.sources.enumerated() {
            guard case .mailbox(let mailbox) = source.settings else { continue }
            let base = ConfigurationPath("sources").appending(index: index)
            if ownerAddresses.contains(mailbox.mailboxAddress) {
                report(
                    base.appending(key: "mailboxAddress"), "is one of the owner's approved addresses; \(ownMailbox)",
                    fix: fix)
            }
            if ownerAddresses.contains(mailbox.username.lowercased()) {
                report(
                    base.appending(key: "username"), "is one of the owner's approved addresses; \(ownMailbox)",
                    fix: fix)
            }
        }
    }

    // MARK: - Model routing (MODEL-01, MODEL-04, SEC-03)

    private func validateModel(_ model: ModelConfiguration) {
        let provider = ConfigurationPath("model", "provider")
        let endpoint = ConfigurationPath("model", "endpoint")
        let identifier = ConfigurationPath("model", "modelIdentifier")
        let sharing = ConfigurationPath("model", "dataSharing")
        guard model.provider == .openAICompatible, isClean(provider, endpoint, identifier, sharing) else { return }
        var missing: [String] = []
        if model.endpoint == nil { missing.append("model.endpoint") }
        if model.modelIdentifier == nil { missing.append("model.modelIdentifier") }
        if !missing.isEmpty {
            report(
                provider, "openAICompatible needs " + Self.joined(missing),
                fix: "set them, or keep the provider \"deterministic\"")
        }
        switch model.dataSharing {
        case .none:
            report(
                sharing,
                "none allows only the in-process deterministic provider, so every request to this endpoint would be "
                    + "refused",
                fix: "choose localOnly for an endpoint on this machine or a private network, or remoteMinimized to "
                    + "let minimized content reach a remote endpoint")
        case .localOnly:
            if let scope = model.endpointScope, scope != .loopback, scope != .privateNetwork {
                report(
                    endpoint,
                    "is not an address on this machine or a private network, so localOnly data sharing would refuse "
                        + "every request",
                    fix: "use a loopback or private IP address, or choose remoteMinimized to let minimized content "
                        + "reach this endpoint")
            }
        case .remoteMinimized:
            return
        }
    }

    // MARK: - Limits (OPS-02)

    private func validateDeliveryLimits(_ delivery: DeliveryConfiguration) {
        let base = ConfigurationPath("delivery", "baseBackoffSeconds")
        let maximum = ConfigurationPath("delivery", "maxBackoffSeconds")
        if isClean(base, maximum), delivery.maxBackoffSeconds < delivery.baseBackoffSeconds {
            report(maximum, "must be at least baseBackoffSeconds")
        }
        let perCommitment = ConfigurationPath("delivery", "calls", "maxCallsPerCommitmentPerDay")
        let perDay = ConfigurationPath("delivery", "calls", "maxCallsPerDay")
        if isClean(perCommitment, perDay), delivery.calls.maxCallsPerCommitmentPerDay > delivery.calls.maxCallsPerDay {
            report(perCommitment, "must not be larger than maxCallsPerDay")
        }
    }

    private func validateResourceLimits(_ limits: ResourceLimits) {
        let perEvent = ConfigurationPath("limits", "maxRecurrenceOccurrencesPerEvent")
        let total = ConfigurationPath("limits", "maxTotalOccurrences")
        if isClean(perEvent, total), limits.maxTotalOccurrences < limits.maxRecurrenceOccurrencesPerEvent {
            report(total, "must be at least maxRecurrenceOccurrencesPerEvent")
        }
        let perPass = ConfigurationPath("limits", "maxBytesPerSync")
        let message = ConfigurationPath("limits", "maxMessageBytes")
        let feed = ConfigurationPath("limits", "maxFeedBytes")
        if isClean(perPass, message, feed), limits.maxBytesPerSync < max(limits.maxMessageBytes, limits.maxFeedBytes) {
            report(
                perPass, "must be at least maxMessageBytes and maxFeedBytes",
                fix: "otherwise one item of the largest allowed size could never be synchronized")
        }
    }

    // MARK: - Helpers

    private func isClean(_ paths: ConfigurationPath...) -> Bool {
        !paths.contains { context.hasIssue(affecting: $0) }
    }

    private func report(_ path: ConfigurationPath, _ problem: String, fix: String? = nil) {
        context.report(path, at: context.position(of: path), problem, fix: fix)
    }

    /// "a", "a and b", or "a, b and c".
    private static func joined(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
}
