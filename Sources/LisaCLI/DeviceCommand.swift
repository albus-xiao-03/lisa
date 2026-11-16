// `lisa device`: pairing codes, the paired devices and their removal (NOTIFY-02).

import ArgumentParser
import Foundation
import LisaAPIContract

struct DeviceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "device", abstract: "Pair, list and remove companion devices.",
        subcommands: [PairCode.self, List.self, Revoke.self], defaultSubcommand: List.self)

    struct PairCode: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "pair-code",
            abstract: "Create a one-time pairing code (valid for 10 minutes, while this host keeps running).")

        @OptionGroup var host: HostOptions

        func run() async throws {
            let code = try await HostSession.withOwner(host) { _, client in try await client.createPairingCode() }
            try host.output.emit(code) { code in
                "pairing code: \(code.code) (expires \(APIDates.string(from: code.expiresAt)); "
                    + "enter it in the app while the host is running)"
            }
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List paired devices.")

        @OptionGroup var host: HostOptions

        func run() async throws {
            let devices = try await HostSession.withOwner(host) { _, client in try await client.devices() }
            try host.output.emit(devices) { devices in
                devices.isEmpty
                    ? "no paired devices"
                    : devices.map {
                        "\($0.id)  \($0.name) (\($0.deviceClass.rawValue), \($0.state)) notifications: "
                            + ($0.canReceiveNotifications ? "on" : "off (\($0.authorization.rawValue))")
                    }.joined(separator: "\n")
            }
        }
    }

    struct Revoke: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "revoke",
            abstract: "Remove a device: its credential stops working and pending deliveries are cancelled.")

        @OptionGroup var host: HostOptions

        @Argument(help: "The device ID, as `lisa device list` prints it.")
        var id: String

        func run() async throws {
            try await HostSession.withOwner(host) { _, client in try await client.removeDevice(id: id) }
            print("removed device \(id)")
        }
    }
}
