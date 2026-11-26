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

    /// The routes converted so far: `POST /v1/tasks` (M3-6a).
    static func isConverted(_ route: APIRoute) -> Bool {
        if case .createTask = route { return true }
        return false
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
            retentionDays: configuration.idempotencyRetentionDays
        ) { tx in
            switch route {
            case .createTask:
                return try convertCreateTask(request, principal: principal, context: context, tx: tx, changes: &changes)
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
            throw try terminalReply(route, context: context)
        case .awaitingReview:
            throw APIFailure(
                body: APIErrorBody(
                    code: .unavailable, message: "This change is waiting for review on the administrative terminal.",
                    retryAfterSeconds: 300))
        }
        guard let conversion else {
            throw APIFailure(body: APIErrorBody(code: .internalError, message: "the conversion returned no answer"))
        }
        if conversion.isRecordable, !changes.isEmpty {
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

    /// The answer to a retry whose recorded body has expired (§8.12.2 "Live answers"), from current state, never from
    /// the expired bytes. M3-6d adds the `lisaCode` field these answers also carry.
    func terminalReply(_ route: APIRoute, context: LegacyRequestContext) throws -> APIFailure {
        switch route {
        case .createTask:
            guard try application.record(LisaTask.self, id: context.createdTaskID) != nil else {
                return APIFailure(
                    body: APIErrorBody(
                        code: .notFound, message: "The task this request created was deleted afterwards."))
            }
            return APIFailure(
                body: APIErrorBody(
                    code: .conflict, message: "This task was created earlier; its reply is no longer available."))
        default:
            return APIFailure(body: APIErrorBody(code: .internalError, message: "the route isn't converted"))
        }
    }
}
