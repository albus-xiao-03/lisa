// PROOF ONLY — Apps/Proof never ships. What the owner copies from `lisa-verify pair-session` (plan §10.8) into
// each device before a cell: the run ID, the case ID, this device's role, the pair and condition, and the session
// nonce shown on both screens; plus the owner's own observations of the local-network prompt, which no API reports.

import Foundation

struct ProofRunContext: Codable, Sendable, Equatable {
    static let defaultsKey = "proof.run-context"

    var runID = ""
    /// The case without role, for example `OV-NEAR-MI-01` or `OV-APPLE-X1-FETCH-03`.
    var caseID = ""
    var role: ProofHarnessRole = .sender
    /// `mac,iphone`, `mac,ipad` or `iphone,ipad`.
    var devices = ""
    /// `shared-wifi`, `no-internet` or `no-access-point`.
    var condition = ""
    var harnessNonce = ""
    /// "shown", "not-shown" or "" (not yet observed).
    var permissionPrompt = ""
    /// "allowed", "denied" or "" (not yet observed).
    var permissionChoice = ""

    /// `run-<UTC time>-<6 base32 characters>`; the harness spells the time `YYYYMMDDTHHMMSSZ` and the six characters in
    /// lowercase RFC 4648 base32 (docs/DECISIONS.md D-54); only the shape and a safe path component are checked here.
    var hasValidRunID: Bool {
        runID.range(of: #"^run-[0-9A-Za-z]+-[A-Za-z2-7]{6}$"#, options: .regularExpression) != nil
    }

    var hasValidCaseID: Bool {
        caseID.range(of: #"^OV-[A-Z0-9]+(-[A-Z0-9]+)*-[0-9]{2}$"#, options: .regularExpression) != nil
    }

    /// `<case>@<role>` for a paired session (plan §10.8).
    var correlatedCaseID: String { caseID + "@" + role.rawValue }

    static func load(_ defaults: UserDefaults = .standard) -> ProofRunContext {
        guard let data = defaults.data(forKey: defaultsKey),
            let context = try? JSONDecoder().decode(ProofRunContext.self, from: data)
        else { return ProofRunContext() }
        return context
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
