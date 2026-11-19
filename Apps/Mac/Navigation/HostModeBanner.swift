// The notice above every screen when the host needs attention: starting, not running, running without its network
// API, or a `lisa serve` that this app can no longer reach.

import LisaPresentation
import SwiftUI

/// Says when the screens can't use the host as usual, with what the owner can do. It shows nothing while the host runs
/// normally, in this app or in `lisa serve`; the sidebar's foot always names the mode.
struct HostModeBanner: View {
    let session: MacSession
    let connectivity: ConnectivityModel

    var body: some View {
        if let notice {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(notice.text, systemImage: notice.systemImage)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if session.host.isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else if notice.offersRetry {
                    Button("Try Again") {
                        Task { await session.retryHost() }
                    }
                    .accessibilityHint("Connects to lisa serve if it runs, or runs Lisa's host in this app.")
                } else if notice.offersRestart {
                    Button("Restart Host") {
                        Task { await session.restartHost() }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
            .accessibilityElement(children: .contain)
        }
    }

    /// What the banner says and offers, or `nil` when the host runs normally.
    private var notice: (text: String, systemImage: String, offersRetry: Bool, offersRestart: Bool)? {
        let mode = session.host.mode
        switch mode {
        case .starting:
            return (mode.message, mode.systemImage, false, false)
        case .unavailable:
            return (mode.message, mode.systemImage, mode.canRetry, false)
        case .embedded(_, let problem):
            guard problem != nil else { return nil }
            return (mode.message, mode.systemImage, false, true)
        case .client:
            switch connectivity.status {
            case .unreachable, .revoked, .notPaired:
                return (
                    "Lisa can't reach lisa serve right now. If it stopped or restarted, try again.",
                    "bolt.horizontal.circle", true, false
                )
            case .unknown, .reachable, .incompatible:
                return nil
            }
        }
    }
}
