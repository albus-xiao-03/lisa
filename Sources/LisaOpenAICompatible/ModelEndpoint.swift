// The model endpoint's request address and the network policy derived from it: which addresses may be reached.

import Foundation
import LisaHTTP
import LisaInference

/// A validated Chat Completions endpoint.
///
/// The address policy follows from the configured address alone, before any DNS lookup (SEC-02):
/// - plain `http` only to a loopback address (`127.0.0.0/8`, `::1` or `localhost`), with `.loopbackOnly`;
/// - `https` to `localhost` or to a loopback or private IP literal, with `.allowLocalNetworks`: an explicitly
///   configured local model server;
/// - `https` to any other host, with `.publicOnly`: a host name that resolves only to local addresses is refused when
///   the connection is opened, so a local server must be named by its IP address.
///
/// Link-local (including cloud metadata addresses such as 169.254.169.254), unspecified, multicast and reserved
/// literals are refused here, as the HTTP client refuses them under every policy. The descriptor's location matches:
/// `.localNetwork` for the first two, `.remote` for the third.
public struct ModelEndpoint: Hashable, Sendable {
    /// Where completions are requested: the base address followed by `/chat/completions`.
    public let completionsURL: URL
    public let addresses: AddressPolicy
    public let location: ModelLocation
    /// The scheme, host and port: all that is ever shown of the address.
    public let origin: String

    /// Validates `base`, the Chat Completions base address such as `https://models.example.com/v1`. An address that
    /// already ends in `/chat/completions` is used as it is.
    public init(base: URL) throws(OpenAICompatibleConfigurationError) {
        guard let components = URLComponents(url: base, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(), let rawHost = components.host, !rawHost.isEmpty
        else { throw OpenAICompatibleConfigurationError("the model endpoint must be a complete https or http address") }
        guard components.user == nil, components.password == nil else {
            throw OpenAICompatibleConfigurationError(
                "the model endpoint must not contain a user name or password; reference the API key instead")
        }
        guard components.query == nil, components.fragment == nil else {
            throw OpenAICompatibleConfigurationError("the model endpoint must not contain a query or fragment")
        }
        let host = rawHost.hasPrefix("[") && rawHost.hasSuffix("]") ? String(rawHost.dropFirst().dropLast()) : rawHost
        let reach = Self.reach(of: host)
        let policy: AddressPolicy
        switch (scheme, reach) {
        case ("http", .loopback):
            policy = .loopbackOnly
        case ("http", _):
            throw OpenAICompatibleConfigurationError(
                "plain http is allowed only to a loopback model server (127.0.0.1, ::1 or localhost); use https")
        case ("https", .loopback), ("https", .privateNetwork):
            policy = .allowLocalNetworks
        case ("https", .named), ("https", .publicInternet):
            policy = .publicOnly
        case ("https", .refused):
            throw OpenAICompatibleConfigurationError(
                "the model endpoint's address is link-local, unspecified, multicast or reserved, which Lisa never"
                    + " connects to")
        default:
            throw OpenAICompatibleConfigurationError(
                "the model endpoint must use https (or http to a loopback address)")
        }
        var request = components
        let path = request.percentEncodedPath
        var trimmed = Substring(path)
        while trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
        if !trimmed.hasSuffix("/chat/completions") {
            request.percentEncodedPath = String(trimmed) + "/chat/completions"
        }
        guard let url = request.url else {
            throw OpenAICompatibleConfigurationError("the model endpoint must be a complete https or http address")
        }
        switch URLPolicy.validate(url, addresses: policy) {
        case .success(let validated): completionsURL = validated
        case .failure(let failure):
            throw OpenAICompatibleConfigurationError("the model endpoint is refused: \(failure)")
        }
        addresses = policy
        location = policy == .publicOnly ? .remote : .localNetwork
        origin = URLPolicy.origin(of: url)
    }

    /// Where a host points, judged from its literal form alone.
    enum Reach: Hashable, Sendable {
        case loopback
        case privateNetwork
        case publicInternet
        /// A host name other than `localhost`: only DNS can say where it points.
        case named
        /// An address the HTTP client never connects to.
        case refused
    }

    static func reach(of host: String) -> Reach {
        let name = host.lowercased()
        if name == "localhost" || name == "localhost." { return .loopback }
        guard let address = IPLiteral.parse(name) else { return .named }
        switch address.addressClass {
        case .loopback: return .loopback
        case .privateNetwork: return .privateNetwork
        case .publicInternet: return .publicInternet
        case .linkLocal, .unspecified, .multicastOrBroadcast, .reserved: return .refused
        }
    }
}
