// The model-provider boundary (MODEL-01): requests, responses, descriptors and errors, independent of any vendor.

import Foundation

/// Where a provider runs; drives the data-sharing check.
public enum ModelLocation: String, Codable, Sendable {
    /// In this process, sending nothing anywhere (the deterministic provider).
    case inProcess
    /// An explicitly configured endpoint on the local machine or private network.
    case localNetwork
    /// A remote endpoint.
    case remote
}

/// Identifies a provider in records and reports. Deterministic output is never presented as live inference.
public struct ModelDescriptor: Hashable, Codable, Sendable {
    public var name: String
    public var location: ModelLocation
    public var isDeterministic: Bool

    public init(name: String, location: ModelLocation, isDeterministic: Bool) {
        self.name = name
        self.location = location
        self.isDeterministic = isDeterministic
    }
}

/// One chat message.
public struct ModelMessage: Hashable, Sendable {
    public enum Role: String, Sendable {
        case system
        case user
        case assistant
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// A completion request.
public struct ModelRequest: Hashable, Sendable {
    public var messages: [ModelMessage]
    public var maxOutputTokens: Int
    public var temperature: Double
    public var wantsJSON: Bool

    public init(messages: [ModelMessage], maxOutputTokens: Int, temperature: Double = 0, wantsJSON: Bool = true) {
        self.messages = messages
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.wantsJSON = wantsJSON
    }
}

/// A completion response.
public struct ModelResponse: Hashable, Sendable {
    public var text: String
    public var finishReason: String?
    public var inputTokens: Int?
    public var outputTokens: Int?

    public init(text: String, finishReason: String? = nil, inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.text = text
        self.finishReason = finishReason
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// Why a completion failed.
public enum ModelError: Error, Hashable, Sendable, CustomStringConvertible {
    case unavailable(String)
    case authentication
    case rateLimited(retryAfter: Date?)
    case timeout
    case invalidResponse(String)
    case refusedByPolicy(String)
    case requestTooLarge

    public var description: String {
        switch self {
        case .unavailable(let reason): "the model is unavailable: \(reason)"
        case .authentication: "the model endpoint rejected the credentials"
        case .rateLimited: "the model endpoint is rate limiting requests"
        case .timeout: "the model request timed out"
        case .invalidResponse(let reason): "the model response could not be used: \(reason)"
        case .refusedByPolicy(let reason): "the request was not sent: \(reason)"
        case .requestTooLarge: "the request exceeds the configured size limit"
        }
    }
}

/// A model provider. Providers propose; deterministic services decide (MODEL-03).
public protocol ModelProvider: Sendable {
    var descriptor: ModelDescriptor { get }
    func complete(_ request: ModelRequest) async throws -> ModelResponse
}
