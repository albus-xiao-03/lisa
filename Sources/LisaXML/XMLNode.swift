// A Swift-owned XML/HTML tree copied out of libxml2, so no C memory escapes the reader.

/// An element or text node.
public struct XMLNode: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case element
        case text
    }

    public var kind: Kind
    /// The local name of an element; empty for text.
    public var name: String
    public var namespaceURI: String?
    /// Attribute values by local name.
    public var attributes: [String: String]
    public var children: [XMLNode]
    /// The text of a text node.
    public var text: String

    public init(
        kind: Kind, name: String, namespaceURI: String? = nil, attributes: [String: String] = [:],
        children: [XMLNode] = [], text: String = ""
    ) {
        self.kind = kind
        self.name = name
        self.namespaceURI = namespaceURI
        self.attributes = attributes
        self.children = children
        self.text = text
    }

    /// Child elements, optionally filtered by local name and namespace.
    public func elements(_ name: String? = nil, namespace: String? = nil) -> [XMLNode] {
        children.filter { child in
            child.kind == .element && (name == nil || child.name.caseInsensitiveEquals(name!))
                && (namespace == nil || child.namespaceURI == namespace)
        }
    }

    /// The first child element with `name`.
    public func element(_ name: String, namespace: String? = nil) -> XMLNode? {
        elements(name, namespace: namespace).first
    }

    /// The concatenated text of this node and its descendants.
    public var textContent: String {
        switch kind {
        case .text: text
        case .element: children.map(\.textContent).joined()
        }
    }
}

extension String {
    fileprivate func caseInsensitiveEquals(_ other: String) -> Bool {
        lowercased() == other.lowercased()
    }
}
