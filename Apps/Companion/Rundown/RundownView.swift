// The rundown screen (UI-02): the plan for today, or the saved copy with its age while the host can't be reached.

import Foundation
import LisaAPIContract
import LisaClient
import LisaPresentation
import SwiftUI

/// Today's planned blocks in time order, what could not be scheduled, and the planner's notes. The screen only shows
/// the plan: the host is the only scheduler (UI-02).
struct RundownView: View {
    let model: RundownModel

    var body: some View {
        LoadStateView(
            state: model.state, emptyTitle: "Nothing Planned", emptySystemImage: "calendar",
            emptyMessage: "Lisa has no plan for this day yet.",
            isEmpty: { $0.blocks.isEmpty && $0.unscheduled.isEmpty }, isEarlierDay: model.showsEarlierDay,
            retry: { await model.refresh() },
            content: { result in plan(result.value) }
        )
        .navigationTitle("Rundown")
        .refreshable { [model] in await model.refresh() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.state.isLoading)
            }
        }
    }

    private func plan(_ rundown: RundownDTO) -> some View {
        let zone = TimeZone(identifier: rundown.zone) ?? .current
        return List {
            Section(LocalDayText.words(for: rundown.date, style: .complete)) {
                if rundown.blocks.isEmpty {
                    Text("Nothing is planned for this day.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rundown.blocks.sorted(by: { $0.start < $1.start }), id: \.blockID) { block in
                    PlanBlockRow(block: block, zone: zone)
                }
            }
            if !rundown.unscheduled.isEmpty {
                Section("Couldn't Be Scheduled") {
                    ForEach(rundown.unscheduled, id: \.self) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(item.reason)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if rundown.availabilityUncertain || !rundown.warnings.isEmpty {
                Section("Notes") {
                    if rundown.availabilityUncertain {
                        Label(
                            "Some calendar information is missing, so times may change.",
                            systemImage: "calendar.badge.exclamationmark")
                    }
                    ForEach(rundown.warnings, id: \.self) { warning in
                        Text(warning)
                    }
                }
            }
            if !rundown.changes.isEmpty {
                Section("What Changed") {
                    ForEach(rundown.changes, id: \.self) { change in
                        Text(change)
                    }
                }
            }
        }
    }
}
