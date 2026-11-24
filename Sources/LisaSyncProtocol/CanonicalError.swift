// Why canonical JSON could not be produced or accepted (plan §8.16.1).

/// A canonical JSON encoding or decoding failure. Each case names one rule of plan §8.16.1, with the byte offset
/// where the decoder found it.
public enum CanonicalError: Error, Hashable, Sendable {
    /// The input is larger than the limit for its unit.
    case tooLarge(bytes: Int, limit: Int)
    /// Containers are nested more deeply than the limit.
    case tooDeep(limit: Int, offset: Int)
    /// The bytes are not valid UTF-8 (including overlong forms, encoded surrogates and values above U+10FFFF).
    case invalidUTF8(offset: Int)
    /// A byte that cannot start or continue a value at this position, including any whitespace.
    case unexpectedByte(UInt8, offset: Int)
    /// The input ended inside a value.
    case unexpectedEnd
    /// Bytes follow the top-level value.
    case trailingBytes(offset: Int)
    /// A number with a fraction, an exponent or another non-integer form.
    case nonInteger(offset: Int)
    /// An integer outside the signed 64-bit range.
    case integerOutOfRange(offset: Int)
    /// A string escape that is malformed or names a lone surrogate.
    case invalidEscape(offset: Int)
    /// An unescaped control character inside a string.
    case controlCharacter(offset: Int)
    /// An object key that repeats an earlier key, exactly or as canonically equivalent text.
    case duplicateKey(String)
    /// Valid JSON that is not in canonical form: unsorted keys, an unnecessary or non-minimal escape, a leading
    /// zero, negative zero, or any other byte difference from the canonical encoding of the same value.
    case nonCanonical(offset: Int)
}
