// Parses one framed server response into its typed form (RFC 9051 §7, §9; RFC 3501 §7 for IMAP4rev1 SEARCH):
// strictly for the items Lisa relies on, and leniently but within bounds for anything it ignores.

import Foundation

/// Bounds on what one response may contain, beyond the framer's size limits.
struct IMAPParseLimits: Hashable, Sendable {
    /// The most capabilities in a CAPABILITY response or response code.
    var maxCapabilities: Int
    /// The most UIDs or ranges in one SEARCH or ESEARCH result.
    var maxSearchElements: Int

    init(maxCapabilities: Int = 512, maxSearchElements: Int = 1_000_000) {
        self.maxCapabilities = maxCapabilities
        self.maxSearchElements = maxSearchElements
    }
}

/// Turns raw responses into `IMAPResponse` values.
enum IMAPResponseParser {
    static func parse(_ raw: IMAPRawResponse, limits: IMAPParseLimits = IMAPParseLimits()) throws(IMAPProtocolError)
        -> IMAPResponse
    {
        var reader = IMAPTokenReader(raw)
        switch reader.peek() {
        case nil:
            throw .malformedResponse("a response was empty")
        case 0x2B:
            return .continuation
        case 0x2A:
            _ = reader.consume(0x2A)
            try reader.expectSpace()
            return try untagged(&reader, limits: limits)
        default:
            let tag = try reader.readTag()
            try reader.expectSpace()
            guard let status = status(try reader.readKeyword()) else {
                throw .malformedResponse("a tagged response was not OK, NO or BAD")
            }
            return .tagged(tag: tag, status: status, try statusText(&reader, limits: limits))
        }
    }

    private static func status(_ keyword: String) -> IMAPStatus? {
        switch keyword {
        case "OK": .ok
        case "NO": .no
        case "BAD": .bad
        default: nil
        }
    }

    private static func untagged(_ reader: inout IMAPTokenReader, limits: IMAPParseLimits) throws(IMAPProtocolError)
        -> IMAPResponse
    {
        if let first = reader.peek(), (0x30...0x39).contains(first) {
            let number = try reader.readNumber32()
            try reader.expectSpace()
            let keyword = try reader.readKeyword()
            switch keyword {
            case "EXISTS":
                try reader.expectEnd("EXISTS")
                return .exists(number)
            case "EXPUNGE":
                return .expunge(number)
            case "FETCH":
                try reader.expectSpace()
                return .fetch(sequence: number, try fetchData(&reader))
            default:
                return .ignored(keyword)
            }
        }
        let keyword = try reader.readKeyword()
        if let status = status(keyword) { return .status(status, try statusText(&reader, limits: limits)) }
        switch keyword {
        case "BYE":
            return .bye(try statusText(&reader, limits: limits))
        case "PREAUTH":
            return .preauth(try statusText(&reader, limits: limits))
        case "CAPABILITY":
            var capabilities: [String] = []
            while reader.consume(0x20) {
                capabilities.append(try reader.readKeyword())
                guard capabilities.count <= limits.maxCapabilities else {
                    throw .malformedResponse("a CAPABILITY response listed too many capabilities")
                }
            }
            return .capability(capabilities)
        case "SEARCH":
            return .search(try searchResult(&reader, limits: limits))
        case "ESEARCH":
            return .extendedSearch(try extendedSearch(&reader, limits: limits))
        default:
            return .ignored(keyword)
        }
    }

    /// `resp-text` (RFC 9051 §9): an optional bracketed code, then free text. A missing text is accepted.
    private static func statusText(_ reader: inout IMAPTokenReader, limits: IMAPParseLimits)
        throws(IMAPProtocolError) -> IMAPStatusText
    {
        guard reader.consume(0x20) else {
            try reader.expectEnd("a status")
            return IMAPStatusText()
        }
        var code: IMAPResponseCode?
        if reader.peek() == 0x5B {
            _ = reader.consume(0x5B)
            code = try responseCode(reader.readUntil(0x5D, maxLength: 65_536), limits: limits)
            _ = reader.consume(0x5D)
            _ = reader.consume(0x20)
        }
        return IMAPStatusText(code: code, text: reader.readRemainder())
    }

    /// Interprets the content of `[...]`. UIDVALIDITY and UIDNEXT must be well-formed, because message identity
    /// depends on them; unknown codes keep only their name.
    private static func responseCode(_ content: [UInt8], limits: IMAPParseLimits) throws(IMAPProtocolError)
        -> IMAPResponseCode
    {
        let space = content.firstIndex(of: 0x20) ?? content.count
        let name = String(decoding: content[0..<space], as: UTF8.self).uppercased()
        let arguments = space < content.count ? Array(content[(space + 1)...]) : []
        switch name {
        case "READ-ONLY":
            return .readOnly
        case "READ-WRITE":
            return .readWrite
        case "UIDVALIDITY":
            return .uidValidity(try nonZeroNumber32(arguments, name))
        case "UIDNEXT":
            return .uidNext(try nonZeroNumber32(arguments, name))
        case "CAPABILITY":
            let capabilities = arguments.split(separator: 0x20).map {
                String(decoding: $0, as: UTF8.self).uppercased()
            }
            guard capabilities.count <= limits.maxCapabilities else {
                throw .malformedResponse("a CAPABILITY code listed too many capabilities")
            }
            return .capability(capabilities)
        default:
            return .other(String(name.prefix(64)))
        }
    }

    private static func nonZeroNumber32(_ bytes: [UInt8], _ name: String) throws(IMAPProtocolError) -> UInt32 {
        guard !bytes.isEmpty, bytes.count <= 10, bytes.allSatisfy({ (0x30...0x39).contains($0) }),
            let value = UInt32(String(decoding: bytes, as: UTF8.self)), value > 0
        else { throw .malformedResponse("the \(name) code did not carry a valid non-zero number") }
        return value
    }

    /// IMAP4rev1 `SEARCH *(SP nz-number)`, possibly followed by a CONDSTORE `(MODSEQ n)` group, which is skipped.
    private static func searchResult(_ reader: inout IMAPTokenReader, limits: IMAPParseLimits)
        throws(IMAPProtocolError) -> IMAPUIDSet
    {
        var uids: [UInt32] = []
        while reader.consume(0x20) {
            if reader.peek() == 0x28 {
                try reader.skipValue()
                continue
            }
            uids.append(try reader.readNonZeroNumber32())
            guard uids.count <= limits.maxSearchElements else {
                throw .malformedResponse("a SEARCH result listed too many messages")
            }
        }
        try reader.expectEnd("a SEARCH result")
        return IMAPUIDSet(uids)
    }

    /// `ESEARCH [search-correlator] [SP "UID"] *(SP search-return-data)` (RFC 9051 §9). Only ALL is kept; MIN, MAX,
    /// COUNT and extensions are skipped.
    private static func extendedSearch(_ reader: inout IMAPTokenReader, limits: IMAPParseLimits)
        throws(IMAPProtocolError) -> IMAPExtendedSearch
    {
        var result = IMAPExtendedSearch(isUID: false)
        while reader.consume(0x20) {
            if reader.consume(0x28) {
                guard try reader.readKeyword() == "TAG" else {
                    throw .malformedResponse("an ESEARCH correlator was not a TAG")
                }
                try reader.expectSpace()
                result.tag = String(decoding: try reader.readAString(), as: UTF8.self)
                try reader.expect(0x29, "the end of an ESEARCH correlator")
                continue
            }
            switch try reader.readKeyword() {
            case "UID":
                result.isUID = true
            case "ALL":
                try reader.expectSpace()
                let set = try IMAPUIDSet.parse(reader.readSequenceSet(), maxRanges: limits.maxSearchElements)
                result.all = result.all.union(set)
            default:
                try reader.expectSpace()
                try reader.skipValue()
            }
        }
        try reader.expectEnd("an ESEARCH result")
        return result
    }

    /// `msg-att` (RFC 9051 §9): reads UID, RFC822.SIZE and BODY[]; skips every other item. A UID or size given
    /// twice with different values is malformed.
    private static func fetchData(_ reader: inout IMAPTokenReader) throws(IMAPProtocolError) -> IMAPFetchData {
        try reader.expect(0x28, "the start of FETCH data")
        var data = IMAPFetchData()
        var items = 0
        while !reader.consume(0x29) {
            if items > 0 { try reader.expectSpace() }
            let name = try reader.readKeyword()
            var section: [UInt8]?
            var partial = false
            if reader.peek() == 0x5B {
                section = try reader.readSection()
                if reader.consume(0x3C) {
                    _ = try reader.readNumber()
                    try reader.expect(0x3E, "the end of a partial origin")
                    partial = true
                }
            }
            try reader.expectSpace()
            switch name {
            case "UID" where section == nil:
                let uid = try reader.readNonZeroNumber32()
                guard data.uid == nil || data.uid == uid else { throw .malformedResponse("FETCH data had two UIDs") }
                data.uid = uid
            case "RFC822.SIZE" where section == nil:
                let size = try reader.readNumber()
                guard data.size == nil || data.size == size else {
                    throw .malformedResponse("FETCH data had two sizes")
                }
                data.size = size
            case "BODY" where section == [] && !partial:
                let body = try reader.readNString()
                if data.body == nil { data.body = body.map(IMAPBodyContent.octets) ?? .absent }
            default:
                try reader.skipValue()
            }
            items += 1
        }
        try reader.expectEnd("FETCH data")
        return data
    }
}
