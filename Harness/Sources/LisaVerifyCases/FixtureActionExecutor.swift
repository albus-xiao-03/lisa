// The harness performing a fixture action itself against the controlled servers under the ledger's rules (plan §10.8
// "The action ledger"): the intent before any I/O, `submitting` before the first byte, the outcome as soon as it is
// known; when the answer is lost, the server's lookup decides between accepted and ambiguous. Resume observes and
// reconciles: an intent that never reached I/O is sent with the same operation ID; an action that reached
// `submitting` is never sent again.

import Foundation
import LisaVerifyKit
import LisaVerifyServers

/// The loopback ports of the controlled servers a fixture run uses.
public struct FixtureEndpoints: Sendable, Equatable {
    public let smtpPort: Int
    public let httpPort: Int

    public init(smtpPort: Int, httpPort: Int) {
        self.smtpPort = smtpPort
        self.httpPort = httpPort
    }
}

/// Performs and reconciles fixture actions.
public enum FixtureActionExecutor {
    /// The planned action at `position` of a fixture case: deterministic, so every process derives the same one.
    public static func plannedAction(
        case caseID: VerifyCaseID, kind: VerifyActionKind, position: Int, in run: VerifyRunID
    ) -> VerifyPlannedAction {
        VerifyPlannedAction(
            caseID: caseID, position: position, kind: kind, targetAlias: "\(kind.rawValue)-target-1",
            operationID: "op-\(run.text)-\(caseID.text)-\(position)", slot: nil,
            summary: "fixture \(kind.rawValue) to \(kind.rawValue)-target-1 (controlled server)")
    }

    /// The key the controlled servers count the action under: the email's `Message-ID`, else the operation ID.
    public static func key(kind: VerifyActionKind, operationID: String) -> String {
        kind == .email ? "<\(operationID)@lisa-verify.invalid>" : operationID
    }

    /// Records the intent and performs the action, optionally requiring a confirmation that lists it and optionally
    /// killing the process at a crash point.
    public static func perform(
        _ planned: VerifyPlannedAction, in run: VerifyRunID, ledger: VerifyActionLedger, endpoints: FixtureEndpoints,
        requireConfirmation: Bool, crashAt: FixtureCrashPoint?
    ) async throws(VerifyError) -> VerifyActionRecord {
        let id = planned.actionID(in: run)
        var digest = "fixture (no real action)"
        if requireConfirmation {
            guard let confirmed = try ledger.confirmation(covering: id, in: run) else {
                throw .confirmationRequired("\(id) is in no confirmed list; confirm the run's new list first")
            }
            digest = confirmed
        }
        let record = try ledger.recordIntent(planned, in: run, confirmationDigest: digest)
        guard record.state == .intent else { return record }
        if crashAt == .afterIntent { crashAt?.strike() }
        return try await submit(record, ledger: ledger, endpoints: endpoints, crashAt: crashAt)
    }

    /// Resume: reconciles every unresolved action of the run and returns the ledger.
    public static func resume(run: VerifyRunID, ledger: VerifyActionLedger, endpoints: FixtureEndpoints)
        async throws(VerifyError) -> [VerifyActionRecord]
    {
        for record in try ledger.unresolved(in: run) {
            switch record.state {
            case .intent: _ = try await submit(record, ledger: ledger, endpoints: endpoints, crashAt: nil)
            case .submitting: try await observe(record, ledger: ledger, endpoints: endpoints)
            default: break
            }
        }
        return try ledger.records(in: run)
    }

    static func submit(
        _ record: VerifyActionRecord, ledger: VerifyActionLedger, endpoints: FixtureEndpoints,
        crashAt: FixtureCrashPoint?
    ) async throws(VerifyError) -> VerifyActionRecord {
        try ledger.markSubmitting(record.actionID)
        let outcome: ControlledClient.Outcome
        do {
            outcome = try await send(record, endpoints)
        } catch {
            outcome = .noAnswer
        }
        switch outcome {
        case .accepted(let reference):
            if crashAt == .afterAccept { crashAt?.strike() }
            try ledger.recordAccepted(record.actionID, providerReference: reference, outcome: "accepted")
        case .refused(let status):
            try ledger.recordRefused(record.actionID, outcome: "refused with \(status)")
        case .noAnswer:
            try await observe(record, ledger: ledger, endpoints: endpoints)
        }
        guard let updated = try ledger.record(record.actionID) else { throw .ledger("\(record.actionID) vanished") }
        return updated
    }

    /// The server's lookup decides: found → accepted; otherwise ambiguous (absence proves nothing).
    static func observe(_ record: VerifyActionRecord, ledger: VerifyActionLedger, endpoints: FixtureEndpoints)
        async throws(VerifyError)
    {
        let lookup: ControlledRegistry.Lookup
        do {
            lookup = try await ControlledClient.lookup(
                port: endpoints.httpPort, key: key(kind: record.kind, operationID: record.operationID))
        } catch {
            lookup = .disabled
        }
        switch lookup {
        case .found(let reference, _):
            try ledger.recordAccepted(record.actionID, providerReference: reference, outcome: "accepted (observed)")
        case .notFound:
            try ledger.markAmbiguous(record.actionID, evidence: "no answer; the lookup found nothing")
        case .disabled:
            try ledger.markAmbiguous(record.actionID, evidence: "no answer; no lookup available")
        }
    }

    static func send(_ record: VerifyActionRecord, _ endpoints: FixtureEndpoints) async throws
        -> ControlledClient.Outcome
    {
        let key = key(kind: record.kind, operationID: record.operationID)
        switch record.kind {
        case .email:
            return try await ControlledClient.sendEmail(
                port: endpoints.smtpPort, messageID: key, recipientAlias: record.targetAlias)
        case .push:
            return try await ControlledClient.post(
                port: endpoints.httpPort, path: "/3/device/fixture-token", operationID: key, body: "{\"aps\":{}}")
        case .modelRequest:
            return try await ControlledClient.post(
                port: endpoints.httpPort, path: "/v1/chat/completions", operationID: key,
                body: "{\"model\":\"fixture\"}")
        case .call:
            return try await ControlledClient.post(
                port: endpoints.httpPort, path: "/2010-04-01/Accounts/ACfixture/Calls.json", operationID: key,
                body: "{}")
        }
    }
}
