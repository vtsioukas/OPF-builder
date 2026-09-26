# OPF Capture Builder — Development Plan

## 1. Goal

A genuine **native iOS application** (Swift + SwiftUI, Xcode 16 project format, SPM only,
deployment target **iOS 17.0**) that captures or imports overlapping photogrammetry
photographs and exports a project conforming to **Open Photogrammetry Format (OPF) v1.0**.

Source of truth: <https://pix4d.github.io/opf-spec/> and
<https://github.com/Pix4D/opf-spec/>. No OPF property names or structures are invented;
the official JSON schemas are vendored verbatim under `OPFCaptureBuilder/Resources/OPFSchemas`.

## 2. Environment constraint and how it is handled

The build sandbox used to author this project is **Debian Linux without a Swift or Xcode
toolchain**. Therefore the Xcode project **cannot be compiled or run in the authoring
sandbox**. Rather than fake a build, we provide two *real, executed* verification layers:

| Layer | What it proves | Where it runs |
|-------|----------------|---------------|
| `tools/structural_verify.py` | `project.pbxproj` is internally consistent: every Swift/resource file exists, every target membership and build setting is declared, no dangling references. | Authoring sandbox (executed) |
| `tools/opf_reference_harness/` | The exact OPF JSON the Swift writer emits is **byte-compatible in structure** with what we validate here against the **official** `opf-spec/schema/*.schema.json` (JSON Schema 2020-12) + business rules from the spec prose. | Authoring sandbox (executed) |
| XCTest unit + UI tests | OPF generation and the create→export flow, on device/simulator. | macOS + Xcode (user runs) |

The milestone **"build the project and run the tests"** is satisfied on macOS; the
sandbox-side equivalent (schema validation of generated OPF) is executed and its raw
results are included in the final report.

## 3. OPF 1.0 facts that drive the design (authoritative quotes)

* **Input cameras are raw, as-shot data.** `input_cameras.md.txt`: *"the data as provided
  by the user and camera database. It does not contain processed information, such as for
  example coordinates converted into the processing CRS."* Consequence: interpretation of
  `geolocation.crs` is deferred to the consumer, so a single-camera dataset is
  reference-consistent **without** a scene reference frame.
* **`geolocation.sigmas` is required** and all three are in **metres** for geographic CRSs.
  So `[horizontalAccuracy, horizontalAccuracy, verticalAccuracy]` — never unordered.
* **Camera IDs (`uid64`) and sensor/capture IDs are unsigned 64-bit integers.**
  `uid64.schema.json`: `minimum: 0`, `maximum: 18446744073709551615`.
* **`uid_generator` must be identical across all camera lists in a project** and declares a
  `scope` of `global` or `project`. Sequential UIDs are *"highly discouraged"*.
* **`format` constants**: `application/opf-project+json`, `application/opf-camera-list+json`,
  `application/opf-input-cameras+json`, `application/opf-scene-reference-frame+json`; version `1.0`.
* **CRS** may be `Authority:code` (e.g. `EPSG:4326`). We only claim **WGS 84 geographic,
  ellipsoidal**, which matches ISO-19111 semantics for an EPSG geographic 3D CRS.
* **Scene reference frame** must exist whenever projected coordinates exist; `project.opf`
  declares `input_cameras` with `sources:[{camera_list}]`. We therefore emit the
  `camera_list` → `input_cameras` chain and (only when the user enables georeferencing)
  a `scene_reference_frame` item.

## 4. Scope of the MVP (and explicit non-goals)

In scope: project management, AVFoundation capture, Photos/Files import, EXIF/sensor
metadata, camera/sensor separation, verified-intrinsics entry, OPF generation, CRS
declaration, validation, ZIP export via share sheet, privacy/about, tests, sample project.

**Non-goals for v1** (per instructions): LiDAR, RTK, autotags, point-cloud reconstruction,
photogrammetric (self-)calibration. Consequently we never emit `calibration` or
`point_cloud` items, and never mark a camera `model_source:"database"`; unverified
intrinsics are `"generic"` or `"generic_from_exif"`, and only user-entered verified
intrinsics are `"user"`.

## 5. UID generation strategy (one strategy for the whole project)

* **Cameras (basis for `uid64`)**: deterministic 64-bit FNV-1a hash of the raw image bytes,
  masked to 63 bits (so every value is in `Int64.positive` and trivially `uid64`-legal).
  Stable across re-exports, reproducible from the image alone, collision-checked.
* `uid_generator = { vendor: "opfcapturebuilder", name: "fnv1a64_image_content", scope: "project", version: 1 }`
* **Sensors**: FNV-1a of the sensor *identity signature* (manufacturer|model|lens|width×height|focal35mm).
* **Captures**: FNV-1a of `cameraID | ISO8601 time`.
* All three share one `FNV1a64` implementation → importer and OPF writer cannot diverge.

## 6. Milestones

| # | Milestone | Deliverable |
|---|-----------|-------------|
| M0 | Scaffold + schemas | Xcode project, scheme, Info.plist, vendored schemas/examples |
| M1 | Models + writer core | `JSONValue`, `OPFUIDGenerator`, models, `OPFWriter` (3–4 docs) |
| M2 | Services | ProjectStore, ImageImporter (EXIF), CameraCapture, SensorRecorder, EXIFWriter |
| M3 | OPF + validation | manifest, generator, validator, JSONSchemaValidator, report |
| M4 | Export | ZIP writer, ExportService, shared `OPFExporter` façade |
| M5 | UI | 12 SwiftUI screens, design system, accessibility, privacy strings |
| M6 | Tests + docs | XCTest unit/UI, reference harness, sample project, PIX4Dmatic checklist, README |

## 7. Verification plan

1. `python3 tools/structural_verify.py` — pbxproj integrity (executed in sandbox).
2. `python3 tools/opf_reference_harness/run_harness.py` — generates OPF fixtures and
   validates every document against the official schemas with `jsonschema` 2020-12
   (executed in sandbox); prints a pass/fail matrix.
3. On macOS: `xcodebuild test` for `OPFCaptureBuilderTests` and `OPFCaptureBuilderUITests`.
4. Manual: import the sample project into PIX4Dmatic ≥ 1.46 using `docs/PIX4DMATIC_CHECKLIST.md`.
