//
//  ExportService.swift
//  OPFCaptureBuilder
//
//  Coordinates export: stages the OPF package, zips it, hands the archive to the system
//  share sheet, and — critically — cleans the temporary files up afterwards. Staging
//  directories are tracked so a crash of the share flow cannot leak megabytes of images
//  into the tmp directory.
//

import Foundation

@MainActor
final class ExportService: ObservableObject {

    enum State: Equatable {
        case idle
        case working(String)
        case ready(archiveURL: URL, packageName: String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private var stagingDirectories: [URL] = []

    /// Produces the archive. Does not present UI; the view layer owns the share sheet.
    func prepareArchive(project: CaptureProject, imagesDirectory: URL) async -> Result<URL, Error> {
        state = .working("Building the OPF project…")
        let temporary = FileManager.default.temporaryDirectory
        do {
            let result = try OPFExporter.createArchive(
                project: project,
                imagesDirectory: imagesDirectory,
                temporaryDirectory: temporary
            )
            stagingDirectories.append(result.stagingDirectory)
            state = .ready(archiveURL: result.archiveURL, packageName: project.name)
            return .success(result.archiveURL)
        } catch {
            state = .failed(error.localizedDescription)
            return .failure(error)
        }
    }

    /// Called once the share sheet is dismissed (completion, cancellation or error).
    func cleanUpAfterSharing() {
        for directory in stagingDirectories {
            OPFExporter.cleanUp(directory)
        }
        stagingDirectories.removeAll()
        state = .idle
    }

    /// Emergency cleanup, e.g. when leaving the export screen without sharing.
    func cleanUpOrphanedStagingDirectories() {
        cleanUpAfterSharing()
        let temporary = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: temporary, includingPropertiesForKeys: nil
        ) else { return }
        for url in contents where url.lastPathComponent.hasPrefix("opf-export-") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
