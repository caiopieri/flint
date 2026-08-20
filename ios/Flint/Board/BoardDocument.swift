import Foundation

/// JSON values kept verbatim enough for a Board round-trip. JSON Canvas is an
/// open format, so the MVP must not collapse fields it does not understand.
indirect enum BoardJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([BoardJSONValue])
    case object([String: BoardJSONValue])

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null; return }
        if let value = try? single.decode(Bool.self) { self = .bool(value); return }
        if let value = try? single.decode(Double.self) { self = .number(value); return }
        if let value = try? single.decode(String.self) { self = .string(value); return }
        if let value = try? single.decode([BoardJSONValue].self) { self = .array(value); return }
        self = .object(try single.decode([String: BoardJSONValue].self))
    }

    func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .null: try single.encodeNil()
        case .bool(let value): try single.encode(value)
        case .number(let value): try single.encode(value)
        case .string(let value): try single.encode(value)
        case .array(let value): try single.encode(value)
        case .object(let value): try single.encode(value)
        }
    }
}

struct BoardDocument: Equatable, Sendable {
    static let maxBytes = 5 * 1024 * 1024
    static let maxNodes = 2_000
    static let maxEdges = 4_000
    static let defaultNodeWidth = 320
    static let defaultNodeHeight = 180

    var nodes: [BoardNode]
    var edges: [BoardEdge]
    var extras: [String: BoardJSONValue]

    init(nodes: [BoardNode] = [], edges: [BoardEdge] = [], extras: [String: BoardJSONValue] = [:]) {
        self.nodes = nodes
        self.edges = edges
        self.extras = extras
    }

    static var empty: BoardDocument { BoardDocument() }

    static func decode(_ data: Data) throws -> BoardDocument {
        guard data.count <= maxBytes else { throw BoardDocumentError.tooLarge }
        do {
            let document = try JSONDecoder().decode(WireDocument.self, from: data).document
            try document.validate()
            return document
        } catch let error as BoardDocumentError {
            throw error
        } catch {
            throw BoardDocumentError.invalidJSON
        }
    }

    func encoded() throws -> Data {
        try validate()
        return try JSONEncoder().encode(WireDocument(document: self))
    }

    func validate() throws {
        guard nodes.count <= Self.maxNodes else { throw BoardDocumentError.tooManyNodes }
        guard edges.count <= Self.maxEdges else { throw BoardDocumentError.tooManyEdges }

        var nodeIDs = Set<String>()
        for node in nodes {
            try validateIdentifier(node.id)
            guard nodeIDs.insert(node.id).inserted else { throw BoardDocumentError.duplicateIdentifier(node.id) }
            guard node.width > 0, node.height > 0,
                  node.width <= 10_000, node.height <= 10_000,
                  node.x >= -10_000_000, node.x <= 10_000_000,
                  node.y >= -10_000_000, node.y <= 10_000_000 else {
                throw BoardDocumentError.invalidGeometry(node.id)
            }
            if node.type == "file", let path = node.file {
                guard Self.isSafeRelativePath(path) else { throw BoardDocumentError.invalidPath(path) }
            }
        }

        var edgeIDs = Set<String>()
        for edge in edges {
            try validateIdentifier(edge.id)
            guard edgeIDs.insert(edge.id).inserted else { throw BoardDocumentError.duplicateIdentifier(edge.id) }
            guard nodeIDs.contains(edge.fromNode), nodeIDs.contains(edge.toNode) else {
                throw BoardDocumentError.missingEdgeNode(edge.id)
            }
        }
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, path.count <= 1_024,
              !path.hasPrefix("/"), !path.contains("\\") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return !components.isEmpty && !components.contains { $0 == "." || $0 == ".." }
    }

    func addingMarkdown(path: String, title: String, at origin: BoardPoint) throws -> BoardDocument {
        guard Self.isSafeRelativePath(path), path.lowercased().hasSuffix(".md") else {
            throw BoardDocumentError.invalidPath(path)
        }
        guard !nodes.contains(where: { $0.type == "file" && $0.file == path }) else { return self }
        let node = BoardNode(
            id: UUID().uuidString,
            type: "file",
            x: origin.x,
            y: origin.y,
            width: Self.defaultNodeWidth,
            height: Self.defaultNodeHeight,
            file: path,
            extras: ["flintTitle": .string(title)]
        )
        var result = self
        result.nodes.append(node)
        try result.validate()
        return result
    }

    private func validateIdentifier(_ value: String) throws {
        guard !value.isEmpty, value.count <= 128, !value.contains(where: { $0.isWhitespace }) else {
            throw BoardDocumentError.invalidIdentifier
        }
    }
}

struct BoardPoint: Equatable, Sendable {
    let x: Int
    let y: Int
}

struct BoardNode: Equatable, Sendable {
    let id: String
    let type: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    var color: String?
    var text: String?
    var file: String?
    var subpath: String?
    var url: String?
    var label: String?
    var background: String?
    var backgroundStyle: String?
    var extras: [String: BoardJSONValue]

    init(
        id: String, type: String, x: Int, y: Int, width: Int, height: Int,
        color: String? = nil, text: String? = nil, file: String? = nil,
        subpath: String? = nil, url: String? = nil, label: String? = nil,
        background: String? = nil, backgroundStyle: String? = nil,
        extras: [String: BoardJSONValue] = [:]
    ) {
        self.id = id; self.type = type; self.x = x; self.y = y
        self.width = width; self.height = height; self.color = color
        self.text = text; self.file = file; self.subpath = subpath; self.url = url
        self.label = label; self.background = background; self.backgroundStyle = backgroundStyle
        self.extras = extras
    }
}

struct BoardEdge: Equatable, Sendable {
    let id: String
    let fromNode: String
    let toNode: String
    var fromSide: String?
    var fromEnd: String?
    var toSide: String?
    var toEnd: String?
    var color: String?
    var label: String?
    var extras: [String: BoardJSONValue]

    init(
        id: String, fromNode: String, toNode: String,
        fromSide: String? = nil, fromEnd: String? = nil, toSide: String? = nil,
        toEnd: String? = nil, color: String? = nil, label: String? = nil,
        extras: [String: BoardJSONValue] = [:]
    ) {
        self.id = id; self.fromNode = fromNode; self.toNode = toNode
        self.fromSide = fromSide; self.fromEnd = fromEnd; self.toSide = toSide
        self.toEnd = toEnd; self.color = color; self.label = label; self.extras = extras
    }
}

enum BoardDocumentError: LocalizedError, Equatable {
    case invalidJSON, tooLarge, tooManyNodes, tooManyEdges
    case invalidIdentifier, duplicateIdentifier(String), invalidGeometry(String)
    case invalidPath(String), missingEdgeNode(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "This Board file is not valid JSON Canvas."
        case .tooLarge: return "This Board is too large to open safely."
        case .tooManyNodes: return "This Board has too many nodes."
        case .tooManyEdges: return "This Board has too many edges."
        case .invalidIdentifier: return "This Board contains an invalid identifier."
        case .duplicateIdentifier(let id): return "This Board repeats identifier “\(id)”."
        case .invalidGeometry(let id): return "Node “\(id)” has invalid geometry."
        case .invalidPath(let path): return "The Board path is not allowed: \(path)"
        case .missingEdgeNode(let id): return "Edge “\(id)” references a missing node."
        }
    }
}

private struct WireDocument: Codable {
    let document: BoardDocument

    init(document: BoardDocument) { self.document = document }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        let nodeData = try container.decodeIfPresent([BoardNode].self, forKey: DynamicKey("nodes")) ?? []
        let edgeData = try container.decodeIfPresent([BoardEdge].self, forKey: DynamicKey("edges")) ?? []
        var extras: [String: BoardJSONValue] = [:]
        for key in container.allKeys where key.stringValue != "nodes" && key.stringValue != "edges" {
            extras[key.stringValue] = try container.decode(BoardJSONValue.self, forKey: key)
        }
        document = BoardDocument(nodes: nodeData, edges: edgeData, extras: extras)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(document.nodes, forKey: DynamicKey("nodes"))
        try container.encode(document.edges, forKey: DynamicKey("edges"))
        for (key, value) in document.extras where key != "nodes" && key != "edges" {
            try container.encode(value, forKey: DynamicKey(key))
        }
    }
}

private struct DynamicKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

extension BoardNode: Codable {
    private static let known: Set<String> = ["id", "type", "x", "y", "width", "height", "color", "text", "file", "subpath", "url", "label", "background", "backgroundStyle"]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        id = try c.decode(String.self, forKey: DynamicKey("id")); type = try c.decode(String.self, forKey: DynamicKey("type"))
        x = try c.decode(Int.self, forKey: DynamicKey("x")); y = try c.decode(Int.self, forKey: DynamicKey("y"))
        width = try c.decode(Int.self, forKey: DynamicKey("width")); height = try c.decode(Int.self, forKey: DynamicKey("height"))
        color = try c.decodeIfPresent(String.self, forKey: DynamicKey("color")); text = try c.decodeIfPresent(String.self, forKey: DynamicKey("text")); file = try c.decodeIfPresent(String.self, forKey: DynamicKey("file")); subpath = try c.decodeIfPresent(String.self, forKey: DynamicKey("subpath")); url = try c.decodeIfPresent(String.self, forKey: DynamicKey("url")); label = try c.decodeIfPresent(String.self, forKey: DynamicKey("label")); background = try c.decodeIfPresent(String.self, forKey: DynamicKey("background")); backgroundStyle = try c.decodeIfPresent(String.self, forKey: DynamicKey("backgroundStyle"))
        extras = try Self.decodeExtras(c)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        try c.encode(id, forKey: DynamicKey("id")); try c.encode(type, forKey: DynamicKey("type")); try c.encode(x, forKey: DynamicKey("x")); try c.encode(y, forKey: DynamicKey("y")); try c.encode(width, forKey: DynamicKey("width")); try c.encode(height, forKey: DynamicKey("height"))
        try c.encodeIfPresent(color, forKey: DynamicKey("color")); try c.encodeIfPresent(text, forKey: DynamicKey("text")); try c.encodeIfPresent(file, forKey: DynamicKey("file")); try c.encodeIfPresent(subpath, forKey: DynamicKey("subpath")); try c.encodeIfPresent(url, forKey: DynamicKey("url")); try c.encodeIfPresent(label, forKey: DynamicKey("label")); try c.encodeIfPresent(background, forKey: DynamicKey("background")); try c.encodeIfPresent(backgroundStyle, forKey: DynamicKey("backgroundStyle"))
        for (key, value) in extras where !Self.known.contains(key) { try c.encode(value, forKey: DynamicKey(key)) }
    }

    private static func decodeExtras(_ c: KeyedDecodingContainer<DynamicKey>) throws -> [String: BoardJSONValue] {
        var result: [String: BoardJSONValue] = [:]
        for key in c.allKeys where !known.contains(key.stringValue) { result[key.stringValue] = try c.decode(BoardJSONValue.self, forKey: key) }
        return result
    }
}

extension BoardEdge: Codable {
    private static let known: Set<String> = ["id", "fromNode", "fromSide", "fromEnd", "toNode", "toSide", "toEnd", "color", "label"]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        id = try c.decode(String.self, forKey: DynamicKey("id")); fromNode = try c.decode(String.self, forKey: DynamicKey("fromNode")); toNode = try c.decode(String.self, forKey: DynamicKey("toNode"))
        fromSide = try c.decodeIfPresent(String.self, forKey: DynamicKey("fromSide")); fromEnd = try c.decodeIfPresent(String.self, forKey: DynamicKey("fromEnd")); toSide = try c.decodeIfPresent(String.self, forKey: DynamicKey("toSide")); toEnd = try c.decodeIfPresent(String.self, forKey: DynamicKey("toEnd")); color = try c.decodeIfPresent(String.self, forKey: DynamicKey("color")); label = try c.decodeIfPresent(String.self, forKey: DynamicKey("label"))
        extras = try Self.decodeExtras(c)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        try c.encode(id, forKey: DynamicKey("id")); try c.encode(fromNode, forKey: DynamicKey("fromNode")); try c.encode(toNode, forKey: DynamicKey("toNode")); try c.encodeIfPresent(fromSide, forKey: DynamicKey("fromSide")); try c.encodeIfPresent(fromEnd, forKey: DynamicKey("fromEnd")); try c.encodeIfPresent(toSide, forKey: DynamicKey("toSide")); try c.encodeIfPresent(toEnd, forKey: DynamicKey("toEnd")); try c.encodeIfPresent(color, forKey: DynamicKey("color")); try c.encodeIfPresent(label, forKey: DynamicKey("label"))
        for (key, value) in extras where !Self.known.contains(key) { try c.encode(value, forKey: DynamicKey(key)) }
    }

    private static func decodeExtras(_ c: KeyedDecodingContainer<DynamicKey>) throws -> [String: BoardJSONValue] {
        var result: [String: BoardJSONValue] = [:]
        for key in c.allKeys where !known.contains(key.stringValue) { result[key.stringValue] = try c.decode(BoardJSONValue.self, forKey: key) }
        return result
    }
}
