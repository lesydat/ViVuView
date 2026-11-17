import Darwin
import Foundation

/// An open file read with `pread`, which needs no lock because it never moves a shared file position
/// (docs/TECH_SPEC.md §4.4). The whole file is never loaded.
public final class FileReader: Sendable {
    public let size: Int64
    private let fd: Int32

    public init(url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw DecodeError.cannotOpen }
        var st = stat()
        guard fstat(fd, &st) == 0 else { close(fd); throw DecodeError.cannotOpen }
        // Reads are mostly sequential within a band; let the kernel read ahead.
        _ = fcntl(fd, F_RDAHEAD, 1)
        self.fd = fd
        self.size = Int64(st.st_size)
    }

    deinit { close(fd) }

    /// Reads exactly `count` bytes at `offset`; throws on any short read or bad range.
    public func read(at offset: Int64, count: Int, into buffer: UnsafeMutableRawPointer) throws {
        guard offset >= 0, count >= 0 else { throw DecodeError.corrupt("offset âm") }
        guard offset <= size, Int64(count) <= size - offset else { throw DecodeError.corrupt("đọc quá cuối file") }
        var done = 0
        while done < count {
            let n = pread(fd, buffer.advanced(by: done), count - done, off_t(offset) + off_t(done))
            if n < 0 {
                if errno == EINTR { continue }
                throw DecodeError.corrupt("lỗi đọc: \(String(cString: strerror(errno)))")
            }
            if n == 0 { throw DecodeError.corrupt("file bị cắt cụt") }
            done += n
        }
    }

    public func bytes(at offset: Int64, count: Int) throws -> [UInt8] {
        var result = [UInt8](repeating: 0, count: count)
        try result.withUnsafeMutableBytes { try read(at: offset, count: count, into: $0.baseAddress!) }
        return result
    }
}

/// Big-endian / little-endian integer reading from a byte array, with bounds checks.
public struct ByteCursor {
    public let bytes: [UInt8]
    public var position: Int
    public let bigEndian: Bool

    public init(_ bytes: [UInt8], bigEndian: Bool = true, position: Int = 0) {
        self.bytes = bytes
        self.bigEndian = bigEndian
        self.position = position
    }

    public mutating func uint(_ width: Int) throws -> UInt64 {
        guard position >= 0, position + width <= bytes.count else { throw DecodeError.corrupt("thiếu dữ liệu header") }
        var value: UInt64 = 0
        for i in 0..<width {
            let byte = UInt64(bytes[position + (bigEndian ? i : width - 1 - i)])
            value = (value << 8) | byte
        }
        position += width
        return value
    }

    public mutating func u8() throws -> Int { Int(try uint(1)) }
    public mutating func u16() throws -> Int { Int(try uint(2)) }
    public mutating func u32() throws -> Int { Int(try uint(4)) }
    public mutating func u64() throws -> UInt64 { try uint(8) }
}
