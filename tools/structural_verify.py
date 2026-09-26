#!/usr/bin/env python3
"""
Structural integrity checker for OPFCaptureBuilder.xcodeproj.

Executed evidence that the generated Xcode project is internally consistent, since the
authoring sandbox has no Xcode toolchain to build it. Verifies:
  * every referenced object ID is defined exactly once,
  * section dictionaries only reference existing objects,
  * the three synchronized root groups exist on disk,
  * resource file references exist on disk,
  * the iOS deployment target is 17.0 and no CocoaPods artefacts are present,
  * every Swift file lives under a synchronized folder (so Xcode will compile it).

Exit 0 = all checks passed. Run from the repository root.
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBXPROJ = ROOT / "OPFCaptureBuilder.xcodeproj" / "project.pbxproj"

FAILURES: list[str] = []
CHECKS = 0


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


def main() -> int:
    text = PBXPROJ.read_text()
    object_id = re.compile(r"\b([0-9A-F]{24})\b")

    # 0. The file must parse with Xcode's OpenStep plist grammar. An unquoted string may
    #    only contain [A-Za-z0-9_$./-]; a stray '<', '>' or ':' outside quotes makes Xcode
    #    report "the project is damaged and cannot be opened due to a parse error".
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import openstep_plist

    try:
        document = openstep_plist.parse_file(PBXPROJ)
        check(document.get("objectVersion") == "77", "objectVersion should be 77")
        check("objects" in document, "the parsed project has no objects dictionary")
        check("rootObject" in document, "the parsed project has no rootObject")
    except Exception as error:  # noqa: BLE001
        check(False, f"project.pbxproj does not parse: {error}")
        document = {}

    # 1. Every 24-char hex id that starts an object definition.
    definitions = re.findall(r"^\t+([0-9A-F]{24}) /\* .* \*/ = \{", text, re.MULTILINE)
    check(len(definitions) > 0, "no object definitions found in project.pbxproj")
    check(len(definitions) == len(set(definitions)), "duplicate object definitions detected")

    defined = set(definitions)
    referenced = set(object_id.findall(text))
    # ids referenced but never defined (the rootObject and values like 2147483647 are excluded).
    dangling = referenced - defined
    # 2147483647 is a buildActionMask, not an id; filter it out.
    dangling = {d for d in dangling if d != "2147483647"}
    check(not dangling, f"dangling object references: {sorted(dangling)}")

    # 2. Synchronized root groups for all three targets.
    for folder in ("OPFCaptureBuilder", "OPFCaptureBuilderTests", "OPFCaptureBuilderUITests"):
        check((ROOT / folder).is_dir(), f"synchronized folder missing on disk: {folder}")
        check(f'path = {folder};' in text, f"no synchronized group for {folder}")

    # 3. Resource file references resolve on disk.
    for relative in ("Resources/Assets.xcassets", "Resources/OPFSchemas"):
        check((ROOT / relative).exists(), f"resource missing on disk: {relative}")

    # 4. Build settings sanity.
    check("IPHONEOS_DEPLOYMENT_TARGET = 17.0;" in text, "deployment target is not 17.0")
    check("objectVersion = 77;" in text, "objectVersion should be 77 for the Xcode 16 format")
    check("PRODUCT_BUNDLE_IDENTIFIER = com.opfcapturebuilder.photogrammetry;" in text,
          "app bundle identifier is not set as expected")
    check("INFOPLIST_FILE = Config/Info.plist;" in text, "Info.plist is not referenced")

    # 5. No CocoaPods.
    check(not (ROOT / "Podfile").exists(), "a Podfile is present; SPM only was requested")
    check("Pods" not in text, "the pbxproj mentions Pods")

    # 6. Every Swift file is inside a synchronized folder (so it is compiled).
    swift_files = list(ROOT.rglob("*.swift"))
    check(len(swift_files) > 0, "no Swift files found")
    for path in swift_files:
        relative = path.relative_to(ROOT).as_posix()
        top = relative.split("/")[0]
        check(top in ("OPFCaptureBuilder", "OPFCaptureBuilderTests", "OPFCaptureBuilderUITests"),
              f"Swift file outside a synchronized folder (would not compile): {relative}")

    # 7. The official schemas are all present.
    schema_count = len(list((ROOT / "Resources" / "OPFSchemas" / "schema").glob("*.schema.json")))
    check(schema_count >= 30, f"expected the full set of official schemas, found {schema_count}")

    print("Structural verification of OPFCaptureBuilder.xcodeproj")
    print("=" * 64)
    print(f"swift files          : {len(swift_files)}")
    print(f"pbxproj objects      : {len(defined)}")
    print(f"bundled OPF schemas  : {schema_count}")
    print("=" * 64)
    print(f"checks executed      : {CHECKS}")
    print(f"failures             : {len(FAILURES)}")
    if FAILURES:
        for failure in FAILURES:
            print(f"  FAIL: {failure}")
        print("\nRESULT: FAIL")
        return 1
    print("\nRESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
