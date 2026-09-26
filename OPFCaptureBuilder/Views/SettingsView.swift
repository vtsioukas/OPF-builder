//
//  SettingsView.swift
//  OPFCaptureBuilder
//
//  Settings, privacy, OPF attribution and open-source licence notices. There is no
//  analytics toggle because there is no analytics.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingResetConfirmation = false

    var body: some View {
        List {
            Section("OPF Capture Builder") {
                MetadataRow(label: "Version", value: appVersion)
                MetadataRow(label: "OPF specification", value: "1.0")
                MetadataRow(label: "Bundled schemas", value: "\(OPFSchemaProvider.availableSchemaNames().count) official schemas")
            }

            Section("Privacy") {
                Label("Everything stays on this device", systemImage: "lock.shield")
                    .font(.subheadline)
                Text("Photographs, metadata and projects are stored in the app's Documents folder. The app makes no network requests, contains no analytics and no advertising, and does not create user accounts. Data leaves the device only when you export a project and pick a destination in the share sheet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions this app may request") {
                permissionRow("Camera", "Capture original-resolution photographs.", "camera")
                permissionRow("Photo library", "Import photographs you select.", "photo.on.rectangle")
                permissionRow("Location (while using)", "Record each capture's position. Foreground only; no background access is requested.", "location")
                permissionRow("Motion", "Record device attitude. Stored as device attitude, never as camera orientation.", "gyroscope")
            }

            Section("Altitude") {
                Text("Recorded GPS altitude is height above the WGS 84 ellipsoid (ellipsoidal height). It is not orthometric height above mean sea level. This app never converts between the two without a verified geoid model.")
                    .font(.caption)
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Open Photogrammetry Format")
                        .font(.subheadline.weight(.semibold))
                    Text("© 2023–2024 Pix4D SA. The OPF specification, its JSON schemas and examples are licensed under the Creative Commons Attribution 4.0 International License (CC BY 4.0). Scripts and code are licensed under the Apache License 2.0.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let url = URL(string: "https://pix4d.github.io/opf-spec/") {
                        Link("pix4d.github.io/opf-spec", destination: url)
                            .font(.caption)
                    }
                    Text("Grégoire Krähenbühl, Klaus Schneider-Zapp, Bastien Dalla Piazza, Juan Hernando, Juan Palacios, Massimiliano Bellomo, Mohamed-Ghath Kaabi, Christoph Strecha, Pix4D, 2023.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Attribution")
            }

            Section("Open-source dependencies") {
                licenceRow("Open Photogrammetry Format schemas", "CC BY 4.0 / Apache 2.0", "© 2023–2024 Pix4D SA")
                licenceRow("FNV-1a 64", "Public domain", "Landon Curt Noll / Glenn Fowler (algorithm)")
                licenceRow("CRC-32 (IEEE 802.3)", "Public domain", "Standard polynomial 0xEDB88320")
                licenceRow("Apple frameworks", "Apple SDK terms", "AVFoundation, CoreLocation, CoreMotion, ImageIO, SwiftUI, Compression, PhotosUI")
            }

            Section {
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset onboarding", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog("Show the onboarding screen again next launch?",
                            isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("Reset") {
                model.hasCompletedOnboarding = false
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func permissionRow(_ title: String, _ detail: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func licenceRow(_ name: String, _ licence: String, _ holder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.subheadline.weight(.semibold))
            Text("\(licence) — \(holder)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
