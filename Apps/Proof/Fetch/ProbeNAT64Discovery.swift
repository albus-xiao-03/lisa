// PROOF ONLY — Apps/Proof never ships. E-1 probe (plan §8.9.3 "Path-scoped NAT64 evidence", RFC 7050): the AAAA
// query for `ipv4only.arpa` through `DNSServiceQueryRecord` on the request's interface index, with TTLs; synthesized
// answers give the prefixes. Used only on an IPv6-only path. Evidence is never carried to another request.

import Foundation
import dnssd

struct ProbeNAT64Evidence: Codable, Sendable, Equatable {
    /// "synthesized", "no-synthesis", "failed <code>" or "timed-out".
    let outcome: String
    let answers: [String]
    let prefixes: [ProbeNAT64Prefix]
    let minimumTTL: UInt32?
    let interfaceIndices: [UInt32]
}

enum ProbeNAT64Discovery {
    static let name = "ipv4only.arpa"

    static func discover(interfaceIndex: UInt32, timeoutSeconds: Double = 5) async -> ProbeNAT64Evidence {
        await withCheckedContinuation { continuation in
            RecordQuery(continuation: continuation).start(
                interfaceIndex: interfaceIndex, timeoutSeconds: timeoutSeconds)
        }
    }
}

private final class RecordQuery: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.example.lisa.proof.dns-aaaa")
    private var reference: DNSServiceRef?
    private var answers: [[UInt8]] = []
    private var ttls: [UInt32] = []
    private var indices: [UInt32] = []
    private var continuation: CheckedContinuation<ProbeNAT64Evidence, Never>?

    init(continuation: CheckedContinuation<ProbeNAT64Evidence, Never>) {
        self.continuation = continuation
    }

    func start(interfaceIndex: UInt32, timeoutSeconds: Double) {
        queue.async { [self] in
            let context = Unmanaged.passRetained(self).toOpaque()
            var created: DNSServiceRef?
            let status = DNSServiceQueryRecord(
                &created, DNSServiceFlags(kDNSServiceFlagsReturnIntermediates), interfaceIndex,
                ProbeNAT64Discovery.name, UInt16(kDNSServiceType_AAAA), UInt16(kDNSServiceClass_IN),
                { _, flags, interfaceIndex, errorCode, _, _, _, length, data, ttl, context in
                    guard let context else { return }
                    let query = Unmanaged<RecordQuery>.fromOpaque(context).takeUnretainedValue()
                    let rdata = data.map { Array(UnsafeRawBufferPointer(start: $0, count: Int(length))) } ?? []
                    query.handle(
                        flags: flags, interfaceIndex: interfaceIndex, errorCode: errorCode, rdata: rdata, ttl: ttl)
                }, context)
            guard status == DNSServiceErrorType(kDNSServiceErr_NoError), let created else {
                Unmanaged<RecordQuery>.fromOpaque(context).release()
                finish("failed \(status)", releasing: false)
                return
            }
            reference = created
            DNSServiceSetDispatchQueue(created, queue)
            queue.asyncAfter(deadline: .now() + timeoutSeconds) { [self] in
                finish(answers.isEmpty ? "timed-out" : "synthesized", releasing: true)
            }
        }
    }

    private func handle(
        flags: DNSServiceFlags, interfaceIndex: UInt32, errorCode: DNSServiceErrorType, rdata: [UInt8], ttl: UInt32
    ) {
        if errorCode == DNSServiceErrorType(kDNSServiceErr_NoSuchRecord) {
            finish(answers.isEmpty ? "no-synthesis" : "synthesized", releasing: true)
            return
        }
        guard errorCode == DNSServiceErrorType(kDNSServiceErr_NoError) else {
            finish("failed \(errorCode)", releasing: true)
            return
        }
        if flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0, rdata.count == 16 {
            answers.append(rdata)
            ttls.append(ttl)
            indices.append(interfaceIndex)
        }
        if flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) == 0, !answers.isEmpty {
            finish("synthesized", releasing: true)
        }
    }

    private func finish(_ outcome: String, releasing: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        if let reference {
            DNSServiceRefDeallocate(reference)
            self.reference = nil
        }
        if releasing { Unmanaged.passUnretained(self).release() }
        continuation.resume(
            returning: ProbeNAT64Evidence(
                outcome: outcome, answers: answers.map { LowercaseHexText.encode($0) },
                prefixes: ProbeNAT64Prefix.discover(fromSynthesized: answers), minimumTTL: ttls.min(),
                interfaceIndices: indices))
    }
}
