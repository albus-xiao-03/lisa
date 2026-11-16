// Handlers for tasks, ideas and captures.

import Foundation
import LisaAPIContract
import LisaApplication
import LisaDomain
import LisaOwnerData
import LisaPorts
import LisaTime

extension APIRouter {
    static func deadline(_ dto: DeadlineDTO?, field: String) throws -> Deadline? {
        guard let dto else { return nil }
        guard dto.isValid else {
            throw APIFailure.invalid("\(field) needs exactly one of instant or date (YYYY-MM-DD)", field: field)
        }
        if let instant = dto.instant {
            var zone: TimeZoneID?
            if let identifier = dto.zone {
                guard let parsed = TimeZoneID(identifier) else {
                    throw APIFailure.invalid("\(field).zone is not a known time zone", field: "\(field).zone")
                }
                zone = parsed
            }
            return .at(instant: instant, zone: zone)
        }
        guard let text = dto.date, let date = LocalDate(iso: text) else {
            throw APIFailure.invalid("\(field).date must look like 2026-11-16", field: "\(field).date")
        }
        return .onDate(date)
    }

    func listTasks(_ request: APIRequest) throws -> APIResponse {
        var query = RecordQuery.all
        if let statuses = try values(request, "status", { TaskStatus(rawValue: $0) }) {
            query = query.filter("status", in: statuses.map { .text($0.rawValue) })
        }
        let page = try application.page(LisaTask.self, query, limit: try pageLimit(request), after: try cursor(request))
        return try json(Page(items: page.items.map(DTOMapping.task), nextCursor: page.nextCursor))
    }

    func task(_ id: String) throws -> APIResponse {
        guard let task = try application.record(LisaTask.self, id: TaskID(id)) else {
            throw APIFailure.notFound("the task")
        }
        return try json(DTOMapping.task(task))
    }

    func createTask(_ request: APIRequest, _ caller: Caller) throws -> APIResponse {
        let body = try decode(TaskCreateRequest.self, request)
        let task = try application.createTask(
            TaskDraft(
                title: body.title, notes: body.notes ?? "",
                priority: body.priority.flatMap { TaskPriority(rawValue: $0.rawValue) } ?? .normal,
                deadline: try Self.deadline(body.deadline, field: "deadline"), estimatedMinutes: body.estimatedMinutes,
                splittable: body.splittable ?? false),
            by: try principal(caller))
        return try json(DTOMapping.task(task), status: 201)
    }

    func updateTask(_ id: String, _ request: APIRequest, _ caller: Caller) throws -> APIResponse {
        let body = try decode(TaskPatchRequest.self, request)
        let principal = try principal(caller)
        let taskID = TaskID(id)
        guard let current = try application.record(LisaTask.self, id: taskID) else {
            throw APIFailure.notFound("the task")
        }
        guard current.revision.value == body.expectedRevision else {
            throw APIFailure.conflict("the task changed since it was read", currentRevision: current.revision.value)
        }
        var task = current
        let correction = TaskCorrection(
            title: body.title, notes: body.notes,
            priority: body.priority.flatMap { TaskPriority(rawValue: $0.rawValue) },
            deadline: try Self.deadline(body.deadline, field: "deadline"), clearDeadline: body.clearDeadline ?? false,
            estimatedMinutes: body.estimatedMinutes,
            confirmation: body.confirmation.flatMap { Confirmation(rawValue: $0.rawValue) })
        if correction != TaskCorrection() {
            task = try application.correctTask(taskID, expectedRevision: task.revision, correction, by: principal)
        }
        if let status = body.status.flatMap({ TaskStatus(rawValue: $0.rawValue) }), status != task.status {
            task = try application.setTaskStatus(taskID, to: status, expectedRevision: task.revision, by: principal)
        }
        return try json(DTOMapping.task(task))
    }

    func listIdeas(_ request: APIRequest) throws -> APIResponse {
        var query = RecordQuery.all
        if let lifecycles = try values(request, "lifecycle", { IdeaLifecycle(rawValue: $0) }) {
            query = query.filter("lifecycle", in: lifecycles.map { .text($0.rawValue) })
        }
        let page = try application.page(Idea.self, query, limit: try pageLimit(request), after: try cursor(request))
        return try json(Page(items: page.items.map(DTOMapping.idea), nextCursor: page.nextCursor))
    }

    func updateIdea(_ id: String, _ request: APIRequest, _ caller: Caller) throws -> APIResponse {
        let body = try decode(IdeaPatchRequest.self, request)
        let principal = try principal(caller)
        let ideaID = IdeaID(id)
        guard let current = try application.record(Idea.self, id: ideaID) else { throw APIFailure.notFound("the idea") }
        guard current.revision.value == body.expectedRevision else {
            throw APIFailure.conflict("the idea changed since it was read", currentRevision: current.revision.value)
        }
        var idea = current
        let edit = IdeaEdit(
            summary: body.summary, tags: body.tags, notes: body.notes,
            priority: body.priority.flatMap { TaskPriority(rawValue: $0.rawValue) },
            estimatedMinutes: body.estimatedMinutes,
            deadline: try Self.deadline(body.deadline, field: "deadline"), clearDeadline: body.clearDeadline ?? false)
        if edit != IdeaEdit() {
            idea = try application.editIdea(ideaID, expectedRevision: idea.revision, edit, by: principal)
        }
        if let lifecycle = body.lifecycle.flatMap({ IdeaLifecycle(rawValue: $0.rawValue) }), lifecycle != idea.lifecycle
        {
            idea = try application.moveIdea(ideaID, to: lifecycle, expectedRevision: idea.revision, by: principal)
        }
        return try json(DTOMapping.idea(idea))
    }

    func capture(_ request: APIRequest, _ caller: Caller, requestID: String?) throws -> APIResponse {
        let body = try decode(CaptureRequestDTO.self, request)
        guard let kind = CaptureKind(rawValue: body.kind.rawValue),
            let channel = CaptureChannel(rawValue: body.channel.rawValue)
        else { throw APIFailure.invalid("unknown capture kind or channel") }
        let result = try application.capture(
            CaptureRequest(
                kind: kind, text: body.text, url: body.url, title: body.title, channel: channel, requestID: requestID),
            by: try principal(caller))
        return try json(DTOMapping.capture(result.capture, created: result.created), status: result.created ? 201 : 200)
    }
}
