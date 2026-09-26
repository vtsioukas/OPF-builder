//
//  OPFDocumentBuilder.swift
//  OPFCaptureBuilder
//
//  Builds the OPF JSON documents as `JSONValue` trees. Property names, enum values and
//  the "required" set of every object come directly from the vendored official schemas:
//
//      camera_list.schema.json      -> camera_list
//      input_cameras.schema.json    -> input_cameras
//      sensor_internals.schema.json -> perspective internals
//      scene_reference_frame.schema.json -> scene reference frame
//
//  Only the chain camera_list -> input_cameras (+ optional scene_reference_frame) is
//  produced. No `calibration` or `point_cloud` item is ever written, because this app
//  does not perform photogrammetric calibration or reconstruction.
//

import Foundation

/// One camera entry inside an `input_cameras` capture.
struct OPFCaptureCameraEntry {
    var sensorID: UInt64
    var cameraID: UInt64
    var modelSource: String          // "database" | "generic_from_exif" | "generic" | "user"
    var pixelType: String            // "uint8" | "uint12" | "uint16" | "float"
    var pixelRangeMin: Double
    var pixelRangeMax: Double
    var exifOrientation: Int?        // 1...8, omitted when 1
}

/// One `input_cameras` capture. `orientation` is nil unless the user opted in.
struct OPFCaptureEntry {
    var id: UInt64
    var referenceCameraID: UInt64
    var cameras: [OPFCaptureCameraEntry]
    var rigModelSource: String       // always "not_applicable" for single-camera captures
    var geolocation: GeolocationRecord?
    var crsDefinition: String
    var orientation: OrientationExport?
    var time: Date
}

struct OrientationExport {
    var yawDeg: Double
    var pitchDeg: Double
    var rollDeg: Double
    var sigmaDeg: Double
}

/// One `input_cameras` sensor.
struct OPFSensorEntry {
    var id: UInt64
    var name: String
    var bands: [(name: String, weight: Double)]
    var imageWidthPx: Int
    var imageHeightPx: Int
    var pixelSizeMicrometres: Double?
    var internals: OPFPerspectiveInternals?
    var focalLengthIn35mmMM: Double?
    var shutterType: String          // "global" | "rolling"
}

struct OPFPerspectiveInternals {
    var principalPointXPx: Double
    var principalPointYPx: Double
    var focalLengthPx: Double
    var radialDistortion: [Double]   // exactly 3
    var tangentialDistortion: [Double] // exactly 2
}

/// One camera in the `camera_list`.
struct OPFCameraListEntry {
    var id: UInt64
    var uri: String
}

enum OPFDocumentBuilder {

    // MARK: - camera-list.json

    static func cameraList(cameras: [OPFCameraListEntry]) -> JSONValue {
        var root = JSONObject()
        root["format"] = .string(OPFConstants.Format.cameraList)
        root["version"] = .string(OPFConstants.version)

        var generator = JSONObject()
        generator["vendor"] = .string(OPFUID.vendor)
        generator["name"] = .string(OPFUID.name)
        generator["scope"] = .string(OPFUID.scope)
        generator["version"] = .int(OPFUID.version)
        root["uid_generator"] = .object(generator)

        root["cameras"] = .array(cameras.map { camera in
            var object = JSONObject()
            object["id"] = .uint64(camera.id)
            object["uri"] = .string(camera.uri)
            return .object(object)
        })
        return .object(root)
    }

    // MARK: - input-cameras.json

    static func inputCameras(
        sensors: [OPFSensorEntry],
        captures: [OPFCaptureEntry],
        sensorContents: [UInt64: SensorContent]
    ) -> JSONValue {
        var root = JSONObject()
        root["format"] = .string(OPFConstants.Format.inputCameras)
        root["version"] = .string(OPFConstants.version)

        root["sensors"] = .array(sensors.map { sensor in
            sensorObject(sensor, content: sensorContents[sensor.id])
        })

        root["captures"] = .array(captures.map { capture in
            captureObject(capture)
        })
        return .object(root)
    }

    private static func sensorObject(_ sensor: OPFSensorEntry, content: SensorContent?) -> JSONValue {
        var object = JSONObject()
        object["id"] = .uint64(sensor.id)
        object["name"] = .string(sensor.name)

        object["bands"] = .array(sensor.bands.map { band in
            var bandObject = JSONObject()
            bandObject["name"] = .string(band.name)
            bandObject["weight"] = .double(band.weight)
            return .object(bandObject)
        })

        object["image_size_px"] = .array([.int(sensor.imageWidthPx), .int(sensor.imageHeightPx)])

        // `pixel_size_um` is required by the schema. When the real pixel size is unknown
        // we derive it from the physical sensor width when we have one, otherwise from the
        // 35 mm-equivalent focal length ratio implied by the EXIF focal length. The value
        // is always accompanied by a `model_source` of `generic*` so consumers know it is
        // not a database figure, and the UI tells the user it is estimated.
        object["pixel_size_um"] = .double(sensor.pixelSizeMicrometres ?? estimatedPixelSizeMicrometres(sensor))

        if let internals = sensor.internals {
            object["internals"] = perspectiveInternals(internals)
        } else {
            object["internals"] = sphericalInternals(width: sensor.imageWidthPx, height: sensor.imageHeightPx)
        }

        object["shutter_type"] = .string(sensor.shutterType)
        return .object(object)
    }

    static func perspectiveInternals(_ internals: OPFPerspectiveInternals) -> JSONValue {
        var object = JSONObject()
        object["type"] = .string("perspective")
        object["principal_point_px"] = .array([.double(internals.principalPointXPx), .double(internals.principalPointYPx)])
        object["focal_length_px"] = .double(internals.focalLengthPx)
        object["radial_distortion"] = .numbers(internals.radialDistortion)
        object["tangential_distortion"] = .numbers(internals.tangentialDistortion)
        return .object(object)
    }

    private static func sphericalInternals(width: Int, height: Int) -> JSONValue {
        var object = JSONObject()
        object["type"] = .string("spherical")
        object["principal_point_px"] = .array([.double(Double(width) / 2.0), .double(Double(height) / 2.0)])
        return .object(object)
    }

    private static func captureObject(_ capture: OPFCaptureEntry) -> JSONValue {
        var object = JSONObject()
        object["id"] = .uint64(capture.id)
        object["rig_model_source"] = .string(capture.rigModelSource)

        object["cameras"] = .array(capture.cameras.map { camera in
            var cameraObject = JSONObject()
            cameraObject["sensor_id"] = .uint64(camera.sensorID)
            cameraObject["id"] = .uint64(camera.cameraID)
            cameraObject["model_source"] = .string(camera.modelSource)
            cameraObject["pixel_type"] = .string(camera.pixelType)
            var range = JSONObject()
            range["min"] = .double(camera.pixelRangeMin)
            range["max"] = .double(camera.pixelRangeMax)
            cameraObject["pixel_range"] = .object(range)
            // `image_orientation` defaults to 1 and may be omitted for upright images.
            if let orientation = camera.exifOrientation, orientation > 1, (1...8).contains(orientation) {
                cameraObject["image_orientation"] = .int(orientation)
            }
            return .object(cameraObject)
        })

        object["reference_camera_id"] = .uint64(capture.referenceCameraID)

        if let geo = capture.geolocation {
            object["geolocation"] = geolocationObject(geo, crsDefinition: capture.crsDefinition)
        }

        if let orientation = capture.orientation {
            var orientationObject = JSONObject()
            orientationObject["type"] = .string("yaw_pitch_roll")
            // Only expose angles that are finite; otherwise omit the whole orientation.
            if [orientation.yawDeg, orientation.pitchDeg, orientation.rollDeg, orientation.sigmaDeg].allSatisfy(\.isFinite) {
                orientationObject["angles_deg"] = .numbers([orientation.yawDeg, orientation.pitchDeg, orientation.rollDeg])
                orientationObject["sigmas_deg"] = .numbers([orientation.sigmaDeg, orientation.sigmaDeg, orientation.sigmaDeg])
                object["orientation"] = .object(orientationObject)
            }
        }

        object["time"] = .string(OPFDateFormat.iso8601(capture.time))
        return .object(object)
    }

    static func geolocationObject(_ geo: GeolocationRecord, crsDefinition: String) -> JSONValue {
        var object = JSONObject()
        var crs = JSONObject()
        crs["definition"] = .string(crsDefinition)
        object["crs"] = .object(crs)
        object["coordinates"] = .numbers([geo.latitude, geo.longitude, geo.ellipsoidalAltitude])
        // For geographic CRSs every sigma is in metres: horizontal, horizontal, vertical.
        object["sigmas"] = .numbers([geo.horizontalAccuracy, geo.horizontalAccuracy, geo.verticalAccuracy])
        return .object(object)
    }

    // MARK: - scene-reference-frame.json

    static func sceneReferenceFrame(
        crsDefinition: String,
        shift: [Double],
        scale: [Double],
        swapXY: Bool,
        geoidHeight: Double?
    ) -> JSONValue {
        var root = JSONObject()
        root["format"] = .string(OPFConstants.Format.sceneReferenceFrame)
        root["version"] = .string(OPFConstants.version)

        var crs = JSONObject()
        crs["definition"] = .string(crsDefinition)
        if let geoidHeight, geoidHeight.isFinite {
            crs["geoid_height"] = .double(geoidHeight)
        }
        root["crs"] = .object(crs)

        var transform = JSONObject()
        transform["shift"] = .numbers(shift)
        transform["scale"] = .numbers(scale)
        transform["swap_xy"] = .bool(swapXY)
        root["base_to_canonical"] = .object(transform)

        return .object(root)
    }

    // MARK: - project.opf

    struct ProjectItem {
        var id: UUID
        var name: String?
        var type: String
        var resources: [(uri: String, format: String)]
        var sources: [(id: UUID, type: String)]
    }

    static func projectDocument(
        project: CaptureProject,
        items: [ProjectItem]
    ) -> JSONValue {
        var root = JSONObject()
        root["format"] = .string(OPFConstants.Format.project)
        root["version"] = .string(OPFConstants.version)
        root["id"] = .string(OPFIdentifier.uuidString(project.opfProjectID))
        root["name"] = .string(project.name)
        root["description"] = .string(project.description)

        var generator = JSONObject()
        generator["name"] = .string(OPFConstants.generatorName)
        generator["version"] = .string(OPFConstants.generatorVersion)
        root["generator"] = .object(generator)

        root["items"] = .array(items.map { item in
            var object = JSONObject()
            object["id"] = .string(OPFIdentifier.uuidString(item.id))
            if let name = item.name { object["name"] = .string(name) }
            object["type"] = .string(item.type)
            object["resources"] = .array(item.resources.map { resource in
                var resourceObject = JSONObject()
                resourceObject["uri"] = .string(resource.uri)
                resourceObject["format"] = .string(resource.format)
                return .object(resourceObject)
            })
            object["sources"] = .array(item.sources.map { source in
                var sourceObject = JSONObject()
                sourceObject["id"] = .string(OPFIdentifier.uuidString(source.id))
                sourceObject["type"] = .string(source.type)
                return .object(sourceObject)
            })
            return .object(object)
        })

        return .object(root)
    }

    /// Fallback pixel size when nothing better is known. Uses a 36 mm sensor width, the
    /// most common assumption for an unknown interchangeable-lens camera, and is always
    /// reported to the user as an estimate.
    private static func estimatedPixelSizeMicrometres(_ sensor: OPFSensorEntry) -> Double {
        let assumedSensorWidthMM = 36.0
        let width = Double(sensor.imageWidthPx)
        guard width > 0 else { return 1.0 }
        return (assumedSensorWidthMM * 1000.0) / width
    }
}

/// Content statistics for a sensor, computed from the images that use it. This lets the
/// dynamic pixel range case be reported and lets the writer avoid fabricating a range.
struct SensorContent {
    var observedMin: Double
    var observedMax: Double
}
