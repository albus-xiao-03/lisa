// Unit tests for L31, notification privacy and authority at policy level (NOTIFY-02, NOTIFY-06, NOTIFY-07, SEC-01;
// D-08, D-09, D-17, D-28, D-38): default content is generic localized text plus opaque identifiers; item titles appear
// only for devices that opted in, truncated; push tokens and secrets are redacted wherever they are described or
// logged; and a missing push acknowledgement alone never authorizes a call.

import Foundation
import LisaDomain
import LisaLogging
import LisaPolicy
import LisaRedaction
import LisaTime
import Testing

@Suite("L31 — Notification privacy and authority", .tags(.unit))
struct L31NotificationPrivacyTests {
    private let now = TestTime.instant("2026-11-16T14:00", in: TestTime.newYork)
    private let privateTitle = "Pay Dr. Example's invoice of $480 before the 5pm cutoff"

    private func intent(_ category: NotificationCategory, title: String?, subject: NotificationSubject? = nil)
        -> NotificationIntent
    {
        NotificationIntent(
            occurrenceKey: "test:\(category.rawValue)", category: category,
            subject: subject ?? .task(TaskID.random()), changeSequence: 0, collapseKey: "test:\(category.rawValue)",
            interruptionLevel: .active, titleHint: title, validUntil: now.addingTimeInterval(3_600), now: now)
    }

    private static let expectedBase: [NotificationCategory: String] = [
        .reminder: "LISA_REMINDER", .overdue: "LISA_OVERDUE", .planBlock: "LISA_PLAN_BLOCK",
        .eventProposal: "LISA_EVENT_PROPOSAL", .commitmentChange: "LISA_COMMITMENT_CHANGE", .brief: "LISA_BRIEF",
    ]

    @Test(
        "By default every category carries only generic keys and an opaque thread identifier",
        arguments: NotificationCategory.allCases)
    func defaultContentIsGeneric(category: NotificationCategory) throws {
        let notification = intent(category, title: privateTitle)
        let content = NotificationContentPolicy.content(for: notification, showTitle: false)
        let base = try #require(Self.expectedBase[category])
        #expect(content.titleKey == "\(base)_TITLE")
        #expect(content.bodyKey == "\(base)_BODY")
        #expect(content.categoryIdentifier == base)
        #expect(content.itemTitle == nil)
        #expect(content.threadIdentifier == notification.subject.key)
        let everything = [content.titleKey, content.bodyKey, content.categoryIdentifier, content.threadIdentifier]
        for word in ["Example", "invoice", "480", "5pm"] {
            #expect(!everything.contains { $0.contains(word) }, "\(word) leaked into the content")
        }
    }

    @Test("Thread identifiers are built from random record identifiers, never from item text")
    func identifiersAreOpaque() {
        let first = NotificationContentPolicy.content(for: intent(.reminder, title: privateTitle), showTitle: false)
        let second = NotificationContentPolicy.content(for: intent(.reminder, title: privateTitle), showTitle: false)
        #expect(first.threadIdentifier != second.threadIdentifier)
        #expect(first.threadIdentifier.hasPrefix("task:"))
        let opaque = first.threadIdentifier.dropFirst("task:".count)
        #expect(opaque.allSatisfy { $0.isHexDigit || $0 == "-" })
    }

    @Test("Only a device that opted in receives the item title, flattened to one line and truncated to 60 characters")
    func titlesOnlyWhenOptedIn() {
        let short = NotificationContentPolicy.content(
            for: intent(.reminder, title: "  Water the\nplants\r\n"), showTitle: true)
        #expect(short.itemTitle == "Water the plants")
        let long = NotificationContentPolicy.content(
            for: intent(.reminder, title: String(repeating: "x", count: 100)), showTitle: true)
        #expect(long.itemTitle?.count == NotificationContentPolicy.maxTitleCharacters)
        #expect(long.itemTitle?.hasSuffix("…") == true)
        #expect(NotificationContentPolicy.content(for: intent(.brief, title: nil), showTitle: true).itemTitle == nil)
    }

    @Test("A device's default preferences send no titles")
    func routingDefaultsToNoTitles() {
        let device = SyntheticDevice.registration(.iPhone, now: now)
        #expect(!device.preferences.showTitles)
        let decisions = NotificationRouting.route(category: .reminder, level: .active, devices: [device])
        #expect(decisions.map(\.showTitle) == [false])
    }

    @Test("Push tokens never appear when a registration is described, printed or logged")
    func tokensAreRedacted() throws {
        let device = SyntheticDevice.registration(.iPad, now: now)
        let token = try #require(device.pushToken?.token.revealed)
        #expect(String(describing: try #require(device.pushToken).token) == "<redacted>")
        #expect(!String(describing: device).contains(token))
        #expect(!String(reflecting: device).contains(token))
        #expect(!"\(device)".contains(token))

        #expect(LogValue.secret.rendered == "<redacted>")
        let fingerprint = LogValue.private(token).rendered
        #expect(fingerprint.hasPrefix("fp:"))
        #expect(!fingerprint.contains(token))
        let line = LogRecord(
            timestamp: now, level: .info, category: "devices", message: "token updated",
            metadata: ["token": .private(token), "key": .secret, "device": .public(device.id.rawValue)]
        ).jsonLine()
        #expect(!line.contains(token))
        #expect(line.contains(device.id.rawValue))
        #expect(Sensitive("synthetic signing key material").description == "<redacted>")
    }

    @Test("A missing push acknowledgement alone never authorizes a call")
    func missingAcknowledgementAuthorizesNoCall() {
        let task = SyntheticTask.confirmed(
            deadline: SyntheticTask.due(now.addingTimeInterval(10 * 60)), createdAt: now.addingTimeInterval(-3_600))
        func decision(_ settings: CallSettings, deadline: Deadline?) -> CallDecision {
            var subject = task
            subject.deadline = deadline
            return CallEligibility.evaluate(
                CallContext(
                    task: subject, now: now, zone: TestTime.newYork.timeZone, settings: settings,
                    quietHours: .defaultValue, destination: settings.approvedNumber,
                    earlierReminderUnacknowledged: true, callsForCommitmentToday: 0, callsToday: 0,
                    basedOnProvisionalPlan: false))
        }
        let withDefaults = decision(CallSettings(), deadline: task.deadline)
        #expect(!withDefaults.allowed)
        #expect(withDefaults.unmetConditions.contains("calls are not enabled"))

        let enabled = CallSettings(enabled: true, approvedNumber: "+15555550100")
        let notUrgent = decision(enabled, deadline: SyntheticTask.due(now.addingTimeInterval(2 * 3_600)))
        #expect(notUrgent.unmetConditions == ["the deadline is not within 15 minutes"])
    }
}
