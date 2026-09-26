//
//  CameraCaptureView.swift
//  OPFCaptureBuilder
//
//  Previews the live camera, records location + device attitude while the user composes
//  the shot, and stores original-resolution photographs. Duplicate capture requests are
//  rejected by the capture service.
//

import SwiftUI
import AVFoundation
import UIKit

struct CameraCaptureView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var project: CaptureProject
    @StateObject private var camera = CameraCaptureService()
    @Environment(\.dismiss) private var dismiss

    @State private var fileType: CameraCaptureService.PhotoFileType = .jpeg
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var lastCaptured: String?
    @State private var capturedCount = 0

    var body: some View {
        VStack(spacing: 0) {
            PreviewContainer(session: camera.session)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .overlay(alignment: .topLeading) { liveStatusOverlay }

            controls
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.sensorRecorder.requestAuthorizationIfNeeded()
            model.sensorRecorder.startLocationUpdates()
            model.sensorRecorder.startMotionUpdates()
            do {
                try await camera.configure(preferredFileType: fileType)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .onDisappear {
            model.sensorRecorder.stopEverything()
            Task { await camera.stop() }
        }
        .alert("Camera unavailable", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 16) {
            Picker("File format", selection: $fileType) {
                ForEach(CameraCaptureService.PhotoFileType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("capture.filetype")

            if let lastCaptured {
                Label("Saved \(lastCaptured)", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.success)
            }

            Button {
                Task { await capture() }
            } label: {
                ZStack {
                    Circle().fill(Color.white).frame(width: 74, height: 74)
                    Circle().strokeBorder(AppTheme.accent, lineWidth: 4).frame(width: 66, height: 66)
                    if isBusy {
                        ProgressView()
                    }
                }
            }
            .disabled(isBusy || !camera.isAuthorized)
            .accessibilityLabel("Capture photograph")
            .accessibilityIdentifier("capture.shutter")

            Text(camera.isAuthorized
                 ? "\(capturedCount) captured in this session"
                 : "Camera access is required. Enable it in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(AppTheme.groupedBackground)
    }

    private var liveStatusOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(model.sensorRecorder.latestLocation == nil ? "No location fix" : "Location available",
                  systemImage: model.sensorRecorder.latestLocation == nil ? "location.slash" : "location.fill")
            Label(model.sensorRecorder.latestAttitude == nil ? "No device attitude" : "Device attitude available",
                  systemImage: "gyroscope")
            Text("Device attitude is not camera orientation.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(8)
    }

    // MARK: - Capture

    private func capture() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let result = try await camera.capturePhoto()
            let exif = EXIFReader.read(data: result.data)
            let fileName = try model.store.storeImageData(
                result.data,
                fileName: generatedFileName(extension: result.fileType.fileExtension),
                in: project
            )

            let summary = exif?.summary ?? EXIFSummary()
            let width = exif?.pixelWidth ?? 0
            let height = exif?.pixelHeight ?? 0
            let signature = SensorSignature(
                make: summary.cameraMake ?? "Apple",
                model: summary.cameraModel ?? "iPhone Camera",
                lensModel: summary.lensModel,
                width: width,
                height: height,
                focalLengthIn35mmMM: summary.focalLengthIn35mmMM,
                focalLengthMM: summary.focalLengthMM
            ).rawValue

            let now = Date()
            let record = ImageRecord(
                fileName: fileName,
                addedAt: now,
                origin: .cameraCapture,
                pixelWidth: width,
                pixelHeight: height,
                exifOrientation: exif?.orientation ?? 1,
                captureTime: now,
                captureTimeSource: .deviceClock,
                fileByteSize: result.data.count,
                utTypeIdentifier: result.fileType.utTypeIdentifier,
                isOriginalPixelsUnmodified: true,
                geolocation: model.sensorRecorder.currentGeolocation(),
                deviceAttitude: model.sensorRecorder.currentAttitude(),
                exifSummary: summary,
                sensorSignature: signature
            )

            model.addImage(record, to: project)
            if let updated = model.store.projects.first(where: { $0.id == project.id }) {
                project = updated
            }
            capturedCount += 1
            lastCaptured = fileName
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generatedFileName(extension ext: String) -> String {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return "CAP_\(stamp)_\(String(format: "%04X", Int.random(in: 0..<0xFFFF))).\(ext)"
    }
}

/// Wraps AVCaptureVideoPreviewLayer for SwiftUI.
private struct PreviewContainer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
