//
//  NewProjectView.swift
//  OPFCaptureBuilder
//

import SwiftUI

struct NewProjectView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var projectDescription = ""
    @State private var exportAsJPEG = false
    @State private var emitSceneReferenceFrame = false
    @State private var crsDefinition = OPFConstants.defaultCRSDefinition
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("newproject.name")
                    TextField("Description", text: $projectDescription, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("newproject.description")
                }

                Section {
                    Toggle("Export photographs as JPEG", isOn: $exportAsJPEG)
                        .accessibilityIdentifier("newproject.jpeg")
                    Text("Off keeps the original file exactly as captured or imported. On transcodes non-JPEG originals to JPEG for maximum compatibility and tells you when it does.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Photograph format")
                }

                Section {
                    Toggle("Write a scene reference frame", isOn: $emitSceneReferenceFrame)
                    TextField("CRS definition", text: $crsDefinition)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("Only WGS 84 geographic coordinates (EPSG:4326) are fully supported. The CRS is declared explicitly; altitude is ellipsoidal height.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Coordinate reference system")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.danger)
                    }
                }
            }
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("newproject.create")
                }
            }
        }
    }

    private func create() {
        do {
            var project = try model.store.createProject(name: name, description: projectDescription)
            project.exportAsJPEG = exportAsJPEG
            project.emitSceneReferenceFrame = emitSceneReferenceFrame
            project.crsDefinition = crsDefinition.isEmpty ? OPFConstants.defaultCRSDefinition : crsDefinition
            try model.store.update(project)
            model.banner = BannerMessage(text: "Project \"\(project.name)\" created.", kind: .success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
