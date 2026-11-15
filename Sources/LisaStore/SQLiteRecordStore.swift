// The SQLite implementation of RecordStore: JSON record bodies with whitelisted indexed columns.

import Foundation
import LisaDomain
import LisaPorts
import LisaSQLite

/// Records stored as JSON bodies with indexed columns. Queries may only name declared fields, and every value is a
/// bound parameter.
public final class SQLiteRecordStore: RecordStore {
    let database: SQLiteDatabase

    init(database: SQLiteDatabase) {
        self.database = database
    }

    @discardableResult
    public func read<T>(_ body: (any RecordReading) throws -> T) throws -> T {
        try mapErrors { try database.readTransaction { try body(RecordSession(session: $0)) } }
    }

    @discardableResult
    public func write<T>(_ body: (any RecordWriting) throws -> T) throws -> T {
        try mapErrors { try database.writeTransaction { try body(RecordSession(session: $0)) } }
    }

    private func mapErrors<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as SQLiteError where error.isBusy {
            throw StoreError.unavailable("the database is busy")
        }
    }
}

/// Record operations within one transaction.
struct RecordSession: RecordWriting {
    let session: SQLiteSession
    private let encoder = DomainJSON.encoder()
    private let decoder = DomainJSON.decoder()

    init(session: SQLiteSession) {
        self.session = session
    }

    func get<E: StoredEntity>(_ type: E.Type, id: E.ID) throws -> E? {
        let table = try tableName(E.self)
        let rows = try session.query("SELECT body FROM \(table) WHERE id = ?", [.text(id.description)])
        return try rows.first.map { try decode(E.self, $0) }
    }

    func find<E: StoredEntity>(_ type: E.Type, _ query: RecordQuery) throws -> [E] {
        let (whereClause, parameters) = try clause(E.self, query)
        var sql = "SELECT body FROM \(try tableName(E.self))\(whereClause)"
        sql += try orderClause(E.self, query)
        if let limit = query.limit { sql += " LIMIT \(max(0, limit))" }
        return try session.query(sql, parameters).map { try decode(E.self, $0) }
    }

    func count<E: StoredEntity>(_ type: E.Type, _ query: RecordQuery) throws -> Int {
        let (whereClause, parameters) = try clause(E.self, query)
        let rows = try session.query("SELECT COUNT(*) FROM \(try tableName(E.self))\(whereClause)", parameters)
        return Int(rows.first?.first?.integer ?? 0)
    }

    func insert<E: StoredEntity>(_ entity: E) throws -> E {
        let table = try tableName(E.self)
        let indexes = E.indexes.map(\.name)
        let columns = ["id", "revision", "updated_at", "body"] + indexes
        let values = entity.indexValues
        let parameters: [SQLiteValue] =
            [
                .text(entity.id.description), .integer(entity.revision.value),
                .integer(Int64((entity.updatedAt.timeIntervalSince1970 * 1000).rounded())), .text(try encode(entity)),
            ] + indexes.map { sqliteValue(values[$0] ?? .null) }
        let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
        try run(
            "INSERT INTO \(table) (\(columns.joined(separator: ", "))) VALUES (\(placeholders))", parameters,
            table: table)
        return entity
    }

    func update<E: StoredEntity>(_ entity: E) throws -> E {
        let table = try tableName(E.self)
        var updated = entity
        updated.revision = entity.revision.next
        let indexes = E.indexes.map(\.name)
        let values = updated.indexValues
        let assignments = (["revision", "updated_at", "body"] + indexes).map { "\($0) = ?" }.joined(separator: ", ")
        let parameters: [SQLiteValue] =
            [
                .integer(updated.revision.value),
                .integer(Int64((updated.updatedAt.timeIntervalSince1970 * 1000).rounded())),
                .text(try encode(updated)),
            ] + indexes.map { sqliteValue(values[$0] ?? .null) } + [
                .text(entity.id.description), .integer(entity.revision.value),
            ]
        try run("UPDATE \(table) SET \(assignments) WHERE id = ? AND revision = ?", parameters, table: table)
        if session.changes == 0 {
            let rows = try session.query("SELECT revision FROM \(table) WHERE id = ?", [.text(entity.id.description)])
            guard let stored = rows.first?.first?.integer else {
                throw StoreError.notFound(collection: table, id: entity.id.description)
            }
            throw StoreError.conflict(
                collection: table, id: entity.id.description, expected: entity.revision, actual: Revision(stored))
        }
        return updated
    }

    func delete<E: StoredEntity>(_ type: E.Type, id: E.ID) throws {
        let table = try tableName(E.self)
        try session.query("DELETE FROM \(table) WHERE id = ?", [.text(id.description)])
    }

    private func run(_ sql: String, _ parameters: [SQLiteValue], table: String) throws {
        do {
            try session.query(sql, parameters)
        } catch let error as SQLiteError where error.isUniqueViolation {
            let field = error.message.split(separator: ".").last.map(String.init) ?? "key"
            throw StoreError.duplicate(collection: table, field: field)
        }
    }

    private func tableName<E: StoredEntity>(_ type: E.Type) throws -> String {
        guard CollectionRegistry.collectionNames.contains(E.collectionName) else {
            throw StoreError.unknownCollection(E.collectionName)
        }
        return E.collectionName
    }

    private func clause<E: StoredEntity>(_ type: E.Type, _ query: RecordQuery) throws -> (String, [SQLiteValue]) {
        guard !query.conditions.isEmpty else { return ("", []) }
        var parts: [String] = []
        var parameters: [SQLiteValue] = []
        for condition in query.conditions {
            guard E.queryableFields.contains(condition.field) else {
                throw StoreError.unknownField(collection: E.collectionName, field: condition.field)
            }
            switch condition {
            case .compare(let field, let comparison, let value):
                parts.append("\(field) \(comparison.rawValue) ?")
                parameters.append(sqliteValue(value))
            case .isNull(let field):
                parts.append("\(field) IS NULL")
            case .isNotNull(let field):
                parts.append("\(field) IS NOT NULL")
            case .oneOf(let field, let values):
                if values.isEmpty {
                    parts.append("0")
                } else {
                    parts.append("\(field) IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))")
                    parameters.append(contentsOf: values.map(sqliteValue))
                }
            }
        }
        return (" WHERE " + parts.joined(separator: " AND "), parameters)
    }

    private func orderClause<E: StoredEntity>(_ type: E.Type, _ query: RecordQuery) throws -> String {
        guard !query.ordering.isEmpty else { return " ORDER BY id" }
        let parts = try query.ordering.map { ordering -> String in
            guard E.queryableFields.contains(ordering.field) else {
                throw StoreError.unknownField(collection: E.collectionName, field: ordering.field)
            }
            return "\(ordering.field) \(ordering.ascending ? "ASC" : "DESC")"
        }
        return " ORDER BY " + parts.joined(separator: ", ") + ", id"
    }

    private func sqliteValue(_ value: IndexValue) -> SQLiteValue {
        switch value {
        case .text(let text): .text(text)
        case .integer(let number): .integer(number)
        case .null: .null
        }
    }

    private func encode<E: StoredEntity>(_ entity: E) throws -> String {
        String(decoding: try encoder.encode(entity), as: UTF8.self)
    }

    private func decode<E: StoredEntity>(_ type: E.Type, _ row: [SQLiteValue]) throws -> E {
        guard let text = row.first?.text else { throw StoreError.corrupt("a \(E.collectionName) record has no body") }
        do {
            return try decoder.decode(E.self, from: Data(text.utf8))
        } catch {
            throw StoreError.corrupt("a \(E.collectionName) record could not be decoded")
        }
    }
}
