// The planning zone on a replica (plan §8.4.2 "Occurrences that move with the zone", "On replicas and in offline
// planning"). The planning zone is a replicated preference; a local zone change invalidates coverage at once, even with
// Core offline: every source with occurrences that move with the zone becomes unverified for the new zone, and stays
// so for a bucket until a zone proof for that source and zone covers it. A planning day is read from the instants of
// its own bounds in the planning zone, which the caller computes with the zone rules: all-day occurrences follow the
// planning date immediately, zoned and UTC ones keep their instants, and floating ones expanded in another zone are
// shown unverified. No free time is offered from an unverified, stale or repairing day.

import LisaSQLite
import LisaSyncProtocol

extension ReplicaStore {
    /// The planning zone this replica plans in, if one was set.
    public func planningZone() throws(ReplicaStoreError) -> String? {
        try read { session in
            try session.query("SELECT planning_zone FROM replica_identity WHERE singleton = 1").first?.first?.text
        }
    }

    /// Changes the planning zone: the coverage generation advances, and every source with occurrences that move with
    /// the zone becomes unverified for the new zone at once.
    public func setPlanningZone(_ zone: String) throws(ReplicaStoreError) {
        try write { session in
            let current = try session.query("SELECT planning_zone FROM replica_identity WHERE singleton = 1").first?
                .first?.text
            guard current != zone else { return }
            try session.query(
                """
                UPDATE replica_identity SET planning_zone = ?, coverage_generation = coverage_generation + 1
                WHERE singleton = 1
                """, [.text(zone)])
            let generation =
                try session.query("SELECT coverage_generation FROM replica_identity WHERE singleton = 1").first?.first?
                .integer ?? 0
            try session.query("DELETE FROM unverified_sources")
            if current != nil {
                try session.query(
                    """
                    INSERT INTO unverified_sources (source_id, zone, since_generation)
                    SELECT DISTINCT source_id, ?, ? FROM derived_rows
                    WHERE record_type = 'occurrence' AND zone_dependent = 1 AND body IS NOT NULL AND source_id IS NOT NULL
                    """, [.text(zone), .integer(generation)])
            }
            try LocalChangeJournal.append(.coverage, operations: [], items: [], in: session)
        }
    }

    /// One planning day: `date` in the planning zone, whose bounds in UTC milliseconds are `[start, end)`.
    public func planningDay(date: String, start: Int64, end: Int64) throws(ReplicaStoreError) -> PlanningDayView {
        let buckets = CalendarBuckets.bucket(ofInstant: start)...CalendarBuckets.bucket(ofInstant: max(start, end - 1))
        var listings: [Identifier128: (listing: OccurrenceListing, bucket: Int64)] = [:]
        var staleOrRepairing = false
        for bucket in buckets {
            guard let cursor = try partitionCursor(CalendarBuckets.partition(bucket)), !cursor.isRepairing else {
                staleOrRepairing = true
                continue
            }
            for listing in try occurrences(inBucket: bucket) where listings[listing.id] == nil {
                listings[listing.id] = (listing, bucket)
            }
        }
        return try read { session in
            let zone = try session.query("SELECT planning_zone FROM replica_identity WHERE singleton = 1").first?.first?
                .text
            let marked = try session.query("SELECT source_id FROM unverified_sources").compactMap { $0.first?.text }
            var unverified: Set<String> = []
            for source in marked {
                for bucket in buckets where try !Self.proves(source, zone: zone, bucket: bucket, in: session) {
                    unverified.insert(source)
                }
            }
            var entries: [PlanningDayView.Entry] = []
            for (listing, _) in listings.values.sorted(by: {
                $0.listing.id.bytes.lexicographicallyPrecedes($1.listing.id.bytes)
            }) {
                let row = listing.row
                switch row.timing {
                case .allDay(let firstDate, let endDate):
                    guard firstDate <= date, date < endDate else { continue }
                    entries.append(PlanningDayView.Entry(listing: listing, isVerified: true))
                case .timed(let from, let to, _):
                    guard from < end, to > start || (from == to && from >= start && from < end) else { continue }
                    let expandedElsewhere = row.movesWithZone && zone != nil && row.expandedZone != zone
                    let sourceUnverified = row.movesWithZone && unverified.contains(row.sourceID)
                    entries.append(
                        PlanningDayView.Entry(listing: listing, isVerified: !expandedElsewhere && !sourceUnverified))
                }
            }
            return PlanningDayView(
                date: date, entries: entries, unverifiedSources: unverified.sorted(),
                isStaleOrRepairing: staleOrRepairing)
        }
    }

    /// Whether a published zone proof covers `source` in `zone` at `bucket`.
    static func proves(_ source: String, zone: String?, bucket: Int64, in session: SQLiteSession) throws -> Bool {
        guard let zone else { return false }
        return try !session.query(
            """
            SELECT 1 FROM derived_rows
            WHERE record_type = 'zoneProof' AND body IS NOT NULL AND source_id = ? AND zone = ?
              AND first_bucket <= ? AND last_bucket >= ? AND generation IN \(DerivedRows.published)
            LIMIT 1
            """, [.text(source), .text(zone), .integer(bucket), .integer(bucket)]
        ).isEmpty
    }
}
