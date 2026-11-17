// The tasks screen (UI-02): the task list from the host or the saved copy, filtered by status, with completing and
// reopening queued durably and checked against the version shown.

import LisaAPIContract
import LisaClient
import LisaPresentation
import SwiftUI

/// The task list. Each change expects the version the owner saw: a change made offline waits in the queue and is
/// marked, and a change the host refused because the task changed is marked and resolved in the task's detail. Swipe
/// right, or use the context menu, to complete or reopen a task.
struct TasksView: View {
    let model: TasksModel

    var body: some View {
        LoadStateView(
            state: model.state, emptyTitle: "No Tasks", emptySystemImage: "checklist",
            emptyMessage: "Tasks Lisa keeps for you appear here.", isEmpty: { $0.items.isEmpty },
            retry: { await model.refresh() },
            content: { result in list(result.value.items) }
        )
        .navigationTitle(model.statusFilter.map(TaskText.status) ?? "Tasks")
        .refreshable { [model] in await model.refresh() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                filterMenu
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.state.isLoading)
            }
        }
        .navigationDestination(for: TaskRoute.self) { route in
            TaskDetailView(model: model, taskID: route.taskID)
        }
    }

    private func list(_ tasks: [TaskDTO]) -> some View {
        List {
            if let outcome = model.lastOutcome {
                Section {
                    ActionOutcomeLabel(outcome: outcome)
                }
            }
            Section {
                ForEach(tasks, id: \.id) { task in
                    NavigationLink(value: TaskRoute(taskID: task.id)) {
                        TaskRow(
                            task: task, hasPendingChange: model.pendingChanges[task.id] != nil,
                            hasConflict: model.conflicts[task.id] != nil, isBusy: model.busyTaskIDs.contains(task.id))
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        completionButton(for: task)
                    }
                    .contextMenu {
                        completionButton(for: task)
                    }
                }
                if model.hasMore {
                    Button("Show More Tasks") {
                        Task { await model.loadMore() }
                    }
                    .disabled(model.isLoadingMore)
                }
            }
        }
    }

    private func completionButton(for task: TaskDTO) -> some View {
        let isCompleted = task.status == .completed
        let title = isCompleted ? "Reopen" : "Complete"
        return Button(title, systemImage: isCompleted ? "arrow.uturn.backward" : "checkmark") {
            Task {
                if isCompleted {
                    await model.reopen(task)
                } else {
                    await model.complete(task)
                }
            }
        }
        .tint(isCompleted ? Color.gray : Color.green)
        .disabled(model.busyTaskIDs.contains(task.id))
    }

    private var filterMenu: some View {
        let current = model.statusFilter
        let selection = Binding<TaskStatusValue?>(
            get: { current },
            set: { [model] status in Task { @MainActor in await model.load(status: status) } })
        return Menu(
            content: {
                Picker("Show", selection: selection) {
                    Text("All Tasks").tag(TaskStatusValue?.none)
                    ForEach(TaskStatusValue.allCases, id: \.self) { status in
                        Text(TaskText.status(status)).tag(TaskStatusValue?.some(status))
                    }
                }
            },
            label: { Label("Show", systemImage: "line.3.horizontal.decrease.circle") })
    }
}
