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

            Section {
                Stepper(value: $project.captureIntervalSeconds,
                        in: CaptureInterval.fastestSeconds...CaptureInterval.slowestSeconds,
                        step: 0.5) {
                    LabeledContent("Interval", value: CaptureInterval.description(project.captureIntervalSeconds))
                }
                .accessibilityIdentifier("detail.interval.stepper")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CaptureInterval.presets, id: \.self) { value in
                            let isSelected = abs(project.captureIntervalSeconds - value) < 0.001
                            Button {
                                project.captureIntervalSeconds = value
                            } label: {
                                Text(intervalChipLabel(value))
                                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? AppTheme.accent : AppTheme.neutralSurface)
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityIdentifier("detail.interval.presets")
            } header: {
                Text("Capture interval")
            } footer: {
                Text("While a capture run is active, the live camera stores one full-resolution photograph every \(CaptureInterval.secondsLabel(project.captureIntervalSeconds)). Location and device attitude are recorded with every frame. Tap the shutter once to start and again to stop.")
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

    private func intervalChipLabel(_ seconds: Double) -> String {
        let text = seconds == seconds.rounded() ? String(Int(seconds)) : String(format: "%.1f", seconds)
        return "\(text) s"
    }
}
