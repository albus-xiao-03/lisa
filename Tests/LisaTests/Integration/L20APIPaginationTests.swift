// Integration tests for L20, pagination (API-03; D-35), through the real router in process as docs/API.md documents
// it: pages are ordered by record identifier, each `nextCursor` continues exactly where its page ended and the last
// page has none; pages stay stable across inserts (nothing is repeated or skipped); `limit` defaults to 50 and
// accepts 1–200; filters page through the matching records only. Records are synthetic.

import Foundation
import LisaAPIContract
import LisaApplication
import LisaClient
import LisaDomain
import LisaHost
import LisaOwnerData
import Testing

@Suite("L20 — API pagination", .tags(.integration))
struct L20APIPaginationTests {
    private let start = TestTime.instant("2026-11-16T10:00", in: TestTime.newYork)

    /// Every page of tasks with `status`, following the cursors, with at most `limit` items per page.
    private func allPages(
        _ client: LisaAPIClient, status: TaskStatusValue? = nil, limit: Int
    ) async throws -> [Page<TaskDTO>] {
        var pages: [Page<TaskDTO>] = []
        var cursor: String?
        repeat {
            let page = try await client.tasks(status: status, limit: limit, cursor: cursor)
            pages.append(page)
            cursor = page.nextCursor
        } while cursor != nil && pages.count < 100
        return pages
    }

    private func createTasks(_ count: Int, in host: LisaHost, prefix: String) throws -> [LisaTask] {
        try (1...count).map { index in
            try host.application.createTask(TaskDraft(title: "\(prefix) \(index)"), by: .localOwner)
        }
    }

    @Test("Pages follow the record identifier, cursors continue where a page ended, and the last page has no cursor")
    func pagesFollowTheIdentifier() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            try await phone.pair(codeFrom: OwnerClient.inProcess(host))
            let created = try createTasks(7, in: host, prefix: "Synthetic chore")

            let pages = try await allPages(phone.client, limit: 3)
            #expect(pages.map(\.items.count) == [3, 3, 1])
            #expect(pages.last?.nextCursor == nil)
            for page in pages.dropLast() {
                #expect(page.nextCursor == page.items.last?.id)
            }
            let ids = pages.flatMap(\.items).map(\.id)
            #expect(ids == created.map(\.id.rawValue).sorted())
            #expect(Set(ids).count == 7)
            host.close()
        }
    }

    @Test("Pages stay stable across inserts: nothing is repeated or skipped")
    func pagesStayStableAcrossInserts() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let client = OwnerClient.inProcess(host)
            let original = try createTasks(6, in: host, prefix: "Synthetic errand")

            let first = try await client.tasks(limit: 3)
            let cursor = try #require(first.nextCursor)
            let inserted = try createTasks(8, in: host, prefix: "Synthetic insert")
            var rest: [TaskDTO] = []
            var next: String? = cursor
            while let current = next {
                let page = try await client.tasks(limit: 3, cursor: current)
                rest += page.items
                next = page.nextCursor
            }
            let seen = first.items.map(\.id) + rest.map(\.id)
            #expect(Set(seen).count == seen.count)
            #expect(rest.allSatisfy { $0.id > cursor })
            #expect(Set(original.map(\.id.rawValue)).isSubset(of: Set(seen)))
            let expectedLater = inserted.map(\.id.rawValue).filter { $0 > cursor }
            #expect(Set(expectedLater).isSubset(of: Set(rest.map(\.id))))
            #expect(rest.map(\.id) == rest.map(\.id).sorted())
            host.close()
        }
    }

    @Test("limit defaults to 50 and accepts 1 to 200")
    func limitDefaultsAndBounds() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            for index in 1...205 {
                _ = try host.application.capture(
                    CaptureRequest(kind: .idea, text: "Synthetic idea \(index)", channel: .api), by: .localOwner)
            }
            let owner = host.ownerTransport
            let standard = try APIExchange.decode(
                Page<IdeaDTO>.self, try await owner.send(APIExchange.request(.listIdeas)))
            #expect(standard.items.count == 50)
            #expect(standard.nextCursor == standard.items.last?.id)
            let largest = try APIExchange.decode(
                Page<IdeaDTO>.self, try await owner.send(APIExchange.request(.listIdeas, query: ["limit": "200"])))
            #expect(largest.items.count == 200)
            let remainder = try APIExchange.decode(
                Page<IdeaDTO>.self,
                try await owner.send(
                    APIExchange.request(
                        .listIdeas, query: ["limit": "200", "cursor": try #require(largest.nextCursor)])))
            #expect(remainder.items.count == 5)
            #expect(remainder.nextCursor == nil)
            let smallest = try APIExchange.decode(
                Page<IdeaDTO>.self, try await owner.send(APIExchange.request(.listIdeas, query: ["limit": "1"])))
            #expect(smallest.items.count == 1)
            for limit in ["0", "201", "-1"] {
                APIExchange.expectError(
                    try await owner.send(APIExchange.request(.listIdeas, query: ["limit": limit])), .invalidRequest,
                    field: "limit")
            }
            host.close()
        }
    }

    @Test("A filter pages through the matching records only")
    func filtersPageThroughMatches() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let client = OwnerClient.inProcess(host)
            let tasks = try createTasks(9, in: host, prefix: "Synthetic filing")
            let completed = try tasks.enumerated().filter { $0.offset % 3 == 0 }.map { _, task in
                try host.application.setTaskStatus(task.id, to: .completed, expectedRevision: nil, by: .localOwner)
            }
            let pages = try await allPages(client, status: .completed, limit: 2)
            #expect(pages.map(\.items.count) == [2, 1])
            let ids = pages.flatMap(\.items).map(\.id)
            #expect(ids == completed.map(\.id.rawValue).sorted())
            #expect(pages.flatMap(\.items).allSatisfy { $0.status == .completed })
            let open = try await allPages(client, status: .open, limit: 4)
            #expect(open.flatMap(\.items).count == 6)
            host.close()
        }
    }
}
