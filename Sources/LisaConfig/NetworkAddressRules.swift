// Rules for configured network addresses: host names, https URLs, model endpoints and the API bind address.

import Foundation

/// Format rules for network addresses in the configuration. Refusals never quote the refused value.
enum NetworkAddressRules {
    /// A DNS host name: dot-separated labels of ASCII letters, digits and hyphens (1 to 63 bytes each, no hyphen at
    /// either end), at most 253 bytes, optionally ending in a dot. The last label cannot be all digits.
    static func isDNSName(_ text: String) -> Bool {
        var name = Substring(text)
        if name.hasSuffix(".") { name = name.dropLast() }
        guard !name.isEmpty, name.utf8.count <= 253 else { return false }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        let wellFormed = labels.allSatisfy { label in
            (1...63).contains(label.utf8.count) && label.first != "-" && label.last != "-"
                && label.unicodeScalars.allSatisfy { scalar in
                    scalar.isASCII
                        && (scalar.properties.isAlphabetic || (0x30...0x39).contains(scalar.value) || scalar == "-")
                }
        }
        return wellFormed && !(labels.last?.allSatisfy(\.isNumber) ?? true)
    }

    /// A server host: a DNS name or an IP address, written without a scheme, port, path or user name.
    static func serverHost(_ text: String) -> Result<String, ValueRefusal> {
        if IPAddress(text) != nil || isDNSName(text) {
            return .success(text)
        }
        return .failure(
            ValueRefusal(
                "must be a host name such as mail.example.com or an IP address, without a scheme, port or path"))
    }

    /// An https address without embedded credentials, for calendar and news feeds.
    static func httpsURL(_ text: String) -> Result<URL, ValueRefusal> {
        checkedURL(text, allowsLoopbackHTTP: false)
    }

    /// A model endpoint: https to any host, or plain http to a loopback address only.
    static func modelEndpoint(_ text: String) -> Result<URL, ValueRefusal> {
        checkedURL(text, allowsLoopbackHTTP: true)
    }

    /// The API bind address: an IP address literal, returned with its scope.
    static func bindAddress(_ text: String) -> Result<NetworkScope, ValueRefusal> {
        guard let address = IPAddress(text) else {
            let hint = text.lowercased() == "localhost" ? "write 127.0.0.1 or ::1 instead of a host name" : nil
            return .failure(ValueRefusal("must be an IP address such as 127.0.0.1 or ::1", fix: hint))
        }
        return .success(address.scope)
    }

    /// The host part of `url`, without IPv6 brackets.
    static func host(of url: URL) -> String? {
        guard let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host, !host.isEmpty else {
            return nil
        }
        return host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    }

    private static func checkedURL(_ text: String, allowsLoopbackHTTP: Bool) -> Result<URL, ValueRefusal> {
        let example = allowsLoopbackHTTP ? "https://models.example.com/v1" : "https://example.com/feed.xml"
        guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
            let url = components.url, let host = host(of: url)
        else {
            return .failure(ValueRefusal("must be a complete address such as \(example)"))
        }
        guard components.user == nil, components.password == nil else {
            return .failure(
                ValueRefusal(
                    "must not contain a user name or password",
                    fix: "keep credentials outside this file and reference them from the setting ending in Secret"))
        }
        if let items = components.queryItems, items.contains(where: { SecretNamePolicy.suggestsSecret($0.name) }) {
            let fix =
                allowsLoopbackHTTP
                ? "reference the API key with apiKeySecret instead"
                : "an address that contains a credential is a secret: keep it outside this file and use urlSecret"
            return .failure(ValueRefusal("appears to carry a credential in its query", fix: fix))
        }
        guard IPAddress(host) != nil || isDNSName(host) else {
            return .failure(ValueRefusal("must name a valid host, such as \(example)"))
        }
        switch scheme {
        case "https":
            return .success(url)
        case "http" where allowsLoopbackHTTP && NetworkScope.of(host: host) == .loopback:
            return .success(url)
        case "http" where allowsLoopbackHTTP:
            return .failure(
                ValueRefusal(
                    "must use https; plain http is allowed only to a loopback address (127.0.0.1, ::1, localhost)"))
        case "webcal", "webcals":
            return .failure(ValueRefusal("must use https", fix: "replace webcal:// with https://"))
        default:
            return .failure(ValueRefusal("must use https, such as \(example)"))
        }
    }
}
