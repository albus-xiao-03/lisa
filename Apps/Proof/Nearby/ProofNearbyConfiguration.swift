// PROOF ONLY — Apps/Proof never ships. The owner's choices for one nearby proof run; every field is non-secret and
// recorded (as allowlisted configuration) in each result it affects.

enum ProofDesign: String, Codable, Sendable, CaseIterable {
    case a = "A"
    case b = "B"
}

/// The pair-session role from `lisa-verify pair-session` (plan §10.8): the sender drives the timed exchange, the
/// receiver echoes.
enum ProofHarnessRole: String, Codable, Sendable, CaseIterable {
    case sender
    case receiver
}

/// What the owner is about to do to the link, so the next re-authentication is attributed to it (N-1).
enum ProofReconnectTrigger: String, Codable, Sendable, CaseIterable {
    case none
    case kill
    case wifiToggle = "wifi-toggle"
}

struct ProofNearbyConfiguration: Codable, Sendable, Equatable {
    var design: ProofDesign = .a
    var suitePolicy: DesignAPSKSuites.Policy = .forwardSecretOnly
    /// Design A: act as a device whose discovery secret is too old (no tag; rejoin identities only).
    var rejoin = false
    var fault: ProofFaultInjection = .none
    var harnessRole: ProofHarnessRole = .sender
    /// Echo payload of the 100 timed frames (TN3213 suggests chunks of at least 64 KiB).
    var framePayloadBytes = 65_536
    /// Design A: install the listener-side PSK selection probe.
    var probeSelectionBlock = false
    var nextReconnectTrigger: ProofReconnectTrigger = .none

    /// The allowlisted configuration fields of a result (plan §10.8 "non-secret configuration").
    var allowlisted: [String: String] {
        [
            "design": design.rawValue, "suitePolicy": suitePolicy.rawValue, "rejoin": String(rejoin),
            "fault": fault.rawValue, "harnessRole": harnessRole.rawValue,
            "framePayloadBytes": String(framePayloadBytes), "probeSelectionBlock": String(probeSelectionBlock),
        ]
    }
}
