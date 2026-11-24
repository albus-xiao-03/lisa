// The four transfer budgets, each checked separately at its own layer (plan §8.16.2).

/// Lisa's transfer budgets. Every limit counts encoded bytes, so multi-byte UTF-8 and escaped control characters
/// count at their encoded size.
public enum TransferBudgets {
    /// One canonical operation body, metadata included: 64 KiB.
    public static let operationBodyBytes = 65_536
    /// Operations in one batch.
    public static let batchOperations = 100
    /// Canonical bodies plus their raw signatures in one batch: 512 KiB.
    public static let batchBytes = 524_288
    /// One encoded HTTP request body (a JSON envelope carrying base64url bodies): 768 KiB, at least
    /// 512 KiB × 4/3 plus 64 KiB of envelope.
    public static let httpRequestBytes = 786_432
    /// One nearby frame, its 8-byte header included: 1 MiB.
    public static let frameBytes = 1_048_576
    /// The length of a nearby frame header.
    public static let frameHeaderBytes = 8
    /// The length of a raw P-256 ECDSA signature (`r ‖ s`).
    public static let signatureBytes = 64
    /// The most dependencies one operation may declare (plan §8.2.2).
    public static let maximumDependencies = 32

    /// Checks one operation body's encoded size.
    public static func checkOperationBody(bytes: Int) throws(TransferBudgetError) {
        guard bytes <= operationBodyBytes else { throw .operationBodyTooLarge(bytes: bytes, limit: operationBodyBytes) }
    }

    /// Checks a batch: at most 100 operations, and at most 512 KiB of bodies plus one 64-byte signature each.
    public static func checkBatch(bodyByteCounts: [Int]) throws(TransferBudgetError) {
        guard bodyByteCounts.count <= batchOperations else {
            throw .tooManyOperations(count: bodyByteCounts.count, limit: batchOperations)
        }
        var total = 0
        for bytes in bodyByteCounts {
            try checkOperationBody(bytes: bytes)
            total += bytes + signatureBytes
        }
        guard total <= batchBytes else { throw .batchTooLarge(bytes: total, limit: batchBytes) }
    }

    /// Checks an HTTP request body against the transport limit, on the bytes actually received or declared.
    public static func checkHTTPRequestBody(bytes: Int) throws(TransferBudgetError) {
        guard bytes <= httpRequestBytes else { throw .httpBodyTooLarge(bytes: bytes, limit: httpRequestBytes) }
    }

    /// Checks a nearby frame's total length, header included, before anything is allocated for it.
    public static func checkFrame(totalBytes: Int) throws(TransferBudgetError) {
        guard totalBytes >= frameHeaderBytes else { throw .frameTruncated(bytes: totalBytes) }
        guard totalBytes <= frameBytes else { throw .frameTooLarge(bytes: totalBytes, limit: frameBytes) }
    }
}

/// A transfer budget that was exceeded.
public enum TransferBudgetError: Error, Hashable, Sendable {
    case operationBodyTooLarge(bytes: Int, limit: Int)
    case tooManyOperations(count: Int, limit: Int)
    case batchTooLarge(bytes: Int, limit: Int)
    case httpBodyTooLarge(bytes: Int, limit: Int)
    case frameTooLarge(bytes: Int, limit: Int)
    case frameTruncated(bytes: Int)
}
