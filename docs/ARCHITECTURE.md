# Architecture

## Layers

```
Views (SwiftUI)      → 12 screens, no OPF knowledge
AppModel             → observable state, project selection, banners
Services             → ProjectStore, ImageImporter, CameraCaptureService,
                       SensorRecorder, ExportService, ZipArchiveWriter, OPFSchemaProvider
OPF                  → JSONValue writer, JSONSchemaValidator, OPFWriter,
                       OPFValidator, OPFUIDGenerator, DeviceAttitudeMapping
Models               → CaptureProject, ImageRecord, GeolocationRecord, SensorRecord, …
```

Views never construct JSON. `OPFExporter` is the single façade that turns a
`CaptureProject` into a validated, zipped package, and it is called by both the app and
the unit tests, so the tested path is the shipping path.

## Models

* `CaptureProject` — id, name, description, CRS settings, images, manual intrinsics keyed
  by sensor signature. Persisted as `project.json` in the project folder.
* `ImageRecord` — one photograph: file name, pixel geometry, EXIF orientation, capture
  time and its source, byte size, geolocation, device attitude, EXIF summary, sensor
  signature.
* `GeolocationRecord` — latitude, longitude, **ellipsoidal** altitude, horizontal and
  vertical accuracy, timestamp. `altitudeIsEllipsoidal` is always true and the UI explains it.
* `DeviceAttitudeRecord` — raw quaternion (w,x,y,z) plus derived Euler angles, explicitly
  documented as device attitude rather than camera orientation.
* `SensorRecord` / `ManualIntrinsics` — the physical camera/lens and any user-verified
  intrinsics. `CalibrationSource` decides the OPF `model_source` value.

Missing data is represented by `nil`, never by a placeholder number.

## Services

* **ProjectStore** — all file layout under `Documents/<UUID>/`; byte-for-byte image copies;
  size reporting; duplicate/rename/delete.
* **EXIFReader / ImageImporter** — read-only ImageIO metadata; copies originals unchanged;
  optional JPEG transcode is announced to the user; missing-field report per image.
* **CameraCaptureService** — AVFoundation photo output, codec chosen before capture,
  `isCapturing` guard prevents duplicate requests.
* **SensorRecorder** — CoreLocation foreground updates, CoreMotion attitude on a serial
  queue; no background location.
* **ZipArchiveWriter** — store/deflate ZIP with correct central directory and CRC-32.
* **ExportService** — stages, zips, presents the share sheet, and removes temporary files
  after dismissal (including a sweep for orphaned `opf-export-*` directories).

## OPF writer

`OPFWriter.build(project:cameraIDProvider:)` produces an `OPFDocumentSet`:

* **camera-list.json** — one entry per distinct image file, plus the `uid_generator` block.
* **input-cameras.json** — sensors (grouped by sensor signature) and one capture per image,
  carrying geolocation and, only on explicit opt-in, orientation.
* **scene-reference-frame.json** — optional; emitted when the user enables georeferencing.
* **project.opf** — the item graph `camera_list → input_cameras` and, if present,
  `scene_reference_frame`.

`JSONValue` preserves property order, guarantees unique keys, escapes RFC 8259-compliantly
and **throws** on non-finite numbers.

### UID strategy (one for the whole project)

`FNV-1a 64` of the raw image bytes, masked to 63 bits so every value fits in
`Int64.positive` (and therefore trivially in `uid64`). Sensors hash their identity
signature; captures hash `cameraID + ISO 8601 time`. The same routine is used by the
importer and the writer, and collisions are resolved deterministically.

### Sensor data handling

* CoreLocation altitude is used as-is and written as the third coordinate of an
  `EPSG:4326` geographic CRS, whose third axis *is* ellipsoidal height (ISO 19111).
  The app never relabels it as orthometric height.
* `geolocation.sigmas` is `[horizontalAccuracy, horizontalAccuracy, verticalAccuracy]`,
  all in metres, as the specification requires.
* Device attitude is stored as a quaternion. YPR is derived via
  `Rz(yaw)·Ry(pitch)·Rx(roll)` (intrinsic Z-Y-X) in `DeviceAttitudeMapping`, with the
  camera-to-device mounting matrix configurable. Because OPF also requires an angular
  sigma the app cannot measure, orientation export is **off by default** and the user
  supplies the sigma when they enable it.
* Unverified intrinsics are labelled `generic_from_exif` or `generic`; only user-entered
  verified intrinsics become `user`. `database` is never emitted.

## Validation

`OPFValidator.validate` runs three layers:

1. **JSON Schema** conformance via `JSONSchemaValidator`, a self-contained validator for
   the draft 2020-12 subset the OPF schemas use (`type`, `required`, `enum`, `const`,
   `minimum`, `pattern`, `items`, `minItems`, `anyOf`, `allOf`, `oneOf`, …).
2. **OPF business rules** — unique camera/sensor/capture IDs, consistent `uid_generator`,
   no dangling source references, required source types per item type, resource format
   matching, band weights summing to 1, safe relative URIs, resource existence.
3. **Data sanity** — no non-finite numbers, no invented values, helpful warnings when a
   project would not georeference or is empty.

## Export

1. Documents are generated and validated (with real file existence).
2. A staging directory is created and the four/ﬁve documents plus the images are written.
3. A ZIP is built with `ZipArchiveWriter`.
4. The archive is handed to the iOS share sheet (Save to Files, AirDrop, …).
5. On dismissal the staging directory is deleted.

## Threading

`ProjectStore`, `AppModel`, `ExportService` and `CameraCaptureService` are
`@MainActor`. I/O-heavy work (image reads, zipping) runs off the main actor or in
`Task`/`Task.detached` where it matters.
