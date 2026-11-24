// A device's role in a paired session (plan §10.8 "Paired-device sessions").

/// Which side of a paired case a device plays; its result carries `<case>@<role>`.
public enum VerifyPairRole: String, Hashable, Sendable, Codable, CaseIterable {
    case sender
    case receiver
}
