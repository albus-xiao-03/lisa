// Dry-run transports: they record the intended delivery and never transmit anything (EMAIL-01, CALL-01, NOTIFY-04).

import Foundation
import LisaDomain
import LisaPorts
import LisaTime
import Synchronization

/// One intended delivery captured instead of being sent.
public struct DryRunCapture: Hashable, Codable, Sendable {
    public var channel: DeliveryChannel
    /// The message ID for email, the delivery ID otherwise.
    public var reference: String
    /// The intended destination: addresses for email and calls; the APNs environment and topic for pushes.
    public var recipient: String
    public var subject: String?
    public var content: String
    public var capturedAt: Date

    public init(
        channel: DeliveryChannel, reference: String, recipient: String, subject: String?, content: String,
        capturedAt: Date
    ) {
        self.channel = channel
        self.reference = reference
        self.recipient = recipient
        self.subject = subject
        self.content = content
        self.capturedAt = capturedAt
    }
}

/// Where dry-run captures are kept for inspection.
public protocol DryRunRecorder: Sendable {
    func record(_ capture: DryRunCapture) throws
    /// The most recent captures, newest first.
    func recent(limit: Int) throws -> [DryRunCapture]
}

/// Keeps the most recent captures in memory (offline demonstration and the in-process host).
public final class MemoryDryRunRecorder: DryRunRecorder {
    private let captures = Mutex<[DryRunCapture]>([])
    public let capacity: Int

    public init(capacity: Int = 500) {
        self.capacity = max(1, capacity)
    }

    public func record(_ capture: DryRunCapture) throws {
        captures.withLock { list in
            list.insert(capture, at: 0)
            if list.count > capacity { list.removeLast(list.count - capacity) }
        }
    }

    public func recent(limit: Int) throws -> [DryRunCapture] {
        captures.withLock { Array($0.prefix(max(0, limit))) }
    }
}

/// Captures email instead of sending it.
public struct DryRunEmailTransport: EmailTransport {
    public let mode = DeliveryMode.dryRun
    private let recorder: any DryRunRecorder
    private let clock: any WallClock

    public init(recorder: any DryRunRecorder, clock: any WallClock) {
        self.recorder = recorder
        self.clock = clock
    }

    public func send(_ envelope: EmailEnvelope) async -> TransportResult {
        let capture = DryRunCapture(
            channel: .email, reference: envelope.messageID, recipient: envelope.to.joined(separator: ", "),
            subject: envelope.subject, content: envelope.textBody, capturedAt: clock.now())
        do { try recorder.record(capture) } catch { return .notSent(reason: "the dry-run capture could not be stored") }
        return .capturedDryRun(summary: "email to \(envelope.to.count) approved recipient(s) captured, not sent")
    }
}

/// Captures calls instead of placing them.
public struct DryRunCallTransport: CallTransport {
    public let mode = DeliveryMode.dryRun
    private let recorder: any DryRunRecorder
    private let clock: any WallClock

    public init(recorder: any DryRunRecorder, clock: any WallClock) {
        self.recorder = recorder
        self.clock = clock
    }

    public func place(_ call: CallRequest) async -> TransportResult {
        let capture = DryRunCapture(
            channel: .call, reference: "call", recipient: call.to, subject: nil, content: call.spokenText,
            capturedAt: clock.now())
        do { try recorder.record(capture) } catch { return .notSent(reason: "the dry-run capture could not be stored") }
        return .capturedDryRun(summary: "call to the approved number captured, not placed")
    }
}

/// Captures pushes instead of sending them to APNs. The device token is never recorded.
public struct DryRunPushTransport: PushTransport {
    public let mode = DeliveryMode.dryRun
    private let recorder: any DryRunRecorder
    private let clock: any WallClock

    public init(recorder: any DryRunRecorder, clock: any WallClock) {
        self.recorder = recorder
        self.clock = clock
    }

    public func push(_ message: PushMessage) async -> TransportResult {
        let presentation = message.presentation
        let capture = DryRunCapture(
            channel: .push, reference: message.deliveryID,
            recipient: "apns \(message.environment.rawValue) topic \(message.topic)",
            subject: presentation.titleKey,
            content: DryRunPushTransport.describe(
                presentation, collapseID: message.collapseID, expiresAt: message.expiresAt),
            capturedAt: clock.now())
        do { try recorder.record(capture) } catch { return .notSent(reason: "the dry-run capture could not be stored") }
        return .capturedDryRun(summary: "push captured, not sent to APNs")
    }

    static func describe(_ presentation: NotificationPresentation, collapseID: String, expiresAt: Date) -> String {
        var parts = [
            "category=\(presentation.categoryIdentifier)", "level=\(presentation.level.rawValue)",
            "body=\(presentation.bodyKey)", "notification=\(presentation.notificationID)",
            "subject=\(presentation.subjectKind):\(presentation.subjectID)@\(presentation.subjectRevision)",
            "collapse=\(collapseID)", "expires=\(expiresAt.millisecondsSince1970)",
        ]
        if let title = presentation.itemTitle { parts.append("title=\(title)") }
        return parts.joined(separator: " ")
    }
}

/// Captures local notifications when the host does not run inside the Mac app.
public struct DryRunLocalNotificationTransport: LocalNotificationTransport {
    private let recorder: any DryRunRecorder
    private let clock: any WallClock

    public init(recorder: any DryRunRecorder, clock: any WallClock) {
        self.recorder = recorder
        self.clock = clock
    }

    public func present(_ presentation: NotificationPresentation, deliveryID: String) async -> TransportResult {
        let capture = DryRunCapture(
            channel: .localNotification, reference: deliveryID, recipient: "local", subject: presentation.titleKey,
            content: DryRunPushTransport.describe(
                presentation, collapseID: presentation.threadIdentifier, expiresAt: clock.now()),
            capturedAt: clock.now())
        do { try recorder.record(capture) } catch { return .notSent(reason: "the dry-run capture could not be stored") }
        return .capturedDryRun(summary: "local notification captured, not posted")
    }
}
