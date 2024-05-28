import Foundation
import Logging
import VideoToolbox
#if canImport(UIKit)
import UIKit
#endif

// MARK: - VideoDecoder

public typealias CMSampleBufferWithDate = (CMSampleBuffer, Date?)

public final class VideoDecoder {
    // MARK: Lifecycle

    public private(set) var enqueuedRemaining: Int = 0
    
    public init(config: Config) {
        self.config = config

        #if canImport(UIKit)
        willEnterForegroundTask = Task { [weak self] in
            for await _ in await NotificationCenter.default.notifications(
                named: UIApplication.willEnterForegroundNotification
            ) {
                self?.invalidate()
            }
        }
        #endif
    }

    // MARK: Public

    public var config: Config {
        didSet {
            decodingQueue.sync {
                sessionInvalidated = true
                enqueuedRemaining = config.outputBufferCount ?? 0
            }
        }
    }
    
    /// 20%
    private var fullMark: Int {
        (config.outputBufferCount ?? 0) * 2 / 10
    }
    
    /// 80%
    private var emptyMark: Int {
        (config.outputBufferCount ?? 0) * 8 / 10
    }

    public var bufferingPolicy: AsyncStream<CMSampleBufferWithDate>.Continuation.BufferingPolicy {
        if let count = config.outputBufferCount {
            .bufferingNewest(count)
        } else {
            .unbounded
        }
    }
    
    public var isBufferAlmostFull: Bool {
        enqueuedRemaining < fullMark
    }
    
    public var isBufferAlmostEmpty: Bool {
        enqueuedRemaining > emptyMark
    }
    
    public var isBufferFull: Bool {
        enqueuedRemaining == 0
    }
    
    public var isBufferEmpty: Bool {
        enqueuedRemaining == (config.outputBufferCount ?? 0)
    }
    
    public var decodedSampleBuffers: AsyncStream<CMSampleBufferWithDate> {
        .init(bufferingPolicy: bufferingPolicy) { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                self?.continuations[id] = nil
            }
        }
    }

    public func invalidate() {
        decodingQueue.sync {
            sessionInvalidated = true
            enqueuedRemaining = 0
        }
    }

    public func setFormatDescription(_ formatDescription: CMFormatDescription) {
        decodingQueue.sync {
            self.formatDescription = formatDescription
        }
    }

    public func decode(_ sampleBuffer: CMSampleBuffer, ts: Date? = nil) {
        print("ts: \(ts?.timeIntervalSince1970)")
        decodingQueue.sync {
            if decompressionSession == nil || sessionInvalidated {
                decompressionSession = createDecompressionSession()
            }

            guard let decompressionSession else {
                Self.logger.error("No decompression session")
                return
            }

            do {
                try decompressionSession.decodeFrame(
                    sampleBuffer,
                    flags: [._1xRealTimePlayback]
                ) { [weak self] status, _, imageBuffer, presentationTimeStamp, presentationDuration in
                    guard let self else { return }
                    outputQueue.sync {
                        do {
                            if let error = VideoTranscoderError(status: status) { throw error }
                            guard let imageBuffer else { return }
                            let formatDescription = try CMVideoFormatDescription(imageBuffer: imageBuffer)
                            let sampleTiming = CMSampleTimingInfo(
                                duration: presentationDuration,
                                presentationTimeStamp: presentationTimeStamp,
                                decodeTimeStamp: sampleBuffer.decodeTimeStamp
                            )
                            let sampleBuffer = try CMSampleBuffer(
                                imageBuffer: imageBuffer,
                                formatDescription: formatDescription,
                                sampleTiming: sampleTiming
                            )
                            for continuation in self.continuations.values {
                                print("ts: \(ts?.timeIntervalSince1970)")
                                let yieldResult = continuation.yield((sampleBuffer, ts))
                                switch yieldResult {
                                case .enqueued(let remaining):
                                    //print("enqueued remaining:\(remaining)")
                                    self.enqueuedRemaining = remaining
                                case .dropped(_):
                                    Self.logger.info("dropped")
                                case .terminated:
                                    Self.logger.info("terminated")
                                @unknown default:
                                    print("unknown")
                                }
                            }
                        } catch {
                            Self.logger.error("Error in decode frame output handler: \(error)")
                        }
                    }
                }
            } catch {
                Self.logger.error("Failed to decode frame with error: \(error)")
            }
        }
    }

    // MARK: Internal

    static let logger = Logger(label: "Transcoding")

    var continuations: [UUID: AsyncStream<CMSampleBufferWithDate>.Continuation] = [:]

    var willEnterForegroundTask: Task<Void, Never>?

    lazy var decodingQueue = DispatchQueue(
        label: String(describing: Self.self),
        qos: .userInitiated
    )

    lazy var outputQueue = DispatchQueue(
        label: "\(String(describing: Self.self)).output",
        qos: .userInitiated
    )

    var sessionInvalidated = false {
        didSet {
            dispatchPrecondition(condition: .onQueue(decodingQueue))
        }
    }

    var formatDescription: CMFormatDescription? {
        didSet {
            dispatchPrecondition(condition: .onQueue(decodingQueue))
            if let decompressionSession,
               let formatDescription,
               VTDecompressionSessionCanAcceptFormatDescription(
                   decompressionSession,
                   formatDescription: formatDescription
               ) {
                return
            }
            sessionInvalidated = true
        }
    }

    var decompressionSession: VTDecompressionSession? {
        didSet {
            dispatchPrecondition(condition: .onQueue(decodingQueue))
            if let oldValue { VTDecompressionSessionInvalidate(oldValue) }
            sessionInvalidated = false
        }
    }

    func createDecompressionSession() -> VTDecompressionSession? {
        dispatchPrecondition(condition: .onQueue(decodingQueue))
        do {
            guard let formatDescription else {
                Self.logger.error("Missing format description when creating decompression session")
                return nil
            }
            let session = try VTDecompressionSession.create(
                formatDescription: formatDescription,
                decoderSpecification: config.decoderSpecification,
                imageBufferAttributes: config.imageBufferAttributes
            )
            config.apply(to: session)
            return session
        } catch {
            Self.logger.error("Failed to create decompression session with error: \(error)")
            return nil
        }
    }
}
