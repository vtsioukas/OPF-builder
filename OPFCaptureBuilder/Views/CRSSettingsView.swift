//
//  CRSSettingsView.swift
//  OPFCaptureBuilder
//
//  Coordinate reference system and positioning settings. Makes the CRS explicit and
//  warns about ellipsoidal versus orthometric altitude.
//

import SwiftUI

struct CRSSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var project: CaptureProject

    @State private var crsDefinition: String = OPFConstants.defaultCRSDefinition
    @State private var emitSceneReferenceFrame = false
    @State private var geoidHeightText = ""
    @State private var acknowledged = false

    static let knownCRS: [(label: String, definition: String)] = [
        ("WGS 84 (geographic, EPSG:4326)", "EPSG:4326"),
        ("NAD83 (geographic, EPSG:4269)", "EPSG:4269"),
        ("ETRS89 (geographic, EPSG:4258)", "EPSG:4258")
    ]

    var body: some View {
        Form {
            Section {
                Picker("Coordinate reference system", selection: $crsDefinition) {
                    ForEach(Self.knownCRS, id: \.definition) { entry in
                        Text(entry.label).tag(entry.definition)
                    }
                }
                .accessibilityIdentifier("crs.picker")
                Text("The MVP only produces WGS 84 geographic coordinates, which is what the device's location service provides. Other geographic CRSs are listed for completeness; projected CRSs are not produced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Coordinate reference system")
            }

            Section {
                Toggle("Write a scene reference frame", isOn: $emitSceneReferenceFrame)
                    .accessibilityIdentifier("crs.sceneframe")
                Text("A scene reference frame is optional and is not required for a single-camera dataset. Enable it if downstream tools need an explicit project CRS and canonical transform.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Scene reference frame")
            }

            Section {
                HStack {
                    Text("Constant geoid height (m)")
                    Spacer()
                    TextField("optional", text: $geoidHeightText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                }
                Text("Leave empty unless you have a verified value. Do not enter a guess: a wrong geoid height shifts every height in the project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Geoid")
            }

            Section {
                Toggle("I understand that altitude is ellipsoidal height", isOn: $acknowledged)
                    .accessibilityIdentifier("crs.acknowledge")
                Text("GPS altitude is height above the WGS 84 ellipsoid. It is not orthometric height above mean sea level, and the two can differ by tens of metres. This app records ellipsoidal height and never relabels it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Altitude warning")
            }

            Section {
                Button("Save settings") { save() }
                    .disabled(!acknowledged && hasLocationData)
            }
        }
        .navigationTitle("CRS and Positioning")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prefill)
    }

    private var hasLocationData: Bool {
        project.images.contains { $0.geolocation != nil }
    }

    private func prefill() {
        crsDefinition = project.crsDefinition
        emitSceneReferenceFrame = project.emitSceneReferenceFrame
        acknowledged = project.acknowledgedAltitudeWarning
        if let geoid = project.geoidHeight { geoidHeightText = String(geoid) }
    }

    private func save() {
        var updated = project
        updated.crsDefinition = crsDefinition
        updated.emitSceneReferenceFrame = emitSceneReferenceFrame
        updated.acknowledgedAltitudeWarning = acknowledged
        updated.geoidHeight = Double(geoidHeightText)
        project = updated
        model.save(updated)
        model.banner = BannerMessage(text: "Positioning settings saved.", kind: .success)
    }
}
