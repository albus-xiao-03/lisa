// The seam to the app's connection setup: which host address requests go to, and switching to a new one.

import Foundation
import LisaClient

/// Points the app's transport at a host address and keeps the choice (NOTIFY-07: a configurable host endpoint). The
/// app implements it: it stores the address, which is not a secret, and makes the client's transport, such as a
/// `URLSessionTransport` with its server-trust evaluator, send to it.
@MainActor
public protocol HostEndpointConfiguring: AnyObject {
    /// The address requests go to now, or `nil` when none is configured.
    var configuredEndpoint: HostEndpoint? { get }
    /// Sends later requests to `endpoint` and keeps the choice.
    ///
    /// - Throws: when the transport cannot use the address on this platform; the error's description is shown.
    func configure(_ endpoint: HostEndpoint) throws
}
