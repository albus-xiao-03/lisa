// Reads a response's Content-Type (media type and charset) and Content-Encoding, and refuses content codings that
// Lisa did not ask for.

import Foundation
import LisaHTTP
import LisaPorts

/// A parsed Content-Type value (RFC 9110 §8.3.1). Only the essence and the charset parameter are kept.
package struct MediaType: Hashable, Sendable {
    /// The lower-cased `type/subtype`.
    package let essence: String
    /// The lower-cased charset label, without quotes.
    package let charset: String?

    /// Parses a field value; nil when it is absent or not `type/subtype`.
    package init?(_ value: String?) {
        guard let value, value.utf8.count <= 1_024 else { return nil }
        let parts = value.split(separator: ";", omittingEmptySubsequences: false)
        let essence = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        let halves = essence.split(separator: "/", omittingEmptySubsequences: false)
        guard halves.count == 2, halves.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy(Self.isTokenByte) }) else {
            return nil
        }
        self.essence = essence
        var charset: String?
        for parameter in parts.dropFirst() {
            let pair = parameter.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "charset" else {
                continue
            }
            var label = pair[1].trimmingCharacters(in: .whitespaces)
            if label.count >= 2, label.hasPrefix("\""), label.hasSuffix("\"") {
                label = String(label.dropFirst().dropLast())
            }
            let lowered = label.lowercased()
            if !lowered.isEmpty, lowered.utf8.count <= 40, lowered.utf8.allSatisfy(Self.isTokenByte) {
                charset = lowered
            }
        }
        self.charset = charset
    }

    /// The media type of a response, or nil when it has none or an invalid one.
    package static func of(_ response: HTTPResponse) -> MediaType? {
        MediaType(response.header("Content-Type"))
    }

    /// RFC 9110 token characters.
    package static func isTokenByte(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
            || "!#$%&'*+-.^_`|~".utf8.contains(byte)
    }
}

/// Content codings (RFC 9110 §8.4). Requests ask for `identity`, and the transport does not decode compressed
/// content, so coded content cannot be read.
package enum ContentCoding {
    /// A failure when `response` carries a content coding other than identity; nil otherwise.
    package static func error(in response: HTTPResponse, subject: String) -> ConnectorError? {
        guard let value = response.header("Content-Encoding") else { return nil }
        let codings = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && $0 != "identity" }
        guard !codings.isEmpty else { return nil }
        let names = codings.prefix(3).map { coding in
            coding.utf8.count <= 20 && coding.utf8.allSatisfy(MediaType.isTokenByte) ? coding : "unrecognized"
        }
        return ConnectorError(
            .unsupported,
            "the server sent the \(subject) with the \(names.joined(separator: ", ")) content coding, although Lisa"
                + " asked for uncompressed content and does not decode it")
    }
}
