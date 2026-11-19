// Why a notification payload could not be built; every case points to a defect in Lisa, never to the owner's content.

/// A presentation that cannot become a valid APNs payload. Nothing is sent.
public enum APNsPayloadError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The category is not one of the contract's notification categories, which the apps register.
    case unknownCategory
    /// A title or body localization key is empty, too long or has characters other than letters, digits and `_.-`.
    case invalidLocalizationKey
    /// An opaque identifier is empty or longer than the payload allows.
    case invalidIdentifier
    /// Even the generic payload exceeds APNs's limit.
    case tooLarge(bytes: Int, limit: Int)
    /// JSON encoding failed.
    case encodingFailed

    public var description: String {
        switch self {
        case .unknownCategory: "the notification category is not one the apps register"
        case .invalidLocalizationKey: "a notification localization key is not valid"
        case .invalidIdentifier: "a notification identifier is empty or too long"
        case .tooLarge(let bytes, let limit): "the notification payload is \(bytes) bytes, more than APNs's \(limit)"
        case .encodingFailed: "the notification payload could not be encoded"
        }
    }
}
