// `report <run-id>` (plan §10.8 "Results"): the owner-readable `summary.md` — per session and area, what passed,
// failed or waits, with causes and next steps. A paired case's device results are joined under the case and the
// session nonce.

/// Renders a run's summary.
public enum VerifyReport {
    public static func summary(run: VerifyRun, results: [VerifyResultRecord], cases: [VerifyCase]) -> String {
        var lines = [
            "# Lisa owner verification — \(run.id)", "",
            "Mode \(run.mode.rawValue); commit \(run.commit); harness \(run.harnessVersion); created \(run.createdAt).",
            "",
        ]
        let bySession = Dictionary(grouping: cases) { $0.session ?? "fixture" }
        for session in bySession.keys.sorted() {
            lines.append("## \(session)")
            lines.append("")
            lines.append("| Case | Title | Device results | Status | Cause |")
            lines.append("|---|---|---|---|---|")
            for verifyCase in bySession[session]!.sorted(by: { $0.id < $1.id }) {
                let mine = results.filter {
                    (try? VerifyCaseID.parseCorrelated($0.caseID))?.0 == verifyCase.id
                }
                let status = combinedStatus(mine, paired: verifyCase.paired)
                let devices =
                    mine.isEmpty
                    ? "—"
                    : mine.map { record in
                        let nonce = record.pairSession.map { " nonce \($0.harnessNonce)" } ?? ""
                        let design = record.design.map { " design \($0)" } ?? ""
                        return "\(record.caseID) \(record.platform)\(design)\(nonce): \(record.status.rawValue)"
                    }.joined(separator: "<br>")
                let cause =
                    mine.isEmpty
                    ? "waiting: \(verifyCase.executor.rawValue) has not run it"
                    : mine.filter { $0.status != .pass }.map(\.cause).joined(separator: "; ")
                lines.append(
                    "| \(verifyCase.id) | \(escape(verifyCase.title)) | \(escape(devices)) | \(status) | "
                        + "\(escape(cause.isEmpty ? "—" : cause)) |")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// PASS only if every result passed and, for a paired case, both roles reported under one nonce per design.
    static func combinedStatus(_ results: [VerifyResultRecord], paired: Bool) -> String {
        guard !results.isEmpty else { return "waiting" }
        if let failing = results.first(where: { $0.status != .pass }) { return failing.status.rawValue }
        guard paired else { return VerifyStatus.pass.rawValue }
        let byDesign = Dictionary(grouping: results) { $0.design ?? "" }
        for (_, records) in byDesign {
            let joined = Dictionary(grouping: records) { $0.pairSession?.harnessNonce ?? "" }
            let complete = joined.contains { nonce, group in
                !nonce.isEmpty && Set(group.compactMap { $0.pairSession?.role }) == ["sender", "receiver"]
            }
            if !complete { return "waiting (one device's result)" }
        }
        return VerifyStatus.pass.rawValue
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}
