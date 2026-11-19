// Review routes of the typed client: event proposals, their calendar files, reminders and notification actions.

import Foundation
import LisaAPIContract

extension LisaAPIClient {
    /// `GET /v1/event-proposals`: a page of event proposals, optionally only those whose match state is one of
    /// `states` (such as `needsClarification` or `possibleMatch`).
    public func proposals(
        states: [String] = [], limit: Int? = nil, cursor: String? = nil
    ) async throws(ClientError) -> Page<EventProposalDTO> {
        let query = try RequestQuery.page(limit: limit, cursor: cursor).merging(RequestQuery.states(states)) { $1 }
        return try await call(.listProposals, query: query, returning: Page<EventProposalDTO>.self)
    }

    /// `POST /v1/event-proposals/{id}/actions`: confirms a match, dismisses, corrects or reports a proposal as added.
    /// Returns the proposal after the action.
    public func proposalAction(
        id: String, _ request: ProposalActionRequest, requestID: String? = nil
    ) async throws(ClientError) -> EventProposalDTO {
        try await call(
            .proposalAction(id: id), body: encode(request), requestID: requestID, returning: EventProposalDTO.self)
    }

    /// `GET /v1/event-proposals/{id}/calendar-file`: the proposal as iCalendar (`.ics`) text, for the owner to add to
    /// a calendar.
    public func proposalCalendarFile(id: String) async throws(ClientError) -> String {
        let response = try await send(.proposalCalendarFile(id: id))
        return try ResponseInterpreter.text(from: response)
    }

    /// `GET /v1/reminders`: a page of reminders whose state is one of `states` (such as `delivered`), or in the host's
    /// default states when `states` is empty.
    public func reminders(
        states: [String] = [], limit: Int? = nil, cursor: String? = nil
    ) async throws(ClientError) -> Page<ReminderDTO> {
        let query = try RequestQuery.page(limit: limit, cursor: cursor).merging(RequestQuery.states(states)) { $1 }
        return try await call(.listReminders, query: query, returning: Page<ReminderDTO>.self)
    }

    /// `POST /v1/reminders/{id}/actions`: acknowledges, snoozes, dismisses or completes a reminder. Returns the
    /// reminder after the action.
    public func reminderAction(
        id: String, _ request: ReminderActionRequest, requestID: String? = nil
    ) async throws(ClientError) -> ReminderDTO {
        try await call(
            .reminderAction(id: id), body: encode(request), requestID: requestID, returning: ReminderDTO.self)
    }

    /// `POST /v1/notifications/{id}/actions`: an action chosen on a delivered notification, identified by the
    /// payload's notification ID. `NotificationActionHandler` queues these durably with deterministic request IDs.
    public func notificationAction(
        id: String, _ request: NotificationActionRequest, requestID: String? = nil
    ) async throws(ClientError) -> NotificationActionResult {
        try await call(
            .notificationAction(id: id), body: encode(request), requestID: requestID,
            returning: NotificationActionResult.self)
    }
}
