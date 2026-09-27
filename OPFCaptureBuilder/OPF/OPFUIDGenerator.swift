//
//  OPFUIDGenerator.swift
//  OPFCaptureBuilder
//
//  One UID strategy for the whole project.
//
//  The OPF specification requires every camera_list in a project to declare the
//  same `uid_generator`, and discourages sequential UIDs. We therefore use a
//  deterministic content hash so that the same photograph yields the same camera UID
//  across re-exports. IDs are limited to signed Int32 for broad consumer compatibility.
//
//  `FNV1a64` is a public-domain algorithm; the same routine produces camera,
//  sensor and capture identifiers so importer and OPF writer can never diverge.
//

import Foundation

enum OPFUID {
    /// Identifier of the generator, written verbatim into every `camera_list`.
    static let vendor = "opfcapturebuilder"
    static let name = "fnv1a64_int32_image_content"
    static let version = 1
    /// UIDs are guaranteed unique within an exported project.
    static let scope = "project"

    /// Signed Int32 IDs are a valid subset of the OPF `uid64` range.
    static let usableBits: UInt64 = 0x0000_0000_7FFF_FFFF

    static func identifyCamera(rawImageBytesAt url: URL) throws -> UInt64 {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return cameraID(forImageBytes: data)
    }

    static func cameraID(forImageBytes bytes: Data) -> UInt64 {
        FNV1a64.hash(bytes) & usableBits
    }

    /// Sensor identity is derived from physical characteristics only, so two captures
    /// from the same physical camera share one sensor.
    static func sensorID(signature: String) -> UInt64 {
        FNV1a64.hash(Data(signature.utf8)) & usableBits
    }

    /// A capture groups the cameras fired at the same instant.
    static func captureID(cameraID: UInt64, iso8601Time: String) -> UInt64 {
        var bytes = Data()
        withUnsafeBytes(of: cameraID.littleEndian) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: Data(iso8601Time.utf8))
        return FNV1a64.hash(bytes) & usableBits
    }
}

/// FNV-1a 64-bit hashing (streaming, constant memory).
enum FNV1a64 {
    static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    static let prime: UInt64 = 0x0000_0100_0000_01b3

    static func hash(_ data: Data) -> UInt64 {
        var value = offsetBasis
        for byte in data {
            value ^= UInt64(byte)
            value = value &* prime
        }
        return value
    }

    static func hash(_ string: String) -> UInt64 {
        hash(Data(string.utf8))
    }

    /// Streaming variant for large files that should not be read into memory at once.
    static func hash(contentsOf url: URL, chunkSize: Int = 1 << 20) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var value = offsetBasis
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            for byte in chunk {
                value ^= UInt64(byte)
                value = value &* prime
            }
        }
        return value
    }
}
