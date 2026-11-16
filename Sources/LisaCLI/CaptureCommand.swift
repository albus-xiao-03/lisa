// `lisa capture`: saves an idea, text or link immediately; a repeated request ID returns the original capture.

import ArgumentParser
import Foundation
import LisaAPIContract

struct CaptureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture", abstract: "Capture an idea, text or a link.")

    @OptionGroup var host: HostOptions

    @Option(help: "idea, text or link.")
    var kind: CaptureKindValue = .idea

    @Option(help: "A title for a shared link.")
    var title: String?

    @Option(name: .customLong("request-id"), help: "A stable request ID so a retried capture is saved once.")
    var requestID: String?

    @Argument(help: "The idea or text, or the link's address.")
    var content: [String]

    func run() async throws {
        let text = content.joined(separator: " ")
        let isLink = kind == .link || kind == .sharedAppleNews
        let request = CaptureRequestDTO(
            kind: kind, text: isLink ? nil : text, url: isLink ? text : nil, title: title, channel: .commandLine)
        let capture = try await HostSession.withOwner(host) { _, client in
            try await client.capture(request, requestID: requestID)
        }
        try host.output.emit(capture) { capture in
            "\(capture.created ? "saved" : "already saved") \(capture.kind.rawValue) \(capture.id)"
                + (capture.ideaID.map { " as idea \($0)" } ?? "")
                + (capture.newsID.map { " as shared item \($0)" } ?? "")
        }
    }
}

extension CaptureKindValue: ExpressibleByArgument {}
