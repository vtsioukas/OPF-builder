//
//  ProjectDetailView.swift
//  OPFCaptureBuilder
//
//  The hub for one project: capture, import, inspect, calibrate, validate and export.
//

import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var project: CaptureProject

    init(project: CaptureProject) {
        _project = State(initialValue: project)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.description.isEmpty ? "No description" : project.description)
                        .font(.subheadline)
                        .foregroundStyle(project.description.isEmpty ? .secondary : .primary)
                    HStack(spacing: 12) {
                        Label("\(project.images.count) images", systemImage: "photo.on.rectangle")
                        Label(ByteCountFormatterHelper.string(model.store.storageSize(of: project)), systemImage: "internaldrive")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Overview")
            }

            Section("Capture and import") {
                NavigationLink {
                    CameraCaptureView(project: $project)
                } label: {
                    Label("Camera capture", systemImage: "camera")
                }
                .accessibilityIdentifier("detail.capture")

                NavigationLink {
                    ImportView(project: $project)
                } label: {
                    Label("Import photographs", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("detail.import")

                NavigationLink {
                    ImageListView(project: $project)
                } label: {
                    Label("Photographs (\(project.images.count))", systemImage: "photo.stack")
                }
                .accessibilityIdentifier("detail.images")
            }

            Section("Camera and positioning") {
                NavigationLink {
                    CalibrationEditorView(project: $project)
                } label: {
                    Label("Camera calibration", systemImage: "camera.aperture")
                }
                .accessibilityIdentifier("detail.calibration")

                NavigationLink {
                    CRSSettingsView(project: $project)
                } label: {
                    Label("Coordinate reference system", systemImage: "globe.europe.africa")
                }
                .accessibilityIdentifier("detail.crs")
            }

            Section("Open Photogrammetry Format") {
                NavigationLink {
                    ValidationReportView(project: $project)
                } label: {
                    Label("Validation report", systemImage: "checkmark.seal")
                }
                .accessibilityIdentifier("detail.validate")

                NavigationLink {
                    ExportView(project: $project)
                } label: {
                    Label("Export project", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("detail.export")
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        model.save(project)
                        model.banner = BannerMessage(text: "Project saved.", kind: .success)
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down.on.square")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .onChange(of: project) { _, newValue in
            model.save(newValue)
        }
        .onAppear {
            if let refreshed = model.store.projects.first(where: { $0.id == project.id }) {
                project = refreshed
            }
        }
    }
}
