// The authorization for an owner-initiated page retrieval (NEWS-01, SEC-02): only a link the owner captured, from the
// host or a paired device, to a public https address; never Apple News shares or links found inside content.

import Foundation
import LisaDomain
import LisaHTTP
import LisaHTTPSources
import LisaPorts

/// A page retrieval the owner asked for by capturing a link.
///
/// It can only be made from a ``Capture`` of kind `link` by the local owner or a paired device. Text captures (whose
/// links are content), Apple News shares (kept as shared content and never fetched), and anything initiated by the
/// runtime, a model or the demonstration are refused, so a retrieval is always tied to an explicit owner action.
public struct OwnerPageRequest: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    /// Hosts of Apple News share links, which are never fetched (plan §5.3 decision 9). A defense in depth: the
    /// capture kind is the primary rule.
    static let appleNewsHosts = ["apple.news"]

    public let captureID: CaptureID
    /// The captured address after the URL policy, without a fragment.
    public let url: URL

    public init(capture: Capture) throws(ConnectorError) {
        switch capture.kind {
        case .link:
            break
        case .sharedAppleNews:
            throw ConnectorError(.unsupported, "Apple News items are kept as shared content and are never retrieved")
        case .idea, .text:
            throw ConnectorError(
                .permissionDenied, "only a link the owner captured is retrieved; links inside text are never fetched")
        }
        switch capture.principal {
        case .localOwner, .pairedDevice:
            break
        case .runtime, .model, .demonstration:
            throw ConnectorError(.permissionDenied, "a page is retrieved only for a link the owner captured")
        }
        guard let text = capture.url?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
            let url = URL(string: text)
        else { throw ConnectorError(.configuration, "the captured link is not a valid address") }
        guard url.scheme?.lowercased() == "https" else {
            throw ConnectorError(.unsupported, "Lisa retrieves only https pages; the captured link is not https")
        }
        let checked = try AddressResolution.check(url, label: "the captured link").get()
        if Self.isAppleNews(checked) {
            throw ConnectorError(.unsupported, "Apple News links are kept as shared content and are never retrieved")
        }
        captureID = capture.id
        self.url = checked
    }

    static func isAppleNews(_ url: URL) -> Bool {
        guard let host = URLComponents(url: url, resolvingAgainstBaseURL: true)?.host?.lowercased() else {
            return false
        }
        let name = host.hasSuffix(".") ? String(host.dropLast()) : host
        return appleNewsHosts.contains { name == $0 || name.hasSuffix(".\($0)") }
    }

    public var description: String { "page retrieval for capture \(captureID) at \(URLPolicy.origin(of: url))" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: ["request": description]) }
}
