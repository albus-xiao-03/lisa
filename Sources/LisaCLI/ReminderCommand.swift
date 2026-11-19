// `lisa reminder`: list reminders and acknowledge, snooze, dismiss or complete one (REM-01).

import ArgumentParser
import Foundation
import LisaAPIContract

struct ReminderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminder", abstract: "List reminders and act on them.",
        subcommands: [List.self, Act.self], defaultSubcommand: List.self)

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List active reminders.")

        @OptionGroup var host: HostOptions

        func run() async throws {
            let page = try await HostSession.withOwner(host) { _, client in try await client.reminders(limit: 200) }
            try host.output.emit(page.items) { reminders in
                reminders.isEmpty
                    ? "no active reminders"
                    : reminders.map {
                        "\($0.id)  \(APIDates.string(from: $0.dueAt))  \($0.title) [\($0.rule), \($0.state)]"
                    }
                    .joined(separator: "\n")
            }
        }
    }

    struct Act: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "act",
            abstract: "Acknowledge, snooze, dismiss or complete a reminder. Acknowledging never completes the task.")

        @OptionGroup var host: HostOptions

        @Argument(help: "acknowledge, snooze, dismiss or complete.")
        var action: ReminderActionKind

        @Argument(help: "The reminder ID.")
        var id: String

        func run() async throws {
            let reminder = try await HostSession.withOwner(host) { _, client in
                try await client.reminderAction(id: id, ReminderActionRequest(action: action))
            }
            try host.output.emit(reminder) { "reminder \($0.id) is now \($0.state)" }
        }
    }
}

extension ReminderActionKind: ExpressibleByArgument {}
