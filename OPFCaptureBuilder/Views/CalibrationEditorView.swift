//
//  CalibrationEditorView.swift
//  OPFCaptureBuilder
//
//  The advanced screen for entering verified camera intrinsics. A sensor stays "estimated
//  from EXIF" (not calibrated) until the user enters real values here; only then is it
//  written as `model_source: "user"` in the OPF project.
//

import SwiftUI

struct CalibrationEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var project: CaptureProject

    @State private var editingSignature: String?

    var body: some View {
        List {
            Section {
                Text("Intrinsics are only marked verified when you enter them here after confirming them. Values estimated from EXIF are labelled as estimates and are never presented as calibration.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if sensorSignatures.isEmpty {
                ContentUnavailableView(
                    "No cameras yet",
                    systemImage: "camera.aperture",
                    description: Text("Capture or import photographs first; sensors are derived from them.")
                )
            } else {
                ForEach(sensorSignatures, id: \.self) { signature in
                    let savedIntrinsics = project.manualIntrinsicsBySensorSignature[signature]
                    NavigationLink {
                        ManualIntrinsicsEditor(
                            signature: signature,
                            existing: savedIntrinsics,
                            onSave: { intrinsics in
                                var updated = project
                                updated.manualIntrinsicsBySensorSignature[signature] = intrinsics
                                project = updated
                                model.save(updated)
                            },
                            onClear: {
                                var updated = project
                                updated.manualIntrinsicsBySensorSignature.removeValue(forKey: signature)
                                project = updated
                                model.save(updated)
                            }
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sensorDisplayName(signature))
                                .font(.subheadline.weight(.semibold))
                            if let savedIntrinsics {
                                Label("User-verified intrinsics", systemImage: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.success)
                                Text(String(format: "f = %.1f px, principal point (%.1f, %.1f)", savedIntrinsics.focalLengthPx, savedIntrinsics.principalPointXPx, savedIntrinsics.principalPointYPx))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Label("Estimated from EXIF — not calibrated", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.warning)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Camera Calibration")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sensorSignatures: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for image in project.images where seen.insert(image.sensorSignature).inserted {
            result.append(image.sensorSignature)
        }
        return result
    }

    private func sensorDisplayName(_ signature: String) -> String {
        guard let image = project.images.first(where: { $0.sensorSignature == signature }) else { return signature }
        return SensorSignature(
            make: image.exifSummary.cameraMake,
            model: image.exifSummary.cameraModel,
            lensModel: image.exifSummary.lensModel,
            width: image.pixelWidth,
            height: image.pixelHeight,
            focalLengthIn35mmMM: image.exifSummary.focalLengthIn35mmMM,
            focalLengthMM: image.exifSummary.focalLengthMM
        ).sensorName
    }
}

private struct ManualIntrinsicsEditor: View {
    let signature: String
    let existing: ManualIntrinsics?
    var onSave: (ManualIntrinsics) -> Void
    var onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var focalLengthPx = ""
    @State private var principalX = ""
    @State private var principalY = ""
    @State private var radial1 = "0"
    @State private var radial2 = "0"
    @State private var radial3 = "0"
    @State private var tangential1 = "0"
    @State private var tangential2 = "0"
    @State private var pixelSize = ""
    @State private var validationMessage: String?

    var body: some View {
        Form {
            Section("Focal length") {
                labeledField("Focal length (px)", $focalLengthPx, keyboard: .decimalPad)
            }
            Section("Principal point") {
                labeledField("Principal point X (px)", $principalX, keyboard: .decimalPad)
                labeledField("Principal point Y (px)", $principalY, keyboard: .decimalPad)
            }
            Section("Radial distortion (R1, R2, R3)") {
                labeledField("R1", $radial1, keyboard: .numbersAndPunctuation)
                labeledField("R2", $radial2, keyboard: .numbersAndPunctuation)
                labeledField("R3", $radial3, keyboard: .numbersAndPunctuation)
            }
            Section("Tangential distortion (T1, T2)") {
                labeledField("T1", $tangential1, keyboard: .numbersAndPunctuation)
                labeledField("T2", $tangential2, keyboard: .numbersAndPunctuation)
            }
            Section("Sensor") {
                labeledField("Pixel size (µm)", $pixelSize, keyboard: .decimalPad)
            }
            if let validationMessage {
                Section {
                    Text(validationMessage).foregroundStyle(AppTheme.danger)
                }
            }
            Section {
                Button("Save verified intrinsics") { save() }
                    .disabled(!isComplete)
                if existing != nil {
                    Button("Clear and revert to estimate", role: .destructive) {
                        onClear()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Intrinsics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prefill)
    }

    private func labeledField(_ title: String, _ text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
        }
    }

    private var isComplete: Bool {
        !focalLengthPx.isEmpty && !principalX.isEmpty && !principalY.isEmpty && !pixelSize.isEmpty
    }

    private func prefill() {
        guard let existing else { return }
        focalLengthPx = String(existing.focalLengthPx)
        principalX = String(existing.principalPointXPx)
        principalY = String(existing.principalPointYPx)
        radial1 = String(existing.radialDistortion.first ?? 0)
        radial2 = String(existing.radialDistortion.dropFirst().first ?? 0)
        radial3 = String(existing.radialDistortion.dropFirst(2).first ?? 0)
        tangential1 = String(existing.tangentialDistortion.first ?? 0)
        tangential2 = String(existing.tangentialDistortion.dropFirst().first ?? 0)
        pixelSize = String(existing.pixelSizeMicrometres)
    }

    private func save() {
        let intrinsics = ManualIntrinsics(
            focalLengthPx: Double(focalLengthPx) ?? .nan,
            principalPointXPx: Double(principalX) ?? .nan,
            principalPointYPx: Double(principalY) ?? .nan,
            radialDistortion: [Double(radial1) ?? 0, Double(radial2) ?? 0, Double(radial3) ?? 0],
            tangentialDistortion: [Double(tangential1) ?? 0, Double(tangential2) ?? 0],
            pixelSizeMicrometres: Double(pixelSize) ?? .nan
        )
        guard intrinsics.isValid else {
            validationMessage = "Enter finite, positive values for focal length and pixel size, and numeric distortion coefficients."
            return
        }
        onSave(intrinsics)
        dismiss()
    }
}
