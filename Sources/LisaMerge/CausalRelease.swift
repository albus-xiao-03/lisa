// Causal readiness and bounded release (plan §8.2.2): an operation waits for its dependencies and is never applied out
// of causal order or skipped. A decision inserts one release marker, whatever the number of dependents; an expansion
// step reads at most 256 dependency edges after the marker's cursor and enqueues the dependents now ready; a release
// step applies at most 256 ready operations, oldest first and round-robin across origins. More than 32 declared
// dependencies is malformed; a cycle among waiting operations (only forged or corrupt input) rejects every member.
// This is the reference the replica store (M2) and Core's ledger (M3) persist step by step.

import LisaSyncProtocol

/// The causal state of a set of operations, advanced in bounded steps.
public struct CausalRelease: Sendable {
    public static let maximumDependencies = 32
    public static let edgesPerStep = 256
    public static let releasesPerStep = 256
    public static let cycleWalkLimit = 1_024

    public enum Decision: String, Hashable, Sendable {
        case applied
        case rejected
    }

    public enum Intake: Hashable, Sendable {
        case ready
        case waiting
        case rejectedMalformed
        /// The arriving operation closed a cycle; every member is rejected.
        case rejectedCycle(members: Set<Identifier128>)
    }

    struct Marker: Hashable, Sendable {
        let operation: Identifier128
        var cursor: Identifier128?
    }

    public private(set) var decisions: [Identifier128: Decision] = [:]
    private var dependencies: [Identifier128: [Identifier128]] = [:]
    private var origins: [Identifier128: Identifier128] = [:]
    private var waiting: Set<Identifier128> = []
    /// dependency → its waiting dependents, kept sorted by dependent ID for cursor reads.
    private var edges: [Identifier128: [Identifier128]] = [:]
    private var markers: [Marker] = []
    private var ready: [(operation: Identifier128, sequence: Int)] = []
    private var sequence = 0

    public init() {}

    public var markerCount: Int { markers.count }
    public var readyCount: Int { ready.count }
    public var waitingCount: Int { waiting.count }

    /// An arriving operation from `origin` declaring `declared` dependencies.
    public mutating func intake(
        _ operation: Identifier128, origin: Identifier128, dependencies declared: [Identifier128]
    )
        -> Intake
    {
        guard decisions[operation] == nil, dependencies[operation] == nil else { return .waiting }
        guard declared.count <= Self.maximumDependencies else {
            decisions[operation] = .rejected
            return .rejectedMalformed
        }
        dependencies[operation] = declared
        origins[operation] = origin
        let open = Set(declared).filter { decisions[$0] == nil }
        guard !open.isEmpty else {
            enqueue(operation)
            return .ready
        }
        waiting.insert(operation)
        for dependency in open {
            var list = edges[dependency, default: []]
            let index = list.firstIndex { !$0.bytes.lexicographicallyPrecedes(operation.bytes) } ?? list.endIndex
            list.insert(operation, at: index)
            edges[dependency] = list
        }
        if let cycle = cycle(from: operation) {
            for member in cycle {
                waiting.remove(member)
                decisions[member] = .rejected
                markers.append(Marker(operation: member, cursor: nil))
            }
            return .rejectedCycle(members: cycle)
        }
        return .waiting
    }

    /// Records a decision and inserts its release marker: constant work, however many dependents exist.
    public mutating func decide(_ operation: Identifier128, _ decision: Decision) {
        guard decisions[operation] == nil else { return }
        decisions[operation] = decision
        markers.append(Marker(operation: operation, cursor: nil))
    }

    /// One expansion step: at most 256 edges of the oldest marker. Returns the edges read and the operations enqueued.
    @discardableResult
    public mutating func expansionStep() -> (edges: Int, enqueued: Int) {
        guard var marker = markers.first else { return (0, 0) }
        let dependents = edges[marker.operation] ?? []
        let start =
            marker.cursor.map { cursor in
                dependents.firstIndex { cursor.bytes.lexicographicallyPrecedes($0.bytes) } ?? dependents.endIndex
            } ?? dependents.startIndex
        let batch = dependents[start...].prefix(Self.edgesPerStep)
        var enqueued = 0
        for dependent in batch where waiting.contains(dependent) {
            if (dependencies[dependent] ?? []).allSatisfy({ decisions[$0] != nil }) {
                waiting.remove(dependent)
                enqueue(dependent)
                enqueued += 1
            }
        }
        if let last = batch.last, start + batch.count < dependents.count {
            marker.cursor = last
            markers[0] = marker
        } else {
            markers.removeFirst()
            edges[marker.operation] = nil
        }
        return (batch.count, enqueued)
    }

    /// One release step: at most 256 ready operations, oldest first and round-robin across origins, each applied by
    /// `apply` and decided. Returns them in the order applied.
    @discardableResult
    public mutating func releaseStep(_ apply: (Identifier128) -> Decision) -> [Identifier128] {
        guard !ready.isEmpty else { return [] }
        var byOrigin: [Identifier128: [(operation: Identifier128, sequence: Int)]] = [:]
        for entry in ready { byOrigin[origins[entry.operation] ?? entry.operation, default: []].append(entry) }
        let originsOldestFirst = byOrigin.keys.sorted {
            (byOrigin[$0]!.first!.sequence) < (byOrigin[$1]!.first!.sequence)
        }
        var chosen: [Identifier128] = []
        var round = 0
        while chosen.count < Self.releasesPerStep {
            var took = false
            for origin in originsOldestFirst {
                guard let queue = byOrigin[origin], round < queue.count, chosen.count < Self.releasesPerStep else {
                    continue
                }
                chosen.append(queue[round].operation)
                took = true
            }
            if !took { break }
            round += 1
        }
        let chosenSet = Set(chosen)
        ready.removeAll { chosenSet.contains($0.operation) }
        for operation in chosen { decide(operation, apply(operation)) }
        return chosen
    }

    /// Runs expansion and release steps alternately until nothing is left; returns the steps taken.
    public mutating func drain(_ apply: (Identifier128) -> Decision) -> Int {
        var steps = 0
        while !markers.isEmpty || !ready.isEmpty {
            if !markers.isEmpty {
                expansionStep()
                steps += 1
            }
            if !ready.isEmpty {
                releaseStep(apply)
                steps += 1
            }
        }
        return steps
    }

    private mutating func enqueue(_ operation: Identifier128) {
        sequence += 1
        ready.append((operation, sequence))
    }

    /// A cycle through `start` among waiting operations, found by walking at most 1,024 nodes.
    private func cycle(from start: Identifier128) -> Set<Identifier128>? {
        var stack: [(node: Identifier128, path: [Identifier128])] = [(start, [start])]
        var visited: Set<Identifier128> = []
        while let (node, path) = stack.popLast(), visited.count < Self.cycleWalkLimit {
            for dependency in dependencies[node] ?? [] where decisions[dependency] == nil {
                if dependency == start { return Set(path) }
                if waiting.contains(dependency), !visited.contains(dependency) {
                    visited.insert(dependency)
                    stack.append((dependency, path + [dependency]))
                }
            }
        }
        return nil
    }
}
