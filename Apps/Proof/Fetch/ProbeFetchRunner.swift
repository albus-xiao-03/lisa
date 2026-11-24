// PROOF ONLY — Apps/Proof never ships. One E-1 probe fetch with Core unavailable (plan §8.9.3): one interface for
// the whole request; NAT64 evidence on an IPv6-only path; for every hop, checks 1–4 from the start (a redirect target
// is a new initial URL); dials one checked address at a time; at most 3 redirects; fail closed whenever evidence is
// missing, expired (older than the smallest TTL in the chain) or contradicted by the connected path. No request byte
// is written before the checks pass; nothing is retried through URLSession.

import Foundation
import LisaCrypto
import LisaHTTP
import Network

enum ProbeFetchRunner {
    static let maximumRedirects = 3

    static func fetch(_ initial: URL) async -> ProbeFetchTrace {
        guard let request = await ProbeRequestInterface.current() else {
            var trace = ProbeFetchTrace(
                interface: "none", interfaceIndex: 0, pathKind: .unsatisfied, availableInterfaces: [])
            trace.finalOutcome = "failed-closed"
            return trace
        }
        var trace = ProbeFetchTrace(
            interface: request.name, interfaceIndex: request.index, pathKind: request.pathKind,
            availableInterfaces: request.availableNames)
        var deadline = UInt64.max
        if request.pathKind == .ipv6Only {
            let evidence = await ProbeNAT64Discovery.discover(interfaceIndex: request.index)
            trace.nat64 = evidence
            if let ttl = evidence.minimumTTL { deadline = min(deadline, now() + UInt64(ttl) * 1_000_000_000) }
        }
        let prefixes = trace.nat64?.prefixes ?? []
        var url = initial
        for hopNumber in 0...maximumRedirects {
            var hop = ProbeHop(
                origin: URLPolicy.origin(of: url), urlSHA256: Digests.sha256Hex(Data(url.absoluteString.utf8)))
            let checked: ProbeCheckedURL
            switch ProbeDestinationPolicy.checkURL(url) {
            case .failure(let refusal):
                hop.check1 = refusal.reason
                hop.outcome = "refused-before-connect"
                return finish(&trace, hop, hopNumber)
            case .success(let value):
                checked = value
            }
            var decision = ProbeDestinationPolicy.decideHost(checked.host, path: request.pathKind, prefixes: prefixes)
            if case .resolveA(let host) = decision {
                let resolution = await ProbeAddressResolver.resolveA(host: host, interfaceIndex: request.index)
                hop.resolution = resolution
                switch resolution {
                case .answers(let answers):
                    hop.minimumTTL = answers.map(\.ttl).min()
                    if let ttl = hop.minimumTTL { deadline = min(deadline, now() + UInt64(ttl) * 1_000_000_000) }
                    decision = ProbeDestinationPolicy.dialTargets(
                        forIPv4: answers.map(\.bytes), path: request.pathKind, prefixes: prefixes)
                case .noSuchRecord:
                    decision = .deferToCore(ProbeDestinationPolicy.deferMessage)
                case .failed, .timedOut:
                    decision = .refuse(ProbeDestinationPolicy.unverifiableMessage)
                }
            }
            hop.decision = String(describing: decision)
            let targets: [ProbeDialTarget]
            switch decision {
            case .refuse(let message):
                hop.outcome =
                    hop.resolution == nil || message == ProbeDestinationPolicy.refusedMessage
                    ? "refused-before-connect" : "failed-closed"
                hop.message = message
                return finish(&trace, hop, hopNumber)
            case .deferToCore(let message):
                hop.outcome = "deferred-to-core"
                hop.message = message
                return finish(&trace, hop, hopNumber)
            case .resolveA:
                hop.outcome = "failed-closed"
                return finish(&trace, hop, hopNumber)
            case .dial(let list):
                targets = list
            }
            var response: ProbeHTTPResponse?
            for target in targets {
                guard now() <= deadline else {
                    trace.evidenceExpired = true
                    break
                }
                let (connection, dial) = await ProbeDialer.connect(
                    to: target, port: checked.port, serverName: checked.host, interface: request.interface)
                hop.dials.append(dial)
                guard let connection else { continue }
                do {
                    response = try await ProbeHTTP1Exchange.get(
                        on: connection, host: checked.host, port: checked.port, pathAndQuery: checked.pathAndQuery)
                } catch {
                    hop.message = "after connect: \(error)"
                }
                connection.cancel()
                break
            }
            hop.response = response
            guard let response else {
                hop.outcome = hop.dials.contains { $0.outcome == "ready" } ? "failed-after-connect" : "failed-closed"
                hop.message = hop.message ?? ProbeDestinationPolicy.unverifiableMessage
                return finish(&trace, hop, hopNumber)
            }
            if HTTPRedirects.followedStatuses.contains(response.status), let location = response.location,
                let next = URL(string: location, relativeTo: url)?.absoluteURL
            {
                hop.outcome = "redirect"
                trace.hops.append(hop)
                url = next
                continue
            }
            hop.outcome = "fetched"
            return finish(&trace, hop, hopNumber)
        }
        trace.finalOutcome = "redirect-limit"
        return trace
    }

    private static func finish(_ trace: inout ProbeFetchTrace, _ hop: ProbeHop, _ hopNumber: Int) -> ProbeFetchTrace {
        trace.hops.append(hop)
        switch (hopNumber, hop.outcome) {
        case (1..., "refused-before-connect"): trace.finalOutcome = "redirect-stopped-refused"
        case (1..., "deferred-to-core"): trace.finalOutcome = "redirect-stopped-deferred"
        default: trace.finalOutcome = hop.outcome
        }
        return trace
    }

    private static func now() -> UInt64 {
        ProofMonotonicClock.nowNanoseconds()
    }
}
