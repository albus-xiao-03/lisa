// Queries over indexed record fields; field names are checked against each entity's declared indexes.

import Foundation

/// A value stored in an indexed column.
public enum IndexValue: Hashable, Sendable {
    case text(String)
    case integer(Int64)
    case null

    /// An instant as milliseconds since 1970.
    public static func instant(_ date: Date?) -> IndexValue {
        guard let date else { return .null }
        return .integer(Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }
}

/// Comparison operators for conditions.
public enum ComparisonOperator: String, Sendable {
    case equals = "="
    case notEquals = "<>"
    case lessThan = "<"
    case lessOrEqual = "<="
    case greaterThan = ">"
    case greaterOrEqual = ">="
}

/// One condition on an indexed field.
public enum RecordCondition: Hashable, Sendable {
    case compare(field: String, ComparisonOperator, IndexValue)
    case isNull(field: String)
    case isNotNull(field: String)
    case oneOf(field: String, [IndexValue])

    public var field: String {
        switch self {
        case .compare(let field, _, _), .isNull(let field), .isNotNull(let field), .oneOf(let field, _): field
        }
    }
}

/// A query: conditions combined with AND, ordering and a limit.
public struct RecordQuery: Hashable, Sendable {
    public var conditions: [RecordCondition]
    public var ordering: [Ordering]
    public var limit: Int?

    public struct Ordering: Hashable, Sendable {
        public var field: String
        public var ascending: Bool
    }

    public init(conditions: [RecordCondition] = [], ordering: [Ordering] = [], limit: Int? = nil) {
        self.conditions = conditions
        self.ordering = ordering
        self.limit = limit
    }

    /// Every record.
    public static let all = RecordQuery()

    public func filter(_ field: String, _ comparison: ComparisonOperator, _ value: IndexValue) -> RecordQuery {
        var copy = self
        copy.conditions.append(.compare(field: field, comparison, value))
        return copy
    }

    public func filter(_ field: String, equals text: String) -> RecordQuery {
        filter(field, .equals, .text(text))
    }

    public func filter(_ field: String, in values: [IndexValue]) -> RecordQuery {
        var copy = self
        copy.conditions.append(.oneOf(field: field, values))
        return copy
    }

    public func filterNull(_ field: String) -> RecordQuery {
        var copy = self
        copy.conditions.append(.isNull(field: field))
        return copy
    }

    public func sorted(by field: String, ascending: Bool = true) -> RecordQuery {
        var copy = self
        copy.ordering.append(Ordering(field: field, ascending: ascending))
        return copy
    }

    public func limited(to count: Int) -> RecordQuery {
        var copy = self
        copy.limit = count
        return copy
    }
}
