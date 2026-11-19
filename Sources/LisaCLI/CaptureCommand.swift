// `lisa capture`: saves an idea, text or link immediately; a repeated request ID returns the original capture. With
// `--retrieve`, the page behind a captured link is read right away, once (NEWS-01).

import ArgumentParser
import Foundation
import LisaAPIContract
import LisaClient

struct CaptureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture", abstract: "Capture an idea, text or a link.")

    @OptionGroup var host: HostOptions

    @Option(help: "idea, text or link.")
    var kind: CaptureKindValue = .idea

    @Option(help: "A title for a shared link.")
    var title: String?

    @Option(
        name: .customLong("request-id"),
        help: "A stable request ID so a retried capture is saved once, and with --retrieve its page is read once.")
    var requestID: String?

    @Flag(
        help: ArgumentHelp(
            "Read the page behind the link right after capturing it (with --kind link).",
            discussion:
                "Lisa sends one GET, to public https addresses only, without cookies or credentials, and keeps the"
                + " page's visible text. It never signs in, works around a paywall, runs scripts or follows the"
                + " page's links. When the page cannot be read, the item stays headline-only and the command exits"
                + " with 1."))
    var retrieve = false

    @Argument(help: "The idea or text, or the link's address.")
    var content: [String]

    func validate() throws {
        guard retrieve else { return }
        switch kind {
        case .link:
            return
        case .sharedAppleNews:
            throw ValidationError("--retrieve reads links only; Apple News items are kept as shared content")
        case .idea, .text:
            throw ValidationError("--retrieve needs --kind link; links inside ideas and text are never fetched")
        }
    }

    func run() async throws {
        let text = content.joined(separator: " ")
        let isLink = kind == .link || kind == .sharedAppleNews
        let request = CaptureRequestDTO(
            kind: kind, text: isLink ? nil : text, url: isLink ? text : nil, title: title, channel: .commandLine)
        let output = host.output
        let result = try await HostSession.withOwner(host) { _, client in
            let capture = try await client.capture(request, requestID: requestID)
            var result = CaptureCommandResult(capture: capture)
            guard retrieve else { return result }
            // The capture is saved: say so before the page is requested, which can take a while.
            if !output.json { print(Self.describe(capture)) }
            do throws(ClientError) {
                result.retrieval = try await client.retrieveCapturedPage(
                    captureID: capture.id, requestID: Self.retrievalRequestID(for: requestID))
            } catch {
                result.retrievalError = error.description
            }
            return result
        }
        guard retrieve else {
            try output.emit(result.capture) { Self.describe($0) }
            return
        }
        if output.json {
            try output.emit(result) { _ in "" }
        } else if let retrieval = result.retrieval {
            print(Self.describe(retrieval))
        }
        if let error = result.retrievalError {
            Output.error(error)
            throw LisaExit.failure
        }
        if result.retrieval?.retrieved == false { throw LisaExit.failure }
    }

    /// The retrieval's request ID, derived from the capture's, so rerunning the same command replays both answers
    /// instead of asking for the page again. Without a capture request ID, or when the derived one would be too long,
    /// the client picks a random one.
    static func retrievalRequestID(for captureRequestID: String?) -> String? {
        guard let captureRequestID else { return nil }
        let derived = captureRequestID + ":retrieve"
        return derived.count <= 128 ? derived : nil
    }

    static func describe(_ capture: CaptureDTO) -> String {
        "\(capture.created ? "saved" : "already saved") \(capture.kind.rawValue) \(capture.id)"
            + (capture.ideaID.map { " as idea \($0)" } ?? "") + (capture.newsID.map { " as shared item \($0)" } ?? "")
    }

    /// One line about the page: what was kept, or why nothing was. Only the page's origin is shown.
    static func describe(_ retrieval: CaptureRetrievalDTO) -> String {
        guard retrieval.retrieved else {
            return "the page was not read (\(retrieval.failureClass ?? "unknown")): "
                + "\(retrieval.failureSummary ?? "no reason was given"); nothing from it was kept"
        }
        let origin = retrieval.pageURL.flatMap(Self.origin).map { " from \($0)" } ?? ""
        guard retrieval.boundary == "pageText" else {
            return "read the page\(origin): \"\(retrieval.title)\"; it has no text Lisa can read without running"
                + " scripts, so the item stays headline-only"
        }
        return "read the page\(origin): \"\(retrieval.title)\", \(retrieval.textCharacters) characters kept"
            + (retrieval.textTruncated ? " (the page's text was cut at the size limit)" : "")
    }

    /// The scheme, host and port of an address.
    static func origin(_ address: String) -> String? {
        guard let components = URLComponents(string: address), let scheme = components.scheme,
            let host = components.host
        else { return nil }
        return "\(scheme)://\(host)" + (components.port.map { ":\($0)" } ?? "")
    }
}

/// What `lisa capture --retrieve --json` prints: the capture, and what reading its page did or why the host refused.
struct CaptureCommandResult: Encodable {
    var capture: CaptureDTO
    var retrieval: CaptureRetrievalDTO?
    /// Why the host refused or could not finish reading the page, such as a conflict or a temporary failure.
    var retrievalError: String?
}

extension CaptureKindValue: ExpressibleByArgument {}
