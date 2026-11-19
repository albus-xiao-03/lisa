// `lisa plan`: shows the day's rundown, and applies owner actions to its blocks, moving them included.

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
            commandName: "block", abstract: "Accept, lock, reject, complete, defer or move a plan block.",
            discussion: """
                move gives the block a new --start and --end, HH:MM in the owner's time zone on the rundown's day \
                (--end 24:00 is midnight at its end). The block is then locked there, so Lisa keeps it at that time \
                when she plans again, and plans the rest of the day around it. The host refuses a move that would \
                overlap a busy calendar event or another accepted, locked or completed block (exit 1).
                """)

        @OptionGroup var host: HostOptions

        @Argument(help: "accept, lock, reject, complete, defer or move.")
        var action: PlanBlockActionKind

        @Option(help: "The block's ID, as `lisa plan show` prints it.")
        var block: String

        @Option(help: "The local date of the rundown (default: today).")
        var date: String?

        @Option(help: "For move: the block's new start, HH:MM in the owner's time zone.")
        var start: String?

        @Option(help: "For move: the block's new end, HH:MM in the owner's time zone (24:00 for midnight).")
        var end: String?

        func validate() throws {
            guard action == .move else {
                if start != nil || end != nil { throw ValidationError("--start and --end are only for move") }
                return
            }
            guard let start, let end else { throw ValidationError("move needs --start and --end, HH:MM") }
            _ = try LocalBlockTimes(start: start, end: end)
        }

        func run() async throws {
            let plan = try await HostSession.withOwner(host) { _, client in
                let current = try await client.rundown(date: date)
                var request = PlanBlockActionRequest(action: action, expectedRevision: current.revision)
                if action == .move, let start, let end {
                    let times = try Self.instants(start: start, end: end, on: current)
                    request.start = times.start
                    request.end = times.end
                }
                return try await client.planBlockAction(planID: current.planID, blockID: block, request)
            }
            try host.output.emit(plan) { plan in
                guard action == .move, let moved = plan.blocks.first(where: { $0.blockID == block }) else {
                    return "\(action.rawValue): block \(block); rundown revision \(plan.revision)"
                }
                return "move: block \(block) is now \(Self.localTimes(of: moved, in: plan.zone)) (\(plan.zone)), "
                    + "\(moved.state); rundown revision \(plan.revision)"
            }
        }

        /// `--start` and `--end` as instants on the date of `rundown` in its time zone. A time that does not exist there,
        /// because the clocks skip it, is a usage error (exit 64) reported before anything is sent.
        static func instants(start: String, end: String, on rundown: RundownDTO) throws -> (start: Date, end: Date) {
            do {
                return try LocalBlockTimes(start: start, end: end).instants(on: rundown.date, in: rundown.zone)
            } catch let error as ValidationError {
                Output.error(error.message)
                throw ExitCode.validationFailure
            }
        }

        /// A block's start and end as `HH:MM–HH:MM` in the time zone `zone`.
        static func localTimes(of block: PlanBlockDTO, in zone: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: zone)
            formatter.dateFormat = "HH:mm"
            return "\(formatter.string(from: block.start))–\(formatter.string(from: block.end))"
        }
    }
}

extension PlanBlockActionKind: ExpressibleByArgument {}
