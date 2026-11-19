// Work routes of the typed client: captures, tasks and ideas.

import Foundation
import LisaAPIContract

extension LisaAPIClient {
    /// `POST /v1/captures`: saves an idea, text or link. Retrying with the same request ID returns the original capture
    /// with `created == false` instead of capturing it again.
    public func capture(_ request: CaptureRequestDTO, requestID: String? = nil) async throws(ClientError) -> CaptureDTO
    {
        try await call(.capture, body: encode(request), requestID: requestID, returning: CaptureDTO.self)
    }

    /// `POST /v1/captures/{id}/retrieve`: asks the host to read the page behind a link the owner captured. A page is
    /// read once: retrying with the same request ID returns the recorded answer, and asking again with another ID after
    /// the page was read is a conflict (409), as is asking for an idea, text or an Apple News share. A page that cannot
    /// be read for a lasting reason returns `retrieved == false` with the reason; a temporary failure is a 503 with
    /// `retryAfterSeconds`, to retry with the same request ID.
    public func retrieveCapturedPage(
        captureID: String, requestID: String? = nil
    ) async throws(ClientError) -> CaptureRetrievalDTO {
        try await call(.retrieveCapture(id: captureID), requestID: requestID, returning: CaptureRetrievalDTO.self)
    }

    /// `GET /v1/tasks`: a page of tasks, optionally only those with `status`.
    public func tasks(
        status: TaskStatusValue? = nil, limit: Int? = nil, cursor: String? = nil
    ) async throws(ClientError) -> Page<TaskDTO> {
        var query = try RequestQuery.page(limit: limit, cursor: cursor)
        if let status { query[RequestQuery.statusParameter] = status.rawValue }
        return try await call(.listTasks, query: query, returning: Page<TaskDTO>.self)
    }

    /// `GET /v1/tasks/{id}`.
    public func task(id: String) async throws(ClientError) -> TaskDTO {
        try await call(.task(id: id), returning: TaskDTO.self)
    }

    /// `POST /v1/tasks`: creates a confirmed manual task.
    public func createTask(_ request: TaskCreateRequest, requestID: String? = nil) async throws(ClientError) -> TaskDTO
    {
        try await call(.createTask, body: encode(request), requestID: requestID, returning: TaskDTO.self)
    }

    /// `PATCH /v1/tasks/{id}`: changes a task the client last saw at `request.expectedRevision`; a newer revision on
    /// the host is a conflict (409).
    public func updateTask(
        id: String, _ request: TaskPatchRequest, requestID: String? = nil
    ) async throws(ClientError) -> TaskDTO {
        try await call(.updateTask(id: id), body: encode(request), requestID: requestID, returning: TaskDTO.self)
    }

    /// `GET /v1/ideas`: a page of ideas, optionally only those in `lifecycle`.
    public func ideas(
        lifecycle: IdeaLifecycleValue? = nil, limit: Int? = nil, cursor: String? = nil
    ) async throws(ClientError) -> Page<IdeaDTO> {
        var query = try RequestQuery.page(limit: limit, cursor: cursor)
        if let lifecycle { query[RequestQuery.lifecycleParameter] = lifecycle.rawValue }
        return try await call(.listIdeas, query: query, returning: Page<IdeaDTO>.self)
    }

    /// `PATCH /v1/ideas/{id}`: edits, schedules or archives an idea at `request.expectedRevision`.
    public func updateIdea(
        id: String, _ request: IdeaPatchRequest, requestID: String? = nil
    ) async throws(ClientError) -> IdeaDTO {
        try await call(.updateIdea(id: id), body: encode(request), requestID: requestID, returning: IdeaDTO.self)
    }
}
