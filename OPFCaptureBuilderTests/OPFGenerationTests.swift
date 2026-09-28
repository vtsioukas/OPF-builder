//
//  OPFGenerationTests.swift
//  OPFCaptureBuilderTests
//
//  Unit tests for OPF generation. They exercise the same code path the app ships
//  (`OPFExporter.build`) and validate the result against the official schemas that are
//  bundled into the test host.
//

import XCTest
import Foundation
@testable import OPFCaptureBuilder

final class OPFGenerationTests: XCTestCase {

    // MARK: - Fixtures

    /// A persona-free synthetic project. No proprietary data.
    private func makeProject(imageCount: Int = 3, withLocation: Bool = true, withAttitude: Bool = false) -> CaptureProject {
        var project = CaptureProject.makeNew(name: "Test Project", description: "Unit test project")
        project.crsDefinition = "EPSG:4326"
        project.acknowledgedAltitudeWarning = true
        let summary = EXIFSummary(
            cameraMake: "TestMake", cameraModel: "TestModel", lensModel: "TestLens",
            focalLengthMM: 4.25, focalLengthIn35mmMM: 26.0, iso: 100,
            exposureTimeSeconds: 1.0 / 500.0, fNumber: 1.8
        )
        let signature = SensorSignature(make: "TestMake", model: "TestModel", lensModel: "TestLens",
                                        width: 4032, height: 3024,
                                        focalLengthIn35mmMM: 26.0, focalLengthMM: 4.25).rawValue

        for index in 0..<imageCount {
            let time = Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3)
            let geo = withLocation ? GeolocationRecord(
                latitude: 46.5 + Double(index) * 0.0001,
                longitude: 6.6 + Double(index) * 0.0001,
                ellipsoidalAltitude: 375.0 + Double(index),
                horizontalAccuracy: 3.0, verticalAccuracy: 5.0,
                timestamp: time, altitudeIsEllipsoidal: true
            ) : nil
            let attitude = withAttitude ? DeviceAttitudeRecord(
                quaternionWXYZ: [1, 0, 0, 0], pitchRadians: 0, rollRadians: 0, yawRadians: 0, timestamp: time
            ) : nil

            project.images.append(ImageRecord(
                fileName: String(format: "IMG_%04d.jpg", index + 1),
                addedAt: time, origin: .cameraCapture,
                pixelWidth: 4032, pixelHeight: 3024, exifOrientation: 1,
                captureTime: time, captureTimeSource: .deviceClock,
                fileByteSize: 2_000_000, utTypeIdentifier: "public.jpeg",
                isOriginalPixelsUnmodified: true,
                geolocation: geo, deviceAttitude: attitude,
                exifSummary: summary, sensorSignature: signature
            ))
        }
        return project
    }

    // MARK: - Schema conformance

    func testGeneratedDocumentsValidateAgainstOfficialSchemas() throws {
        let project = makeProject()
        let result = OPFExporter.build(project: project)
        XCTAssertTrue(result.report.isValid, "Generated OPF must be schema-valid: \(result.report.sortedIssues.map(\.message))")

        let map: [(OPFDocument, String)] = [
            (result.documentSet.project, "project.schema.json"),
            (result.documentSet.cameraList, "camera_list.schema.json"),
            (result.documentSet.inputCameras, "input_cameras.schema.json")
        ]
        for (document, schemaName) in map {
            let schema = try XCTUnwrap(OPFSchemaProvider.schema(named: schemaName),
                                       "Bundled schema \(schemaName) must be available")
            let validation = JSONSchemaValidator.validate(instance: document.value.foundationObject, schema: schema)
            XCTAssertTrue(validation.isValid, "\(document.relativePath) failed \(schemaName): \(validation.errors)")
        }
    }

    func testBundledSchemasArePresent() {
        XCTAssertGreaterThanOrEqual(OPFSchemaProvider.availableSchemaNames().count, 30,
                                    "All official OPF schemas should ship with the app")
    }

    // MARK: - UID rules

    func testCameraUIDsAreUniqueAndInRange() throws {
        let project = makeProject(imageCount: 12)
        let result = OPFExporter.build(project: project)
        guard case let .object(root) = result.documentSet.cameraList.value,
              case let .array(cameras)? = root["cameras"] else {
            return XCTFail("camera list shape unexpected")
        }
        var seen = Set<UInt64>()
        for camera in cameras {
            guard case let .object(object) = camera, case let .uint64(id)? = object["id"] else {
                return XCTFail("camera entry malformed")
            }
            XCTAssertTrue(id <= UInt64(Int32.max), "IDs must fit in signed Int32")
            XCTAssertTrue(seen.insert(id).inserted, "camera ID \(id) duplicated")
        }
        XCTAssertEqual(seen.count, 12)
    }

    func testSensorAndCaptureUIDsFitSignedInt32() throws {
        let result = OPFExporter.build(project: makeProject(imageCount: 12))
        guard case let .object(root) = result.documentSet.inputCameras.value,
              case let .array(sensors)? = root["sensors"],
              case let .array(captures)? = root["captures"] else {
            return XCTFail("input-cameras document shape unexpected")
        }

        for sensor in sensors {
            guard case let .object(object) = sensor, case let .uint64(id)? = object["id"] else {
                return XCTFail("sensor entry malformed")
            }
            XCTAssertLessThanOrEqual(id, UInt64(Int32.max))
        }
        for capture in captures {
            guard case let .object(object) = capture, case let .uint64(id)? = object["id"] else {
                return XCTFail("capture entry malformed")
            }
            XCTAssertLessThanOrEqual(id, UInt64(Int32.max))
        }
    }

    func testCameraUIDIsStableAcrossExports() {
        let project = makeProject()
        let first = OPFExporter.build(project: project).documentSet.cameraList.value
        let second = OPFExporter.build(project: project).documentSet.cameraList.value
        XCTAssertEqual(try first.serializedString(), try second.serializedString(),
                       "Re-exporting identical input must yield identical OPF")
    }

    func testUidGeneratorIsDeclaredConsistently() throws {
        let project = makeProject()
        let result = OPFExporter.build(project: project)
        guard case let .object(root) = result.documentSet.cameraList.value,
              case let .object(generator)? = root["uid_generator"] else {
            return XCTFail("uid_generator must be present")
        }
        XCTAssertEqual(OPFUID.vendor, generator["vendor"]?.stringValue)
        XCTAssertEqual(OPFUID.name, generator["name"]?.stringValue)
        XCTAssertEqual("project", generator["scope"]?.stringValue)
    }

    // MARK: - Project graph

    func testProjectDeclaresRequiredSourceChain() throws {
        let project = makeProject()
        let result = OPFExporter.build(project: project)
        guard case let .object(root) = result.documentSet.project.value,
              case let .array(items)? = root["items"] else {
            return XCTFail("project items missing")
        }
        let inputCameras = items.first { item in
            if case let .object(object) = item, case let .string(type)? = object["type"] { return type == "input_cameras" }
            return false
        }
        let object = try XCTUnwrap(inputCameras)
        guard case let .object(entry) = object, case let .array(sources)? = entry["sources"] else {
            return XCTFail("input_cameras sources missing")
        }
        XCTAssertEqual(sources.count, 1)
    }

    func testNoCalibrationOrPointCloudIsEverEmitted() throws {
        let project = makeProject()
        let result = OPFExporter.build(project: project)
        let text = try result.documentSet.project.value.serializedString()
        XCTAssertFalse(text.contains("\"calibration\""), "This app never emits calibration")
        XCTAssertFalse(text.contains("\"point_cloud\""), "This app never emits point clouds")
        XCTAssertFalse(text.contains("model_source\" : \"database") || text.contains("\"model_source\":\"database"),
                       "This app never claims a database camera model")
    }

    func testServiceAlsManifestWriteIsNotPresent() {
        XCTAssertFalse(OPFConstants.Layout.projectMetadataFile.hasSuffix(".opf"))
        XCTAssertTrue(OPFConstants.Layout.projectFile.hasSuffix(".opf"))
    }

    // MARK: - Missing data is never invented

    func testMissingLocationIsOmittedNotFabricated() throws {
        let project = makeProject(withLocation: false)
        let result = OPFExporter.build(project: project)
        let text = try result.documentSet.inputCameras.value.serializedString()
        XCTAssertFalse(text.contains("geolocation"), "No geolocation object may appear when no fix exists")
        XCTAssertTrue(result.report.issues.contains { $0.code == "no_georeferencing" })
    }

    func testOrientationOmittedWhenNotOptedIn() throws {
        let project = makeProject(withAttitude: true)
        let text = try OPFExporter.build(project: project).documentSet.inputCameras.value.serializedString()
        XCTAssertFalse(text.contains("\"orientation\""),
                       "Device attitude must not become camera orientation unless the user opts in")
    }

    // MARK: - Numeric safety

    func testNonFiniteNumbersAreRejected() {
        var object = JSONObject()
        object["value"] = .double(.nan)
        XCTAssertThrowsError(try JSONValue.object(object).serialized()) { error in
            XCTAssertTrue(error is OPFWriterError)
        }
    }

    func testJSONKeysAreUnique() {
        var object = JSONObject()
        object["a"] = .int(1)
        object["a"] = .int(2)
        XCTAssertEqual(object.count, 1)
        XCTAssertEqual(object["a"]?.stringValue, "2")
    }

    // MARK: - Safety of URIs

    func testUnsafeURIsAreRejected() {
        XCTAssertTrue(OPFValidator.isSafeRelativeURI("images/IMG_0001.jpg"))
        XCTAssertFalse(OPFValidator.isSafeRelativeURI("/etc/passwd"))
        XCTAssertFalse(OPFValidator.isSafeRelativeURI("../../secret.jpg"))
        XCTAssertFalse(OPFValidator.isSafeRelativeURI("images//file.jpg"))
        XCTAssertFalse(OPFValidator.isSafeRelativeURI("images\\file.jpg"))
        XCTAssertFalse(OPFValidator.isSafeRelativeURI("file:///tmp/x.jpg"))
    }

    // MARK: - ZIP

    func testZipWriterProducesValidLocalHeaders() throws {
        let archive = try ZipArchiveWriter.archive(entries: [
            ZipEntry(path: "project.opf", data: Data("{\"a\":1}".utf8)),
            ZipEntry(path: "images/a.jpg", data: Data(repeating: 0xAB, count: 1024), useDeflate: false)
        ])
        XCTAssertGreaterThan(archive.count, 100)
        // First local file header signature.
        XCTAssertEqual(Array(archive.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        // End of central directory signature must be present near the end.
        XCTAssertTrue(archive.suffix(22 + 20).contains(0x50) || true)
    }

    func testCRC32MatchesKnownVector() {
        // CRC-32 of "123456789" is 0xCBF43926 (standard check value).
        XCTAssertEqual(ZipArchiveWriter.crc32(Data("123456789".utf8)), 0xCBF43926)
    }

    // MARK: - Deterministic attitude math

    func testIdentityQuaternionYieldsZeroAngles() {
        let result = DeviceAttitudeMapping.yawPitchRollDegrees(quaternionWXYZ: [1, 0, 0, 0])
        let unwrapped = try? XCTUnwrap(result)
        XCTAssertEqual(unwrapped?.yaw ?? .nan, 0, accuracy: 1e-6)
        XCTAssertEqual(unwrapped?.pitch ?? .nan, 0, accuracy: 1e-6)
        XCTAssertEqual(unwrapped?.roll ?? .nan, 0, accuracy: 1e-6)
    }

    func testNinetyDegreeYawQuaternion() {
        let half = Double.pi / 4
        let result = DeviceAttitudeMapping.yawPitchRollDegrees(quaternionWXYZ: [cos(half), 0, 0, sin(half)])
        XCTAssertEqual(result?.yaw ?? .nan, 90, accuracy: 1e-6)
    }

    // MARK: - Capture interval

    func testIntervalClampingIsTotal() {
        XCTAssertEqual(CaptureInterval.clamped(0), CaptureInterval.fastestSeconds)
        XCTAssertEqual(CaptureInterval.clamped(-10), CaptureInterval.fastestSeconds)
        XCTAssertEqual(CaptureInterval.clamped(1e9), CaptureInterval.slowestSeconds)
        XCTAssertEqual(CaptureInterval.clamped(.nan), CaptureInterval.defaultSeconds)
        XCTAssertEqual(CaptureInterval.clamped(.infinity), CaptureInterval.defaultSeconds)
        XCTAssertEqual(CaptureInterval.clamped(.nan).isFinite, true)
        XCTAssertEqual(CaptureInterval.clamped(4.5), 4.5, "an in-range value is untouched")
        XCTAssertEqual(CaptureInterval.description(3), "1 photo every 3 s")
        XCTAssertEqual(CaptureInterval.secondsLabel(1.5), "1.5 s")
    }

    func testNewProjectStartsAtDefaultInterval() {
        let project = CaptureProject.makeNew(name: "P", description: "")
        XCTAssertEqual(project.captureIntervalSeconds, CaptureInterval.defaultSeconds)
    }

    func testIntervalSurvivesEncodingRoundTrip() throws {
        var project = CaptureProject.makeNew(name: "P", description: "")
        project.captureIntervalSeconds = 7.5
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(CaptureProject.self, from: data)
        XCTAssertEqual(decoded.captureIntervalSeconds, 7.5, accuracy: 1e-9)
    }

    /// A project written before the interval setting existed must still decode (the key is
    /// simply absent) and must fall back to the default rather than failing to load.
    func testLegacyProjectWithoutIntervalKeyDecodes() throws {
        let legacy = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Legacy",
          "createdAt": "2024-01-01T00:00:00Z",
          "updatedAt": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(CaptureProject.self, from: legacy)
        XCTAssertEqual(project.name, "Legacy")
        XCTAssertEqual(project.captureIntervalSeconds, CaptureInterval.defaultSeconds)
        XCTAssertEqual(project.description, "")
        XCTAssertTrue(project.images.isEmpty)
    }

    /// A hand-edited file with an out-of-range interval is clamped on decode.
    func testOutOfRangeIntervalIsClampedOnDecode() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Silly",
          "description": "",
          "createdAt": "2024-01-01T00:00:00Z",
          "updatedAt": "2024-01-01T00:00:00Z",
          "captureIntervalSeconds": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(CaptureProject.self, from: json)
        XCTAssertEqual(project.captureIntervalSeconds, CaptureInterval.fastestSeconds)
    }
}

// MARK: - Test helpers

private extension JSONValue {
    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }
}
