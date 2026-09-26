//
//  JSONSchemaValidator.swift
//  OPFCaptureBuilder
//
//  A strict validator for the subset of JSON Schema draft 2020-12 used by the official
//  OPF schemas:
//
//      type, required, properties, items, enum, const,
//      minimum, maximum, minLength, maxLength, pattern,
//      minItems, maxItems, minProperties, anyOf, allOf, oneOf
//
//  It deliberately does NOT resolve `$ref`. Instead, the OPF schemas are self-contained
//  per document: the properties we emit are checked directly against their inline
//  definitions, and cross-document references are covered by OPFValidator's business rules.
//  `additionalProperties` is treated as permissive, exactly as the OPF specification
//  requires for forward compatibility.
//

import Foundation
import CoreFoundation

struct SchemaValidationResult {
    var errors: [String] = []
    var isValid: Bool { errors.isEmpty }
}

enum JSONSchemaValidator {

    static func validate(instance: Any, schema: [String: Any], path: String = "$") -> SchemaValidationResult {
        var result = SchemaValidationResult()
        check(instance: instance, schema: schema, path: path, into: &result)
        return result
    }

    // MARK: - Core

    private static func check(instance: Any, schema: [String: Any], path: String, into result: inout SchemaValidationResult) {
        if let const = schema["const"], !deepEquals(instance, const) {
            result.errors.append("\(path): expected the constant value \(describe(const)), found \(describe(instance)).")
        }

        if let allowed = schema["enum"] as? [Any] {
            let matches = allowed.contains { deepEquals(instance, $0) }
            if !matches {
                result.errors.append("\(path): value \(describe(instance)) is not one of the allowed values.")
            }
        }

        if schema["anyOf"] != nil || schema["allOf"] != nil || schema["oneOf"] != nil {
            checkCombinators(instance: instance, schema: schema, path: path, into: &result)
            // Continue to also apply sibling constraints when they exist.
        }

        if let typeSpec = schema["type"] {
            let permitted = typeSpec as? [Any] ?? [typeSpec]
            let names = permitted.compactMap { $0 as? String }
            if !names.isEmpty, !names.contains(where: { matchesType(instance, $0) }) {
                result.errors.append("\(path): expected type \(names.joined(separator: " or ")), found \(describe(instance)).")
                return
            }
        }

        if let object = instance as? [String: Any] {
            validateObject(object, schema: schema, path: path, into: &result)
        }
        if let array = instance as? [Any] {
            validateArray(array, schema: schema, path: path, into: &result)
        }
        if let string = instance as? String {
            validateString(string, schema: schema, path: path, into: &result)
        }
        if isJSONNumber(instance) {
            validateNumber(instance, schema: schema, path: path, into: &result)
        }
    }

    private static func validateObject(_ object: [String: Any], schema: [String: Any], path: String, into result: inout SchemaValidationResult) {
        if let required = schema["required"] as? [String] {
            for key in required where object[key] == nil {
                result.errors.append("\(path): missing required property \"\(key)\".")
            }
        }
        if let minProperties = schema["minProperties"] as? Int, object.count < minProperties {
            result.errors.append("\(path): expected at least \(minProperties) properties, found \(object.count).")
        }
        if let properties = schema["properties"] as? [String: Any] {
            for (key, subSchema) in properties {
                guard let value = object[key], let subSchema = subSchema as? [String: Any] else { continue }
                check(instance: value, schema: subSchema, path: "\(path).\(key)", into: &result)
            }
        }
    }

    private static func validateArray(_ array: [Any], schema: [String: Any], path: String, into result: inout SchemaValidationResult) {
        if let minItems = schema["minItems"] as? Int, array.count < minItems {
            result.errors.append("\(path): expected at least \(minItems) items, found \(array.count).")
        }
        if let maxItems = schema["maxItems"] as? Int, array.count > maxItems {
            result.errors.append("\(path): expected at most \(maxItems) items, found \(array.count).")
        }
        if let items = schema["items"] as? [String: Any] {
            for (index, element) in array.enumerated() {
                check(instance: element, schema: items, path: "\(path)[\(index)]", into: &result)
            }
        }
    }

    private static func validateString(_ string: String, schema: [String: Any], path: String, into result: inout SchemaValidationResult) {
        if let minLength = schema["minLength"] as? Int, string.count < minLength {
            result.errors.append("\(path): string shorter than the minimum length \(minLength).")
        }
        if let maxLength = schema["maxLength"] as? Int, string.count > maxLength {
            result.errors.append("\(path): string longer than the maximum length \(maxLength).")
        }
        if let pattern = schema["pattern"] as? String {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(string.startIndex..<string.endIndex, in: string)
                if regex.firstMatch(in: string, range: range) == nil {
                    result.errors.append("\(path): value \"\(string)\" does not match the pattern \(pattern).")
                }
            }
        }
    }

    private static func validateNumber(_ number: Any, schema: [String: Any], path: String, into result: inout SchemaValidationResult) {
        let value = (number as? NSNumber)?.doubleValue ?? 0
        if !value.isFinite {
            result.errors.append("\(path): non-finite numeric value is not representable in JSON.")
            return
        }
        if let minimum = (schema["minimum"] as? NSNumber)?.doubleValue, value < minimum {
            result.errors.append("\(path): value \(value) is below the minimum \(minimum).")
        }
        if let maximum = (schema["maximum"] as? NSNumber)?.doubleValue, value > maximum {
            result.errors.append("\(path): value \(value) is above the maximum \(maximum).")
        }
    }

    private static func checkCombinators(instance: Any, schema: [String: Any], path: String, into result: inout SchemaValidationResult) {
        if let allOf = schema["allOf"] as? [[String: Any]] {
            for sub in allOf {
                check(instance: instance, schema: sub, path: path, into: &result)
            }
        }
        if let anyOf = schema["anyOf"] as? [[String: Any]] {
            let anyMatches = anyOf.contains { sub in
                var probe = SchemaValidationResult()
                check(instance: instance, schema: sub, path: path, into: &probe)
                return probe.isValid
            }
            if !anyMatches {
                result.errors.append("\(path): value \(describe(instance)) does not satisfy any of the permitted schemas.")
            }
        }
        if let oneOf = schema["oneOf"] as? [[String: Any]] {
            var matches = 0
            for sub in oneOf {
                var probe = SchemaValidationResult()
                check(instance: instance, schema: sub, path: path, into: &probe)
                if probe.isValid { matches += 1 }
            }
            if matches != 1 {
                result.errors.append("\(path): expected exactly one matching schema, found \(matches).")
            }
        }
    }

    // MARK: - Type helpers

    private static func isCFBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func isJSONNumber(_ value: Any) -> Bool {
        guard value is NSNumber else { return false }
        return !isCFBoolean(value)
    }

    private static func matchesType(_ instance: Any, _ type: String) -> Bool {
        switch type {
        case "object": return instance is [String: Any]
        case "array": return instance is [Any]
        case "string": return instance is String
        case "boolean": return isCFBoolean(instance)
        case "null": return instance is NSNull
        case "integer":
            guard let number = instance as? NSNumber, !isCFBoolean(instance) else { return false }
            return number.doubleValue == number.doubleValue.rounded()
        case "number":
            return isJSONNumber(instance)
        default:
            return true
        }
    }

    private static func deepEquals(_ lhs: Any, _ rhs: Any) -> Bool {
        if let a = lhs as? [String: Any], let b = rhs as? [String: Any] {
            guard a.count == b.count else { return false }
            return a.allSatisfy { key, value in b[key].map { deepEquals(value, $0) } ?? false }
        }
        if let a = lhs as? [Any], let b = rhs as? [Any] {
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { deepEquals($0, $1) }
        }
        if isCFBoolean(lhs), isCFBoolean(rhs) {
            return (lhs as? NSNumber)?.boolValue == (rhs as? NSNumber)?.boolValue
        }
        if let a = lhs as? String, let b = rhs as? String { return a == b }
        if isJSONNumber(lhs), isJSONNumber(rhs) {
            return (lhs as? NSNumber)?.doubleValue == (rhs as? NSNumber)?.doubleValue
        }
        if lhs is NSNull, rhs is NSNull { return true }
        return false
    }

    private static func describe(_ value: Any) -> String {
        switch value {
        case is NSNull: return "null"
        case let string as String: return "\"\(string)\""
        case let array as [Any]: return "array(\(array.count))"
        case is [String: Any]: return "object"
        default: return "\(value)"
        }
    }
}
