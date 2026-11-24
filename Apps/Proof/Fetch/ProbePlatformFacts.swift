// PROOF ONLY — Apps/Proof never ships. OV-APPLE-X1-FETCH-09: the platform behavior §8.9.3's design relies on, each
// recorded: `DNSServiceGetAddrInfo` and `DNSServiceQueryRecord` scoped to an interface index, with TTLs;
// `NWConnection` honoring `requiredInterface` (a public address required onto loopback must never become ready);
// `currentPath` reporting the interface and remote endpoint before the first write; and whether the running system
// exports `nw_nat64_copy_prefixes_async` (looked up with dlsym, never called; whether the SDK headers declare it is
// for the owner to check with grep; Harness/docs/SETUP-APPLE.md).

import Darwin
import Foundation
import Network

struct ProbePlatformFactsReport: Codable, Sendable {
    var interface = ""
    var pathKind: ProbePathKind = .unsatisfied
    var addrInfo: ProbeResolution?
    var addrInfoTTLsReported = false
    var addrInfoInterfaceScoped = false
    var queryRecord: ProbeNAT64Evidence?
    var queryRecordTTLReported = false
    var requiredInterfaceOnRequestInterface: ProbeDialRecord?
    var requiredInterfaceOnLoopback: ProbeDialRecord?
    var currentPathBeforeWrite = false
    var nat64CopyPrefixesSymbolPresent = false
}

enum ProbePlatformFacts {
    /// - Parameter name: an owner-authorized public name with A records; `port` its HTTPS port.
    static func run(name: String, port: UInt16 = 443) async -> ProbePlatformFactsReport {
        var report = ProbePlatformFactsReport()
        guard let request = await ProbeRequestInterface.current() else { return report }
        report.interface = request.name
        report.pathKind = request.pathKind
        let resolution = await ProbeAddressResolver.resolveA(host: name, interfaceIndex: request.index)
        report.addrInfo = resolution
        if case .answers(let answers) = resolution {
            report.addrInfoTTLsReported = answers.allSatisfy { $0.ttl > 0 }
            report.addrInfoInterfaceScoped = answers.allSatisfy { $0.interfaceIndex == request.index }
        }
        let nat64 = await ProbeNAT64Discovery.discover(interfaceIndex: request.index)
        report.queryRecord = nat64
        report.queryRecordTTLReported = nat64.minimumTTL.map { $0 > 0 } ?? false

        if case .answers(let answers) = resolution, let first = answers.first,
            case .dial(let targets) = ProbeDestinationPolicy.dialTargets(
                forIPv4: [first.bytes], path: request.pathKind, prefixes: nat64.prefixes),
            let target = targets.first
        {
            let (connection, dial) = await ProbeDialer.connect(
                to: target, port: port, serverName: name, interface: request.interface)
            report.requiredInterfaceOnRequestInterface = dial
            report.currentPathBeforeWrite = dial.remoteEndpointMatched == true && dial.interfaceMatched == true
            connection?.cancel()
            if let loopback = await ProbeRequestInterface.current(requiredType: .loopback) {
                let (stray, strayDial) = await ProbeDialer.connect(
                    to: target, port: port, serverName: name, interface: loopback.interface, timeoutSeconds: 3)
                stray?.cancel()
                report.requiredInterfaceOnLoopback = strayDial
            }
        }
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        report.nat64CopyPrefixesSymbolPresent = dlsym(defaultHandle, "nw_nat64_copy_prefixes_async") != nil
        return report
    }
}
