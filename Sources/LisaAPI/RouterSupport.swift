// Router plumbing: dispatch to handlers, JSON responses, body decoding, query parsing and per-caller throttling.

import Foundation
import LisaAPIContract
import LisaApplication
import LisaDomain
import LisaTime
import Synchronization

extension APIRouter {
    func dispatch(_ route: APIRoute, request: APIRequest, caller: Caller, requestID: String?) async throws
        -> APIResponse
    {
        switch route {
        case .health: return try health()
        case .rundown: return try rundown(request)
        case .planBlockAction(let plan, let block): return try planBlockAction(plan, block, request, caller)
        case .brief: return try brief(request)
        case .regenerateBrief: return try regenerateBrief(request, caller)
        case .capture: return try capture(request, caller, requestID: requestID)
        case .retrieveCapture(let id): return try await retrieveCapture(id, caller)
        case .listTasks: return try listTasks(request)
        case .createTask: return try createTask(request, caller)
        case .task(let id): return try task(id)
        case .updateTask(let id): return try updateTask(id, request, caller)
        case .listIdeas: return try listIdeas(request)
        case .updateIdea(let id): return try updateIdea(id, request, caller)
        case .listProposals: return try listProposals(request)
        case .proposalAction(let id): return try proposalAction(id, request, caller)
        case .proposalCalendarFile(let id): return try proposalCalendarFile(id)
        case .listReminders: return try listReminders(request)
        case .reminderAction(let id): return try reminderAction(id, request, caller)
        case .notificationAction(let id): return try notificationAction(id, request, caller)
        case .preferences: return try preferences()
        case .updatePreferences: return try updatePreferences(request, caller)
        case .sourcesStatus: return try sourcesStatus()
        case .createPairingCode: return try createPairingCode(caller)
        case .pairDevice: return try pairDevice(request)
        case .pushRegistration: return try pushRegistration(request, caller)
        case .notificationStatus: return try notificationStatus(request, caller)
        case .deviceNotificationPreferences: return try deviceNotificationPreferences(caller)
        case .updateDeviceNotificationPreferences: return try updateDeviceNotificationPreferences(request, caller)
        case .notificationReceipts: return try notificationReceipts(request, caller)
        case .listDevices: return try listDevices(caller)
        case .removeDevice(let id): return try removeDevice(id, caller)
        case .export: return try export(caller)
        }
    }

    // MARK: - Responses

    static func headers(contentType: String) -> [String: String] {
        ["Content-Type": contentType, APIVersioning.versionHeader: APIVersioning.version]
    }

    func json<T: Encodable>(_ value: T, status: Int = 200) throws -> APIResponse {
        APIResponse(
            status: status, headers: Self.headers(contentType: "application/json"),
            body: try APIJSON.encoder().encode(value))
    }

    static func error(_ body: APIErrorBody) -> APIResponse {
        var headers = headers(contentType: "application/json")
        if let retry = body.retryAfterSeconds { headers["Retry-After"] = String(retry) }
        let data = (try? APIJSON.encoder().encode(body)) ?? Data()
        return APIResponse(status: body.code.httpStatus, headers: headers, body: data)
    }

    // MARK: - Input

    func decode<T: Decodable>(_ type: T.Type, _ request: APIRequest) throws -> T {
        guard let body = request.body, !body.isEmpty else {
            throw APIFailure.invalid("a JSON request body is required")
        }
        do {
            return try APIJSON.decoder().decode(type, from: body)
        } catch {
            throw APIFailure.invalid("the request body does not match the documented schema for this route")
        }
    }

    /// The `date` query parameter, or today in the owner's zone.
    func localDate(_ request: APIRequest, _ name: String = "date") throws -> LocalDate {
        guard let text = request.query[name] else { return try application.today() }
        guard APIDates.isLocalDate(text), let date = LocalDate(iso: text) else {
            throw APIFailure.invalid("\(name) must be a date such as 2026-11-16", field: name)
        }
        return date
    }

    func pageLimit(_ request: APIRequest) throws -> Int {
        guard let text = request.query[Pagination.limitParameter] else { return Pagination.defaultLimit }
        guard let limit = Int(text), (1...Pagination.maxLimit).contains(limit) else {
            throw APIFailure.invalid(
                "limit must be between 1 and \(Pagination.maxLimit)", field: Pagination.limitParameter)
        }
        return limit
    }

    func cursor(_ request: APIRequest) throws -> String? {
        guard let cursor = request.query[Pagination.cursorParameter] else { return nil }
        guard (1...128).contains(cursor.count), cursor.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw APIFailure.invalid("cursor is not a value this API returned", field: Pagination.cursorParameter)
        }
        return cursor
    }

    /// A comma-separated list of allowed values.
    func values<T>(_ request: APIRequest, _ name: String, _ parse: (String) -> T?) throws -> [T]? {
        guard let text = request.query[name], !text.isEmpty else { return nil }
        return try text.split(separator: ",").map { part in
            guard let value = parse(String(part)) else {
                throw APIFailure.invalid("\(name) has an unknown value \(part)", field: name)
            }
            return value
        }
    }

    func requireDevice(_ caller: Caller) throws -> DeviceID {
        guard let id = caller.deviceID else {
            throw APIFailure.forbidden("only a paired device has a current registration")
        }
        return id
    }

    func principal(_ caller: Caller) throws -> Principal {
        guard let principal = caller.principal else { throw APIFailure.unauthenticated }
        return principal
    }
}

/// A fixed-window request limit per caller.
final class RateLimiter: Sendable {
    private let perMinute: Int
    private let windows = Mutex<[String: (start: Date, count: Int)]>([:])

    init(perMinute: Int) {
        self.perMinute = perMinute
    }

    /// `nil` when the request is admitted, otherwise the seconds until the window resets.
    func admit(_ key: String, now: Date) -> Int? {
        windows.withLock { windows in
            if windows.count > 10_000 { windows.removeAll() }
            var window = windows[key] ?? (now, 0)
            if now.timeIntervalSince(window.start) >= 60 { window = (now, 0) }
            let limit = key == "anonymous" ? max(5, perMinute / 10) : perMinute
            guard window.count < limit else {
                return max(1, Int((60 - now.timeIntervalSince(window.start)).rounded(.up)))
            }
            window.count += 1
            windows[key] = window
            return nil
        }
    }
}
