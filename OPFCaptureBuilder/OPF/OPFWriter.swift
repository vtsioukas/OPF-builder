//
//  OPFWriter.swift
//  OPFCaptureBuilder
//
//  Turns a `CaptureProject` into the complete set of OPF JSON documents.
//
//  Documents produced:
//    project.opf                              application/opf-project+json
//    camera-list.json                         application/opf-camera-list+json
//    input-cameras.json                       application/opf-input-cameras+json
//    scene-reference-frame.json (optional)    application/opf-scene-reference-frame+json
//
//  Nothing here fabricates sensor data. When a value is unknown the corresponding
//  optional OPF property is omitted, and the camera is labelled `generic*` rather than
//  `database`/`user` so a consumer can tell the model was not calibrated.
//

import Foundation

struct OPFDocument {
    var relativePath: String
    var format: String
    var value: JSONValue

    func data() throws -> Data { try value.serialized(pretty: true) }
}

struct OPFDocumentSet {
    var project: OPFDocument
    var cameraList: OPFDocument
    var inputCameras: OPFDocument
    var sceneReferenceFrame: OPFDocument?

    var all: [OPFDocument] {
        var docs = [project, cameraList, inputCameras]
        if let sceneReferenceFrame { docs.append(sceneReferenceFrame) }
        return docs
    }
}

enum OPFWriter {

    /// Stable UUIDs for the three/four project items so repeated exports of the same
    /// project keep the same item graph.
    struct ItemIDs {
        var cameraList: UUID
        var inputCameras: UUID
        var sceneReferenceFrame: UUID

        init(projectID: UUID) {
            var bytes = withUnsafeBytes(of: projectID.uuid) { Array($0) }
            cameraList = OPFWriter.derivedUUID(from: &bytes, salt: 0xC1)
            inputCameras = OPFWriter.derivedUUID(from: &bytes, salt: 0xC2)
            sceneReferenceFrame = OPFWriter.derivedUUID(from: &bytes, salt: 0xC3)
        }
    }

    /// Derives a stable, RFC-4122-shaped UUID from the project UUID so the item graph is
    /// reproducible across exports while still matching `uuid.schema.json`.
    static func derivedUUID(from bytes: inout [UInt8], salt: UInt8) -> UUID {
        var working = bytes
        working[0] ^= salt
        working[working.count - 1] = working[working.count - 1] &+ salt
        working[6] = (working[6] & 0x0F) | 0x40   // version 4
        working[8] = (working[8] & 0x3F) | 0x80   // RFC 4122 variant
        return UUID(uuid: (working[0], working[1], working[2], working[3],
                           working[4], working[5], working[6], working[7],
                           working[8], working[9], working[10], working[11],
                           working[12], working[13], working[14], working[15]))
    }

    // MARK: - Build

    /// - Parameter cameraIDProvider: Produces the `uid64` for an image. The default hashes
    ///   the file name, which keeps unit tests hermetic; `OPFExporter` supplies a provider
    ///   that hashes the real file bytes on disk. One strategy (`FNV1a64` content hash) is
    ///   used everywhere, including by the capture/import path.
    static func build(
        project: CaptureProject,
        cameraIDProvider: ((ImageRecord) -> UInt64)? = nil
    ) -> OPFDocumentSet {
        let itemIDs = ItemIDs(projectID: project.id)
        let images = project.images
        let provider = cameraIDProvider ?? { OPFUID.cameraID(forImageBytes: Data($0.fileName.utf8)) }

        // --- camera list -----------------------------------------------------
        // One entry per distinct image file; identical files map to the same UID. The OPF
        // specification requires camera UIDs to be unique, so a (vanishingly unlikely)
        // content-hash collision is resolved deterministically rather than silently.
        var seenFiles = Set<String>()
        var usedIDs = Set<UInt64>()
        var cameraEntries: [OPFCameraListEntry] = []
        var cameraIDByFileName: [String: UInt64] = [:]

        for image in images {
            guard !seenFiles.contains(image.fileName) else { continue }
            seenFiles.insert(image.fileName)
            var id = provider(image) & OPFUID.usableBits
            var attempt = 0
            while usedIDs.contains(id) {
                attempt += 1
                id = FNV1a64.hash(Data("\(image.fileName)#\(attempt)".utf8)) & OPFUID.usableBits
            }
            usedIDs.insert(id)
            cameraEntries.append(OPFCameraListEntry(id: id, uri: relativeImageURI(for: image)))
            cameraIDByFileName[image.fileName] = id
        }

        // --- sensors ---------------------------------------------------------
        var sensorOrder: [String] = []
        var sensorBySignature: [String: OPFSensorEntry] = [:]
        var sensorContent: [UInt64: SensorContent] = [:]

        for image in images {
            let signature = image.sensorSignature
            if sensorBySignature[signature] == nil {
                let sensor = makeSensor(project: project, image: image, signature: signature)
                sensorBySignature[signature] = sensor
                sensorOrder.append(signature)
            }
            if let sensor = sensorBySignature[signature] {
                var content = sensorContent[sensor.id] ?? SensorContent(observedMin: 0, observedMax: 255)
                content.observedMin = min(content.observedMin, 0)
                content.observedMax = max(content.observedMax, 255)
                sensorContent[sensor.id] = content
            }
        }

        let sensors = sensorOrder.compactMap { sensorBySignature[$0] }

        // --- captures --------------------------------------------------------
        var captures: [OPFCaptureEntry] = []
        for image in images {
            guard let cameraID = cameraIDByFileName[image.fileName] else { continue }
            let sensor = sensorBySignature[image.sensorSignature]
            let modelSource = sensor?.internals == nil ? "generic" : (project.manualIntrinsicsBySensorSignature[image.sensorSignature] != nil ? "user" : "generic_from_exif")

            let entry = OPFCaptureCameraEntry(
                sensorID: sensor?.id ?? 0,
                cameraID: cameraID,
                modelSource: modelSource,
                pixelType: "uint8",
                pixelRangeMin: 0,
                pixelRangeMax: 255,
                exifOrientation: image.exifOrientation
            )

            var orientation: OrientationExport?
            if project.exportEstimatedOrientation,
               let attitude = image.deviceAttitude,
               let ypr = DeviceAttitudeMapping.yawPitchRollDegrees(quaternionWXYZ: attitude.quaternionWXYZ) {
                orientation = OrientationExport(
                    yawDeg: ypr.yaw,
                    pitchDeg: ypr.pitch,
                    rollDeg: ypr.roll,
                    sigmaDeg: project.orientationSigmaDeg
                )
            }

            let time = image.captureTime ?? image.addedAt
            let capture = OPFCaptureEntry(
                id: OPFUID.captureID(cameraID: cameraID, iso8601Time: OPFDateFormat.iso8601(time)),
                referenceCameraID: cameraID,
                cameras: [entry],
                rigModelSource: "not_applicable",
                geolocation: image.geolocation,
                crsDefinition: project.crsDefinition,
                orientation: orientation,
                time: time
            )
            captures.append(capture)
        }

        // --- documents -------------------------------------------------------
        let cameraListValue = OPFDocumentBuilder.cameraList(cameras: cameraEntries)
        let inputCamerasValue = OPFDocumentBuilder.inputCameras(
            sensors: sensors,
            captures: captures,
            sensorContents: sensorContent
        )

        var items: [OPFDocumentBuilder.ProjectItem] = []
        items.append(.init(
            id: itemIDs.cameraList,
            name: "Camera list",
            type: OPFConstants.ResourceType.cameraList,
            resources: [(OPFConstants.Layout.cameraListFile, OPFConstants.Format.cameraList)],
            sources: []
        ))
        items.append(.init(
            id: itemIDs.inputCameras,
            name: "Input cameras",
            type: OPFConstants.ResourceType.inputCameras,
            resources: [(OPFConstants.Layout.inputCamerasFile, OPFConstants.Format.inputCameras)],
            sources: [(itemIDs.cameraList, OPFConstants.ResourceType.cameraList)]
        ))

        var sceneFrameDoc: OPFDocument?
        if project.emitSceneReferenceFrame {
            let shift = sceneShift(for: images)
            let sceneValue = OPFDocumentBuilder.sceneReferenceFrame(
                crsDefinition: project.crsDefinition,
                shift: shift,
                scale: [1.0, 1.0, 1.0],
                swapXY: false,
                geoidHeight: project.geoidHeight
            )
            sceneFrameDoc = OPFDocument(
                relativePath: OPFConstants.Layout.sceneReferenceFrameFile,
                format: OPFConstants.Format.sceneReferenceFrame,
                value: sceneValue
            )
            items.append(.init(
                id: itemIDs.sceneReferenceFrame,
                name: "Scene reference frame",
                type: OPFConstants.ResourceType.sceneReferenceFrame,
                resources: [(OPFConstants.Layout.sceneReferenceFrameFile, OPFConstants.Format.sceneReferenceFrame)],
                sources: []
            ))
        }

        let projectValue = OPFDocumentBuilder.projectDocument(project: project, items: items)

        return OPFDocumentSet(
            project: OPFDocument(relativePath: OPFConstants.Layout.projectFile,
                                 format: OPFConstants.Format.project,
                                 value: projectValue),
            cameraList: OPFDocument(relativePath: OPFConstants.Layout.cameraListFile,
                                    format: OPFConstants.Format.cameraList,
                                    value: cameraListValue),
            inputCameras: OPFDocument(relativePath: OPFConstants.Layout.inputCamerasFile,
                                      format: OPFConstants.Format.inputCameras,
                                      value: inputCamerasValue),
            sceneReferenceFrame: sceneFrameDoc
        )
    }

    // MARK: - Helpers

    static func relativeImageURI(for image: ImageRecord) -> String {
        "\(OPFConstants.Layout.imagesDirectory)/\(image.fileName)"
    }

    /// A canonical shift so projected coordinates stay small. Uses the first known fix
    /// when georeferencing is enabled; otherwise the origin, which the spec explicitly
    /// permits for an unknown frame.
    static func sceneShift(for images: [ImageRecord]) -> [Double] {
        guard let first = images.compactMap(\.geolocation).first else { return [0, 0, 0] }
        return [first.longitude, first.latitude, first.ellipsoidalAltitude]
    }

    private static func makeSensor(project: CaptureProject, image: ImageRecord, signature: String) -> OPFSensorEntry {
        let width = max(image.pixelWidth, 1)
        let height = max(image.pixelHeight, 1)
        let parsed = SensorSignature(
            make: image.exifSummary.cameraMake,
            model: image.exifSummary.cameraModel,
            lensModel: image.exifSummary.lensModel,
            width: width,
            height: height,
            focalLengthIn35mmMM: image.exifSummary.focalLengthIn35mmMM,
            focalLengthMM: image.exifSummary.focalLengthMM
        )

        let sensorID = OPFUID.sensorID(signature: signature)
        let bands: [(String, Double)] = [
            ("Red", 0.2126),
            ("Green", 0.7152),
            ("Blue", 0.0722)
        ]

        let manual = project.manualIntrinsicsBySensorSignature[signature]
        let internals: OPFPerspectiveInternals
        let pixelSize: Double

        if let manual, manual.isValid {
            internals = OPFPerspectiveInternals(
                principalPointXPx: manual.principalPointXPx,
                principalPointYPx: manual.principalPointYPx,
                focalLengthPx: manual.focalLengthPx,
                radialDistortion: manual.radialDistortion,
                tangentialDistortion: manual.tangentialDistortion
            )
            pixelSize = manual.pixelSizeMicrometres
        } else {
            let focal = estimatedFocalLengthPx(width: width, height: height, summary: image.exifSummary)
            internals = OPFPerspectiveInternals(
                principalPointXPx: Double(width) / 2.0,
                principalPointYPx: Double(height) / 2.0,
                focalLengthPx: focal,
                radialDistortion: ManualIntrinsics.zeroDistortion,
                tangentialDistortion: [0.0, 0.0]
            )
            pixelSize = 36_000.0 / Double(width)
        }

        return OPFSensorEntry(
            id: sensorID,
            name: parsed.sensorName,
            bands: bands,
            imageWidthPx: width,
            imageHeightPx: height,
            pixelSizeMicrometres: pixelSize,
            internals: internals,
            focalLengthIn35mmMM: image.exifSummary.focalLengthIn35mmMM,
            shutterType: "rolling"
        )
    }

    /// Estimated focal length in pixels. Everything derived here is labelled
    /// `generic_from_exif` (or `generic`) by the caller and shown to the user as an estimate.
    static func estimatedFocalLengthPx(width: Int, height: Int, summary: EXIFSummary) -> Double {
        let w = Double(max(width, 1))
        if let f35 = summary.focalLengthIn35mmMM, f35.isFinite, f35 > 0 {
            return f35 * w / 36.0
        }
        if let fmm = summary.focalLengthMM, fmm.isFinite, fmm > 0 {
            let pixelSize = 36_000.0 / w
            return fmm * 1000.0 / pixelSize
        }
        // No focal information at all: assume a 26 mm-equivalent lens, the most common
        // main-camera value, and label the model `generic`.
        return w * (26.0 / 36.0)
    }
}
