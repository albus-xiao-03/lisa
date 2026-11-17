// One block of the rundown: its times, title and kind, and whether it is a suggestion, locked, done or set aside.

import Foundation
import LisaAPIContract
import SwiftUI

/// A planned block as the rundown shows it, in the rundown's own zone. At accessibility text sizes the times move
/// above the title.
struct PlanBlockRow: View {
    let block: PlanBlockDTO
    let zone: TimeZone
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(times)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Label(block.title.isEmpty ? "Untitled block" : block.title, systemImage: symbol)
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !block.explanation.isEmpty {
                    Text(block.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var times: String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)
        return "\(block.start.formatted(style)) – \(block.end.formatted(style))"
    }

    private var symbol: String {
        switch block.kind {
        case "fixedEvent": "calendar"
        case "task": "checkmark.circle"
        case "idea": "lightbulb"
        default: "circle"
        }
    }

    /// The block's state when it is not simply accepted, and whether its times may change.
    private var status: String? {
        var parts: [String] = []
        switch block.state {
        case "proposed": parts.append("Suggested")
        case "locked": parts.append("Locked")
        case "completed": parts.append("Done")
        case "rejected": parts.append("Declined")
        case "deferred": parts.append("Deferred")
        default: break
        }
        if block.provisional { parts.append("Times may change") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
