//
//  ZipArchiveWriter.swift
//  OPFCaptureBuilder
//
//  A minimal, deterministic ZIP writer (store + deflate). It writes central-directory
//  metadata correctly so the archive opens in Finder, Files, iZip, PIX4Dmatic and any
//  standard unarchiver. CRC-32 uses the standard IEEE polynomial.
//

import Foundation
import Compression

enum ZipArchiveWriterError: Error, LocalizedError {
    case compressionFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case let .compressionFailed(name): return "Could not compress \"\(name)\" while building the archive."
        case let .writeFailed(name): return "Could not write \"\(name)\" into the archive."
        }
    }
}

struct ZipEntry {
    var name: String
    var data: Data
    var useDeflate: Bool

    init(path: String, data: Data, useDeflate: Bool = true) {
        self.name = path
        self.data = data
        self.useDeflate = useDeflate
    }
}

enum ZipArchiveWriter {

    /// Builds a ZIP archive from the given entries, in order.
    static func archive(entries: [ZipEntry]) throws -> Data {
        var output = Data()
        var centralDirectory = Data()

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let uncompressedSize = UInt32(entry.data.count)

            var payload = entry.data
            var method: UInt16 = 0 // store
            if entry.useDeflate, entry.data.count > 0 {
                if let compressed = deflate(entry.data), compressed.count < entry.data.count {
                    payload = compressed
                    method = 8
                }
            }
            let compressedSize = UInt32(payload.count)

            let localHeaderOffset = UInt32(output.count)

            // Local file header
            output.appendUInt32LE(0x04034b50)
            output.appendUInt16LE(20)            // version needed
            output.appendUInt16LE(0x0800)        // UTF-8 name flag
            output.appendUInt16LE(method)
            output.appendUInt16LE(0)             // mod time
            output.appendUInt16LE(0)             // mod date
            output.appendUInt32LE(crc)
            output.appendUInt32LE(compressedSize)
            output.appendUInt32LE(uncompressedSize)
            output.appendUInt16LE(UInt16(nameData.count))
            output.appendUInt16LE(0)             // extra length
            output.append(nameData)
            output.append(payload)

            // Central directory record
            centralDirectory.appendUInt32LE(0x02014b50)
            centralDirectory.appendUInt16LE(20)  // version made by
            centralDirectory.appendUInt16LE(20)  // version needed
            centralDirectory.appendUInt16LE(0x0800)
            centralDirectory.appendUInt16LE(method)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(crc)
            centralDirectory.appendUInt32LE(compressedSize)
            centralDirectory.appendUInt32LE(uncompressedSize)
            centralDirectory.appendUInt16LE(UInt16(nameData.count))
            centralDirectory.appendUInt16LE(0)   // extra
            centralDirectory.appendUInt16LE(0)   // comment
            centralDirectory.appendUInt16LE(0)   // disk number
            centralDirectory.appendUInt16LE(0)   // internal attributes
            centralDirectory.appendUInt32LE(0)   // external attributes
            centralDirectory.appendUInt32LE(localHeaderOffset)
            centralDirectory.append(nameData)
        }

        let centralDirectoryOffset = UInt32(output.count)
        output.append(centralDirectory)
        let centralDirectorySize = UInt32(centralDirectory.count)

        // End of central directory
        output.appendUInt32LE(0x06054b50)
        output.appendUInt16LE(0)
        output.appendUInt16LE(0)
        output.appendUInt16LE(UInt16(entries.count))
        output.appendUInt16LE(UInt16(entries.count))
        output.appendUInt32LE(centralDirectorySize)
        output.appendUInt32LE(centralDirectoryOffset)
        output.appendUInt16LE(0)

        return output
    }

    // MARK: - Compression

    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let destinationCapacity = max(data.count + data.count / 2 + 64, 256)
        var destination = Data(count: destinationCapacity)
        let written: Int? = destination.withUnsafeMutableBytes { destinationBuffer in
            guard let destinationPointer = destinationBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
            return data.withUnsafeBytes { sourceBuffer -> Int? in
                guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
                let result = compression_encode_buffer(
                    destinationPointer, destinationCapacity,
                    sourcePointer, data.count,
                    nil, COMPRESSION_ZLIB
                )
                return result == 0 ? nil : result
            }
        }
        guard let written, written > 0 else { return nil }
        return destination.prefix(written)
    }

    // MARK: - CRC-32

    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            table[index] = value
        }
        return table
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
