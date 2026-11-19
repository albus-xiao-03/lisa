// The versioned cursor of a conditionally fetched document: the validators of the last full download, the address
// configuration they belong to, and when that download happened.

import Foundation
import LisaHTTP
import LisaTime

/// What a feed connector keeps between fetches. Text that is malformed, too long, of another version or with invalid
/// values decodes to nil, which costs one full download and nothing else.
package struct ConditionalCursor: Hashable, Sendable {
    package static let version = 1
    package static let maxEncodedLength = 2_048
    package static let maxEntityTagLength = 512
    package static let maxDateLength = 64
    package static let maxBindingLength = 64

    /// The ``ResolvedAddress/binding`` of the address the validators came from.
    package var binding: String
    /// The entity tag of the last full download, exactly as the server sent it (RFC 9110 §8.8.3).
    package var entityTag: String?
    /// The Last-Modified value of the last full download, exactly as sent (RFC 9110 §13.1.3).
    package var lastModified: String?
    /// When the last full (200) download happened.
    package var fullRetrievalAt: Date

    package var hasValidators: Bool { entityTag != nil || lastModified != nil }

    package init(binding: String, entityTag: String?, lastModified: String?, fullRetrievalAt: Date) {
        self.binding = binding
        self.entityTag = entityTag
        self.lastModified = lastModified
        self.fullRetrievalAt = fullRetrievalAt.roundedToMilliseconds
    }

    /// The cursor after a full download: the response's validators, where they are valid.
    package init(binding: String, response: HTTPResponse, retrievedAt: Date) {
        self.init(
            binding: binding, entityTag: Self.entityTag(response.header("ETag")),
            lastModified: Self.lastModified(response.header("Last-Modified")), fullRetrievalAt: retrievedAt)
    }

    /// The cursor after a 304: the same full-download time, with any validators the 304 repeats replacing the stored
    /// ones (RFC 9111 §4.3.4).
    package func refreshed(by response: HTTPResponse) -> ConditionalCursor {
        var next = self
        if let tag = Self.entityTag(response.header("ETag")) { next.entityTag = tag }
        if let date = Self.lastModified(response.header("Last-Modified")) { next.lastModified = date }
        return next
    }

    /// The cursor as stored: compact JSON with sorted keys, so equal cursors are equal text.
    package func encoded() -> String {
        let wire = Wire(
            v: Self.version, b: binding, e: entityTag, m: lastModified, f: fullRetrievalAt.millisecondsSince1970)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(wire) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The stored cursor, or nil when `text` is absent or not a valid cursor of this version.
    package static func decode(_ text: String?) -> ConditionalCursor? {
        guard let text, !text.isEmpty, text.utf8.count <= maxEncodedLength,
            let wire = try? JSONDecoder().decode(Wire.self, from: Data(text.utf8)), wire.v == version,
            !wire.b.isEmpty, wire.b.utf8.count <= maxBindingLength, wire.f >= 0
        else { return nil }
        // Stored values must still be values Lisa would have stored; anything else is ignored as a whole.
        if let tag = wire.e, entityTag(tag) != tag { return nil }
        if let date = wire.m, lastModified(date) != date { return nil }
        return ConditionalCursor(
            binding: wire.b, entityTag: wire.e, lastModified: wire.m,
            fullRetrievalAt: Date(millisecondsSince1970: wire.f))
    }

    /// A syntactically valid entity tag, limited to visible ASCII: `[W/] DQUOTE *etagc DQUOTE` with etagc in
    /// `%x21 / %x23-7E`. Header text is decoded as UTF-8, so obs-text bytes could not be sent back unchanged.
    package static func entityTag(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), value.utf8.count <= maxEntityTagLength else {
            return nil
        }
        var opaque = Substring(value)
        if opaque.hasPrefix("W/") { opaque = opaque.dropFirst(2) }
        guard opaque.utf8.count >= 2, opaque.hasPrefix("\""), opaque.hasSuffix("\"") else { return nil }
        let inner = opaque.utf8.dropFirst().dropLast()
        guard inner.allSatisfy({ $0 == 0x21 || (0x23...0x7E).contains($0) }) else { return nil }
        return value
    }

    /// A valid HTTP-date, kept exactly as the server sent it; servers commonly match it exactly.
    package static func lastModified(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty,
            value.utf8.count <= maxDateLength, value.utf8.allSatisfy({ (0x20...0x7E).contains($0) }),
            HTTPDate.parse(value) != nil
        else { return nil }
        return value
    }

    /// The stored form. Short keys keep the cursor small.
    private struct Wire: Codable {
        var v: Int
        var b: String
        var e: String?
        var m: String?
        var f: Int64
    }
}
