// Handlers for the rundown, plan blocks, briefs, event proposals, reminders and notification actions.

import Foundation
import LisaAPIContract
import LisaAgenda
import LisaApplication
import LisaDomain
import LisaPorts
import LisaTime

extension APIRouter {
    func rundown(_ request: APIRequest) throws -> APIResponse {
        let date = try localDate(request)
        guard let plan = try application.rundown(for: date) else {
            throw APIFailure.notFound("a rundown for \(date.iso)")
        }
        return try json(DTOMapping.rundown(plan))
    }

    func planBlockAction(_ planID: String, _ blockID: String, _ request: APIRequest, _ caller: Caller) throws
        -> APIResponse
    {
        let body = try decode(PlanBlockActionRequest.self, request)
        if body.action == .move { return try movePlanBlock(planID, blockID, body, caller) }
        if body.start != nil || body.end != nil {
            throw APIFailure.invalid(
                "start and end are given only to move a block", field: body.start != nil ? "start" : "end")
        }
        guard let action = PlanBlockAction(rawValue: body.action.rawValue) else {
            throw APIFailure.invalid("unknown action")
        }
        let plan = try application.actOnPlanBlock(
            action, planID: PlanID(planID), blockID: blockID, expectedRevision: Revision(body.expectedRevision),
            by: try principal(caller))
        return try json(DTOMapping.rundown(plan))
    }

    /// Moves a block to `start`–`end` (PLAN-04). A move that breaks a rule is a validation failure (400) with the
    /// reason, naming `start` or `end` when one of them is at fault; nothing changes. The answer is the plan as stored
    /// after the move, the replanning of its day and the reminder changes that follow it (D-47).
    func movePlanBlock(_ planID: String, _ blockID: String, _ body: PlanBlockActionRequest, _ caller: Caller) throws
        -> APIResponse
    {
        guard let start = body.start else {
            throw APIFailure.invalid("start is required to move a block", field: "start")
        }
        guard let end = body.end else { throw APIFailure.invalid("end is required to move a block", field: "end") }
        let moved = try application.movePlanBlock(
            planID: PlanID(planID), blockID: blockID, start: start, end: end,
            expectedRevision: Revision(body.expectedRevision), by: try principal(caller))
        return try json(DTOMapping.rundown(moved))
    }

    func brief(_ request: APIRequest) throws -> APIResponse {
        let date = try localDate(request)
        guard let brief = try application.brief(for: date) else { throw APIFailure.notFound("a brief for \(date.iso)") }
        return try json(DTOMapping.brief(brief))
    }

    func regenerateBrief(_ request: APIRequest, _ caller: Caller) throws -> APIResponse {
        _ = try principal(caller)
        let body = request.body.map { _ in try? decode(RegenerateBriefRequest.self, request) } ?? nil
        var date = try application.today()
        if let text = body?.date {
            guard APIDates.isLocalDate(text), let parsed = LocalDate(iso: text) else {
                throw APIFailure.invalid("date must look like 2026-11-16", field: "date")
            }
            date = parsed
        }
        return try json(DTOMapping.brief(try application.services.briefs.generate(for: date)))
    }

    func listProposals(_ request: APIRequest) throws -> APIResponse {
        var query = RecordQuery.all
        if let states = try values(request, "state", { Self.proposalStates.contains($0) ? $0 : nil }) {
            query = query.filter("match_state", in: states.map { .text($0) })
        }
        let page = try application.page(
            EventProposal.self, query, limit: try pageLimit(request), after: try cursor(request))
        return try json(Page(items: page.items.map(DTOMapping.proposal), nextCursor: page.nextCursor))
    }

    static let proposalStates: Set<String> = [
        "needsClarification", "notFound", "possibleMatch", "matched", "dismissed", "ownerReportsAdded",
    ]

    func proposalAction(_ id: String, _ request: APIRequest, _ caller: Caller) throws -> APIResponse {
        let body = try decode(ProposalActionRequest.self, request)
        let action: ProposalAction
        switch body.action {
        case .confirmMatch:
            guard let occurrence = body.occurrenceID, !occurrence.isEmpty else {
                throw APIFailure.invalid("confirmMatch needs occurrenceID", field: "occurrenceID")
            }
            action = .confirmMatch(OccurrenceID(occurrence))
        case .dismiss:
            action = .dismiss
        case .correct:
            action = .correct(title: body.title, timing: try body.timing.map(Self.timing), location: body.location)
        case .reportAdded:
            action = .reportAdded
        }
        let proposal = try application.reviewProposal(
            action, ProposalID(id), expectedRevision: Revision(body.expectedRevision), by: try principal(caller))
        return try json(DTOMapping.proposal(proposal))
    }

    static func timing(_ dto: ProposedTimingDTO) throws -> ProposedTiming {
        if let start = dto.start {
            if let end = dto.end, end < start {
                throw APIFailure.invalid("timing.end is before timing.start", field: "timing.end")
            }
            var zone: TimeZoneID?
            if let identifier = dto.zone {
                guard let parsed = TimeZoneID(identifier) else {
                    throw APIFailure.invalid("unknown time zone", field: "timing.zone")
                }
                zone = parsed
            }
            return .timed(start: start, end: dto.end, zone: zone)
        }
        if let text = dto.date {
            guard APIDates.isLocalDate(text), let date = LocalDate(iso: text) else {
                throw APIFailure.invalid("timing.date must look like 2026-11-16", field: "timing.date")
            }
            return .dateOnly(date)
        }
        return .unknown
    }

    func proposalCalendarFile(_ id: String) throws -> APIResponse {
        let text = try application.services.proposals.exportICS(ProposalID(id))
        return APIResponse(
            status: 200, headers: Self.headers(contentType: "text/calendar; charset=utf-8"), body: Data(text.utf8))
    }

    func listReminders(_ request: APIRequest) throws -> APIResponse {
        let states =
            try values(request, "state", { Self.reminderStates.contains($0) ? $0 : nil })
            ?? ["scheduled", "delivered", "snoozed"]
        let query = RecordQuery.all.filter("state", in: states.map { .text($0) })
        let page = try application.page(Reminder.self, query, limit: try pageLimit(request), after: try cursor(request))
        return try json(Page(items: page.items.map(DTOMapping.reminder), nextCursor: page.nextCursor))
    }

    static let reminderStates: Set<String> = [
        "scheduled", "delivered", "acknowledged", "snoozed", "dismissed", "completed", "cancelled", "suppressed",
    ]

    func reminderAction(_ id: String, _ request: APIRequest, _ caller: Caller) throws -> APIResponse {
        let body = try decode(ReminderActionRequest.self, request)
        guard let action = ReminderAction(rawValue: body.action.rawValue) else {
            throw APIFailure.invalid("unknown action")
        }
        let reminder = try application.actOnReminder(
            action, ReminderID(id), expectedRevision: body.expectedRevision.map(Revision.init),
            by: try principal(caller))
        return try json(DTOMapping.reminder(reminder))
    }

    func notificationAction(_ id: String, _ request: APIRequest, _ caller: Caller) throws -> APIResponse {
        let body = try decode(NotificationActionRequest.self, request)
        guard let action = ReminderAction(rawValue: body.action.rawValue) else {
            throw APIFailure.invalid("unknown action")
        }
        let notificationID = NotificationID(id)
        guard let intent = try application.record(NotificationIntent.self, id: notificationID) else {
            throw APIFailure.notFound("the notification")
        }
        try application.actOnNotification(action, notificationID: notificationID, by: try principal(caller))
        var reminder: ReminderDTO?
        if case .reminder(let reminderID) = intent.subject {
            reminder = try application.record(Reminder.self, id: reminderID).map(DTOMapping.reminder)
        }
        return try json(NotificationActionResult(notificationID: id, action: body.action, reminder: reminder))
    }
}
