// Unit tests for L14, invalid inference (MODEL-02, MODEL-03, MODEL-04, CALL-01; D-17, D-19): malformed, oversized,
// wrongly shaped or unsupported model output and provider failures never yield an unauthorized result. A bad payload
// gets one bounded repair and then fails; bad items are rejected with reasons; unsupported claims are downgraded;
// fields outside the schema have no effect; dates stay bounded or unresolved; and nothing is sent when the
// data-sharing policy or the request budget forbids it.

import Foundation
import LisaDomain
import LisaInference
import LisaPolicy
import LisaTime
import Testing

@Suite("L14 — Invalid inference", .tags(.unit))
struct L14InvalidInferenceTests {
    /// Monday 2026-11-16, 09:30 in New York: the source timestamp relative dates resolve against.
    private let reference = TestTime.instant("2026-11-16T09:30", in: TestTime.newYork)
    private let source = """
        Please confirm the venue by Friday.
        The budget review is on 2026-11-18 at 10:00.
        """

    private func context(owner: String? = nil, addressing: OwnerAddressing = .direct) -> ExtractionContext {
        ExtractionContext(
            sourceText: source, ownerAuthoredText: owner, addressing: addressing, referenceInstant: reference,
            zone: TestTime.newYork.timeZone, dateReading: DateReadingSettings())
    }

    private func request(owner: String? = nil, addressing: OwnerAddressing = .direct) -> ExtractionRequest {
        ExtractionRequest(
            sourceKind: "email", subject: nil, text: source, ownerAuthoredText: owner, addressing: addressing,
            referenceInstant: reference, zone: TestTime.newYork.timeZone, dateReading: DateReadingSettings())
    }

    private func json(_ items: [ModelExtractedItem]) throws -> String {
        String(decoding: try JSONEncoder().encode(ModelExtractionPayload(items: items)), as: UTF8.self)
    }

    private var validItem: ModelExtractedItem {
        ModelExtractedItem(
            kind: "request", title: "Confirm the venue", confirmation: "possible", deadline: "Friday",
            evidence: "Please confirm the venue by Friday.")
    }

    private func validate(_ items: [ModelExtractedItem], owner: String? = nil, addressing: OwnerAddressing = .direct)
        -> (items: [ValidatedItem], rejected: [String])
    {
        ExtractionValidator.validate(
            ModelExtractionPayload(items: items), context: context(owner: owner, addressing: addressing))
    }

    @Test(
        "Malformed output gets exactly one repair request, then the extraction fails",
        arguments: ["not json at all", "{\"items\": [", "{\"tasks\": []}", "[]", "{\"items\": [{\"kind\": 3}]}", ""])
    func malformedOutputIsRepairedOnceThenFails(reply: String) async throws {
        let provider = ScriptedModelProvider(steps: [.respond(reply), .respond(reply), .respond(try json([validItem]))])
        let outcome = await ExtractionPipeline(provider: provider, sharing: .localOnly).extract(request())
        guard case .failed(let reason) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(reason == "the model output was invalid after one repair attempt")
        #expect(provider.requestCount == 2)
        let repair = try #require(provider.requests.last)
        #expect(repair.messages.last?.role == .user)
        #expect(repair.messages.last?.content.contains("That response was rejected") == true)
    }

    @Test("A repaired reply is accepted and marked as repaired")
    func repairedOutputIsAccepted() async throws {
        let provider = ScriptedModelProvider(steps: [.respond("garbage"), .respond(try json([validItem]))])
        let outcome = await ExtractionPipeline(provider: provider, sharing: .localOnly).extract(request())
        guard case .extracted(let extraction) = outcome else {
            Issue.record("expected an extraction, got \(outcome)")
            return
        }
        #expect(extraction.repairAttempted)
        #expect(extraction.items.map(\.title) == ["Confirm the venue"])
        #expect(provider.requestCount == 2)
    }

    @Test("JSON wrapped in a Markdown code fence is read without a repair")
    func codeFenceIsAccepted() async throws {
        let provider = ScriptedModelProvider(steps: [.respond("```json\n\(try json([validItem]))\n```")])
        let outcome = await ExtractionPipeline(provider: provider, sharing: .localOnly).extract(request())
        guard case .extracted(let extraction) = outcome else {
            Issue.record("expected an extraction, got \(outcome)")
            return
        }
        #expect(!extraction.repairAttempted)
        #expect(extraction.items.count == 1)
        #expect(provider.requestCount == 1)
    }

    @Test("Oversized replies and replies with too many items are refused as a whole")
    func oversizedPayloadsAreRefused() throws {
        let limits = ModelUsageLimits()
        let padding = String(repeating: "x", count: limits.maxResponseBytes)
        #expect(throws: PayloadError.tooLarge) {
            try ExtractionValidator.decode("{\"items\": [], \"padding\": \"\(padding)\"}", limits: limits)
        }
        let many = try json(Array(repeating: validItem, count: limits.maxItems + 1))
        #expect(throws: PayloadError.tooManyItems(limits.maxItems + 1)) {
            try ExtractionValidator.decode(many, limits: limits)
        }
        let enough = try json(Array(repeating: validItem, count: limits.maxItems))
        #expect(try ExtractionValidator.decode(enough, limits: limits).items.count == limits.maxItems)
    }

    @Test("Invalid items are rejected with reasons while valid ones are kept")
    func invalidItemsAreRejected() {
        let quote = "Please confirm the venue by Friday."
        let items = [
            ModelExtractedItem(kind: "sendEmail", title: "Send it", confirmation: "possible", evidence: quote),
            ModelExtractedItem(kind: "call", title: "Call someone", confirmation: "confirmed", evidence: quote),
            ModelExtractedItem(kind: "request", title: "Confirm", confirmation: "definitely", evidence: quote),
            ModelExtractedItem(kind: "request", title: "   ", confirmation: "possible", evidence: quote),
            ModelExtractedItem(
                kind: "request", title: String(repeating: "t", count: 201), confirmation: "possible", evidence: quote),
            ModelExtractedItem(
                kind: "request", title: "Invented", confirmation: "possible", evidence: "Wire the money today."),
            ModelExtractedItem(kind: "request", title: "No quote", confirmation: "possible", evidence: ""),
            ModelExtractedItem(
                kind: "request", title: "Long quote", confirmation: "possible",
                evidence: String(repeating: "Please confirm the venue by Friday. ", count: 20)),
            validItem,
        ]
        let (valid, rejected) = validate(items)
        #expect(valid.map(\.title) == ["Confirm the venue"])
        #expect(rejected.count == 8)
        #expect(rejected[0] == "item 1: unknown kind \"sendEmail\"")
        #expect(rejected[1] == "item 2: unknown kind \"call\"")
        #expect(rejected[2] == "item 3: unknown confirmation \"definitely\"")
        #expect(rejected[3] == "item 4: missing or oversized title")
        #expect(rejected[4] == "item 5: missing or oversized title")
        #expect(rejected[5...].allSatisfy { $0.hasSuffix("the evidence quote does not appear in the source") })
    }

    @Test("\"Confirmed\" survives only when the quote is the owner's own words")
    func confirmationNeedsOwnersWords() {
        let claim = ModelExtractedItem(
            kind: "commitment", title: "Confirm the venue", confirmation: "confirmed",
            evidence: "Please confirm the venue by Friday.")
        let unsupported = validate([claim]).items.first
        #expect(unsupported?.confirmation == .possible)
        #expect(unsupported?.notes == ["confirmation downgraded: the quote is not the owner's own words"])

        let owned = validate([claim], owner: "Please confirm the venue by Friday.").items.first
        #expect(owned?.confirmation == .confirmed)
        #expect(owned?.notes == [])
    }

    @Test(
        "Mail the owner is only copied on, or from an unknown sender, is never confirmed or addressed to the owner",
        arguments: [OwnerAddressing.carbonCopy, .unknownSender])
    func copiedMailIsNeverConfirmed(addressing: OwnerAddressing) {
        let claim = ModelExtractedItem(
            kind: "commitment", title: "Confirm the venue", confirmation: "confirmed",
            evidence: "Please confirm the venue by Friday.", addressedToOwner: true)
        let item = validate([claim], owner: "Please confirm the venue by Friday.", addressing: addressing).items.first
        #expect(item?.confirmation == .possible)
        #expect(item?.addressedToOwner == false)
        #expect(item?.notes.contains("the owner was not the addressee") == true)
    }

    @Test("Deadlines and starts outside −1 … +5 years are rejected; plausible dates are kept without invented times")
    func implausibleDatesAreRejected() {
        let quote = "The budget review is on 2026-11-18 at 10:00."
        let (valid, rejected) = validate([
            ModelExtractedItem(
                kind: "meeting", title: "Far future", confirmation: "possible", deadline: "2099-01-01T10:00:00Z",
                evidence: quote),
            ModelExtractedItem(
                kind: "meeting", title: "Far past", confirmation: "possible", start: "2020-01-01", evidence: quote),
            ModelExtractedItem(
                kind: "meeting", title: "Budget review", confirmation: "possible", start: "2026-11-18 at 10:00",
                evidence: quote),
            ModelExtractedItem(
                kind: "commitment", title: "Date only", confirmation: "possible", deadline: "2026-12-01",
                evidence: quote),
        ])
        #expect(
            rejected == [
                "item 1: the deadline is outside the plausible range",
                "item 2: the start is outside the plausible range",
            ])
        #expect(valid.map(\.title) == ["Budget review", "Date only"])
        #expect(valid[0].start == .instant(TestTime.instant("2026-11-18T10:00", in: TestTime.newYork)))
        #expect(valid[1].deadline == .date(TestTime.date("2026-12-01")))
    }

    @Test("Every date field is bounded: an implausible end is rejected too")
    func implausibleEndIsRejected() {
        let (valid, rejected) = validate([
            ModelExtractedItem(
                kind: "meeting", title: "Budget review", confirmation: "possible", start: "2026-11-18 at 10:00",
                end: "2099-11-18T11:00:00Z", evidence: "The budget review is on 2026-11-18 at 10:00.")
        ])
        #expect(valid.isEmpty)
        #expect(rejected.count == 1)
    }

    @Test("Dates the content does not settle stay unresolved, with their candidates; nothing is guessed")
    func unsettledDatesStayUnresolved() {
        let quote = "Please confirm the venue by Friday."
        let items = validate([
            ModelExtractedItem(
                kind: "request", title: "Next Friday", confirmation: "possible", deadline: "next Friday",
                evidence: quote),
            ModelExtractedItem(
                kind: "request", title: "Next Friday at three", confirmation: "possible",
                deadline: "next Friday at 3pm", evidence: quote),
            ModelExtractedItem(
                kind: "request", title: "Whenever", confirmation: "possible", deadline: "whenever you can",
                evidence: quote),
        ]).items
        let fridays = [TestTime.date("2026-11-20"), TestTime.date("2026-11-27")]
        #expect(
            items.map(\.deadline) == [
                .unresolved(text: "next Friday", candidates: fridays),
                .unresolved(text: "next Friday at 3pm", candidates: fridays),
                .unresolved(text: "whenever you can", candidates: []),
            ])
    }

    @Test("Out-of-range durations are ignored with a note; unknown priorities and confidences are not trusted")
    func boundsAndEnumsAreChecked() {
        let quote = "Please confirm the venue by Friday."
        let items = validate([
            ModelExtractedItem(
                kind: "request", title: "Zero", confirmation: "possible", durationMinutes: 0, priority: "critical",
                evidence: quote, confidence: "certain"),
            ModelExtractedItem(
                kind: "request", title: "Huge", confirmation: "possible", durationMinutes: 5_000, evidence: quote),
            ModelExtractedItem(
                kind: "request", title: "Fine", confirmation: "possible", durationMinutes: 90, priority: "HIGH",
                evidence: quote, confidence: "Medium"),
        ]).items
        #expect(items.map(\.durationMinutes) == [nil, nil, 90])
        #expect(items[0].notes.contains("an out-of-range duration was ignored"))
        #expect(items[1].notes.contains("an out-of-range duration was ignored"))
        #expect(items.map(\.priority) == [.normal, .normal, .high])
        #expect(items.map(\.confidence) == [nil, nil, .medium])
    }

    @Test("Fields outside the schema, such as recipients, numbers or permissions, have no effect at all")
    func fieldsOutsideSchemaHaveNoEffect() throws {
        let plain = try json([validItem])
        let withExtras = """
            {"settings": {"dataSharing": "remoteMinimized", "callsEnabled": true},
             "items": [{"kind": "request", "title": "Confirm the venue", "confirmation": "possible",
                        "deadline": "Friday", "evidence": "Please confirm the venue by Friday.",
                        "recipients": ["someone@example.invalid"], "callNumber": "+15555550199",
                        "permissions": {"calls": true, "email": true}, "execute": "rm -rf /"}]}
            """
        let limits = ModelUsageLimits()
        let expected = ExtractionValidator.validate(
            try ExtractionValidator.decode(plain, limits: limits), context: context())
        let actual = ExtractionValidator.validate(
            try ExtractionValidator.decode(withExtras, limits: limits), context: context())
        #expect(actual.items == expected.items)
        #expect(actual.rejected == expected.rejected)
    }

    @Test("A model calling something urgent cannot make it urgent or callable: the claim is not the owner's")
    func modelUrgencyAuthorizesNothing() throws {
        let claim = ModelExtractedItem(
            kind: "commitment", title: "Confirm the venue", confirmation: "confirmed", deadline: "today at 10:00",
            priority: "urgent", evidence: "Please confirm the venue by Friday.")
        let item = try #require(validate([claim]).items.first)
        #expect(item.priority == .urgent)
        #expect(item.confirmation == .possible)
        guard case .instant(let due) = item.deadline else {
            Issue.record("expected a timed deadline, got \(String(describing: item.deadline))")
            return
        }
        // The task as review would record it: the validated confirmation, priority and deadline.
        let task = SyntheticTask.unconfirmed(
            item.title, confirmation: item.confirmation, priority: item.priority, deadline: SyntheticTask.due(due),
            createdAt: reference)
        let now = due.addingTimeInterval(-5 * 60)
        #expect(!UrgencyRule.isUrgentDeadline(task, now: now, windowMinutes: 15))
        let decision = CallEligibility.evaluate(
            CallContext(
                task: task, now: now, zone: TestTime.newYork.timeZone,
                settings: CallSettings(enabled: true, approvedNumber: "+15555550100"), quietHours: .defaultValue,
                destination: "+15555550100", earlierReminderUnacknowledged: true, callsForCommitmentToday: 0,
                callsToday: 0, basedOnProvisionalPlan: false))
        #expect(!decision.allowed)
        #expect(decision.unmetConditions == ["the commitment is not confirmed"])
    }

    @Test(
        "An unavailable, slow or throttled model leaves items waiting; nothing is guessed",
        arguments: [ModelError.unavailable("down"), .timeout, .rateLimited(retryAfter: nil)])
    func transientFailuresWait(error: ModelError) async {
        let provider = ScriptedModelProvider(steps: [.fail(error)])
        let outcome = await ExtractionPipeline(provider: provider, sharing: .localOnly).extract(request())
        guard case .awaitingModel = outcome else {
            Issue.record("expected the item to wait, got \(outcome)")
            return
        }
        #expect(provider.requestCount == 1)
    }

    @Test(
        "Credential, policy, size and response errors fail the extraction without a retry",
        arguments: [
            ModelError.authentication, .invalidResponse("broken"), .refusedByPolicy("not allowed"), .requestTooLarge,
        ])
    func permanentFailuresFail(error: ModelError) async {
        let provider = ScriptedModelProvider(steps: [.fail(error), .respond("{\"items\": []}")])
        let outcome = await ExtractionPipeline(provider: provider, sharing: .localOnly).extract(request())
        guard case .failed = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(provider.requestCount == 1)
    }

    @Test("An unclassified provider failure leaves items waiting")
    func unclassifiedFailureWaits() async {
        let provider = ScriptedModelProvider(steps: [.failUnclassified])
        let outcome = await ExtractionPipeline(provider: provider, sharing: .localOnly).extract(request())
        guard case .awaitingModel = outcome else {
            Issue.record("expected the item to wait, got \(outcome)")
            return
        }
    }

    @Test("Without a provider, or when the data-sharing policy forbids it, nothing is sent and items wait")
    func policyGatesEveryRequest() async {
        guard
            case .awaitingModel(let reason) = await ExtractionPipeline(provider: nil, sharing: .remoteMinimized)
                .extract(request())
        else {
            Issue.record("expected the item to wait without a provider")
            return
        }
        #expect(reason == "no model provider is configured")

        let forbidden: [(ModelDataSharing, ModelLocation)] = [
            (.none, .localNetwork), (.none, .remote), (.localOnly, .remote),
        ]
        for (sharing, location) in forbidden {
            let provider = ScriptedModelProvider(location: location, steps: [.respond("{\"items\": []}")])
            let outcome = await ExtractionPipeline(provider: provider, sharing: sharing).extract(request())
            guard case .awaitingModel = outcome else {
                Issue.record("\(sharing) must not send to a \(location) provider")
                continue
            }
            #expect(provider.requestCount == 0)
        }
        let allowed = ScriptedModelProvider(location: .remote, steps: [.respond("{\"items\": []}")])
        _ = await ExtractionPipeline(provider: allowed, sharing: .remoteMinimized).extract(request())
        #expect(allowed.requestCount == 1)
    }

    @Test("Every request, including the repair, is reserved against the daily budget first")
    func budgetGatesEveryRequest() async throws {
        let exhausted = ScriptedRequestBudget(.grant(0))
        let unused = ScriptedModelProvider(steps: [.respond(try json([validItem]))])
        let waiting = await ExtractionPipeline(provider: unused, sharing: .localOnly, budget: exhausted).extract(
            request())
        guard case .awaitingModel(let reason) = waiting else {
            Issue.record("expected the item to wait, got \(waiting)")
            return
        }
        #expect(reason == "the daily limit of 500 model requests is reached; items wait until tomorrow")
        #expect(unused.requestCount == 0)

        let broken = ScriptedRequestBudget(.fail)
        let alsoUnused = ScriptedModelProvider(steps: [.respond(try json([validItem]))])
        let unrecorded = await ExtractionPipeline(provider: alsoUnused, sharing: .localOnly, budget: broken).extract(
            request())
        guard case .awaitingModel = unrecorded else {
            Issue.record("expected the item to wait when the count cannot be recorded, got \(unrecorded)")
            return
        }
        #expect(alsoUnused.requestCount == 0)

        let one = ScriptedRequestBudget(.grant(1))
        let repairing = ScriptedModelProvider(steps: [.respond("garbage"), .respond(try json([validItem]))])
        let stopped = await ExtractionPipeline(provider: repairing, sharing: .localOnly, budget: one).extract(request())
        guard case .awaitingModel = stopped else {
            Issue.record("the repair must wait for budget, got \(stopped)")
            return
        }
        #expect(repairing.requestCount == 1)
        #expect(one.attempts == 2)
        #expect(one.limitsSeen == [500, 500])
    }

    @Test("The in-process deterministic provider is always labeled as such, never as live inference")
    func deterministicProviderIsLabeled() async {
        let provider = DeterministicProvider()
        #expect(
            provider.descriptor
                == ModelDescriptor(name: "deterministic-rules", location: .inProcess, isDeterministic: true))
        let outcome = await ExtractionPipeline(provider: provider, sharing: .none).extract(request())
        guard case .extracted(let extraction) = outcome else {
            Issue.record("expected an extraction, got \(outcome)")
            return
        }
        #expect(extraction.provider.isDeterministic)
        #expect(extraction.provider.name == "deterministic-rules")
    }
}
