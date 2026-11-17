// The reminders screen (UI-02): the host's active reminders, acknowledged or snoozed through the durable queue, and
// the actions the host refused because a reminder changed there.

import LisaAPIContract
import LisaClient
import LisaPresentation
import SwiftUI

/// Active reminders in time order. Reminders are not saved on this device, so while the host can't be reached the
/// screen keeps the ones it last read, marked as not current. Snoozing uses the host's snooze duration and the host
/// computes the next reminder; the app schedules nothing itself.
struct RemindersView: View {
    let model: RemindersModel

    var body: some View {
        LoadStateView(
            state: model.state, emptyTitle: "No Reminders", emptySystemImage: "bell",
            emptyMessage: "Upcoming and snoozed reminders appear here.", isEmpty: { $0.isEmpty },
            retry: { await model.load() },
            content: { result in list(result.value) }
        )
        .navigationTitle("Reminders")
        .refreshable { [model] in await model.load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.load() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.state.isLoading)
            }
        }
    }

    private func list(_ reminders: [ReminderDTO]) -> some View {
        List {
            if let outcome = model.lastOutcome {
                Section {
                    ActionOutcomeLabel(outcome: outcome)
                }
            }
            if !model.conflicts.isEmpty {
                Section("Your Action Wasn't Applied") {
                    ForEach(model.conflicts.keys.sorted(), id: \.self) { id in
                        if let conflict = model.conflicts[id] {
                            conflictRow(id: id, conflict: conflict, reminders: reminders)
                        }
                    }
                }
            }
            Section {
                ForEach(reminders.sorted(by: { $0.dueAt < $1.dueAt }), id: \.id) { reminder in
                    ReminderRow(
                        reminder: reminder, pendingAction: model.pendingActions[reminder.id],
                        hasConflict: model.conflicts[reminder.id] != nil,
                        isBusy: model.busyReminderIDs.contains(reminder.id),
                        acknowledge: { await model.acknowledge(reminder) }, snooze: { await model.snooze(reminder) })
                }
            }
        }
    }

    private func conflictRow(id: String, conflict: ActionConflict, reminders: [ReminderDTO]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(reminders.first(where: { $0.id == id })?.title ?? "A reminder")
                .font(.headline)
            ConflictNotice(
                message: conflict.message, canApplyAgain: conflict.canApplyToCurrentRevision,
                applyAgain: { await model.applyAgain(reminderID: id) },
                discard: { await model.discardAction(reminderID: id) })
        }
    }
}
