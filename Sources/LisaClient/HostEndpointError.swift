// Why a Lisa host address cannot be used; descriptions never repeat the address, which might contain a password.

/// Why text is not a usable Lisa host address. Descriptions never repeat the text, which might contain a password.
public enum HostEndpointError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The text is not an absolute address made of printable ASCII.
    case malformed(String)
    /// The scheme is neither `https` nor `http`.
    case unsupportedScheme
    /// `http` names a host that is not a loopback address.
    case plaintextToRemoteHost
    /// The address carries a user name or password.
    case userInfo
    /// The address carries a query or a fragment.
    case queryOrFragment
    /// The host is missing, or is not a valid host name or IP address.
    case invalidHost(String)
    /// The port is not a number from 1 to 65535.
    case invalidPort
    /// A path segment is empty, `.` or `..`, or has a character other than letters, digits, `-`, `.`, `_` and `~`.
    case invalidPathPrefix

    public var description: String {
        switch self {
        case .malformed(let reason): "the Lisa host address is not valid: \(reason)"
        case .unsupportedScheme: "the Lisa host address must start with https:// (or http:// for a loopback host)"
        case .plaintextToRemoteHost:
            "the Lisa host address uses http, which is only allowed for a loopback host (127.0.0.1, ::1 or "
                + "localhost); use https"
        case .userInfo: "the Lisa host address must not contain a user name or password"
        case .queryOrFragment: "the Lisa host address must not contain a query (?) or a fragment (#)"
        case .invalidHost(let reason): "the Lisa host address has no valid host: \(reason)"
        case .invalidPort: "the Lisa host address has an invalid port: expected a number from 1 to 65535"
        case .invalidPathPrefix:
            "the Lisa host address has an invalid path: each segment must be letters, digits, '-', '.', '_' or '~', "
                + "and not empty, '.' or '..'"
        }
    }
}
