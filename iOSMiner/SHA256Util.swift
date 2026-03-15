//
//  SHA256Util.swift
//  iOSMiner
//
//  Created by Cooper Wang on 4/3/2026.
//

import Foundation
import CryptoKit

// MARK: - Hex Conversion

nonisolated enum HexUtil {
    /// Convert hex string to Data. Returns nil for invalid hex.
    static func data(from hex: String) -> Data? {
        let len = hex.count
        guard len % 2 == 0 else { return nil }
        var data = Data(capacity: len / 2)
        var index = hex.startIndex
        for _ in 0..<len / 2 {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }

    /// Convert Data to lowercase hex string.
    static func hex(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Convert a UInt32 to 4-byte little-endian hex string.
    static func hexLE(_ value: UInt32) -> String {
        var le = value.littleEndian
        let data = Data(bytes: &le, count: 4)
        return hex(from: data)
    }

    /// Reverse byte order of a hex string (swap endianness).
    static func reverseHex(_ hex: String) -> String? {
        guard let data = self.data(from: hex) else { return nil }
        return self.hex(from: Data(data.reversed()))
    }
}

// MARK: - SHA-256d (double SHA-256)

nonisolated enum SHA256d {
    /// Double SHA-256 hash of raw data.
    static func hash(_ data: Data) -> Data {
        let first = SHA256.hash(data: data)
        let second = SHA256.hash(data: Data(first))
        return Data(second)
    }
}

// MARK: - Difficulty / Target Helpers

nonisolated enum DifficultyUtil {
    /// Compute the 32-byte target from pool difficulty.
    /// target = diff1Target / difficulty
    ///
    /// diff1Target (pdiff) = 0x00000000FFFF0000...0000 (32 bytes)
    /// This is equivalent to 0xFFFF << 208.
    ///
    /// We use 256-bit integer division to avoid floating-point precision loss.
    static func targetBytes(for difficulty: Double) -> Data {
        guard difficulty > 0 else {
            return Data(repeating: 0xFF, count: 32)
        }

        // diff1Target as 32-byte big-endian
        var diff1 = [UInt8](repeating: 0, count: 32)
        diff1[4] = 0xFF
        diff1[5] = 0xFF

        // For pool difficulties, we compute: target = diff1 / difficulty
        // To handle this with integer precision, we multiply diff1 by a large factor,
        // divide by difficulty (as integer), then shift back.
        //
        // But simpler approach that works for all practical pool difficulties:
        // Express difficulty as numerator/denominator to maintain precision.
        //
        // For the common case where difficulty is a power-of-2 or simple fraction,
        // this approach works well:

        if difficulty >= 1.0 {
            // target = diff1 / difficulty
            // Do 256-bit division: diff1 / difficulty
            return divideTarget(diff1, by: difficulty)
        } else {
            // difficulty < 1 means target > diff1
            // target = diff1 * (1/difficulty)
            // Multiply diff1 by the multiplier
            let multiplier = 1.0 / difficulty
            return multiplyTarget(diff1, by: multiplier)
        }
    }

    /// Divide a 256-bit big-endian number by a double, returning 32 bytes.
    private static func divideTarget(_ target: [UInt8], by divisor: Double) -> Data {
        // Convert target to a Double (loses precision for huge numbers, but
        // for diff1 = 0xFFFF << 208 this is fine since it's a clean value).
        // Then divide and convert back.
        //
        // Better approach: long division byte by byte.
        var result = [UInt8](repeating: 0, count: 32)
        var remainder: Double = 0

        for i in 0..<32 {
            remainder = remainder * 256.0 + Double(target[i])
            let quotient = floor(remainder / divisor)
            result[i] = UInt8(min(255, max(0, quotient)))
            remainder -= quotient * divisor
        }

        return Data(result)
    }

    /// Multiply a 256-bit big-endian number by a double, returning 32 bytes.
    private static func multiplyTarget(_ target: [UInt8], by multiplier: Double) -> Data {
        // Multiply from least significant byte, carrying overflow
        var result = [UInt64](repeating: 0, count: 32)

        for i in (0..<32).reversed() {
            let product = Double(target[i]) * multiplier
            result[i] += UInt64(product)
        }

        // Propagate carries from right to left
        for i in (1..<32).reversed() {
            result[i - 1] += result[i] / 256
            result[i] = result[i] % 256
        }
        // Clamp to 256 bits
        result[0] = min(result[0], 255)

        var bytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 {
            bytes[i] = UInt8(min(255, result[i]))
        }
        return Data(bytes)
    }

    /// Check if a hash (32 bytes, natural byte order as produced by SHA256d)
    /// meets the target. Both are compared as big-endian 256-bit integers.
    /// The hash from SHA256d is in little-endian (least significant byte first),
    /// so we reverse it for comparison.
    static func hashMeetsTarget(hash: Data, target: Data) -> Bool {
        // hash is in internal byte order (little-endian for Bitcoin).
        // Reverse it to big-endian for comparison.
        let hashBE = Data(hash.reversed())
        // Compare byte-by-byte, big-endian (most significant first).
        for i in 0..<32 {
            if hashBE[i] < target[i] { return true }
            if hashBE[i] > target[i] { return false }
        }
        return true // equal
    }

    /// Debug: return hex representation of a target
    static func targetHex(for difficulty: Double) -> String {
        HexUtil.hex(from: targetBytes(for: difficulty))
    }
}
