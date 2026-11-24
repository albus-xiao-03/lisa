// PROOF ONLY — Apps/Proof never ships. IANA names for the raw TLS version and cipher-suite values the proof
// records, so a result reads without a lookup table. Unknown values print as hexadecimal.

enum ProofCipherSuiteNames {
    static let suites: [UInt16: String] = [
        0xCCAC: "TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256",  // RFC 7905
        0xD001: "TLS_ECDHE_PSK_WITH_AES_128_GCM_SHA256",  // RFC 8442
        0xD002: "TLS_ECDHE_PSK_WITH_AES_256_GCM_SHA384",  // RFC 8442
        0xC037: "TLS_ECDHE_PSK_WITH_AES_128_CBC_SHA256",  // RFC 5489
        0xC038: "TLS_ECDHE_PSK_WITH_AES_256_CBC_SHA384",  // RFC 5489
        0xC035: "TLS_ECDHE_PSK_WITH_AES_128_CBC_SHA",  // RFC 5489
        0xC036: "TLS_ECDHE_PSK_WITH_AES_256_CBC_SHA",  // RFC 5489
        0x00A8: "TLS_PSK_WITH_AES_128_GCM_SHA256",  // RFC 5487, no forward secrecy
        0x00A9: "TLS_PSK_WITH_AES_256_GCM_SHA384",  // RFC 5487, no forward secrecy
        0xCCAB: "TLS_PSK_WITH_CHACHA20_POLY1305_SHA256",  // RFC 7905, no forward secrecy
        0x008C: "TLS_PSK_WITH_AES_128_CBC_SHA",  // RFC 4279, no forward secrecy
        0x008D: "TLS_PSK_WITH_AES_256_CBC_SHA",  // RFC 4279, no forward secrecy
        0x1301: "TLS_AES_128_GCM_SHA256",  // TLS 1.3
        0x1302: "TLS_AES_256_GCM_SHA384",  // TLS 1.3
        0x1303: "TLS_CHACHA20_POLY1305_SHA256",  // TLS 1.3
    ]

    static let versions: [UInt16: String] = [0x0303: "TLS 1.2", 0x0304: "TLS 1.3"]

    static func suite(_ raw: UInt16) -> String {
        suites[raw] ?? "0x" + String(raw, radix: 16)
    }

    static func version(_ raw: UInt16) -> String {
        versions[raw] ?? "0x" + String(raw, radix: 16)
    }
}
