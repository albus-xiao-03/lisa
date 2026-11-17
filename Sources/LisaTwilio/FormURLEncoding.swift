// application/x-www-form-urlencoded bodies, the request encoding Twilio's Calls resource documents.

import Foundation

/// The WHATWG URL Standard's application/x-www-form-urlencoded serializer: UTF-8 bytes, with `*-._` and ASCII letters
/// and digits kept, space as `+`, and every other byte percent-encoded. No input byte can end a field early.
enum FormURLEncoding {
    static func body(_ fields: [(name: String, value: String)]) -> Data {
        Data(fields.map { "\(component($0.name))=\(component($0.value))" }.joined(separator: "&").utf8)
    }

    static func component(_ text: String) -> String {
        let hex = Array("0123456789ABCDEF".utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.utf8.count)
        for byte in text.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2A, 0x2D, 0x2E, 0x5F:
                bytes.append(byte)
            case 0x20:
                bytes.append(0x2B)
            default:
                bytes.append(contentsOf: [0x25, hex[Int(byte >> 4)], hex[Int(byte & 0x0F)]])
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
