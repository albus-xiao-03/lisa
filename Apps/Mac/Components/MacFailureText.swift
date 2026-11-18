// Words for a screen's load failure on the Mac: the Mac app is the owner, never a paired device, so a refused
// credential means its connection to `lisa serve` was lost, not that the host removed a device.

import LisaPresentation

/// Titles, symbols and sentences for a `LoadFailure` as the Mac app shows it.
enum MacFailureText {
    /// A short title.
    static func title(of failure: LoadFailure) -> String {
        switch failure {
        case .notPaired, .revoked: "Connection to Lisa's Host Lost"
        case .unreachable: "Can't Reach Lisa's Host"
        case .notFound: "Nothing Here Yet"
        case .incompatibleHost: "Update Needed"
        case .failed: "Couldn't Load"
        }
    }

    /// The SF Symbol.
    static func symbol(of failure: LoadFailure) -> String {
        switch failure {
        case .notPaired, .revoked: "bolt.horizontal.circle"
        case .unreachable: "exclamationmark.icloud"
        case .notFound: "tray"
        case .incompatibleHost: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle"
        }
    }

    /// The sentence shown.
    static func message(of failure: LoadFailure) -> String {
        switch failure {
        case .notPaired, .revoked:
            "Lisa's host no longer accepts this app's connection, for example because lisa serve restarted. Try "
                + "again to reconnect."
        case .unreachable, .notFound, .incompatibleHost, .failed:
            failure.message
        }
    }
}
