// R2's v1 translation in the router (plan §8.12.2; docs/DECISIONS.md D-71). With a legacy converter configured, a
// converted route's request is looked up and converted in one Core transaction, and R1's answer is recorded with the
// parent. The other routes keep R1's handlers and request ledger. Both stores share the caller's one request-ID space,
// so reusing a key across them is refused as R1 refuses it. R1's domain changes are propagated after the commit.

import Foundation
import LisaAPIContract
import LisaApplication
import LisaCoreLedger
import LisaDomain
import LisaLegacyRequests
import LisaOwnerData

extension APIRouter {
    /// The same router, converting the routes `converter` handles so far instead of writing through R1's services.
    public func converting(with converter: LegacyConverter) -> APIRouter {
        var configuration = configuration
        configuration.legacyConverter = converter
        return APIRouter(application: application, configuration: configuration, status: status, logger: logger)
    }

    /// The routes converted so far: `POST /v1/tasks` and `PATCH /v1/tasks/{id}` (M3-6a), `PATCH /v1/preferences`
    /// (M3-6b).
    static func isConverted(_ route: APIRoute) -> Bool {
        switch route {
        case .createTask, .updateTask, .updatePreferences: true
        default: false
        }
    }

    /// §8.12.2's answer while a request waits for an administrative decision: R1's 503, never recorded.
    static var awaitingReview: APIFailure {
        APIFailure(
            body: APIErrorBody(
                code: .unavailable, message: "This change is waiting for review on the administrative terminal.",
                retryAfterSeconds: 300))
    }

    static var requestIDReused: APIFailure {
        APIFailure(
            body: APIErrorBody(
                code: .requestIDReused, message: "this request ID was already used for a different request"))
    }

    /// A recorded answer, replayed as R1 replays one.
    static func replayed(status: Int, body: Data) -> APIResponse {
        var replayed = APIResponse(status: status, headers: Self.headers(contentType: "application/json"), body: body)
        replayed.headers["Lisa-Replayed"] = "true"
        return replayed
    }

    /// R1's refusal before any change: its status and error body, and no child.
    static func refusal(_ failure: any Error) -> LegacyConversion {
        let response = Self.error(ErrorMapping.body(for: failure))
        return LegacyConversion(status: response.status, body: [UInt8](response.body), children: [], setDigest: nil)
    }

    /// A converted route's request: the parent's answer when one exists, otherwise the conversion. The conversion is
    /// recorded with the parent when R1 would record its answer, and R1's domain changes are propagated after the
    /// commit (§8.12.2 "Atomicity"). A failure after the children were taken in keeps nothing and answers R1's 500.
    func converted(
        _ request: APIRequest, route: APIRoute, caller: Caller, requestID: String, fingerprint: String,
        converter: LegacyConverter
    ) throws -> APIResponse {
        // A key R1's own ledger holds, from a route not yet converted, keeps R1's answer for that key.
        switch try application.lookupRequest(scopedKey: "\(caller.scope):\(requestID)", fingerprint: fingerprint) {
        case .replay(let status, let body): return Self.replayed(status: status, body: body)
        case .mismatch: throw Self.requestIDReused
        case .unknown: break
        }
        let principal = try principal(caller)
        let context = LegacyRequestContext(datasetID: converter.datasetID, scope: caller.scope, requestID: requestID)
        var changes: [DomainChange] = []
        let (lookup, conversion) = try converter.ledger.legacyConvert(
            scope: caller.scope, requestID: requestID, fingerprint: fingerprint, route: Self.name(of: route),
            retentionDays: configuration.idempotencyRetentionDays, requestBody: request.body.map { [UInt8]($0) }
        ) { tx in
            switch route {
            case .createTask:
                return try convertCreateTask(request, principal: principal, context: context, tx: tx, changes: &changes)
            case .updateTask(let id):
                return try convertUpdateTask(
                    id, request, principal: principal, context: context, tx: tx, changes: &changes)
            case .updatePreferences:
                return try convertUpdatePreferences(
                    request, principal: principal, context: context, tx: tx, changes: &changes)
            default:
                throw APIFailure(body: APIErrorBody(code: .internalError, message: "the route isn't converted"))
            }
        }
        switch lookup {
        case .unknown:
            break
        case .replay(let status, let body):
            return Self.replayed(status: status, body: Data(body))
        case .mismatch:
            throw Self.requestIDReused
        case .bodyExpired:
            return try terminalReply(route, context: context)
        case .awaitingReview:
            throw Self.awaitingReview
        }
        guard let conversion else {
            throw APIFailure(body: APIErrorBody(code: .internalError, message: "the conversion returned no answer"))
        }
        if conversion.isRecordable || conversion.awaitsReview, !changes.isEmpty {
            do {
                try application.propagate(changes)
            } catch {
                // The change is committed and its answer recorded; the host's cycle replans and syncs reminders.
                logger.error("follow-up after a conversion failed", ["error": .private(String(describing: error))])
            }
        }
        return APIResponse(
            status: conversion.status, headers: Self.headers(contentType: "application/json"),
            body: Data(conversion.body))
    }

    /// `POST /v1/tasks` under R1's semantics: the body checks inside the parent, so their answers replay (D-35), then
    /// R1's checks, then the children and R1's 201 `TaskDTO`.
    func convertCreateTask(
        _ request: APIRequest, principal: Principal, context: LegacyRequestContext, tx: LegacyTransaction,
        changes: inout [DomainChange]
    ) throws -> LegacyConversion {
        let draft: TaskDraft
        do {
            try Self.checkBodySize(request)
            draft = try LegacyTaskRoutes.checkedCreation(try taskDraft(request), by: principal)
        } catch {
            return Self.refusal(error)
        }
        let effect = try LegacyTaskRoutes.create(draft, by: principal, context: context, in: tx)
        changes = effect.changes
        let answer = try json(DTOMapping.task(effect.task), status: 201)
        return LegacyConversion(
            status: answer.status, body: [UInt8](answer.body), children: effect.children, setDigest: effect.setDigest)
    }

    /// `PATCH /v1/tasks/{id}` under R1's semantics (D-72): the body size, its decoding, the record, the revision check,
    /// the correction's deadline and `TaskService`'s checks inside the parent, so their answers replay; then the field
    /// children and the status. R1's answer is 200 with the `TaskDTO`, or the status's refusal with the correction kept.
    func convertUpdateTask(
        _ id: String, _ request: APIRequest, principal: Principal, context: LegacyRequestContext,
        tx: LegacyTransaction, changes: inout [DomainChange]
    ) throws -> LegacyConversion {
        let taskID = TaskID(id)
        let body: TaskPatchRequest
        var correction: TaskCorrection
        do {
            try Self.checkBodySize(request)
            body = try decode(TaskPatchRequest.self, request)
            guard let current = try tx.records.get(LisaTask.self, id: taskID) else {
                throw APIFailure.notFound("the task")
            }
            guard current.revision.value == body.expectedRevision else {
                throw APIFailure.conflict("the task changed since it was read", currentRevision: current.revision.value)
            }
            correction = try taskCorrection(body)
            if correction != TaskCorrection() {
                correction = try LegacyTaskRoutes.checkedCorrection(correction, by: principal)
            }
        } catch {
            return Self.refusal(error)
        }
        let effect = try LegacyTaskRoutes.update(
            taskID, correction: correction, status: body.status.flatMap { TaskStatus(rawValue: $0.rawValue) },
            expectedRevision: body.expectedRevision, by: principal, context: context, in: tx)
        changes = effect.changes
        if let refusal = effect.statusRefusal {
            let response = Self.error(ErrorMapping.body(for: refusal))
            return LegacyConversion(
                status: response.status, body: [UInt8](response.body), children: effect.children,
                setDigest: effect.setDigest)
        }
        let answer = try json(DTOMapping.task(effect.task))
        return LegacyConversion(
            status: answer.status, body: [UInt8](answer.body), children: effect.children, setDigest: effect.setDigest)
    }

    /// `PATCH /v1/preferences` under R1's semantics (D-74): the body size, its decoding and the 1–50 changes inside the
    /// parent, so their answers replay; then each change in order. R1's answer is 200 with every preference, or the
    /// first refusal, rendered from a template that names the change's position, with the earlier changes kept. In
    /// owner scope an administrative key holds the request: the 503, not recorded, with the earlier changes kept (D-75).
    func convertUpdatePreferences(
        _ request: APIRequest, principal: Principal, context: LegacyRequestContext, tx: LegacyTransaction,
        changes: inout [DomainChange]
    ) throws -> LegacyConversion {
        let requested: [LegacyPreferenceRoutes.Change]
        do {
            try Self.checkBodySize(request)
            let body = try decode(PreferencesPatchRequest.self, request)
            guard !body.changes.isEmpty, body.changes.count <= 50 else {
                throw APIFailure.invalid("send between 1 and 50 changes", field: "changes")
            }
            requested = body.changes.map { change in
                let action: LegacyPreferenceRoutes.Action
                if let value = change.value {
                    action = .set(DTOMapping.preferenceValue(value), expectedRevision: change.expectedRevision)
                } else if change.confirm == true {
                    action = .confirm
                } else {
                    action = .delete
                }
                return LegacyPreferenceRoutes.Change(key: change.key, action: action)
            }
        } catch {
            return Self.refusal(error)
        }
        let effect = try LegacyPreferenceRoutes.update(requested, by: principal, context: context, in: tx)
        changes = effect.changes
        if effect.heldIndex != nil {
            let response = Self.error(Self.awaitingReview.body)
            return LegacyConversion(
                status: response.status, body: [UInt8](response.body), children: effect.children,
                setDigest: effect.setDigest)
        }
        if let refused = effect.refusal {
            let response = Self.error(Self.template(refused))
            return LegacyConversion(
                status: response.status, body: [UInt8](response.body), children: effect.children,
                setDigest: effect.setDigest)
        }
        let answer = try json(effect.preferences.map(DTOMapping.preference))
        return LegacyConversion(
            status: answer.status, body: [UInt8](answer.body), children: effect.children, setDigest: effect.setDigest)
    }

    /// R1's refusal of a preference change, with R1's code, from a fixed template that names the change's position and
    /// never the caller's key or value (§8.12.2 "Error bodies never echo caller input").
    static func template(_ refused: LegacyPreferenceRoutes.Refused) -> APIErrorBody {
        let change = "changes[\(refused.index)]"
        switch refused.refusal {
        case .unsupportedKey:
            return APIErrorBody(
                code: .invalidRequest, message: "\(change).key is not a supported preference", field: "\(change).key")
        case .invalidValue(let reason):
            // R1's reasons are its own text; only an unknown weekday's names the caller's token.
            let shown = reason.hasPrefix("unknown weekday") ? "has an unknown weekday" : reason
            return APIErrorBody(code: .invalidRequest, message: "\(change).value \(shown)", field: "\(change).value")
        case .ownerOnly:
            return APIErrorBody(code: .forbidden, message: "\(change) can be changed only by the owner on the host")
        case .deletedByOwnerOnly:
            return APIErrorBody(code: .forbidden, message: "\(change) can be deleted only by the owner on the host")
        case .notPermitted:
            return APIErrorBody(code: .forbidden, message: "\(change) can't be changed by this caller")
        case .notFound:
            return APIErrorBody(code: .notFound, message: "\(change) names a preference that does not exist")
        case .changed(let currentRevision):
            return APIErrorBody(
                code: .conflict, message: "\(change) changed since it was read; reload it and try again",
                currentRevision: currentRevision)
        }
    }

    /// The answer to a retry whose recorded body has expired (§8.12.2 "Live answers"), from current state, never from
    /// the expired bytes. M3-6d adds the `lisaCode` field these answers also carry.
    func terminalReply(_ route: APIRoute, context: LegacyRequestContext) throws -> APIResponse {
        switch route {
        case .createTask:
            guard try application.record(LisaTask.self, id: context.createdTaskID) != nil else {
                throw APIFailure(
                    body: APIErrorBody(
                        code: .notFound, message: "The task this request created was deleted afterwards."))
            }
            throw APIFailure(
                body: APIErrorBody(
                    code: .conflict, message: "This task was created earlier; its reply is no longer available."))
        case .updateTask(let id):
            guard let task = try application.record(LisaTask.self, id: TaskID(id)) else {
                throw APIFailure(
                    body: APIErrorBody(
                        code: .notFound, message: "This change was applied; the task was deleted afterwards."))
            }
            var current = try json(DTOMapping.task(task))
            current.headers["Lisa-Replayed"] = "true"
            current.headers["Lisa-Reply"] = "current"
            return current
        case .updatePreferences:
            // §8.12.2's terminal reply for the owner's settings: the 409, never a list rebuilt from current state.
            throw APIFailure(
                body: APIErrorBody(
                    code: .conflict,
                    message:
                        "This change was applied; its reply is no longer available. Reload to see current values."))
        default:
            throw APIFailure(body: APIErrorBody(code: .internalError, message: "the route isn't converted"))
        }
    }
}
