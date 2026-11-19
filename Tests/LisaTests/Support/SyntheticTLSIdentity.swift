// Test-only controlled substitute material (plan §10): a synthetic certificate authority and a server certificate for
// 127.0.0.1 and localhost, both P-256 and valid for two days, generated at run time with the openssl CLI inside the
// test's scratch directory and removed with it. No certificate or key is hardcoded. Used by the loopback TLS servers
// of the adapter suites (L18).

import Foundation

/// A server identity signed by its own synthetic authority. A client trusts it only when given ``authorityFile``.
struct SyntheticTLSIdentity: Sendable {
    /// The authority's certificate: the trust store a client is given.
    let authorityFile: URL
    /// The server certificate, PEM.
    let certificateFile: URL
    /// The server's unencrypted private key, PEM, readable only by the current user.
    let keyFile: URL

    /// Generates a new authority and a server certificate signed by it, in `directory` (created if needed).
    static func generate(in directory: URL) async throws -> SyntheticTLSIdentity {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let curve = ["-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes", "-days", "2"]
        try await OpenSSLCommand.run(
            ["req", "-x509"] + curve + [
                "-keyout", "authority.key", "-out", "authority.pem", "-subj", "/CN=Lisa synthetic test authority",
                "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign",
            ], in: directory)
        try await OpenSSLCommand.run(
            ["req", "-x509"] + curve + [
                "-keyout", "server.key", "-out", "server.pem", "-subj", "/CN=localhost", "-CA", "authority.pem",
                "-CAkey", "authority.key", "-addext", "subjectAltName=IP:127.0.0.1,DNS:localhost",
                "-addext", "basicConstraints=critical,CA:FALSE", "-addext", "keyUsage=critical,digitalSignature",
                "-addext", "extendedKeyUsage=serverAuth",
            ], in: directory)
        return SyntheticTLSIdentity(
            authorityFile: directory.appendingPathComponent("authority.pem"),
            certificateFile: directory.appendingPathComponent("server.pem"),
            keyFile: directory.appendingPathComponent("server.key"))
    }
}
