// The owner-initiated page retriever (NEWS-01, SEC-02): one bounded, https-only, public-only GET with re-checked
// redirects, read as text through LisaHTMLText without fetching subresources or running scripts.

import Foundation
import LisaDomain
import LisaHTTP
import LisaHTTPSources
import LisaPorts
import LisaTime

/// Retrieves the page behind a link the owner captured.
///
/// - Only an ``OwnerPageRequest`` can be retrieved, and one exists only for an owner-captured link.
/// - One GET is sent, to public-internet addresses only, over https, with at most a few redirects that the transport
///   re-checks; no cookies or credentials are sent, and nothing the page refers to is ever requested.
/// - Only HTML, XHTML and plain text are read, within size, text and time bounds.
/// - A page that needs signing in or payment is reported as such; Lisa never signs in or works around a paywall.
public struct OwnerPageRetriever: Sendable, CustomStringConvertible {
    public let options: OwnerPageOptions
    private let client: any HTTPClient
    private let clock: any WallClock

    static let subject = "page"
    static let accept = "text/html, application/xhtml+xml;q=0.9, text/plain;q=0.8"

    /// - Parameters:
    ///   - client: the HTTP transport (`CurlHTTPClient` in production).
    ///   - clock: stamps the retrieval time.
    ///   - options: size, text, time and redirect bounds.
    public init(client: any HTTPClient, clock: any WallClock, options: OwnerPageOptions = OwnerPageOptions()) {
        self.client = client
        self.clock = clock
        self.options = options
    }

    /// Retrieves the page. Every failure is classified; nothing is returned for a page that could not be read.
    public func retrieve(_ request: OwnerPageRequest) async throws(ConnectorError) -> RetrievedPage {
        guard !Task.isCancelled else { throw ConnectorError(.timeout, "the page retrieval was cancelled") }
        let bounds = options.bounds
        let scrubber = SecretScrubber(url: request.url)
        let exchange = ConditionalRequest.make(url: request.url, accept: Self.accept, validators: nil, bounds: bounds)
        let response: HTTPResponse
        switch await FetchDeadline.send(exchange, using: client, within: bounds.deadlineSeconds) {
        case .response(let value):
            response = value
        case .failure(let failure):
            throw ResponseClassification.error(for: failure, subject: Self.subject, scrubber: scrubber)
        case .expired:
            throw ConnectorError(.timeout, "the page was not retrieved within \(Int(bounds.deadlineSeconds)) seconds")
        case .cancelled:
            throw ConnectorError(.timeout, "the page retrieval was cancelled")
        }
        let retrievedAt = clock.now()
        let content: HTTPResponse
        let outcome = ResponseClassification.outcome(
            of: response, conditional: false, subject: Self.subject, now: retrievedAt)
        switch outcome {
        case .success(.content(let value)):
            content = value
        case .success(.notModified):
            throw ConnectorError(.internalError, "a \"not modified\" answer arrived for an unconditional request")
        case .failure(let error):
            throw Self.pageSpecific(error)
        }
        if let error = ContentCoding.error(in: content, subject: Self.subject) { throw error }
        guard content.body.count <= bounds.maxBytes else {
            throw ResponseClassification.tooLarge(subject: Self.subject, limit: bounds.maxBytes)
        }
        let bytes = [UInt8](content.body)
        let mediaType = MediaType.of(content)
        let kind = try PageContentCheck.kind(of: bytes, mediaType: mediaType).get()
        let decoded = try PageCharset.decode(bytes, declared: mediaType?.charset, kind: kind).get()
        let page = PageTextExtraction.extract(decoded.text, kind: kind, limit: options.textLimit)
        guard !page.text.isEmpty || page.title != nil else {
            throw ConnectorError(
                .parse, "the page has no text Lisa can read; it may need scripts, which Lisa never runs")
        }
        return RetrievedPage(
            captureID: request.captureID, requestedURL: request.url, finalURL: content.finalURL, title: page.title,
            text: page.text, textTruncated: page.truncated, mediaType: mediaType?.essence ?? kind.mediaType,
            characterSet: decoded.label, removedElements: page.removedElements, rawContent: content.body,
            retrievedAt: retrievedAt)
    }

    /// Sign-in and access refusals are about the page, not about a private address.
    private static func pageSpecific(_ error: ConnectorError) -> ConnectorError {
        switch error.errorClass {
        case .authentication:
            ConnectorError(
                .authentication, "the page requires signing in; Lisa never signs in or works around paywalls")
        case .permissionDenied:
            ConnectorError(
                .permissionDenied, "the site refused to provide the page; Lisa never works around access restrictions")
        default:
            error
        }
    }

    public var description: String { "owner page retriever" }
}
