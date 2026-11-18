// Which host the Mac app's screens use: the host running in this app, a running `lisa serve` reached as a client, or
// none yet and why, in words for the window and the settings screen.

import Foundation

/// Where the app's screens get their data (UI-01, ARCH-03). The data-directory lock decides: the app runs the host
/// itself only when no other runtime owns the data directory, so one data directory never has two hosts.
enum HostMode: Hashable, Sendable {
    /// The app is opening its host or looking for `lisa serve`.
    case starting
    /// The host runs in this app. `deviceListener` is where paired devices reach its network API; `apiProblem` says
    /// why the API is not served, when it is not.
    case embedded(deviceListener: String, apiProblem: String?)
    /// A running `lisa serve`, process `processID`, owns the data directory since `since`; the app is its client.
    case client(processID: Int32, since: Date)
    /// The app has no host. `reason` says why; `canRetry` says whether trying again may help.
    case unavailable(reason: String, canRetry: Bool)

    /// A short name for the mode.
    var title: String {
        switch self {
        case .starting: "Starting"
        case .embedded: "Running on this Mac"
        case .client: "Connected to lisa serve"
        case .unavailable: "Not running"
        }
    }

    /// A sentence about the mode, for the settings screen and assistive technologies.
    var message: String {
        switch self {
        case .starting:
            "Lisa is starting its host, or looking for one that already runs."
        case .embedded(let listener, let problem):
            if let problem {
                "Lisa runs its host in this app. Its network API isn't running, so your iPhone, iPad and lisa "
                    + "commands can't reach it: \(problem)."
            } else {
                "Lisa runs its host in this app. Paired devices reach it at \(listener), and lisa commands connect "
                    + "to this app while it runs."
            }
        case .client(let processID, _):
            "lisa serve (process \(processID)) runs your host, so this app connects to it instead of running a "
                + "second one."
        case .unavailable(let reason, _):
            "Lisa can't run its host: \(reason)"
        }
    }

    /// The SF Symbol for the mode.
    var systemImage: String {
        switch self {
        case .starting: "hourglass"
        case .embedded(_, let problem): problem == nil ? "desktopcomputer" : "exclamationmark.triangle"
        case .client: "terminal"
        case .unavailable: "exclamationmark.octagon"
        }
    }

    /// Whether the host runs in this app.
    var isEmbedded: Bool {
        if case .embedded = self { return true }
        return false
    }

    /// Whether the app is a client of `lisa serve`.
    var isClient: Bool {
        if case .client = self { return true }
        return false
    }

    /// Whether the app is starting.
    var isStarting: Bool { self == .starting }

    /// Whether trying again may give the app a host.
    var canRetry: Bool {
        switch self {
        case .unavailable(_, let canRetry): canRetry
        case .client: true
        case .starting, .embedded: false
        }
    }
}
