// Notification responses on a device (NOTIFY-05, plan §6.5): opening, durable actions with stable IDs, and receipts.

import Foundation
import LisaAPIContract

/// What handling a notification response produced.
public struct NotificationActionOutcome: Hashable, Sendable {
    /// The notification's item. The app shows it when the response opens the app.
    public var subject: LisaPushData
    /// The chosen action, or `nil` when the notification was opened.
    public var action: NotificationActionID?
    /// The queued action after the submission attempt: done, pending, a conflict or a failure. `nil` when opened.
    public var entry: QueuedRequest?

    /// The outcome of a response about `subject`.
    public init(subject: LisaPushData, action: NotificationActionID?, entry: QueuedRequest?) {
        self.subject = subject
        self.action = action
        self.entry = entry
    }

    /// Whether the response opens the app on `subject` without submitting anything.
    public var opensItem: Bool { action == nil }
}

/// Handles responses to delivered Lisa notifications (NOTIFY-05, plan §6.5).
///
/// The Apple apps call it from their notification delegate, with the notification's user info as JSON and the chosen
/// action identifier (`open` for the default action). The device must not decide anything itself: every action goes
/// to the host through the authenticated API.
public struct NotificationActionHandler: Sendable {
    /// The most notification identifiers in one receipts request.
    public static let maxReceiptsPerRequest = 200

    /// The client that submits actions and provides the installation ID.
    public let client: LisaAPIClient
    /// The durable queue every action is written to first.
    public let queue: OfflineQueue

    /// A handler that submits through `client` and queues in `queue`.
    public init(client: LisaAPIClient, queue: OfflineQueue) {
        self.client = client
        self.queue = queue
    }

    /// Handles a response to a delivered notification.
    ///
    /// Opening makes no mutation and returns the item to show. An action is first written to the durable queue with
    /// the deterministic request ID `na:<installationID>:<notificationID>:<action>`, then submitted within
    /// `timeLimit`; when the host is unreachable or slow it stays pending, and a later flush sends it with the same ID.
    /// The system may invoke the handler more than once for one response: a repeat finds the queued entry instead of
    /// queueing the action again, and the host applies the action once.
    ///
    /// - Parameters:
    ///   - payloadJSON: the notification's user info as JSON, which holds the `lisa` payload object.
    ///   - actionIdentifier: `open`, or a `NotificationActionID` raw value.
    ///   - timeLimit: how long to try submitting before leaving the action pending.
    public func handle(
        payloadJSON: Data, actionIdentifier: String, timeLimit: Duration
    ) async throws -> NotificationActionOutcome {
        guard let subject = PushPayload.lisaData(fromJSON: payloadJSON) else {
            throw NotificationActionError.unreadablePayload
        }
        guard let response = NotificationResponseAction(identifier: actionIdentifier) else {
            throw NotificationActionError.unknownAction(actionIdentifier)
        }
        guard case .action(let action) = response else {
            return NotificationActionOutcome(subject: subject, action: nil, entry: nil)
        }
        guard subject.version == LisaPushData.currentVersion else {
            throw NotificationActionError.unsupportedPayloadVersion(subject.version)
        }
        if let category = Self.category(forKind: subject.kind), !category.actions.contains(action) {
            throw NotificationActionError.actionNotOffered(action: action, category: category)
        }
        let installation = try await client.installation()
        guard
            let requestID = RequestID.notificationAction(
                installationID: installation.installationID, notificationID: subject.notificationID, action: action)
        else { throw NotificationActionError.unusableIdentifiers(notificationID: subject.notificationID) }
        let mutation = QueuedMutation.notificationAction(
            notificationID: subject.notificationID, NotificationActionRequest(action: action.reminderAction))
        let entry = try await queue.submit(mutation, requestID: requestID, using: client, timeLimit: timeLimit)
        return NotificationActionOutcome(subject: subject, action: action, entry: entry)
    }

    /// Queues receipts for notifications this device presented, opened or still listed, which are the host's only
    /// evidence of display. They are then submitted within `timeLimit` when one is given.
    ///
    /// Identifiers are de-duplicated in order and sent in requests of at most `maxReceiptsPerRequest`. When queueing
    /// fails part-way, the requests queued before the failure stay queued; recording a receipt twice is harmless.
    ///
    /// - Returns: the queued receipt requests as they stand afterwards.
    public func recordReceipts(_ notificationIDs: [String], timeLimit: Duration? = nil) async throws -> [QueuedRequest]
    {
        var seen: Set<String> = []
        let unique = notificationIDs.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !unique.isEmpty else { throw NotificationActionError.noReceipts }
        var queued: [QueuedRequest] = []
        for start in stride(from: 0, to: unique.count, by: Self.maxReceiptsPerRequest) {
            let chunk = Array(unique[start..<min(start + Self.maxReceiptsPerRequest, unique.count)])
            queued.append(
                try await queue.enqueue(.notificationReceipts(NotificationReceiptsRequest(notificationIDs: chunk))))
        }
        if let timeLimit {
            _ = await queue.flush(using: client, timeLimit: timeLimit)
        }
        var current: [QueuedRequest] = []
        for entry in queued {
            current.append(await queue.entry(entry.id) ?? entry)
        }
        return current
    }

    /// The category of the host's notification kind, such as `reminder`; `nil` for a kind this client does not know,
    /// whose actions the host alone checks.
    private static func category(forKind kind: String) -> NotificationCategoryID? {
        switch kind {
        case "reminder": .reminder
        case "overdue": .overdue
        case "planBlock": .planBlock
        case "eventProposal": .eventProposal
        case "commitmentChange": .commitmentChange
        case "brief": .brief
        default: nil
        }
    }
}
