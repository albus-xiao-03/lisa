// PROOF ONLY — Apps/Proof never ships. E-1 fetch probe (plan §8.9.3 check 1, "One interface for the whole
// request"): the request takes the first available interface of the current `NWPath` and records its index, name and
// the path's address families. Resolution, NAT64 discovery and the connection all use that one interface.

import Foundation
import Network

enum ProbePathKind: String, Codable, Sendable {
    case ipv4Only = "ipv4-only"
    case ipv6Only = "ipv6-only"
    case dualStack = "dual-stack"
    case unsatisfied
}

struct ProbeRequestInterface: @unchecked Sendable {
    let interface: NWInterface
    let pathKind: ProbePathKind
    let availableNames: [String]

    var index: UInt32 { UInt32(truncatingIfNeeded: interface.index) }
    var name: String { interface.name }

    /// The current path's first available interface, or nil when the path has none.
    static func current(requiredType: NWInterface.InterfaceType? = nil) async -> ProbeRequestInterface? {
        let path = await firstPath(requiredType: requiredType)
        guard path.status == .satisfied, let first = path.availableInterfaces.first else { return nil }
        let kind: ProbePathKind =
            switch (path.supportsIPv4, path.supportsIPv6) {
            case (true, true): .dualStack
            case (true, false): .ipv4Only
            case (false, true): .ipv6Only
            case (false, false): .unsatisfied
            }
        return ProbeRequestInterface(
            interface: first, pathKind: kind, availableNames: path.availableInterfaces.map(\.name))
    }

    /// The first path update of a fresh monitor; the monitor is cancelled after it.
    static func firstPath(requiredType: NWInterface.InterfaceType?) async -> NWPath {
        await withCheckedContinuation { continuation in
            let monitor = requiredType.map { NWPathMonitor(requiredInterfaceType: $0) } ?? NWPathMonitor()
            let once = ProbeOnce()
            monitor.pathUpdateHandler = { path in
                guard once.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: path)
            }
            monitor.start(queue: DispatchQueue(label: "org.example.lisa.proof.path"))
        }
    }
}
