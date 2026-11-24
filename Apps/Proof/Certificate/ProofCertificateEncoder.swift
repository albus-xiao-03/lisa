// PROOF ONLY — compiled into Apps/Proof and into the temporary Linux check; never linked into a product.
// Plan R2 §8.7, "Certificates: proof-only at X1": a fixed-template DER encoder for Design B's self-signed X.509 v3
// certificate over a P-256 key. Random positive 16-byte serial, one-year validity, keyUsage digitalSignature
// (critical), extKeyUsage serverAuth and clientAuth, ecdsa-with-SHA256, no CA, chain or host name. The signing step
// goes through `ProofCertificateSigning`: the app passes its Secure Enclave key, the Linux check a software key, and
// openssl checks the Linux output. Production issuance (X4, P-08) would use swift-certificates instead.
//
// Foundation only, so the identical file builds on Linux and on Apple platforms.

import Foundation

/// The signing step of the proof certificate: a P-256 key that signs with ECDSA over SHA-256.
protocol ProofCertificateSigning {
    /// The 65-byte uncompressed public point, `0x04 ‖ X ‖ Y`.
    var publicKeyX963: [UInt8] { get }
    /// The DER `Ecdsa-Sig-Value` (`SEQUENCE { r INTEGER, s INTEGER }`) of ECDSA-with-SHA256 over `message`.
    func ecdsaSHA256SignatureDER(over message: [UInt8]) throws -> [UInt8]
}

/// Why the proof certificate was not encoded.
enum ProofCertificateError: Error, Equatable {
    case publicKeyNotUncompressedP256
    case serialNotPositive16Bytes
    case validityOutOfRange
    case signatureNotDER
}

/// A proof-only certificate and the parts the checks look at.
struct ProofCertificate: Equatable {
    let der: [UInt8]
    let tbsDER: [UInt8]
    let signatureDER: [UInt8]
    let serial: [UInt8]
    /// The 91-byte canonical SubjectPublicKeyInfo, the form LisaCrypto's `P256Verifier` accepts.
    let spkiDER: [UInt8]
    let notBefore: Date
    let notAfter: Date
}

/// The fixed template. Only the serial, the two times, the public point and the signature vary.
enum ProofCertificateEncoder {
    static let validitySeconds: Int64 = 365 * 86_400
    static let serialLength = 16
    /// Issuer and subject common name: fixed, and identifying nothing; peers are recognized by key pin only.
    static let commonName = "LISA PROOF ONLY"

    /// AlgorithmIdentifier ecdsa-with-SHA256 (1.2.840.10045.4.3.2), parameters absent (RFC 5758 §3.2).
    static let ecdsaWithSHA256: [UInt8] = [0x30, 0x0A, 0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]
    /// SubjectPublicKeyInfo prefix: id-ecPublicKey, prime256v1, BIT STRING of 66 bytes with no unused bits.
    static let p256SPKIPrefix: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
        0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ]
    /// `[0] EXPLICIT INTEGER 2`: version 3.
    static let versionV3: [UInt8] = [0xA0, 0x03, 0x02, 0x01, 0x02]
    /// Extension keyUsage (2.5.29.15), critical, digitalSignature only.
    static let keyUsageDigitalSignature: [UInt8] = [
        0x30, 0x0E, 0x06, 0x03, 0x55, 0x1D, 0x0F, 0x01, 0x01, 0xFF, 0x04, 0x04, 0x03, 0x02, 0x07, 0x80,
    ]
    /// Extension extKeyUsage (2.5.29.37), not critical: id-kp-serverAuth, id-kp-clientAuth.
    static let extendedKeyUsageServerAndClient: [UInt8] = [
        0x30, 0x1D, 0x06, 0x03, 0x55, 0x1D, 0x25, 0x04, 0x16, 0x30, 0x14,
        0x06, 0x08, 0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01,
        0x06, 0x08, 0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02,
    ]

    /// Encodes and signs a certificate valid from `notBefore` (whole seconds) for one year.
    /// - Parameter serial: 16 bytes with a first byte in 0x01...0x7F; nil draws a random one.
    static func certificate(
        signer: some ProofCertificateSigning, notBefore: Date, serial: [UInt8]? = nil
    ) throws -> ProofCertificate {
        let point = signer.publicKeyX963
        guard point.count == 65, point[0] == 0x04 else { throw ProofCertificateError.publicKeyNotUncompressedP256 }
        let serial = serial ?? randomSerial()
        guard serial.count == serialLength, (0x01...0x7F).contains(serial[0]) else {
            throw ProofCertificateError.serialNotPositive16Bytes
        }
        let interval = notBefore.timeIntervalSince1970.rounded(.down)
        guard interval >= 0, interval < 8_000_000_000 else { throw ProofCertificateError.validityOutOfRange }
        let start = Int64(interval)
        let end = start + validitySeconds
        let spki = p256SPKIPrefix + point
        let name = distinguishedName()
        let validity = tlv(0x30, try time(start) + time(end))
        let extensions = tlv(0xA3, tlv(0x30, keyUsageDigitalSignature + extendedKeyUsageServerAndClient))
        let tbs = tlv(
            0x30, versionV3 + tlv(0x02, serial) + ecdsaWithSHA256 + name + validity + name + spki + extensions)
        let signature = try signer.ecdsaSHA256SignatureDER(over: tbs)
        guard isECDSASignatureDER(signature) else { throw ProofCertificateError.signatureNotDER }
        let der = tlv(0x30, tbs + ecdsaWithSHA256 + tlv(0x03, [0x00] + signature))
        return ProofCertificate(
            der: der, tbsDER: tbs, signatureDER: signature, serial: serial, spkiDER: spki,
            notBefore: Date(timeIntervalSince1970: TimeInterval(start)),
            notAfter: Date(timeIntervalSince1970: TimeInterval(end)))
    }

    /// 16 random bytes from the system generator, made positive and minimal for a DER INTEGER.
    static func randomSerial() -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        var bytes = (0..<serialLength).map { _ in UInt8.random(in: 0...255, using: &generator) }
        bytes[0] &= 0x7F
        if bytes[0] == 0 { bytes[0] = 0x01 }
        return bytes
    }

    /// `SEQUENCE { SET { SEQUENCE { id-at-commonName, UTF8String } } }`.
    static func distinguishedName() -> [UInt8] {
        let attribute = tlv(0x30, [0x06, 0x03, 0x55, 0x04, 0x03] + tlv(0x0C, Array(commonName.utf8)))
        return tlv(0x30, tlv(0x31, attribute))
    }

    /// UTCTime for 1950–2049 and GeneralizedTime after, as RFC 5280 §4.1.2.5 requires.
    static func time(_ seconds: Int64) throws -> [UInt8] {
        let (year, month, day, hour, minute, second) = civil(seconds)
        let rest = digits(month, 2) + digits(day, 2) + digits(hour, 2) + digits(minute, 2) + digits(second, 2) + "Z"
        if (1950...2049).contains(year) { return tlv(0x17, Array((digits(year % 100, 2) + rest).utf8)) }
        guard (2050...9999).contains(year) else { throw ProofCertificateError.validityOutOfRange }
        return tlv(0x18, Array((digits(year, 4) + rest).utf8))
    }

    /// The proleptic Gregorian UTC date and time of a non-negative Unix time (H. Hinnant's civil_from_days).
    static func civil(_ seconds: Int64) -> (Int, Int, Int, Int, Int, Int) {
        let days = seconds / 86_400
        let secondsOfDay = Int(seconds % 86_400)
        let z = days + 719_468
        let era = z / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (
            Int(year), Int(month), Int(day), secondsOfDay / 3_600, secondsOfDay % 3_600 / 60, secondsOfDay % 60
        )
    }

    static func digits(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }

    /// Whether `bytes` is a DER `SEQUENCE { INTEGER, INTEGER }` of positive minimal integers of at most 33 bytes.
    static func isECDSASignatureDER(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 8, bytes.count <= 72, bytes[0] == 0x30, Int(bytes[1]) == bytes.count - 2 else {
            return false
        }
        var index = 2
        for _ in 0..<2 {
            guard index + 2 <= bytes.count, bytes[index] == 0x02 else { return false }
            let length = Int(bytes[index + 1])
            guard (1...33).contains(length), index + 2 + length <= bytes.count else { return false }
            let first = bytes[index + 2]
            guard first & 0x80 == 0 else { return false }
            if length > 1, first == 0, bytes[index + 3] & 0x80 == 0 { return false }
            index += 2 + length
        }
        return index == bytes.count
    }

    /// One DER tag-length-value with a definite length.
    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + length(content.count) + content
    }

    static func length(_ count: Int) -> [UInt8] {
        guard count >= 0x80 else { return [UInt8(count)] }
        var bytes: [UInt8] = []
        var value = count
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }
}
