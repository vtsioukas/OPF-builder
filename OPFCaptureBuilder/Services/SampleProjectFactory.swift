//
//  SampleProjectFactory.swift
//  OPFCaptureBuilder
//
//  Builds a small, self-contained sample project with synthesised photographs and clearly
//  synthetic metadata. It contains no proprietary PIX4D data: the images are gradients
//  drawn by Core Graphics and the coordinates are a made-up but plausible location.
//
//  The coordinates are deliberately labelled in the project description as synthetic so a
//  reader never mistakes them for a real survey.
//

import Foundation
import UIKit

enum SampleProjectFactory {

    static let sampleProjectName = "Sample Project (synthetic)"

    @MainActor
    static func makeSampleProject(store: ProjectStore) throws -> CaptureProject {
        var project = try store.createProject(
            name: uniqueSampleName(store: store),
            description: "Synthetic sample project generated on device. The photographs and coordinates are fabricated for testing and contain no proprietary data."
        )
        project.crsDefinition = OPFConstants.defaultCRSDefinition
        project.acknowledgedAltitudeWarning = true
        project.emitSceneReferenceFrame = true
        try store.update(project)

        // A small overlapping flight line: eight positions along a straight path, each
        // with a synthetic overlapping image and a synthetic location fix.
        let baseLatitude = 46.5196535
        let baseLongitude = 6.6322734
        let baseAltitude = 375.0

        for index in 0..<8 {
            let offset = Double(index) * 0.00006
            let width = 1600
            let height = 1200
            let image = SyntheticImageFactory.makeImage(width: width, height: height, seed: index)
            guard let data = image.jpegData(compressionQuality: 0.9) else { continue }
            let fileName = "SAMPLE_\(String(format: "%04d", index + 1)).jpg"
            _ = try store.storeImageData(data, fileName: fileName, in: project)

            let summary = EXIFSummary(
                cameraMake: "Synthetic",
                cameraModel: "SampleCam 1.0",
                lensModel: "Sample 26mm",
                focalLengthMM: 4.25,
                focalLengthIn35mmMM: 26.0,
                iso: 100,
                exposureTimeSeconds: 1.0 / 500.0,
                fNumber: 1.8
            )

            let signature = SensorSignature(
                make: summary.cameraMake,
                model: summary.cameraModel,
                lensModel: summary.lensModel,
                width: width,
                height: height,
                focalLengthIn35mmMM: summary.focalLengthIn35mmMM,
                focalLengthMM: summary.focalLengthMM
            ).rawValue

            let captureTime = Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3)
            let geolocation = GeolocationRecord(
                latitude: baseLatitude + offset,
                longitude: baseLongitude + offset * 0.35,
                ellipsoidalAltitude: baseAltitude + Double(index) * 0.4,
                horizontalAccuracy: 3.0,
                verticalAccuracy: 5.0,
                timestamp: captureTime,
                altitudeIsEllipsoidal: true
            )

            let record = ImageRecord(
                fileName: fileName,
                addedAt: captureTime,
                origin: .cameraCapture,
                pixelWidth: width,
                pixelHeight: height,
                exifOrientation: 1,
                captureTime: captureTime,
                captureTimeSource: .deviceClock,
                fileByteSize: data.count,
                utTypeIdentifier: "public.jpeg",
                isOriginalPixelsUnmodified: true,
                geolocation: geolocation,
                deviceAttitude: nil,
                exifSummary: summary,
                sensorSignature: signature
            )

            project.images.append(record)
        }

        try store.update(project)
        return project
    }

    private static func uniqueSampleName(store: ProjectStore) -> String {
        var candidate = sampleProjectName
        var index = 2
        while store.projects.contains(where: { $0.name == candidate }) {
            candidate = "\(sampleProjectName) \(index)"
            index += 1
        }
        return candidate
    }
}

/// Draws deterministic synthetic photographs. No external assets and no proprietary data.
enum SyntheticImageFactory {
    static func makeImage(width: Int, height: Int, seed: Int) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let hue = CGFloat((seed * 47) % 360) / 360.0
            let start = UIColor(hue: hue, saturation: 0.45, brightness: 0.95, alpha: 1).cgColor
            let end = UIColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1.0), saturation: 0.7, brightness: 0.55, alpha: 1).cgColor
            let colors = [start, end] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient,
                                      start: CGPoint(x: 0, y: 0),
                                      end: CGPoint(x: size.width, y: size.height),
                                      options: [])
            }

            // Overlapping feature markers so the frames are visibly distinct but aligned.
            let markerCount = 24
            for marker in 0..<markerCount {
                let x = CGFloat((marker * 137 + seed * 53) % width)
                let y = CGFloat((marker * 89 + seed * 31) % height)
                let radius = CGFloat(18 + (marker % 5) * 8)
                cg.setFillColor(UIColor.white.withAlphaComponent(0.25).cgColor)
                cg.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                cg.setStrokeColor(UIColor.black.withAlphaComponent(0.35).cgColor)
                cg.setLineWidth(3)
                cg.strokeEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }
    }
}
