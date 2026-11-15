// Reads untrusted XML and HTML with libxml2 configured for safety: no network, no external or DTD entities, bounded.

import CLibXML2
import Foundation

/// Bounds for one document.
public struct XMLReadLimits: Hashable, Sendable {
    public var maxBytes: Int
    public var maxNodes: Int
    public var maxDepth: Int
    public var maxTextBytes: Int

    public init(maxBytes: Int = 10_000_000, maxNodes: Int = 200_000, maxDepth: Int = 200, maxTextBytes: Int = 8_000_000)
    {
        self.maxBytes = maxBytes
        self.maxNodes = maxNodes
        self.maxDepth = maxDepth
        self.maxTextBytes = maxTextBytes
    }
}

/// Why a document was not read.
public enum XMLReadError: Error, Hashable, Sendable, CustomStringConvertible {
    case tooLarge
    case empty
    case malformed
    /// The document declares entities or an external DTD, which Lisa never processes.
    case forbiddenDocumentType
    case limitExceeded(String)

    public var description: String {
        switch self {
        case .tooLarge: "the document exceeds the configured size limit"
        case .empty: "the document is empty"
        case .malformed: "the document is not well-formed XML"
        case .forbiddenDocumentType: "the document declares entities or an external DTD, which are refused"
        case .limitExceeded(let what): "the document exceeds the \(what) limit"
        }
    }
}

/// A parsed document.
public struct XMLDocumentResult: Hashable, Sendable {
    public var root: XMLNode
    /// True when libxml2 had to recover from errors; the result may be partial and is labeled as such.
    public var recovered: Bool
    /// How many undefined entity references were rewritten before parsing (see `EntityNormalizer`).
    public var normalizedEntityReferences: Int
}

/// The only entry point Lisa uses to read XML and HTML.
public enum SafeXMLReader {
    /// One-time libxml2 setup: initialize the parser and refuse every external entity load.
    private static let setUp: Void = {
        xmlInitParser()
        xmlSetExternalEntityLoader { _, _, _ in nil }
    }()

    /// Parses XML. A document that is not well-formed is retried in recovery mode and marked `recovered`.
    public static func parseXML(_ data: Data, limits: XMLReadLimits = XMLReadLimits()) throws -> XMLDocumentResult {
        _ = setUp
        guard data.count <= limits.maxBytes else { throw XMLReadError.tooLarge }
        guard !data.isEmpty else { throw XMLReadError.empty }
        let (normalized, rewritten) = EntityNormalizer.normalize(data)
        if let strict = try read(normalized, recover: false, limits: limits) {
            return XMLDocumentResult(root: strict, recovered: false, normalizedEntityReferences: rewritten)
        }
        guard let recovered = try read(normalized, recover: true, limits: limits) else { throw XMLReadError.malformed }
        return XMLDocumentResult(root: recovered, recovered: true, normalizedEntityReferences: rewritten)
    }

    /// Parses HTML leniently (HTML is never "well-formed"); no network access, no external resources.
    public static func parseHTML(_ text: String, limits: XMLReadLimits = XMLReadLimits()) throws -> XMLNode {
        _ = setUp
        let data = Data(text.utf8)
        guard data.count <= limits.maxBytes else { throw XMLReadError.tooLarge }
        guard let context = htmlNewParserCtxt() else { throw XMLReadError.malformed }
        defer { htmlFreeParserCtxt(context) }
        let options = Int32(
            HTML_PARSE_NONET.rawValue | HTML_PARSE_NOERROR.rawValue | HTML_PARSE_NOWARNING.rawValue
                | HTML_PARSE_RECOVER.rawValue | HTML_PARSE_NOIMPLIED.rawValue)
        let document = data.withUnsafeBytes { raw in
            htmlCtxtReadMemory(
                context, raw.baseAddress?.assumingMemoryBound(to: CChar.self), Int32(data.count), nil, "UTF-8", options)
        }
        guard let document else { return XMLNode(kind: .element, name: "html") }
        defer { xmlFreeDoc(document) }
        var budget = Budget(limits: limits)
        var root = XMLNode(kind: .element, name: "html")
        var child = document.pointee.children
        while let node = child {
            if let converted = try convert(node, depth: 0, budget: &budget) { root.children.append(converted) }
            child = node.pointee.next
        }
        return root
    }

    private static func read(_ data: Data, recover: Bool, limits: XMLReadLimits) throws -> XMLNode? {
        guard let context = xmlNewParserCtxt() else { return nil }
        defer { xmlFreeParserCtxt(context) }
        var options =
            XML_PARSE_NONET.rawValue | XML_PARSE_NOCDATA.rawValue | XML_PARSE_NOERROR.rawValue
            | XML_PARSE_NOWARNING.rawValue
        if recover { options |= XML_PARSE_RECOVER.rawValue }
        let document = data.withUnsafeBytes { raw in
            xmlCtxtReadMemory(
                context, raw.baseAddress?.assumingMemoryBound(to: CChar.self), Int32(data.count), nil, nil,
                Int32(options))
        }
        guard let document else { return nil }
        defer { xmlFreeDoc(document) }
        if document.pointee.extSubset != nil { throw XMLReadError.forbiddenDocumentType }
        if let subset = document.pointee.intSubset, subset.pointee.entities != nil || subset.pointee.pentities != nil {
            throw XMLReadError.forbiddenDocumentType
        }
        if !recover, context.pointee.wellFormed == 0 { return nil }
        guard let rootElement = xmlDocGetRootElement(document) else { return nil }
        var budget = Budget(limits: limits)
        return try convert(rootElement, depth: 0, budget: &budget)
    }

    private struct Budget {
        let limits: XMLReadLimits
        var nodes = 0
        var textBytes = 0
    }

    private static func convert(_ node: xmlNodePtr, depth: Int, budget: inout Budget) throws -> XMLNode? {
        budget.nodes += 1
        guard budget.nodes <= budget.limits.maxNodes else { throw XMLReadError.limitExceeded("node count") }
        guard depth <= budget.limits.maxDepth else { throw XMLReadError.limitExceeded("nesting depth") }
        switch node.pointee.type {
        case XML_TEXT_NODE, XML_CDATA_SECTION_NODE:
            let text = node.pointee.content.map { String(cString: $0) } ?? ""
            budget.textBytes += text.utf8.count
            guard budget.textBytes <= budget.limits.maxTextBytes else { throw XMLReadError.limitExceeded("text size") }
            return XMLNode(kind: .text, name: "", text: text)
        case XML_ENTITY_REF_NODE:
            // An entity Lisa does not expand stays visible as written instead of silently disappearing.
            let name = node.pointee.name.map { String(cString: $0) } ?? ""
            return XMLNode(kind: .text, name: "", text: "&\(name);")
        case XML_ELEMENT_NODE:
            var element = XMLNode(
                kind: .element, name: node.pointee.name.map { String(cString: $0) } ?? "",
                namespaceURI: node.pointee.ns?.pointee.href.map { String(cString: $0) })
            var attribute = node.pointee.properties
            while let current = attribute {
                let name = current.pointee.name.map { String(cString: $0) } ?? ""
                var value = ""
                var valueNode = current.pointee.children
                while let piece = valueNode {
                    if piece.pointee.type == XML_ENTITY_REF_NODE {
                        value += "&" + (piece.pointee.name.map { String(cString: $0) } ?? "") + ";"
                    } else if let content = piece.pointee.content {
                        value += String(cString: content)
                    }
                    valueNode = piece.pointee.next
                }
                element.attributes[name] = value
                attribute = current.pointee.next
            }
            var child = node.pointee.children
            while let current = child {
                if let converted = try convert(current, depth: depth + 1, budget: &budget) {
                    element.children.append(converted)
                }
                child = current.pointee.next
            }
            return element
        default:
            return nil
        }
    }
}
