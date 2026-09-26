//
//  ProjectStore.swift
//  OPFCaptureBuilder
//
//  Owns the on-disk layout of every project inside the app's Documents directory:
//
//      Documents/
//        <ProjectUUID>/
//          project.json                  (app metadata: images, intrinsics, CRS)
//          images/                       (the photographs, originals kept untouched)
//
//  The OPF container (project.opf, camera-list.json, input-cameras.json, ...) is written
//  by OPFWriter/ExportService into a *separate* staging directory so the working project
//  and the exported artifact never interfere.
//

import Foundation

enum ProjectStoreError: Error, LocalizedError {
    case documentsUnavailable
    case projectNotFound(UUID)
    case nameRequired
    case destinationExists(String)

    var errorDescription: String? {
        switch self {
        case .documentsUnavailable:
            return "The app's Documents directory is not available."
        case let .projectNotFound(id):
            return "No project folder was found for \(id.uuidString)."
        case .nameRequired:
            return "A project name is required."
        case let .destinationExists(name):
            return "A project named \"\(name)\" already exists."
        }
    }
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [CaptureProject] = []

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Locations

    static var documentsURL: URL {
        get throws {
            guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw ProjectStoreError.documentsUnavailable
            }
            return url
        }
    }

    func projectFolder(for project: CaptureProject) throws -> URL {
        try Self.documentsURL.appendingPathComponent(project.id.uuidString, isDirectory: true)
    }

    func imagesFolder(for project: CaptureProject) throws -> URL {
        try projectFolder(for: project).appendingPathComponent(OPFConstants.Layout.imagesDirectory, isDirectory: true)
    }

    func imageURL(for record: ImageRecord, in project: CaptureProject) throws -> URL {
        try imagesFolder(for: project).appendingPathComponent(record.fileName, isDirectory: false)
    }

    // MARK: - Load / save

    func load() {
        do {
            let documents = try Self.documentsURL
            let entries = try fileManager.contentsOfDirectory(
                at: documents,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            var loaded: [CaptureProject] = []
            for entry in entries {
                let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDirectory else { continue }
                let metadata = entry.appendingPathComponent(OPFConstants.Layout.projectMetadataFile)
                guard fileManager.fileExists(atPath: metadata.path) else { continue }
                if let data = try? Data(contentsOf: metadata),
                   let project = try? decoder.decode(CaptureProject.self, from: data) {
                    loaded.append(project)
                }
            }
            projects = loaded.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            projects = []
        }
    }

    @discardableResult
    func createProject(name: String, description: String) throws -> CaptureProject {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProjectStoreError.nameRequired }
        guard !projects.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw ProjectStoreError.destinationExists(trimmed)
        }
        let project = CaptureProject.makeNew(name: trimmed, description: description)
        try persist(project)
        try fileManager.createDirectory(at: try imagesFolder(for: project), withIntermediateDirectories: true)
        projects.insert(project, at: 0)
        return project
    }

    func update(_ project: CaptureProject) throws {
        var copy = project
        copy.updatedAt = Date()
        try persist(copy)
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = copy
        } else {
            projects.append(copy)
        }
        projects.sort { $0.updatedAt > $1.updatedAt }
    }

    func rename(_ project: CaptureProject, to newName: String) throws -> CaptureProject {
        var copy = project
        copy.name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.name.isEmpty else { throw ProjectStoreError.nameRequired }
        try update(copy)
        return copy
    }

    func duplicate(_ project: CaptureProject) throws -> CaptureProject {
        var copy = project
        copy.id = UUID()
        copy.name = uniqueCopyName(basedOn: project.name)
        copy.createdAt = Date()
        copy.updatedAt = Date()
        try persist(copy)
        let source = try imagesFolder(for: project)
        let destination = try imagesFolder(for: copy)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: source.path) {
            let files = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            for file in files {
                let target = destination.appendingPathComponent(file.lastPathComponent)
                if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
                try fileManager.copyItem(at: file, to: target)
            }
        }
        projects.insert(copy, at: 0)
        return copy
    }

    func delete(_ project: CaptureProject) throws {
        let folder = try projectFolder(for: project)
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
        projects.removeAll { $0.id == project.id }
    }

    // MARK: - Image files

    /// Copies (never moves or rewrites) source bytes into the project's images folder and
    /// returns the relative file name to record.
    func storeImageFile(from sourceURL: URL, preferredExtension: String, in project: CaptureProject) throws -> String {
        let folder = try imagesFolder(for: project)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = preferredExtension.isEmpty ? sourceURL.pathExtension : preferredExtension
        let base = "IMG_\(Int(Date().timeIntervalSince1970 * 1000))_\(String(format: "%04X", Int.random(in: 0..<0xFFFF)))"
        let fileName = ext.isEmpty ? base : "\(base).\(ext)"
        let destination = folder.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return fileName
    }

    /// Stores already-materialised bytes (e.g. an AVFoundation photo or a transcoded JPEG).
    func storeImageData(_ data: Data, fileName: String, in project: CaptureProject) throws -> String {
        let folder = try imagesFolder(for: project)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(fileName)
        try data.write(to: destination, options: .atomic)
        return fileName
    }

    func removeImageFile(named fileName: String, in project: CaptureProject) throws {
        let url = try imagesFolder(for: project).appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: - Size reporting

    func storageSize(of project: CaptureProject) -> Int64 {
        guard let folder = try? projectFolder(for: project) else { return 0 }
        var total: Int64 = 0
        let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        while let url = enumerator?.nextObject() as? URL {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    // MARK: - Private

    private func persist(_ project: CaptureProject) throws {
        let folder = try projectFolder(for: project)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try encoder.encode(project)
        try data.write(to: folder.appendingPathComponent(OPFConstants.Layout.projectMetadataFile), options: .atomic)
    }

    private func uniqueCopyName(basedOn name: String) -> String {
        var candidate = "\(name) copy"
        var index = 2
        while projects.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(name) copy \(index)"
            index += 1
        }
        return candidate
    }
}
