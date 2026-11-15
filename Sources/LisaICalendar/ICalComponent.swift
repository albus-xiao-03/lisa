// The iCalendar component tree (VCALENDAR, VEVENT, VTIMEZONE …) built from unfolded content lines.

import Foundation

/// A component with its properties and nested components.
public struct ICalComponent: Hashable, Sendable {
    public let name: String
    public var properties: [ContentLine]
    public var components: [ICalComponent]

    public init(name: String, properties: [ContentLine] = [], components: [ICalComponent] = []) {
        self.name = name
        self.properties = properties
        self.components = components
    }

    /// The first property named `name`.
    public func property(_ name: String) -> ContentLine? {
        properties.first { $0.name == name }
    }

    /// Every property named `name`.
    public func properties(named name: String) -> [ContentLine] {
        properties.filter { $0.name == name }
    }

    /// Nested components named `name`.
    public func components(named name: String) -> [ICalComponent] {
        components.filter { $0.name == name }
    }
}

/// Parses calendar text into components.
public enum ICalParser {
    /// Parses `data` as UTF-8 iCalendar text and returns the first VCALENDAR.
    public static func parseCalendar(_ data: Data, limits: ICalendarLimits = ICalendarLimits()) throws -> ICalComponent
    {
        guard data.count <= limits.maxInputBytes else { throw ICalendarError.inputTooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw ICalendarError.notUTF8 }
        return try parseCalendar(text, limits: limits)
    }

    /// Parses calendar text and returns the first VCALENDAR.
    public static func parseCalendar(_ text: String, limits: ICalendarLimits = ICalendarLimits()) throws
        -> ICalComponent
    {
        guard text.utf8.count <= limits.maxInputBytes else { throw ICalendarError.inputTooLarge }
        var stack: [ICalComponent] = []
        var roots: [ICalComponent] = []
        for raw in try LineUnfolder.unfold(text, limits: limits) {
            guard let line = ContentLine.parse(raw) else { continue }
            if line.name == "BEGIN" {
                guard stack.count < limits.maxNestingDepth else { throw ICalendarError.nestingTooDeep }
                stack.append(ICalComponent(name: line.value.uppercased()))
            } else if line.name == "END" {
                guard let finished = stack.popLast() else { continue }
                guard finished.name == line.value.uppercased() else {
                    throw ICalendarError.unbalancedComponents(finished.name)
                }
                if stack.isEmpty {
                    roots.append(finished)
                } else {
                    stack[stack.count - 1].components.append(finished)
                }
            } else if !stack.isEmpty {
                stack[stack.count - 1].properties.append(line)
            }
        }
        if let open = stack.last { throw ICalendarError.unbalancedComponents(open.name) }
        guard let calendar = roots.first(where: { $0.name == "VCALENDAR" }) else { throw ICalendarError.notACalendar }
        return calendar
    }
}
