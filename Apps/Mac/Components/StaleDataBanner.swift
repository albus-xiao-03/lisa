// The notice above data that is not the host's current answer: a saved copy while the host can't be reached, data kept
// after a refresh failed, or a saved copy of an earlier day. Its age is always shown (UI-03).

import Foundation
import SwiftUI

/// Says that the data below may be out of date, and how old it is.
struct StaleDataBanner: View {
    /// When the host returned the data.
    let fetchedAt: Date
    /// Whether the data is the copy saved on this Mac, shown because the host can't be reached.
    let isSavedCopy: Bool
    /// Whether it is a saved copy of a day before today.
    let isEarlierDay: Bool

    var body: some View {
        Label(
            title: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.footnote.weight(.semibold))
                    AgeText(prefix: isSavedCopy ? "Saved" : "Last updated", date: fetchedAt)
                        .font(.footnote)
                }
            },
            icon: { Image(systemName: "clock.arrow.circlepath") }
        )
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        if isEarlierDay { return "A saved copy from an earlier day. It may be out of date." }
        if isSavedCopy { return "A saved copy, because Lisa's host can't be reached. It may be out of date." }
        return "Lisa couldn't update this, so it may be out of date."
    }
}
