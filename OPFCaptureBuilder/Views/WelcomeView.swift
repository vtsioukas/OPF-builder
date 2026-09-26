//
//  WelcomeView.swift
//  OPFCaptureBuilder
//
//  Onboarding. Explains what OPF is, what the app does, and the privacy posture, and
//  collects the acknowledgement that GPS altitude is ellipsoidal height.
//

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    CardContainer(title: "What this app does", systemImage: "camera.viewfinder") {
                        Text("Capture overlapping photographs or import them, record the sensor data your device can actually measure, and export a project in the Open Photogrammetry Format version 1.0.")
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CardContainer(title: "What it will not do", systemImage: "hand.raised") {
                        VStack(alignment: .leading, spacing: 8) {
                            bullet("No photogrammetric calibration, point clouds or LiDAR. Those are out of scope for this version.")
                            bullet("No invented data. Coordinates, accuracies, calibration and orientation are only written when they were really measured or you entered them.")
                            bullet("No accounts, no analytics, no advertising, no uploads.")
                        }
                    }

                    CardContainer(title: "Your data stays on this device", systemImage: "lock.shield") {
                        Text("Projects and photographs are stored in this app's Documents directory. Nothing leaves the device unless you export it and choose a destination in the iOS share sheet.")
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CardContainer(title: "About altitude", systemImage: "mountain.2") {
                        Text("Global Positioning System altitude is height above the WGS 84 ellipsoid, not orthometric height above mean sea level. This app records ellipsoidal height and never relabels it.")
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        model.hasCompletedOnboarding = true
                    } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("welcome.continue")
                }
                .padding()
            }
            .background(AppTheme.groupedBackground)
            .navigationTitle("OPF Capture Builder")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            Text("Capture photographs for photogrammetry and export an Open Photogrammetry Format project.")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .padding(.top, 7)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
