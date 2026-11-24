// PROOF ONLY — Apps/Proof never ships. E-1 probe, checks 2–4 of plan §8.9.3: `NWConnection` to one checked IP
// endpoint (never by name, deliberately departing from TN3151), `preferNoProxies`, `requiredInterface` set to the
// request's interface, system TLS with minimum 1.2 and the URL's host as the TLS server name; then, before any request
// byte, `currentPath.remoteEndpoint` must equal the chosen endpoint and the path must use the request's interface.

import Foundation
import Network
import Security

struct ProbeDialRecord: Codable, Sendable {
    let target: String
    let requiredInterface: String
    /// "ready", "failed: …", "waiting: …" or "timed-out".
    let outcome: String
    let remoteEndpointMatched: Bool?
    let interfaceMatched: Bool?
    let pathInterfaces: [String]
    let tlsVersion: String?
    let elapsedNanoseconds: UInt64
}

enum ProbeDialer {
    static func connect(
        to target: ProbeDialTarget, port: UInt16, serverName: String, interface: NWInterface,
        timeoutSeconds: Double = 10
    ) async -> (NWConnection?, ProbeDialRecord) {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, serverName)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.requiredInterface = interface
        parameters.preferNoProxies = true
        let host: NWEndpoint.Host? =
            target.address.count == 4
            ? IPv4Address(Data(target.address)).map { .ipv4($0) } : IPv6Address(Data(target.address)).map { .ipv6($0) }
        let start = ProofMonotonicClock.nowNanoseconds()
        guard let host, let nwPort = NWEndpoint.Port(rawValue: port) else {
            return (nil, record(target, interface, "invalid endpoint", nil, nil, [], nil, start))
        }
        let endpoint = NWEndpoint.hostPort(host: host, port: nwPort)
        let connection = NWConnection(to: endpoint, using: parameters)
        let outcome: String = await withCheckedContinuation { continuation in
            let once = ProbeOnce()
            let queue = DispatchQueue(label: "org.example.lisa.proof.dial")
            connection.stateUpdateHandler = { state in
                let result: String? =
                    switch state {
                    case .ready: "ready"
                    case .failed(let error): "failed: \(error)"
                    case .waiting(let error): "waiting: \(error)"
                    default: nil
                    }
                if let result, once.claim() { continuation.resume(returning: result) }
            }
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                if once.claim() { continuation.resume(returning: "timed-out") }
            }
            connection.start(queue: queue)
        }
        guard outcome == "ready" else {
            connection.cancel()
            return (nil, record(target, interface, outcome, nil, nil, [], nil, start))
        }
        let path = connection.currentPath
        let endpointMatched = sameEndpoint(path?.remoteEndpoint, endpoint)
        let interfaceMatched = path?.availableInterfaces.first?.index == interface.index
        var version: String?
        if let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata {
            version = ProofCipherSuiteNames.version(
                sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata.securityProtocolMetadata).rawValue)
        }
        let dial = record(
            target, interface, outcome, endpointMatched, interfaceMatched,
            path?.availableInterfaces.map(\.name) ?? [], version, start)
        guard endpointMatched, interfaceMatched else {
            connection.cancel()
            return (nil, dial)
        }
        return (connection, dial)
    }

    /// Host bytes and port only; an interface scope on the reported endpoint does not matter for public addresses.
    static func sameEndpoint(_ reported: NWEndpoint?, _ chosen: NWEndpoint) -> Bool {
        guard case .hostPort(let reportedHost, let reportedPort)? = reported,
            case .hostPort(let chosenHost, let chosenPort) = chosen, reportedPort == chosenPort
        else { return false }
        switch (reportedHost, chosenHost) {
        case (.ipv4(let a), .ipv4(let b)): return a.rawValue == b.rawValue
        case (.ipv6(let a), .ipv6(let b)): return a.rawValue == b.rawValue
        default: return false
        }
    }

    private static func record(
        _ target: ProbeDialTarget, _ interface: NWInterface, _ outcome: String, _ endpoint: Bool?, _ path: Bool?,
        _ names: [String], _ version: String?, _ start: UInt64
    ) -> ProbeDialRecord {
        ProbeDialRecord(
            target: target.text, requiredInterface: interface.name, outcome: outcome, remoteEndpointMatched: endpoint,
            interfaceMatched: path, pathInterfaces: names, tlsVersion: version,
            elapsedNanoseconds: ProofMonotonicClock.nowNanoseconds() - start)
    }
}
