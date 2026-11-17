// How long ago something happened, in Lisa's words ("3 hours"), kept current while it is on screen.

import Foundation
import LisaPresentation
import SwiftUI

/// "<prefix> 3 hours ago", with the age in `AgePhrase`'s words, updated every minute.
struct AgeText: View {
    /// The words before the age, such as "Saved".
    let prefix: String
    /// When it happened.
    let date: Date

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(verbatim: "\(prefix) \(AgePhrase.english(context.date.timeIntervalSince(date))) ago")
        }
    }
}
