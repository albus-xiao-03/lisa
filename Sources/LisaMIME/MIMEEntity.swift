// The MIME entity tree: headers, decoded leaf bodies, multipart children and embedded messages.

import Foundation

/// One MIME entity.
public struct MIMEEntity: Sendable {
    public var headers: HeaderFields
    public var contentType: ContentType
    public var disposition: ContentDisposition?
    /// The transfer-decoded body of a leaf entity.
    public var body: Data
    public var parts: [MIMEEntity]
    /// The parsed message for a `message/rfc822` entity (forwarded mail).
    public var embedded: [MIMEEntity]
    public var warnings: [String]

    public var isMultipart: Bool { contentType.type == "multipart" }
}

/// Parses raw message bytes into an entity tree within the configured limits.
public enum MIMEParser {
    public static func parse(_ data: Data, limits: MIMELimits = MIMELimits()) throws -> MIMEEntity {
        guard data.count <= limits.maxMessageBytes else { throw MIMEError.messageTooLarge }
        var partCount = 0
        let entity = try parseEntity(data, depth: 0, limits: limits, partCount: &partCount)
        guard !entity.headers.fields.isEmpty else { throw MIMEError.noHeaders }
        return entity
    }

    private static func parseEntity(_ data: Data, depth: Int, limits: MIMELimits, partCount: inout Int) throws
        -> MIMEEntity
    {
        let (headerData, bodyData) = splitHeaderAndBody(data)
        let (headers, headersTruncated) = try HeaderFields.parse(headerData, limits: limits)
        let contentType = headers.value("Content-Type").flatMap { ContentType($0) } ?? ContentType.defaultText
        var entity = MIMEEntity(
            headers: headers, contentType: contentType,
            disposition: ContentDisposition(headers.value("Content-Disposition")), body: Data(), parts: [],
            embedded: [], warnings: [])
        if headersTruncated {
            entity.warnings.append("the header has more than \(limits.maxHeaderFields) fields; the rest were not read")
        }
        partCount += 1
        guard partCount <= limits.maxParts else {
            entity.warnings.append("the message has more than \(limits.maxParts) parts; the rest were not read")
            return entity
        }
        if contentType.type == "multipart" {
            guard depth < limits.maxDepth else {
                entity.warnings.append("multipart nesting deeper than \(limits.maxDepth) was not read")
                return entity
            }
            guard let boundary = contentType.boundary, !boundary.isEmpty else {
                entity.warnings.append("a multipart part has no boundary; it was read as text")
                entity.contentType = ContentType(
                    type: "text", subtype: "plain", parameters: ["charset": contentType.charset ?? "us-ascii"])
                entity.body = TransferDecoding.decode(bodyData, encoding: headers.value("Content-Transfer-Encoding"))
                return entity
            }
            let (pieces, closed) = splitMultipart(bodyData, boundary: boundary)
            if !closed { entity.warnings.append("a multipart section is not properly closed") }
            for piece in pieces {
                guard partCount < limits.maxParts else {
                    if partCount == limits.maxParts {
                        entity.warnings.append(
                            "the message has more than \(limits.maxParts) parts; the rest were not read")
                        partCount += 1  // Reported once: enclosing multiparts stop without repeating it.
                    }
                    break
                }
                entity.parts.append(try parseEntity(piece, depth: depth + 1, limits: limits, partCount: &partCount))
            }
        } else if contentType.mimeType == "message/rfc822", depth < limits.maxDepth {
            let decoded = TransferDecoding.decode(bodyData, encoding: headers.value("Content-Transfer-Encoding"))
            entity.embedded = [try parseEntity(decoded, depth: depth + 1, limits: limits, partCount: &partCount)]
        } else {
            entity.body = TransferDecoding.decode(bodyData, encoding: headers.value("Content-Transfer-Encoding"))
        }
        return entity
    }

    /// Splits at the first empty line (CRLF CRLF or LF LF).
    static func splitHeaderAndBody(_ data: Data) -> (Data, Data) {
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            if bytes[index] == 10 {
                if index + 1 < bytes.count, bytes[index + 1] == 10 {
                    return (Data(bytes[..<index]), Data(bytes[(index + 2)...]))
                }
                if index + 2 < bytes.count, bytes[index + 1] == 13, bytes[index + 2] == 10 {
                    return (Data(bytes[..<index]), Data(bytes[(index + 3)...]))
                }
            }
            index += 1
        }
        return (data, Data())
    }

    /// Splits a multipart body on its boundary lines; reports whether the closing delimiter was present.
    static func splitMultipart(_ body: Data, boundary: String) -> ([Data], closed: Bool) {
        let delimiter = "--" + boundary
        var parts: [Data] = []
        var current: [UInt8]?
        var closed = false
        for line in splitLines([UInt8](body)) {
            let text = String(decoding: line.content, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            if text == delimiter + "--" {
                if let current { parts.append(Data(trimTrailingNewline(current))) }
                current = nil
                closed = true
                break
            }
            if text == delimiter {
                if let current { parts.append(Data(trimTrailingNewline(current))) }
                current = []
                continue
            }
            current?.append(contentsOf: line.content + line.terminator)
        }
        if let current, !current.isEmpty { parts.append(Data(trimTrailingNewline(current))) }
        return (parts, closed)
    }

    private struct Line {
        var content: [UInt8]
        var terminator: [UInt8]
    }

    private static func splitLines(_ bytes: [UInt8]) -> [Line] {
        var lines: [Line] = []
        var start = 0
        var index = 0
        while index < bytes.count {
            if bytes[index] == 10 {
                var end = index
                var terminator: [UInt8] = [10]
                if end > start, bytes[end - 1] == 13 {
                    end -= 1
                    terminator = [13, 10]
                }
                lines.append(Line(content: Array(bytes[start..<end]), terminator: terminator))
                start = index + 1
            }
            index += 1
        }
        if start < bytes.count { lines.append(Line(content: Array(bytes[start...]), terminator: [])) }
        return lines
    }

    private static func trimTrailingNewline(_ bytes: [UInt8]) -> [UInt8] {
        var result = bytes
        if result.last == 10 { result.removeLast() }
        if result.last == 13 { result.removeLast() }
        return result
    }
}
