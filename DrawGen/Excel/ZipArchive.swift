import Compression
import Foundation

/// 极简 ZIP 读写，仅覆盖 .xlsx 所需的部分（store / deflate，无加密、无 ZIP64）。
enum ZipArchive {
    struct Entry {
        var path: String
        var data: Data
    }

    enum Failure: LocalizedError {
        case notAZip
        case corrupted
        case unsupportedMethod(UInt16)
        case inflateFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAZip: "文件不是有效的 xlsx（ZIP）格式。"
            case .corrupted: "xlsx 文件已损坏。"
            case .unsupportedMethod(let method): "不支持的压缩方式（\(method)）。"
            case .inflateFailed(let path): "无法解压 \(path)。"
            }
        }
    }

    // MARK: Reading

    static func read(_ data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard let eocd = findEndOfCentralDirectory(bytes) else { throw Failure.notAZip }

        let entryCount = Int(try bytes.u16(eocd + 10))
        var cursor = Int(try bytes.u32(eocd + 16))
        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)

        for _ in 0..<entryCount {
            guard try bytes.u32(cursor) == 0x0201_4B50 else { throw Failure.corrupted }
            let method = try bytes.u16(cursor + 10)
            let compressedSize = Int(try bytes.u32(cursor + 20))
            let uncompressedSize = Int(try bytes.u32(cursor + 24))
            let nameLength = Int(try bytes.u16(cursor + 28))
            let extraLength = Int(try bytes.u16(cursor + 30))
            let commentLength = Int(try bytes.u16(cursor + 32))
            let localOffset = Int(try bytes.u32(cursor + 42))
            let nameBytes = try bytes.slice(cursor + 46, nameLength)
            let path = String(decoding: nameBytes, as: UTF8.self)

            guard try bytes.u32(localOffset) == 0x0403_4B50 else { throw Failure.corrupted }
            let localNameLength = Int(try bytes.u16(localOffset + 26))
            let localExtraLength = Int(try bytes.u16(localOffset + 28))
            let dataStart = localOffset + 30 + localNameLength + localExtraLength
            let payload = try bytes.slice(dataStart, compressedSize)

            let content: Data
            switch method {
            case 0: content = Data(payload)
            case 8: content = try inflate(payload, expectedSize: uncompressedSize, path: path)
            default: throw Failure.unsupportedMethod(method)
            }

            entries.append(Entry(path: path, data: content))
            cursor += 46 + nameLength + extraLength + commentLength
        }

        return entries
    }

    private static func findEndOfCentralDirectory(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let lowerBound = max(0, bytes.count - 22 - 0xFFFF)
        var index = bytes.count - 22
        while index >= lowerBound {
            if bytes[index] == 0x50, bytes[index + 1] == 0x4B, bytes[index + 2] == 0x05, bytes[index + 3] == 0x06 {
                return index
            }
            index -= 1
        }
        return nil
    }

    private static func inflate(_ source: ArraySlice<UInt8>, expectedSize: Int, path: String) throws -> Data {
        if expectedSize == 0 { return Data() }
        let input = Array(source)
        guard !input.isEmpty else { throw Failure.inflateFailed(path) }

        var output = [UInt8](repeating: 0, count: expectedSize)
        let written = input.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                // COMPRESSION_ZLIB 在 Apple 平台上即原始 DEFLATE（RFC 1951），与 ZIP 一致。
                compression_decode_buffer(dst.baseAddress!, expectedSize, src.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw Failure.inflateFailed(path) }
        return Data(output)
    }

    // MARK: Writing

    static func write(_ entries: [Entry]) -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let raw = [UInt8](entry.data)
            let crc = CRC32.checksum(raw)
            let deflated = deflate(raw)
            let method: UInt16 = deflated == nil ? 0 : 8
            let payload = deflated ?? raw
            let name = [UInt8](entry.path.utf8)
            let offset = UInt32(archive.count)

            // Local file header
            archive.append(le32: 0x0403_4B50)
            archive.append(le16: 20)          // version needed
            archive.append(le16: 0x0800)      // UTF-8 文件名
            archive.append(le16: method)
            archive.append(le16: 0)           // mod time
            archive.append(le16: 0x0021)      // mod date: 1980-01-01
            archive.append(le32: crc)
            archive.append(le32: UInt32(payload.count))
            archive.append(le32: UInt32(raw.count))
            archive.append(le16: UInt16(name.count))
            archive.append(le16: 0)           // extra length
            archive.append(contentsOf: name)
            archive.append(contentsOf: payload)

            // Central directory header
            centralDirectory.append(le32: 0x0201_4B50)
            centralDirectory.append(le16: 20) // version made by
            centralDirectory.append(le16: 20) // version needed
            centralDirectory.append(le16: 0x0800)
            centralDirectory.append(le16: method)
            centralDirectory.append(le16: 0)
            centralDirectory.append(le16: 0x0021)
            centralDirectory.append(le32: crc)
            centralDirectory.append(le32: UInt32(payload.count))
            centralDirectory.append(le32: UInt32(raw.count))
            centralDirectory.append(le16: UInt16(name.count))
            centralDirectory.append(le16: 0)  // extra
            centralDirectory.append(le16: 0)  // comment
            centralDirectory.append(le16: 0)  // disk number
            centralDirectory.append(le16: 0)  // internal attrs
            centralDirectory.append(le32: 0)  // external attrs
            centralDirectory.append(le32: offset)
            centralDirectory.append(contentsOf: name)
        }

        let centralOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        // End of central directory
        archive.append(le32: 0x0605_4B50)
        archive.append(le16: 0)
        archive.append(le16: 0)
        archive.append(le16: UInt16(entries.count))
        archive.append(le16: UInt16(entries.count))
        archive.append(le32: UInt32(centralDirectory.count))
        archive.append(le32: centralOffset)
        archive.append(le16: 0)

        return archive
    }

    /// 返回 nil 表示压缩无收益或失败，此时按 store 方式写入。
    private static func deflate(_ input: [UInt8]) -> [UInt8]? {
        guard input.count > 64 else { return nil }
        var output = [UInt8](repeating: 0, count: input.count)
        let written = input.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                compression_encode_buffer(dst.baseAddress!, input.count, src.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written < input.count else { return nil }
        return Array(output[0..<written])
    }
}

// MARK: - Helpers

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Array where Element == UInt8 {
    func u16(_ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw ZipArchive.Failure.corrupted }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func u32(_ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw ZipArchive.Failure.corrupted }
        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }

    func slice(_ offset: Int, _ length: Int) throws -> ArraySlice<UInt8> {
        guard offset >= 0, length >= 0, offset + length <= count else { throw ZipArchive.Failure.corrupted }
        return self[offset..<(offset + length)]
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func append(le32 value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ])
    }
}
