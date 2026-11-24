// PROOF ONLY — Apps/Proof never ships. The N-1 success criteria of plan §10.5, one check each, that a nearby cell
// record (`OV-NEAR-<pair>-<NN>@<role>`, per design) must show. §10.8 gives no sub-check IDs; these are the proof's
// (docs/DECISIONS.md D-54). Two informational checks are recorded but do not decide the cell.

enum ProofCellCheck: String, Codable, CaseIterable, Sendable {
    case peerIdentification = "peer-identification"
    case unenrolledRefused = "unenrolled-identity-refused"
    case exporterBoundHello = "exporter-bound-hello"
    case wrongBindingRefused = "wrong-binding-refused"
    case reconnectAfterKill = "reconnect-after-kill"
    case reconnectAfterWiFiToggle = "reconnect-after-wifi-toggle"
    case deduplication
    case framesTimed = "100-frames-timed"
    case tlsVersionAndSuite = "tls-version-and-suite-recorded"
    case forwardSecretSuite = "forward-secret-ecdhe-psk-suite"
    case permissionPrompt = "local-network-prompt-recorded"
    case permissionDenial = "local-network-denial-recorded"
    case framesWithinBudget = "frames-within-1-mib-budget"
    case rejoinWithoutSecret = "rejoin-without-discovery-secret"

    /// The checks that decide a cell; Design A adds the forward-secret suite on every session.
    static func required(for design: ProofDesign) -> [ProofCellCheck] {
        var checks: [ProofCellCheck] = [
            .peerIdentification, .unenrolledRefused, .exporterBoundHello, .wrongBindingRefused, .reconnectAfterKill,
            .reconnectAfterWiFiToggle, .deduplication, .framesTimed, .tlsVersionAndSuite, .permissionPrompt,
            .permissionDenial,
        ]
        if design == .a { checks.append(.forwardSecretSuite) }
        return checks
    }

    /// Permission checks belong to the device and installation, not to one cell; their evidence is recorded once
    /// under this key and copied into every cell record of the device.
    var isDeviceLevel: Bool { self == .permissionPrompt || self == .permissionDenial }
    static let deviceLevelCaseKey = "device-local-network"
}
