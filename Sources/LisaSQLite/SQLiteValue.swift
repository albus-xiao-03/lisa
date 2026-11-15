// Values bound to and read from SQLite statements.

import Foundation

/// A SQLite storage value.
public enum SQLiteValue: Hashable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public var integer: Int64? {
        if case .integer(let value) = self { value } else { nil }
    }

    public var text: String? {
        if case .text(let value) = self { value } else { nil }
    }

    public var blob: Data? {
        if case .blob(let value) = self { value } else { nil }
    }
}
