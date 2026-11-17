// One reminder: what it is about and when, whether an action on it waits to sync, and Acknowledge and Snooze.

import Foundation
import LisaAPIContract
import SwiftUI

/// A reminder as the reminders list shows it. Acknowledging tells Lisa the owner has seen it and never completes the
/// task. While an action on the reminder waits to sync, or was refused, no other action is offered.
struct ReminderRow: View {
    let reminder: ReminderDTO
    let pendingAction: ReminderActionKind?
    let hasConflict: Bool
    let isBusy: Bool
    let acknowledge: @MainActor () async -> Void
    let snooze: @MainActor () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if reminder.urgentDeadline {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Urgent")
                }
                Text(reminder.title.isEmpty ? "Reminder" : reminder.title)
                Spacer(minLength: 0)
                if isBusy {
                    ProgressView()
                }
            }
            Text(timing)
                .font(.caption)
                .foregroundStyle(.secondary)
            if hasConflict {
                SyncBadge(kind: .conflict)
            } else if let pendingAction {
                SyncBadge(kind: .waiting, action: Self.name(of: pendingAction))
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    buttons
                }
                VStack(alignment: .leading) {
                    buttons
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isBusy || hasConflict || pendingAction != nil)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Acknowledge", systemImage: "checkmark") {
            Task { await acknowledge() }
        }
        .accessibilityHint("Tells Lisa you've seen it. The task stays open.")
        Button("Snooze", systemImage: "zzz") {
            Task { await snooze() }
        }
        .accessibilityHint("Lisa reminds you again after your snooze time.")
    }

    /// What the reminder is about and when it is due, or until when it is snoozed.
    private var timing: String {
        if reminder.state == "snoozed", let until = reminder.snoozedUntil {
            return "Snoozed until \(until.formatted(date: .omitted, time: .shortened))"
        }
        return "\(about) · \(reminder.dueAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private var about: String {
        switch reminder.rule {
        case "deadlineAhead", "dateOnlyDeadline": "Deadline"
        case "overdue": "Past due"
        case "planBlockStart": "Planned block"
        case "proposalFollowUp": "Event to review"
        case "commitmentChange": "Commitment changed"
        default: "Reminder"
        }
    }

    private static func name(of action: ReminderActionKind) -> String {
        switch action {
        case .acknowledge: "Acknowledge"
        case .snooze: "Snooze"
        case .dismiss: "Dismiss"
        case .complete: "Complete"
        }
    }
}
