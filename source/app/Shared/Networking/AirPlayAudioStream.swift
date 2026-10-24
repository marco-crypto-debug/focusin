import Foundation
import Darwin

enum AirPlayClock {
    private static let timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static var nowNanoseconds: UInt64 {
        let machTime = mach_absolute_time()
        return (machTime * UInt64(timebaseInfo.numer)) / UInt64(timebaseInfo.denom)
    }

    static func toNanoseconds(_ machTime: UInt64) -> UInt64 {
        return (machTime * UInt64(timebaseInfo.numer)) / UInt64(timebaseInfo.denom)
    }
}

struct AirPlayAudioPacket {
    static let magic: [UInt8] = [0x41, 0x50, 0x41, 0x55]
    static let headerSize: Int = 28

    let version: UInt8
    let flags: UInt8
    let sequenceNumber: UInt16
    let ptsNanoseconds: UInt64
    let clockID: UInt32
    let sampleRate: Double
    let channels: UInt32
    let bits: UInt8
    let isFloat: Bool
    let isInterleaved: Bool
    let pcm: Data

    func pack() -> Data {
        var data = Data(Self.magic)
        data.append(version)
        data.append(flags)
        withUnsafeBytes(of: sequenceNumber.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: ptsNanoseconds.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: clockID.bigEndian) { data.append(contentsOf: $0) }

        var sr = UInt32(sampleRate.rounded()).littleEndian
        data.append(Data(bytes: &sr, count: 4))
        data.append(UInt8(channels))
        data.append(bits)

        var fmtFlags: UInt8 = 0
        if isFloat { fmtFlags |= 0x01 }
        if isInterleaved { fmtFlags |= 0x02 }
        data.append(fmtFlags)
        data.append(0)

        data.append(pcm)
        return data
    }

    static func unpack(_ data: Data) -> AirPlayAudioPacket? {
        guard data.count >= headerSize,
              data.prefix(4).elementsEqual(Self.magic) else { return nil }

        let version = data[4]
        let flags = data[5]

        var seq: UInt16 = 0
        data.subdata(in: 6..<8).withUnsafeBytes { seq = $0.loadUnaligned(as: UInt16.self) }
        seq = UInt16(bigEndian: seq)

        var pts: UInt64 = 0
        data.subdata(in: 8..<16).withUnsafeBytes { pts = $0.loadUnaligned(as: UInt64.self) }
        pts = UInt64(bigEndian: pts)

        var clockID: UInt32 = 0
        data.subdata(in: 16..<20).withUnsafeBytes { clockID = $0.loadUnaligned(as: UInt32.self) }
        clockID = UInt32(bigEndian: clockID)

        var sr: UInt32 = 0
        data.subdata(in: 20..<24).withUnsafeBytes { sr = $0.loadUnaligned(as: UInt32.self) }
        let sampleRate = Double(UInt32(littleEndian: sr))

        let channels = UInt32(data[24])
        let bits = data[25]
        let fmtFlags = data[26]
        let isFloat = (fmtFlags & 0x01) != 0
        let isInterleaved = (fmtFlags & 0x02) != 0

        let pcm = data.subdata(in: headerSize..<data.count)

        return AirPlayAudioPacket(
            version: version,
            flags: flags,
            sequenceNumber: seq,
            ptsNanoseconds: pts,
            clockID: clockID,
            sampleRate: sampleRate,
            channels: channels,
            bits: bits,
            isFloat: isFloat,
            isInterleaved: isInterleaved,
            pcm: pcm
        )
    }

    var legacyFormatInfo: PeerConnection.AudioFormatInfo {
        PeerConnection.AudioFormatInfo(
            sampleRate: sampleRate,
            channels: channels,
            bits: bits,
            isFloat: isFloat,
            interleaved: isInterleaved
        )
    }
}
