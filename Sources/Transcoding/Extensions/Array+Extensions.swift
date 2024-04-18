import Foundation

/// https://github.com/futo-org/circles-ios/blob/main/Circles/Utilities/Array%2BExtension.swift
/// // The following extensions were extracted from https://github.com/krzyzanowskim/CryptoSwift/blob/main/Sources/CryptoSwift/Array%2BExtension.swift

extension Array {
    @inlinable
    init(reserveCapacity: Int) {
        self = Array<Element>()
        self.reserveCapacity(reserveCapacity)
    }
    
    @inlinable
    var slice: ArraySlice<Element> {
        self[self.startIndex ..< self.endIndex]
    }
    
    @inlinable
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element == UInt8 {
    public init(hex: String) {
        self.init(reserveCapacity: hex.unicodeScalars.lazy.underestimatedCount)
        var buffer: UInt8?
        var skip = 0
        
        for char in hex.unicodeScalars.lazy {
            guard skip == 0 else {
                skip -= 1
                continue
            }
            guard char.value >= 48 && char.value <= 102 else {
                removeAll()
                return
            }
            let v: UInt8
            let c: UInt8 = UInt8(char.value)
            switch c {
            case let c where c <= 57:
                v = c - 48
            case let c where c >= 65 && c <= 70:
                v = c - 55
            case let c where c >= 97:
                v = c - 87
            default:
                removeAll()
                return
            }
            if let b = buffer {
                append(b << 4 | v)
                buffer = nil
            } else {
                buffer = v
            }
        }
        if let b = buffer {
            append(b)
        }
    }
}

fileprivate let hexAlphabet = Array("0123456789abcdef".unicodeScalars)

extension Array where Element == UInt8 {
    func hex(spacing: Bool = false) -> String {
        String(reduce(into: "".unicodeScalars) { result, value in
            result.append(hexAlphabet[Int(value / 0x10)])
            result.append(hexAlphabet[Int(value % 0x10)])
            if spacing {
                result.append(" ")
            }
        })
    }
}

extension Array where Element == UInt8 {
    var uint64Value: UInt64 {
        return UInt64(bigEndian: Data(bytes: self).withUnsafeBytes { $0.pointee })
    }
    var uint32Value: UInt32 {
        return UInt32(bigEndian: Data(bytes: self).withUnsafeBytes { $0.pointee })
    }
    var uint16Value: UInt16 {
        return UInt16(bigEndian: Data(bytes: self).withUnsafeBytes { $0.pointee })
    }
    
    public var ascii: String? {
        return String(data: Data(bytes: self), encoding: .ascii)
    }
}
