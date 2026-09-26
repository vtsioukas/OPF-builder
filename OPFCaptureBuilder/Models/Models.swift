//
//  Models.swift
//  OPFCaptureBuilder
//
//  Domain model for a capture project. Everything here is persisted on device only.
//  Fields that describe *unavailable* information are optional and must stay nil:
//  the app never invents coordinates, accuracies, calibration or orientation.
//

import Foundation

// MARK: - Project

/// A capture project, persisted as `project.json` inside its own folder.
struct CaptureProject: Identifiable, Codable, Hashable {
    var id: UUID
    /// OPF `name` (required, may be renamed).
    var name: String
    /// OPF `description` (required; empty string is a valid value).
    var description: String
    var createdAt: Date
    var updatedAt: Date

    /// Whether to write an `application/opf-scene-reference-frame+json` resource.
    var emitSceneReferenceFrame: Bool = false
    /// CRS definition string, e.g. "EPSG:4326". Used for `geolocation.crs` and the scene frame.
    var crsDefinition: String = OPFConstants.defaultCRSDefinition
    /// Optional constant geoid height (metres). Only used when the user supplies it.
    var geoidHeight: Double? = nil
    /// Export originals in place (false) or transcode to JPEG on import (true).
    /// Original pixels are never modified without telling the user.
    var exportAsJPEG: Bool = false
    /// True once the user has acknowledged the ellipsoidal/orthometric altitude note.
    var acknowledgedAltitudeWarning: Bool = false

    /// Whether to write CoreMotion device attitude into the OPF capture `orientation`.
    /// Off by default, because device attitude is not photogrammetric camera orientation
    /// and because OPF requires an angular sigma we cannot measure. When the user turns
    /// this on they explicitly supply the sigma below, so nothing is fabricated.
    var exportEstimatedOrientation: Bool = false
    /// User-supplied standard deviation (degrees) for the estimated orientation export.
    var orientationSigmaDeg: Double = 5.0

    /// All photographs belonging to the project, in capture/import order.
    var images: [ImageRecord] = []

    /// Verified intrinsics entered by the user, keyed by sensor signature.
    /// When a signature is absent here the sensor is reported as estimated/generic.
    var manualIntrinsicsBySensorSignature: [String: ManualIntrinsics] = [:]

    /// The project-level OPF UUID written into `project.opf`.
    var opfProjectID: UUID { id }

    static func makeNew(name: String, description: String) -> CaptureProject {
        CaptureProject(
            id: UUID(),
            name: name,
            description: description,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Image / capture record

/// Everything the app knows about one captured or imported photograph.
struct ImageRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// File name relative to the project's `images/` directory, e.g. "P0001.jpg".
    var fileName: String
    var addedAt: Date
    var origin: ImageOrigin

    // Pixel geometry (measured from the actual file).
    var pixelWidth: Int
    var pixelHeight: Int
    /// EXIF orientation value 1...8 (1 = no rotation, no mirror).
    var exifOrientation: Int

    // Acquisition time as recorded in EXIF / at capture time.
    var captureTime: Date?
    /// Whether the capture time came from the device clock (capture) or file EXIF (import).
    var captureTimeSource: TimeSource

    // File facts.
    var fileByteSize: Int
    var utTypeIdentifier: String
    /// Whether the stored file is the untouched original (true) or a JPEG transcode (false).
    var isOriginalPixelsUnmodified: Bool

    // Sensor data: nil means "unavailable", never a fabricated value.
    var geolocation: GeolocationRecord?
    var deviceAttitude: DeviceAttitudeRecord?
    var exifSummary: EXIFSummary

    /// Sensor identity signature; groups images that share a physical camera/lens.
    var sensorSignature: String
}

enum ImageOrigin: String, Codable {
    case cameraCapture
    case importedPhotoLibrary
    case importedFiles

    var displayName: String {
        switch self {
        case .cameraCapture: return "Captured"
        case .importedPhotoLibrary: return "Imported (Photos)"
        case .importedFiles: return "Imported (Files)"
        }
    }
}

enum TimeSource: String, Codable {
    case deviceClock
    case exif
    case fileSystem
    case unavailable

    var displayName: String {
        switch self {
        case .deviceClock: return "Device clock"
        case .exif: return "EXIF"
        case .fileSystem: return "File system"
        case .unavailable: return "Unavailable"
        }
    }
}

// MARK: - Geolocation

/// A measured position. `altitudeIsEllipsoidal` documents the ISO-19111 semantics of
/// a WGS 84 geographic CRS: the height is measured above the ellipsoid, **not** above
/// mean sea level. The app never claims a GPS altitude is an orthometric height.
struct GeolocationRecord: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    /// Height above the reference ellipsoid, in metres.
    var ellipsoidalAltitude: Double
    var horizontalAccuracy: Double
    var verticalAccuracy: Double
    var timestamp: Date
    /// Always true for the CRS the app emits; kept explicit so the UI can explain it.
    var altitudeIsEllipsoidal: Bool = true

    /// Values that are absent in the reading (e.g. a fix without vertical accuracy)
    /// are surfaced as unavailable rather than as a number.
    var hasVerticalAccuracy: Bool { verticalAccuracy.isFinite && verticalAccuracy > 0 }
}

// MARK: - Device attitude

/// Device attitude at capture time, captured as a quaternion to avoid Euler-order
/// conversion errors. This is **device** attitude and is explicitly *not* the
/// photogrammetric camera orientation.
struct DeviceAttitudeRecord: Codable, Hashable {
    var quaternionWXYZ: [Double]
    var pitchRadians: Double
    var rollRadians: Double
    var yawRadians: Double
    var timestamp: Date

    static let documentID = "device_attitude"

    var note: String {
        "Device attitude as reported by CoreMotion. This is not photogrammetric camera orientation."
    }
}

// MARK: - EXIF summary

/// The subset of EXIF we read, with explicit availability flags so the UI can tell
/// the user precisely which fields were missing.
struct EXIFSummary: Codable, Hashable {
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var focalLengthMM: Double?
    var focalLengthIn35mmMM: Double?
    var iso: Int?
    var exposureTimeSeconds: Double?
    var fNumber: Double?

    var availableFieldNames: [String] {
        var names: [String] = []
        if cameraMake != nil { names.append("Make") }
        if cameraModel != nil { names.append("Model") }
        if lensModel != nil { names.append("LensModel") }
        if focalLengthMM != nil { names.append("FocalLength") }
        if focalLengthIn35mmMM != nil { names.append("FocalLengthIn35mmFilm") }
        if iso != nil { names.append("ISOSpeedRatings") }
        if exposureTimeSeconds != nil { names.append("ExposureTime") }
        if fNumber != nil { names.append("FNumber") }
        return names
    }

    static let requiredForOPF = ["Make", "Model", "FocalLength"]
}

// MARK: - Sensor / camera model records

/// Groups images that share one physical camera + lens. OPF models this as a "sensor".
struct SensorRecord: Identifiable, Codable, Hashable {
    /// OPF `uid64` sensor id.
    var id: UInt64
    var displayName: String
    /// `perspective` | `fisheye` | `spherical` (only perspective is produced for phone cameras).
    var internalType: String
    var imageWidthPx: Int
    var imageHeightPx: Int
    /// Never fabricated: nil unless the user or a database supplied a real value.
    var pixelSizeMicrometres: Double?

    /// How the intrinsics were obtained. Controls the OPF `model_source` value.
    var calibrationSource: CalibrationSource

    /// Manual, user-verified intrinsics. Only present when `calibrationSource == .user`.
    var manualIntrinsics: ManualIntrinsics?

    var make: String?
    var model: String?
    var lensModel: String?

    var signature: String
}

enum CalibrationSource: String, Codable {
    /// Estimated from EXIF focal length; no distortion coefficients known.
    case genericFromEXIF
    /// No usable information at all.
    case generic
    /// A user entered verified intrinsics on the calibration screen.
    case user

    var opfModelSource: String {
        switch self {
        case .genericFromEXIF: return "generic_from_exif"
        case .generic: return "generic"
        case .user: return "user"
        }
    }

    var displayName: String {
        switch self {
        case .genericFromEXIF: return "Estimated from EXIF (not calibrated)"
        case .generic: return "Generic (not calibrated)"
        case .user: return "User-verified intrinsics"
        }
    }

    var isCalibrated: Bool { self == .user }
}

/// Intrinsics entered by the user after verifying them externally.
struct ManualIntrinsics: Codable, Hashable {
    var focalLengthPx: Double
    var principalPointXPx: Double
    var principalPointYPx: Double
    var radialDistortion: [Double]   // R1, R2, R3
    var tangentialDistortion: [Double] // T1, T2
    var pixelSizeMicrometres: Double

    static let zeroDistortion = [0.0, 0.0, 0.0]

    var isValid: Bool {
        focalLengthPx.isFinite && focalLengthPx > 0
            && principalPointXPx.isFinite && principalPointYPx.isFinite
            && radialDistortion.count == 3 && radialDistortion.allSatisfy(\.isFinite)
            && tangentialDistortion.count == 2 && tangentialDistortion.allSatisfy(\.isFinite)
            && pixelSizeMicrometres.isFinite && pixelSizeMicrometres > 0
    }
}

// MARK: - Validation

enum ValidationSeverity: String, Codable, Comparable {
    case error
    case warning
    case info

    private var rank: Int {
        switch self {
        case .error: return 0
        case .warning: return 1
        case .info: return 2
        }
    }

    static func < (lhs: ValidationSeverity, rhs: ValidationSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    var displayName: String {
        switch self {
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Info"
        }
    }
}

struct ValidationIssue: Identifiable, Hashable {
    var id = UUID()
    var severity: ValidationSeverity
    var code: String
    var message: String
    var document: String?
}

struct ValidationReport {
    var issues: [ValidationIssue] = []
    var checkedDocuments: [String] = []
    var generatedAt: Date = Date()

    var errors: [ValidationIssue] { issues.filter { $0.severity == .error } }
    var warnings: [ValidationIssue] { issues.filter { $0.severity == .warning } }
    var infos: [ValidationIssue] { issues.filter { $0.severity == .info } }

    var isValid: Bool { errors.isEmpty }

    var sortedIssues: [ValidationIssue] { issues.sorted { $0.severity < $1.severity } }

    /// Human readable report written next to the exported archive.
    func plainText(projectName: String) -> String {
        var lines: [String] = []
        lines.append("OPF Capture Builder — Validation Report")
        lines.append("Project: \(projectName)")
        lines.append("Generated: \(OPFDateFormat.iso8601(generatedAt))")
        lines.append("Result: \(isValid ? "PASS (no errors)" : "FAIL (\(errors.count) error(s))")")
        lines.append("Errors: \(errors.count)   Warnings: \(warnings.count)   Info: \(infos.count)")
        lines.append("")
        lines.append("Documents checked:")
        for document in checkedDocuments { lines.append("  - \(document)") }
        lines.append("")
        if issues.isEmpty {
            lines.append("No issues were found.")
        } else {
            lines.append("Issues:")
            for issue in sortedIssues {
                let location = issue.document.map { " [\($0)]" } ?? ""
                lines.append("  \(issue.severity.displayName.uppercased()) \(issue.code)\(location): \(issue.message)")
            }
        }
        lines.append("")
        lines.append("Validated against the official OPF JSON schemas (opf-spec schema/ directory).")
        lines.append("Note: GPS altitude is ellipsoidal height, not orthometric height.")
        return lines.joined(separator: "\n")
    }
}
