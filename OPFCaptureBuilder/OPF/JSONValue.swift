//
//  JSONValue.swift
//  OPFCaptureBuilder
//
//  A small JSON document model with three properties that matter for OPF:
//   1. Property insertion order is preserved (deterministic output).
//   2. Keys are unique (the OPF specification forbids duplicate keys).
//   3. Non-finite numbers are rejected at serialisation time, because JSON
//      has no representation for NaN or Infinity.
//

import Foundation

/// Error types raised while building or serialising an OPF JSON document.
enum OPFWriterError: Error, LocalizedError, Equatable {
    case nonFiniteNumber(path: String, value: Double)
    case unsupportedValue(path: String)
    case encodingFailed(path: String)

    var errorDescription: String? {
        switch self {
        case let .nonFiniteNumber(path, value):
            return "Non-finite number (\(value)) at JSON path \(path). JSON cannot represent NaN or Infinity."
        case let .unsupportedValue(path):
            return "A value at JSON path \(path) could not be represented as JSON."
        case let .encodingFailed(path):
            return "Failed to UTF-8 encode the JSON document (path \(path))."
        }
    }
}

/// An ordered JSON object. Insertion order is preserved when serialising.
struct JSONObject {
    private(set) var pairs: [(key: String, value: JSONValue)] = []

    init() {}

    init(_ pairs: [(String, JSONValue)]) {
        for (key, value) in pairs { self[key] = value }
    }

    /// Replaces an existing key in place, otherwise appends. Guarantees uniqueness.
    subscript(key: String) -> JSONValue? {
        get { pairs.first(where: { $0.key == key })?.value }
        set {
            if let index = pairs.firstIndex(where: { $0.key == key }) {
                if let newValue {
                    pairs[index].value = newValue
                } else {
                    pairs.remove(at: index)
                }
            } else if let newValue {
                pairs.append((key: key, value: newValue))
            }
        }
    }

    var keys: [String] { pairs.map(\.key) }
    var isEmpty: Bool { pairs.isEmpty }
    var count: Int { pairs.count }
}

/// A JSON value tree.
indirect enum JSONValue {
    case null
    case bool(Bool)
    case int(Int)
    case uint64(UInt64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    // MARK: Convenience constructors

    /// Wraps a Double, mapping any non-finite value to `nil` so callers can decide
    /// how to degrade gracefully instead of emitting invalid JSON.
    static func finite(_ value: Double) -> JSONValue? {
        guard value.isFinite else { return nil }
        return .double(value)
    }

    static func numbers(_ values: [Double]) -> JSONValue {
        .array(values.map { .double($0) })
    }

    static func strings(_ values: [String]) -> JSONValue {
        .array(values.map { .string($0) })
    }

    // MARK: Serialisation

    /// Serialises to UTF-8 `Data`. Throws if the tree contains non-finite numbers.
    func serialized(pretty: Bool = true) throws -> Data {
        var out = ""
        try write(into: &out, indent: 0, pretty: pretty, path: "$")
        guard let data = out.data(using: .utf8) else {
            throw OPFWriterError.encodingFailed(path: "$")
        }
        return data
    }

    /// Serialises to a `String`. Throws if the tree contains non-finite numbers.
    func serializedString(pretty: Bool = true) throws -> String {
        var out = ""
        try write(into: &out, indent: 0, pretty: pretty, path: "$")
        return out
    }

    private func write(into out: inout String, indent: Int, pretty: Bool, path: String) throws {
        let pad = pretty ? String(repeating: "  ", count: indent) : ""
        let childPad = pretty ? String(repeating: "  ", count: indent + 1) : ""

        switch self {
        case .null:
            out += "null"

        case let .bool(value):
            out += value ? "true" : "false"

        case let .int(value):
            out += String(value)

        case let .uint64(value):
            out += String(value)

        case let .double(value):
            guard value.isFinite else {
                throw OPFWriterError.nonFiniteNumber(path: path, value: value)
            }
            out += JSONValue.canonicalNumber(value)

        case let .string(value):
            out += JSONValue.escapedString(value)

        case let .array(items):
            if items.isEmpty {
                out += "[]"
                break
            }
            if pretty {
                out += "[\n"
                for (index, item) in items.enumerated() {
                    out += childPad
                    try item.write(into: &out, indent: indent + 1, pretty: pretty, path: "\(path)[\(index)]")
                    out += index == items.count - 1 ? "\n" : ",\n"
                }
                out += pad + "]"
            } else {
                out += "["
                for (index, item) in items.enumerated() {
                    if index > 0 { out += "," }
                    try item.write(into: &out, indent: indent, pretty: pretty, path: "\(path)[\(index)]")
                }
                out += "]"
            }

        case let .object(object):
            if object.isEmpty {
                out += "{}"
                break
            }
            if pretty {
                out += "{\n"
                for (index, pair) in object.pairs.enumerated() {
                    out += childPad + JSONValue.escapedString(pair.key) + ": "
                    try pair.value.write(into: &out, indent: indent + 1, pretty: pretty, path: "\(path).\(pair.key)")
                    out += index == object.count - 1 ? "\n" : ",\n"
                }
                out += pad + "}"
            } else {
                out += "{"
                for (index, pair) in object.pairs.enumerated() {
                    if index > 0 { out += "," }
                    out += JSONValue.escapedString(pair.key) + ":"
                    try pair.value.write(into: &out, indent: indent, pretty: pretty, path: "\(path).\(pair.key)")
                }
                out += "}"
            }
        }
    }

    /// A locale-independent number formatter. Integral doubles are printed without a
    /// fractional part; everything else uses Swift's shortest round-tripping description.
    static func canonicalNumber(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 9_007_199_254_740_992 {
            return String(Int64(value))
        }
        return String(value)
    }

    /// RFC 8259 compliant string escaping.
    static func escapedString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}

// MARK: - Ergonomic builders

extension JSONValue {
    static func `if`(_ condition: Bool, _ value: @autoclosure () -> JSONValue) -> JSONValue? {
        condition ? value() : nil
    }

    /// Bridges to Foundation containers so the `JSONSchemaValidator` can operate on the
    /// same tree that gets written to disk.
    var foundationObject: Any {
        switch self {
        case .null: return NSNull()
        case let .bool(value): return value
        case let .int(value): return value
        case let .uint64(value): return value
        case let .double(value): return value
        case let .string(value): return value
        case let .array(items): return items.map(\.foundationObject)
        case let .object(object):
            var dictionary: [String: Any] = [:]
            for pair in object.pairs { dictionary[pair.key] = pair.value.foundationObject }
            return dictionary
        }
    }
}

extension JSONObject {
    /// Inserts a value only when it is non-nil. Keeps generated documents free of
    /// placeholder `null`s for optional OPF properties.
    mutating func setOptional(_ key: String, _ value: JSONValue?) {
        if let value { self[key] = value }
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) { self = .int(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) { self = .double(value) }
}
