// Why a wire identifier or digest was refused (plan §8.1.1, §8.16.1).

/// An identifier or digest that is not exactly its byte length or not strict lowercase hexadecimal.
public enum IdentifierError: Error, Hashable, Sendable {
    case invalidLength(Int)
    case invalidHex
}
