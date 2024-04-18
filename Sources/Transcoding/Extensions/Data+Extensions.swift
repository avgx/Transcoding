import Foundation

extension Data {
    func split(separator: Data) -> [Data] {
        var chunks: [Data] = []
        var position = startIndex
        while let range = self[position...].range(of: separator) {
            if range.lowerBound > position {
                chunks.append(self[position..<range.lowerBound])
            }
            position = range.upperBound
        }
        if position < endIndex {
            chunks.append(self[position..<endIndex])
        }
        return chunks
    }
}

fileprivate let hexAlphabet = Array("0123456789abcdef".unicodeScalars)

extension Data {
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
