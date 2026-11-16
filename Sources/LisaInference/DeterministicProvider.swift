// A deterministic, rule-based provider for tests and the demonstration; it is always labeled as such.

import Foundation

/// Extracts items from explicitly marked lines, with no model and no network.
///
/// Recognized lines (case-insensitive):
/// - `Task: <title>` (optionally followed by `Due: <when>`; `(confirmed)` marks a confirmed commitment)
/// - `Deadline: <when>` or `Due: <when>` (attaches to the preceding task)
/// - `Meeting: <title> on <when>` or `Event: …` (optionally `at <location>` after `|`)
/// - `Please <request> by <when>`
/// - `Cancelled: <title>` / `Moved: <title> to <when>`
public struct DeterministicProvider: ModelProvider {
    public let descriptor = ModelDescriptor(name: "deterministic-rules", location: .inProcess, isDeterministic: true)

    public init() {}

    public func complete(_ request: ModelRequest) async throws -> ModelResponse {
        guard let prompt = request.messages.last(where: { $0.role == .user })?.content,
            let content = UntrustedContent.extract(from: prompt)
        else { throw ModelError.invalidResponse("no source content found") }
        let payload = ModelExtractionPayload(items: DeterministicProvider.items(in: content))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        return ModelResponse(text: String(decoding: data, as: UTF8.self), finishReason: "stop")
    }

    static func items(in content: String) -> [ModelExtractedItem] {
        var items: [ModelExtractedItem] = []
        // Any newline, including CRLF, which Swift treats as a single character.
        for rawLine in content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespaces).trimmingCharacters(
                in: CharacterSet(charactersIn: ">*- "))
            let lower = line.lowercased()
            if let title = value(after: "task:", in: line) {
                let confirmed = lower.contains("(confirmed)")
                let clean = title.replacingOccurrences(of: "(confirmed)", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                items.append(
                    ModelExtractedItem(
                        kind: "commitment", title: clean, confirmation: confirmed ? "confirmed" : "possible",
                        priority: lower.contains("high priority") ? "high" : nil, evidence: line))
            } else if let when = value(after: "deadline:", in: line) ?? value(after: "due:", in: line), !items.isEmpty {
                items[items.count - 1].deadline = when
                items[items.count - 1].evidence = items[items.count - 1].evidence
            } else if let rest = value(after: "meeting:", in: line) ?? value(after: "event:", in: line) {
                let parts = rest.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                var title = parts[0]
                var when: String?
                if let range = title.range(of: " on ", options: .caseInsensitive) {
                    when = String(title[range.upperBound...])
                    title = String(title[..<range.lowerBound])
                }
                let location = parts.dropFirst().first.map {
                    $0.replacingOccurrences(of: "at ", with: "", options: [.anchored, .caseInsensitive])
                }
                items.append(
                    ModelExtractedItem(
                        kind: "meeting", title: title, confirmation: "possible", start: when, location: location,
                        evidence: line))
            } else if lower.hasPrefix("please "),
                let range = line.range(of: " by ", options: [.caseInsensitive, .backwards])
            {
                let title = String(line[line.index(line.startIndex, offsetBy: 7)..<range.lowerBound])
                items.append(
                    ModelExtractedItem(
                        kind: "request", title: title.prefix(1).uppercased() + title.dropFirst(),
                        confirmation: "possible",
                        deadline: String(line[range.upperBound...]).trimmingCharacters(
                            in: CharacterSet(charactersIn: ". ")),
                        evidence: line))
            } else if let title = value(after: "cancelled:", in: line) ?? value(after: "canceled:", in: line) {
                items.append(
                    ModelExtractedItem(
                        kind: "change", title: "Cancelled: \(title)", confirmation: "informational", evidence: line))
            } else if let rest = value(after: "moved:", in: line) {
                items.append(
                    ModelExtractedItem(
                        kind: "change", title: "Moved: \(rest)", confirmation: "informational", evidence: line))
            }
        }
        return items
    }

    private static func value(after prefix: String, in line: String) -> String? {
        guard line.lowercased().hasPrefix(prefix) else { return nil }
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
