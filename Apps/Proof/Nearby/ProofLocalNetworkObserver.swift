// PROOF ONLY — Apps/Proof never ships. Reads local-network privacy outcomes from Network framework states
// (TN3179, plan §1.5 and §8.7): a denial shows as the DNS error −65570 (kDNSServiceErr_PolicyDenied) on a listener or
// browser, or as `localNetworkDenied` on an unsatisfied path. Whether the prompt appeared, and what the owner chose,
// only the owner can see; the UI asks for that observation and records it beside these states.

import Network

enum ProofLocalNetworkState: String, Codable, Sendable {
    case ready
    case deniedPolicy = "denied-dns-policy-65570"
    case deniedPath = "denied-path-localNetworkDenied"
    case waiting
    case failed
}

enum ProofLocalNetworkObserver {
    static let policyDenied: Int32 = -65570

    static func classify(_ error: NWError) -> ProofLocalNetworkState {
        if case .dns(let code) = error, code == policyDenied { return .deniedPolicy }
        return .waiting
    }

    /// The path's denial, if it shows one.
    static func classify(_ path: NWPath?) -> ProofLocalNetworkState? {
        guard let path, path.status == .unsatisfied, path.unsatisfiedReason == .localNetworkDenied else { return nil }
        return .deniedPath
    }

    static func classify(_ state: NWListener.State) -> ProofLocalNetworkState? {
        switch state {
        case .ready: .ready
        case .waiting(let error): classify(error)
        case .failed(let error): classify(error) == .deniedPolicy ? .deniedPolicy : .failed
        default: nil
        }
    }

    static func classify(_ state: NWBrowser.State) -> ProofLocalNetworkState? {
        switch state {
        case .ready: .ready
        case .waiting(let error): classify(error)
        case .failed(let error): classify(error) == .deniedPolicy ? .deniedPolicy : .failed
        default: nil
        }
    }
}
