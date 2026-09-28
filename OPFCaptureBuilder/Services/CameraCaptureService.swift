//
//  CameraCaptureService.swift
//  OPFCaptureBuilder
//
//  Native AVFoundation capture. Produces original-resolution JPEG or HEIC data, applies
//  no filters, and guards against duplicate capture requests.
//

import Foundation
import AVFoundation
import UIKit

@MainActor
final class CameraCaptureService: NSObject, ObservableObject {

    enum CaptureError: Error, LocalizedError {
        case unauthorized
        case sessionNotConfigured
        case captureInProgress
        case noData
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Camera access has not been granted. Enable it in Settings to capture photographs."
            case .sessionNotConfigured:
                return "The capture session is not ready yet."
            case .captureInProgress:
                return "A capture is already in progress."
            case .noData:
                return "The camera returned no image data."
            case let .underlying(message):
                return message
            }
        }
    }

    enum PhotoFileType: String, CaseIterable {
        case jpeg
        case heic

        var displayName: String { self == .jpeg ? "JPEG" : "HEIC" }

        var codec: AVVideoCodecType {
            self == .jpeg ? .jpeg : .hevc
        }

        var fileExtension: String {
            self == .jpeg ? "jpg" : "heic"
        }

        var utTypeIdentifier: String {
            self == .jpeg ? "public.jpeg" : "public.heic"
        }
    }

    @Published private(set) var isAuthorized = false
    @Published private(set) var isRunning = false
    @Published private(set) var isCapturing = false
    @Published private(set) var isAutoCapturing = false
    @Published private(set) var lastErrorMessage: String?

    /// One completed automatic capture, delivered on the main actor so the caller can store
    /// the frame and the sensor readings that belong to it.
    enum AutoCaptureOutcome {
        case captured(data: Data, fileType: PhotoFileType)
        case failed(String)
    }

    /// The configured session, exposed so the preview layer can render it.
    nonisolated let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private var fileType: PhotoFileType = .jpeg
    private var completion: ((Data, PhotoFileType) -> Void)?

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isAuthorized = true
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            return granted
        default:
            isAuthorized = false
            return false
        }
    }

    // MARK: - Session

    func configure(preferredFileType: PhotoFileType) async throws {
        fileType = preferredFileType
        guard await requestAuthorization() else { throw CaptureError.unauthorized }

        if !session.inputs.isEmpty {
            await start()
            return
        }

        session.beginConfiguration()
        do {
            defer { session.commitConfiguration() }

            if session.canSetSessionPreset(.photo) {
                session.sessionPreset = .photo
            }

            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video)
            guard let device, let input = try? AVCaptureDeviceInput(device: device) else {
                throw CaptureError.underlying("No usable back camera was found on this device.")
            }
            guard session.canAddInput(input) else {
                throw CaptureError.underlying("The camera input could not be added to the session.")
            }
            session.addInput(input)

            guard session.canAddOutput(photoOutput) else {
                throw CaptureError.underlying("The photo output could not be added to the session.")
            }
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }

        await start()
    }

    func start() async {
        guard !session.isRunning else { return }
        await Task.detached { [session] in session.startRunning() }.value
        isRunning = session.isRunning
    }

    func stop() async {
        guard session.isRunning else { return }
        await Task.detached { [session] in session.stopRunning() }.value
        isRunning = false
    }

    // MARK: - Capture

    /// Requests a single original-resolution photograph. Calling this while a capture is
    /// outstanding throws instead of silently queueing a duplicate.
    func capturePhoto(wanting fileType: PhotoFileType? = nil) async throws -> (data: Data, fileType: PhotoFileType) {
        guard !isCapturing else { throw CaptureError.captureInProgress }
        guard !session.inputs.isEmpty else { throw CaptureError.sessionNotConfigured }

        isCapturing = true
        defer { isCapturing = false }

        // The codec is chosen by the user before capture; AVFoundation records the original
        // resolution and applies no pixel processing of its own beyond its standard pipeline.
        let desired = fileType ?? self.fileType

        return try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            let delegate = PhotoCaptureDelegate(fileType: desired) { result in
                continuation.resume(with: result)
            }
            self.activeDelegate = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private var activeDelegate: PhotoCaptureDelegate?

    // MARK: - Automatic (interval) capture

    #if os(iOS) && targetEnvironment(simulator)
    /// A simulator has no camera hardware, so the automatic run needs a synthesised frame for
    /// development and UI tests. This property is only compiled into a simulator build; on a
    /// real device it does not exist. The bytes it generates are a JPEG solid colour.
    var simulatorFrameProvider: ((Int) -> Data?)?
    #endif

    /// Starts capturing one photograph every `interval` seconds until `stopAutoCapture()` is
    /// called. The first frame is taken after one interval, so the button that starts the run
    /// never also takes a frame. Frames are delivered to `handler`; the task yields when the
    /// device is still busy, so the preview stays responsive and no frames are queued.
    func startAutoCapture(
        every interval: Double,
        fileType: PhotoFileType,
        handler: @escaping @MainActor (AutoCaptureOutcome) -> Void
    ) {
        stopAutoCapture()
        let seconds = CaptureInterval.clamped(interval)
        self.fileType = fileType
        isAutoCapturing = true

        autoCaptureTask = Task { [weak self] in
            var index = 0
            // Deadline-based scheduling: the cadence stays close to the chosen interval even
            // when a frame takes a moment to store, and it never bursts to catch up.
            var nextDeadline = Date().addingTimeInterval(seconds)
            while !Task.isCancelled {
                let delay = nextDeadline.timeIntervalSinceNow
                if delay > 0 {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    } catch {
                        return
                    }
                }
                nextDeadline = max(nextDeadline.addingTimeInterval(seconds),
                                   Date().addingTimeInterval(seconds))

                guard let self, !Task.isCancelled else { return }
                guard !self.isCapturing else { continue } // device still busy: skip, never queue

                #if os(iOS) && targetEnvironment(simulator)
                if let provider = self.simulatorFrameProvider {
                    if let data = provider(index) {
                        index += 1
                        self.autoCaptureCount += 1
                        handler(.captured(data: data, fileType: fileType))
                    }
                    continue
                }
                #endif

                do {
                    let result = try await self.capturePhoto(wanting: fileType)
                    guard !Task.isCancelled else { return }
                    self.autoCaptureCount += 1
                    handler(.captured(data: result.data, fileType: result.fileType))
                } catch CameraCaptureService.CaptureError.captureInProgress {
                    continue // a manual shot is in flight; skip this tick
                } catch {
                    handler(.failed(error.localizedDescription))
                }
            }
        }
    }

    /// Stops the automatic run. Safe to call when no run is active.
    func stopAutoCapture() {
        autoCaptureTask?.cancel()
        autoCaptureTask = nil
        isAutoCapturing = false
    }

    /// Number of frames the current/last automatic run produced. The capture screen resets
    /// this when a new run starts.
    @Published var autoCaptureCount = 0

    private var autoCaptureTask: Task<Void, Never>?
}

/// Bridges AVFoundation's delegate callbacks to a single async result.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let fileType: CameraCaptureService.PhotoFileType
    private let completion: (Result<(data: Data, fileType: CameraCaptureService.PhotoFileType), Error>) -> Void
    private var hasResumed = false

    init(fileType: CameraCaptureService.PhotoFileType,
         completion: @escaping (Result<(data: Data, fileType: CameraCaptureService.PhotoFileType), Error>) -> Void) {
        self.fileType = fileType
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard !hasResumed else { return }
        hasResumed = true
        if let error {
            completion(.failure(CameraCaptureService.CaptureError.underlying(error.localizedDescription)))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CameraCaptureService.CaptureError.noData))
            return
        }
        completion(.success((data, fileType)))
    }
}
