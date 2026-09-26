//
//  ValidationReportView.swift
//  OPFCaptureBuilder
//
//  Runs the validator over the freshly generated OPF documents and shows the result with
//  the ability to copy the plain-text report and open the official schemas notice.
//

import SwiftUI

struct ValidationReportView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var project: CaptureProject

    @State private var report: ValidationReport?
    @State private var isRunning = false
    @State private var copied = false

    var body: some View {
        List {
            Section {
                Button {
                    runValidation()
                } label: {
                    Label(isRunning ? "Validating…" : "Run validation", systemImage: "checkmark.seal")
                }
                .disabled(isRunning)
                .accessibilityIdentifier("validation.run")
            }

            if let report {
                Section {
                    summaryRow(report)
                } header: {
                    Text("Result")
                }

                if !report.checkedDocuments.isEmpty {
                    Section("Documents checked") {
                        ForEach(report.checkedDocuments, id: \.self) { document in
                            Label(document, systemImage: "doc.text")
                                .font(.subheadline)
                        }
                    }
                }

                if report.issues.isEmpty {
                    Section {
                        Label("No issues found. The project is structurally valid and each resource resolves.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                    }
                } else {
                    Section("Issues") {
                        ForEach(report.sortedIssues) { issue in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(issue.severity.displayName, systemImage: AppTheme.severityIcon(issue.severity))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.severityColor(issue.severity))
                                Text(issue.message)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 8) {
                                    Text(issue.code)
                                    if let document = issue.document {
                                        Text("• \(document)")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    Button {
                        UIPasteboard.general.string = report.plainText(projectName: project.name)
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy plain-text report", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .navigationTitle("Validation Report")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let refreshed = model.store.projects.first(where: { $0.id == project.id }) {
                project = refreshed
            }
            runValidation()
        }
    }

    private func summaryRow(_ report: ValidationReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(report.isValid ? "Passed with no errors" : "Failed",
                  systemImage: report.isValid ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(report.isValid ? AppTheme.success : AppTheme.danger)
                .font(.headline)
            HStack(spacing: 16) {
                badge("Errors", report.errors.count, AppTheme.danger)
                badge("Warnings", report.warnings.count, AppTheme.warning)
                badge("Info", report.infos.count, AppTheme.accent)
            }
        }
    }

    private func badge(_ title: String, _ count: Int, _ color: Color) -> some View {
        VStack {
            Text("\(count)").font(.title3.weight(.bold)).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(title)")
    }

    private func runValidation() {
        isRunning = true
        defer { isRunning = false }
        let imagesDirectory = model.imagesDirectory(for: project)
        let result = OPFExporter.build(project: project, imagesDirectory: imagesDirectory) { relativeURI in
            let name = (relativeURI as NSString).lastPathComponent
            return FileManager.default.fileExists(
                atPath: imagesDirectory.appendingPathComponent(name).path
            )
        }
        report = result.report
    }
}
