// PROOF ONLY — Apps/Proof never ships. The TLS 1.2 PSK cipher suites Design A offers, by IANA raw value: Security
// defines no `tls_ciphersuite_t` constant for any PSK suite (plan §1.5, Security reference row), so each is built
// with `tls_ciphersuite_t(rawValue:)`. Only ECDHE-PSK suites give forward secrecy, and Design A's proof passes only
// if one of them is negotiated on every cell (plan §8.7 Limits, §10.5 N-1). The ECDHE-PSK list excludes the NULL
// (0xC039–0xC03B), RC4 (0xC033) and 3DES (0xC034) variants. AEAD suites come first.

enum DesignAPSKSuites {
    enum Policy: String, Codable, Sendable, CaseIterable {
        /// The proof configuration: only forward-secret ECDHE-PSK suites are offered.
        case forwardSecretOnly = "forward-secret-only"
        /// A labeled diagnostic, never a pass: plain PSK suites only (0x00A8 is the suite of Apple's TicTacToe
        /// TLS-PSK sample), to tell "PSK does not work" apart from "no ECDHE-PSK suite is supported".
        case diagnosticPlainPSK = "diagnostic-plain-psk"
    }

    static let forwardSecret: [UInt16] = [0xCCAC, 0xD001, 0xD002, 0xC037, 0xC038, 0xC035, 0xC036]
    static let diagnosticPlainPSK: [UInt16] = [0x00A8, 0x00A9, 0xCCAB, 0x008C, 0x008D]

    static func offered(_ policy: Policy) -> [UInt16] {
        policy == .forwardSecretOnly ? forwardSecret : diagnosticPlainPSK
    }

    static func isForwardSecret(_ raw: UInt16) -> Bool {
        forwardSecret.contains(raw)
    }
}
