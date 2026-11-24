// The two sides of a nearby session (plan §8.7).

/// A side of a nearby session.
public enum NearbyRole: String, Hashable, Sendable {
    case initiator
    case responder
}
