import Foundation

/// A parsed JSON node. `.null` and "missing key" both surface as a non-matching case,
/// so callers never distinguish a missing key from an explicit `null`.
enum JSONValue: Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    /// Decode a top-level payload from raw response bytes. Returns `.null` on any
    /// malformed input (never throws) so the caller can keep degrading defensively.
    static func decode(_ data: Data) -> JSONValue {
        guard let obj = try? JSONSerialization.jsonObject(
            with: data, options: [.fragmentsAllowed]
        ) else { return .null }
        return JSONValue(any: obj)
    }

    /// Wrap a `JSONSerialization` `Any` graph into the typed tree.
    init(any: Any) {
        switch any {
        case let dict as [String: Any]:
            var out: [String: JSONValue] = [:]
            out.reserveCapacity(dict.count)
            for (k, v) in dict { out[k] = JSONValue(any: v) }
            self = .object(out)
        case let arr as [Any]:
            self = .array(arr.map(JSONValue.init(any:)))
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .number(n.doubleValue)
            }
        case let s as String:
            self = .string(s)
        case is NSNull:
            self = .null
        default:
            self = .null
        }
    }
}

extension JSONValue {
    /// The object's children, or an empty dictionary when this isn't an object.
    var objectValue: [String: JSONValue] {
        if case let .object(o) = self { return o }
        return [:]
    }

    /// True when this node is a JSON object.
    var isObject: Bool {
        if case .object = self { return true }
        return false
    }

    /// The array's elements, or `[]` when this isn't an array.
    var arrayValue: [JSONValue] {
        if case let .array(a) = self { return a }
        return []
    }

    /// The string value, or `nil` when this isn't a string.
    var stringValue: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    /// A bool from a JSON bool (or a "true"/"false" string), else `nil`.
    var boolValue: Bool? {
        switch self {
        case let .bool(b): return b
        case let .string(s): return s == "true" ? true : (s == "false" ? false : nil)
        default: return nil
        }
    }

    /// A finite number from a JSON number or a numeric string (commas stripped), else `nil`.
    /// Display strings like "5,322" parse.
    var numberValue: Double? {
        switch self {
        case let .number(n):
            return n.isFinite ? n : nil
        case let .string(s):
            let cleaned = s.replacing(",", with: "")
            guard let n = Double(cleaned), n.isFinite else { return nil }
            return n
        default:
            return nil
        }
    }

    /// Key subscript: a missing key (or non-object self) yields `.null` so chains like
    /// `home["metadata"]["cycle_metadata"]` never trap.
    subscript(_ key: String) -> JSONValue {
        if case let .object(o) = self { return o[key] ?? .null }
        return .null
    }
}
