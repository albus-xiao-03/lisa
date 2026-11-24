// Causal readiness and bounded release, persisted (plan §8.2.2): LisaMerge's `CausalRelease`, step by step in the
// replica's `causal_*` tables, each step one short transaction, so a kill between steps resumes without loss or
// repetition. An operation is decided once: `applied` when it enters the effective view (a local operation at once, a
// relayed one when every dependency is decided), `rejected` for Core's rejection or a cycle among waiting operations.
// A decision inserts one marker, whatever the number of dependents; an expansion step reads at most 256 edges in all,
// from the oldest markers on, each after its cursor (so the many markers without dependents that releases leave cost
// one step, not one each), and enqueues the dependents now ready; a release step applies at most 256 ready operations,
// oldest first and round-robin across origins. Edges are kept only for waiting operations.

import LisaMerge
import LisaSQLite
import LisaSyncProtocol

/// The persisted causal state, inside the caller's transaction.
enum CausalReleaseTables {
    enum Intake: Hashable, Sendable {
        case ready
        case waiting
        case alreadyKnown
        case rejectedMalformed
        case rejectedCycle(Set<Identifier128>)
    }

    /// The most ready rows one release step looks at to choose its 256, oldest first.
    static let releaseWindow = 4_096

    static func decision(_ operation: Identifier128, in session: SQLiteSession) throws -> CausalRelease.Decision? {
        guard
            let text = try session.query(
                "SELECT decision FROM causal_decisions WHERE operation_id = ?", [ReplicaColumns.id(operation)]
            ).first?.first?.text
        else { return nil }
        guard let decision = CausalRelease.Decision(rawValue: text) else {
            throw ReplicaStoreError.corrupt("a causal decision")
        }
        return decision
    }

    /// An arriving operation from `origin` declaring `dependencies`.
    static func intake(
        _ operation: Identifier128, origin: Identifier128, dependencies: [Identifier128], in session: SQLiteSession
    ) throws -> Intake {
        let known = try session.query(
            """
            SELECT 1 FROM causal_decisions WHERE operation_id = ?1
            UNION ALL SELECT 1 FROM causal_waiting WHERE operation_id = ?1
            UNION ALL SELECT 1 FROM causal_ready WHERE operation_id = ?1
            """, [ReplicaColumns.id(operation)])
        guard known.isEmpty else { return .alreadyKnown }
        guard dependencies.count <= CausalRelease.maximumDependencies else {
            try decide(operation, .rejected, in: session)
            return .rejectedMalformed
        }
        var open: [Identifier128] = []
        for dependency in dependencies where try decision(dependency, in: session) == nil { open.append(dependency) }
        guard !open.isEmpty else {
            try session.query(
                "INSERT INTO causal_ready (operation_id, origin_key) VALUES (?, ?)",
                [ReplicaColumns.id(operation), ReplicaColumns.id(origin)])
            return .ready
        }
        try session.query(
            "INSERT INTO causal_waiting (operation_id, origin_key) VALUES (?, ?)",
            [ReplicaColumns.id(operation), ReplicaColumns.id(origin)])
        for dependency in open {
            try session.query(
                "INSERT INTO causal_edges (dependency_id, dependent_id) VALUES (?, ?)",
                [ReplicaColumns.id(dependency), ReplicaColumns.id(operation)])
        }
        if let cycle = try cycle(from: operation, in: session) {
            for member in cycle { try decide(member, .rejected, in: session) }
            return .rejectedCycle(cycle)
        }
        return .waiting
    }

    /// Records a decision and its marker. A waiting or ready operation decided directly leaves those queues.
    static func decide(_ operation: Identifier128, _ verdict: CausalRelease.Decision, in session: SQLiteSession) throws
    {
        guard try decision(operation, in: session) == nil else { return }
        let id = ReplicaColumns.id(operation)
        try session.query(
            "INSERT INTO causal_decisions (operation_id, decision) VALUES (?, ?)", [id, .text(verdict.rawValue)])
        try session.query("INSERT INTO causal_markers (operation_id) VALUES (?)", [id])
        try session.query("DELETE FROM causal_waiting WHERE operation_id = ?", [id])
        try session.query("DELETE FROM causal_ready WHERE operation_id = ?", [id])
        try session.query("DELETE FROM causal_edges WHERE dependent_id = ?", [id])
    }

    /// The most markers one expansion step visits.
    static let markersPerStep = 256

    /// One expansion step: at most 256 edges in all, from the oldest markers on, each after its cursor; a marker whose
    /// edges are all read is removed, and one left unfinished keeps its cursor. `nil` when no marker is left.
    static func expansionStep(in session: SQLiteSession) throws -> (edges: Int, enqueued: Int)? {
        let markers = try session.query(
            "SELECT marker_id, operation_id, cursor FROM causal_markers ORDER BY marker_id LIMIT ?",
            [.integer(Int64(markersPerStep))])
        guard !markers.isEmpty else { return nil }
        var budget = CausalRelease.edgesPerStep
        var read = 0
        var enqueued = 0
        for marker in markers {
            guard budget > 0 else { break }
            let dependents = try session.query(
                """
                SELECT dependent_id FROM causal_edges
                WHERE dependency_id = ?1 AND (?2 IS NULL OR dependent_id > ?2) ORDER BY dependent_id LIMIT ?3
                """, [marker[1], marker[2], .integer(Int64(budget + 1))])
            let batch = dependents.prefix(budget)
            for row in batch where try enqueueIfReady(row[0], in: session) { enqueued += 1 }
            read += batch.count
            budget -= batch.count
            if dependents.count > batch.count, let last = batch.last {
                try session.query("UPDATE causal_markers SET cursor = ? WHERE marker_id = ?", [last[0], marker[0]])
                break
            }
            try session.query("DELETE FROM causal_markers WHERE marker_id = ?", [marker[0]])
        }
        return (read, enqueued)
    }

    /// Moves a waiting operation whose dependencies are all decided to the ready queue; returns whether it moved.
    private static func enqueueIfReady(_ dependent: SQLiteValue, in session: SQLiteSession) throws -> Bool {
        let open =
            try session.query(
                """
                SELECT count(*) FROM causal_edges e
                WHERE e.dependent_id = ? AND NOT EXISTS
                  (SELECT 1 FROM causal_decisions d WHERE d.operation_id = e.dependency_id)
                """, [dependent]
            ).first?.first?.integer ?? 0
        guard open == 0,
            let origin = try session.query(
                "SELECT origin_key FROM causal_waiting WHERE operation_id = ?", [dependent]
            ).first?.first
        else { return false }
        try session.query("DELETE FROM causal_waiting WHERE operation_id = ?", [dependent])
        try session.query("DELETE FROM causal_edges WHERE dependent_id = ?", [dependent])
        try session.query("INSERT INTO causal_ready (operation_id, origin_key) VALUES (?, ?)", [dependent, origin])
        return true
    }

    /// One release step: at most 256 ready operations, oldest first and round-robin across origins, each decided
    /// `applied`. Returns them in the order released.
    static func releaseStep(in session: SQLiteSession) throws -> [Identifier128] {
        let rows = try session.query(
            "SELECT operation_id, origin_key FROM causal_ready ORDER BY ready_id LIMIT ?",
            [.integer(Int64(releaseWindow))])
        var queues: [[UInt8]: [Identifier128]] = [:]
        var origins: [[UInt8]] = []
        for row in rows {
            let origin = try ReplicaColumns.bytes(row[1])
            if queues[origin] == nil { origins.append(origin) }
            queues[origin, default: []].append(try ReplicaColumns.identifier(row[0]))
        }
        var chosen: [Identifier128] = []
        var round = 0
        while chosen.count < CausalRelease.releasesPerStep {
            var took = false
            for origin in origins {
                guard let queue = queues[origin], round < queue.count, chosen.count < CausalRelease.releasesPerStep
                else { continue }
                chosen.append(queue[round])
                took = true
            }
            if !took { break }
            round += 1
        }
        for operation in chosen { try decide(operation, .applied, in: session) }
        return chosen
    }

    static func counts(in session: SQLiteSession) throws -> (waiting: Int, ready: Int, markers: Int) {
        let row =
            try session.query(
                """
                SELECT (SELECT count(*) FROM causal_waiting), (SELECT count(*) FROM causal_ready),
                  (SELECT count(*) FROM causal_markers)
                """
            ).first ?? []
        guard row.count == 3 else { throw ReplicaStoreError.corrupt("causal counts") }
        return (
            Int(try ReplicaColumns.integer(row[0])), Int(try ReplicaColumns.integer(row[1])),
            Int(try ReplicaColumns.integer(row[2]))
        )
    }

    /// A cycle through `start` among waiting operations, found by walking at most 1,024 nodes.
    static func cycle(from start: Identifier128, in session: SQLiteSession) throws -> Set<Identifier128>? {
        var stack: [(node: Identifier128, path: [Identifier128])] = [(start, [start])]
        var visited: Set<Identifier128> = []
        while let (node, path) = stack.popLast(), visited.count < CausalRelease.cycleWalkLimit {
            let dependencies = try session.query(
                "SELECT dependency_id FROM causal_edges WHERE dependent_id = ?", [ReplicaColumns.id(node)])
            for row in dependencies {
                let dependency = try ReplicaColumns.identifier(row[0])
                guard try decision(dependency, in: session) == nil else { continue }
                if dependency == start { return Set(path) }
                let waiting = try !session.query(
                    "SELECT 1 FROM causal_waiting WHERE operation_id = ?", [ReplicaColumns.id(dependency)]
                ).isEmpty
                if waiting, !visited.contains(dependency) {
                    visited.insert(dependency)
                    stack.append((dependency, path + [dependency]))
                }
            }
        }
        return nil
    }
}
