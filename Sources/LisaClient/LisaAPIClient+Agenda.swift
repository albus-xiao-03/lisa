// Agenda routes of the typed client: health, the rundown and its plan-block actions, the brief and its regeneration.

import Foundation
import LisaAPIContract

extension LisaAPIClient {
    /// `GET /v1/health`: runtime health, without secrets or private content.
    public func health() async throws(ClientError) -> HealthDTO {
        try await call(.health, returning: HealthDTO.self)
    }

    /// `GET /v1/rundown`: the rundown for `date` (`YYYY-MM-DD`), or for the host's current date.
    public func rundown(date: String? = nil) async throws(ClientError) -> RundownDTO {
        try await call(.rundown, query: RequestQuery.localDate(date), returning: RundownDTO.self)
    }

    /// `POST /v1/plans/{planID}/blocks/{blockID}/actions`: accepts, locks, rejects, completes, defers or moves a block of
    /// the plan revision the owner saw (a move carries `start` and `end`). Returns the plan after the action.
    public func planBlockAction(
        planID: String, blockID: String, _ request: PlanBlockActionRequest, requestID: String? = nil
    ) async throws(ClientError) -> RundownDTO {
        try await call(
            .planBlockAction(planID: planID, blockID: blockID), body: encode(request), requestID: requestID,
            returning: RundownDTO.self)
    }

    /// `GET /v1/brief`: the brief for `date` (`YYYY-MM-DD`), or for the host's current date.
    public func brief(date: String? = nil) async throws(ClientError) -> BriefDTO {
        try await call(.brief, query: RequestQuery.localDate(date), returning: BriefDTO.self)
    }

    /// `POST /v1/briefs/regenerate`: regenerates the brief for `date`, or today's. A failed regeneration keeps the
    /// last good content and reports the failure in the returned brief.
    public func regenerateBrief(date: String? = nil, requestID: String? = nil) async throws(ClientError) -> BriefDTO {
        if let date { try RequestQuery.checkLocalDate(date) }
        return try await call(
            .regenerateBrief, body: encode(RegenerateBriefRequest(date: date)), requestID: requestID,
            returning: BriefDTO.self)
    }
}
