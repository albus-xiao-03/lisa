// One preference: its title and value (the queued value while a change waits), where it came from, whether it takes
// effect, and editing, confirming or deleting it, with the host's refusal or a recoverable conflict shown beside it.

import Foundation
import LisaAPIContract
import LisaPresentation
import SwiftUI

/// A preference as the memory and settings screens show it (MEM-01). Deleting one asks first; Lisa then follows its
/// configuration for it again.
struct PreferenceRow: View {
    let model: MemoryModel
    let preference: PreferenceDTO
    /// Opens the edit sheet.
    let edit: () -> Void

    @State private var confirmsDeletion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.title)
                    Text(valueText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(originText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.pendingChanges[preference.key] != nil {
                        SyncBadge(kind: .waiting)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if model.busyKeys.contains(preference.key) {
                    ProgressView()
                        .controlSize(.small)
                }
                if preference.origin == "inferred", !preference.confirmed {
                    Button("Confirm") {
                        Task { await model.confirm(preference.key) }
                    }
                    .help("Lets this preference take effect.")
                }
                Button("Edit…", action: edit)
                Button(
                    role: .destructive, action: { confirmsDeletion = true },
                    label: { Text("Delete") })
            }
            .controlSize(.small)
            .disabled(model.busyKeys.contains(preference.key))
            if let issue = model.issues[preference.key] {
                HStack(alignment: .firstTextBaseline) {
                    Label(issueText(issue), systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(.red)
                    Button("Dismiss") {
                        Task { await model.dismissIssue(key: preference.key) }
                    }
                    .controlSize(.small)
                }
            }
            if let refused = model.conflicts[preference.key] {
                ConflictNotice(
                    message: refused.conflict.message, canApplyAgain: refused.conflict.canApplyToCurrentRevision,
                    applyAgain: { await model.applyAgain(key: preference.key) },
                    discard: { await model.discardChange(key: preference.key) })
            }
        }
        .padding(.vertical, 2)
        .confirmationDialog(
            "Delete “\(descriptor.title)”?", isPresented: $confirmsDeletion,
            actions: {
                Button("Delete", role: .destructive) {
                    Task { await model.delete(preference.key) }
                }
            },
            message: { Text("Lisa then follows its configuration for it again.") })
    }

    private var descriptor: PreferenceDescriptor { PreferenceDescriptor.describing(preference.key) }

    /// The value shown: the queued one while a change waits, or that a deletion waits.
    private var valueText: String {
        guard let value = model.displayedValue(for: preference.key) else { return "Deletion waiting to sync" }
        return PreferenceDescriptor.displayText(value)
    }

    private var originText: String {
        var parts: [String] = []
        if preference.origin == "inferred" {
            parts.append(preference.confirmed ? "Learned by Lisa, confirmed by you" : "Learned by Lisa, not confirmed")
        } else {
            parts.append("Set by you")
        }
        if !preference.effective { parts.append("not in effect") }
        if preference.consequential { parts.append("only changed on the Mac that runs Lisa") }
        return parts.joined(separator: " · ")
    }

    private func issueText(_ issue: PreferenceIssue) -> String {
        if issue.isPermissionRefusal { return "Lisa's host doesn't let this be changed here: \(issue.reason)" }
        return "Lisa's host refused this value: \(issue.reason)"
    }
}
