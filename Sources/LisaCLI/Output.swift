// Terminal output: readable text or JSON for scripts, and errors on standard error.

import Foundation
import LisaAPIContract

/// Writes command results.
struct Output {
    let json: Bool

    /// Prints a value as sorted JSON (machine-readable) or through `text` (human-readable).
    func emit<T: Encodable>(_ value: T, text: (T) -> String) throws {
        if json {
            let encoder = APIJSON.encoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            print(String(decoding: try encoder.encode(value), as: UTF8.self))
        } else {
            print(text(value))
        }
    }

    static func error(_ message: String) {
        FileHandle.standardError.write(Data("lisa: \(message)\n".utf8))
    }
}
