// A paired-device session (plan §10.8 "Paired-device sessions (X1, X4, X7)"): the devices, the condition, each
// device's role and a session nonce shown on both screens, so the two device results join without a shared clock.

import Foundation

/// One paired session of a case, recorded in the run's `pair-sessions.jsonl`.
public struct VerifyPairSession: Codable, Sendable, Equatable {
    public let runID: VerifyRunID
    public let caseID: VerifyCaseID
    /// `mac,iphone`, `mac,ipad` or `iphone,ipad`; the first device sends, the second receives.
    public let devices: String
    /// `shared-wifi`, `no-internet` or `no-access-point`.
    public let condition: String
    /// Twelve lowercase base32 characters in three groups, shown on both screens.
    public let nonce: String
    public let createdAt: String

    public static let deviceChoices = ["mac,iphone", "mac,ipad", "iphone,ipad"]
    public static let conditions = ["shared-wifi", "no-internet", "no-access-point"]

    public init(runID: VerifyRunID, caseID: VerifyCaseID, devices: String, condition: String) throws(VerifyError) {
        guard Self.deviceChoices.contains(devices) else {
            throw .invalidInput("--devices must be one of \(Self.deviceChoices.joined(separator: ", "))")
        }
        guard Self.conditions.contains(condition) else {
            throw .invalidInput("--condition must be one of \(Self.conditions.joined(separator: ", "))")
        }
        self.runID = runID
        self.caseID = caseID
        self.devices = devices
        self.condition = condition
        var generator = SystemRandomNumberGenerator()
        let characters = (0..<12).map { _ in VerifyRunID.alphabet[Int.random(in: 0..<32, using: &generator)] }
        nonce = [0, 4, 8].map { String(characters[$0..<($0 + 4)]) }.joined(separator: "-")
        createdAt = VerifyClock.wallClock()
    }

    /// Each device with its role: the pair's first device is the sender.
    public var roles: [(device: String, role: VerifyPairRole)] {
        let names = devices.split(separator: ",").map(String.init)
        return [(names[0], .sender), (names[1], .receiver)]
    }

    /// What `pair-session` prints for one device: the scheme, test plan and destination, or the guided steps.
    public static func destination(for device: String) -> String {
        device == "mac" ? "'platform=macOS'" : "'platform=iOS,id=<UDID of the \(device)>'"
    }
}
