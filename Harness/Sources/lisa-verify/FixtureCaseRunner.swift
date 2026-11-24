// The fixture cases of S-24 (plan §10.8 acceptance), executed by Claude with no account and no provider: the action
// ledger's four interruption variants over an email, a push, a model request and a call against the counting
// controlled servers, with real process kills and resumes in new processes; resumption and a one-case retry; a manual
// observation and joined paired results; the canary-free export; and cleanup.

import Foundation
import LisaVerifyCases
import LisaVerifyKit
import LisaVerifyServers

enum FixtureCaseRunner {
    typealias Check = VerifyResultRecord.Check

    /// Runs one fixture case, records its result and the case's state, and prints a line.
    static func execute(
        _ verifyCase: VerifyCase, run: inout VerifyRun, store: VerifyRunStore, home: String, attempt: Int
    )
        async throws -> VerifyResultRecord
    {
        run.caseStates[verifyCase.id.text] = .running
        try store.save(run)
        let startWall = VerifyClock.wallClock()
        let start = VerifyClock.monotonicNanoseconds()
        let context = Context(store: store, home: home, run: run, verifyCase: verifyCase, attempt: attempt)
        let checks: [Check]
        switch verifyCase.id.text {
        case "OV-HARNESS-LEDGER-01": checks = try await context.ledgerVariant(1)
        case "OV-HARNESS-LEDGER-02": checks = try await context.ledgerVariant(2)
        case "OV-HARNESS-LEDGER-03": checks = try await context.ledgerVariant(3)
        case "OV-HARNESS-LEDGER-04": checks = try await context.ledgerVariant(4)
        case "OV-HARNESS-RUN-01": checks = try await context.resumeAndRetry()
        case "OV-HARNESS-RUN-02": checks = try context.observationAndPairs()
        case "OV-HARNESS-EXPORT-01": checks = try context.exportCanaries()
        case "OV-HARNESS-CLEANUP-01": checks = try context.cleanupOwnRunOnly()
        case "OV-HARNESS-PREFLIGHT-01": checks = try context.signedEntitlements()
        default: throw VerifyError.unknownCase(verifyCase.id.text)
        }
        let passed = checks.allSatisfy { $0.status == .pass }
        let failing = checks.filter { $0.status != .pass }.map { "\($0.id): \($0.observed)" }
        let record = VerifyResultRecord(
            runID: run.id.text, caseID: verifyCase.id.text, commit: run.commit, harnessVersion: run.harnessVersion,
            providerInterface: verifyCase.interface + " (controlled, test only)",
            configuration: .init(digest: "fixture", fields: ["mode": "fixture", "platform": HarnessInfo.platform]),
            platform: HarnessInfo.platform, deviceModel: "",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            xcodeVersion: "", assumptions: ["controlled servers on 127.0.0.1; no provider contacted"],
            requiredEvidence: verifyCase.requiredEvidence, expectedResult: verifyCase.expectedOutcome,
            observedResult: checks.map { "\($0.id) \($0.status.rawValue)" }.joined(separator: "; "),
            resultLevel: passed ? .harnessReady : nil, requiredResultLevel: verifyCase.requiredResultLevel,
            status: passed ? .pass : .fail, executor: .claude,
            cause: passed ? "every check passed" : failing.joined(separator: "; "),
            actions: try actionOutcomes(context),
            times: .init(
                wallClockStart: startWall, wallClockEnd: VerifyClock.wallClock(), monotonicStartNanoseconds: start,
                monotonicEndNanoseconds: VerifyClock.monotonicNanoseconds()),
            evidenceFiles: ["actions.sqlite", "results.jsonl"], checks: checks)
        try store.append(record, to: run.id)
        run = try store.load(run.id)
        run.caseStates[verifyCase.id.text] = .completed
        try store.save(run)
        print("\(verifyCase.id) \(record.status.rawValue)" + (passed ? "" : " — \(record.cause)"))
        return record
    }

    static func actionOutcomes(_ context: Context) throws -> [String] {
        let path = context.store.ledgerPath(of: context.run.id)
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        return try VerifyActionLedger(path: path).records(in: context.run.id)
            .filter { $0.caseID == context.verifyCase.id }
            .map { "\($0.actionID)=\($0.state.rawValue)" }
    }

    struct Context {
        let store: VerifyRunStore
        let home: String
        let run: VerifyRun
        let verifyCase: VerifyCase
        let attempt: Int

        func check(_ id: String, _ condition: Bool, _ observed: String) -> Check {
            Check(id: id, status: condition ? .pass : .fail, observed: observed, evidenceEntries: 1)
        }

        func child(_ arguments: [String], input: String? = nil) async throws -> ChildProcess.Result {
            try await ChildProcess.run(arguments + ["--home", home], input: input)
        }

        func actionArguments(_ kind: VerifyActionKind, _ position: Int, _ servers: ControlledServers) -> [String] {
            [
                "fixture-action", "--run", run.id.text, "--case", verifyCase.id.text, "--kind", kind.rawValue,
                "--position", String(position), "--smtp-port", String(servers.smtpPort), "--http-port",
                String(servers.httpPort),
            ]
        }

        func resumeArguments(_ servers: ControlledServers) -> [String] {
            ["resume", run.id.text, "--smtp-port", String(servers.smtpPort), "--http-port", String(servers.httpPort)]
        }

        // MARK: The ledger's four interruption variants

        func ledgerVariant(_ variant: Int) async throws -> [Check] {
            let servers = try await ControlledServers.start()
            defer { Task { await servers.stop() } }
            let ledger = try VerifyActionLedger(path: store.ledgerPath(of: run.id))
            var checks: [Check] = []
            for (index, kind) in VerifyActionKind.allCases.enumerated() {
                let position = attempt * 100 + index * 10 + 1
                let planned = FixtureActionExecutor.plannedAction(
                    case: verifyCase.id, kind: kind, position: position, in: run.id)
                let id = planned.actionID(in: run.id)
                let key = FixtureActionExecutor.key(kind: kind, operationID: planned.operationID)
                let name = kind.rawValue
                switch variant {
                case 1:
                    servers.registry.behavior = .init()
                    let killed = try await child(
                        actionArguments(kind, position, servers) + ["--crash-at", "after-intent"])
                    let afterKill = try ledger.record(id)?.state
                    checks.append(
                        check(
                            "\(name)-killed-after-intent",
                            killed.killedBySignal && afterKill == .intent
                                && servers.registry.count(key: key) == 0,
                            "killed: \(killed.killedBySignal); ledger \(afterKill?.rawValue ?? "none"); accepted "
                                + "\(servers.registry.count(key: key))"))
                    let resumed = try await child(resumeArguments(servers))
                    checks.append(
                        try check(
                            "\(name)-resumed-once",
                            resumed.status == 0 && ledger.record(id)?.state == .accepted
                                && servers.registry.count(key: key) == 1,
                            "resume exit \(resumed.status); ledger \(ledger.record(id)?.state.rawValue ?? "none"); "
                                + "accepted \(servers.registry.count(key: key))"))
                case 2:
                    servers.registry.behavior = .init()
                    let killed = try await child(
                        actionArguments(kind, position, servers) + ["--crash-at", "after-accept"])
                    let afterKill = try ledger.record(id)?.state
                    checks.append(
                        check(
                            "\(name)-killed-after-accept",
                            killed.killedBySignal && afterKill == .submitting
                                && servers.registry.count(key: key) == 1,
                            "killed: \(killed.killedBySignal); ledger \(afterKill?.rawValue ?? "none"); accepted "
                                + "\(servers.registry.count(key: key))"))
                    let resumed = try await child(resumeArguments(servers))
                    let state = try ledger.record(id)
                    checks.append(
                        check(
                            "\(name)-observed-not-resent",
                            resumed.status == 0 && state?.state == .accepted
                                && state?.outcome == "accepted (observed)" && servers.registry.count(key: key) == 1,
                            "ledger \(state?.state.rawValue ?? "none") (\(state?.outcome ?? "")); accepted "
                                + "\(servers.registry.count(key: key))"))
                case 3:
                    servers.registry.behavior = .init(answer: .acceptThenDrop, lookupEnabled: false)
                    _ = try await child(actionArguments(kind, position, servers))
                    let ambiguous = try ledger.record(id)?.state
                    _ = try await child(resumeArguments(servers))
                    checks.append(
                        try check(
                            "\(name)-ambiguous-resume-sends-nothing",
                            ambiguous == .ambiguous
                                && ledger.record(id)?.state == .ambiguous && servers.registry.count(key: key) == 1,
                            "ledger \(ambiguous?.rawValue ?? "none"); accepted \(servers.registry.count(key: key))"))
                    let refused = try await child(["authorize-retry", id], input: "yes")
                    checks.append(
                        try check(
                            "\(name)-retry-without-phrase-sends-nothing",
                            refused.status != 0
                                && ledger.record(id + ".r2") == nil && servers.registry.count(key: key) == 1,
                            "exit \(refused.status); accepted \(servers.registry.count(key: key))"))
                    servers.registry.behavior = .init()
                    let authorized = try await child(["authorize-retry", id], input: "may duplicate \(id)")
                    _ = try await child(resumeArguments(servers))
                    let retry = try ledger.record(id + ".r2")
                    checks.append(
                        try check(
                            "\(name)-typed-phrase-exactly-one-more",
                            authorized.status == 0 && retry?.state == .accepted
                                && ledger.record(id)?.state == .superseded && servers.registry.count(key: key) == 2,
                            "retry \(retry?.state.rawValue ?? "none"); accepted \(servers.registry.count(key: key)) "
                                + "(reported as a possible duplicate)"))
                default:
                    servers.registry.behavior = .init()
                    let first = planned
                    let later = FixtureActionExecutor.plannedAction(
                        case: verifyCase.id, kind: kind, position: position + 1, in: run.id)
                    let laterID = later.actionID(in: run.id)
                    let laterKey = FixtureActionExecutor.key(kind: kind, operationID: later.operationID)
                    let oldDigest = try ledger.recordConfirmation([first], in: run.id)
                    let confirmed = try await child(
                        actionArguments(kind, position, servers) + ["--require-confirmation"])
                    let refused = try await child(
                        actionArguments(kind, position + 1, servers) + ["--require-confirmation"])
                    checks.append(
                        try check(
                            "\(name)-new-action-refused-under-old-confirmation",
                            confirmed.status == 0
                                && refused.status != 0 && ledger.record(laterID) == nil
                                && servers.registry.count(key: laterKey) == 0
                                && ledger.confirmation(covering: laterID, in: run.id) == nil,
                            "confirmed exit \(confirmed.status); new action exit \(refused.status); accepted "
                                + "\(servers.registry.count(key: laterKey))"))
                    let newDigest = try ledger.recordConfirmation([later], in: run.id)
                    let accepted = try await child(
                        actionArguments(kind, position + 1, servers) + ["--require-confirmation"])
                    checks.append(
                        try check(
                            "\(name)-new-confirmation-covers-it",
                            accepted.status == 0 && newDigest != oldDigest
                                && ledger.record(laterID)?.state == .accepted
                                && servers.registry.count(key: laterKey) == 1,
                            "exit \(accepted.status); accepted \(servers.registry.count(key: laterKey))"))
                }
            }
            return checks
        }

        // MARK: Resumption and a one-case retry

        func resumeAndRetry() async throws -> [Check] {
            let servers = try await ControlledServers.start()
            defer { Task { await servers.stop() } }
            let ledger = try VerifyActionLedger(path: store.ledgerPath(of: run.id))
            let position = attempt * 100 + 1
            let killed = try await child(actionArguments(.email, position, servers) + ["--crash-at", "after-intent"])
            let state = try store.load(run.id).state(of: verifyCase.id)
            let resumed = try await child(resumeArguments(servers))
            let id = FixtureActionExecutor.plannedAction(
                case: verifyCase.id, kind: .email, position: position, in: run.id
            )
            .actionID(in: run.id)
            var checks = [
                try check(
                    "interrupted-mid-case-resumes",
                    killed.killedBySignal && state == .running && resumed.status == 0
                        && ledger.record(id)?.state == .accepted,
                    "killed \(killed.killedBySignal); case state \(state.rawValue); action "
                        + "\(ledger.record(id)?.state.rawValue ?? "none")")
            ]
            let inner = VerifyRun(
                id: VerifyRunID.generate(), mode: .fixture, createdAt: VerifyClock.wallClock(), commit: run.commit,
                harnessVersion: run.harnessVersion,
                selection: [try VerifyCaseID("OV-HARNESS-EXPORT-01"), try VerifyCaseID("OV-HARNESS-RUN-02")],
                caseStates: ["OV-HARNESS-EXPORT-01": .completed, "OV-HARNESS-RUN-02": .completed])
            try store.create(inner)
            func simulated(_ caseID: String, _ status: VerifyStatus) -> VerifyResultRecord {
                VerifyResultRecord(
                    runID: inner.id.text, caseID: caseID, commit: run.commit, harnessVersion: run.harnessVersion,
                    providerInterface: "simulated earlier result", configuration: .init(digest: "fixture", fields: [:]),
                    platform: HarnessInfo.platform, deviceModel: "", osVersion: "", xcodeVersion: "", assumptions: [],
                    requiredEvidence: [], expectedResult: "",
                    observedResult: "simulated \(status.rawValue) for the retry check",
                    resultLevel: nil, requiredResultLevel: .harnessReady, status: status, executor: .claude,
                    cause: "simulated", actions: [],
                    times: .init(
                        wallClockStart: "", wallClockEnd: "", monotonicStartNanoseconds: 0, monotonicEndNanoseconds: 0),
                    evidenceFiles: [])
            }
            try store.append(simulated("OV-HARNESS-EXPORT-01", .fail), to: inner.id)
            try store.append(simulated("OV-HARNESS-RUN-02", .pass), to: inner.id)
            let retried = try await child(["retry", inner.id.text, "OV-HARNESS-EXPORT-01"])
            let results = try store.results(of: inner.id)
            let export = results.filter { $0.caseID == "OV-HARNESS-EXPORT-01" }
            let other = results.filter { $0.caseID == "OV-HARNESS-RUN-02" }
            checks.append(
                check(
                    "one-failed-case-reruns-alone",
                    retried.status == 0 && export.map(\.status) == [.fail, .pass]
                        && other.count == 1 && other.first?.status == .pass,
                    "retry exit \(retried.status); EXPORT-01 \(export.map(\.status.rawValue)); RUN-02 \(other.count) result"
                ))
            try store.remove(inner.id)
            return checks
        }

        // MARK: A manual observation and joined paired results

        func observationAndPairs() throws -> [Check] {
            let inner = VerifyRun(
                id: VerifyRunID.generate(), mode: .device, createdAt: VerifyClock.wallClock(), commit: run.commit,
                harnessVersion: run.harnessVersion, selection: [])
            try store.create(inner)
            defer { try? store.remove(inner.id) }
            let build = try VerifyCatalogue.find(try VerifyCaseID("OV-APPLE-X1-01"))
            let evidence = store.directory(of: inner.id).appendingPathComponent("build.log")
            try Data("** BUILD SUCCEEDED **\n".utf8).write(to: evidence)
            let observation = try VerifyObservation.record(
                run: inner, case: build, correlatedCaseID: build.id.text, status: .pass, observed: "built (fixture)",
                evidenceFiles: [evidence], platform: "macOS", commit: run.commit, harnessVersion: run.harnessVersion)
            try store.append(observation, to: inner.id)
            let cell = try VerifyCatalogue.find(try VerifyCaseID("OV-NEAR-MI-01"))
            func device(_ role: String, _ nonce: String) -> VerifyResultRecord {
                var record = observation
                record.caseID = "OV-NEAR-MI-01@\(role)"
                record.design = "A"
                record.pairSession = .init(
                    baseCaseID: "OV-NEAR-MI-01", role: role, devices: "mac,iphone", condition: "shared-wifi",
                    harnessNonce: nonce, sessionCodes: ["abcde-12345"])
                return record
            }
            try store.append(device("sender", "aaaa-bbbb-cccc"), to: inner.id)
            let half = VerifyReport.summary(run: inner, results: try store.results(of: inner.id), cases: [build, cell])
            try store.append(device("receiver", "zzzz-zzzz-zzzz"), to: inner.id)
            let mismatched = VerifyReport.summary(run: inner, results: try store.results(of: inner.id), cases: [cell])
            try store.append(device("receiver", "aaaa-bbbb-cccc"), to: inner.id)
            let joined = VerifyReport.summary(run: inner, results: try store.results(of: inner.id), cases: [cell])
            let stored = try store.results(of: inner.id)
            return [
                check(
                    "manual-observation-recorded",
                    stored.first?.evidenceFiles.first?.hasPrefix("build.log sha256:") == true
                        && stored.first?.executor == .owner,
                    stored.first?.evidenceFiles.first ?? "none"),
                check(
                    "paired-results-join-under-case-and-nonce",
                    half.contains("waiting (one device's result)")
                        && mismatched.contains("waiting (one device's result)")
                        && joined.contains("| PASS |"),
                    "one device: waiting; mismatched nonce: waiting; both under one nonce: PASS"),
            ]
        }

        // MARK: The canary-free export

        func exportCanaries() throws -> [Check] {
            let inner = VerifyRun(
                id: VerifyRunID.generate(), mode: .fixture, createdAt: VerifyClock.wallClock(), commit: run.commit,
                harnessVersion: run.harnessVersion, selection: [])
            try store.create(inner)
            defer { try? store.remove(inner.id) }
            let canaries = [
                "canary.owner@example.org", "+1 415 555 0199", "https://p01-caldav.icloud.example/123/calendars/x/",
                "Tell me about CANARYPROMPTCANARYPROMPTCANARYPROMPT",
                "Subject: CANARY-MAIL-BODY-7f3a9c2e1d4b5a6f8e9d0c1b",
                "sk-live-CANARYKEYCANARYKEYCANARYKEY12",
                "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0",
            ]
            var record = VerifyResultRecord(
                runID: inner.id.text, caseID: "OV-APPLE-X1-01", commit: run.commit, harnessVersion: run.harnessVersion,
                providerInterface: "fixture",
                configuration: .init(digest: "d", fields: ["design": "A", "apiKey": canaries[5]]),
                platform: "macOS", deviceModel: "", osVersion: "", xcodeVersion: "",
                assumptions: ["prompt: \(canaries[3])"], requiredEvidence: [], expectedResult: "",
                observedResult: "mail \(canaries[4]) to \(canaries[0]); called \(canaries[1]); calendar \(canaries[2])",
                resultLevel: nil, requiredResultLevel: .ownerVerified, status: .fail, executor: .owner,
                cause: "push token \(canaries[6])", actions: [],
                times: .init(
                    wallClockStart: "", wallClockEnd: "", monotonicStartNanoseconds: 0, monotonicEndNanoseconds: 0),
                evidenceFiles: [])
            let action = VerifyActionRecord(
                actionID: "OVA-\(inner.id.text)-OV-HARNESS-EXPORT-01-1", runID: inner.id,
                caseID: try VerifyCaseID("OV-HARNESS-EXPORT-01"), position: 1, kind: .email, targetAlias: "recipient-1",
                operationID: "op", slot: nil, confirmationDigest: "d", retryOf: nil, state: .accepted,
                providerReference: "<canary-ref-\(canaries[0])>", outcome: "250", createdAt: "", updatedAt: "")
            let data = try VerifyRedactedExport.make(
                run: inner, results: [record], actions: [action], canaries: canaries)
            let text = String(decoding: data, as: UTF8.self)
            let surviving = canaries.filter { text.contains($0) }
            record.design = canaries[0]
            var refused = false
            do {
                _ = try VerifyRedactedExport.make(run: inner, results: [record], actions: [], canaries: canaries)
            } catch {
                refused = true
            }
            return [
                check(
                    "no-planted-canary-survives", surviving.isEmpty, "\(surviving.count) of \(canaries.count) survived"),
                check("export-refused-when-a-canary-would-survive", refused, refused ? "refused" : "written"),
            ]
        }

        // MARK: Signed entitlements and profiles

        func signedEntitlements() throws -> [Check] {
            func plist(_ object: [String: Any]) throws -> Data {
                try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
            }
            let bundle = "org.example.lisa.companion"
            let later = Date().addingTimeInterval(86_400 * 90)
            func product(
                _ platform: ApplePlatform, entitlements: [String: Any], profileAPS: String?,
                devices: [String]? = ["UDID-1"],
                expiration: Date? = nil, sandbox: Bool = false
            ) throws -> AppleSignedProduct {
                var granted: [String: Any] = ["application-identifier": "TEAMID0000.\(bundle)", "get-task-allow": true]
                if let profileAPS { granted[platform.apsEntitlementKey] = profileAPS }
                var profile: [String: Any] = [
                    "TeamIdentifier": ["TEAMID0000"], "Entitlements": granted, "ExpirationDate": expiration ?? later,
                ]
                if let devices { profile["ProvisionedDevices"] = devices }
                var signed = entitlements
                if sandbox { signed["com.apple.security.app-sandbox"] = true }
                return try AppleSignedProduct.parse(
                    platform: platform, infoPlist: try plist(["CFBundleIdentifier": bundle]),
                    entitlementsPlist: try plist(signed), profilePlist: try plist(profile))
            }
            let push = ApplePushRequirement(environment: "development", topic: bundle)
            let mac = try product(
                .macOS, entitlements: ["com.apple.developer.aps-environment": "development"], profileAPS: "development")
            let phone = try product(.iOS, entitlements: ["aps-environment": "development"], profileAPS: "development")
            let macWithIOSKey = try product(.macOS, entitlements: ["aps-environment": "development"], profileAPS: nil)
            let phoneWithMacKey = try product(
                .iOS, entitlements: ["com.apple.developer.aps-environment": "development"], profileAPS: nil)
            let missing = try product(.iOS, entitlements: [:], profileAPS: nil)
            let production = try product(
                .iOS, entitlements: ["aps-environment": "production"], profileAPS: "production")
            let expired = try product(
                .macOS, entitlements: ["com.apple.developer.aps-environment": "development"], profileAPS: "development",
                expiration: Date(timeIntervalSince1970: 1_700_000_000))
            let sandboxed = try product(.macOS, entitlements: [:], profileAPS: nil, sandbox: true)
            func refused(_ reasons: [String], containing text: String) -> Bool {
                reasons.contains { $0.contains(text) }
            }
            return [
                check(
                    "each-platform-key-with-matching-environment-passes",
                    ApplePreflight.refusals(mac, push: push, deviceUDID: nil).isEmpty
                        && ApplePreflight.refusals(phone, push: push, deviceUDID: "UDID-1").isEmpty,
                    "macOS \(ApplePreflight.refusals(mac, push: push, deviceUDID: nil)); iOS "
                        + "\(ApplePreflight.refusals(phone, push: push, deviceUDID: "UDID-1"))"),
                check(
                    "other-platform-key-only-stops",
                    refused(
                        ApplePreflight.refusals(macWithIOSKey, push: push, deviceUDID: nil),
                        containing: "only aps-environment")
                        && refused(
                            ApplePreflight.refusals(phoneWithMacKey, push: push, deviceUDID: "UDID-1"),
                            containing: "only com.apple.developer.aps-environment"),
                    "both platforms refuse the other's key"),
                check(
                    "missing-key-stops",
                    refused(
                        ApplePreflight.refusals(missing, push: push, deviceUDID: "UDID-1"),
                        containing: "no aps-environment"),
                    "\(ApplePreflight.refusals(missing, push: push, deviceUDID: "UDID-1"))"),
                check(
                    "mismatched-environment-or-topic-stops",
                    refused(
                        ApplePreflight.refusals(production, push: push, deviceUDID: "UDID-1"),
                        containing: "is production")
                        && refused(
                            ApplePreflight.refusals(
                                phone,
                                push: ApplePushRequirement(environment: "development", topic: "org.example.other"),
                                deviceUDID: "UDID-1"), containing: "isn't the bundle identifier"),
                    "environment and topic mismatches refused"),
                check(
                    "unlisted-device-and-expired-profile-stop",
                    refused(
                        ApplePreflight.refusals(phone, push: push, deviceUDID: "UDID-9"),
                        containing: "doesn't list this device")
                        && refused(ApplePreflight.refusals(expired, push: push, deviceUDID: nil), containing: "expired"),
                    "unlisted device and expired profile refused"),
                check(
                    "identifiers-derive-from-the-bundle-id",
                    mac.apnsTopic == bundle && mac.keychainServices.clientIdentity == bundle + ".client-identity"
                        && mac.r1ClientDirectory(home: "/Users/o")
                            == "/Users/o/Library/Application Support/\(bundle)/Client"
                        && sandboxed.r1ClientDirectory(home: "/Users/o")
                            == "/Users/o/Library/Containers/\(bundle)/Data/Library/Application Support/\(bundle)/Client"
                        && phone.profile?.kind == "development",
                    "topic, Keychain service and client directory (plain and sandboxed) derived"),
            ]
        }

        // MARK: Cleanup removes only the run's own data

        func cleanupOwnRunOnly() throws -> [Check] {
            func inner() throws -> VerifyRun {
                let made = VerifyRun(
                    id: VerifyRunID.generate(), mode: .fixture, createdAt: VerifyClock.wallClock(), commit: run.commit,
                    harnessVersion: run.harnessVersion, selection: [])
                try store.create(made)
                return made
            }
            let first = try inner()
            var second = try inner()
            while second.id == first.id { second = try inner() }
            let unrelated = store.home.appendingPathComponent("unrelated-\(first.id.text).txt")
            try Data("not the harness's".utf8).write(to: unrelated)
            try store.remove(first.id)
            let firstGone = !FileManager.default.fileExists(atPath: store.directory(of: first.id).path)
            let secondKept = FileManager.default.fileExists(atPath: store.directory(of: second.id).path)
            let unrelatedKept = FileManager.default.fileExists(atPath: unrelated.path)
            var repeatRefused = false
            do { try store.remove(first.id) } catch { repeatRefused = true }
            try store.remove(second.id)
            try? FileManager.default.removeItem(at: unrelated)
            return [
                check(
                    "only-the-runs-own-data-removed", firstGone && secondKept && unrelatedKept && repeatRefused,
                    "removed \(firstGone); other run kept \(secondKept); unrelated file kept \(unrelatedKept); "
                        + "second removal refused \(repeatRefused)")
            ]
        }
    }
}
