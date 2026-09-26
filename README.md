# OPF Capture Builder

A **native iOS application** (Swift, SwiftUI, Xcode 16 project format, Swift Package
Manager, **no CocoaPods**) that captures or imports overlapping photogrammetry
photographs and exports a project conforming to **version 1.0 of the Open Photogrammetry
Format (OPF)**.

OPF source of truth: <https://pix4d.github.io/opf-spec/> · <https://github.com/Pix4D/opf-spec/>

---

## What it does

* **Project management** — create, list, open, rename, duplicate, delete; shows image count and storage size.
* **Camera capture** — native AVFoundation, original-resolution JPEG or HEIC selected before capture, duplicate-request guard.
* **Image importing** — Photos and Files, EXIF read-only, and a per-import report of *missing* metadata.
* **Sensor metadata** — CoreLocation (latitude/longitude/**ellipsoidal** altitude, horizontal + vertical accuracy, timestamp), CoreMotion device attitude stored as a quaternion.
* **Camera information** — separates the physical camera/lens (**sensor**) from individual captures; unverified intrinsics are labelled *estimated/generic*, never *calibrated*.
* **OPF generation** — `project.opf`, `camera-list.json`, `input-cameras.json`, optional `scene-reference-frame.json`, images under `images/`.
* **Validation** — official JSON Schema checks plus OPF business rules, with an in-app report before export.
* **Export** — ZIP of the whole project directory shared through the iOS share sheet, plus `validation-report.txt`, with safe temporary-file cleanup.
* **Privacy** — offline, no accounts, no analytics, no advertising, no tracking, no uploads.

## Explicit non-goals for this version

LiDAR, RTK, autotags, point-cloud reconstruction and photogrammetric self-calibration are
**out of scope**. As a direct consequence the app **never** emits a `calibration` or
`point_cloud` item, and never marks a camera `model_source: "database"`.

---

## Requirements

| | |
|---|---|
| macOS | 14 Sonoma or newer |
| Xcode | 16.0 or newer |
| iOS deployment target | **17.0** |
| Swift | 5.0 (language mode), Swift 6-ready code |
| Dependencies | **Swift Package Manager only** — the project has *zero* external package dependencies |
| Device | A physical iPhone is required for camera capture, GPS and motion. The Simulator can run the UI and the sample project. |

## Open the project

```bash
git clone <this-repo> OPFCaptureBuilder
cd OPFCaptureBuilder
open OPFCaptureBuilder.xcodeproj
```

The project uses Xcode 16 **synchronized folder groups**, so every `.swift` file under
`OPFCaptureBuilder/`, `OPFCaptureBuilderTests/` and `OPFCaptureBuilderUITests/` is part of
the target automatically — there is no file to add by hand.

## Build and test

```bash
# Build for a connected device
xcodebuild -project OPFCaptureBuilder.xcodeproj \
           -scheme OPFCaptureBuilder \
           -destination 'generic/platform=iOS' \
           build

# Run unit + UI tests on a simulator
xcodebuild -project OPFCaptureBuilder.xcodeproj \
           -scheme OPFCaptureBuilder \
           -destination 'platform=iOS Simulator,name=iPhone 15' \
           test
```

Or press **⌘U** in Xcode.

### First-run notes

* **Signing.** Select the `OPFCaptureBuilder` target → *Signing & Capabilities* → choose your
  team. `DEVELOPMENT_TEAM` is intentionally empty so the project is portable.
* **Bundle identifier.** `com.opfcapturebuilder.photogrammetry`. Change it if it clashes.
* **Permissions.** Camera, Photos, Location (when-in-use) and Motion prompts are described
  in `Config/Info.plist`. **No background location** access is requested.

---

## Repository layout

```
OPFCaptureBuilder.xcodeproj/        Xcode project (Xcode 16, objectVersion 77)
Config/Info.plist                   privacy strings + launch configuration
OPFCaptureBuilder/
  App/                              entry point, app model
  Models/                           CaptureProject, ImageRecord, sensors, validation, constants
  OPF/                              JSON writer, JSON Schema validator, OPF writer/validator,
                                    UID strategy, attitude→YPR mapping
  Services/                         project store, EXIF, importer, capture, sensors, ZIP, export
  Views/                            12 SwiftUI screens + design system
  Resources/OPFSchemas/             vendored official OPF schemas + examples (see ATTRIBUTION.md)
Resources/Assets.xcassets/          app icon + accent colour
OPFCaptureBuilderTests/             XCTest unit tests for OPF generation
OPFCaptureBuilderUITests/           XCUITest for create + export flow
tools/opf_reference_harness/        executed Python harness (schema validation)
tools/structural_verify.py          executed project-integrity checker
tools/generate_xcodeproj.py         project.pbxproj generator
samples/sample-project/             generated sample OPF project
docs/                               development plan, architecture, PIX4Dmatic checklist
```

---

## Verification

There are three independent layers, all of which are reproducible.

### 1. Executed in this authoring sandbox — the OPF reference harness

The authoring sandbox is Linux and has no Swift/Xcode toolchain, so the Xcode project
cannot be compiled here. Instead, `tools/opf_reference_harness/run_harness.py` builds the
**same** OPF documents (mirroring the Swift builder field-for-field) and validates them
against the **official** schemas:

```bash
python3 tools/opf_reference_harness/run_harness.py
```

Last run: **227 checks, 0 failures, RESULT: PASS.**

### 2. Executed in this authoring sandbox — structural integrity

```bash
python3 tools/structural_verify.py
```

Checks `project.pbxproj` object integrity, dangling references, target membership,
deployment target, and that every referenced source/resource exists on disk.

### 3. On macOS — Xcode build and tests

`xcodebuild build` and `xcodebuild test` (unit + UI) as shown above.

---

## Privacy summary

* All data lives in the app's `Documents/` directory.
* No network requests are made anywhere in the codebase.
* No analytics, advertising, tracking or third-party upload SDK is linked.
* Location and motion are **foreground only**; background location is not requested.
* Photographs can be exported only by the user, via the standard share sheet.

## Attribution and licences

The official OPF JSON schemas and examples are vendored verbatim in
`OPFCaptureBuilder/Resources/OPFSchemas/` under **CC BY 4.0** (specification) and
**Apache 2.0** (scripts/code), © 2023–2024 Pix4D SA. See
`OPFCaptureBuilder/Resources/OPFSchemas/ATTRIBUTION.md` and the bundled `LICENSE`.

Citation: *The Open Photogrammetry Format Specification*, Grégoire Krähenbühl, Klaus
Schneider-Zapp, Bastien Dalla Piazza, Juan Hernando, Juan Palacios, Massimiliano Bellomo,
Mohamed-Ghath Kaabi, Christoph Strecha, Pix4D, 2023.

Third-party algorithms: FNV-1a 64 (public domain) and CRC-32 IEEE 802.3 (standard
polynomial `0xEDB88320`). Everything else is Apple frameworks: AVFoundation, CoreLocation,
CoreMotion, ImageIO, Compression, PhotosUI, SwiftUI, UIKit.
