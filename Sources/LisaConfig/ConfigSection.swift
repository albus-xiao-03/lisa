// One configuration object being decoded: typed settings with defaults, missing settings and unknown keys.

import LisaSecrets
import LisaTime

/// Reads one configuration object. Every key a decoder asks for becomes a known setting; `finish()` reports the
/// others as unknown, so typos are caught. `null` means "not set" everywhere.
final class ConfigSection {
    let path: ConfigurationPath
    /// Where the object starts; issues about missing settings point here.
    let position: SourcePosition
    let context: DecodingContext
    /// How messages name this object, such as "a mailbox source"; `nil` uses its path.
    var subject: String?
    private let object: JSON5Object
    private var knownKeys: [String] = []
    private var checksUnknownKeys = true

    init(_ object: JSON5Object, path: ConfigurationPath, position: SourcePosition, context: DecodingContext) {
        self.object = object
        self.path = path
        self.position = position
        self.context = context
    }

    /// The value of `key`, or `nil` when it is absent or `null`. Marks `key` as a known setting.
    func value(_ key: String) -> ConfigValue? {
        if !knownKeys.contains(key) {
            knownKeys.append(key)
        }
        guard let member = object.member(key) else { return nil }
        let childPath = path.appending(key: key)
        context.record(childPath, at: member.value.position)
        if case .null = member.value.value { return nil }
        return ConfigValue(node: member.value, path: childPath, context: context)
    }

    /// Whether `key` is set to something other than `null`. Marks `key` as a known setting.
    func isSet(_ key: String) -> Bool {
        value(key) != nil
    }

    /// Reports a problem with the setting `key` of this object.
    func report(_ key: String, _ problem: String, fix: String? = nil) {
        let childPath = path.appending(key: key)
        context.report(childPath, at: context.position(of: childPath) ?? position, problem, fix: fix)
    }

    func reportMissing(_ key: String, fix: String) {
        report(key, "is required", fix: fix)
    }

    /// Stops `finish()` from reporting unknown keys, when the object's kind could not be determined.
    func skipUnknownKeyCheck() {
        checksUnknownKeys = false
    }

    /// Reports every key that no decoder asked for. Call once, after every setting has been read.
    func finish() {
        guard checksUnknownKeys else { return }
        for member in object.members where !knownKeys.contains(member.key) {
            UnknownSettingAdvice.report(
                member, path: path.appending(key: member.key), owner: subject ?? Self.describe(path),
                knownKeys: knownKeys, context: context)
        }
    }

    private static func describe(_ path: ConfigurationPath) -> String {
        path.isRoot ? "a top-level setting" : "a setting of \(path)"
    }
}

// MARK: - Typed settings

extension ConfigSection {
    func bool(_ key: String, default fallback: Bool) -> Bool {
        value(key)?.bool() ?? fallback
    }

    func integer(_ key: String, default fallback: Int, in range: ClosedRange<Int>) -> Int {
        value(key)?.integer(in: range) ?? fallback
    }

    func number(_ key: String, default fallback: Double, in range: ClosedRange<Double>) -> Double {
        value(key)?.number(in: range) ?? fallback
    }

    func text(_ key: String, maxLength: Int = 256) -> String? {
        value(key)?.text(maxLength: maxLength)
    }

    func requiredText(_ key: String, maxLength: Int = 256, fix: String) -> String? {
        guard let value = value(key) else {
            reportMissing(key, fix: fix)
            return nil
        }
        return value.text(maxLength: maxLength)
    }

    func validated<T>(_ key: String, maxLength: Int = 256, _ rule: (String) -> Result<T, ValueRefusal>) -> T? {
        value(key)?.validated(maxLength: maxLength, rule)
    }

    func requiredValidated<T>(
        _ key: String, maxLength: Int = 256, fix: String, _ rule: (String) -> Result<T, ValueRefusal>
    ) -> T? {
        guard let value = value(key) else {
            reportMissing(key, fix: fix)
            return nil
        }
        return value.validated(maxLength: maxLength, rule)
    }

    func choice<T: RawRepresentable>(_ key: String, default fallback: T, options: [T]) -> T where T.RawValue == String {
        value(key)?.choice(of: options) ?? fallback
    }

    func optionalChoice<T: RawRepresentable>(_ key: String, options: [T]) -> T? where T.RawValue == String {
        value(key)?.choice(of: options)
    }

    func requiredChoice<T: RawRepresentable>(_ key: String, options: [T]) -> T? where T.RawValue == String {
        guard let value = value(key) else {
            reportMissing(key, fix: "one of " + options.map(\.rawValue).joined(separator: ", "))
            return nil
        }
        return value.choice(of: options)
    }

    func timeZone(_ key: String) -> TimeZoneID? {
        value(key)?.timeZone()
    }

    func time(_ key: String, default fallback: LocalTime) -> LocalTime {
        value(key)?.localTime() ?? fallback
    }

    func optionalTime(_ key: String) -> LocalTime? {
        value(key)?.localTime()
    }

    func requiredTime(_ key: String, fix: String) -> LocalTime? {
        guard let value = value(key) else {
            reportMissing(key, fix: fix)
            return nil
        }
        return value.localTime()
    }

    func secret(_ key: String) -> SecretReference? {
        value(key)?.secretReference()
    }

    func requiredSecret(_ key: String, fix: String) -> SecretReference? {
        guard let value = value(key) else {
            reportMissing(key, fix: fix)
            return nil
        }
        return value.secretReference()
    }

    func section(_ key: String) -> ConfigSection? {
        value(key)?.section()
    }

    func list(_ key: String, maxCount: Int) -> [ConfigValue]? {
        value(key)?.elements(maxCount: maxCount)
    }

    /// A list of distinct texts, in the order written. Invalid entries are reported and the default is kept.
    func textList(_ key: String, default fallback: [String], maxCount: Int, maxLength: Int = 200) -> [String] {
        guard let elements = list(key, maxCount: maxCount) else { return fallback }
        let texts = elements.map { $0.text(maxLength: maxLength) }
        guard texts.allSatisfy({ $0 != nil }) else { return fallback }
        var seen: Set<String> = []
        return texts.compactMap { $0 }.filter { seen.insert($0).inserted }
    }

    /// A list of whole numbers within `range`. Invalid entries are reported and the default is kept.
    func integerList(_ key: String, default fallback: [Int], maxCount: Int, in range: ClosedRange<Int>) -> [Int] {
        guard let elements = list(key, maxCount: maxCount) else { return fallback }
        let numbers = elements.map { $0.integer(in: range) }
        guard numbers.allSatisfy({ $0 != nil }) else { return fallback }
        return numbers.compactMap { $0 }
    }
}
