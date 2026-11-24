// The local token index (plan §7.2.1, §8.6.1): it implements `ReplicaIndexing`, so an item's postings change in the
// same transaction as the item's effective view, and a search reads them on one snapshot. A search for several tokens
// finds the items holding every one of them.

import Foundation
import LisaReplicaStore
import LisaSQLite
import LisaSyncProtocol

/// The replica's search index.
public struct LocalSearchIndex: ReplicaIndexing {
    public init() {}

    /// Replaces `item`'s postings with the tokens of its effective view's searchable text.
    public func itemChanged(_ item: ReplicaItemKey, in session: SQLiteSession) throws {
        try write(
            item, texts: try ReplicaStore.searchableText(of: item, in: session), into: "search_postings", in: session)
    }

    /// The same for a staged installation's index.
    public func stage(_ item: ReplicaItemKey, searchableText: [String], into table: String, in session: SQLiteSession)
        throws
    {
        try write(item, texts: searchableText, into: table, in: session)
    }

    private func write(_ item: ReplicaItemKey, texts: [String], into table: String, in session: SQLiteSession) throws {
        guard table == "search_postings" || table == "staged_search_postings" else {
            throw ReplicaStoreError.corrupt("an unknown postings table")
        }
        let id = SQLiteValue.blob(Data(item.entityID.bytes))
        try session.query("DELETE FROM \(table) WHERE entity_type = ? AND entity_id = ?", [.text(item.entityType), id])
        var tokens: Set<String> = []
        for text in texts { tokens.formUnion(SearchTokenizer.tokens(text)) }
        for token in tokens {
            try session.query(
                "INSERT INTO \(table) (token, entity_type, entity_id) VALUES (?, ?, ?)",
                [.text(token), .text(item.entityType), id])
        }
    }

    /// The items whose postings hold every token of `query`, ordered by type and ID; none for a query without tokens.
    public static func search(_ query: String, in session: SQLiteSession) throws -> [ReplicaItemKey] {
        let tokens = SearchTokenizer.tokens(query)
        guard !tokens.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: tokens.count).joined(separator: ", ")
        let rows = try session.query(
            """
            SELECT entity_type, entity_id FROM search_postings WHERE token IN (\(placeholders))
            GROUP BY entity_type, entity_id HAVING count(DISTINCT token) = ? ORDER BY entity_type, entity_id
            """, tokens.map { .text($0) } + [.integer(Int64(tokens.count))])
        return try rows.map { row in
            guard let type = row[0].text, let data = row[1].blob else {
                throw ReplicaStoreError.corrupt("a search posting")
            }
            return ReplicaItemKey(entityType: type, entityID: try Identifier128(bytes: [UInt8](data)))
        }
    }

    /// Searches `store` on its own read-only connection as a long reader under the reader monitor (plan §8.15.2):
    /// `readerReleased` means the monitor released it; search again later.
    public static func search(_ query: String, in store: ReplicaStore, purpose: SQLiteReaderPurpose = .search)
        throws(ReplicaStoreError) -> [ReplicaItemKey]
    {
        try store.withLongReader(purpose) { session in try search(query, in: session) }
    }
}
