// A capture being written or shared: an idea, text, a link, or content shared from Apple News (NEWS-04).

import Foundation
import LisaAPIContract

/// What the owner is capturing for a future brief (UI-02, IDEA-01, NEWS-04): an idea, text, a link, or content shared
/// from Apple News, which Lisa labels as shared content.
public struct CaptureDraft: Hashable, Sendable {
    /// The longest text the host saves, in characters.
    public static let maxTextCharacters = 20_000
    /// The longest address the host saves, in characters.
    public static let maxAddressCharacters = 2_048

    /// What is captured.
    public var kind: CaptureKindValue
    /// The idea or text; for a link or share, an optional note or excerpt.
    public var text: String
    /// The web address of a link or share; optional for an idea or text.
    public var url: String
    /// A title supplied with shared content, such as the article's headline.
    public var title: String

    /// A draft of `kind`.
    public init(kind: CaptureKindValue = .idea, text: String = "", url: String = "", title: String = "") {
        self.kind = kind
        self.text = text
        self.url = url
        self.title = title
    }

    /// A draft for content shared into Lisa from another app. An Apple News link (on `apple.news`), or content the
    /// caller knows came from Apple News, is an Apple News share and is labeled as shared content (NEWS-04). Any other
    /// address is a link; without an address it is text.
    public static func shared(
        url: String?, title: String? = nil, text: String? = nil, fromAppleNews: Bool = false
    ) -> CaptureDraft {
        let address = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let kind: CaptureKindValue =
            if fromAppleNews || isAppleNewsAddress(address) {
                .sharedAppleNews
            } else if address.isEmpty {
                .text
            } else {
                .link
            }
        return CaptureDraft(kind: kind, text: text ?? "", url: address, title: title ?? "")
    }

    /// Whether `address` is an Apple News link, such as `https://apple.news/...`.
    public static func isAppleNewsAddress(_ address: String) -> Bool {
        guard let host = URLComponents(string: address)?.host?.lowercased() else { return false }
        return host == "apple.news" || host.hasSuffix(".apple.news")
    }

    /// Whether this is content shared from Apple News, which Lisa labels as shared content (NEWS-04).
    public var isAppleNewsShare: Bool { kind == .sharedAppleNews }

    /// A label for the draft's kind.
    public var label: String {
        switch kind {
        case .idea: "Idea"
        case .text: "Text"
        case .link: "Link"
        case .sharedAppleNews: "Shared from Apple News"
        }
    }

    /// The problems that keep the draft from being saved, checked as the host checks them; empty when it can be saved.
    public func validate() -> [CaptureValidationIssue] {
        var issues: [CaptureValidationIssue] = []
        let text = trimmed(self.text)
        let address = trimmed(url)
        if let text, text.count > Self.maxTextCharacters { issues.append(.textTooLong(limit: Self.maxTextCharacters)) }
        if let address {
            if address.count > Self.maxAddressCharacters {
                issues.append(.addressTooLong(limit: Self.maxAddressCharacters))
            } else if !Self.isWebAddress(address) {
                issues.append(.invalidAddress)
            }
        }
        switch kind {
        case .idea, .text:
            if text == nil, address == nil { issues.append(.emptyText) }
        case .link, .sharedAppleNews:
            if address == nil { issues.append(.missingAddress) }
        }
        return issues
    }

    /// The capture request for this draft from `channel`, with surrounding whitespace removed and empty fields
    /// omitted.
    public func request(channel: CaptureChannelValue) -> CaptureRequestDTO {
        CaptureRequestDTO(kind: kind, text: trimmed(text), url: trimmed(url), title: trimmed(title), channel: channel)
    }

    /// Whether `address` is an `http` or `https` address with a host.
    static func isWebAddress(_ address: String) -> Bool {
        guard let parsed = URL(string: address), let scheme = parsed.scheme?.lowercased(),
            scheme == "https" || scheme == "http", let host = parsed.host, !host.isEmpty
        else { return false }
        return true
    }

    private func trimmed(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
