//
//  ExportView.swift
//  OPFCaptureBuilder
//
//  Validates, stages, zips, and shares the OPF project through the system share sheet
//  (Save to Files, AirDrop, and every other target). Temporary files are removed once
//  sharing finishes.
//

import SwiftUI
import UIKit

struct ExportView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var project: CaptureProject

    @State private var report: ValidationReport?
    @State private var archiveURL: URL?
    @State private var isPreparing = false
    @State private var showingShareSheet = false
    @State private var errorMessage: String?
    @State private var stageMessage = ""

    var body: some View {
        List {
            Section {
                Text("The export creates a ZIP archive containing project.opf, the JSON resources, the photographs and a validation-report.txt file, and opens the iOS share sheet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let report {
                Section("Pre-export validation") {
                    Label(report.isValid ? "No errors" : "\(report.errors.count) error(s)",
                          systemImage: report.isValid ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(report.isValid ? AppTheme.success : AppTheme.danger)
                    if !report.warnings.isEmpty {
                        Label("\(report.warnings.count) warning(s)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.warning)
                    }
                    if !report.isValid {
                        Text("Fix the errors shown in the validation report before exporting. An invalid project is never written.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if isPreparing {
                    HStack {
                        ProgressView()
                        Text(stageMessage.isEmpty ? "Preparing…" : stageMessage)
                    }
                } else {
                    Button {
                        Task { await prepareAndShare() }
                    } label: {
                        Label("Export and share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(report?.isValid == false)
                    .accessibilityIdentifier("export.share")
                }
            }

            Section {
                Label("Save to Files", systemImage: "folder")
                Label("AirDrop", systemImage: "airplayaudio")
                Label("Any other installed share target", systemImage: "ellipsis.circle")
            } header: {
                Text("Available share targets")
            } footer: {
                Text("Temporary export files are deleted after the share sheet closes.")
            }
        }
        .navigationTitle("Export Project")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshReport)
        .sheet(isPresented: $showingShareSheet, onDismiss: {
            model.exportService.cleanUpAfterSharing()
            archiveURL = nil
        }) {
            if let archiveURL {
                ShareSheet(items: [archiveURL])
            }
        }
        .alert("Export problem", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func refreshReport() {
        if let refreshed = model.store.projects.first(where: { $0.id == project.id }) {
            project = refreshed
        }
        let imagesDirectory = model.imagesDirectory(for: project)
        report = OPFExporter.build(project: project, imagesDirectory: imagesDirectory) { relativeURI in
            let name = (relativeURI as NSString).lastPathComponent
            return FileManager.default.fileExists(atPath: imagesDirectory.appendingPathComponent(name).path)
        }.report
    }

    private func prepareAndShare() async {
        isPreparing = true
        stageMessage = "Building the OPF project…"
        defer { isPreparing = false }

        let imagesDirectory = model.imagesDirectory(for: project)
        let result = await model.exportService.prepareArchive(project: project, imagesDirectory: imagesDirectory)
        switch result {
        case let .success(url):
            archiveURL = url
            showingShareSheet = true
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }
}

/// Thin wrapper around UIActivityViewController so ShareLink-style behaviour is available
/// with an explicit completion handler we can use to clean up.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
