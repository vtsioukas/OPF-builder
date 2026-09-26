//
//  ImageImporter.swift
//  OPFCaptureBuilder
//
//  Imports photographs from the Files app or the photo library. Originals are copied
//  byte-for-byte; the app never rewrites EXIF in the stored originals. When the user asks
//  for maximum third-party compatibility, a *separate* JPEG rendition is produced and the
//  user is told the pixels were transcoded.
//

import Foundation
import UIKit
import UniformTypeIdentifiers

struct ImportOutcome {
    var record: ImageRecord
    var missingFields: [String]
    var transcodeNotice: String?
}

enum ImageImporter {

    /// Imports a file URL (from the Files app / document picker).
    static func importFile(
        at url: URL,
        into project: CaptureProject,
        store: ProjectStore,
        includeSensorData: Bool
    ) async throws -> ImportOutcome {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        let exif = EXIFReader.read(url: url)

        let originalData = try Data(contentsOf: url)
        var storedData = originalData
        var storedExtension = ext.isEmpty ? "jpg" : ext
        var transcodeNotice: String?
        var pixelsUnmodified = true

        if project.exportAsJPEG, let image = UIImage(data: originalData), ext != "jpg", ext != "jpeg" {
            if let jpeg = image.jpegData(compressionQuality: 0.98) {
                storedData = jpeg
                storedExtension = "jpg"
                pixelsUnmodified = false
                transcodeNotice = "This photograph was transcoded to JPEG on import (maximum compatibility mode is on). The original pixels were re-encoded."
            }
        }

        let fileName = try store.storeImageData(storedData, fileName: generatedFileName(extension: storedExtension), in: project)

        let record = makeRecord(
            fileName: fileName,
            exif: exif,
            storedByteSize: storedData.count,
            origin: .importedFiles,
            pixelsUnmodified: pixelsUnmodified,
            captureTimeFallback: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        )

        let missing = missingFields(for: record)
        return ImportOutcome(record: record, missingFields: missing, transcodeNotice: transcodeNotice)
    }

    /// Imports image data supplied by the photo library picker.
    static func importPhotoLibraryItem(
        data: Data,
        suggestedName: String?,
        creationDate: Date?,
        location: GeolocationRecord?,
        into project: CaptureProject,
        store: ProjectStore
    ) async throws -> ImportOutcome {
        let exif = EXIFReader.read(data: data)

        var storedData = data
        var storedExtension = fileExtension(forUTI: exif?.utTypeIdentifier) ?? "jpg"
        var transcodeNotice: String?
        var pixelsUnmodified = true

        if project.exportAsJPEG, let image = UIImage(data: data), storedExtension != "jpg" {
            if let jpeg = image.jpegData(compressionQuality: 0.98) {
                storedData = jpeg
                storedExtension = "jpg"
                pixelsUnmodified = false
                transcodeNotice = "This photograph was transcoded to JPEG on import (maximum compatibility mode is on). The original pixels were re-encoded."
            }
        }

        let fileName = try store.storeImageData(storedData, fileName: generatedFileName(extension: storedExtension), in: project)

        var record = makeRecord(
            fileName: fileName,
            exif: exif,
            storedByteSize: storedData.count,
            origin: .importedPhotoLibrary,
            pixelsUnmodified: pixelsUnmodified,
            captureTimeFallback: creationDate
        )
        // A photo-library asset may carry a location; if it does we keep it, otherwise the
        // field stays unavailable rather than being invented.
        if let location, record.geolocation == nil {
            record.geolocation = location
        }
        if let suggestedName, record.captureTimeSource == .unavailable, creationDate == nil {
            record.captureTime = nil
            _ = suggestedName
        }

        let missing = missingFields(for: record)
        return ImportOutcome(record: record, missingFields: missing, transcodeNotice: transcodeNotice)
    }

    // MARK: - Helpers

    private static func makeRecord(
        fileName: String,
        exif: EXIFReadResult?,
        storedByteSize: Int,
        origin: ImageOrigin,
        pixelsUnmodified: Bool,
        captureTimeFallback: Date?
    ) -> ImageRecord {
        let summary = exif?.summary ?? EXIFSummary()
        let width = exif?.pixelWidth ?? 0
        let height = exif?.pixelHeight ?? 0

        let signature = SensorSignature(
            make: summary.cameraMake,
            model: summary.cameraModel,
            lensModel: summary.lensModel,
            width: width,
            height: height,
            focalLengthIn35mmMM: summary.focalLengthIn35mmMM,
            focalLengthMM: summary.focalLengthMM
        ).rawValue

        let timeSource: TimeSource
        let time: Date?
        if let exifTime = exif?.captureTime {
            time = exifTime
            timeSource = .exif
        } else if let fallback = captureTimeFallback {
            time = fallback
            timeSource = .fileSystem
        } else {
            time = nil
            timeSource = .unavailable
        }

        return ImageRecord(
            fileName: fileName,
            addedAt: Date(),
            origin: origin,
            pixelWidth: width,
            pixelHeight: height,
            exifOrientation: exif?.orientation ?? 1,
            captureTime: time,
            captureTimeSource: timeSource,
            fileByteSize: storedByteSize,
            utTypeIdentifier: exif?.utTypeIdentifier ?? "public.jpeg",
            isOriginalPixelsUnmodified: pixelsUnmodified,
            geolocation: nil,
            deviceAttitude: nil,
            exifSummary: summary,
            sensorSignature: signature
        )
    }

    static func missingFields(for record: ImageRecord) -> [String] {
        var missing: [String] = []
        if record.pixelWidth == 0 || record.pixelHeight == 0 { missing.append("Pixel dimensions") }
        if record.captureTime == nil { missing.append("Capture time") }
        if record.exifSummary.cameraMake == nil { missing.append("Camera make") }
        if record.exifSummary.cameraModel == nil { missing.append("Camera model") }
        if record.exifSummary.focalLengthMM == nil && record.exifSummary.focalLengthIn35mmMM == nil {
            missing.append("Focal length")
        }
        if record.geolocation == nil { missing.append("Location") }
        return missing
    }

    private static func generatedFileName(extension ext: String) -> String {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return "IMG_\(stamp)_\(String(format: "%04X", Int.random(in: 0..<0xFFFF))).\(ext)"
    }

    private static func fileExtension(forUTI identifier: String) -> String? {
        guard let type = UTType(identifier) else { return nil }
        return type.preferredFilenameExtension
    }
}
