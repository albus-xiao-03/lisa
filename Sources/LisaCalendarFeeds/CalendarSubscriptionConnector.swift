// The HTTPS iCalendar subscription connector (CAL-01, CAL-02, INGEST-01): a bounded, public-only, conditional GET
// whose full downloads are complete snapshots and whose "not modified" answers change nothing.

import Foundation
import LisaDomain
import LisaHTTP
import LisaHTTPSources
import LisaPorts
import LisaSecrets
import LisaTime

/// Reads one iCalendar subscription over HTTPS.
///
/// - The address is resolved at each fetch; a private address comes from the secret store and is never shown beyond
///   its origin.
/// - Requests go only to public-internet addresses, follow at most a few redirects (each re-checked by the transport),
///   and stay within the pass's size and time limits.
/// - Stored validators make an unchanged calendar cost one small exchange. A 304 is returned as an empty batch that is
///   not a snapshot, so it can never be mistaken for an empty calendar that would cancel events.
/// - A full download is offered as a complete snapshot only after its content checks pass.
public struct CalendarSubscriptionConnector: SourceConnector, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let kind: SourceKind = .calendarFeed
    public let address: CalendarSubscriptionAddress
    public let options: CalendarSubscriptionOptions
    private let secrets: any SecretStore
    private let client: any HTTPClient
    private let clock: any WallClock

    static let subject = "calendar"
    static let accept = "text/calendar, text/plain;q=0.5, */*;q=0.1"
    static let externalID = "calendar-subscription"

    /// - Parameters:
    ///   - address: a public https address, or a secret holding a private one.
    ///   - secrets: resolves a secret address at each fetch.
    ///   - client: the HTTP transport (`CurlHTTPClient` in production).
    ///   - clock: stamps retrieval times and ages stored validators.
    ///   - options: size, time, redirect and validator bounds.
    public init(
        address: CalendarSubscriptionAddress, secrets: any SecretStore, client: any HTTPClient,
        clock: any WallClock, options: CalendarSubscriptionOptions = CalendarSubscriptionOptions()
    ) {
        self.address = address
        self.secrets = secrets
        self.client = client
        self.clock = clock
        self.options = options
    }

    /// Resolves the address and applies the URL policy without contacting the server.
    public func validateConfiguration() throws {
        _ = try AddressResolution.resolve(address.source, secrets: secrets, subject: Self.subject).get()
    }

    public func fetch(cursor: String?, limits: SyncLimits) async throws -> FetchBatch {
        try Task.checkCancellation()
        guard limits.maxItems >= 1, limits.maxBytes >= 1 else {
            throw ConnectorError(.configuration, "the synchronization limits leave no room for the calendar")
        }
        let resolved = try AddressResolution.resolve(address.source, secrets: secrets, subject: Self.subject).get()
        let bounds = options.bounds(for: limits)
        let validators = ConditionalRequest.validators(
            from: ConditionalCursor.decode(cursor), binding: resolved.binding, now: clock.now(),
            lifetimeSeconds: bounds.validatorLifetimeSeconds)
        let request = ConditionalRequest.make(
            url: resolved.url, accept: Self.accept, validators: validators, bounds: bounds)
        let response: HTTPResponse
        switch await FetchDeadline.send(request, using: client, within: bounds.deadlineSeconds) {
        case .response(let value):
            response = value
        case .failure(let failure):
            throw ResponseClassification.error(for: failure, subject: Self.subject, scrubber: resolved.scrubber)
        case .expired:
            throw ConnectorError(
                .timeout, "the calendar was not retrieved within \(Int(bounds.deadlineSeconds)) seconds")
        case .cancelled:
            throw CancellationError()
        }
        let receivedAt = clock.now()
        let outcome = try ResponseClassification.outcome(
            of: response, conditional: validators != nil, subject: Self.subject, now: receivedAt
        ).get()
        switch outcome {
        case .notModified(let notModified):
            guard let validators else {
                throw ConnectorError(.internalError, "a \"not modified\" answer arrived without stored validators")
            }
            // Nothing was transferred, so the stored occurrences stay exactly as they are.
            return FetchBatch(
                items: [], nextCursor: validators.refreshed(by: notModified).encoded(), isCompleteSnapshot: false)
        case .content(let content):
            if let error = ContentCoding.error(in: content, subject: Self.subject) { throw error }
            guard content.body.count <= bounds.maxBytes else {
                throw ResponseClassification.tooLarge(subject: Self.subject, limit: bounds.maxBytes)
            }
            let mediaType = MediaType.of(content)
            if let error = CalendarContentCheck.error(in: content.body, mediaType: mediaType) { throw error }
            let next = ConditionalCursor(binding: resolved.binding, response: content, retrievedAt: receivedAt)
            let item = FetchedItem(
                externalID: Self.externalID, kind: .calendar, data: content.body, receivedAt: receivedAt,
                metadata: [
                    "origin": URLPolicy.origin(of: content.finalURL), "mediaType": mediaType?.essence ?? "unknown",
                ])
            return FetchBatch(items: [item], nextCursor: next.encoded(), isCompleteSnapshot: true)
        }
    }

    public var description: String { "calendar subscription connector for \(address)" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: ["address": address.description]) }
}
