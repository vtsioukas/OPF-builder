//
//  ImportView.swift
//  OPFCaptureBuilder
//
//  Imports photographs from Files or the photo library. After each import the user is told
//  exactly which useful metadata was missing, and whether any pixels were transcoded.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var project: CaptureProject

    @State private var isImporting = false
    @State private var showingFileImporter = false
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var outcomes: [ImportSummary] = []
    @State private var errorMessage: String?

    private let imageContentTypes: [UTType] = [.image, .jpeg, .heic, .tiff, .png]

    struct ImportSummary: Identifiable {
        let id = UUID()
        var fileName: String
        var missingFields: [String]
        var transcodeNotice: String?
    }

    var body: some View {
        List {
            Section {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import from Files", systemImage: "folder")
                }
                .disabled(isImporting)
                .accessibilityIdentifier("import.files")

                PhotosPicker(
                    selection: $photoSelections,
                    maxSelectionCount: 50,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Import from Photos", systemImage: "photo.on.rectangle.angled")
                }
                .disabled(isImporting)
                .accessibilityIdentifier("import.photos")
            } header: {
                Text("Sources")
            } footer: {
                Text("Originals are copied into this project. EXIF metadata in the stored originals is never rewritten.")
            }

            if isImporting {
                Section {
                    HStack {
                        ProgressView()
                        Text("Importing…")
                    }
                }
            }

            if !outcomes.isEmpty {
                Section("Import report") {
                    ForEach(outcomes) { outcome in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(outcome.fileName)
                                .font(.subheadline.weight(.semibold))
                            if outcome.missingFields.isEmpty {
                                Label("No missing metadata detected", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.success)
                            } else {
                                Label("Missing: \(outcome.missingFields.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.warning)
                            }
                            if let notice = outcome.transcodeNotice {
                                Text(notice)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Import Photographs")
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: imageContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task { await importFiles(urls) }
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
        .onChange(of: photoSelections) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task { await importPhotos(newValue) }
        }
        .alert("Import problem", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Import

    private func importFiles(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        for url in urls {
            do {
                let outcome = try await ImageImporter.importFile(
                    at: url,
                    into: project,
                    store: model.store,
                    includeSensorData: false
                )
                model.addImage(outcome.record, to: project)
                outcomes.append(ImportSummary(
                    fileName: outcome.record.fileName,
                    missingFields: outcome.missingFields,
                    transcodeNotice: outcome.transcodeNotice
                ))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        reloadProject()
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer {
            isImporting = false
            photoSelections = []
        }
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let outcome = try await ImageImporter.importPhotoLibraryItem(
                    data: data,
                    suggestedName: nil,
                    creationDate: nil,
                    location: nil,
                    into: project,
                    store: model.store
                )
                model.addImage(outcome.record, to: project)
                outcomes.append(ImportSummary(
                    fileName: outcome.record.fileName,
                    missingFields: outcome.missingFields,
                    transcodeNotice: outcome.transcodeNotice
                ))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        reloadProject()
    }

    private func reloadProject() {
        if let updated = model.store.projects.first(where: { $0.id == project.id }) {
            project = updated
        }
    }
}
