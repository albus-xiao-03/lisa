// One screen's data in every state: loading, a failure with nothing to show, the screen's empty state, or the data,
// with a notice and its age whenever it is not the host's current answer (UI-03).

import LisaClient
import LisaPresentation
import SwiftUI

/// Shows a screen's `LoadState`.
///
/// - Nothing shown yet: a progress indicator.
/// - A failure with nothing to show: why, with Try Again; when the device is not paired or was removed, a way to the
///   connection screen instead. A missing item (`.notFound`) is the screen's empty state.
/// - Data: `content`, or the empty state. Whenever the data is not the host's current answer (a saved copy, or data
///   kept after a refresh failed), `StaleDataBanner` above it says so and shows its age: cached data is never shown as
///   current.
struct LoadStateView<Value: Sendable, Content: View>: View {
    let state: LoadState<Value>
    let emptyTitle: String
    let emptySystemImage: String
    let emptyMessage: String
    /// Whether a value has nothing to show.
    let isEmpty: (Value) -> Bool
    /// Whether the data shown is a saved copy of an earlier day.
    var isEarlierDay = false
    /// Reads the data again.
    let retry: @MainActor () async -> Void
    /// The data, as the screen shows it.
    @ViewBuilder let content: (ReadResult<Value>) -> Content

    @Environment(CompanionNavigation.self) private var navigation

    var body: some View {
        if let result = state.result {
            shown(result)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if state.isStale {
                        StaleDataBanner(
                            fetchedAt: result.fetchedAt, isSavedCopy: result.source == .cache,
                            isEarlierDay: isEarlierDay)
                    }
                }
        } else if let failure = state.failure {
            unavailable(failure)
        } else {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func shown(_ result: ReadResult<Value>) -> some View {
        if isEmpty(result.value) {
            ContentUnavailableView(emptyTitle, systemImage: emptySystemImage, description: Text(emptyMessage))
        } else {
            content(result)
        }
    }

    @ViewBuilder
    private func unavailable(_ failure: LoadFailure) -> some View {
        if failure == .notFound {
            ContentUnavailableView(emptyTitle, systemImage: emptySystemImage, description: Text(emptyMessage))
        } else {
            ContentUnavailableView(
                label: { Label(Self.title(of: failure), systemImage: Self.symbol(of: failure)) },
                description: { Text(failure.message) },
                actions: {
                    if failure.hidesData {
                        Button("Open Connection") { navigation.show(.connection) }
                    } else {
                        Button("Try Again") { Task { await retry() } }
                    }
                })
        }
    }

    private static func title(of failure: LoadFailure) -> String {
        switch failure {
        case .notPaired: "Not Paired"
        case .revoked: "Removed by Your Host"
        case .unreachable: "Can't Reach Your Lisa Host"
        case .notFound: "Nothing Here Yet"
        case .incompatibleHost: "Update Needed"
        case .failed: "Couldn't Load"
        }
    }

    private static func symbol(of failure: LoadFailure) -> String {
        switch failure {
        case .notPaired: "link.badge.plus"
        case .revoked: "person.crop.circle.badge.xmark"
        case .unreachable: "wifi.exclamationmark"
        case .notFound: "tray"
        case .incompatibleHost: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle"
        }
    }
}
