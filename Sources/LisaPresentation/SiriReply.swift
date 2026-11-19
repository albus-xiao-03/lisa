// What Siri and Shortcuts say after an App Intent: the brief, the rundown, or the truthful result of an action.

import Foundation
import LisaClient

/// The answer of an App Intent (SIRI-01): what Siri says or shows, and the outcome of the action, if one was taken.
/// An action queued offline is never reported as done; a saved copy of the brief or rundown says how old it is.
public struct SiriReply: Hashable, Sendable {
    /// What Siri says or shows. For the brief and the rundown it is also the intent's text result, so a shortcut can
    /// speak it.
    public var dialog: String
    /// What became of the action; `nil` for reading the brief or rundown, or when nothing was attempted.
    public var outcome: ActionOutcome?

    /// A reply saying `dialog`, for an action that ended as `outcome`.
    public init(dialog: String, outcome: ActionOutcome? = nil) {
        self.dialog = dialog
        self.outcome = outcome
    }

    /// The reply when the app has no client services yet, so nothing was attempted.
    public static let notSetUp = SiriReply(
        dialog: "Lisa isn't set up on this device yet. Open Lisa to connect it to your Lisa host.",
        outcome: .unavailable(reason: "Lisa is not set up on this device"))

    // MARK: - Reading

    /// The brief: its spoken text, or why there is none to read.
    static func brief(speech: String?, failure: LoadFailure?, date: String?) -> SiriReply {
        if let speech { return SiriReply(dialog: speech) }
        let day = date.map { "for \(LocalDay.spokenEnglish($0))" } ?? "for today"
        let reason =
            switch failure {
            case .notFound?: "Lisa hasn't prepared a brief \(day) yet."
            case .unreachable?: "Lisa's host can't be reached, and no brief \(day) is saved on this device."
            case .failed(let detail)?: "Lisa couldn't get your brief: \(clause(detail))."
            case let other?: readingFailure(other)
            case nil: "The brief \(day) has nothing to read yet."
            }
        return SiriReply(dialog: reason)
    }

    /// Why no rundown could be read.
    static func rundownFailure(_ failure: LoadFailure?, date: String?) -> SiriReply {
        let day = date.map { "for \(LocalDay.spokenEnglish($0))" } ?? "for today"
        let reason =
            switch failure {
            case .notFound?: "Lisa has no rundown \(day) yet."
            case .unreachable?: "Lisa's host can't be reached, and no rundown \(day) is saved on this device."
            case .failed(let detail)?: "Lisa couldn't get your rundown: \(clause(detail))."
            case let other?: readingFailure(other)
            case nil: "Lisa has no rundown \(day) yet."
            }
        return SiriReply(dialog: reason)
    }

    // MARK: - Capturing

    /// What became of a capture: an idea, or text or a link for a future brief.
    static func captured(_ outcome: ActionOutcome, isIdea: Bool) -> SiriReply {
        let dialog: String
        switch outcome {
        case .done:
            dialog = isIdea ? "Saved your idea." : "Saved for a future brief."
        case .queued:
            dialog =
                (isIdea ? "Saved your idea on this device." : "Saved on this device for a future brief.")
                + " Lisa sends it to your host when the host can be reached."
        case .unavailable(let reason):
            dialog = "Nothing was saved: \(clause(reason))."
        case .conflict, .failed:
            dialog = "Nothing was saved: \(failureClause(outcome))."
        }
        return SiriReply(dialog: dialog, outcome: outcome)
    }

    // MARK: - Acting

    /// What became of completing the task `title`.
    static func completed(_ title: String, _ outcome: ActionOutcome) -> SiriReply {
        let name = quoted(title)
        let dialog =
            switch outcome {
            case .done: "Marked \(name) complete."
            case .queued:
                "\(name) will be marked complete when your Lisa host can be reached. Until then Lisa shows it as "
                    + "pending."
            case .conflict:
                "\(name) changed on your Lisa host, so it wasn't marked complete. Open Lisa to review it."
            case .unavailable(let reason): "\(name) wasn't marked complete: \(clause(reason))."
            case .failed: "\(name) wasn't marked complete: \(failureClause(outcome))."
            }
        return SiriReply(dialog: dialog, outcome: outcome)
    }

    /// The reply for a task that can no longer be completed, without trying.
    static func notCompletable(_ item: SiriItem) -> SiriReply {
        let name = quoted(item.title)
        let dialog =
            switch item.state {
            case "completed": "\(name) is already complete."
            case "cancelled": "\(name) was cancelled, so it can't be marked complete."
            default: "\(name) can't be marked complete right now."
            }
        return SiriReply(dialog: dialog)
    }

    /// What became of snoozing the reminder `title`; `until` is when it fires again, once the host said so.
    static func snoozed(_ title: String, until: String?, _ outcome: ActionOutcome) -> SiriReply {
        let name = quoted(title)
        let dialog =
            switch outcome {
            case .done: until.map { "Snoozed \(name) until \($0)." } ?? "Snoozed \(name)."
            case .queued:
                "\(name) will be snoozed when your Lisa host can be reached. Until then Lisa shows it as pending."
            case .conflict: "\(name) changed on your Lisa host, so it wasn't snoozed. Open Lisa to review it."
            case .unavailable(let reason): "\(name) wasn't snoozed: \(clause(reason))."
            case .failed: "\(name) wasn't snoozed: \(failureClause(outcome))."
            }
        return SiriReply(dialog: dialog, outcome: outcome)
    }

    /// The reply for a reminder that is no longer active, without trying.
    static func notSnoozable(_ item: SiriItem) -> SiriReply {
        SiriReply(dialog: "\(quoted(item.title)) is no longer active, so it can't be snoozed.")
    }

    // MARK: - Wording

    /// A reading failure other than a missing item or an unreachable host.
    private static func readingFailure(_ failure: LoadFailure) -> String {
        switch failure {
        case .notPaired: "This device isn't paired with a Lisa host. Open Lisa to pair it."
        case .revoked: "Your Lisa host removed this device. Open Lisa to pair it again."
        default: failure.message
        }
    }

    /// The reason a failed or conflicting outcome gives.
    private static func failureClause(_ outcome: ActionOutcome) -> String {
        switch outcome {
        case .failed(let reason): clause(reason)
        case .conflict(let conflict): clause(conflict.message)
        default: clause(outcome.summary)
        }
    }

    /// `text` without a closing period, to end a sentence of its own.
    static func clause(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    /// `title` in quotation marks, plain for speech.
    private static func quoted(_ title: String) -> String {
        let plain = clause(SpokenText.plain(title))
        return "\u{201C}\(plain.isEmpty ? "the item" : plain)\u{201D}"
    }
}
