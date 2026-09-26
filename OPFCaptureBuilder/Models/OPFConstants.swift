//
//  OPFConstants.swift
//  OPFCaptureBuilder
//
//  Constants taken verbatim from the Open Photogrammetry Format specification v1.0.
//  Every string here maps to a `const` or `enum` in the official JSON schemas.
//

import Foundation

enum OPFConstants {
    /// OPF version implemented by this app.
    static let version = "1.0"

    enum Format {
        static let project = "application/opf-project+json"
        static let cameraList = "application/opf-camera-list+json"
        static let inputCameras = "application/opf-input-cameras+json"
        static let sceneReferenceFrame = "application/opf-scene-reference-frame+json"
    }

    enum ResourceType {
        static let cameraList = "camera_list"
        static let inputCameras = "input_cameras"
        static let sceneReferenceFrame = "scene_reference_frame"
    }

    /// The only CRS the MVP claims: WGS 84 geographic. Per ISO 19111 the third axis of
    /// a WGS 84 geographic CRS is ellipsoidal height, which is exactly what CoreLocation
    /// provides. We never upgrade this to an orthometric definition.
    static let defaultCRSDefinition = "EPSG:4326"

    /// Registry of `uid_generator` names reserved by the OPF specification.
    static let specVendor = "opf"

    enum Layout {
        static let projectFile = "project.opf"
        static let cameraListFile = "camera-list.json"
        static let inputCamerasFile = "input-cameras.json"
        static let sceneReferenceFrameFile = "scene-reference-frame.json"
        static let imagesDirectory = "images"
        static let projectMetadataFile = "project.json"
        static let validationReportFile = "validation-report.txt"
    }

    /// The generator block written into `project.opf`.
    static let generatorName = "OPF Capture Builder"
    static let generatorVersion = "1.0"
}

// MARK: - Date formatting

enum OPFDateFormat {
    /// ISO 8601 formatted in UTC. The OPF spec requires that when the timezone is known
    /// the time is given as UTC; CoreLocation and CoreMotion timestamps are absolute.
    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    /// Human readable form for the UI, localised to the user's locale.
    static func localized(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Identifier rules

/// Structural rules for identifiers, expressed once so the writer and the validator agree.
enum OPFIdentifier {
    /// `uid64` in the official schema: integer, 0 ... 2^64 - 1.
    static func isValidUID64(_ value: UInt64) -> Bool { true }

    /// UUID pattern used by `uuid.schema.json`.
    static let uuidPattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

    private static let uuidRegex = try? NSRegularExpression(pattern: uuidPattern)

    static func isValidUUIDString(_ value: String) -> Bool {
        guard let uuidRegex else { return UUID(uuidString: value) != nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return uuidRegex.firstMatch(in: value, range: range) != nil
    }

    /// Lower-case UUID string, matching the schema pattern.
    static func uuidString(_ uuid: UUID) -> String {
        uuid.uuidString.lowercased()
    }
}
