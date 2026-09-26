#!/usr/bin/env python3
"""
Generates OPFCaptureBuilder.xcodeproj/project.pbxproj (Xcode 16 object format,
synchronized root groups) from the on-disk folder structure.

Deterministic: re-running produces byte-identical output. Using PBXFileSystemSynchronizedRootGroup
lets Xcode auto-discover every Swift file in the source folders, which removes the most
common class of project.pbxproj corruption (hand-written PBXFileReference/PBXBuildFile bookkeeping).
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUNDLE_ID = "com.opfcapturebuilder.photogrammetry"


class IdGen:
    def __init__(self):
        self.n = 0

    def next(self):
        self.n += 1
        return "FA%022X" % self.n


def obj(ids, isa, extra, trailing_semicolon=True):
    lines = [f"{ids} /* {isa} */ = {{", f"\tisa = {isa};"]
    for k, v in extra:
        lines.append(f"\t{k} = {v};")
    lines.append("};")
    return "\n".join(lines)


COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_COMMA": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
    "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
    "CLANG_WARN_STRICT_PROTOTYPES": "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
    "buildTargetsInParallel": "YES",
    "ENABLE_MODULE_VERIFIER": "YES",
}


def build_settings_dict(d):
    items = "".join(f"\n\t\t\t\t{k} = {v};" for k, v in d.items())
    return "{" + items + "\n\t\t\t}"


def main():
    ids = IdGen()
    PROJECT = ids.next()
    MAIN_GROUP = ids.next()
    PRODUCTS_GROUP = ids.next()
    RES_GROUP = ids.next()
    CFG_LIST_PROJECT = ids.next()
    CFG_LIST_APP = ids.next()
    CFG_LIST_UTEST = ids.next()
    CFG_LIST_UITEST = ids.next()
    APP = ids.next()
    UTEST = ids.next()
    UITEST = ids.next()
    PROD_APP = ids.next()
    PROD_UTEST = ids.next()
    PROD_UITEST = ids.next()
    SYNC_APP = ids.next()
    SYNC_UTEST = ids.next()
    SYNC_UITEST = ids.next()
    FR_ASSETS = ids.next()
    FR_SCHEMAS = ids.next()
    BF_ASSETS = ids.next()
    BF_SCHEMAS = ids.next()
    PH_SRC_APP = ids.next()
    PH_FRW_APP = ids.next()
    PH_RES_APP = ids.next()
    PH_SRC_UTEST = ids.next()
    PH_FRW_UTEST = ids.next()
    PH_RES_UTEST = ids.next()
    PH_SRC_UITEST = ids.next()
    PH_FRW_UITEST = ids.next()
    PH_RES_UITEST = ids.next()
    DEP_UTEST = ids.next()
    DEP_UITEST = ids.next()
    PROXY_UTEST = ids.next()
    PROXY_UITEST = ids.next()

    cfg = {}
    for scope in ("proj", "app", "utest", "uitest"):
        for name in ("Debug", "Release"):
            cfg[(scope, name)] = ids.next()

    blocks = []

    def add(ids_, isa, extra):
        blocks.append(obj(ids_, isa, extra))

    # ----- PBXBuildFile -----
    add(BF_ASSETS, "PBXBuildFile", [
        ("fileRef", f"{FR_ASSETS} /* Assets.xcassets */"),
    ])
    add(BF_SCHEMAS, "PBXBuildFile", [
        ("fileRef", f"{FR_SCHEMAS} /* OPFSchemas in Resources */"),
    ])

    # ----- PBXContainerItemProxy -----
    add(PROXY_UTEST, "PBXContainerItemProxy", [
        ("containerPortal", f"{PROJECT} /* Project object */"),
        ("proxyType", "1"),
        ("remoteGlobalIDString", APP),
        ("remoteInfo", "OPFCaptureBuilder"),
    ])
    add(PROXY_UITEST, "PBXContainerItemProxy", [
        ("containerPortal", f"{PROJECT} /* Project object */"),
        ("proxyType", "1"),
        ("remoteGlobalIDString", APP),
        ("remoteInfo", "OPFCaptureBuilder"),
    ])

    # ----- PBXFileReference -----
    add(PROD_APP, "PBXFileReference", [
        ("explicitFileType", "wrapper.application"),
        ("includeInIndex", "0"),
        ("path", "OPFCaptureBuilder.app"),
        ("sourceTree", "BUILT_PRODUCTS_DIR"),
    ])
    add(PROD_UTEST, "PBXFileReference", [
        ("explicitFileType", "wrapper.cfbundle"),
        ("includeInIndex", "0"),
        ("path", "OPFCaptureBuilderTests.xctest"),
        ("sourceTree", "BUILT_PRODUCTS_DIR"),
    ])
    add(PROD_UITEST, "PBXFileReference", [
        ("explicitFileType", "wrapper.cfbundle"),
        ("includeInIndex", "0"),
        ("path", "OPFCaptureBuilderUITests.xctest"),
        ("sourceTree", "BUILT_PRODUCTS_DIR"),
    ])
    add(FR_ASSETS, "PBXFileReference", [
        ("lastKnownFileType", "folder.assetcatalog"),
        ("path", "Assets.xcassets"),
        ("sourceTree", '"<group>"'),
    ])
    add(FR_SCHEMAS, "PBXFileReference", [
        ("lastKnownFileType", "folder"),
        ("path", "OPFSchemas"),
        ("sourceTree", '"<group>"'),
    ])

    # ----- PBXFileSystemSynchronizedRootGroup -----
    for sid, name in ((SYNC_APP, "OPFCaptureBuilder"),
                      (SYNC_UTEST, "OPFCaptureBuilderTests"),
                      (SYNC_UITEST, "OPFCaptureBuilderUITests")):
        add(sid, "PBXFileSystemSynchronizedRootGroup", [
            ("explicitFileTypes", "{}"),
            ("explicitFolders", "()"),
            ("path", name),
            ("sourceTree", '"<group>"'),
        ])

    # ----- PBXFrameworksBuildPhase -----
    add(PH_FRW_APP, "PBXFrameworksBuildPhase", [
        ("buildActionMask", "2147483647"),
        ("files", "()"),
        ("runOnlyForDeploymentPostprocessing", "0"),
    ])
    add(PH_FRW_UTEST, "PBXFrameworksBuildPhase", [
        ("buildActionMask", "2147483647"),
        ("files", "()"),
        ("runOnlyForDeploymentPostprocessing", "0"),
    ])
    add(PH_FRW_UITEST, "PBXFrameworksBuildPhase", [
        ("buildActionMask", "2147483647"),
        ("files", "()"),
        ("runOnlyForDeploymentPostprocessing", "0"),
    ])

    # ----- PBXGroup -----
    add(MAIN_GROUP, "PBXGroup", [
        ("children", "(\n\t\t\t\t" + SYNC_APP + " /* OPFCaptureBuilder */,\n\t\t\t\t"
         + SYNC_UTEST + " /* OPFCaptureBuilderTests */,\n\t\t\t\t"
         + SYNC_UITEST + " /* OPFCaptureBuilderUITests */,\n\t\t\t\t"
         + RES_GROUP + " /* Resources */,\n\t\t\t\t"
         + PRODUCTS_GROUP + " /* Products */,\n\t\t\t)"),
        ("sourceTree", '"<group>"'),
    ])
    add(RES_GROUP, "PBXGroup", [
        ("children", "(\n\t\t\t\t" + FR_ASSETS + " /* Assets.xcassets */,\n\t\t\t\t"
         + FR_SCHEMAS + " /* OPFSchemas */,\n\t\t\t)"),
        ("path", "Resources"),
        ("sourceTree", '"<group>"'),
    ])
    add(PRODUCTS_GROUP, "PBXGroup", [
        ("children", "(\n\t\t\t\t" + PROD_APP + " /* OPFCaptureBuilder.app */,\n\t\t\t\t"
         + PROD_UTEST + " /* OPFCaptureBuilderTests.xctest */,\n\t\t\t\t"
         + PROD_UITEST + " /* OPFCaptureBuilderUITests.xctest */,\n\t\t\t)"),
        ("name", "Products"),
        ("sourceTree", '"<group>"'),
    ])

    # ----- PBXNativeTarget -----
    add(APP, "PBXNativeTarget", [
        ("buildConfigurationList", f"{CFG_LIST_APP} /* Build configuration list for PBXNativeTarget \"OPFCaptureBuilder\" */"),
        ("buildPhases", "(\n\t\t\t\t" + PH_SRC_APP + " /* Sources */,\n\t\t\t\t"
         + PH_FRW_APP + " /* Frameworks */,\n\t\t\t\t" + PH_RES_APP + " /* Resources */,\n\t\t\t)"),
        ("buildRules", "()"),
        ("dependencies", "()"),
        ("fileSystemSynchronizedGroups", "(\n\t\t\t\t" + SYNC_APP + " /* OPFCaptureBuilder */,\n\t\t\t)"),
        ("name", "OPFCaptureBuilder"),
        ("productName", "OPFCaptureBuilder"),
        ("productReference", f"{PROD_APP} /* OPFCaptureBuilder.app */"),
        ("productType", '"com.apple.product-type.application"'),
    ])
    add(UTEST, "PBXNativeTarget", [
        ("buildConfigurationList", f"{CFG_LIST_UTEST} /* Build configuration list for PBXNativeTarget \"OPFCaptureBuilderTests\" */"),
        ("buildPhases", "(\n\t\t\t\t" + PH_SRC_UTEST + " /* Sources */,\n\t\t\t\t"
         + PH_FRW_UTEST + " /* Frameworks */,\n\t\t\t\t" + PH_RES_UTEST + " /* Resources */,\n\t\t\t)"),
        ("buildRules", "()"),
        ("dependencies", "(\n\t\t\t\t" + DEP_UTEST + " /* PBXTargetDependency */,\n\t\t\t)"),
        ("fileSystemSynchronizedGroups", "(\n\t\t\t\t" + SYNC_UTEST + " /* OPFCaptureBuilderTests */,\n\t\t\t)"),
        ("name", "OPFCaptureBuilderTests"),
        ("productName", "OPFCaptureBuilderTests"),
        ("productReference", f"{PROD_UTEST} /* OPFCaptureBuilderTests.xctest */"),
        ("productType", '"com.apple.product-type.bundle.unit-test"'),
    ])
    add(UITEST, "PBXNativeTarget", [
        ("buildConfigurationList", f"{CFG_LIST_UITEST} /* Build configuration list for PBXNativeTarget \"OPFCaptureBuilderUITests\" */"),
        ("buildPhases", "(\n\t\t\t\t" + PH_SRC_UITEST + " /* Sources */,\n\t\t\t\t"
         + PH_FRW_UITEST + " /* Frameworks */,\n\t\t\t\t" + PH_RES_UITEST + " /* Resources */,\n\t\t\t)"),
        ("buildRules", "()"),
        ("dependencies", "(\n\t\t\t\t" + DEP_UITEST + " /* PBXTargetDependency */,\n\t\t\t)"),
        ("fileSystemSynchronizedGroups", "(\n\t\t\t\t" + SYNC_UITEST + " /* OPFCaptureBuilderUITests */,\n\t\t\t)"),
        ("name", "OPFCaptureBuilderUITests"),
        ("productName", "OPFCaptureBuilderUITests"),
        ("productReference", f"{PROD_UITEST} /* OPFCaptureBuilderUITests.xctest */"),
        ("productType", '"com.apple.product-type.bundle.ui-testing"'),
    ])

    # ----- PBXProject -----
    add(PROJECT, "PBXProject", [
        ("attributes", "{ LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; TargetAttributes = { "
         + f"{APP} = {{ CreatedOnToolsVersion = 16.0; }}; "
         + f"{UTEST} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {APP}; }}; "
         + f"{UITEST} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {APP}; }}; "
         + "}; }"),
        ("buildConfigurationList", f"{CFG_LIST_PROJECT} /* Build configuration list for PBXProject \"OPFCaptureBuilder\" */"),
        ("compatibilityVersion", '"Xcode 15.0"'),
        ("developmentRegion", "en"),
        ("hasScannedForEncodings", "0"),
        ("knownRegions", "(\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t)"),
        ("mainGroup", MAIN_GROUP),
        ("minimizedProjectReferenceProxies", "1"),
        ("preferredProjectObjectVersion", "77"),
        ("productRefGroup", f"{PRODUCTS_GROUP} /* Products */"),
        ("projectDirPath", '""'),
        ("projectRoot", '""'),
        ("targets", "(\n\t\t\t\t" + APP + " /* OPFCaptureBuilder */,\n\t\t\t\t"
         + UTEST + " /* OPFCaptureBuilderTests */,\n\t\t\t\t"
         + UITEST + " /* OPFCaptureBuilderUITests */,\n\t\t\t)"),
    ])

    # ----- PBXResourcesBuildPhase -----
    add(PH_RES_APP, "PBXResourcesBuildPhase", [
        ("buildActionMask", "2147483647"),
        ("files", "(\n\t\t\t\t" + BF_ASSETS + " /* Assets.xcassets */,\n\t\t\t\t"
         + BF_SCHEMAS + " /* OPFSchemas in Resources */,\n\t\t\t)"),
        ("runOnlyForDeploymentPostprocessing", "0"),
    ])
    add(PH_RES_UTEST, "PBXResourcesBuildPhase", [
        ("buildActionMask", "2147483647"),
        ("files", "()"),
        ("runOnlyForDeploymentPostprocessing", "0"),
    ])
    add(PH_RES_UITEST, "PBXResourcesBuildPhase", [
        ("buildActionMask", "2147483647"),
        ("files", "()"),
        ("runOnlyForDeploymentPostprocessing", "0"),
    ])

    # ----- PBXSourcesBuildPhase -----
    for ph in (PH_SRC_APP, PH_SRC_UTEST, PH_SRC_UITEST):
        add(ph, "PBXSourcesBuildPhase", [
            ("buildActionMask", "2147483647"),
            ("files", "()"),
            ("runOnlyForDeploymentPostprocessing", "0"),
        ])

    # ----- PBXTargetDependency -----
    add(DEP_UTEST, "PBXTargetDependency", [
        ("target", f"{APP} /* OPFCaptureBuilder */"),
        ("targetProxy", f"{PROXY_UTEST} /* PBXContainerItemProxy */"),
    ])
    add(DEP_UITEST, "PBXTargetDependency", [
        ("target", f"{APP} /* OPFCaptureBuilder */"),
        ("targetProxy", f"{PROXY_UITEST} /* PBXContainerItemProxy */"),
    ])

    # ----- XCBuildConfiguration -----
    def xcconfig(cid, name, settings):
        add(cid, "XCBuildConfiguration", [
            ("buildSettings", build_settings_dict(settings)),
            ("name", name),
        ])

    for name in ("Debug", "Release"):
        proj = dict(COMMON)
        if name == "Debug":
            proj.update({
                "DEBUG_INFORMATION_FORMAT": "dwarf",
                "ENABLE_TESTABILITY": "YES",
                "GCC_DYNAMIC_NO_PIC": "NO",
                "GCC_OPTIMIZATION_LEVEL": "0",
                "GCC_PREPROCESSOR_DEFINITIONS": '(\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t)',
                "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
                "ONLY_ACTIVE_ARCH": "YES",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
                "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
            })
        else:
            proj.update({
                "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
                "ENABLE_NS_ASSERTIONS": "NO",
                "MTL_ENABLE_DEBUG_INFO": "NO",
                "SWIFT_COMPILATION_MODE": "wholemodule",
            })
        xcconfig(cfg[("proj", name)], name, proj)

        app = {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "DEVELOPMENT_TEAM": '""',
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_FILE": "Config/Info.plist",
            "INFOPLIST_KEY_CFBundleDisplayName": '"OPF Capture Builder"',
            "INFOPLIST_KEY_LSApplicationCategoryType": '"public.app-category.utilities"',
            "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
            "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
            "INFOPLIST_KEY_UIStatusBarStyle": "UIStatusBarStyleDefault",
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
            "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t)',
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "SWIFT_VERSION": "5.0",
            "TARGETED_DEVICE_FAMILY": '"1,2"',
        }
        xcconfig(cfg[("app", name)], name, app)

        utest = {
            "BUNDLE_LOADER": '"$(TEST_HOST)"',
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "DEVELOPMENT_TEAM": '""',
            "GENERATE_INFOPLIST_FILE": "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + ".tests",
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "SWIFT_EMIT_LOC_STRINGS": "NO",
            "SWIFT_VERSION": "5.0",
            "TARGETED_DEVICE_FAMILY": '"1,2"',
            "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/OPFCaptureBuilder.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/OPFCaptureBuilder"',
        }
        xcconfig(cfg[("utest", name)], name, utest)

        uitest = {
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "DEVELOPMENT_TEAM": '""',
            "GENERATE_INFOPLIST_FILE": "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + ".uitests",
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "SWIFT_EMIT_LOC_STRINGS": "NO",
            "SWIFT_VERSION": "5.0",
            "TARGETED_DEVICE_FAMILY": '"1,2"',
            "TEST_TARGET_NAME": "OPFCaptureBuilder",
        }
        xcconfig(cfg[("uitest", name)], name, uitest)

    # ----- XCConfigurationList -----
    def cfg_list(cid, label, scope):
        add(cid, "XCConfigurationList", [
            ("buildConfigurations", "(\n\t\t\t\t" + cfg[(scope, "Debug")] + " /* Debug */,\n\t\t\t\t"
             + cfg[(scope, "Release")] + " /* Release */,\n\t\t\t)"),
            ("defaultConfigurationIsVisible", "0"),
            ("defaultConfigurationName", "Release"),
        ])

    cfg_list(CFG_LIST_PROJECT, "project", "proj")
    cfg_list(CFG_LIST_APP, "app", "app")
    cfg_list(CFG_LIST_UTEST, "utest", "utest")
    cfg_list(CFG_LIST_UITEST, "uitest", "uitest")

    header = ("// !$*UTF8*$!\n"
              "{\n"
              "\tarchiveVersion = 1;\n"
              "\tclasses = {\n\t};\n"
              "\tobjectVersion = 77;\n"
              "\tobjects = {\n")
    # Re-nest object blocks with correct 2-tab indentation
    body = "\n".join(blocks)
    body = "\n".join("\t" + line if line.strip() else line for line in body.split("\n"))
    footer = ("\n\t};\n"
              f"\trootObject = {PROJECT} /* Project object */;\n"
              "}\n")

    out = header + body + footer
    os.makedirs(os.path.join(ROOT, "OPFCaptureBuilder.xcodeproj"), exist_ok=True)
    project_path = os.path.join(ROOT, "OPFCaptureBuilder.xcodeproj", "project.pbxproj")
    with open(project_path, "w") as f:
        f.write(out)

    # Self-check: the file must parse with Xcode's OpenStep plist grammar. This catches
    # values that contain characters which are illegal in an unquoted string (for example
    # `<` in `sourceTree = "<group>"`), which would make Xcode report the project as damaged.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import openstep_plist

    try:
        document = openstep_plist.parse_file(__import__("pathlib").Path(project_path))
        assert document["objectVersion"] == "77", "objectVersion missing from generated project"
    except Exception as error:  # noqa: BLE001
        raise SystemExit(f"FATAL: generated project.pbxproj does not parse: {error}")

    print("Wrote project.pbxproj (%d bytes, %d objects) — OpenStep parse check passed"
          % (len(out), ids.n))


if __name__ == "__main__":
    main()
