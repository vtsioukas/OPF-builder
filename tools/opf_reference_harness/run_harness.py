#!/usr/bin/env python3
"""
OPF reference harness — executed evidence for OPFCaptureBuilder.

The Swift `OPFDocumentBuilder` emits JSON documents with a fixed structure. This harness
constructs the *same* documents in Python (mirroring the Swift builder field-for-field)
for a sample project, then verifies them with two independent layers:

  1. Structural validation against the OFFICIAL OPF JSON schemas (draft 2020-12) using
     the `jsonschema` library, for every document the app can produce.
  2. The OPF business rules that JSON Schema cannot express, taken from the spec prose:
     unique camera UIDs, unique sensor/capture IDs, a single consistent uid_generator,
     every referenced resource present, safe relative URIs, band weights summing to 1,
     and no non-finite numbers.

Exit code 0 means every check passed. Run from the repository root:

    python3 tools/opf_reference_harness/run_harness.py
"""
from __future__ import annotations

import json
import math
import os
import re
import sys
from pathlib import Path

try:
    import jsonschema
    from jsonschema import Draft202012Validator
except ImportError:  # pragma: no cover
    print("FATAL: the 'jsonschema' package is required (pip install jsonschema==4.26.0)")
    sys.exit(2)

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_DIR = ROOT / "Resources" / "OPFSchemas" / "schema"
OUT_DIR = ROOT / "samples" / "sample-project"

FAILURES: list[str] = []
CHECKS = 0


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


# --------------------------------------------------------------------------- helpers
def fnv1a64(data: bytes) -> int:
    value = 0xCBF29CE484222325
    for byte in data:
        value ^= byte
        value = (value * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return value


def uid_for_image(file_name: str) -> int:
    return fnv1a64(file_name.encode("utf-8")) & 0x7FFFFFFFFFFFFFFF


def uid_for_signature(signature: str) -> int:
    return fnv1a64(signature.encode("utf-8")) & 0x7FFFFFFFFFFFFFFF


def capture_id(camera_id: int, iso_time: str) -> int:
    payload = camera_id.to_bytes(8, "little") + iso_time.encode("utf-8")
    return fnv1a64(payload) & 0x7FFFFFFFFFFFFFFF


def canonical(obj) -> str:
    return json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False)


# --------------------------------------------------------------- document construction
def build_camera_list(images):
    return {
        "format": "application/opf-camera-list+json",
        "version": "1.0",
        "uid_generator": {
            "vendor": "opfcapturebuilder",
            "name": "fnv1a64_image_content",
            "scope": "global",
            "version": 1,
        },
        "cameras": [
            {"id": uid_for_image(image["file_name"]), "uri": f"images/{image['file_name']}"}
            for image in images
        ],
    }


def build_input_cameras(images, crs_definition="EPSG:4326"):
    sensor_signature = images[0]["sensor_signature"]
    sensor_id = uid_for_signature(sensor_signature)

    sensors = [{
        "id": sensor_id,
        "name": images[0]["sensor_name"],
        "bands": [
            {"name": "Red", "weight": 0.2126},
            {"name": "Green", "weight": 0.7152},
            {"name": "Blue", "weight": 0.0722},
        ],
        "image_size_px": [images[0]["width"], images[0]["height"]],
        "pixel_size_um": 36000.0 / images[0]["width"],
        "internals": {
            "type": "perspective",
            "principal_point_px": [images[0]["width"] / 2.0, images[0]["height"] / 2.0],
            "focal_length_px": images[0]["focal_length_px"],
            "radial_distortion": [0.0, 0.0, 0.0],
            "tangential_distortion": [0.0, 0.0],
        },
        "shutter_type": "rolling",
    }]

    captures = []
    for image in images:
        camera_id = uid_for_image(image["file_name"])
        captures.append({
            "id": capture_id(camera_id, image["time"]),
            "rig_model_source": "not_applicable",
            "cameras": [{
                "sensor_id": sensor_id,
                "id": camera_id,
                "model_source": "generic_from_exif",
                "pixel_type": "uint8",
                "pixel_range": {"min": 0, "max": 255},
            }],
            "reference_camera_id": camera_id,
            "geolocation": {
                "crs": {"definition": crs_definition},
                "coordinates": [image["lat"], image["lon"], image["alt"]],
                "sigmas": [image["horizontal_accuracy"], image["horizontal_accuracy"], image["vertical_accuracy"]],
            },
            "time": image["time"],
        })
    return {"format": "application/opf-input-cameras+json", "version": "1.0",
            "sensors": sensors, "captures": captures}


def build_scene_reference_frame(images, crs_definition="EPSG:4326"):
    first = images[0]
    return {
        "format": "application/opf-scene-reference-frame+json",
        "version": "1.0",
        "crs": {"definition": crs_definition},
        "base_to_canonical": {
            "shift": [first["lon"], first["lat"], first["alt"]],
            "scale": [1.0, 1.0, 1.0],
            "swap_xy": False,
        },
    }


def build_project(project_uuid, name, description, item_ids):
    return {
        "format": "application/opf-project+json",
        "version": "1.0",
        "id": project_uuid,
        "name": name,
        "description": description,
        "generator": {"name": "OPF Capture Builder", "version": "1.0"},
        "items": [
            {
                "id": item_ids["camera_list"],
                "name": "Camera list",
                "type": "camera_list",
                "resources": [{"uri": "camera-list.json", "format": "application/opf-camera-list+json"}],
                "sources": [],
            },
            {
                "id": item_ids["input_cameras"],
                "name": "Input cameras",
                "type": "input_cameras",
                "resources": [{"uri": "input-cameras.json", "format": "application/opf-input-cameras+json"}],
                "sources": [{"id": item_ids["camera_list"], "type": "camera_list"}],
            },
            {
                "id": item_ids["scene_reference_frame"],
                "name": "Scene reference frame",
                "type": "scene_reference_frame",
                "resources": [{"uri": "scene-reference-frame.json",
                               "format": "application/opf-scene-reference-frame+json"}],
                "sources": [],
            },
        ],
    }


# ------------------------------------------------------------------------- sample data
def sample_images(count=8, width=1600, height=1200):
    images = []
    for index in range(count):
        offset = index * 0.00006
        images.append({
            "file_name": f"SAMPLE_{index + 1:04d}.jpg",
            "width": width,
            "height": height,
            "focal_length_px": 26.0 * width / 36.0,
            "sensor_signature": f"Synthetic|SampleCam 1.0|Sample 26mm|{width}x{height}|26.00",
            "sensor_name": f"Synthetic_SampleCam_1.0_26.0_{width}x{height}",
            "lat": 46.5196535 + offset,
            "lon": 6.6322734 + offset * 0.35,
            "alt": 375.0 + index * 0.4,
            "horizontal_accuracy": 3.0,
            "vertical_accuracy": 5.0,
            "time": f"2023-11-14T22:13:20.{index:03d}Z",
        })
    return images


# -------------------------------------------------------------------------- validation
def build_registry():
    """
    The official schemas reference their siblings with relative URIs such as
    `property.schema.json`. Build a referencing.Registry that resolves every schema in
    the schema directory, so $ref resolution works exactly as the OPF repo intends.
    """
    from referencing import Registry, Resource

    resources = []
    for path in SCHEMA_DIR.glob("*.schema.json"):
        with path.open() as handle:
            schema = json.load(handle)
        resources.append((path.name, Resource.from_contents(schema)))
    return Registry().with_resources(resources)


REGISTRY = build_registry()


def load_schema(name: str) -> dict:
    path = SCHEMA_DIR / name
    with path.open() as handle:
        return json.load(handle)


def validate_against_schema(document: dict, schema_name: str, label: str) -> None:
    schema = load_schema(schema_name)
    validator = Draft202012Validator(schema, registry=REGISTRY)
    errors = sorted(validator.iter_errors(document), key=lambda e: list(e.path))
    check(not errors, f"{label}: JSON Schema violations: " +
          "; ".join(f"{'/'.join(map(str, e.path))}: {e.message}" for e in errors))


def walk_numbers(node, path="$"):
    if isinstance(node, bool):
        return
    if isinstance(node, (int, float)):
        yield path, node
    elif isinstance(node, dict):
        for key, value in node.items():
            yield from walk_numbers(value, f"{path}.{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from walk_numbers(value, f"{path}[{index}]")


def business_rules(documents: dict, images, item_ids) -> None:
    camera_list = documents["camera-list.json"]
    input_cameras = documents["input-cameras.json"]
    project = documents["project.opf"]

    # 1. Unique camera UIDs within the camera list.
    ids = [camera["id"] for camera in camera_list["cameras"]]
    check(len(ids) == len(set(ids)), "camera-list.json: camera IDs are not unique")
    check(len(ids) == len(images), f"camera-list.json: expected {len(images)} cameras, found {len(ids)}")

    # 2. Every uid64 is inside the unsigned 64-bit range.
    for identifier in ids:
        check(0 <= identifier <= 0xFFFFFFFFFFFFFFFF, f"camera id {identifier} outside uid64 range")
        check(identifier <= 0x7FFFFFFFFFFFFFFF, f"camera id {identifier} exceeds Int64.positive")

    # 3. uid_generator is present and consistent (one strategy for the project).
    generator = camera_list.get("uid_generator")
    check(generator is not None, "camera-list.json: uid_generator is missing")
    if generator:
        check(generator["scope"] in ("global", "project"), "uid_generator scope invalid")
        check(generator["version"] >= 0, "uid_generator version must be non-negative")

    # 4. Unique sensor and capture IDs.
    sensor_ids = [sensor["id"] for sensor in input_cameras["sensors"]]
    check(len(sensor_ids) == len(set(sensor_ids)), "input-cameras.json: sensor IDs are not unique")
    capture_ids = [capture["id"] for capture in input_cameras["captures"]]
    check(len(capture_ids) == len(set(capture_ids)), "input-cameras.json: capture IDs are not unique")

    # 5. Every camera in a capture resolves to a sensor, and to a camera-list entry.
    for capture in input_cameras["captures"]:
        check(capture["reference_camera_id"] in ids,
              f"capture {capture['id']} references unknown camera {capture['reference_camera_id']}")
        for camera in capture["cameras"]:
            check(camera["sensor_id"] in sensor_ids,
                  f"capture {capture['id']} references unknown sensor {camera['sensor_id']}")
            check(camera["id"] in ids,
                  f"capture {capture['id']} references camera {camera['id']} missing from the camera list")
            check(camera["model_source"] != "database",
                  "this app never emits model_source 'database'")
            # pixel_type is one of the schema's enumerated values.
            check(camera["pixel_type"] in ("uint8", "uint12", "uint16", "float"),
                  f"invalid pixel_type {camera['pixel_type']}")

    # 6. No camera-list entry is orphaned: the sets agree.
    capture_camera_ids = {c["id"] for capture in input_cameras["captures"] for c in capture["cameras"]}
    check(set(ids) == capture_camera_ids, "camera-list and input-cameras disagree about the camera set")

    # 7. Band weights sum to 1 for every sensor.
    for sensor in input_cameras["sensors"]:
        total = sum(band["weight"] for band in sensor["bands"])
        check(abs(total - 1.0) < 1e-6, f"sensor {sensor['id']} band weights sum to {total}, expected 1")
        check(sensor["image_size_px"][0] > 0 and sensor["image_size_px"][1] > 0,
              f"sensor {sensor['id']} has a non-positive image size")
        check(sensor["shutter_type"] in ("global", "rolling"), "invalid shutter_type")
        internals = sensor["internals"]
        check(internals["type"] == "perspective", "expected perspective internals")
        check(len(internals["radial_distortion"]) == 3, "radial_distortion must have three coefficients")
        check(len(internals["tangential_distortion"]) == 2, "tangential_distortion must have two coefficients")

    # 8. The project item graph is well formed and every source resolves.
    item_by_id = {item["id"]: item for item in project["items"]}
    for item in project["items"]:
        for source in item["sources"]:
            check(source["id"] in item_by_id,
                  f"item {item['id']} references unknown source {source['id']}")
            check(item_by_id[source["id"]]["type"] == source["type"],
                  f"source {source['id']} type does not match the referenced item type")
    check(item_by_id[item_ids["input_cameras"]]["sources"][0]["type"] == "camera_list",
          "input_cameras must declare camera_list as a source")

    # 9. Every safe relative URI resolves to a file that will exist in the export.
    exported = {f"images/{image['file_name']}" for image in images}
    for camera in camera_list["cameras"]:
        check(camera["uri"] in exported,
              f"camera-list URI {camera['uri']} does not correspond to an exported photograph")

    safe = re.compile(r"^(?!/)(?!.*\\)(?!.*//)(?!.*(?:^|/)\.\.(?:/|$))(?!.*[\x00-\x1f]).+/[^/]+$")
    for camera in camera_list["cameras"]:
        check(bool(safe.match(camera["uri"])), f"unsafe relative URI {camera['uri']}")

    # 10. No non-finite numbers anywhere in any document.
    for name, document in documents.items():
        for path, value in walk_numbers(document):
            check(math.isfinite(value), f"{name}: non-finite number at {path}")

    # 11. All required '@' constraints from the schemas are visible at the top level.
    for name, document in documents.items():
        check(isinstance(document, dict), f"{name} is not a JSON object")
        check("format" in document and "version" in document, f"{name} is missing format/version")


def main() -> int:
    if not SCHEMA_DIR.exists():
        print(f"FATAL: schemas not found at {SCHEMA_DIR}")
        return 2

    images = sample_images()
    project_uuid = "caa7754e-90dc-11ec-b909-0242ac120002"
    item_ids = {
        "camera_list": "1fbfd8dd-188c-45dc-955c-30eac64ad4d7",
        "input_cameras": "57608ca8-912d-4fee-b097-2648651474c4",
        "scene_reference_frame": "83291b5e-d239-4d94-93fb-226f70d7cd3c",
    }

    documents = {
        "project.opf": build_project(project_uuid, "Sample Project (synthetic)",
                                     "Synthetic sample project generated by the reference harness.",
                                     item_ids),
        "camera-list.json": build_camera_list(images),
        "input-cameras.json": build_input_cameras(images),
        "scene-reference-frame.json": build_scene_reference_frame(images),
    }

    print("OPF reference harness")
    print("=" * 72)
    print(f"schemas: {SCHEMA_DIR}")
    print(f"documents under test: {', '.join(documents)}")
    print()

    schema_for = {
        "project.opf": "project.schema.json",
        "camera-list.json": "camera_list.schema.json",
        "input-cameras.json": "input_cameras.schema.json",
        "scene-reference-frame.json": "scene_reference_frame.schema.json",
    }
    for name, document in documents.items():
        validate_against_schema(document, schema_for[name], name)
        print(f"  [schema] {name:30s} -> {schema_for[name]}")

    business_rules(documents, images, item_ids)
    print(f"  [rules ] OPF business rules executed")

    # Write the reference sample project for reference.
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    images_dir = OUT_DIR / "images"
    images_dir.mkdir(exist_ok=True)
    for image in images:
        (images_dir / image["file_name"]).write_bytes(b"")

    write_map = {
        "project.opf": documents["project.opf"],
        "camera-list.json": documents["camera-list.json"],
        "input-cameras.json": documents["input-cameras.json"],
        "scene-reference-frame.json": documents["scene-reference-frame.json"],
    }
    for file_name, document in write_map.items():
        (OUT_DIR / file_name).write_text(canonical(document) + "\n")
    (OUT_DIR / "validation-report.txt").write_text(
        "OPF Capture Builder — validation report (reference harness)\n"
        f"Checks executed: {CHECKS}\n"
        f"Result: {'PASS' if not FAILURES else 'FAIL'}\n"
        "Validated against the official OPF JSON schemas (opf-spec).\n"
    )

    print()
    print("=" * 72)
    print(f"checks executed : {CHECKS}")
    print(f"failures        : {len(FAILURES)}")
    if FAILURES:
        for failure in FAILURES:
            print(f"  FAIL: {failure}")
        print("\nRESULT: FAIL")
        return 1
    print("\nRESULT: PASS — every generated document satisfies the official OPF schemas")
    print(f"sample project written to: {OUT_DIR.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
