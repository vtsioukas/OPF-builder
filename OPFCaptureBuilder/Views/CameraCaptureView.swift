//
//  CameraCaptureView.swift
//  OPFCaptureBuilder
//
//  Live camera preview with a single start/stop control. Tapping the button starts an
//  automatic run that keeps capturing full-resolution frames in the background at the
//  interval chosen on the project screen; tapping it again stops the run. Every frame is
//  stored together with the location fix and device attitude measured at that moment.
//
//  Location and device attitude are recorded while the screen is open (foreground only),
//  not only at shutter time, so each stored frame can carry the reading that was current
//  when it was taken. The preview never stops while capture is running.
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
    /// True until the capture session has finished configuring (authorization + inputs).
    @State private var isPreparing = true
    @State private var errorMessage: String?
    @State private var capturedCount = 0
    @State private var runStartedAt: Date?

    /// The interval is owned by the project and edited on the project screen (the menu that
    /// leads here); the capture screen only reads it.
    private var interval: Double { project.captureIntervalSeconds }

    /// Writes are serialised on this queue so a full-resolution frame never blocks the UI
    /// thread (and therefore never stutters the live preview). One write at a time keeps the
    /// image order identical to the capture order.
    private let writeQueue = DispatchQueue(label: "com.opfcapturebuilder.image-writes", qos: .userInitiated)

    var body: some View {
        VStack(spacing: 0) {
            PreviewContainer(session: camera.session)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .overlay(alignment: .topLeading) { liveStatusOverlay }
                .overlay(alignment: .bottom) { runSummaryOverlay }

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
            isPreparing = false
        }
        .onDisappear {
            stopRun()
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
            .disabled(camera.isAutoCapturing || isPreparing)
            .accessibilityIdentifier("capture.filetype")
            .onChange(of: fileType) { _, newValue in
                // Applies to the next capture; a run already in flight keeps its codec.
                Task { try? await camera.configure(preferredFileType: newValue) }
            }

            HStack(spacing: 8) {
                Image(systemName: "timer")
                Text(CaptureInterval.description(interval))
                Spacer()
                Text("Set this on the project screen.")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("capture.interval")

            Button {
                toggleRun()
            } label: {
                ZStack {
                    Circle()
                        .fill(camera.isAutoCapturing ? AppTheme.danger : Color.white)
                        .frame(width: 74, height: 74)
                    Circle()
                        .strokeBorder(AppTheme.accent, lineWidth: 4)
                        .frame(width: 66, height: 66)
                    if camera.isAutoCapturing {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white)
                            .frame(width: 26, height: 26)
                    } else if isPreparing {
                        ProgressView()
                    }
                }
            }
            .disabled(isPreparing || !camera.isAuthorized)
            .accessibilityLabel(camera.isAutoCapturing ? "Stop automatic capture" : "Start automatic capture")
            .accessibilityHint(camera.isAutoCapturing
                               ? "Stops taking photographs."
                               : "Starts taking a photograph \(CaptureInterval.description(interval)).")
            .accessibilityIdentifier("capture.shutter")

            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("capture.status")
        }
        .padding()
        .background(AppTheme.groupedBackground)
    }

    private var statusLine: String {
        guard camera.isAuthorized else {
            return "Camera access is required. Enable it in Settings."
        }
        if isPreparing {
            return "Preparing the camera…"
        }
        if camera.isAutoCapturing {
            return "Capturing \(CaptureInterval.description(interval)). Tap the button to stop."
        }
        return capturedCount == 0
            ? "Tap the button to start automatic capture."
            : "\(capturedCount) captured in this session."
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

    private var runSummaryOverlay: some View {
        Group {
            if camera.isAutoCapturing, let runStartedAt {
                TimelineView(.periodic(from: runStartedAt, by: 1)) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(runStartedAt))
                    Label(String(format: "● REC  %02d:%02d  ·  %d frames",
                                 Int(elapsed) / 60, Int(elapsed) % 60, capturedCount),
                          systemImage: "record.circle")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.red.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(.bottom, 12)
                        .accessibilityIdentifier("capture.recording")
                }
            }
        }
    }

    // MARK: - Run control

    private func toggleRun() {
        if camera.isAutoCapturing {
            stopRun()
        } else {
            startRun()
        }
    }

    private func startRun() {
        guard !isPreparing else { return }
        errorMessage = nil
        camera.autoCaptureCount = 0
        runStartedAt = Date()

        #if os(iOS) && targetEnvironment(simulator)
        // No camera hardware on the simulator: synthesise frames so the flow is still usable.
        camera.simulatorFrameProvider = { index in
            let image = SyntheticImageFactory.makeImage(width: 4032, height: 3024, seed: index + 1)
            return image.jpegData(compressionQuality: 0.9)
        }
        #endif

        camera.startAutoCapture(every: interval, fileType: fileType) { outcome in
            handle(outcome)
        }
    }

    private func stopRun() {
        camera.stopAutoCapture()
        runStartedAt = nil
    }

    // MARK: - Frame handling

    private func handle(_ outcome: CameraCaptureService.AutoCaptureOutcome) {
        switch outcome {
        case let .captured(data, resultType):
            // Read the sensors on the main actor: these are the readings that belong to this
            // frame, captured now rather than after the file write completes.
            let geo = model.sensorRecorder.currentGeolocation()
            let attitude = model.sensorRecorder.currentAttitude()
            let now = Date()
            let fileName = generatedFileName(extension: resultType.fileExtension)
            let projectID = project.id
            // Resolve everything main-actor-isolated (the images folder URL) up front, so the
            // background write touches nothing that belongs to the main actor.
            let imagesFolder = model.imagesDirectory(for: project)

            // Capture values for the background write. `self` is a SwiftUI struct and must not
            // be captured here; only the fully-resolved, plain values below cross to the queue.
            let bytes = data
            let folder = imagesFolder
            let name = fileName
            let typeIdentifier = resultType.utTypeIdentifier

            writeQueue.async {
                do {
                    try ProjectStore.writeImageData(bytes, to: folder, fileName: name)
                } catch {
                    let message = error.localizedDescription
                    Task { @MainActor in self.errorMessage = message }
                    return
                }

                let exif = EXIFReader.read(data: bytes)
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

                let record = ImageRecord(
                    fileName: name,
                    addedAt: now,
                    origin: .cameraCapture,
                    pixelWidth: width,
                    pixelHeight: height,
                    exifOrientation: exif?.orientation ?? 1,
                    captureTime: now,
                    captureTimeSource: .deviceClock,
                    fileByteSize: bytes.count,
                    utTypeIdentifier: typeIdentifier,
                    isOriginalPixelsUnmodified: true,
                    geolocation: geo,
                    deviceAttitude: attitude,
                    exifSummary: summary,
                    sensorSignature: signature
                )

                Task { @MainActor in self.commit(record, projectID: projectID) }
            }

        case let .failed(message):
            errorMessage = message
        }
    }

    @MainActor
    private func commit(_ record: ImageRecord, projectID: UUID) {
        // Never write a frame into a different project than the one being captured.
        guard project.id == projectID else { return }
        model.addImage(record, to: project)
        if let updated = model.store.projects.first(where: { $0.id == project.id }) {
            project = updated
        }
        capturedCount += 1
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
