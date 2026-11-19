// Advice for keys Lisa does not know: likely typos, and secrets written inline instead of referenced.

import LisaSecrets

/// Reports unknown settings with a correction, and refuses literal secrets under names that suggest one.
enum UnknownSettingAdvice {
    /// The most known settings listed when no close match exists.
    private static let maxListedKeys = 20

    /// Reports `member`, an unknown key of an object whose known settings are `knownKeys`. The value is never quoted.
    static func report(
        _ member: JSON5Member, path: ConfigurationPath, owner: String, knownKeys: [String], context: DecodingContext
    ) {
        if SecretNamePolicy.suggestsSecret(member.key) {
            let referenceKey = secretReferenceKey(for: member.key, among: knownKeys)
            if case .string(let text) = member.value.value, SecretReference(text) != nil {
                let fix =
                    referenceKey.map { "did you mean \($0)?" }
                    ?? "secret references belong in the settings whose names end in Secret"
                context.report(path, at: member.keyPosition, "is not \(owner)", fix: fix)
            } else {
                context.report(
                    path, at: member.keyPosition,
                    "looks like a secret written into the configuration; Lisa never reads secret values from this file",
                    fix: "move the value into an environment variable, a protected file (mode 0600) or the Keychain, "
                        + "and set \(referenceKey ?? "the matching …Secret setting") to its reference, such as env:NAME"
                )
            }
            return
        }
        let fix: String
        if let suggestion = closestKey(to: member.key, among: knownKeys) {
            fix = "did you mean \(suggestion)?"
        } else if knownKeys.isEmpty {
            fix = "remove it"
        } else {
            let listed = knownKeys.prefix(maxListedKeys).joined(separator: ", ")
            fix = "remove it, or use one of: " + listed + (knownKeys.count > maxListedKeys ? ", …" : "")
        }
        context.report(path, at: member.keyPosition, "is not \(owner)", fix: fix)
    }

    /// The known setting `key` most likely meant: a case-only difference, or a small edit distance.
    static func closestKey(to key: String, among candidates: [String]) -> String? {
        guard key.count <= 64 else { return nil }
        let allowed = key.count <= 4 ? 1 : (key.count <= 10 ? 2 : 3)
        var best: (key: String, distance: Int)?
        for candidate in candidates {
            let distance = editDistance(key, candidate)
            if distance <= allowed, distance < (best?.distance ?? Int.max) {
                best = (candidate, distance)
            }
        }
        return best?.key
    }

    /// The `…Secret` setting an inline secret belongs in: `password` → `passwordSecret`.
    private static func secretReferenceKey(for key: String, among knownKeys: [String]) -> String? {
        let candidates = knownKeys.filter { $0.hasSuffix("Secret") }
        if let prefixed = candidates.first(where: { $0.lowercased().hasPrefix(key.lowercased()) }) {
            return prefixed
        }
        if let close = closestKey(to: key, among: candidates) {
            return close
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// The optimal-string-alignment distance between two names, ignoring case: an adjacent swap counts as one edit.
    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let source = Array(lhs.lowercased().unicodeScalars)
        let target = Array(rhs.lowercased().unicodeScalars)
        guard !source.isEmpty else { return target.count }
        guard !target.isEmpty else { return source.count }
        var beforePrevious = [Int](repeating: 0, count: target.count + 1)
        var previous = Array(0...target.count)
        var current = [Int](repeating: 0, count: target.count + 1)
        for row in 1...source.count {
            current[0] = row
            for column in 1...target.count {
                let cost = source[row - 1] == target[column - 1] ? 0 : 1
                current[column] = min(previous[column] + 1, current[column - 1] + 1, previous[column - 1] + cost)
                if row > 1, column > 1, source[row - 1] == target[column - 2], source[row - 2] == target[column - 1] {
                    current[column] = min(current[column], beforePrevious[column - 2] + 1)
                }
            }
            (beforePrevious, previous, current) = (previous, current, beforePrevious)
        }
        return previous[target.count]
    }
}
