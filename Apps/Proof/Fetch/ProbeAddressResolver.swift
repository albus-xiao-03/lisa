// PROOF ONLY — Apps/Proof never ships. E-1 fetch probe (plan §8.9.3 check 1 "Path-scoped resolution", §1.5 dns_sd
// row): `DNSServiceGetAddrInfo` on the request's interface index, IPv4 only (A records), off the main thread, each
// answer with its TTL and interface index. AAAA is never requested. Negative answers arrive through
// kDNSServiceFlagsReturnIntermediates, so an A-less (for example AAAA-only) name ends as `noSuchRecord`.

import Foundation
import dnssd

struct ProbeAddressAnswer: Codable, Sendable, Equatable {
    let address: String
    let bytes: [UInt8]
    let ttl: UInt32
    let interfaceIndex: UInt32
}

enum ProbeResolution: Codable, Sendable, Equatable {
    case answers([ProbeAddressAnswer])
    case noSuchRecord
    case failed(Int32)
    case timedOut
}

enum ProbeAddressResolver {
    static func resolveA(host: String, interfaceIndex: UInt32, timeoutSeconds: Double = 5) async -> ProbeResolution {
        await withCheckedContinuation { continuation in
            AddressQuery(continuation: continuation).start(
                host: host, interfaceIndex: interfaceIndex, timeoutSeconds: timeoutSeconds)
        }
    }
}

/// One query; every callback, the timeout and the teardown run on its serial queue.
private final class AddressQuery: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.example.lisa.proof.dns-a")
    private var reference: DNSServiceRef?
    private var answers: [ProbeAddressAnswer] = []
    private var continuation: CheckedContinuation<ProbeResolution, Never>?

    init(continuation: CheckedContinuation<ProbeResolution, Never>) {
        self.continuation = continuation
    }

    func start(host: String, interfaceIndex: UInt32, timeoutSeconds: Double) {
        queue.async { [self] in
            let context = Unmanaged.passRetained(self).toOpaque()
            var created: DNSServiceRef?
            let status = DNSServiceGetAddrInfo(
                &created, DNSServiceFlags(kDNSServiceFlagsReturnIntermediates), interfaceIndex,
                DNSServiceProtocol(kDNSServiceProtocol_IPv4), host,
                { _, flags, interfaceIndex, errorCode, _, address, ttl, context in
                    guard let context else { return }
                    let query = Unmanaged<AddressQuery>.fromOpaque(context).takeUnretainedValue()
                    query.handle(
                        flags: flags, interfaceIndex: interfaceIndex, errorCode: errorCode, address: address, ttl: ttl)
                }, context)
            guard status == DNSServiceErrorType(kDNSServiceErr_NoError), let created else {
                Unmanaged<AddressQuery>.fromOpaque(context).release()
                finish(.failed(status), releasing: false)
                return
            }
            reference = created
            DNSServiceSetDispatchQueue(created, queue)
            queue.asyncAfter(deadline: .now() + timeoutSeconds) { [self] in
                finish(answers.isEmpty ? .timedOut : .answers(answers), releasing: true)
            }
        }
    }

    private func handle(
        flags: DNSServiceFlags, interfaceIndex: UInt32, errorCode: DNSServiceErrorType,
        address: UnsafePointer<sockaddr>?, ttl: UInt32
    ) {
        if errorCode == DNSServiceErrorType(kDNSServiceErr_NoSuchRecord) {
            finish(answers.isEmpty ? .noSuchRecord : .answers(answers), releasing: true)
            return
        }
        guard errorCode == DNSServiceErrorType(kDNSServiceErr_NoError) else {
            finish(.failed(errorCode), releasing: true)
            return
        }
        if flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0, let address,
            address.pointee.sa_family == sa_family_t(AF_INET)
        {
            let bytes = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                withUnsafeBytes(of: pointer.pointee.sin_addr.s_addr) { Array($0) }
            }
            answers.append(
                ProbeAddressAnswer(
                    address: bytes.map(String.init).joined(separator: "."), bytes: bytes, ttl: ttl,
                    interfaceIndex: interfaceIndex))
        }
        if flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) == 0, !answers.isEmpty {
            finish(.answers(answers), releasing: true)
        }
    }

    private func finish(_ result: ProbeResolution, releasing: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        if let reference {
            DNSServiceRefDeallocate(reference)
            self.reference = nil
        }
        if releasing { Unmanaged.passUnretained(self).release() }
        continuation.resume(returning: result)
    }
}
