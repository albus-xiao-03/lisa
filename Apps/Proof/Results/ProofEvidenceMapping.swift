// PROOF ONLY — Apps/Proof never ships. Turns what the nearby proof observed into evidence entries for the N-1
// checks (plan §10.5): a session report, a reconnection, a deduplication, a local-network state. A refusal check is
// credited on the device that injected the fault (it alone knows what it did); the refusing device records the
// refusal as a "session" entry. Each refusal case is therefore run once with each device as the faulting side.

import Foundation

enum ProofEvidenceMapping {
    static func entries(
        for report: ProofSessionReport, configuration: ProofNearbyConfiguration, context: ProofRunContext
    ) -> [ProofEvidenceEntry] {
        let make = maker(context: context, design: configuration.design.rawValue, session: report)
        let summary =
            report.authenticated
            ? "authenticated \(report.peerLabel ?? "?") (\(report.peerDeviceID ?? "?")), session code \(report.sessionCode ?? "?")"
            : "not authenticated: \(report.refusal ?? "unknown")"
        if configuration.design == .a, configuration.suitePolicy == .diagnosticPlainPSK {
            return [make("diagnostic-plain-psk", report.authenticated ? .pass : .fail, summary)]
        }
        var entries = [make("session", report.authenticated ? .pass : .fail, summary)]
        if let check = configuration.fault.check, configuration.fault != .oversizeFrameHeader {
            entries.append(
                make(
                    check.rawValue, report.authenticated ? .fail : .pass,
                    "fault \(configuration.fault.rawValue): \(summary)"))
            return entries
        }
        guard report.authenticated else { return entries }
        entries.append(make(ProofCellCheck.peerIdentification.rawValue, .pass, summary))
        entries.append(
            make(
                ProofCellCheck.exporterBoundHello.rawValue, .pass,
                "both transcript signatures over the 32-byte exporter verified; code \(report.sessionCode ?? "?")"))
        let tls =
            "\(report.tlsVersion ?? "?") / \(report.cipherSuite ?? "?") (0x\(String(report.cipherSuiteRaw ?? 0, radix: 16)))"
        entries.append(make(ProofCellCheck.tlsVersionAndSuite.rawValue, .pass, tls))
        if configuration.design == .a {
            entries.append(
                make(ProofCellCheck.forwardSecretSuite.rawValue, report.forwardSecret == true ? .pass : .fail, tls))
        }
        if report.closedByDeduplication {
            entries.append(
                make(ProofCellCheck.deduplication.rawValue, .pass, "this session closed under the lower-device-ID rule")
            )
        }
        if let timing = report.timing {
            entries.append(
                make(
                    ProofCellCheck.framesTimed.rawValue, timing.frames == ProofTimedExchange.frameCount ? .pass : .fail,
                    "\(timing.frames) × \(timing.payloadBytes) B round trips: min \(timing.minimumNanoseconds) ns, median \(timing.medianNanoseconds) ns, p95 \(timing.p95Nanoseconds) ns, max \(timing.maximumNanoseconds) ns"
                ))
            let budget =
                configuration.fault == .oversizeFrameHeader
                ? (timing.peerClosedAfterOversize == true ? ProofStatus.pass : .fail) : .pass
            entries.append(
                make(
                    ProofCellCheck.framesWithinBudget.rawValue, budget,
                    "full 1 MiB frame round trip \(timing.fullBudgetFrameRoundTripNanoseconds) ns; oversize header sent: \(timing.oversizeHeaderSent), peer closed: \(timing.peerClosedAfterOversize.map(String.init) ?? "n/a")"
                ))
        }
        if let echo = report.echo {
            entries.append(
                make(
                    ProofCellCheck.framesTimed.rawValue,
                    echo.framesEchoed >= ProofTimedExchange.frameCount ? .pass : .fail,
                    "receiver echoed \(echo.framesEchoed) frames and \(echo.clockReplies) clock probes; ended by \(echo.endedBy)"
                ))
            if echo.endedBy == "oversize-header-refused-before-allocation" {
                entries.append(make(ProofCellCheck.framesWithinBudget.rawValue, .pass, echo.endedBy))
            }
        }
        if configuration.rejoin {
            let ok =
                report.pskIdentityKind == DesignAPSKEntry.Kind.rejoin.rawValue && report.rejoinSecretMatched == true
            entries.append(
                make(
                    ProofCellCheck.rejoinWithoutSecret.rawValue, ok ? .pass : .fail,
                    "identity \(report.pskIdentityKind ?? "?"), discovery secret handed over: \(report.rejoinSecretMatched.map(String.init) ?? "no")"
                ))
        }
        return entries
    }

    static func reconnect(
        _ observation: ProofNearbyController.ReconnectObservation, configuration: ProofNearbyConfiguration,
        context: ProofRunContext
    ) -> ProofEvidenceEntry {
        let check: ProofCellCheck = observation.trigger == .kill ? .reconnectAfterKill : .reconnectAfterWiFiToggle
        let downtime = (observation.authenticatedNanoseconds &- observation.downNanoseconds) / 1_000_000
        return maker(context: context, design: configuration.design.rawValue, session: nil)(
            check.rawValue, .pass,
            "re-authenticated with \(observation.peerDeviceID) \(downtime) ms after the link went down (or after launch)"
        )
    }

    static func deduplication(_ text: String, configuration: ProofNearbyConfiguration, context: ProofRunContext)
        -> ProofEvidenceEntry
    {
        maker(context: context, design: configuration.design.rawValue, session: nil)(
            ProofCellCheck.deduplication.rawValue, .pass, text)
    }

    /// Device-level: an observed denial is the denial check's evidence; the owner's prompt observation is the
    /// prompt check's.
    static func localNetwork(_ state: ProofLocalNetworkState, detail: String, context: ProofRunContext)
        -> ProofEvidenceEntry?
    {
        guard state == .deniedPolicy || state == .deniedPath else { return nil }
        let entry = ProofEvidenceEntry(
            runID: context.runID, caseID: ProofCellCheck.deviceLevelCaseKey, design: nil,
            check: ProofCellCheck.permissionDenial.rawValue,
            status: context.permissionChoice == "denied" ? .pass : .fail,
            observed:
                "\(state.rawValue) (\(detail)); owner's choice: \(context.permissionChoice.isEmpty ? "not recorded" : context.permissionChoice)",
            monotonicNanoseconds: ProofMonotonicClock.nowNanoseconds(), wallClock: wallClock())
        return entry
    }

    static func prompt(context: ProofRunContext) -> ProofEvidenceEntry? {
        guard !context.permissionPrompt.isEmpty else { return nil }
        return ProofEvidenceEntry(
            runID: context.runID, caseID: ProofCellCheck.deviceLevelCaseKey, design: nil,
            check: ProofCellCheck.permissionPrompt.rawValue, status: .pass,
            observed: "owner observed the prompt as \(context.permissionPrompt); choice \(context.permissionChoice)",
            monotonicNanoseconds: ProofMonotonicClock.nowNanoseconds(), wallClock: wallClock())
    }

    static func wallClock() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func maker(context: ProofRunContext, design: String, session: ProofSessionReport?)
        -> (String, ProofStatus, String) -> ProofEvidenceEntry
    {
        { check, status, observed in
            var entry = ProofEvidenceEntry(
                runID: context.runID, caseID: context.correlatedCaseID, design: design, check: check, status: status,
                observed: observed, monotonicNanoseconds: ProofMonotonicClock.nowNanoseconds(), wallClock: wallClock())
            entry.session = check == "session" || check == "diagnostic-plain-psk" ? session : nil
            return entry
        }
    }
}
