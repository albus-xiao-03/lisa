// The seam through which models report each exchange with the host, so one place tracks connectivity (no polling).

import Foundation

/// Receives what each exchange with the host showed about the connection. `ConnectivityModel` is the app's reporter;
/// every other model reports to it after reading from or writing to the host.
@MainActor
public protocol HostContactReporting: AnyObject {
    /// Records one exchange. A removal by the host (`.revoked`) also clears the data a removed device must stop
    /// showing before this returns.
    func record(_ contact: HostContact) async
}
