//
//  OPFValidator.swift
//  OPFCaptureBuilder
//
//  Validates a generated OPF document set in three layers:
//
//   1. JSON Schema conformance against the vendored official schemas.
//   2. OPF business rules that JSON Schema cannot express (unique camera IDs, consistent
//      uid_generator, every referenced resource present, safe relative URIs, …).
//   3. Data sanity (no non-finite numbers, no invented/placeholder values).
//
//  The result drives the in-app Validation Report shown before export.
//

import Foundation

enum OPFValidator {

    /// Validates an in-memory document set without touching disk. `resourceExists` is
    /// called with each referenced URI so the caller can check the images folder.
    static func validate(
        documentSet: OPFDocumentSet,
        project: CaptureProject,
        schemaProvider: (String) -> [String: Any]?,
        resourceExists: (String) -> Bool
    ) -> ValidationReport {
        var report = ValidationReport()
        var knownCodes = Set<String>()

        func add(_ severity: ValidationSeverity, _ code: String, _ message: String, document: String? = nil) {
            report.issues.append(ValidationIssue(severity: severity, code: code, message: message, document: document))
            knownCodes.insert(code)
        }

        // ---------------------------------------------------------------- schema
        let schemaMap: [(OPFDocument, String)] = [
            (documentSet.project, "project.schema.json"),
            (documentSet.cameraList, "camera_list.schema.json"),
            (documentSet.inputCameras, "input_cameras.schema.json")
        ]

        for (document, schemaName) in schemaMap {
            report.checkedDocuments.append(document.relativePath)
            guard let schema = schemaProvider(schemaName) else {
                add(.warning, "schema_unavailable", "The official schema \(schemaName) could not be loaded from the app bundle.", document: document.relativePath)
                continue
            }
            let result = JSONSchemaValidator.validate(
                instance: document.value.foundationObject,
                schema: schema
            )
            for error in result.errors {
                add(.error, "schema", error, document: document.relativePath)
            }
        }

        if let sceneFrame = documentSet.sceneReferenceFrame {
            report.checkedDocuments.append(sceneFrame.relativePath)
            if let schema = schemaProvider("scene_reference_frame.schema.json") {
                let result = JSONSchemaValidator.validate(instance: sceneFrame.value.foundationObject, schema: schema)
                for error in result.errors {
                    add(.error, "schema", error, document: sceneFrame.relativePath)
                }
            } else {
                add(.warning, "schema_unavailable", "The official schema scene_reference_frame.schema.json could not be loaded.", document: sceneFrame.relativePath)
            }
        }

        // ------------------------------------------------------- project item graph
        validateProjectGraph(documentSet: documentSet, add: add)

        // ------------------------------------------------------------- camera list
        var cameraURIs = Set<String>()
        var cameraIDs = Set<UInt64>()
        if case let .object(root) = documentSet.cameraList.value,
           case let .array(cameras)? = root["cameras"] {
            let uidGenerator = root["uid_generator"]
            if uidGenerator == nil {
                add(.warning, "uid_generator_missing",
                    "camera-list.json does not declare a uid_generator. Consumers then assume project-scoped UIDs.",
                    document: documentSet.cameraList.relativePath)
            }
            for camera in cameras {
                guard case let .object(object) = camera else { continue }
                if case let .uint64(id)? = object["id"] {
                    if !cameraIDs.insert(id).inserted {
                        add(.error, "duplicate_camera_id",
                            "Camera ID \(id) appears more than once. OPF requires unique camera UIDs.",
                            document: documentSet.cameraList.relativePath)
                    }
                }
                if case let .string(uri)? = object["uri"] {
                    if !cameraURIs.insert(uri).inserted {
                        add(.info, "duplicate_camera_uri",
                            "The image \"\(uri)\" is referenced by more than one camera entry.",
                            document: documentSet.cameraList.relativePath)
                    }
                    validateRelativeURI(uri, document: documentSet.cameraList.relativePath, add: add, resourceExists: resourceExists)
                }
            }
            if cameras.isEmpty {
                add(.warning, "no_images", "camera-list.json contains no cameras because the project has no photographs yet, so the export is empty.", document: documentSet.cameraList.relativePath)
            }
        }

        // ------------------------------------------------------------ input cameras
        var sensorIDs = Set<UInt64>()
        var captureIDs = Set<UInt64>()
        var cameraReferencesFromCaptures = Set<UInt64>()
        var totalBandWeightsBySensor: [UInt64: Double] = [:]

        if case let .object(root) = documentSet.inputCameras.value {
            if case let .array(sensors)? = root["sensors"] {
                for sensor in sensors {
                    guard case let .object(object) = sensor else { continue }
                    if case let .uint64(id)? = object["id"] {
                        if !sensorIDs.insert(id).inserted {
                            add(.error, "duplicate_sensor_id", "Sensor ID \(id) is duplicated.", document: documentSet.inputCameras.relativePath)
                        }
                    }
                    var sensorID: UInt64 = 0
                    if case let .uint64(id)? = object["id"] { sensorID = id }

                    if case let .array(bands)? = object["bands"] {
                        let total = bands.reduce(0.0) { partial, band in
                            if case let .object(bandObject) = band, case let .double(weight)? = bandObject["weight"] { return partial + weight }
                            if case let .object(bandObject) = band, case let .int(weight)? = bandObject["weight"] { return partial + Double(weight) }
                            return partial
                        }
                        totalBandWeightsBySensor[sensorID] = total
                        if abs(total - 1.0) > 1e-6 {
                            add(.warning, "band_weights",
                                "Sensor \(sensorID) band weights sum to \(total); the specification expects 1.",
                                document: documentSet.inputCameras.relativePath)
                        }
                    }
                    if case let .array(size)? = object["image_size_px"], size.count == 2 {
                        for (index, component) in size.enumerated() {
                            if case let .double(value) = component, value <= 0 {
                                add(.error, "invalid_image_size",
                                    "Sensor \(sensorID) image_size_px[\(index)] is not positive.",
                                    document: documentSet.inputCameras.relativePath)
                            }
                        }
                    }
                }
            }

            if case let .array(captures)? = root["captures"] {
                for capture in captures {
                    guard case let .object(object) = capture else { continue }
                    if case let .uint64(id)? = object["id"] {
                        if !captureIDs.insert(id).inserted {
                            add(.error, "duplicate_capture_id", "Capture ID \(id) is duplicated.", document: documentSet.inputCameras.relativePath)
                        }
                    }
                    if case let .array(cameras)? = object["cameras"] {
                        for camera in cameras {
                            guard case let .object(cameraObject) = camera else { continue }
                            if case let .uint64(sensorID)? = cameraObject["sensor_id"], !sensorIDs.contains(sensorID) {
                                add(.error, "dangling_sensor_reference",
                                    "A capture references sensor \(sensorID) which is not declared in the sensors array.",
                                    document: documentSet.inputCameras.relativePath)
                            }
                            if case let .uint64(cameraID)? = cameraObject["id"] {
                                // A camera entry only needs to resolve to a camera-list entry.
                                // The same camera may appear in several captures, so this is a
                                // membership check, not a uniqueness check.
                                cameraReferencesFromCaptures.insert(cameraID)
                                if !cameraIDs.contains(cameraID) {
                                    add(.error, "camera_not_in_list",
                                        "Camera ID \(cameraID) appears in a capture but not in camera-list.json.",
                                        document: documentSet.inputCameras.relativePath)
                                }
                            }
                            if case let .string(modelSource)? = cameraObject["model_source"], modelSource == "database" {
                                add(.info, "model_source_database",
                                    "A camera claims model_source \"database\". This app never consults a camera database, so this would be inaccurate.",
                                    document: documentSet.inputCameras.relativePath)
                            }
                            if case let .object(range)? = cameraObject["pixel_range"] {
                                if case let .double(minimum)? = range["min"], case let .double(maximum)? = range["max"], minimum >= maximum {
                                    add(.error, "invalid_pixel_range", "Pixel range min is not smaller than max.", document: documentSet.inputCameras.relativePath)
                                }
                            }
                        }
                    }
                    if case let .object(geolocation)? = object["geolocation"] {
                        if case let .array(coordinates)? = geolocation["coordinates"] {
                            for (index, component) in coordinates.enumerated() where component.isNonFiniteNumber {
                                add(.error, "non_finite_number",
                                    "geolocation.coordinates[\(index)] is not a finite number.",
                                    document: documentSet.inputCameras.relativePath)
                            }
                        }
                        if case let .array(sigmas)? = geolocation["sigmas"] {
                            for (index, component) in sigmas.enumerated() where component.isNonFiniteNumber {
                                add(.error, "non_finite_number",
                                    "geolocation.sigmas[\(index)] is not a finite number.",
                                    document: documentSet.inputCameras.relativePath)
                            }
                        }
                    }
                }
            }
        }

        // Cross-checks between the two camera representations.
        for id in cameraReferencesFromCaptures where !cameraIDs.contains(id) {
            add(.error, "camera_id_mismatch", "Camera \(id) exists in captures but not in the camera list.", document: documentSet.inputCameras.relativePath)
        }

        // --------------------------------------------------------- data completeness
        if project.images.isEmpty {
            add(.warning, "empty_project", "The project contains no photographs. Add images before exporting for photogrammetry.")
        }

        let camerasWithLocation = project.images.filter { $0.geolocation != nil }.count
        if camerasWithLocation == 0 && !project.images.isEmpty {
            add(.info, "no_georeferencing", "No image has a location fix. The project will not be georeferenced.")
        }
        let camerasWithAttitude = project.images.filter { $0.deviceAttitude != nil }.count
        if project.exportEstimatedOrientation && camerasWithAttitude == 0 && !project.images.isEmpty {
            add(.warning, "orientation_requested_no_data", "Estimated orientation export is on but no capture recorded device attitude, so no orientation was written.")
        }

        if project.emitSceneReferenceFrame && camerasWithLocation == 0 && !project.images.isEmpty {
            add(.warning, "scene_frame_without_geolocation", "A scene reference frame was requested but no image has a location fix.", document: OPFConstants.Layout.sceneReferenceFrameFile)
        }

        if !project.acknowledgedAltitudeWarning && camerasWithLocation > 0 {
            add(.info, "altitude_semantics", "Altitude in this project is WGS 84 ellipsoidal height, not orthometric height. Confirm that this suits your downstream workflow.")
        }

        _ = knownCodes
        return report
    }

    // MARK: - Project graph

    private static func validateProjectGraph(
        documentSet: OPFDocumentSet,
        add: (ValidationSeverity, String, String, String?) -> Void
    ) {
        guard case let .object(root) = documentSet.project.value,
              case let .array(items)? = root["items"] else { return }

        var itemIDs = Set<String>()
        var itemTypesByID: [String: String] = [:]

        for item in items {
            guard case let .object(object) = item else { continue }
            guard case let .string(type)? = object["type"] else { continue }
            var identifier = ""
            if case let .string(id)? = object["id"] { identifier = id }
            if identifier.isEmpty {
                add(.error, "item_missing_id", "A project item has no id.", documentSet.project.relativePath)
                continue
            }
            if !OPFIdentifier.isValidUUIDString(identifier) {
                add(.error, "invalid_uuid", "Project item id \"\(identifier)\" is not a lower-case UUID.", documentSet.project.relativePath)
            }
            if !itemIDs.insert(identifier).inserted {
                add(.error, "duplicate_item_id", "Project item id \(identifier) is duplicated.", documentSet.project.relativePath)
            }
            itemTypesByID[identifier] = type

            guard case let .array(resources)? = object["resources"] else { continue }
            for resource in resources {
                guard case let .object(resourceObject) = resource else { continue }
                if case let .string(uri)? = resourceObject["uri"] {
                    validateRelativeURI(uri, document: documentSet.project.relativePath, add: add, resourceExists: { _ in true })
                }
                guard case let .string(format)? = resourceObject["format"] else { continue }
                let expected = expectedFormat(forItemType: type)
                if let expected, format != expected {
                    add(.error, "resource_format_mismatch",
                        "Item type \(type) must reference a resource of format \(expected), found \(format).",
                        documentSet.project.relativePath)
                }
            }
        }

        // Required sources per item type, from the official project schema’s
        // required_sources_per_item_type dictionary.
        let requiredSources: [String: [String]] = [
            "input_cameras": ["camera_list"],
            "projected_input_cameras": ["scene_reference_frame", "input_cameras"],
            "input_control_points": ["camera_list"],
            "projected_control_points": ["scene_reference_frame", "input_control_points"],
            "constraints": ["input_control_points"],
            "calibration": ["input_cameras", "scene_reference_frame"],
            "point_cloud": ["scene_reference_frame"]
        ]

        for item in items {
            guard case let .object(object) = item,
                  case let .string(type)? = object["type"],
                  let required = requiredSources[type] else { continue }
            var providedTypes = Set<String>()
            if case let .array(sources)? = object["sources"] {
                for source in sources {
                    guard case let .object(sourceObject) = source else { continue }
                    if case let .string(sourceID)? = sourceObject["id"] {
                        if let sourceType = itemTypesByID[sourceID] {
                            providedTypes.insert(sourceType)
                        } else {
                            add(.error, "dangling_source", "Item \(type) references source \(sourceID), which does not exist in this project.", documentSet.project.relativePath)
                        }
                    }
                }
            }
            for needed in required where !providedTypes.contains(needed) {
                add(.error, "missing_required_source",
                    "Item type \(type) requires a source of type \(needed).",
                    documentSet.project.relativePath)
            }
        }
    }

    private static func expectedFormat(forItemType type: String) -> String? {
        switch type {
        case OPFConstants.ResourceType.cameraList: return OPFConstants.Format.cameraList
        case OPFConstants.ResourceType.inputCameras: return OPFConstants.Format.inputCameras
        case OPFConstants.ResourceType.sceneReferenceFrame: return OPFConstants.Format.sceneReferenceFrame
        default: return nil
        }
    }

    // MARK: - URI safety

    /// Rejects absolute paths, escaping paths, backslashes and control characters. OPF
    /// uses RFC 3986 URI references relative to the containing file, so the only safe
    /// form for our resources is a forward-slash relative path without `..` segments.
    static func isSafeRelativeURI(_ uri: String) -> Bool {
        guard !uri.isEmpty else { return false }
        if uri.hasPrefix("/") || uri.hasPrefix("\\") { return false }
        if uri.lowercased().hasPrefix("file:") { return false }
        if uri.contains("\\") { return false }
        if uri.contains("//") { return false }
        if uri.unicodeScalars.contains(where: { $0.value < 0x20 }) { return false }
        let segments = uri.split(separator: "/", omittingEmptySubsequences: false)
        for segment in segments where segment == ".." || segment == "." { return false }
        if uri.hasSuffix("/") { return false }
        return true
    }

    private static func validateRelativeURI(
        _ uri: String,
        document: String,
        add: (ValidationSeverity, String, String, String?) -> Void,
        resourceExists: (String) -> Bool
    ) {
        if !isSafeRelativeURI(uri) {
            add(.error, "unsafe_uri", "Resource URI \"\(uri)\" is not a safe relative path.", document)
            return
        }
        if !resourceExists(uri) {
            add(.error, "missing_resource", "The referenced resource \"\(uri)\" does not exist.", document)
        }
    }
}

private extension JSONValue {
    var isNonFiniteNumber: Bool {
        if case let .double(value) = self { return !value.isFinite }
        return false
    }
}
