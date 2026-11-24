// Why a nearby frame header was refused (plan §8.16.2, §8.7).

/// A nearby frame header that can't be accepted. Every case is decided from the 8 header bytes alone, before anything
/// is allocated for the payload.
public enum NearbyFrameError: Error, Hashable, Sendable {
    /// Not exactly `NearbyFrameHeader.length` bytes.
    case headerLength(Int)
    /// The declared total is shorter than the header or larger than the 1 MiB frame budget.
    case budget(TransferBudgetError)
    /// A header version this side doesn't speak.
    case unsupportedVersion(UInt8)
    /// The two reserved bytes aren't zero.
    case reservedBytesSet
}
