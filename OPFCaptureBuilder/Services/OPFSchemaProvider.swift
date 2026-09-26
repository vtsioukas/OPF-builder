//
//  OPFSchemaProvider.swift
//  OPFCaptureBuilder
//
//  Loads the vendored official OPF JSON schemas from the app bundle. The schemas ship as
//  a folder reference (`Resources/OPFSchemas`) so the directory structure is preserved.
//

import Foundation

enum OPFSchemaProvider {

    private static var cache: [String: [String: Any]] = [:]
    private static let lock = NSLock()

    /// Returns the parsed schema with the given file name, e.g. "input_cameras.schema.json".
    static func schema(named name: String) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[name] { return cached }

        guard let url = locateSchema(named: name),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        cache[name] = object
        return object
    }

    /// All schema file names available in the bundle, sorted alphabetically.
    static func availableSchemaNames() -> [String] {
        guard let directory = schemaDirectory() else { return [] }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return contents.filter { $0.hasSuffix(".schema.json") }.sorted()
    }

    /// The folder containing the vendored OPF examples, used by the sample-project feature.
    static var examplesDirectory: URL? {
        bundleOPFSchemasDirectory()?.appendingPathComponent("examples", isDirectory: true)
    }

    static var attributionDocument: URL? {
        bundleOPFSchemasDirectory()?.appendingPathComponent("ATTRIBUTION.md", isDirectory: false)
    }

    // MARK: - Private

    private static func bundleOPFSchemasDirectory() -> URL? {
        // The folder reference is copied verbatim into the bundle.
        if let direct = Bundle.main.url(forResource: "OPFSchemas", withExtension: nil),
           FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        // Fall back to a flattened resource lookup (belt and braces for resource copying modes).
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("OPFSchemas", isDirectory: true),
           FileManager.default.fileExists(atPath: resource.path) {
            return resource
        }
        return nil
    }

    private static func schemaDirectory() -> URL? {
        bundleOPFSchemasDirectory()?.appendingPathComponent("schema", isDirectory: true)
    }

    private static func locateSchema(named name: String) -> URL? {
        if let directory = schemaDirectory() {
            let candidate = directory.appendingPathComponent(name, isDirectory: false)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "OPFSchemas/schema")
            ?? Bundle.main.url(forResource: name, withExtension: nil)
    }
}
