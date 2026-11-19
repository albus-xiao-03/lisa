// The sources on Settings and Health: each configured source, whether it is on, how fresh its data is, when it was last
// read, and why it fails or what it cannot do.

import Foundation
import LisaPresentation
import SwiftUI

/// The sources from health (UI-01: sources). The host reports no addresses or credentials of a source; sources are
/// added and changed in the configuration file.
struct SourcesSection: View {
    let settings: SettingsHealthModel

    var body: some View {
        Section("Sources") {
            if settings.health.value == nil {
                Text("Shown once Lisa's host answers.")
                    .foregroundStyle(.secondary)
            } else if settings.sources.isEmpty {
                Text("No sources are configured. Add them to Lisa's configuration file.")
                    .foregroundStyle(.secondary)
            }
            ForEach(settings.sources) { source in
                row(source)
            }
        }
    }

    private func row(_ source: SourceHealthSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(source.name)
                Text(source.kindLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(source.freshnessLabel)
                    .font(.callout)
                    .foregroundStyle(source.needsAttention ? Color.orange : Color.secondary)
            }
            TimelineView(.everyMinute) { context in
                Text(source.lastReadPhrase(at: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let problem = source.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            ForEach(source.notes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(source.accessibilityLabel)
    }
}
