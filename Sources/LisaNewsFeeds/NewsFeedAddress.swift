// Where an RSS or Atom feed is read from: a public address, or a private one kept as a secret (NEWS-01).

import Foundation
import LisaHTTP
import LisaHTTPSources
import LisaSecrets

/// The address of a news feed.
///
/// A private feed address can carry a credential in its path or query, so descriptions, debug descriptions and mirrors
/// show only the origin or the secret reference, never a path or query.
public enum NewsFeedAddress: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    /// A public https address.
    case url(URL)
    /// A private address kept as a secret and read at each fetch. It must be an https address that the URL policy
    /// accepts for public-internet requests.
    case secretURL(SecretReference)

    public var description: String {
        switch self {
        case .url(let url): "the feed address at \(URLPolicy.origin(of: url))"
        case .secretURL(let reference): "the feed address in secret \(reference)"
        }
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: ["address": description]) }

    var source: AddressSource {
        switch self {
        case .url(let url): .url(url)
        case .secretURL(let reference): .secret(reference)
        }
    }
}
