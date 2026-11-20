import CommonCrypto
import Compression
import Foundation

/// Reads one file out of a .zip, including password-protected ones, using
/// only Apple's frameworks. Built for Clue's data download, a zip locked
/// with a password Clue shows her. Handles stored and deflated entries,
/// classic ZipCrypto, and WinZip AES (128/192/256).
enum ZipReader {
    enum Failure: Error, Equatable {
        case notZip
        case needsPassword
        case wrongPassword
        case unsupported
        case corrupt
        case notFound
    }

    struct Entry {
        let name: String
        let flags: UInt16
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let size: Int
        let localOffset: Int
        let modTime: UInt16
        let extra: Data

        var isEncrypted: Bool { flags & 1 != 0 }
    }

    static func isZip(_ data: Data) -> Bool {
        data.count >= 4 && data.u32(0) == 0x04034b50
    }

    /// Every file in the zip (folders and macOS metadata left out).
    static func entries(_ data: Data) throws -> [Entry] {
        guard isZip(data), let eocd = endOfCentralDirectory(data) else { throw Failure.notZip }
        let count = Int(data.u16(eocd + 10))
        var offset = Int(data.u32(eocd + 16))
        var entries: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= data.count, data.u32(offset) == 0x02014b50 else { throw Failure.corrupt }
            let nameLength = Int(data.u16(offset + 28))
            let extraLength = Int(data.u16(offset + 30))
            let commentLength = Int(data.u16(offset + 32))
            guard offset + 46 + nameLength + extraLength <= data.count else { throw Failure.corrupt }
            let nameData = data.subdata(in: (data.startIndex + offset + 46)..<(data.startIndex + offset + 46 + nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            let extraStart = data.startIndex + offset + 46 + nameLength
            let entry = Entry(
                name: name,
                flags: data.u16(offset + 8),
                method: data.u16(offset + 10),
                crc: data.u32(offset + 16),
                compressedSize: Int(data.u32(offset + 20)),
                size: Int(data.u32(offset + 24)),
                localOffset: Int(data.u32(offset + 42)),
                modTime: data.u16(offset + 12),
                extra: data.subdata(in: extraStart..<(extraStart + extraLength))
            )
            if !name.hasSuffix("/") && !name.hasPrefix("__MACOSX") && !(name as NSString).lastPathComponent.hasPrefix("._") {
                entries.append(entry)
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// The first file whose name matches, decrypted and unpacked.
    static func extract(from data: Data, password: String?, where matches: (String) -> Bool) throws -> Data {
        guard let entry = try entries(data).first(where: { matches(($0.name as NSString).lastPathComponent.lowercased()) }) else {
            throw Failure.notFound
        }
        return try extract(entry, from: data, password: password)
    }

    static func extract(_ entry: Entry, from data: Data, password: String?) throws -> Data {
        let local = entry.localOffset
        guard local + 30 <= data.count, data.u32(local) == 0x04034b50 else { throw Failure.corrupt }
        let start = local + 30 + Int(data.u16(local + 26)) + Int(data.u16(local + 28))
        guard start + entry.compressedSize <= data.count else { throw Failure.corrupt }
        var payload = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + entry.compressedSize))
        var method = entry.method

        if entry.isEncrypted {
            guard let password, !password.isEmpty else { throw Failure.needsPassword }
            if method == 99 {
                let (strength, actualMethod) = try aesInfo(entry.extra)
                payload = try decryptAES(payload, password: password, strength: strength)
                method = actualMethod
            } else {
                payload = try decryptZipCrypto(payload, password: password, entry: entry)
            }
        }

        switch method {
        case 0: return payload
        case 8: return try inflate(payload, size: entry.size)
        default: throw Failure.unsupported
        }
    }

    // MARK: Structure

    private static func endOfCentralDirectory(_ data: Data) -> Int? {
        let lowest = max(0, data.count - 22 - 65_535)
        var i = data.count - 22
        while i >= lowest {
            if data.u32(i) == 0x06054b50 { return i }
            i -= 1
        }
        return nil
    }

    /// WinZip AES's extra field (0x9901): key strength and the real method.
    private static func aesInfo(_ extra: Data) throws -> (strength: Int, method: UInt16) {
        var i = 0
        while i + 4 <= extra.count {
            let id = extra.u16(i), length = Int(extra.u16(i + 2))
            if id == 0x9901, length >= 7, i + 4 + length <= extra.count {
                return (Int(extra[extra.startIndex + i + 8]), extra.u16(i + 9))
            }
            i += 4 + length
        }
        throw Failure.unsupported
    }

    // MARK: WinZip AES

    private static func decryptAES(_ payload: Data, password: String, strength: Int) throws -> Data {
        let keyLength = [1: 16, 2: 24, 3: 32][strength] ?? 0
        guard keyLength > 0 else { throw Failure.unsupported }
        let saltLength = keyLength / 2
        guard payload.count >= saltLength + 2 + 10 else { throw Failure.corrupt }
        let salt = payload.prefix(saltLength)
        let verifier = payload.subdata(in: (payload.startIndex + saltLength)..<(payload.startIndex + saltLength + 2))
        let cipher = payload.subdata(in: (payload.startIndex + saltLength + 2)..<(payload.endIndex - 10))

        let derived = pbkdf2SHA1(password: password, salt: Data(salt), length: keyLength * 2 + 2)
        guard derived.suffix(2) == verifier else { throw Failure.wrongPassword }
        let key = derived.prefix(keyLength)
        return try aesCTRLittleEndian(cipher, key: Data(key))
    }

    private static func pbkdf2SHA1(password: String, salt: Data, length: Int) -> Data {
        var out = Data(count: length)
        let passwordBytes = Array(password.utf8)
        _ = out.withUnsafeMutableBytes { outBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.map { CChar(bitPattern: $0) }, passwordBytes.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1000,
                    outBytes.bindMemory(to: UInt8.self).baseAddress, length
                )
            }
        }
        return out
    }

    /// AES in counter mode with WinZip's little-endian counter, starting at 1.
    private static func aesCTRLittleEndian(_ cipher: Data, key: Data) throws -> Data {
        let blocks = (cipher.count + 15) / 16
        var counters = Data(count: blocks * 16)
        counters.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for block in 0..<blocks {
                var n = UInt64(block + 1)
                for b in 0..<8 {
                    bytes[block * 16 + b] = UInt8(n & 0xff)
                    n >>= 8
                }
            }
        }
        var stream = Data(count: counters.count)
        var moved = 0
        let status = stream.withUnsafeMutableBytes { out in
            counters.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress, key.count, nil,
                        input.baseAddress, counters.count,
                        out.baseAddress, counters.count, &moved
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw Failure.corrupt }
        var plain = Data(count: cipher.count)
        plain.withUnsafeMutableBytes { out in
            cipher.withUnsafeBytes { c in
                stream.withUnsafeBytes { s in
                    let o = out.bindMemory(to: UInt8.self), cb = c.bindMemory(to: UInt8.self), sb = s.bindMemory(to: UInt8.self)
                    for i in 0..<cipher.count { o[i] = cb[i] ^ sb[i] }
                }
            }
        }
        return plain
    }

    // MARK: ZipCrypto

    private static func decryptZipCrypto(_ payload: Data, password: String, entry: Entry) throws -> Data {
        guard payload.count >= 12 else { throw Failure.corrupt }
        var keys: (UInt32, UInt32, UInt32) = (305_419_896, 591_751_049, 878_082_192)

        func update(_ byte: UInt8) {
            keys.0 = crc32Update(keys.0, byte)
            keys.1 = (keys.1 &+ (keys.0 & 0xff)) &* 134_775_813 &+ 1
            keys.2 = crc32Update(keys.2, UInt8(truncatingIfNeeded: keys.1 >> 24))
        }
        func decryptByte() -> UInt8 {
            let temp = UInt16(truncatingIfNeeded: keys.2 | 2)
            return UInt8(truncatingIfNeeded: (UInt32(temp) &* UInt32(temp ^ 1)) >> 8)
        }

        for byte in password.utf8 { update(byte) }
        var header = [UInt8](repeating: 0, count: 12)
        for i in 0..<12 {
            let c = payload[payload.startIndex + i] ^ decryptByte()
            update(c)
            header[i] = c
        }
        // The last header byte checks the password: the CRC's top byte, or
        // the file time's when sizes come after the data.
        let check = entry.flags & 0x8 != 0 ? UInt8(entry.modTime >> 8) : UInt8(entry.crc >> 24)
        guard header[11] == check else { throw Failure.wrongPassword }

        var plain = [UInt8](repeating: 0, count: payload.count - 12)
        for i in 0..<plain.count {
            let c = payload[payload.startIndex + 12 + i] ^ decryptByte()
            update(c)
            plain[i] = c
        }
        return Data(plain)
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func crc32Update(_ crc: UInt32, _ byte: UInt8) -> UInt32 {
        crcTable[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
    }

    // MARK: Deflate

    /// Raw DEFLATE, which Apple's Compression framework calls ZLIB.
    private static func inflate(_ data: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, size,
                    src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { throw Failure.corrupt }
        return out
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }

    func u32(_ offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}
