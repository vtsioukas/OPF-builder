//
//  AppModel.swift
//  OPFCaptureBuilder
//
//  App-wide state: the project list, the currently open project and the services shared
//  between screens. Everything is local; no network, no accounts, no analytics.
//

import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {

    @Published var store = ProjectStore()
    @Published var selectedProject: CaptureProject?
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingKey) }
    }
    @Published var banner: BannerMessage?

    let sensorRecorder = SensorRecorder()
    let exportService = ExportService()

    private static let onboardingKey = "OPFCaptureBuilder.hasCompletedOnboarding"

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
        store.load()
    }

    // MARK: - Project lifecycle

    func refresh() {
        store.load()
        if let selected = selectedProject,
           let updated = store.projects.first(where: { $0.id == selected.id }) {
            selectedProject = updated
        }
    }

    func open(_ project: CaptureProject) {
        selectedProject = project
    }

    func save(_ project: CaptureProject) {
        do {
            try store.update(project)
            selectedProject = project
        } catch {
            banner = BannerMessage(text: error.localizedDescription, kind: .error)
        }
    }

    // MARK: - Image management

    func addImage(_ record: ImageRecord, to project: CaptureProject) {
        var updated = project
        updated.images.append(record)
        save(updated)
    }

    func removeImage(_ record: ImageRecord, from project: CaptureProject) {
        var updated = project
        updated.images.removeAll { $0.id == record.id }
        try? store.removeImageFile(named: record.fileName, in: project)
        save(updated)
    }

    func imagesDirectory(for project: CaptureProject) -> URL {
        (try? store.imagesFolder(for: project))
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(project.id.uuidString)
    }
}

struct BannerMessage: Identifiable, Equatable {
    enum Kind { case info, success, error }
    let id = UUID()
    var text: String
    var kind: Kind
}
