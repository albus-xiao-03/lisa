// A change page as it travels (plan §8.4.2): its exact canonical body and Core's raw 64-byte signature over
// `"lisa-r2-change-page-v1\n"` ‖ body. Relays forward exact bytes.

/// A signed change page.
public struct SignedChangePage: Hashable, Sendable {
    public let body: [UInt8]
    public let signature: [UInt8]

    public init(body: [UInt8], signature: [UInt8]) throws(OperationEnvelopeError) {
        guard body.count <= ChangePage.maximumBytes else {
            throw .encoding(.tooLarge(bytes: body.count, limit: ChangePage.maximumBytes))
        }
        guard signature.count == 64 else { throw .invalidField("page.signature") }
        self.body = body
        self.signature = signature
    }

    /// The page, decoded strictly; says nothing about who signed it.
    public func page() throws(OperationEnvelopeError) -> ChangePage {
        try ChangePage.decode(body: body)
    }
}
