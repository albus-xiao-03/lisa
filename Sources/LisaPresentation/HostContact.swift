// What one exchange with the host showed about the connection: answered, unreachable, incompatible, unpaired, removed.

import Foundation
import LisaClient

/// What one exchange with the host showed about the connection to it. Models report every exchange, so connectivity
/// is shown without polling the host.
public enum HostContact: Hashable, Sendable {
    /// The host answered.
    case reached
    /// The host could not be reached, or a gateway in front of it answered instead.
    case unreachable(reason: String)
    /// The host speaks an API version this app does not support; the value is its `Lisa-API-Version`.
    case incompatible(version: String)
    /// This device is not paired, so nothing was sent.
    case notPaired
    /// The host rejected this device's credential (401): the device was removed and must pair again.
    case revoked

    /// What `error` shows about the connection, or `nil` when it shows nothing, such as a cancelled request or a local
    /// failure.
    public init?(_ error: ClientError) {
        switch error {
        case .transport(let failure):
            self = .unreachable(reason: failure.description)
        case .incompatibleVersion(let version):
            self = .incompatible(version: version)
        case .notPaired:
            self = .notPaired
        case .api, .unexpectedResponse:
            if error.isUnauthenticated {
                self = .revoked
            } else if case .unexpectedResponse(let status) = error, Self.gatewayStatuses.contains(status) {
                self = .unreachable(reason: error.description)
            } else {
                self = .reached
            }
        case .decoding:
            self = .reached
        case .cancelled, .encoding, .invalidRequestID, .invalidArgument, .credentialStore:
            return nil
        }
    }

    /// What a flush of the offline queue showed, or `nil` when it reached nothing.
    init?(_ report: FlushReport) {
        let answered = !(report.applied.isEmpty && report.conflicts.isEmpty && report.failed.isEmpty)
        if case .stopped(let error) = report.stop, let contact = HostContact(error) {
            self = contact
        } else if answered {
            self = .reached
        } else {
            return nil
        }
    }

    /// Statuses a gateway in front of the host answers with when the host itself does not; without Lisa's error body
    /// they say nothing about the host.
    private static let gatewayStatuses: Set<Int> = [502, 503, 504]
}
