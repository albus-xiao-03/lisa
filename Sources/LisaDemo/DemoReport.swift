// The demonstration's report: numbered steps with what happened and the checks each step must pass (DEMO-01).

import Foundation

/// One verified fact in the demonstration.
public struct DemoCheck: Codable, Hashable, Sendable {
    public var description: String
    public var passed: Bool

    public init(_ description: String, _ passed: Bool) {
        self.description = description
        self.passed = passed
    }
}

/// One step of the scenario.
public struct DemoStep: Codable, Hashable, Sendable {
    public var number: Int
    public var title: String
    public var details: [String]
    public var checks: [DemoCheck]

    public var passed: Bool { checks.allSatisfy(\.passed) }
}

/// The whole scenario's outcome. Everything it shows is synthetic demonstration content.
public struct DemoReport: Codable, Hashable, Sendable {
    public var label: String
    public var dataDirectory: String
    public var steps: [DemoStep]

    public var passed: Bool { steps.allSatisfy(\.passed) }

    /// A readable rendering for the terminal.
    public var text: String {
        var lines = ["\(label)", "Data directory: \(dataDirectory)", ""]
        for step in steps {
            lines.append("\(step.number). \(step.title) — \(step.passed ? "passed" : "FAILED")")
            lines += step.details.map { "   \($0)" }
            lines += step.checks.map { "   [\($0.passed ? "ok" : "FAILED")] \($0.description)" }
            lines.append("")
        }
        lines.append(passed ? "All demonstration checks passed." : "Some demonstration checks FAILED.")
        return lines.joined(separator: "\n")
    }
}
