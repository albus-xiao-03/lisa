// PROOF ONLY — Apps/Proof never ships. The §8.9.3 destination decision for one URL hop, before anything is
// resolved or opened, public only (the probe has no self-hosted model endpoint). R1's URL policy and address
// classification come from LisaHTTP (`URLPolicy`, `IPLiteral`, `NetworkAddress`, `AddressPolicy.publicOnly`); the
// literal rules and the path table are the proof's, until M7 writes them portably (docs/DECISIONS.md D-54).
//   IPv4 literal                    → classified like an A answer, then the path table
//   ::ffff:a.b.c.d                  → classified and dialed as a.b.c.d
//   64:ff9b::/96 or discovered      → embedded IPv4 classified; dialed only if public and the path is IPv6-only with
//                                     that prefix discovered on this interface; otherwise deferred
//   any other IPv6 literal          → deferred to Core (never dialed)
//   a DNS name                      → A records only; none usable → deferred; only refused addresses → refused

import Foundation
import LisaHTTP

struct ProbeDialTarget: Codable, Sendable, Equatable {
    let address: [UInt8]
    let text: String
    let embeddedIPv4: String?
    let reason: String
}

enum ProbeDecision: Codable, Sendable, Equatable {
    case resolveA(host: String)
    case dial([ProbeDialTarget])
    case refuse(String)
    case deferToCore(String)
}

struct ProbeCheckedURL: Sendable {
    let url: URL
    let host: String
    let port: UInt16
    let pathAndQuery: String
}

enum ProbeDestinationPolicy {
    static let deferMessage =
        "Lisa can't verify this destination on this device; Lisa Core will fetch it when it's reachable."
    static let refusedMessage = "resolves only to addresses Lisa does not connect to"
    static let unverifiableMessage = "Couldn't verify where this link leads; not fetched"

    /// Why check 1 refused a URL.
    struct URLRefusal: Error, Sendable, Equatable {
        let reason: String
    }

    /// Check 1's URL part: R1's policy (https, no credentials, host syntax, port) under `publicOnly`.
    static func checkURL(_ url: URL) -> Result<ProbeCheckedURL, URLRefusal> {
        switch URLPolicy.validate(url, addresses: .publicOnly) {
        case .failure(let failure):
            return .failure(URLRefusal(reason: String(describing: failure)))
        case .success(let cleaned):
            guard let components = URLComponents(url: cleaned, resolvingAgainstBaseURL: true),
                let rawHost = components.host
            else { return .failure(URLRefusal(reason: "the address does not name a valid host")) }
            let host =
                rawHost.hasPrefix("[") && rawHost.hasSuffix("]") ? String(rawHost.dropFirst().dropLast()) : rawHost
            var path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
            if let query = components.percentEncodedQuery { path += "?" + query }
            return .success(
                ProbeCheckedURL(url: cleaned, host: host, port: UInt16(components.port ?? 443), pathAndQuery: path))
        }
    }

    /// The literal rules; a name is returned for A resolution.
    static func decideHost(_ host: String, path: ProbePathKind, prefixes: [ProbeNAT64Prefix]) -> ProbeDecision {
        guard let literal = IPLiteral.parse(host) else { return .resolveA(host: host.lowercased()) }
        let bytes = literal.bytes
        guard literal.isIPv6 else { return dialTargets(forIPv4: [bytes], path: path, prefixes: prefixes) }
        if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
            return dialTargets(forIPv4: [Array(bytes[12..<16])], path: path, prefixes: prefixes)
        }
        if let prefix = (prefixes + [ProbeNAT64Prefix.wellKnown]).first(where: { $0.contains(bytes) }),
            let embedded = prefix.embeddedIPv4(bytes)
        {
            guard permitsPublic(embedded) else { return .refuse(refusedMessage) }
            guard path == .ipv6Only, prefixes.contains(prefix) else { return .deferToCore(deferMessage) }
            return .dial([
                ProbeDialTarget(
                    address: bytes, text: literal.description, embeddedIPv4: dotted(embedded),
                    reason: "translated literal under the discovered prefix \(prefix.text)")
            ])
        }
        return .deferToCore(deferMessage)
    }

    /// The path table for public IPv4 evidence (A answers or IPv4 literals).
    static func dialTargets(forIPv4 addresses: [[UInt8]], path: ProbePathKind, prefixes: [ProbeNAT64Prefix])
        -> ProbeDecision
    {
        let permitted = addresses.filter(permitsPublic)
        guard !permitted.isEmpty else { return .refuse(refusedMessage) }
        switch path {
        case .ipv4Only, .dualStack:
            return .dial(
                permitted.map {
                    ProbeDialTarget(
                        address: $0, text: dotted($0), embeddedIPv4: nil, reason: "public IPv4, dialed natively")
                })
        case .ipv6Only:
            guard let prefix = prefixes.first else { return .deferToCore(deferMessage) }
            return .dial(
                permitted.map { ipv4 in
                    let synthesized = prefix.synthesize(ipv4)
                    return ProbeDialTarget(
                        address: synthesized, text: NetworkAddress(bytes: synthesized)?.description ?? "?",
                        embeddedIPv4: dotted(ipv4), reason: "public IPv4 synthesized with \(prefix.text)")
                })
        case .unsatisfied:
            return .refuse(unverifiableMessage)
        }
    }

    static func permitsPublic(_ ipv4: [UInt8]) -> Bool {
        guard let address = NetworkAddress(bytes: ipv4) else { return false }
        return AddressPolicy.publicOnly.permits(address)
    }

    static func dotted(_ ipv4: [UInt8]) -> String {
        ipv4.map(String.init).joined(separator: ".")
    }
}
