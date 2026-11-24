// `export <run-id> --redacted <file>` (plan §10.8 "Redacted export"): allowlisted fields only. Free text is scrubbed,
// configuration is reduced to its digest and allowlisted keys, provider references become digests, and the export is
// refused if any canary the owner (or a fixture) planted survives in it.

import Foundation

/// Writes the redacted export of a run.
public enum VerifyRedactedExport {
    /// Configuration keys that never carry owner data.
    public static let allowlistedConfigurationKeys: Set<String> = [
        "design", "suitePolicy", "fault", "harnessRole", "condition", "devices", "mode", "platform", "rejoin",
    ]

    public struct Document: Codable, Sendable {
        public var format = "lisa-verify-redacted-export"
        public var version = 1
        public var run: VerifyRunID
        public var mode: VerifyMode
        public var commit: String
        public var harnessVersion: String
        public var results: [VerifyResultRecord]
        public var actions: [ActionSummary]
    }

    public struct ActionSummary: Codable, Sendable {
        public var actionID: String
        public var kind: VerifyActionKind
        public var targetAlias: String
        public var state: VerifyActionState
        public var providerReferenceDigest: String?
        public var retryOf: String?
    }

    /// The redacted document; throws if a canary survives.
    public static func make(
        run: VerifyRun, results: [VerifyResultRecord], actions: [VerifyActionRecord], canaries: [String]
    ) throws(VerifyError) -> Data {
        let redactor = VerifyRedactor()
        let scrubbed = results.map { record -> VerifyResultRecord in
            var copy = record
            copy.configuration.fields = record.configuration.fields.filter {
                allowlistedConfigurationKeys.contains($0.key)
            }.mapValues(redactor.scrub)
            copy.assumptions = record.assumptions.map(redactor.scrub)
            copy.expectedResult = redactor.scrub(record.expectedResult)
            copy.observedResult = redactor.scrub(record.observedResult)
            copy.cause = redactor.scrub(record.cause)
            copy.actions = record.actions.map(redactor.scrub)
            copy.evidenceFiles = record.evidenceFiles.map(redactor.scrub)
            copy.checks = record.checks.map { check in
                var check = check
                check.observed = redactor.scrub(check.observed)
                return check
            }
            return copy
        }
        let summaries = actions.map { action in
            ActionSummary(
                actionID: action.actionID, kind: action.kind, targetAlias: action.targetAlias, state: action.state,
                providerReferenceDigest: action.providerReference.map(redactor.digest), retryOf: action.retryOf)
        }
        let document = Document(
            run: run.id, mode: run.mode, commit: run.commit, harnessVersion: run.harnessVersion, results: scrubbed,
            actions: summaries)
        let data: Data
        do {
            data = try VerifyRunStore.encoder().encode(document)
        } catch {
            throw .store("can't encode the export: \(error)")
        }
        let text = String(decoding: data, as: UTF8.self)
        let surviving = canaries.filter { !$0.isEmpty && text.contains($0) }
        guard surviving.isEmpty else {
            throw .store(
                "the export still contains \(surviving.count) planted canar\(surviving.count == 1 ? "y" : "ies"); nothing written"
            )
        }
        return data
    }
}
