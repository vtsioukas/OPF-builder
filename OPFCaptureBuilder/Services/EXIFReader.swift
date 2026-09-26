//
//  EXIFReader.swift
//  OPFCaptureBuilder
//
//  Reads only what is actually present in the file. Every field is optional and the
//  reader reports which fields were missing rather than substituting defaults. It uses
//  ImageIO's metadata dictionaries, i.e. read-only access; the file is never rewritten.
//

import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

struct EXIFReadResult {
    var pixelWidth: Int
    var pixelHeight: Int
    var orientation: Int
    var summary: EXIFSummary
    var captureTime: Date?
    var utTypeIdentifier: String
    var bitDepth: Int
}

enum EXIFReader {

    static func read(url: URL) -> EXIFReadResult? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return read(source: source)
    }

    static func read(data: Data) -> EXIFReadResult? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return read(source: source)
    }

    private static func read(source: CGImageSource) -> EXIFReadResult? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        var orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if !(1...8).contains(orientation) { orientation = 1 }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]

        var summary = EXIFSummary()
        summary.cameraMake = nonEmpty(tiff[kCGImagePropertyTIFFMake] as? String)
        summary.cameraModel = nonEmpty(tiff[kCGImagePropertyTIFFModel] as? String)
        summary.lensModel = nonEmpty(exif[kCGImagePropertyExifLensModel] as? String)
        summary.focalLengthMM = finite(exif[kCGImagePropertyExifFocalLength])
        summary.focalLengthIn35mmMM = finite(exif[kCGImagePropertyExifFocalLenIn35mmFilm])
        summary.exposureTimeSeconds = finite(exif[kCGImagePropertyExifExposureTime])
        summary.fNumber = finite(exif[kCGImagePropertyExifFNumber])
        if let isoValues = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let first = isoValues.first {
            summary.iso = first.intValue
        }

        var captureTime: Date?
        if let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            captureTime = exifDateFormatter.date(from: text)
        }

        let bitDepth = (properties[kCGImagePropertyDepth] as? NSNumber)?.intValue ?? 8

        let utType = CGImageSourceGetType(source) as String? ?? UTType.jpeg.identifier

        return EXIFReadResult(
            pixelWidth: width,
            pixelHeight: height,
            orientation: orientation,
            summary: summary,
            captureTime: captureTime,
            utTypeIdentifier: utType,
            bitDepth: bitDepth
        )
    }

    /// EXIF timestamps have no timezone, so they are interpreted as local time, which is
    /// how the camera recorded them. The UI states that the timezone is unknown in this case.
    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func finite(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            let double = number.doubleValue
            return double.isFinite ? double : nil
        }
        if let double = value as? Double, double.isFinite { return double }
        return nil
    }
}

// MARK: - Sensor identity

/// A stable description of the physical camera + lens. Two photographs that share this
/// signature are, as far as the app can tell, from the same camera and are grouped into
/// one OPF sensor.
struct SensorSignature {
    var make: String?
    var model: String?
    var lensModel: String?
    var width: Int
    var height: Int
    var focalLengthIn35mmMM: Double?
    var focalLengthMM: Double?

    var rawValue: String {
        [
            make ?? "unknown_make",
            model ?? "unknown_model",
            lensModel ?? "unknown_lens",
            "\(width)x\(height)",
            (focalLengthIn35mmMM ?? focalLengthMM).map { String(format: "%.2f", $0) } ?? "unknown_focal"
        ].joined(separator: "|")
    }

    /// Human readable sensor name in the style used by the official OPF examples:
    /// `Maker_Model_Focal_WidthxHeight`.
    var sensorName: String {
        var parts: [String] = []
        if let make = make { parts.append(sanitize(make)) }
        if let model = model { parts.append(sanitize(model)) }
        if let focal = focalLengthIn35mmMM ?? focalLengthMM {
            parts.append(String(format: "%.1f", focal))
        }
        parts.append("\(width)x\(height)")
        return parts.joined(separator: "_")
    }

    private func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
    }
}
