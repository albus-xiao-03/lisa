// Keys of the response cache: a brief or rundown per local date, and the first page of the task list per status.

import Foundation
import LisaAPIContract

/// What a cached response is: the brief or rundown of a local date, or the first page of the task list.
public struct CacheKey: Hashable, Sendable, CustomStringConvertible {
    /// The kinds of cached responses.
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case brief
        case rundown
        case tasks
    }

    /// What the cached response is.
    public let kind: Kind
    /// The local date (`YYYY-MM-DD`) of a brief or rundown, or the status filter of a task list.
    public let qualifier: String?

    private init(kind: Kind, qualifier: String?) {
        self.kind = kind
        self.qualifier = qualifier
    }

    /// The brief of a local date, or `nil` when `date` is not a `YYYY-MM-DD` calendar date.
    public static func brief(date: String) -> CacheKey? {
        APIDates.isLocalDate(date) ? CacheKey(kind: .brief, qualifier: date) : nil
    }

    /// The rundown of a local date, or `nil` when `date` is not a `YYYY-MM-DD` calendar date.
    public static func rundown(date: String) -> CacheKey? {
        APIDates.isLocalDate(date) ? CacheKey(kind: .rundown, qualifier: date) : nil
    }

    /// The first page of the task list, optionally filtered by status.
    public static func tasks(status: TaskStatusValue?) -> CacheKey {
        CacheKey(kind: .tasks, qualifier: status?.rawValue)
    }

    /// A name that is safe in file names: `brief.2026-11-16`, `rundown.2026-11-16`, `tasks` or `tasks.open`.
    public var name: String {
        qualifier.map { "\(kind.rawValue).\($0)" } ?? kind.rawValue
    }

    /// Parses a name that `name` produced; `nil` for any other text.
    public init?(name: String) {
        let parts = name.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let kind = Kind(rawValue: parts[0]) else { return nil }
        let qualifier = parts.count == 2 ? parts[1] : nil
        switch kind {
        case .brief, .rundown:
            guard let qualifier, APIDates.isLocalDate(qualifier) else { return nil }
        case .tasks:
            if let qualifier, TaskStatusValue(rawValue: qualifier) == nil { return nil }
        }
        self.init(kind: kind, qualifier: qualifier)
    }

    public var description: String { name }
}
