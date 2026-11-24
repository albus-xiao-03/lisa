// The X1 cases (plan §10.6 X1, §10.5 N-1, E-1 and E-2, §10.9 rows R2-A01, R2-A03, R2-A04 and E-1): the nine nearby
// cells for both designs' proofs, the three portable-module builds and the nine fetch-probe cases. All are the
// owner's, on the owner's devices, with `Apps/Proof` (scheme `LisaProof`) and harness test plan `X1`.

import LisaVerifyKit

/// X1's catalogue.
public enum X1Catalogue {
    static let nearbySteps = [
        "Run `lisa-verify pair-session <case> --devices <pair> --condition <condition>`; it prints the run ID, the "
            + "session nonce and each device's role. Enter them with the case ID, devices and condition in Lisa "
            + "Proof's Results tab on both devices.",
        "Set up the condition on both devices (see the case's environment).",
        "In the Nearby tab choose the design (A, then B in a separate pass) and the harness role printed for the "
            + "device, then press Start on both. Expected: both screens show the same session code and the peer's "
            + "label; the sender then times 100 frames, one 1 MiB frame and 20 clock exchanges; the TLS version and "
            + "suite are recorded (Design A: an ECDHE-PSK suite).",
        "Refusals, one pass each, from each device in turn: choose the fault (wrong exporter binding, unenrolled "
            + "identity, unenrolled operation key, oversize frame header) on the faulting device and start. "
            + "Expected: the peer refuses before any data moves; for the oversize header, before allocating it.",
        "Reconnection: set 'Next reconnection trigger' to kill, force-quit Lisa Proof on one device and reopen it; "
            + "then set it to wifi-toggle and turn Wi-Fi off and on. Expected: a new authenticated session each time.",
        "Deduplication: press Start on both devices within a second. Expected: one session survives (the one opened "
            + "by the lower device ID); the other closes.",
        "Local network permission (Results tab, 'Record prompt observation'): whether the prompt appeared and your "
            + "choice; once per device, deny it in Settings and confirm the proof shows the unavailable state "
            + "without retrying, then allow it again.",
        "Press 'Finish cell: write the result record' on both devices, export results.jsonl and evidence.jsonl from "
            + "the Results tab, and run `lisa-verify import-diagnostics <run-id> <file>` for each file.",
    ]

    /// `OV-NEAR-<pair>-<NN>`: one cell, both designs' proofs, a result per device under `<case>@<role>`.
    public static func nearbyCell(_ pair: NearbyPair, _ condition: NearbyCondition) -> VerifyCase {
        VerifyCase(
            id: try! VerifyCaseID("OV-NEAR-\(pair.rawValue)-\(condition.number)"),
            title: "Nearby proof, \(pair.title), \(condition.rawValue) (N-1, designs A and B)", provider: pair.rawValue,
            interface: "Network framework: Design A TLS 1.2 ECDHE-PSK; Design B TLS 1.3 mutual authentication",
            capability: "Nearby transport security (N-1)", environment: condition.setup, modes: [.device],
            requiredResultLevel: .ownerVerified,
            requiredEvidence: [
                "peer identity", "TLS version and suite", "the session nonce and session code on both devices",
                "refusals with the faulting device named", "reconnection after kill and after the Wi-Fi toggle",
                "deduplication", "100 frames timed by round trips on one device",
                "local-network prompt and denial",
            ],
            executor: .owner,
            prerequisites: [
                "A Mac, iPhone and iPad with Lisa Proof built from the same commit and signed by the owner",
                "Each device's proof card and the shared setup text entered on every device (Roster tab)",
                "Design B: each device's identity provisioned and its updated card re-shared",
            ],
            gate: "N-1 (release requirement): selects the nearby design for M6; Apple clients gate (G3)",
            expectedOutcome:
                "Every check passes on this cell for a design, with an ECDHE-PSK suite on every Design A session; the "
                + "design is selected only if its proof passes on all nine cells",
            manualSteps: nearbySteps, session: "X1", paired: true)
    }

    /// `OV-APPLE-X1-01`–`03`: the portable modules built for macOS, iOS and iPadOS through `LisaProof` (E-2).
    public static func portableBuild(_ number: Int) -> VerifyCase {
        let platform = ["Mac (macOS)", "iPhone (iOS)", "iPad (iPadOS)"][number - 1]
        return VerifyCase(
            id: try! VerifyCaseID("OV-APPLE-X1-0\(number)"),
            title: "Portable modules and swift-crypto build for the \(platform) (E-2)", provider: "X1",
            interface: "Xcode, scheme LisaProof", capability: "Apple SDK module maps and swift-crypto (E-2)",
            environment: "The owner's Mac with Xcode; the \(platform) as the destination", modes: [.device],
            requiredResultLevel: .ownerVerified,
            requiredEvidence: [
                "Xcode version", "scheme", "destination", "build-log digest", "the app's E-2 self-check",
            ],
            executor: .owner,
            prerequisites: ["Xcode and XcodeGen as for R1's apps", "the owner's team ID in Signing.local.xcconfig"],
            gate: "Apple builds (E-2); R2-A01", expectedOutcome: "The build succeeds and the E-2 self-check passes",
            manualSteps: [
                "cd Apps && xcodegen generate --spec project.yml",
                "Build scheme LisaProof for the destination, keeping the log: xcodebuild -scheme LisaProof "
                    + "-destination '<destination>' LISA_PROOF_COMMIT=$(git rev-parse HEAD) build | tee build.log",
                "lisa-verify observe <run-id> <case> --status pass|fail --observed \"…\" --evidence build.log "
                    + "(the harness records the log's SHA-256)",
                "In Lisa Proof's Results tab press 'Run the portable-module check and write its record'; export and "
                    + "import its result.",
            ], session: "X1")
    }

    static let fetchTitles = [
        "Owner-authorized public URL over https (and a public IPv4 literal)",
        "Private destinations refused before any TCP connection (names, literals, a redirect)",
        "Mixed name dialed only at its public address", "A configured system proxy is not used",
        "IPv6-only NAT64 network (macOS Internet Sharing)",
        "Dual-stack network: A records only; AAAA-only names and global IPv6 literals deferred",
        "Independently translated destination never dialed by its AAAA",
        "Split-tunnel VPN: one interface or fail closed", "Platform behavior the design relies on",
    ]

    /// `OV-APPLE-X1-FETCH-01`–`09`: the E-1 probe with Core unavailable, on each of the three devices.
    public static func fetchCase(_ number: Int) -> VerifyCase {
        VerifyCase(
            id: try! VerifyCaseID("OV-APPLE-X1-FETCH-0\(number)"), title: fetchTitles[number - 1], provider: "X1",
            interface: "dns_sd and Network framework NWConnection, Core unavailable",
            capability: "Public fetch on Apple with Core unavailable (E-1)",
            environment: "Mac, iPhone and iPad in turn, no Core configured; the network the case names",
            modes: [.device], requiredResultLevel: .ownerVerified,
            requiredEvidence: [
                "the probe's trace per hop", "the owner's listener or proxy log where the case names one",
            ],
            executor: .owner,
            prerequisites: ["Lisa Proof installed", "the controlled names, listener or network the case needs"],
            gate: "E-1 (release requirement): the production retrieval design (M7)",
            expectedOutcome: "Each subcase ends in its passing outcome on every platform",
            manualSteps: [
                "Arrange the case's network and controlled endpoints.",
                "In Lisa Proof's Fetch tab, run the case's subcases with the URLs you control, then press 'Finish "
                    + "case: write the result record'.",
                "Record what only you can observe (the listener or proxy log) in the app.",
                "Export and import the results.",
            ], session: "X1")
    }

    public static var all: [VerifyCase] {
        var cases: [VerifyCase] = []
        for pair in NearbyPair.allCases {
            for condition in NearbyCondition.allCases { cases.append(nearbyCell(pair, condition)) }
        }
        cases += (1...3).map(portableBuild)
        cases += (1...9).map(fetchCase)
        return cases
    }
}
