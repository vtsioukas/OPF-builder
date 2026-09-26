//
//  ImageMetadataView.swift
//  OPFCaptureBuilder
//
//  The metadata inspector: everything the app knows about one photograph, with explicit
//  "unavailable" states for anything not measured, and an explanation of the ellipsoidal
//  altitude semantics.
//

import SwiftUI

struct ImageMetadataView: View {
    @EnvironmentObject private var model: AppModel
    let project: CaptureProject
    let image: ImageRecord

    var body: some View {
        List {
            Section("Preview") {
                if let url = try? model.store.imageURL(for: image, in: project),
                   let uiImage = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Photograph \(image.fileName)")
                } else {
                    Text("Preview unavailable")
                        .foregroundStyle(.secondary)
                }
            }

            Section("File") {
                MetadataRow(label: "File name", value: image.fileName)
                MetadataRow(label: "Origin", value: image.origin.displayName)
                MetadataRow(label: "Size", value: ByteCountFormatterHelper.string(image.fileByteSize))
                MetadataRow(label: "Type", value: image.utTypeIdentifier)
                MetadataRow(label: "Pixels unmodified",
                            value: image.isOriginalPixelsUnmodified ? "Yes — original kept" : "No — transcoded to JPEG")
            }

            Section {
                MetadataRow(label: "Width", value: "\(image.pixelWidth) px")
                MetadataRow(label: "Height", value: "\(image.pixelHeight) px")
                MetadataRow(label: "EXIF orientation", value: "\(image.exifOrientation)")
            } header: {
                Text("Image geometry")
            }

            Section("Acquisition") {
                MetadataRow(label: "Capture time",
                            value: image.captureTime.map(OPFDateFormat.localized) ?? "Unavailable")
                MetadataRow(label: "Time source", value: image.captureTimeSource.displayName,
                            isAvailable: image.captureTimeSource != .unavailable)
            }

            EXIFSection(summary: image.exifSummary)

            Section {
                if let geo = image.geolocation {
                    MetadataRow(label: "Latitude", value: String(format: "%.7f°", geo.latitude))
                    MetadataRow(label: "Longitude", value: String(format: "%.7f°", geo.longitude))
                    MetadataRow(label: "Altitude (ellipsoidal)", value: String(format: "%.2f m", geo.ellipsoidalAltitude))
                    MetadataRow(label: "Horizontal accuracy", value: String(format: "± %.1f m", geo.horizontalAccuracy))
                    MetadataRow(label: "Vertical accuracy",
                                value: geo.hasVerticalAccuracy ? String(format: "± %.1f m", geo.verticalAccuracy) : "Unavailable",
                                isAvailable: geo.hasVerticalAccuracy)
                    MetadataRow(label: "Fix time", value: OPFDateFormat.localized(geo.timestamp))
                    Text("This altitude is height above the WGS 84 ellipsoid, not orthometric height above mean sea level.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No location was recorded for this photograph.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Location")
            }

            Section {
                if let attitude = image.deviceAttitude {
                    MetadataRow(label: "Quaternion (w,x,y,z)",
                                value: attitude.quaternionWXYZ.map { String(format: "%.4f", $0) }.joined(separator: ", "))
                    MetadataRow(label: "Pitch", value: String(format: "%.2f°", attitude.pitchRadians * 180 / .pi))
                    MetadataRow(label: "Roll", value: String(format: "%.2f°", attitude.rollRadians * 180 / .pi))
                    MetadataRow(label: "Yaw", value: String(format: "%.2f°", attitude.yawRadians * 180 / .pi))
                    Text(attitude.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No device attitude was recorded for this photograph.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Device attitude (not camera orientation)")
            }

            Section("Sensor group") {
                MetadataRow(label: "Signature", value: image.sensorSignature)
            }
        }
        .navigationTitle("Metadata")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EXIFSection: View {
    let summary: EXIFSummary

    var body: some View {
        Section {
            row("Camera make", summary.cameraMake)
            row("Camera model", summary.cameraModel)
            row("Lens", summary.lensModel)
            row("Focal length", summary.focalLengthMM.map { String(format: "%.1f mm", $0) })
            row("35 mm equivalent", summary.focalLengthIn35mmMM.map { String(format: "%.1f mm", $0) })
            row("ISO", summary.iso.map { "\($0)" })
            row("Exposure", summary.exposureTimeSeconds.map { String(format: "%.4f s", $0) })
            row("Aperture", summary.fNumber.map { String(format: "f/%.1f", $0) })
        } header: {
            Text("EXIF")
        } footer: {
            if summary.availableFieldNames.isEmpty {
                Text("No EXIF fields could be read from this file.")
            }
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        MetadataRow(label: label, value: value ?? "Unavailable", isAvailable: value != nil)
    }
}
