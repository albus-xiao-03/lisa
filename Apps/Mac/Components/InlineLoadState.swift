// One part of a screen whose data loads on its own, inside a list or form section: a small progress indicator, a
// failure with Try Again, the empty text, or the data, marked with its age when it is not current (UI-03).

import LisaClient
import LisaPresentation
import SwiftUI

/// Shows a `LoadState` inside a section, for screens that combine several kinds of data, such as Today or Settings and
/// Health. Like `LoadStateView`, it never shows cached or kept data as current.
struct InlineLoadState<Value: Sendable, Content: View>: View {
    let state: LoadState<Value>
    let emptyMessage: String
    /// Whether a value has nothing to show.
    let isEmpty: (Value) -> Bool
    /// Whether the data shown is a saved copy of an earlier day.
    var isEarlierDay = false
    /// Reads the data again.
    let retry: @MainActor () async -> Void
    /// The data, as the section shows it.
    @ViewBuilder let content: (ReadResult<Value>) -> Content

    @Environment(EmbeddedHostController.self) private var host

    var body: some View {
        if let result = state.result {
            if state.isStale {
                StaleDataBanner(
                    fetchedAt: result.fetchedAt, isSavedCopy: result.source == .cache, isEarlierDay: isEarlierDay)
            }
            if isEmpty(result.value) {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                content(result)
            }
        } else if let failure = state.failure {
            if failure == .notFound {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label(MacFailureText.message(of: failure), systemImage: MacFailureText.symbol(of: failure))
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task {
                            if failure.hidesData { await host.retry() }
                            await retry()
                        }
                    }
                    .controlSize(.small)
                }
            }
        } else {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Loading")
        }
    }
}
