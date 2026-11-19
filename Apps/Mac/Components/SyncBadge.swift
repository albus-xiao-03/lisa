// A quiet mark on an item whose change waits to reach the host, or whose change the host refused because the item
// changed there.

import SwiftUI

/// Marks an item's sync state (UI-03): waiting until the host confirms, or changed on the host.
struct SyncBadge: View {
    /// The state marked.
    enum Kind {
        /// A change waits in the offline queue.
        case waiting
        /// The host refused a change because the item changed there.
        case conflict
    }

    let kind: Kind

    var body: some View {
        Group {
            switch kind {
            case .waiting:
                Label("Waiting to sync", systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
            case .conflict:
                Label("Changed on Lisa's host", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }
}
