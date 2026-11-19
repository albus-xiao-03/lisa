// Native TLS for a listener (API-01): TLS 1.2 or later with forward-secret AEAD suites only, ALPN http/1.1, no client
// certificates. Encrypted private keys are refused, because BoringSSL would otherwise prompt on standard input.

import NIOSSL

/// A TLS identity for a listener, built once from PEM bytes. Building it is expensive; do it before serving.
public struct APIServerTLS: Sendable {
    let context: NIOSSLContext

    /// The TLS 1.2 suites offered: ECDHE key exchange with AES-GCM or ChaCha20-Poly1305 (TLS 1.3 suites are fixed).
    static let cipherSuites: [NIOTLSCipher] = [
        .TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256, .TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
        .TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384, .TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
        .TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256, .TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256,
    ]

    /// - Parameters:
    ///   - certificateChainPEM: the server certificate followed by any intermediates, in PEM.
    ///   - privateKeyPEM: the unencrypted private key of the server certificate, in PEM.
    public init(certificateChainPEM: [UInt8], privateKeyPEM: [UInt8]) throws(APIServerError) {
        if Self.looksEncrypted(privateKeyPEM) {
            throw .invalidTLSMaterial(
                "the private key is encrypted; provide an unencrypted key protected by file permissions or the "
                    + "secret store")
        }
        let chain: [NIOSSLCertificate]
        do {
            chain = try NIOSSLCertificate.fromPEMBytes(certificateChainPEM)
        } catch {
            throw .invalidTLSMaterial("the certificate chain is not valid PEM")
        }
        guard !chain.isEmpty else { throw .invalidTLSMaterial("the certificate chain contains no certificate") }
        let key: NIOSSLPrivateKey
        do {
            // A passphrase callback that refuses keeps BoringSSL from prompting on standard input.
            key = try NIOSSLPrivateKey(bytes: privateKeyPEM, format: .pem) { (_: ([UInt8]) -> Void) throws in
                throw APIServerError.invalidTLSMaterial("the private key is encrypted")
            }
        } catch {
            throw .invalidTLSMaterial("the private key is not a valid unencrypted PEM key")
        }
        var configuration = TLSConfiguration.makeServerConfiguration(
            certificateChain: chain.map { .certificate($0) }, privateKey: .privateKey(key))
        configuration.minimumTLSVersion = .tlsv12
        configuration.cipherSuiteValues = Self.cipherSuites
        configuration.applicationProtocols = ["http/1.1"]
        configuration.certificateVerification = .none
        configuration.renegotiationSupport = .none
        do {
            context = try NIOSSLContext(configuration: configuration)
        } catch {
            throw .invalidTLSMaterial("the certificate and private key do not form a usable TLS identity")
        }
    }

    /// PEM markers of encrypted keys: PKCS #8 `ENCRYPTED PRIVATE KEY` and legacy `Proc-Type: 4,ENCRYPTED`.
    static func looksEncrypted(_ pem: [UInt8]) -> Bool {
        let text = String(decoding: pem, as: UTF8.self)
        return text.contains("ENCRYPTED PRIVATE KEY") || text.contains("Proc-Type: 4,ENCRYPTED")
    }
}
