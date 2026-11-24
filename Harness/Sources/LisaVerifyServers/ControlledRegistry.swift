// What the controlled servers accepted (plan §10.8): a count of accepted submissions per logical action — the
// `Message-ID` of an email, the `Lisa-Operation-ID` of a push, model request or call — the provider reference each got,
// a lookup by those identifiers, and the class of every request received. Labeled controlled; it never contacts a
// service.

import Foundation

/// The shared state of one set of controlled servers.
public final class ControlledRegistry: @unchecked Sendable {
    /// The result of the server-side lookup by an action's identifiers.
    public enum Lookup: Sendable, Equatable {
        case disabled
        case notFound
        case found(reference: String, count: Int)
    }

    /// What the server does with a submission it received.
    public enum Admission: Sendable, Equatable {
        case answer(reference: String)
        case drop
        case rateLimited
    }

    private let lock = NSLock()
    private var behaviorValue = ControlledBehavior()
    private var accepted: [String: (reference: String, count: Int)] = [:]
    private var classes: [ControlledRequestClass: Int] = [:]
    private var sequence = 0

    public init() {}

    public var behavior: ControlledBehavior {
        get { lock.withLock { behaviorValue } }
        set { lock.withLock { behaviorValue = newValue } }
    }

    /// Records a submission under `key` unless the behavior is a rate limit, and says how to answer.
    public func admit(key: String, referencePrefix: String) -> Admission {
        lock.withLock {
            if behaviorValue.answer == .rateLimit { return .rateLimited }
            sequence += 1
            let reference = accepted[key]?.reference ?? "\(referencePrefix)\(sequence)"
            accepted[key] = (reference, (accepted[key]?.count ?? 0) + 1)
            return behaviorValue.answer == .acceptThenDrop ? .drop : .answer(reference: reference)
        }
    }

    public func lookup(key: String) -> Lookup {
        lock.withLock {
            guard behaviorValue.lookupEnabled else { return .disabled }
            guard let entry = accepted[key] else { return .notFound }
            return .found(reference: entry.reference, count: entry.count)
        }
    }

    /// Accepted submissions under `key`, whatever the lookup setting (for the case's own assertions).
    public func count(key: String) -> Int { lock.withLock { accepted[key]?.count ?? 0 } }

    public func classify(_ requestClass: ControlledRequestClass) {
        lock.withLock { classes[requestClass, default: 0] += 1 }
    }

    public var classCounts: [ControlledRequestClass: Int] { lock.withLock { classes } }
}
