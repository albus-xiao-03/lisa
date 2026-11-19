// `lisa task`: list, add, and complete, cancel, reopen or start tasks (owner actions).

import ArgumentParser
import Foundation
import LisaAPIContract

struct TaskCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "task", abstract: "List and act on tasks.",
        subcommands: [List.self, Add.self, SetStatus.self], defaultSubcommand: List.self)

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List tasks.")

        @OptionGroup var host: HostOptions

        @Option(help: "Only tasks in this state: open, inProgress, blocked, completed or cancelled.")
        var status: TaskStatusValue?

        func run() async throws {
            let tasks = try await HostSession.withOwner(host) { _, client in
                var all: [TaskDTO] = []
                var cursor: String?
                repeat {
                    let page = try await client.tasks(status: status, limit: 200, cursor: cursor)
                    all += page.items
                    cursor = page.nextCursor
                } while cursor != nil
                return all
            }
            try host.output.emit(tasks) { tasks in
                tasks.isEmpty
                    ? "no tasks"
                    : tasks.map { task in
                        let due = task.deadline.map { $0.date ?? $0.instant.map(APIDates.string(from:)) ?? "" }
                        return "\(task.id)  \(task.title) [\(task.status.rawValue), \(task.confirmation.rawValue)]"
                            + (due.map { " due \($0)" } ?? "")
                    }.joined(separator: "\n")
            }
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "Add a confirmed task.")

        @OptionGroup var host: HostOptions

        @Option(help: "A timed deadline (ISO 8601, for example 2026-11-18T17:00:00Z).")
        var due: String?

        @Option(help: "A date-only deadline, YYYY-MM-DD.")
        var dueDate: String?

        @Option(help: "low, normal, high or urgent.")
        var priority: TaskPriorityValue?

        @Option(help: "Estimated minutes.")
        var minutes: Int?

        @Argument(help: "The task's title.")
        var title: [String]

        func validate() throws {
            if due != nil && dueDate != nil { throw ValidationError("use either --due or --due-date") }
            if let due, APIDates.date(from: due) == nil { throw ValidationError("--due must be an ISO 8601 instant") }
            if let dueDate, !APIDates.isLocalDate(dueDate) {
                throw ValidationError("--due-date must look like 2026-11-18")
            }
        }

        func run() async throws {
            let deadline: DeadlineDTO? =
                if let due { DeadlineDTO(instant: APIDates.date(from: due)) } else {
                    dueDate.map { DeadlineDTO(date: $0) }
                }
            let task = try await HostSession.withOwner(host) { _, client in
                try await client.createTask(
                    TaskCreateRequest(
                        title: title.joined(separator: " "), priority: priority, deadline: deadline,
                        estimatedMinutes: minutes))
            }
            try host.output.emit(task) { "added task \($0.id): \($0.title)" }
        }
    }

    struct SetStatus: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-status", abstract: "Complete, cancel, reopen, start or block a task.")

        @OptionGroup var host: HostOptions

        @Argument(help: "completed, cancelled, open, inProgress or blocked.")
        var status: TaskStatusValue

        @Argument(help: "The task ID.")
        var id: String

        func run() async throws {
            let task = try await HostSession.withOwner(host) { _, client in
                let current = try await client.task(id: id)
                return try await client.updateTask(
                    id: id, TaskPatchRequest(expectedRevision: current.revision, status: status))
            }
            try host.output.emit(task) { "task \($0.id) is now \($0.status.rawValue)" }
        }
    }
}

extension TaskStatusValue: ExpressibleByArgument {}
extension TaskPriorityValue: ExpressibleByArgument {}
