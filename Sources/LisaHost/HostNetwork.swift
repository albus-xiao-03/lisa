// The network stack the host's adapters use: libcurl HTTP clients by purpose, and the trust store for mail. The
// platform may substitute HTTP clients (the harness does, with scripted test doubles); configuration never can.

import Foundation
import LisaCurl
import LisaDomain
import LisaHTTP

/// What an HTTP client is for. Each APNs environment gets its own client, so each keeps one long-lived connection.
public enum HTTPClientPurpose: Hashable, Sendable {
    /// Calendar and news feeds, X and Discord.
    case connectors
    /// The model endpoint.
    case model
    /// Twilio.
    case calls
    /// One APNs environment.
    case apns(APNsEnvironment)
}

/// How the host reaches the network.
public struct HostNetwork: Sendable {
    /// Makes the HTTP client for one purpose, once per host.
    public var makeHTTPClient: @Sendable (HTTPClientPurpose) throws -> any HTTPClient
    /// Replaces the system trust store for IMAP and SMTP connections. Only loopback verification sets it.
    public var mailTrustStorePath: String?
    /// The libcurl library, when it loaded; `nil` with the reason otherwise.
    public var library: Result<CurlLibraryInfo, CurlSetupError>

    public init(
        makeHTTPClient: @escaping @Sendable (HTTPClientPurpose) throws -> any HTTPClient, mailTrustStorePath: String?,
        library: Result<CurlLibraryInfo, CurlSetupError>
    ) {
        self.makeHTTPClient = makeHTTPClient
        self.mailTrustStorePath = mailTrustStorePath
        self.library = library
    }

    /// libcurl with the system trust store: Lisa's production network stack.
    public static func libcurl(userAgent: String) -> HostNetwork {
        let library = Result { () throws(CurlSetupError) in try CurlRuntime.library() }
        return HostNetwork(
            makeHTTPClient: { purpose in
                switch purpose {
                case .apns:
                    // One connection per environment, reused for as long as APNs keeps it open.
                    try CurlHTTPClient(
                        configuration: .init(userAgent: userAgent, idleHandles: 1, maxIdleConnectionSeconds: 3_600))
                case .connectors, .model, .calls:
                    try CurlHTTPClient(configuration: .init(userAgent: userAgent))
                }
            }, mailTrustStorePath: nil, library: library)
    }
}
