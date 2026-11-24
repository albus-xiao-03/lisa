// The harness's own fixture cases (plan §10.8 "Acceptance (S-24, every milestone from M1)"), run by Claude without
// any account or provider: the action ledger against the counting controlled servers for an email, a push, a model
// request and a call in the four interruption variants, resumption and reruns, manual observations, paired results,
// the redacted export and cleanup.

import LisaVerifyKit

/// The harness self-test cases.
public enum HarnessCatalogue {
    static func fixture(_ id: String, _ title: String, expected: String, evidence: [String]) -> VerifyCase {
        VerifyCase(
            id: try! VerifyCaseID(id), title: title, provider: nil, interface: "lisa-verify and the controlled servers",
            capability: "Owner-verification harness (S-24)", environment: "Any host; no network access to a provider",
            modes: [.fixture], requiredResultLevel: .harnessReady, requiredEvidence: evidence, executor: .claude,
            prerequisites: ["A clean checkout"], gate: "S-24 (every milestone from M1)", expectedOutcome: expected,
            manualSteps: [], session: nil)
    }

    public static let all: [VerifyCase] = [
        fixture(
            "OV-HARNESS-LEDGER-01", "Killed after the intent, before any I/O: resumed, one accepted submission",
            expected: "For each of email, push, model request and call: exactly one submission accepted",
            evidence: ["the servers' counts", "the ledger"]),
        fixture(
            "OV-HARNESS-LEDGER-02", "Killed after the server accepted, before the harness recorded it: observed",
            expected: "Resume finds the action through the server's lookup and records it; still one accepted",
            evidence: ["the servers' counts", "the ledger"]),
        fixture(
            "OV-HARNESS-LEDGER-03", "Accepted and dropped with lookup disabled: ambiguous, retried only when typed",
            expected:
                "Resume sends nothing; authorize-retry without the phrase sends nothing; with it exactly one more "
                + "(two accepted, reported as a possible duplicate)",
            evidence: ["the servers' counts", "the ledger"]),
        fixture(
            "OV-HARNESS-LEDGER-04", "A resumed run's new action needs a new confirmation",
            expected: "Refused until a new confirmation lists it; the old confirmation never covers it",
            evidence: ["the ledger", "the refusal"]),
        fixture(
            "OV-HARNESS-RUN-01", "A run interrupted mid-case resumes; one failed case reruns alone",
            expected: "The interrupted case completes on resume; retry reruns only the failed case",
            evidence: ["run.json", "results.jsonl"]),
        fixture(
            "OV-HARNESS-RUN-02", "A manual observation and a paired session's two device results",
            expected: "The observation is recorded; both device results join under one case and nonce",
            evidence: ["results.jsonl", "the report"]),
        fixture(
            "OV-HARNESS-EXPORT-01", "The redacted export contains none of the planted canaries",
            expected: "No canary from configuration, prompts, mail, calendar URLs, numbers, references or tokens",
            evidence: ["the export", "the canary scan"]),
        fixture(
            "OV-HARNESS-CLEANUP-01", "Cleanup removes only what the run created",
            expected: "The run's own data is removed; another run's data and unrelated files are untouched",
            evidence: ["the file listing before and after"]),
    ]
}
