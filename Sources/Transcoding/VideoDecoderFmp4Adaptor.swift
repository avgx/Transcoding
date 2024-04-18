import Foundation
import CoreMedia
import OSLog

public class VideoDecoderFmp4Adaptor {
    
    var trackID: Int?
    var sequenceNumber: Int?
    
    var is264: Bool {
        sps != nil && pps != nil && vps == nil
    }
    var is265: Bool {
        sps != nil && pps != nil && vps != nil
    }
    
    var sps: [UInt8]?
    var pps: [UInt8]?
    var vps: [UInt8]?
    
    var width: Int?
    var height: Int?
    
    var buffer: Data = Data(capacity: 1000_000)
    
    let videoDecoder: VideoDecoder
    var formatDescription: CMVideoFormatDescription?
    
    static let logger = Logger(subsystem: "Transcoding", category: "VideoDecoderFmp4Adaptor")
    
    public init(videoDecoder: VideoDecoder) {
        self.videoDecoder = videoDecoder
    }
    
    public func enqueue(data: Data) throws {
        buffer.append(data)
        if buffer.count > 1_000_000 {
            Self.logger.warning("buffer size \(self.buffer.count)")
        }
        var consumed = 0
        while(buffer.count > 0) {
            try buffer.withUnsafeBytes {
                consumed = try parse(pointer: $0, count: buffer.count, parent: "")
            }
            if consumed == 0 {
                break
            }
            buffer = buffer.dropFirst(consumed)
        }
    }
    
    func decodeAVCCFrame(_ data: Data) {
        
        guard let formatDescription else {
            //Self.logger.warning("No format description; need sync frame")
            return
        }
        var data = data
        data.withUnsafeMutableBytes { pointer in
            do {
                let dataBuffer = try CMBlockBuffer(buffer: pointer, allocator: kCFAllocatorNull)
                let sampleBuffer = try CMSampleBuffer(
                    dataBuffer: dataBuffer,
                    formatDescription: formatDescription,
                    numSamples: 1,
                    sampleTimings: [],
                    sampleSizes: []
                )
                
                videoDecoder.decode(sampleBuffer)
                
            } catch {
                Self.logger.error("Failed to create sample buffer with error: \(error, privacy: .public)")
            }
        }
    }
    
    static let UInt32Size = MemoryLayout<UInt32>.size
    /// return consumed bytes
    /// docs about: https://swiftdoc.org/v5.1/type/unsaferawbufferpointer/
    private func parse(pointer: UnsafeRawBufferPointer, count: Int, parent: String) throws -> Int {
        guard count >= 8 else {
            //not enouph data to get size and type
            return 0
        }
        
        let size: [UInt8] = Array(pointer[0..<4])
        let type: [UInt8] = Array(pointer[4..<8])
        let size32 = size.withUnsafeBytes({ $0.load(as: UInt32.self) })
        let boxSize = Int(UInt32(bigEndian: size32 ))
        guard let typeAscii = String(data: Data(type), encoding: .ascii) else {
            throw Mp4ParseError.typeNotAscii
        }
        
        if parent.isEmpty && !["moof", "mdat", "ftyp", "moov"].contains(typeAscii) {
            throw Mp4ParseError.unexpectedAtom
        }
        
        //atom
        guard boxSize <= 10_000_000 else {
            //empty box??
            throw Mp4ParseError.veryLargeFrame
        }
        guard boxSize >= 0 else {
            //empty box??
            return 0
        }
        guard count >= boxSize else {     // + 8 непонятно
            //not enouph data to get atom
            return 0
        }
        
        let slice = pointer[8..<boxSize]
        precondition(slice.count == boxSize - 8)
        let sliceCount = boxSize - 8
        let rebased = UnsafeRawBufferPointer(rebasing: slice)
        Self.logger.debug("\(parent)/\(typeAscii)(\(boxSize))")
        //TODO: consume atom with inner structure from array `rebased`
        //consume boxSize bytes
        try consumeBox(pointer: rebased, count: sliceCount, parent: parent, atom: typeAscii)
        
        return boxSize
    }
    
    /// we sure that box is complete in inner
    private func parseInner(pointer: UnsafeRawBufferPointer, count: Int, atom: String) throws -> Int {
        var consumed = 0
        while consumed < count {
            let slice = pointer[consumed...]
            let sliceCount = count - consumed
            let rebased = UnsafeRawBufferPointer(rebasing: slice)
            let done = try parse(pointer: rebased, count: sliceCount, parent: atom)
            if done == 0 {
                break
            }
            consumed += done
        }
        return consumed
    }
    
    private func consumeBox(pointer: UnsafeRawBufferPointer, count: Int, parent: String, atom: String) throws {
        //here we get a complete loaded atom.
        switch atom {
            
            // top level atoms
        case "ftyp":
            Self.logger.debug("ftyp \(count) bytes")
            Self.logger.debug("ftyp \(Array(pointer).hex())")
        case "moov":
            Self.logger.debug("moov \(count) bytes")
            Self.logger.debug("moov \(Array(pointer).hex())")
            _ = try parseInner(pointer: pointer, count: count, atom: atom)
        case "moof":
            Self.logger.debug("moof \(count) bytes")
            _ = try parseInner(pointer: pointer, count: count, atom: atom)
        case "mdat":
            Self.logger.debug("mdat \(count) bytes")
            consumeBox_mdat(pointer: pointer, count: count)
            // known usefull atoms
        case "avc1":
            // /moov/trak/mdia/minf/stbl/stsd/avc1
            let xwidth: UInt16 = UInt16(pointer[24]) << 8 | UInt16(pointer[25])
            let xheight: UInt16 = UInt16(pointer[26]) << 8 | UInt16(pointer[27])
            self.width = Int(xwidth)
            self.height = Int(xheight)
            Self.logger.debug("\(xwidth)x\(xheight)")
            //78 is offset from avc1 atom start code (from size)
            let offset = 78 - 8
            let slice = pointer[(8+offset)...]
            let sliceCount = count - (8+offset)
            let rebased = UnsafeRawBufferPointer(rebasing: slice)
            //avc1 / hvc1
            _ = try parse(pointer: rebased, count: sliceCount, parent: "\(parent)/\(atom)")
        case "hvc1", "hev1":
            let xwidth: UInt16 = UInt16(pointer[24]) << 8 | UInt16(pointer[25])
            let xheight: UInt16 = UInt16(pointer[26]) << 8 | UInt16(pointer[27])
            self.width = Int(xwidth)
            self.height = Int(xheight)
            Self.logger.debug("\(xwidth)x\(xheight)")
            
            let offset = 78 - 8
            let slice = pointer[(8+offset)...]
            let sliceCount = count - (8+offset)
            let rebased = UnsafeRawBufferPointer(rebasing: slice)
            //avc1 / hvc1
            _ = try parse(pointer: rebased, count: sliceCount, parent: "\(parent)/\(atom)")
        case "avcC":
            Self.logger.debug("avcC \(Array(pointer).hex())")
            let x = try Atom_avcC(data: Array(pointer))
            self.sps = x.sps
            self.pps = x.pps
            let formatDescription = try x.formatDescription()
            self.videoDecoder.setFormatDescription(formatDescription)
            self.formatDescription = formatDescription
        case "hvcC":
            Self.logger.debug("hvcC \(Array(pointer).hex())")
            let x = dump_hvcC(data: Array(pointer))
            self.sps = x.sps
            self.pps = x.pps
            self.vps = x.vps
            let formatDescription = try CMVideoFormatDescription(hevcParameterSets: [Data(x.vps), Data(x.sps), Data(x.pps)])
            self.videoDecoder.setFormatDescription(formatDescription)
            self.formatDescription = formatDescription
        case "tfhd":
            consumeBox_tfhd(pointer: pointer, count: count)
        case "mfhd":
            consumeBox_mfhd(pointer: pointer, count: count)
            
            // inner box with inner atoms
        case "trak", "mdia", "minf", "stbl", "traf":
            _ = try parseInner(pointer: pointer, count: count, atom: "\(parent)/\(atom)")
            
        case "stsd":
            //let x = Atom_stsd(data: Array(pointer))
            let slice = pointer[8...]
            let sliceCount = count - 8
            let rebased = UnsafeRawBufferPointer(rebasing: slice)
            //avc1 / hvc1
            _ = try parse(pointer: rebased, count: sliceCount, parent: "\(parent)/\(atom)")
            // just box without inner. contains content, not size+atom+data
            //case "stsd", "dinf", "vmhd", "hdlr", "edts", "esds",
            //    "tfdt", "trik", "ctts", "stts", "stco", "stsc":
            //    print("skip \(parent)/\(atom) \(Array(pointer).hexStringEncoded().prefix(count*2))")
        default:
            Self.logger.debug("skip \(parent)/\(atom)")
            return
        }
    }
    
    private func consumeBox_tfhd(pointer: UnsafeRawBufferPointer, count: Int) {
        /// https://github.com/jwhittle933/backlit-streamline-go/blob/main/media/mpeg/box/moof/traf/tfhd/api.go
        let versionAndFlags_bytes: [UInt8] = Array(pointer[0..<4])
        let versionAndFlags: UInt32 = versionAndFlags_bytes.uint32Value
        //        let version = versionAndFlags >> 24
        let flags = versionAndFlags & 0x00ffffff
        //00000020  // Version byte, Flags   uint32, FlagsMask = 0x00ffffff, byte(vf >> 24), vf & FlagsMask
        //00000001  // TrackID
        //000100c0  // depend on flags
        
        let TrackID_bytes: [UInt8] = Array(pointer[4..<8])
        let TrackID = TrackID_bytes.uint32Value
        Self.logger.debug("tfhd: TrackID \(TrackID)")
        self.trackID = Int(TrackID)
        
    }
    
    private func consumeBox_mfhd(pointer: UnsafeRawBufferPointer, count: Int) {
        
        let versionAndFlags_bytes: [UInt8] = Array(pointer[0..<4])
        let SequenceNumber_bytes: [UInt8] = Array(pointer[4..<8])
        
        
        
        let versionAndFlags: UInt32 = versionAndFlags_bytes.uint32Value
        //        let version = versionAndFlags >> 24
        //        let flags = versionAndFlags & 0x00ffffff
        let SequenceNumber = SequenceNumber_bytes.uint32Value
        Self.logger.debug("mfhd: SequenceNumber \(SequenceNumber)")
        self.sequenceNumber = Int(SequenceNumber)
        
    }
    
    private func consume_nalu265(pointer: UnsafeRawBufferPointer, count: Int) {
        precondition(trackID == 1)
        precondition(is265)
        precondition(self.formatDescription != nil)
        
        let seq = self.sequenceNumber ?? 0
        
        let nalType = pointer[0]
        let x = ((nalType & 0x7e) >> 1)
        Self.logger.debug("NALU nalType:\(nalType) x:\(x) count:\(count) seq:\(seq)")
        
        //NAL header: 0x2601     I
        //NAL header: 0x0201     P
        //0x40, 0x42 and 0x44 indicate the VPS, PPS and SPS prefixed by length
        let naluData = Array(pointer)
        //print(naluData.hexStringEncoded())
        
        //onFrame(i)  //тут префикса с размером нет!
        switch nalType {
        case 0x26:  // I    Type:38 //x:19
            //onFrame(naluData)
            //self.onFrame(format, naluData, true, seq)
            let bigEndianLength = CFSwapInt32HostToBig(UInt32(naluData.count))
            let avcc = withUnsafeBytes(of: bigEndianLength) { Data($0) } + naluData
            self.decodeAVCCFrame(avcc)
        case 0x02:  // P    Type:2 //x:1
            //onFrame(naluData)
            //self.onFrame(format, naluData, false, seq)
            let bigEndianLength = CFSwapInt32HostToBig(UInt32(naluData.count))
            let avcc = withUnsafeBytes(of: bigEndianLength) { Data($0) } + naluData
            self.decodeAVCCFrame(avcc)
        case 0x40:  // VPS  Type:64 //x:32
            print("VPS")
        case 0x42:  // SPS  Type:66 //x:33
            print("SPS")
        case 0x44:  // PPS  Type:68 //x:34
            print("PPS")
        default:
            print("skip")
        }
    }
    
    private func consume_nalu264(pointer: UnsafeRawBufferPointer, count: Int) {
        precondition(trackID == 1)
        precondition(is264)
        precondition(self.formatDescription != nil)
        
        let seq = self.sequenceNumber ?? 0
        
        let nalType = pointer[0] & 0x1F
        let nalType2 = pointer[0]
        let x = ((nalType2 & 0x7e) >> 1)
        Self.logger.debug("NALU Nal type nalType:\(nalType) nalType2:\(nalType2) x:\(x) count:\(count) seq:\(seq)")
        
        let naluData = Array(pointer)
        
        //onFrame(i)  //тут префикса с размером нет!
        switch nalType {
        case 0x05:
            Self.logger.debug("Nal type is IDR frame")
            let bigEndianLength = CFSwapInt32HostToBig(UInt32(naluData.count))
            let avcc = withUnsafeBytes(of: bigEndianLength) { Data($0) } + naluData
            self.decodeAVCCFrame(avcc)
        case 0x07:
            Self.logger.debug("Nal type is SPS")
        case 0x08:
            Self.logger.debug("Nal type is PPS")
        case 0x01:
            Self.logger.debug("Nal type is B/P frame")
            //            if nalType2 == 65 { //
            let bigEndianLength = CFSwapInt32HostToBig(UInt32(naluData.count))
            let avcc = withUnsafeBytes(of: bigEndianLength) { Data($0) } + naluData
            self.decodeAVCCFrame(avcc)
            //            }
        default:
            Self.logger.debug("Nal type ignore \(nalType)")
        }
    }
    //    NALU Nal type nalType:7 nalType2:103 x:51 count:28 seq:125
    //    Nal type is SPS
    //    NALU Nal type nalType:8 nalType2:104 x:52 count:5 seq:125
    //    Nal type is PPS
    //    NALU Nal type nalType:5 nalType2:101 x:50 count:1552 seq:125
    //    Nal type is IDR frame
    //    NALU Nal type nalType:1 nalType2:65 x:32 count:233 seq:125
    //    Nal type is B/P frame
    //    NALU Nal type nalType:1 nalType2:65 x:32 count:232 seq:125
    //    Nal type is B/P frame
    //    NALU Nal type nalType:1 nalType2:1 x:0 count:232 seq:125
    //    Nal type is B/P frame
    //    NALU Nal type nalType:1 nalType2:1 x:0 count:232 seq:125
    //    Nal type is B/P frame
    //    NALU Nal type nalType:1 nalType2:65 x:32 count:239 seq:126
    //    Nal type is B/P frame
    //    NALU Nal type nalType:1 nalType2:65 x:32 count:233 seq:126
    //    Nal type is B/P frame
    //    NALU Nal type nalType:1 nalType2:1 x:0 count:232 seq:126
    //    Nal type is B/P frame
    //    NALU Nal type nalType:1 nalType2:1 x:0 count:232 seq:127
    //
    private func consumeBox_mdat(pointer: UnsafeRawBufferPointer, count: Int) {
        
        guard trackID == 1 else {
            //think that video is track 1 always
            print("audio from \(self.trackID)")
            return
        }
        precondition(is264 || is265)
        precondition(self.formatDescription != nil)
        
        let seq = self.sequenceNumber ?? 0
        
        //h265
        var consumed = 0
        while count > consumed+4 {
            //TODO: check NALULengthSizeMinusOne === 3
            let start4: [UInt8] = Array(pointer[consumed..<consumed+4])
            let start4_uint32 = start4.withUnsafeBytes({ $0.load(as: UInt32.self) })
            let nalCount = Int(UInt32(bigEndian: start4_uint32 ))
            consumed += 4
            
            if nalCount + consumed > count {
                Self.logger.error("UNEXPECTED nalCount:\(nalCount) consumed:\(consumed) count:\(count)")
                break
            }
            
            let nalu = pointer[consumed..<(consumed + nalCount)]
            let rebased = UnsafeRawBufferPointer(rebasing: nalu)
            
            if is265 {
                consume_nalu265(pointer: rebased, count: nalCount)
            } else if is264 {
                consume_nalu264(pointer: rebased, count: nalCount)
            } else {
                fatalError()
            }
            consumed += nalCount
        }
    }
}


enum Mp4ParseError : Error {
    case ftyp
    
    case typeNotAscii
    case unexpectedAtom
    case veryLargeFrame
}


struct Atom_avcC {
    let version: UInt8
    let avc_profile: UInt8
    let avc_compatibility: UInt8
    let avc_level: UInt8
    let NALULengthSizeMinusOne: UInt8
    let sps: [UInt8]
    let pps: [UInt8]
}

extension Atom_avcC {
    func formatDescription() throws -> CMVideoFormatDescription {
        let formatDescription = try CMVideoFormatDescription(h264ParameterSets: [Data(sps), Data(pps)])
        return formatDescription
    }
}

extension Atom_avcC {
    init(data: [UInt8]) throws {
        self.version = data[0]
        self.avc_profile = data[1]
        self.avc_compatibility = data[2]
        self.avc_level = data[3]
        
        //ff      // 6 bits reserved + lengthSizeMinus1
        //e1      // 3 bits reserved + SPS count
        //001d    // spslen
        self.NALULengthSizeMinusOne = data[4] & 0x03
        print(NALULengthSizeMinusOne)
        let spsCount = (data[5] & 0x1F)
        
        let spsSizeValue = Int(data[6] << 8 | data[7])
        precondition(spsSizeValue < data.count)
        let spsBytes = Array( data[8..<8+spsSizeValue] )
        self.sps = spsBytes
        
        let ppsCount = data[8+spsSizeValue]
        let ppsOffset = 8+spsSizeValue+1
        let ppsSizeValue = Int(data[ppsOffset] << 8 | data[ppsOffset+1])
        precondition(ppsSizeValue < data.count)
        let ppsBytes = Array( data[ppsOffset+2..<ppsOffset+2+ppsSizeValue] )
        self.pps = ppsBytes
    }
    
}



struct Atom_hvcC {
    let vps: [UInt8]
    let sps: [UInt8]
    let pps: [UInt8]
}

extension Atom_hvcC {
    func formatDescription() throws -> CMVideoFormatDescription {
        let formatDescription =
        try CMVideoFormatDescription(hevcParameterSets: [Data(vps), Data(sps), Data(pps)])
        return formatDescription
    }
}


func dump_hvcC(data: [UInt8]) -> (vps: [UInt8], sps: [UInt8], pps: [UInt8]) {
    let num_seq = data[22] //3
    var cursor: Int = 22
    cursor += 1
    let NaluType = data[cursor] & 0x3F
    let ArrayCompleteness = (data[cursor] >> 7) & 0x01
    cursor += 1
    let nalu_count = Int(data[cursor] << 8 | data[cursor+1])
    cursor += 2
    let nalu_length = Int(data[cursor] << 8 | data[cursor+1])
    cursor += 2
    let vpsBytes = Array( data[cursor..<cursor+nalu_length] )
    cursor += nalu_length
    
    let NaluType1 = data[cursor] & 0x3F
    let ArrayCompleteness1 = (data[cursor] >> 7) & 0x01
    cursor += 1
    let nalu_count1 = Int(data[cursor] << 8 | data[cursor+1])
    cursor += 2
    let nalu_length1 = Int(data[cursor] << 8 | data[cursor+1])
    cursor += 2
    let spsBytes = Array( data[cursor..<cursor+nalu_length1] )
    cursor += nalu_length1
    
    let NaluType2 = data[cursor] & 0x3F
    let ArrayCompleteness2 = (data[cursor] >> 7) & 0x01
    cursor += 1
    let nalu_count2 = Int(data[cursor] << 8 | data[cursor+1])
    cursor += 2
    let nalu_length2 = Int(data[cursor] << 8 | data[cursor+1])
    cursor += 2
    let ppsBytes = Array( data[cursor..<cursor+nalu_length2] )
    cursor += nalu_length2
    
    return (vpsBytes, spsBytes, ppsBytes)
}


//struct Atom_stsd {
//    let SampleCount: UInt32
//}
//
//extension Atom_stsd {
//    init(data: [UInt8]) {
////        b.WriteVersionAndFlags(sr)
////        b.SampleCount = sr.Uint32()
////        "avc1": visual.New,
////        "avc3": visual.New,
////        "hev1": visual.New,
////        "hvc1": visual.New,
////        "mp4a": audio.New,
////        "encv": visual.New,
//        print(data.hexStringEncoded())
//        let versionAndFlags: UInt32 = Array(data.prefix(4)).uint32Value
//        let version = versionAndFlags >> 24
//        let flags = versionAndFlags & 0x00ffffff
//
//        let SampleCount = Array(data.dropFirst(4).prefix(4)).uint32Value
//
//        print("stsd: SampleCount \(SampleCount)")
//        self.SampleCount = SampleCount
//    }
//}

