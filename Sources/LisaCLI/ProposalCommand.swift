// `lisa proposal`: review event proposals: list, dismiss, report as added, confirm a match, or export as .ics.

import ArgumentParser
import Foundation
import LisaAPIContract

struct ProposalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "proposal", abstract: "Review event proposals.",
        subcommands: [List.self, Act.self, CalendarFile.self], defaultSubcommand: List.self)

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List event proposals.")

        @OptionGroup var host: HostOptions

        func run() async throws {
            let page = try await HostSession.withOwner(host) { _, client in try await client.proposals(limit: 200) }
            try host.output.emit(page.items) { proposals in
                proposals.isEmpty
                    ? "no event proposals"
                    : proposals.map { proposal in
                        let when =
                            proposal.timing.start.map(APIDates.string(from:)) ?? proposal.timing.date ?? "date unknown"
                        return "\(proposal.id)  \(proposal.title) at \(when) [\(proposal.match.state)]"
                    }.joined(separator: "\n")
            }
        }
    }

    struct Act: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "act", abstract: "dismiss, reportAdded, or confirmMatch with --occurrence.")

        @OptionGroup var host: HostOptions

        @Argument(help: "dismiss, reportAdded or confirmMatch.")
        var action: ProposalActionKind

        @Argument(help: "The proposal ID.")
        var id: String

        @Option(help: "The calendar occurrence that matches (for confirmMatch).")
        var occurrence: String?

        func validate() throws {
            if action == .correct { throw ValidationError("corrections are made in the app") }
            if action == .confirmMatch && occurrence == nil { throw ValidationError("confirmMatch needs --occurrence") }
        }

        func run() async throws {
            let proposal = try await HostSession.withOwner(host) { _, client in
                guard let current = try await client.proposals(limit: 200).items.first(where: { $0.id == id }) else {
                    throw ValidationError("no proposal \(id)")
                }
                return try await client.proposalAction(
                    id: id,
                    ProposalActionRequest(action: action, expectedRevision: current.revision, occurrenceID: occurrence))
            }
            try host.output.emit(proposal) { "proposal \($0.id) is now \($0.match.state)" }
        }
    }

    struct CalendarFile: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ics", abstract: "Print a proposal as an .ics file; adding it to a calendar stays your action."
        )

        @OptionGroup var host: HostOptions

        @Argument(help: "The proposal ID.")
        var id: String

        func run() async throws {
            print(try await HostSession.withOwner(host) { _, client in try await client.proposalCalendarFile(id: id) })
        }
    }
}

extension ProposalActionKind: ExpressibleByArgument {}
