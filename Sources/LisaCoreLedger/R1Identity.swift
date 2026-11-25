// Identifiers between R2 operations and R1's records (docs/DECISIONS.md D-58): an R2 entity ID is 128 bits; R1 names
// a record by a lowercase UUID string, which is the same 128 bits spelled 8-4-4-4-12. The mapping is exact in both
// directions for every ID R1 itself generated.

import LisaSyncProtocol

/// The R1 spelling of R2 entity IDs.
public enum R1Identity {
    /// The lowercase UUID spelling of `id`, which is how R1 names the record.
    public static func uuidString(_ id: Identifier128) -> String {
        let hex = id.hex
        let parts = [(0, 8), (8, 12), (12, 16), (16, 20), (20, 32)].map { start, end in
            String(hex[hex.index(hex.startIndex, offsetBy: start)..<hex.index(hex.startIndex, offsetBy: end)])
        }
        return parts.joined(separator: "-")
    }

    /// The entity ID an R1 record ID names, when it is a lowercase UUID; `nil` otherwise.
    public static func entityID(fromUUID text: String) -> Identifier128? {
        let groups = text.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12] else { return nil }
        return try? Identifier128(hex: groups.joined())
    }
}
