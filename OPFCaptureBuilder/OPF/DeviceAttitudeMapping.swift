//
//  DeviceAttitudeMapping.swift
//  OPFCaptureBuilder
//
//  Converts a CoreMotion device attitude into the Yaw-Pitch-Roll convention used by
//  OPF `input_cameras` captures:
//
//      R = Rz(yaw) · Ry(pitch) · Rx(roll)
//
//  from the **image coordinate system to the navigation CRS**, where the image CS is
//  right-top-back and the navigation CRS is East-North-Down.
//
//  IMPORTANT DISTINCTION
//  ---------------------
//  CoreMotion attitude describes how the *device* is oriented. It is not the same as
//  the photogrammetric camera orientation, which the app does not know and must not
//  invent. This type therefore:
//    * always preserves the raw quaternion,
//    * derives YPR only as a documented estimate inside the given attitude reference
//      frame, and
//    * exposes the calibration matrix so the user can tell us how the camera is
//      mounted relative to the device, instead of us guessing.
//

import Foundation
import simd

enum DeviceAttitudeMapping {

    /// Rotation taking device axes to the image coordinate system.
    ///
    /// The default is the identity, which is the honest "we do not know the mounting"
    /// case: `OPFCaptureBuilder` records the raw quaternion and labels the derived YPR
    /// estimate as such. A rear camera looking along the device -Z axis with the image
    /// x-axis along +X and image y-axis along +Y gives this matrix.
    static let defaultCameraToDevice = matrix_identity_double4x4

    /// Decomposes a `simd_quatd` (device attitude) into Z-Y-X Euler angles in the
    /// attitude reference frame, in radians.
    ///
    /// The result satisfies `Rz(yaw) * Ry(pitch) * Rx(roll)` being equal to the rotation
    /// matrix of `q`, i.e. intrinsic yaw → pitch → roll.
    static func eulerZYX(from q: simd_quatd) -> (yaw: Double, pitch: Double, roll: Double) {
        let rotation = simd_double3x3(q)
        // Elements of R = Rz(yaw) Ry(pitch) Rx(roll):
        //   r20 = -sin(pitch)
        //   r21 =  cos(pitch) sin(roll)
        //   r22 =  cos(pitch) cos(roll)
        //   r10 =  cos(pitch) sin(yaw)
        //   r00 =  cos(pitch) cos(yaw)
        let r00 = rotation[0][0]
        let r10 = rotation[1][0]
        let r20 = rotation[2][0]
        let r21 = rotation[2][1]
        let r22 = rotation[2][2]

        let sinPitch = min(max(-r20, -1.0), 1.0)
        let pitch = asin(sinPitch)
        let cosPitch = (pitch * pitch) < 1e-12 ? 0.0 : cos(pitch)

        let yaw: Double
        let roll: Double
        if abs(cosPitch) < 1e-9 {
            // Gimbal lock: fall back to a single-axis solution.
            yaw = atan2(-rotation[0][1], rotation[1][1])
            roll = 0
        } else {
            yaw = atan2(r10, r00)
            roll = atan2(r21, r22)
        }
        return (yaw, pitch, roll)
    }

    /// YPR in degrees for the OPF `orientation` object, computed from the raw quaternion
    /// with the (configurable) camera-to-device mounting matrix applied.
    static func yawPitchRollDegrees(
        quaternionWXYZ: [Double],
        cameraToDevice: simd_double4x4 = defaultCameraToDevice
    ) -> (yaw: Double, pitch: Double, roll: Double)? {
        guard quaternionWXYZ.count == 4 else { return nil }
        let raw = simd_quatd(
            ix: quaternionWXYZ[1],
            iy: quaternionWXYZ[2],
            iz: quaternionWXYZ[3],
            r: quaternionWXYZ[0]
        )
        guard raw.vector.x.isFinite, raw.vector.y.isFinite,
              raw.vector.z.isFinite, raw.vector.w.isFinite else { return nil }
        let normalized = simd_normalize(raw)
        let mounted = simd_double3x3(cameraToDevice) * simd_double3x3(normalized)
        let euler = eulerZYX(from: simd_quatd(mounted))
        return (degrees(euler.yaw), degrees(euler.pitch), degrees(euler.roll))
    }

    private static func degrees(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }
}
