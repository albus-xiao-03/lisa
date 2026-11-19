// Why Siri or Shortcuts could not list the tasks or reminders to choose from.

import Foundation
import LisaClient

/// Why the tasks or reminders could not be listed for an App Intent (SIRI-01). The message is a sentence Siri can say;
/// it never contains the owner's content.
public struct SiriLookupError: Error, Hashable, Sendable, CustomStringConvertible {
    /// What is listed.
    public enum Listing: String, Hashable, Sendable {
        case tasks
        case reminders
    }

    /// A sentence for Siri.
    public var message: String

    /// An error with `message`.
    public init(message: String) {
        self.message = message
    }

    /// The error for listing `listing` after `failure`.
    init(_ failure: LoadFailure, listing: Listing) {
        let items = listing.rawValue
        switch failure {
        case .notPaired: message = "This device isn't paired with a Lisa host. Open Lisa to pair it."
        case .revoked: message = "Your Lisa host removed this device. Open Lisa to pair it again."
        case .unreachable: message = "Lisa's host can't be reached, and no \(items) are saved on this device."
        case .notFound: message = "Lisa found no \(items)."
        case .incompatibleHost: message = failure.message
        case .failed(let reason): message = "Lisa couldn't list your \(items): \(SiriReply.clause(reason))."
        }
    }

    public var description: String { message }
}
