// SQLite values for the Core ledger's columns.

import Foundation
import LisaSQLite
import LisaSyncProtocol

enum CoreColumns {
    static func id(_ identifier: Identifier128) -> SQLiteValue { .blob(Data(identifier.bytes)) }
    static func optionalID(_ identifier: Identifier128?) -> SQLiteValue { identifier.map(id) ?? .null }
    static func digest(_ digest: Digest256) -> SQLiteValue { .blob(Data(digest.bytes)) }
    static func bytes(_ bytes: [UInt8]) -> SQLiteValue { .blob(Data(bytes)) }
    static func optionalInteger(_ integer: Int64?) -> SQLiteValue { integer.map { .integer($0) } ?? .null }
    static func optionalText(_ text: String?) -> SQLiteValue { text.map { .text($0) } ?? .null }

    static func identifier(_ value: SQLiteValue) throws -> Identifier128 {
        guard let data = value.blob, let id = try? Identifier128(bytes: [UInt8](data)) else {
            throw CoreLedgerError.corrupt("an identifier column")
        }
        return id
    }

    static func optionalIdentifier(_ value: SQLiteValue) throws -> Identifier128? {
        if case .null = value { return nil }
        return try identifier(value)
    }

    static func digest(_ value: SQLiteValue) throws -> Digest256 {
        guard let data = value.blob, let digest = try? Digest256(bytes: [UInt8](data)) else {
            throw CoreLedgerError.corrupt("a digest column")
        }
        return digest
    }

    static func bytes(_ value: SQLiteValue) throws -> [UInt8] {
        guard let data = value.blob else { throw CoreLedgerError.corrupt("a blob column") }
        return [UInt8](data)
    }

    static func integer(_ value: SQLiteValue) throws -> Int64 {
        guard let integer = value.integer else { throw CoreLedgerError.corrupt("an integer column") }
        return integer
    }

    static func text(_ value: SQLiteValue) throws -> String {
        guard let text = value.text else { throw CoreLedgerError.corrupt("a text column") }
        return text
    }
}
