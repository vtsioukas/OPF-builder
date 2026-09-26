//
//  OPFExporter.swift
//  OPFCaptureBuilder
//
//  The single façade that turns a project into a validated, zipped OPF package:
//
//      <ProjectName>/
//        project.opf
//        camera-list.json
//        input-cameras.json
//        validation-report.txt
//        scene-reference-frame.json   (optional)
//        images/…                     (the photographs)
//
//  It is used both by the app and by the unit tests, so the tested path is the shipping path.
//

import Foundation

struct OPFBuildResult {
    var documentSet: OPFDocumentSet
    var report: ValidationReport
    var documents: [OPFDocument]
}

enum OPFExporter {

    /// Generates documents for a project without writing anything to disk.
    ///
    /// - Parameters:
    ///   - imagesDirectory: when provided, camera UIDs are derived from the real image
    ///     bytes on disk (the same strategy the capture/import path uses).
    ///   - resourceExists: predicate used by the validator for each referenced URI.
    static func build(
        project: CaptureProject,
        imagesDirectory: URL? = nil,
        resourceExists: @escaping (String) -> Bool = { _ in true }
    ) -> OPFBuildResult {
        let provider: ((ImageRecord) -> UInt64)? = imagesDirectory.map { directory in
            { image in
                let url = directory.appendingPathComponent(image.fileName)
                if let id = try? OPFUID.identifyCamera(rawImageBytesAt: url) { return id }
                return OPFUID.cameraID(forImageBytes: Data(image.fileName.utf8))
            }
        }
        let documentSet = OPFWriter.build(project: project, cameraIDProvider: provider)
        let report = OPFValidator.validate(
            documentSet: documentSet,
            project: project,
            schemaProvider: { OPFSchemaProvider.schema(named: $0) },
            resourceExists: resourceExists
        )
        return OPFBuildResult(documentSet: documentSet, report: report, documents: documentSet.all)
    }

    /// Writes the documents, the reports and every image into a staging directory.
    /// Returns the staging directory URL. The caller owns cleanup.
    static func stage(
        project: CaptureProject,
        imagesDirectory: URL,
        into parentDirectory: URL
    ) throws -> (packageURL: URL, build: OPFBuildResult) {
        let fileManager = FileManager.default
        let packageName = sanitizedFolderName(project.name)
        let packageURL = parentDirectory.appendingPathComponent(packageName, isDirectory: true)
        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }

        // Validate first, using real file existence for every referenced URI.
        let imagesDestination = packageURL.appendingPathComponent(OPFConstants.Layout.imagesDirectory, isDirectory: true)
        let build = build(project: project, imagesDirectory: imagesDirectory) { relativeURI in
            let name = (relativeURI as NSString).lastPathComponent
            return fileManager.fileExists(atPath: imagesDirectory.appendingPathComponent(name).path)
        }

        // A document with schema errors is not written: the user must fix the project first.
        if !build.report.isValid {
            throw ExportError.validationFailed(build.report)
        }

        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: imagesDestination, withIntermediateDirectories: true)

        for document in build.documents {
            let url = packageURL.appendingPathComponent(document.relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try document.data().write(to: url, options: .atomic)
        }

        // Copy photographs byte-for-byte.
        for image in project.images {
            let source = imagesDirectory.appendingPathComponent(image.fileName)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = imagesDestination.appendingPathComponent(image.fileName)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.copyItem(at: source, to: destination)
        }

        // Human-readable validation report next to the archive.
        let reportText = build.report.plainText(projectName: project.name)
        try Data(reportText.utf8).write(
            to: packageURL.appendingPathComponent(OPFConstants.Layout.validationReportFile),
            options: .atomic
        )

        return (packageURL, build)
    }

    /// Stages the package, zips it, and returns the archive URL. Temporary files remain
    /// until the caller calls `cleanUp`, which happens after the share sheet is dismissed.
    static func createArchive(
        project: CaptureProject,
        imagesDirectory: URL,
        temporaryDirectory: URL
    ) throws -> (archiveURL: URL, stagingDirectory: URL, build: OPFBuildResult) {
        let fileManager = FileManager.default
        let stagingRoot = temporaryDirectory.appendingPathComponent("opf-export-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        let (packageURL, build) = try stage(
            project: project,
            imagesDirectory: imagesDirectory,
            into: stagingRoot
        )

        let archiveURL = stagingRoot.appendingPathComponent("\(sanitizedFolderName(project.name)).zip")
        let entries = try collectEntries(packageURL: packageURL, rootName: packageURL.lastPathComponent)
        let archive = try ZipArchiveWriter.archive(entries: entries)
        try archive.write(to: archiveURL, options: .atomic)

        return (archiveURL, stagingRoot, build)
    }

    static func cleanUp(_ stagingDirectory: URL) {
        try? FileManager.default.removeItem(at: stagingDirectory)
    }

    // MARK: - Helpers

    static func collectEntries(packageURL: URL, rootName: String) throws -> [ZipEntry] {
        let fileManager = FileManager.default
        var entries: [ZipEntry] = []
        guard let enumerator = fileManager.enumerator(
            at: packageURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator {
            let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isRegular else { continue }
            let relative = url.path.replacingOccurrences(of: packageURL.path + "/", with: "")
            let data = try Data(contentsOf: url)
            // JSON and text compress well; images are already compressed.
            let isCompressible = !["jpg", "jpeg", "heic", "png", "tif", "tiff"].contains(url.pathExtension.lowercased())
            entries.append(ZipEntry(path: "\(rootName)/\(relative)", data: data, useDeflate: isCompressible))
        }
        // Stable order for reproducible archives.
        return entries.sorted { $0.name < $1.name }
    }

    static func sanitizedFolderName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "OPF Project" : cleaned
    }
}

enum ExportError: Error, LocalizedError {
    case validationFailed(ValidationReport)

    var errorDescription: String? {
        switch self {
        case let .validationFailed(report):
            return "Export cancelled: the generated OPF project has \(report.errors.count) validation error(s). Open the validation report for details."
        }
    }
}
