// One item of the brief with what it is based on: the kind of record each source is, and the original link of
// shared or news content, which opens in the browser only when the owner chooses it.

import Foundation
import LisaAPIContract
import SwiftUI

/// A brief item (UI-01: sources). Each item cites the records it was composed from; Lisa never fetches the links shown,
/// and only `http` and `https` addresses are offered as links.
struct BriefItemRow: View {
    let item: BriefItemDTO
    @State private var showsSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.text)
                .textSelection(.enabled)
                .fontWeight(item.material ? .medium : .regular)
            if let uncertainty = item.uncertainty, !uncertainty.isEmpty {
                Label(uncertainty, systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !item.references.isEmpty {
                DisclosureGroup(sourcesTitle, isExpanded: $showsSources) {
                    ForEach(Array(item.references.enumerated()), id: \.offset) { entry in
                        source(entry.element)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func source(_ reference: SourceReferenceDTO) -> some View {
        let kind = Self.kindLabel(reference.recordKind)
        if let link = reference.originalURL.flatMap(Self.webLink) {
            Link(destination: link) {
                Label("\(kind): \(link.host() ?? link.absoluteString)", systemImage: "link")
            }
            .help(link.absoluteString)
        } else {
            Label(kind, systemImage: "doc.text")
                .foregroundStyle(.secondary)
        }
    }

    private var sourcesTitle: String {
        item.references.count == 1 ? "1 source" : "\(item.references.count) sources"
    }

    /// The heading of a brief section.
    static func title(ofSection section: String) -> String {
        switch section {
        case "commitments": "Commitments"
        case "deadlines": "Deadlines"
        case "email": "Email"
        case "events": "Events"
        case "ideas": "Ideas"
        case "news": "News"
        case "changes": "Changes"
        case "sourceHealth": "Sources"
        default: section
        }
    }

    /// The kind of record a source is, in words.
    private static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "task": "Task"
        case "email": "Email"
        case "occurrence": "Calendar event"
        case "plan": "Today's plan"
        case "evidence": "Extracted evidence"
        case "proposal": "Event to review"
        case "idea": "Idea"
        case "news": "News item"
        case "source": "Source status"
        default: kind
        }
    }

    /// `text` as a web address to offer as a link, or `nil` when it is not `http` or `https` with a host.
    private static func webLink(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
            url.host() != nil
        else { return nil }
        return url
    }
}
