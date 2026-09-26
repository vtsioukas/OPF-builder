//
//  ImageListView.swift
//  OPFCaptureBuilder
//
//  Lists every photograph in the project and flags the ones missing useful metadata.
//

import SwiftUI

struct ImageListView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var project: CaptureProject
    @State private var imageToDelete: ImageRecord?

    var body: some View {
        Group {
            if project.images.isEmpty {
                ContentUnavailableView(
                    "No photographs",
                    systemImage: "photo.on.rectangle",
                    description: Text("Capture or import photographs to build the project.")
                )
            } else {
                List {
                    ForEach(project.images) { image in
                        NavigationLink {
                            ImageMetadataView(project: project, image: image)
                        } label: {
                            row(image)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                imageToDelete = image
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Photographs")
        .confirmationDialog(
            "Remove this photograph from the project?",
            isPresented: Binding(
                get: { imageToDelete != nil },
                set: { if !$0 { imageToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let imageToDelete {
                    model.removeImage(imageToDelete, from: project)
                    if let updated = model.store.projects.first(where: { $0.id == project.id }) {
                        project = updated
                    }
                }
                imageToDelete = nil
            }
            Button("Cancel", role: .cancel) { imageToDelete = nil }
        }
    }

    private func row(_ image: ImageRecord) -> some View {
        let missing = ImageImporter.missingFields(for: image)
        return VStack(alignment: .leading, spacing: 4) {
            Text(image.fileName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 10) {
                Label("\(image.pixelWidth)×\(image.pixelHeight)", systemImage: "aspectratio")
                Label(image.origin.displayName, systemImage: "tray.and.arrow.down")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if missing.isEmpty {
                Label("Metadata complete", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.success)
            } else {
                Label("Missing: \(missing.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
