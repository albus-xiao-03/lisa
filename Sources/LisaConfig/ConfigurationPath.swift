// Setting paths such as `sources[2].passwordSecret`, as shown in configuration issues.

/// The path of a setting, such as `delivery.modes.email` or `sources[2].passwordSecret`.
struct ConfigurationPath: Hashable, Sendable, CustomStringConvertible {
    private enum Component: Hashable, Sendable {
        case key(String)
        case index(Int)
    }

    private let components: [Component]

    /// The top level of the document.
    static let root = ConfigurationPath(components: [])

    private init(components: [Component]) {
        self.components = components
    }

    /// A path of plain keys, such as `ConfigurationPath("delivery", "modes", "email")`.
    init(_ keys: String...) {
        components = keys.map { .key($0) }
    }

    func appending(key: String) -> ConfigurationPath {
        ConfigurationPath(components: components + [.key(key)])
    }

    func appending(index: Int) -> ConfigurationPath {
        ConfigurationPath(components: components + [.index(index)])
    }

    /// The enclosing path, or `nil` for the top level.
    var parent: ConfigurationPath? {
        components.isEmpty ? nil : ConfigurationPath(components: Array(components.dropLast()))
    }

    var isRoot: Bool { components.isEmpty }

    /// Whether `other` is this path or lies inside it.
    func contains(_ other: ConfigurationPath) -> Bool {
        other.components.starts(with: components)
    }

    var description: String {
        guard !components.isEmpty else { return "(top level)" }
        var text = ""
        for component in components {
            switch component {
            case .key(let key) where Self.isPlainKey(key):
                text += text.isEmpty ? key : ".\(key)"
            case .key(let key):
                text += "[\(Self.quoted(key))]"
            case .index(let index):
                text += "[\(index)]"
            }
        }
        return text
    }

    /// Keys written as identifiers (ASCII letters, digits, `_` and `$`) appear after a dot; others are quoted.
    private static func isPlainKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first, first.isASCII, !(0x30...0x39).contains(first.value) else {
            return false
        }
        return key.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII
                && (scalar.properties.isAlphabetic || (0x30...0x39).contains(scalar.value) || scalar == "_"
                    || scalar == "$")
        }
    }

    /// A quoted, escaped key, shortened to 64 characters, so an odd key cannot disturb the message.
    private static func quoted(_ key: String) -> String {
        var text = ""
        for (offset, scalar) in key.unicodeScalars.enumerated() {
            guard offset < 64 else {
                text += "…"
                break
            }
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            default:
                if scalar.properties.generalCategory == .control {
                    text += "\\u{\(String(scalar.value, radix: 16))}"
                } else {
                    text.unicodeScalars.append(scalar)
                }
            }
        }
        return "\"\(text)\""
    }
}
