// `lisa-verify preflight apple` (plan §10.8 "Commands"): on the owner's Mac, the Xcode version and SDKs, the number of
// valid signing identities (never their names or keys), the connected devices, and for each signed app named with
// `--app` its entitlements, embedded profile and derived identifiers, read from the signed product itself — with the
// reasons a case would stop. Provider stages join with their cases (M7).

import ArgumentParser
import Foundation
import LisaVerifyKit

struct PreflightCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preflight", abstract: "Check the Apple tools and signed products before a session.")

    @Argument(help: "apple, or all") var target: String = "apple"
    @Option(name: .customLong("app"), help: "A built, signed .app to read (repeatable).") var apps: [String] = []
    @Option(help: "The Core's APNs environment a push case needs (development or production).") var pushEnvironment:
        String?
    @Option(help: "The Core's APNs topic.") var topic: String?
    @Option(help: "The UDID of the iPhone or iPad the case runs on.") var device: String?

    func run() throws {
        guard ["apple", "all"].contains(target.lowercased()) else {
            throw VerifyError.invalidInput(
                "no provider cases in this build yet; `preflight apple` checks the Apple side")
        }
        #if os(macOS)
            print("Xcode: \(Self.tool(["xcodebuild", "-version"]).split(separator: "\n").first ?? "not found")")
            for sdk in ["macosx", "iphoneos"] {
                print(
                    "SDK \(sdk): \(Self.tool(["xcrun", "--sdk", sdk, "--show-sdk-version"]).trimmingCharacters(in: .whitespacesAndNewlines))"
                )
            }
            let identities = Self.tool(["security", "find-identity", "-v", "-p", "codesigning"])
            let count = identities.split(separator: "\n").filter { $0.contains(")") && $0.contains("\"") }.count
            print("Valid code-signing identities: \(count) (names and keys are not shown)")
            print("Connected devices:\n\(Self.tool(["xcrun", "devicectl", "list", "devices"]))")
            for app in apps { try report(app) }
        #else
            print(
                "Apple preflight: NOT_RUN_ENVIRONMENT (this host isn't a Mac with Xcode; the owner runs it on the Mac "
                    + "that signs the builds)")
        #endif
    }

    #if os(macOS)
        func report(_ path: String) throws {
            let app = URL(fileURLWithPath: path)
            let macInfo = app.appendingPathComponent("Contents/Info.plist")
            let platform: ApplePlatform = FileManager.default.fileExists(atPath: macInfo.path) ? .macOS : .iOS
            let info = platform == .macOS ? macInfo : app.appendingPathComponent("Info.plist")
            let profileFile =
                platform == .macOS
                ? app.appendingPathComponent("Contents/embedded.provisionprofile")
                : app.appendingPathComponent("embedded.mobileprovision")
            guard let infoData = FileManager.default.contents(atPath: info.path) else {
                throw VerifyError.invalidInput("no Info.plist in \(path)")
            }
            let entitlements = Data(Self.tool(["codesign", "-d", "--entitlements", "-", "--xml", path]).utf8)
            let profile =
                FileManager.default.fileExists(atPath: profileFile.path)
                ? Data(Self.tool(["security", "cms", "-D", "-i", profileFile.path]).utf8) : nil
            let product = try AppleSignedProduct.parse(
                platform: platform, infoPlist: infoData, entitlementsPlist: entitlements, profilePlist: profile)
            print("\(app.lastPathComponent) (\(platform.rawValue)): bundle \(product.bundleIdentifier)")
            print(
                "  APNs \(platform.apsEntitlementKey): \(product.apsEnvironment ?? "absent"); topic \(product.apnsTopic)"
            )
            print("  keychain access groups: \(product.keychainAccessGroups.count); app sandbox: \(product.appSandbox)")
            if let profile = product.profile {
                print(
                    "  profile: \(profile.kind), team \(profile.teamIdentifier ?? "?"), expires "
                        + "\(profile.expiration.map(VerifyClock.wallClock) ?? "?"), devices "
                        + "\(profile.provisionedDevices?.count ?? 0)")
            }
            print(
                "  Keychain services: \(product.keychainServices.clientIdentity), \(product.keychainServices.secretPrefix)<service>"
            )
            if platform == .macOS {
                print("  R1 client directory: \(product.r1ClientDirectory(home: NSHomeDirectory()))")
            }
            let push = pushEnvironment.map { ApplePushRequirement(environment: $0, topic: topic ?? product.apnsTopic) }
            let reasons = ApplePreflight.refusals(product, push: push, deviceUDID: device)
            print(reasons.isEmpty ? "  ready" : "  stops: " + reasons.joined(separator: "; "))
        }

        static func tool(_ arguments: [String]) -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return ""
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }
    #endif
}
