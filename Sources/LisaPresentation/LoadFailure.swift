// Why a screen's data could not be loaded: not paired, removed by the host, unreachable, missing, incompatible, other.

import Foundation
import LisaClient

/// Why a screen's data could not be loaded. Messages never contain credentials or the owner's content.
public enum LoadFailure: Hashable, Sendable {
    /// This device is not paired with a Lisa host.
    case notPaired
    /// The host no longer accepts this device's credential (401): it was removed and must pair again. Its cached data
    /// is cleared (plan §6.3).
    case revoked
    /// The host cannot be reached, or asked to retry later, and nothing usable is cached.
    case unreachable(reason: String)
    /// The host has no such data, such as no brief prepared for the date (404).
    case notFound
    /// The host speaks an API version this app does not support; the value is its `Lisa-API-Version`.
    case incompatibleHost(version: String)
    /// Any other failure, such as a refused request or an unreadable answer.
    case failed(reason: String)

    /// The failure a client error means.
    public init(_ error: ClientError) {
        if error == .notPaired {
            self = .notPaired
        } else if case .incompatibleVersion(let version) = error {
            self = .incompatibleHost(version: version)
        } else if error.isUnauthenticated {
            self = .revoked
        } else if error.isHostUnavailable {
            self = .unreachable(reason: error.description)
        } else if error.status == 404 {
            self = .notFound
        } else {
            self = .failed(reason: error.description)
        }
    }

    /// Whether the owner's data must no longer be shown: the device is not paired, or the host removed it.
    public var hidesData: Bool { self == .notPaired || self == .revoked }

    /// A sentence for the screen.
    public var message: String {
        switch self {
        case .notPaired: "This device is not paired with a Lisa host. Pair it in Connection settings."
        case .revoked: "The Lisa host removed this device. Pair it again to see your data."
        case .unreachable(let reason): "Lisa's host can't be reached and nothing is saved on this device (\(reason))."
        case .notFound: "There is nothing here yet."
        case .incompatibleHost(let version):
            "The Lisa host uses API version \(version), which this app does not support. Update the app or the host."
        case .failed(let reason): "Lisa couldn't load this (\(reason))."
        }
    }
}
