// The JSON coding configuration for persisted records: millisecond instants and sorted keys.

import Foundation
import LisaTime

/// JSON coders for persisted domain records. Instants are whole milliseconds since 1970 so they round-trip exactly.
public enum DomainJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.millisecondsSince1970)
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(millisecondsSince1970: try container.decode(Int64.self))
        }
        return decoder
    }
}
