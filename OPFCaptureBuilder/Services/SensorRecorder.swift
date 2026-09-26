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
    @Published private(set) var motionAvailable: Bool

    private let manager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let attitudeQueue = OperationQueue()

    override init() {
        authorizationStatus = manager.authorizationStatus
        motionAvailable = motionManager.isDeviceMotionAvailable
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
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 25.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: attitudeQueue) { [weak self] motion, _ in
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
        guard motionManager.isDeviceMotionActive else { return }
        motionManager.stopDeviceMotionUpdates()
    }

    func currentAttitude() -> DeviceAttitudeRecord? { latestAttitude }
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
