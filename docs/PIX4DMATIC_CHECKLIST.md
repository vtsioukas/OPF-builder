# Testing an exported project in PIX4Dmatic

Minimum PIX4Dmatic version: **v1.46** (first release with OPF import/export support).

This checklist verifies that an archive produced by OPF Capture Builder is accepted by a
real OPF consumer. Nothing here depends on proprietary data: use the app's built-in
**Create Sample Project** action, whose images and coordinates are synthetic.

## 1. Produce the archive

1. Launch OPF Capture Builder and complete onboarding.
2. Projects → **Add** → **Create Sample Project**.
3. Open the sample project → **Validation report** → **Run validation**.
   * Expect: *Passed with no errors*.
4. Back → **Export project** → confirm no errors → **Export and share** →
   **Save to Files** and save the `.zip`.
5. Unzip it.

Expected directory:

```
Sample Project (synthetic)/
  project.opf
  camera-list.json
  input-cameras.json
  scene-reference-frame.json     (present for the sample project)
  validation-report.txt
  images/SAMPLE_0001.jpg … SAMPLE_0008.jpg
```

## 2. Import into PIX4Dmatic

1. Open PIX4Dmatic.
2. **File → Import → OPF project…** and select `project.opf` (or drag the folder in).
3. Expected result: **8 images** are imported and listed.

## 3. Verify the data arrived intact

| Check | Expected |
|---|---|
| Image count | 8 |
| Image names | `SAMPLE_0001.jpg` … `SAMPLE_0008.jpg` |
| Location shown | Yes — every image has a geolocation fix |
| CRS reported | WGS 84 geographic (`EPSG:4326`) |
| Camera model | One sensor, labelled as not from a camera database |
| Orientation column | Empty (orientation export is off by default) |

## 4. Verify the deliberate omissions are honoured

* There is **no** calibrated camera entry: the sample project has no verified intrinsics,
  so the camera must be reported as generic/estimated.
* There is **no** point cloud and **no** sparse reconstruction — the app does not produce them.
* No error mentioning a missing `calibration` resource.

## 5. Round-trip (optional but recommended)

1. In PIX4Dmatic, **File → Export → OPF project…** to a new directory.
2. Confirm the re-export still contains all 8 images and the same scene reference frame.
3. Optionally re-import the app's original `project.opf` afterwards to confirm the app's
   output is accepted unchanged.

## 6. Altitude semantics (important)

PIX4Dmatic may display heights in a projected/orthometric context. The app writes **WGS 84
ellipsoidal heights**. If PIX4Dmatic applies a geoid model, expect a height difference
consistent with that model at the sample location — this is the documented difference
between ellipsoidal and orthometric height, not a bug.

## 7. Negative test (recommended)

1. In the app, create an empty project, add no images, and export.
2. Expect a **warning** in the validation report ("the project contains no photographs")
   and the export to be permitted only if there are no *errors*.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| "Unsupported OPF version" | PIX4Dmatic older than v1.46 |
| Images listed but no location | The sample's synthetic coordinates were stripped; re-create the sample project |
| Camera flagged as calibrated | Should never happen — the app never emits `calibration`; report it as a bug |
| Height differs from expectations | Geoid model applied by the consumer; see section 6 |
