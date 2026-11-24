// Case IDs (plan §10.8): `OV-<AREA>-<PROVIDER>-<NN>`, for example `OV-MAIL-GMAIL-07`, `OV-NEAR-MI-03`,
// `OV-APPLE-X1-FETCH-02` or `OV-HOST-04`; a paired session's device result carries `<case>@<role>`.

/// A case's identifier: `OV`, an area, any further uppercase segments, and a two-digit number.
public struct VerifyCaseID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let text: String

    public var description: String { text }

    public init(_ text: String) throws(VerifyError) {
        guard Self.isValid(text) else { throw .invalidCaseID(text) }
        self.text = text
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard Self.isValid(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "case ID"))
        }
        self.text = text
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }

    public static func < (lhs: VerifyCaseID, rhs: VerifyCaseID) -> Bool { lhs.text < rhs.text }

    /// The area segment, for example `NEAR`, `APPLE`, `MAIL` or `HARNESS`.
    public var area: String { String(text.split(separator: "-")[1]) }

    /// The device result's correlated ID in a paired session (plan §10.8).
    public func correlated(_ role: VerifyPairRole) -> String { text + "@" + role.rawValue }

    /// Splits `<case>@<role>`; a plain case ID has no role.
    public static func parseCorrelated(_ text: String) throws(VerifyError) -> (VerifyCaseID, VerifyPairRole?) {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { throw .invalidCaseID(text) }
        let id = try VerifyCaseID(String(parts[0]))
        guard parts.count == 2 else { return (id, nil) }
        guard let role = VerifyPairRole(rawValue: String(parts[1])) else { throw .invalidCaseID(text) }
        return (id, role)
    }

    public static func isValid(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.first == "OV", let last = parts.last, last.count == 2,
            last.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return false }
        return parts.dropFirst().dropLast().allSatisfy { segment in
            !segment.isEmpty && segment.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
        }
    }
}
