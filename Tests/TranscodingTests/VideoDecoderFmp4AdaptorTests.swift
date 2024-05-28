import CoreMedia
import Logging
@testable import Transcoding
import XCTest

// MARK: - VideoDecoderFmp4AdaptorTests

func bin_data(fromFile file: String) -> Data? {
    return Bundle.module.url(forResource: file, withExtension: "bin")
        .flatMap { try? Data(contentsOf: $0) }
}

extension Data {
    /// https://stackoverflow.com/questions/32212220/how-to-split-a-string-into-substrings-of-equal-length
    public func split(by length: Int) -> [Data] {
        var startIndex = self.startIndex
        var results = [Data]()
        
        while startIndex < self.endIndex {
            let endIndex = self.index(startIndex, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
            results.append(self[startIndex..<endIndex])
            startIndex = endIndex
        }
        
        return results
    }
}

final class VideoDecoderFmp4AdaptorTests: XCTestCase {
    func test264start() async throws {
        let logger = Logger(label: "Fmp4")
        logger.info("fmp4-h264-stream-start")
        let d = bin_data(fromFile: "fmp4-h264-stream-start")!
        
        let decoder = VideoDecoder(config: .init())
        var decodedStream = decoder.decodedSampleBuffers.makeAsyncIterator()
        let decoderAdaptor = VideoDecoderFmp4Adaptor(videoDecoder: decoder, uuid: UUID(), logger: logger)
        
        let chunks = d.split(by: 256)
        
        for chunk in chunks {
            try decoderAdaptor.enqueue(data: chunk, ts: nil)
        }
        
        XCTAssert(decoder.formatDescription != nil)
    }
    
    func test265start() async throws {
        let d = bin_data(fromFile: "fmp4-h265-stream-start")!
        
        let decoder = VideoDecoder(config: .init())
        var decodedStream = decoder.decodedSampleBuffers.makeAsyncIterator()
        let decoderAdaptor = VideoDecoderFmp4Adaptor(videoDecoder: decoder, uuid: UUID())
        
        let chunks = d.split(by: 256)
        
        for chunk in chunks {
            try decoderAdaptor.enqueue(data: chunk, ts: nil)
        }
        
        XCTAssert(decoder.formatDescription != nil)
    }
    
    func testFmp4() async throws {
        let d = bin_data(fromFile: "live")!
        
        let decoder = VideoDecoder(config: .init(outputBufferCount: 100))
        var decodedStream = decoder.decodedSampleBuffers//.makeAsyncIterator()
        let decoderAdaptor = VideoDecoderFmp4Adaptor(videoDecoder: decoder, uuid: UUID(), logger: nil)
        
        let chunks = d.split(by: 256)
        var done = false
        
        Task {
            for chunk in chunks {
                let ts = Date()
                print("enqueue chunk \(ts.timeIntervalSince1970)")
                try decoderAdaptor.enqueue(data: chunk, ts: ts)
                try await Task.sleep(nanoseconds: NSEC_PER_SEC / 10)
            }
            print("done chunks")
            decoder.invalidate()
        }
        
        try await Task.sleep(nanoseconds: NSEC_PER_SEC)
        var n = 0
        XCTAssert(decoder.formatDescription != nil)
        for await (decodedSampleBuffer, ts) in decodedStream {
            n += 1
            try await Task.sleep(nanoseconds: NSEC_PER_SEC / 33)
            
            let q = decoder.enqueuedRemaining
            print("read decodedSampleBuffer enqueuedRemaining: \(q) \(ts?.timeIntervalSince1970 ?? 0)")
            XCTAssertNotNil(decodedSampleBuffer.imageBuffer)
            
            let ci = CIImage(cvImageBuffer: decodedSampleBuffer.imageBuffer!)
            let image = UIImage(ciImage: ci)
            XCTAssertEqual(image.size.width, 640)
            XCTAssertEqual(image.size.height, 360)
            if n > 10 {
                break
            }
            
        }
        print("done")
    }
}
