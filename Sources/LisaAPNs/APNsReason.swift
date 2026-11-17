// The documented APNs error reason strings, each with its documented status code and Apple's never-retry list (S13).

/// A `reason` value from Apple's "Response error strings" table. Raw values are the exact strings APNs sends.
public enum APNsReason: String, Hashable, Sendable, CaseIterable {
    case badCollapseID = "BadCollapseId"
    case badDeviceToken = "BadDeviceToken"
    case badExpirationDate = "BadExpirationDate"
    case badMessageID = "BadMessageId"
    case badPriority = "BadPriority"
    case badTopic = "BadTopic"
    case deviceTokenNotForTopic = "DeviceTokenNotForTopic"
    case duplicateHeaders = "DuplicateHeaders"
    case idleTimeout = "IdleTimeout"
    case invalidPushType = "InvalidPushType"
    case missingDeviceToken = "MissingDeviceToken"
    case missingTopic = "MissingTopic"
    case payloadEmpty = "PayloadEmpty"
    case topicDisallowed = "TopicDisallowed"
    case badCertificate = "BadCertificate"
    case badCertificateEnvironment = "BadCertificateEnvironment"
    case expiredProviderToken = "ExpiredProviderToken"
    case forbidden = "Forbidden"
    case invalidProviderToken = "InvalidProviderToken"
    case missingProviderToken = "MissingProviderToken"
    case unrelatedKeyIDInToken = "UnrelatedKeyIdInToken"
    case badEnvironmentKeyIDInToken = "BadEnvironmentKeyIdInToken"
    case badPath = "BadPath"
    case methodNotAllowed = "MethodNotAllowed"
    case expiredToken = "ExpiredToken"
    case unregistered = "Unregistered"
    case payloadTooLarge = "PayloadTooLarge"
    case tooManyProviderTokenUpdates = "TooManyProviderTokenUpdates"
    case tooManyRequests = "TooManyRequests"
    case internalServerError = "InternalServerError"
    case serviceUnavailable = "ServiceUnavailable"
    case shutdown = "Shutdown"

    /// The status code Apple's table lists with this reason.
    public var documentedStatus: Int {
        switch self {
        case .badCollapseID, .badDeviceToken, .badExpirationDate, .badMessageID, .badPriority, .badTopic,
            .deviceTokenNotForTopic, .duplicateHeaders, .idleTimeout, .invalidPushType, .missingDeviceToken,
            .missingTopic, .payloadEmpty, .topicDisallowed:
            400
        case .badCertificate, .badCertificateEnvironment, .expiredProviderToken, .forbidden, .invalidProviderToken,
            .missingProviderToken, .unrelatedKeyIDInToken, .badEnvironmentKeyIDInToken:
            403
        case .badPath: 404
        case .methodNotAllowed: 405
        case .expiredToken, .unregistered: 410
        case .payloadTooLarge: 413
        case .tooManyProviderTokenUpdates, .tooManyRequests: 429
        case .internalServerError: 500
        case .serviceUnavailable, .shutdown: 503
        }
    }

    /// Apple: "Don't retry notification responses with the error code BadDeviceToken, DeviceTokenNotForTopic,
    /// Forbidden, ExpiredToken, Unregistered, or PayloadTooLarge."
    public var isNeverRetried: Bool {
        switch self {
        case .badDeviceToken, .deviceTokenNotForTopic, .forbidden, .expiredToken, .unregistered, .payloadTooLarge:
            true
        default:
            false
        }
    }
}
