// `lisa-verify pair-session <case> --devices … --condition …` (plan §10.8 "Paired-device sessions"): per device, the
// scheme, test plan and destination, its role, and the session nonce both screens show. Without `--run` it starts a
// device-mode run.

import ArgumentParser
import Foundation
import LisaVerifyCases
import LisaVerifyKit

struct PairSessionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pair-session", abstract: "Start a paired-device session of a case.")

    @Argument(help: "A paired case, for example OV-NEAR-MI-01.") var caseID: String
    @Option(help: "mac,iphone | mac,ipad | iphone,ipad") var devices: String
    @Option(help: "shared-wifi | no-internet | no-access-point") var condition: String
    @Option(name: .customLong("run"), help: "Add the session to this run instead of starting a new one.")
    var existingRun: String?
    @OptionGroup var storeOptions: StoreOptions

    func run() throws {
        let verifyCase = try VerifyCatalogue.find(try VerifyCaseID(caseID))
        guard verifyCase.paired else { throw VerifyError.invalidInput("\(verifyCase.id) is not a paired case") }
        let store = storeOptions.store
        let runRecord: VerifyRun
        if let existingRun {
            runRecord = try store.load(try VerifyRunID(existingRun))
        } else {
            runRecord = VerifyRun(
                id: VerifyRunID.generate(), mode: .device, createdAt: VerifyClock.wallClock(),
                commit: HarnessInfo.commit(), harnessVersion: HarnessInfo.version, selection: [verifyCase.id])
            try store.create(runRecord)
        }
        let session = try VerifyPairSession(
            runID: runRecord.id, caseID: verifyCase.id, devices: devices, condition: condition)
        try PairSessionLog.append(session, store: store)
        print("Run \(runRecord.id)   case \(verifyCase.id)   condition \(condition)")
        print("Session nonce (enter it on both devices): \(session.nonce)")
        for (device, role) in session.roles {
            print(
                "  \(device): role \(role.rawValue), correlated case \(verifyCase.id.correlated(role)); scheme LisaProof, "
                    + "test plan X1, destination \(VerifyPairSession.destination(for: device))")
        }
        print("Steps: lisa-verify guide \(verifyCase.id)")
    }
}

/// The run's `pair-sessions.jsonl`, append-only.
enum PairSessionLog {
    static func append(_ session: VerifyPairSession, store: VerifyRunStore) throws {
        let file = store.directory(of: session.runID).appendingPathComponent("pair-sessions.jsonl")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var line = try encoder.encode(session)
        line.append(UInt8(ascii: "\n"))
        if !FileManager.default.fileExists(atPath: file.path) {
            guard
                FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
            else { throw VerifyError.store("can't create \(file.path)") }
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.synchronize()
    }
}
