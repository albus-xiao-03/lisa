// `lisa preference`: inspect, set, confirm and delete preferences (MEM-01).

import ArgumentParser
import Foundation
import LisaAPIContract

struct PreferenceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preference", abstract: "Inspect, set, confirm and delete preferences.",
        subcommands: [List.self, Set.self, Confirm.self, Delete.self], defaultSubcommand: List.self)

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List preferences.")

        @OptionGroup var host: HostOptions

        func run() async throws {
            let preferences = try await HostSession.withOwner(host) { _, client in try await client.preferences() }
            try host.output.emit(preferences) { preferences in
                preferences.isEmpty
                    ? "no preferences (configuration defaults apply)"
                    : preferences.map {
                        "\($0.key) = \(PreferenceCommand.describe($0.value)) [\($0.origin)\($0.effective ? "" : ", awaiting confirmation")]"
                    }.joined(separator: "\n")
            }
        }
    }

    struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set", abstract: "Set a preference.")

        @OptionGroup var host: HostOptions

        @Option(help: "How to read the value: text, number, flag or list (comma-separated).")
        var type: String = "text"

        @Argument(help: "The preference key, for example brief.time.")
        var key: String

        @Argument(help: "The value.")
        var value: String

        func run() async throws {
            let parsed: PreferenceValueDTO
            switch type {
            case "text": parsed = .text(value)
            case "number":
                guard let number = Double(value) else { throw ValidationError("the value is not a number") }
                parsed = .number(number)
            case "flag":
                guard let flag = Bool(value) else { throw ValidationError("the value must be true or false") }
                parsed = .flag(flag)
            case "list": parsed = .list(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            default: throw ValidationError("--type must be text, number, flag or list")
            }
            _ = try await HostSession.withOwner(host) { _, client in
                try await client.updatePreferences(
                    PreferencesPatchRequest(changes: [PreferenceChange(key: key, value: parsed)]))
            }
            print("set \(key)")
        }
    }

    struct Confirm: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "confirm", abstract: "Confirm an inferred preference.")

        @OptionGroup var host: HostOptions

        @Argument var key: String

        func run() async throws {
            _ = try await HostSession.withOwner(host) { _, client in
                try await client.updatePreferences(
                    PreferencesPatchRequest(changes: [PreferenceChange(key: key, confirm: true)]))
            }
            print("confirmed \(key)")
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete", abstract: "Delete a preference; the configuration's value applies again.")

        @OptionGroup var host: HostOptions

        @Argument var key: String

        func run() async throws {
            _ = try await HostSession.withOwner(host) { _, client in
                try await client.updatePreferences(PreferencesPatchRequest(changes: [PreferenceChange(key: key)]))
            }
            print("deleted \(key)")
        }
    }

    static func describe(_ value: PreferenceValueDTO) -> String {
        switch value {
        case .text(let text): text
        case .number(let number): String(number)
        case .flag(let flag): String(flag)
        case .list(let list): list.joined(separator: ", ")
        }
    }
}
