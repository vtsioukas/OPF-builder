//
//  SensorRecorder.swift
//  OPFCaptureBuilder
//
//  Foreground-only location and device-attitude recording. No background location is
//  requested. Absent readings stay nil: the app never invents coordinates or accuracies.
//

import Foundation
import CoreLocation
import CoreMotion

@MainActor
final class SensorRecorder: NSObject, ObservableObject {

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var latestAttitude: DeviceAttitudeRecord?
    @Published private(set) var lastLocationError: String?
    @Published private(set) var motionAvailable = false

    private let manager = CLLocationManager()
    /// Created lazily, on first use. CoreMotion has no cost when it is never touched, and
    /// this keeps the framework out of the launch path for users who never capture. It also
    /// means the (harmless but noisy) `com.apple.CoreMotion.plist` sandbox log line from
    /// Apple's framework only appears once the user actually opens the capture screen.
    private var motionManager: CMMotionManager?
    private let attitudeQueue = OperationQueue()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        // Foreground only: no `allowsBackgroundLocationUpdates`, no always-authorization.
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        attitudeQueue.qualityOfService = .userInitiated
    }

    // MARK: - Location

    func requestAuthorizationIfNeeded() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func startLocationUpdates() {
        requestAuthorizationIfNeeded()
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        manager.startUpdatingLocation()
    }

    func stopLocationUpdates() {
        manager.stopUpdatingLocation()
    }

    func stopEverything() {
        stopLocationUpdates()
        stopMotionUpdates()
    }

    /// Returns the most recent usable fix, or nil when none has been received. A fix
    /// without a valid vertical accuracy is returned with the altitude retained but the
    /// vertical sigma marked unusable by the caller.
    func currentGeolocation() -> GeolocationRecord? {
        guard let location = latestLocation else { return nil }
        let coordinate = location.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              location.altitude.isFinite else { return nil }

        return GeolocationRecord(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            // CoreLocation reports altitude relative to the WGS 84 ellipsoid, which is
            // exactly the third axis of an EPSG:4326 geographic CRS.
            ellipsoidalAltitude: location.altitude,
            horizontalAccuracy: max(location.horizontalAccuracy, 0),
            verticalAccuracy: max(location.verticalAccuracy, 0),
            timestamp: location.timestamp,
            altitudeIsEllipsoidal: true
        )
    }

    // MARK: - Motion

    func startMotionUpdates() {
        let manager = motionManagerInstance()
        guard manager.isDeviceMotionAvailable else {
            motionAvailable = false
            return
        }
        motionAvailable = true
        manager.deviceMotionUpdateInterval = 1.0 / 25.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: attitudeQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let q = motion.attitude.quaternion
            let record = DeviceAttitudeRecord(
                quaternionWXYZ: [q.w, q.x, q.y, q.z],
                pitchRadians: motion.attitude.pitch,
                rollRadians: motion.attitude.roll,
                yawRadians: motion.attitude.yaw,
                timestamp: motion.timestamp > 0 ? Date(timeIntervalSince1970: motion.timestamp) : Date()
            )
            Task { @MainActor in self.latestAttitude = record }
        }
    }

    func stopMotionUpdates() {
        guard let manager = motionManager, manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
    }

    func currentAttitude() -> DeviceAttitudeRecord? { latestAttitude }

    /// The single CoreMotion entry point. This is the only place a `CMMotionManager` is
    /// created and queried, and it is called only from the capture screen.
    private func motionManagerInstance() -> CMMotionManager {
        if let motionManager { return motionManager }
        let manager = CMMotionManager()
        motionManager = manager
        return manager
    }
}

// MARK: - CLLocationManagerDelegate

extension SensorRecorder: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
            } else {
                manager.stopUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        Task { @MainActor in
            self.latestLocation = newest
            self.lastLocationError = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastLocationError = error.localizedDescription
        }
    }
}
