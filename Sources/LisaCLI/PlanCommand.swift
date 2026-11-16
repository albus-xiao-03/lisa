// `lisa plan`: shows the day's rundown, and applies owner actions to its blocks.

import ArgumentParser
import Foundation
import LisaAPIContract

struct PlanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan", abstract: "Generate or inspect a daily rundown, and act on its blocks.",
        subcommands: [Show.self, Block.self], defaultSubcommand: Show.self)

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Show the rundown for a date.")

        @OptionGroup var host: HostOptions

        @Option(help: "The local date, YYYY-MM-DD (default: today).")
        var date: String?

        func run() async throws {
            let plan = try await HostSession.withOwner(host) { _, client in try await client.rundown(date: date) }
            try host.output.emit(plan) { plan in
                var lines = ["Rundown for \(plan.date) (\(plan.zone)), revision \(plan.revision)"]
                lines += plan.blocks.map {
                    "\(APIDates.string(from: $0.start)) – \(APIDates.string(from: $0.end))  \($0.title) [\($0.kind), \($0.state)] block \($0.blockID)"
                }
                lines += plan.unscheduled.map { "not scheduled: \($0.title): \($0.reason)" }
                lines += plan.warnings.map { "warning: \($0)" }
                if plan.availabilityUncertain {
                    lines.append("availability is uncertain: a calendar is stale or failing")
                }
                return lines.joined(separator: "\n")
            }
        }
    }

    struct Block: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "block", abstract: "Accept, lock, reject, complete or defer a plan block.")

        @OptionGroup var host: HostOptions

        @Argument(help: "accept, lock, reject, complete or defer.")
        var action: PlanBlockActionKind

        @Option(help: "The block's ID, as `lisa plan show` prints it.")
        var block: String

        @Option(help: "The local date of the rundown (default: today).")
        var date: String?

        func run() async throws {
            let plan = try await HostSession.withOwner(host) { _, client in
                let current = try await client.rundown(date: date)
                return try await client.planBlockAction(
                    planID: current.planID, blockID: block,
                    PlanBlockActionRequest(action: action, expectedRevision: current.revision))
            }
            try host.output.emit(plan) { plan in
                "\(action.rawValue): block \(block); rundown revision \(plan.revision)"
            }
        }
    }
}

extension PlanBlockActionKind: ExpressibleByArgument {}
