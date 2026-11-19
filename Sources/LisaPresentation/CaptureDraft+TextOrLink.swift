// Turning what Siri or a shortcut passes as "text or a link" into a capture for a future brief.

import Foundation
import LisaAPIContract

extension CaptureDraft {
    /// A draft for `input`, which is text or one web address (SIRI-01: save supplied text or a URL for a future brief).
    /// A lone `http` or `https` address is a link, or an Apple News share labeled as shared content (NEWS-04); anything
    /// else is text, including text with addresses inside it, which are never fetched.
    public static func textOrLink(_ input: String) -> CaptureDraft {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace), isWebAddress(trimmed) {
            return shared(url: trimmed)
        }
        return CaptureDraft(kind: .text, text: input)
    }
}
