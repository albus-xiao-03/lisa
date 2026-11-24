// Conversions between the replica store's values and SQLite columns: identifiers and digests as fixed-length blobs,
// canonical JSON as its exact bytes. A column that doesn't hold what the schema says is reported as corruption.

import Foundation
import LisaSQLite
import LisaSyncProtocol

/// Column encoding and decoding for the replica schema.
enum ReplicaColumns {
    static func id(_ identifier: Identifier128) -> SQLiteValue { .blob(Data(identifier.bytes)) }
    static func optionalID(_ identifier: Identifier128?) -> SQLiteValue { identifier.map(id) ?? .null }
    static func digest(_ digest: Digest256) -> SQLiteValue { .blob(Data(digest.bytes)) }
    static func bytes(_ bytes: [UInt8]) -> SQLiteValue { .blob(Data(bytes)) }
    static func optionalBytes(_ bytes: [UInt8]?) -> SQLiteValue { bytes.map { .blob(Data($0)) } ?? .null }
    static func optionalInteger(_ integer: Int64?) -> SQLiteValue { integer.map { .integer($0) } ?? .null }
    static func optionalText(_ text: String?) -> SQLiteValue { text.map { .text($0) } ?? .null }

    static func identifier(_ value: SQLiteValue) throws(ReplicaStoreError) -> Identifier128 {
        guard let data = value.blob, let identifier = try? Identifier128(bytes: [UInt8](data)) else {
            throw .corrupt("an identifier column")
        }
        return identifier
    }

    static func optionalIdentifier(_ value: SQLiteValue) throws(ReplicaStoreError) -> Identifier128? {
        if case .null = value { return nil }
        return try identifier(value)
    }

    static func digest(_ value: SQLiteValue) throws(ReplicaStoreError) -> Digest256 {
        guard let data = value.blob, let digest = try? Digest256(bytes: [UInt8](data)) else {
            throw .corrupt("a digest column")
        }
        return digest
    }

    static func bytes(_ value: SQLiteValue) throws(ReplicaStoreError) -> [UInt8] {
        guard let data = value.blob else { throw .corrupt("a blob column") }
        return [UInt8](data)
    }

    static func optionalBytes(_ value: SQLiteValue) -> [UInt8]? { value.blob.map { [UInt8]($0) } }

    static func integer(_ value: SQLiteValue) throws(ReplicaStoreError) -> Int64 {
        guard let integer = value.integer else { throw .corrupt("an integer column") }
        return integer
    }

    static func optionalInteger(_ value: SQLiteValue) -> Int64? { value.integer }

    static func text(_ value: SQLiteValue) throws(ReplicaStoreError) -> String {
        guard let text = value.text else { throw .corrupt("a text column") }
        return text
    }

    static func optionalText(_ value: SQLiteValue) -> String? { value.text }
}
