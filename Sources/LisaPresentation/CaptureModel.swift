// The capture screen, the share sheet and Siri capture: an idea, text, a link or an Apple News share, queued durably
// so nothing is lost offline.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// Captures ideas and items for a future brief (UI-02, UI-03, SIRI-01, NEWS-04).
///
/// Every capture is written to the durable offline queue first, with a stable request ID, and then sent if the host
/// can be reached; a capture made offline is kept and sent later, and the host never stores it twice (L10). The draft
/// is checked as the host checks it before anything is queued. An Apple News share is sent as `sharedAppleNews`, which
/// the host labels as shared content.
@MainActor
@Observable
public final class CaptureModel {
    /// The draft being edited on the capture screen.
    public var draft = CaptureDraft()
    /// Whether a capture is being saved.
    public private(set) var isSubmitting = false
    /// The outcome of the latest capture.
    public private(set) var lastOutcome: ActionOutcome?
    /// The problems found when the owner last tried to save the draft; empty once it saved.
    public private(set) var validationIssues: [CaptureValidationIssue] = []
    /// How many captures wait in the offline queue for the host.
    public private(set) var pendingCaptureCount = 0

    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let contacts: (any HostContactReporting)?
    @ObservationIgnored private let channel: CaptureChannelValue
    @ObservationIgnored private var inFlight = 0

    /// - Parameters:
    ///   - context: the client services.
    ///   - contacts: where connectivity is reported.
    ///   - channel: the channel the app's own captures report: `.nativeApp`; App Intents pass `.siri` per capture.
    public init(
        context: ClientContext, contacts: (any HostContactReporting)? = nil, channel: CaptureChannelValue = .nativeApp
    ) {
        self.context = context
        self.contacts = contacts
        self.channel = channel
    }

    /// Whether the draft can be saved now.
    public var canSubmit: Bool { !isSubmitting && draft.validate().isEmpty }

    /// Saves the draft. Once it is done or queued, the draft is cleared (keeping its kind) unless it was edited
    /// meanwhile; otherwise it is kept so nothing the owner wrote is lost.
    @discardableResult
    public func submit() async -> ActionOutcome {
        let submitted = draft
        validationIssues = submitted.validate()
        guard validationIssues.isEmpty else {
            let outcome = ActionOutcome.failed(reason: validationIssues[0].message)
            lastOutcome = outcome
            return outcome
        }
        let outcome = await capture(submitted)
        if outcome.isDone || outcome.isQueued, draft == submitted { draft = CaptureDraft(kind: submitted.kind) }
        return outcome
    }

    /// Saves `draft` without touching the screen's draft, as the share sheet and Siri do.
    ///
    /// - Parameter channel: where the capture came from; the model's channel when `nil`.
    @discardableResult
    public func capture(_ draft: CaptureDraft, channel: CaptureChannelValue? = nil) async -> ActionOutcome {
        let issues = draft.validate()
        guard issues.isEmpty else {
            let outcome = ActionOutcome.failed(reason: issues[0].message)
            lastOutcome = outcome
            return outcome
        }
        inFlight += 1
        isSubmitting = true
        defer {
            inFlight -= 1
            isSubmitting = inFlight > 0
        }
        let request = draft.request(channel: channel ?? self.channel)
        let submission = await ActionSubmitter(context: context).submit(.capture(request))
        if let contact = submission.contact { await contacts?.record(contact) }
        lastOutcome = submission.outcome
        await refreshPendingCount()
        return submission.outcome
    }

    /// Reads how many captures wait in the offline queue.
    public func refreshPendingCount() async {
        pendingCaptureCount = await context.queue.pendingEntries.count { $0.kind == .capture }
    }
}
