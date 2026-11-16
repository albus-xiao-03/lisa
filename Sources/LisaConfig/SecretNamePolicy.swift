// Recognizes setting and query-parameter names that suggest a credential (password, token, key, secret).

/// Decides whether a name suggests that its value is a credential, so a literal value under it can be refused.
enum SecretNamePolicy {
    /// Fragments that mark a credential wherever they appear in a name, such as `smtpPassword` or `access_token`.
    private static let fragments = [
        "password", "passwd", "passphrase", "secret", "token", "credential", "apikey", "privatekey", "accesskey",
    ]
    /// Whole words that mark a credential, such as the `key` in `api_key`, but not the `key` in `monkey`.
    private static let words: Set<String> = [
        "key", "keys", "pwd", "pass", "auth", "authorization", "sig", "signature", "session", "sessionid", "jwt",
        "bearer",
    ]
    /// Words that, right after `key`, name an identifier rather than a secret, as in `keyID`.
    private static let identifierWords: Set<String> = ["id", "ids", "identifier"]

    /// Whether `name`, a setting or query-parameter name, suggests a credential.
    static func suggestsSecret(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if fragments.contains(where: { lowered.contains($0) }) { return true }
        let parts = splitWords(name)
        for (index, word) in parts.enumerated() where words.contains(word) {
            if word == "key", index + 1 < parts.count, identifierWords.contains(parts[index + 1]) {
                continue
            }
            return true
        }
        return false
    }

    /// Splits camelCase, snake_case, kebab-case and dotted names into lowercase words: `APIKeyID` → api, key, id.
    static func splitWords(_ name: String) -> [String] {
        let characters = Array(name)
        var result: [String] = []
        var word = ""
        for (index, character) in characters.enumerated() {
            guard character.isLetter || character.isNumber else {
                if !word.isEmpty { result.append(word.lowercased()) }
                word = ""
                continue
            }
            if character.isUppercase, !word.isEmpty {
                let previous = characters[index - 1]
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                if previous.isLowercase || previous.isNumber || (previous.isUppercase && next?.isLowercase == true) {
                    result.append(word.lowercased())
                    word = ""
                }
            }
            word.append(character)
        }
        if !word.isEmpty { result.append(word.lowercased()) }
        return result
    }
}
