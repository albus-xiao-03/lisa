// Test-only controlled substitute (plan §10): a synthetic APNs provider-signing key, a P-256 private key in PKCS#8 PEM
// form like Apple's `.p8` keys, generated at run time with the `openssl` CLI for the test that uses it. Nothing is
// hardcoded, written to disk or sent anywhere. Used by the live-push suites (L25, L29, L31, L32) and later APNs suites.

import Foundation

/// Synthetic signing keys. Every call makes a new key; none is an Apple key.
enum SyntheticSigningKey {
    /// Why no key was generated.
    struct GenerationFailed: Error, CustomStringConvertible {
        let description: String
    }

    /// The PEM label of a PKCS#8 private key.
    static let pemHeader = "-----BEGIN PRIVATE KEY-----"

    /// A new P-256 private key as PKCS#8 PEM, from `openssl genpkey`. The key is read from the tool's standard output,
    /// so it never touches the file system. The tool runs on its own thread, never on the test's cooperative threads.
    static func generate() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let thread = Thread { continuation.resume(with: Result { try blockingGenerate() }) }
            thread.start()
        }
    }

    private static func blockingGenerate() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw GenerationFailed(description: "the openssl CLI could not be started: \(error)")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let pem = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0, pem.hasPrefix(pemHeader) else {
            throw GenerationFailed(
                description: "openssl genpkey exited with status \(process.terminationStatus) without a PKCS#8 key")
        }
        return pem
    }
}
