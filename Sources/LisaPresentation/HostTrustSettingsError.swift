// Why the TLS trust the owner supplied for a Lisa host cannot be used. Messages never repeat what the owner supplied.

import Foundation

/// Why a certificate file or a pin cannot be used to trust a Lisa host.
public enum HostTrustSettingsError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The file holds no certificate.
    case noCertificate
    /// A PEM certificate block is not valid base64, or is not closed.
    case malformedPEM
    /// The file holds more certificates than are accepted.
    case tooManyCertificates(limit: Int)
    /// A certificate is larger than accepted.
    case certificateTooLarge(limit: Int)
    /// The platform could not read a certificate.
    case unreadableCertificate
    /// The pin is not a SHA-256 digest.
    case invalidPin

    public var description: String {
        switch self {
        case .noCertificate:
            "the file holds no certificate; choose your Lisa host's certificate, or the certificate authority that "
                + "issued it, as a PEM or DER file"
        case .malformedPEM: "a certificate in the file is damaged: its PEM block is not valid base64 or not closed"
        case .tooManyCertificates(let limit): "the file holds more than \(limit) certificates"
        case .certificateTooLarge(let limit): "a certificate in the file is larger than \(limit) bytes"
        case .unreadableCertificate: "a certificate in the file could not be read"
        case .invalidPin:
            "the pin must be the SHA-256 digest of the host's certificate: 64 hexadecimal digits, which may be "
                + "separated by colons, or 44 base64 characters"
        }
    }
}
