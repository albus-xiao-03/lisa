// Resolves a configured address (a public URL, or a secret read at use time) into a policy-checked https URL, a
// non-secret binding for stored validators, and a scrubber for the address's private parts.

import Foundation
import LisaHTTP
import LisaPorts
import LisaRedaction
import LisaSecrets

/// Where an address comes from, before resolution.
package enum AddressSource: Hashable, Sendable {
    /// A public https address from configuration.
    case url(URL)
    /// A private address kept as a secret.
    case secret(SecretReference)
}

/// A usable address for one fetch. It is never described with more than its origin.
package struct ResolvedAddress: Sendable {
    /// The policy-checked https URL, without a fragment.
    package let url: URL
    /// Ties stored validators to this configuration. For a secret it covers the reference and the origin, never the
    /// secret's value.
    package let binding: String
    /// Removes the address's path and query from text.
    package let scrubber: SecretScrubber

    package var origin: String { URLPolicy.origin(of: url) }
}

/// Address resolution and the checks that apply before anything is sent (SEC-02).
package enum AddressResolution {
    /// Resolves `source` for a request to the public internet. A secret is read here, at use time, so a missing or
    /// invalid secret is a classified configuration failure rather than a crash. Messages name the secret reference
    /// or the origin, never the address.
    package static func resolve(_ source: AddressSource, secrets: any SecretStore, subject: String) -> Result<
        ResolvedAddress, ConnectorError
    > {
        switch source {
        case .url(let url):
            return check(url, label: "the \(subject) address").map { checked in
                ResolvedAddress(
                    url: checked, binding: AddressFingerprint.hex("url\u{0}\(checked.absoluteString)"),
                    scrubber: SecretScrubber(url: checked))
            }
        case .secret(let reference):
            let label = "the \(subject) address in secret \(reference)"
            let value: String
            do {
                value = try secrets.secret(for: reference).revealed
            } catch let error as SecretStoreError {
                return .failure(ConnectorError(.configuration, "\(label) could not be read: \(error.description)"))
            } catch {
                return .failure(ConnectorError(.configuration, "\(label) could not be read"))
            }
            // A secret file often ends with a line break; an address never starts or ends with white space.
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let url = URL(string: text) else {
                return .failure(ConnectorError(.configuration, "\(label) is not a valid address"))
            }
            return check(url, label: label).map { checked in
                ResolvedAddress(
                    url: checked,
                    binding: AddressFingerprint.hex("secret\u{0}\(reference)\u{0}\(URLPolicy.origin(of: checked))"),
                    scrubber: SecretScrubber(url: checked))
            }
        }
    }

    /// Applies the URL policy for public-internet requests and refuses hosts that name a local, private or link-local
    /// destination outright. Names that resolve to such addresses are refused again when the transport connects.
    package static func check(_ url: URL, label: String) -> Result<URL, ConnectorError> {
        let scrubber = SecretScrubber(url: url)
        switch URLPolicy.validate(url, addresses: .publicOnly) {
        case .failure(let failure):
            var reason = scrubber.scrub(policyReason(failure))
            if let hint = schemeHint(url) { reason += " (\(hint))" }
            return .failure(ConnectorError(.configuration, "\(label) is not usable: \(reason)"))
        case .success(let checked):
            if namesLocalHost(checked) {
                return .failure(
                    ConnectorError(
                        .configuration,
                        "\(label) names a loopback, private or link-local host, which Lisa does not contact for this"
                            + " source"))
            }
            return .success(checked)
        }
    }

    /// `localhost` names and IP literals that a public-internet request may not reach.
    package static func namesLocalHost(_ url: URL) -> Bool {
        guard var host = URLComponents(url: url, resolvingAgainstBaseURL: true)?.host?.lowercased() else {
            return true
        }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host = String(host.dropLast()) }
        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        guard let literal = IPLiteral.parse(host) else { return false }
        return !AddressPolicy.publicOnly.permits(literal)
    }

    private static func policyReason(_ failure: HTTPFailure) -> String {
        if case .refused(let reason) = failure { return reason }
        return failure.description
    }

    /// Subscription links are often copied with a scheme that only means "subscribe over HTTP".
    private static func schemeHint(_ url: URL) -> String? {
        switch url.scheme?.lowercased() {
        case "webcal", "webcals": "replace webcal:// with https://"
        case "feed": "replace feed:// with https://"
        case "http": "use the https:// address"
        default: nil
        }
    }
}
