// Integration tests for L13, the brief's full view (BRIEF-04, with BRIEF-01 and BRIEF-02; D-18, docs/API.md): through
// the API, as the owner's client and a paired companion read it, a brief cut to a small target length returns the
// left-out lower-priority items in `omittedItems`, each exactly as the brief within its target shows it, in priority
// order and counted by `omittedCount`; every commitment, deadline and warning stays in `items`; and a brief within its
// target, including one regenerated after the cut, leaves nothing out. The day is built through the production host: a
// calendar file and a missing one read by configured sources, and tasks, shared stories and the length preference set
// through the API. Nothing reaches any network.

import Foundation
import LisaAPIContract
import LisaApplication
import LisaClient
import LisaDomain
import LisaHost
import Testing

@Suite("L13 — Brief full view", .tags(.integration))
struct L13BriefFullViewTests {
    private let start = TestTime.instant("2026-11-16T08:00", in: TestTime.newYork)
    private static let date = "2026-11-16"
    /// The shared stories that match the owner's interest: the brief's only lower-priority items.
    private static let storyCount = 5

    /// The words of the items' readable lines, as the target length counts them.
    private func words(_ items: [BriefItemDTO]) -> Int {
        items.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    /// Sets the owner's brief length preference through the API; `nil` removes it, so the default applies again.
    private func setTargetWords(_ target: Int?, _ client: LisaAPIClient, requestID: String) async throws {
        let change = PreferenceChange(key: "brief.targetWords", value: target.map { .number(Double($0)) })
        _ = try await client.updatePreferences(PreferencesPatchRequest(changes: [change]), requestID: requestID)
    }

    /// The day's three commitments, in a calendar file the configured source reads.
    private static let events = [
        SyntheticEvent(
            uid: "standup@calendar.example.com", title: "Synthetic team standup", start: "2026-11-16T09:00",
            end: "2026-11-16T09:30"),
        SyntheticEvent(
            uid: "review@calendar.example.com", title: "Synthetic design review", start: "2026-11-16T11:00",
            end: "2026-11-16T12:00"),
        SyntheticEvent(
            uid: "dentist@calendar.example.com", title: "Synthetic dentist appointment", start: "2026-11-16T14:00",
            end: "2026-11-16T15:00"),
    ]

    @Test("Cut to a small target, the full view holds each left-out item whole; within the target, nothing is left out")
    func fullViewHoldsTheLeftOutItems() async throws {
        try await ScratchDirectory.with { scratch in
            let calendar = scratch.path("work.ics")
            try SourceFiles.write(SyntheticEvent.calendar(Self.events), to: calendar, modifiedAt: start)
            var owner = TestHost.owner()
            owner.newsInterests = ["transit"]
            let testHost = TestHost(
                scratch: scratch, now: start, owner: owner,
                sources: [
                    SourceFiles.calendarSource(calendar, key: "work-calendar", name: "Synthetic work calendar"),
                    // Its file is never written, so its refresh fails: a warning the brief must keep.
                    SourceFiles.calendarSource(
                        scratch.path("school.ics"), key: "school-calendar", name: "Synthetic school calendar"),
                ])
            let host = try testHost.open()
            defer { host.close() }
            let client = OwnerClient.inProcess(host)

            // Two deadlines and five shared stories through the API, then one cycle reads both calendars.
            let report = try await client.createTask(
                TaskCreateRequest(
                    title: "Submit the synthetic grant report", priority: .high,
                    deadline: DeadlineDTO(
                        instant: TestTime.instant("2026-11-16T17:00", in: TestTime.newYork), zone: "America/New_York")),
                requestID: "full-view-task-0001")
            let permit = try await client.createTask(
                TaskCreateRequest(
                    title: "Renew the synthetic parking permit", deadline: DeadlineDTO(date: "2026-11-17")),
                requestID: "full-view-task-0002")
            for number in 1...Self.storyCount {
                _ = try await client.capture(
                    CaptureRequestDTO(
                        kind: .text, text: "Synthetic notes on transit story \(number).",
                        title: "Synthetic transit story \(number)", channel: .nativeApp),
                    requestID: "full-view-story-000\(number)")
            }
            _ = await host.runtime.runOnce()

            // With the default target the day fits: nothing is left out, and the API says so.
            let full = try await client.regenerateBrief(date: Self.date, requestID: "full-view-brief-0001")
            #expect(full.omittedCount == 0)
            #expect(full.omittedItems == [])
            #expect(!full.text.contains("available in the full view"))
            let material = full.items.filter(\.material)
            let stories = full.items.filter { $0.section == "news" }
            #expect(stories.count == Self.storyCount)
            #expect(full.items.filter { !$0.material } == stories)
            #expect(full.items.filter { $0.section == "commitments" && $0.material }.count == Self.events.count)
            for task in [report.id, permit.id] {
                #expect(
                    material.contains { item in
                        item.section == "deadlines" && item.references.contains { $0.recordID == task }
                    })
            }
            #expect(
                material.contains {
                    $0.section == "sourceHealth" && $0.text.contains("Could not check Synthetic school calendar")
                })

            // The owner shortens the brief through the API to its material lines and the two highest-ranked stories.
            let target = words(material) + words(Array(stories.prefix(2)))
            #expect(target >= 50)
            #expect(target < words(full.items))
            try await setTargetWords(target, client, requestID: "full-view-length-0001")
            let short = try await client.regenerateBrief(date: Self.date, requestID: "full-view-brief-0002")
            let omitted = try #require(short.omittedItems)

            // The full view holds exactly what the brief left out, counted, each item as the brief within its target
            // showed it: nothing is lost, changed or shown twice.
            #expect(short.version > full.version)
            #expect(short.omittedCount == omitted.count)
            #expect(omitted.count == Self.storyCount - 2)
            #expect(short.items.count + omitted.count == full.items.count)
            #expect(Set(short.items).union(omitted) == Set(full.items))
            #expect(Set(short.items).isDisjoint(with: omitted))
            // Lower priorities go first: the brief keeps the two highest-ranked stories, and the full view holds the
            // others in rank order, each still leading to its record.
            #expect(short.items.filter { $0.section == "news" } == Array(stories.prefix(2)))
            #expect(omitted == Array(stories.dropFirst(2)))
            for item in omitted {
                #expect(item.references.contains { $0.recordKind == "news" })
            }
            // Every commitment, deadline and warning stays in the brief, never in the full view.
            #expect(Set(material).isSubset(of: Set(short.items)))
            #expect(omitted.allSatisfy { !$0.material })
            #expect(!omitted.contains { ["commitments", "deadlines", "sourceHealth"].contains($0.section) })
            // The brief says how many items the full view holds, and shows none of them in either version.
            #expect(short.text.hasSuffix("\(omitted.count) lower-priority items are available in the full view."))
            for item in omitted {
                #expect(!short.text.contains(item.text))
                #expect(!short.spokenText.contains(item.spokenText))
            }

            // Reading the brief again returns the same full view, and a paired companion gets it too, under the names
            // docs/API.md gives.
            let read = try await client.brief(date: Self.date)
            #expect(read.version == short.version)
            #expect(read.items == short.items)
            #expect(read.omittedItems == omitted)
            let app = host.application
            let code = try app.createPairingCode(by: .localOwner)
            let phone = try app.pairDevice(
                code: code.code, installationID: SyntheticDevice.randomHex(bytes: 16), name: "Synthetic iPhone",
                deviceClass: .iPhone, appBundleID: SyntheticDevice.companionBundleID, environment: .development)
            let response = await host.router.handle(
                APIExchange.request(.brief, query: ["date": Self.date], credential: phone.credential),
                origin: .authenticateHeaders(isLoopback: true))
            #expect(response.status == 200)
            #expect(APIExchange.keys(response).isSuperset(of: ["items", "omittedItems", "omittedCount"]))
            let companion = try APIExchange.decode(BriefDTO.self, response)
            #expect(companion.version == short.version)
            #expect(companion.items == short.items)
            #expect(companion.omittedItems == omitted)
            #expect(companion.omittedCount == omitted.count)

            // With the preference removed, the brief regenerated within the default target leaves nothing out again.
            try await setTargetWords(nil, client, requestID: "full-view-length-0002")
            let restored = try await client.regenerateBrief(date: Self.date, requestID: "full-view-brief-0003")
            #expect(restored.omittedCount == 0)
            #expect(restored.omittedItems == [])
            #expect(restored.items == full.items)
            #expect(!restored.text.contains("available in the full view"))
        }
    }
}
