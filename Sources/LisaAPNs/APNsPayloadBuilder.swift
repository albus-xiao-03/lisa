// The APNs alert payload, built from a presentation with the shared contract types: generic localized text by
// default, the item title only when the presentation carries one, never more than APNs's 4096 bytes (S10, S14).

import Foundation
import LisaAPIContract
import LisaDomain
import LisaPorts

/// A payload ready to send.
public struct APNsPayload: Hashable, Sendable {
    /// The JSON request body.
    public let json: Data
    /// The item title placed in the payload after cleaning and any shortening; nil when the payload is generic.
    public let itemTitle: String?
}

/// Builds alert payloads (plan §6.7). Only Apple-defined `aps` keys and Lisa's `lisa` object are used, never
/// `badge`, `content-available` (silent pushes), `mutable-content` or a critical-alert sound.
public enum APNsPayloadBuilder {
    /// Apple's limit for every remote notification except VoIP (S10, S14).
    public static let maxBytes = PushPayload.maxBytes
    /// The longest identifier or localization key accepted.
    public static let maxFieldBytes = 256
    /// Appended to a title that was shortened to fit.
    static let ellipsis = "\u{2026}"

    /// The payload for `presentation`. The default carries only localization keys, the category, thread and
    /// interruption level, and opaque identifiers. An item title, present only when the device opted in, is passed
    /// as the argument of the category's titled body format, shortened when needed so the payload fits.
    public static func payload(for presentation: NotificationPresentation) throws(APNsPayloadError) -> APNsPayload {
        guard let category = NotificationCategoryID(rawValue: presentation.categoryIdentifier),
            let kind = hostKind(of: category)
        else { throw .unknownCategory }
        guard isLocalizationKey(presentation.titleKey), isLocalizationKey(presentation.bodyKey) else {
            throw .invalidLocalizationKey
        }
        let identifiers = [
            presentation.notificationID, presentation.subjectKind, presentation.subjectID,
            presentation.threadIdentifier,
        ]
        guard identifiers.allSatisfy({ !$0.isEmpty && $0.utf8.count <= maxFieldBytes }) else {
            throw .invalidIdentifier
        }
        let lisa = LisaPushData(
            kind: kind, notificationID: presentation.notificationID, subjectKind: presentation.subjectKind,
            subjectID: presentation.subjectID, subjectRevision: presentation.subjectRevision)
        let generic = try encode(presentation, category: category, lisa: lisa, title: nil)
        guard generic.count <= maxBytes else { throw .tooLarge(bytes: generic.count, limit: maxBytes) }
        // The titled body format is the contract's variant of the category's body; a presentation with another body
        // key has no known titled format, so it stays generic.
        guard presentation.bodyKey == category.bodyKey, let raw = presentation.itemTitle,
            let title = APNsTitleText.cleaned(raw)
        else { return APNsPayload(json: generic, itemTitle: nil) }
        let full = try encode(presentation, category: category, lisa: lisa, title: title)
        if full.count <= maxBytes { return APNsPayload(json: full, itemTitle: title) }
        // The encoded size grows with every character kept, so the longest prefix that fits is found by bisection.
        let characters = Array(title)
        var low = 1
        var high = characters.count - 1
        var best: APNsPayload?
        while low <= high {
            let middle = (low + high) / 2
            let candidate = String(characters[..<middle]) + ellipsis
            let data = try encode(presentation, category: category, lisa: lisa, title: candidate)
            if data.count <= maxBytes {
                best = APNsPayload(json: data, itemTitle: candidate)
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return best ?? APNsPayload(json: generic, itemTitle: nil)
    }

    /// The `aps.interruption-level` string (S14). Lisa never uses `critical`.
    public static func interruptionLevel(_ level: InterruptionLevel) -> String {
        switch level {
        case .passive: "passive"
        case .active: "active"
        case .timeSensitive: "time-sensitive"
        }
    }

    /// The host's category name sent as `lisa.kind`, found through the contract's own mapping from kinds.
    static func hostKind(of category: NotificationCategoryID) -> String? {
        NotificationCategory.allCases.first { NotificationCategoryID(kind: $0.rawValue) == category }?.rawValue
    }

    /// Letters, digits, `_`, `.` and `-`, at most ``maxFieldBytes`` bytes.
    static func isLocalizationKey(_ key: String) -> Bool {
        (1...maxFieldBytes).contains(key.utf8.count)
            && key.utf8.allSatisfy { byte in
                (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                    || byte == 0x5F || byte == 0x2E || byte == 0x2D
            }
    }

    private static func encode(
        _ presentation: NotificationPresentation, category: NotificationCategoryID, lisa: LisaPushData, title: String?
    ) throws(APNsPayloadError) -> Data {
        let alert =
            if let title {
                PushAlert(titleLocKey: presentation.titleKey, locKey: category.titledBodyKey, locArgs: [title])
            } else {
                PushAlert(titleLocKey: presentation.titleKey, locKey: presentation.bodyKey)
            }
        let aps = PushAPS(
            alert: alert, category: category.rawValue, threadID: presentation.threadIdentifier,
            interruptionLevel: interruptionLevel(presentation.level))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(PushPayload(aps: aps, lisa: lisa))
        } catch {
            throw .encodingFailed
        }
    }
}
