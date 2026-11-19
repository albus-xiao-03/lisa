// Formats of the owner's contact points: E.164 phone numbers and plausible email addresses.

/// Checks phone numbers and email addresses. Configuration takes them only as written; nothing is inferred.
enum ContactFormats {
    /// E.164: `+` and 7 to 15 digits, the first not zero, with no spaces or punctuation, such as `+15555550100`.
    static func isE164(_ text: String) -> Bool {
        guard text.hasPrefix("+") else { return false }
        let digits = text.utf8.dropFirst()
        return (7...15).contains(digits.count) && digits.allSatisfy { (0x30...0x39).contains($0) }
            && digits.first != 0x30
    }

    /// A plausible `local@domain` address: an unquoted ASCII local part (at most 64 bytes) and a host name with at
    /// least one dot (at most 254 bytes in all). Quoted local parts, address literals and non-ASCII addresses are
    /// refused.
    static func isPlausibleEmailAddress(_ text: String) -> Bool {
        guard text.utf8.count <= 254 else { return false }
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0]
        let domain = String(parts[1])
        guard !local.isEmpty, local.utf8.count <= 64, local.first != ".", local.last != ".", !local.contains("..")
        else { return false }
        guard local.unicodeScalars.allSatisfy(isLocalPartScalar) else { return false }
        guard domain.contains("."), NetworkAddressRules.isDNSName(domain) else { return false }
        let topLevel = domain.split(separator: ".").last ?? ""
        return !topLevel.allSatisfy(\.isNumber)
    }

    private static func isLocalPartScalar(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.isASCII else { return false }
        if scalar.properties.isAlphabetic || (0x30...0x39).contains(scalar.value) { return true }
        return "!#$%&'*+-/=?^_`{|}~.".unicodeScalars.contains(scalar)
    }
}
