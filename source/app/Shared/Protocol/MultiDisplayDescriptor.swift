import Foundation

struct DisplayDescriptor: Codable, Identifiable, Hashable {
    let id: UInt32
    let index: Int
    let name: String
    let width: Int
    let height: Int
    let isPrimary: Bool
    let scaleFactor: Double

    var displayTitle: String {
        let primaryTag = isPrimary ? " (主螢幕)" : ""
        return "\(name) [\(width)x\(height)]\(primaryTag)"
    }
}

struct MultiDisplayStreamPacket {
    static let magic: [UInt8] = [0x41, 0x50, 0x56, 0x44]
    static let headerSize: Int = 24

    let displayID: UInt32
    let displayIndex: UInt8
    let isKeyframe: Bool
    let ptsNanoseconds: UInt64
    let width: UInt16
    let height: UInt16
    let videoData: Data

    func pack() -> Data {
        var data = Data(Self.magic)
        withUnsafeBytes(of: displayID.bigEndian) { data.append(contentsOf: $0) }
        data.append(displayIndex)
        data.append(isKeyframe ? 1 : 0)
        withUnsafeBytes(of: ptsNanoseconds.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: width.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: height.bigEndian) { data.append(contentsOf: $0) }
        data.append(videoData)
        return data
    }

    static func unpack(_ data: Data) -> MultiDisplayStreamPacket? {
        guard data.count >= headerSize,
              data.prefix(4).elementsEqual(Self.magic) else { return nil }

        var dID: UInt32 = 0
        data.subdata(in: 4..<8).withUnsafeBytes { dID = $0.loadUnaligned(as: UInt32.self) }
        let displayID = UInt32(bigEndian: dID)

        let displayIndex = data[8]
        let isKeyframe = data[9] == 1

        var pts: UInt64 = 0
        data.subdata(in: 10..<18).withUnsafeBytes { pts = $0.loadUnaligned(as: UInt64.self) }
        let ptsNanoseconds = UInt64(bigEndian: pts)

        var w: UInt16 = 0
        data.subdata(in: 18..<20).withUnsafeBytes { w = $0.loadUnaligned(as: UInt16.self) }
        let width = UInt16(bigEndian: w)

        var h: UInt16 = 0
        data.subdata(in: 20..<22).withUnsafeBytes { h = $0.loadUnaligned(as: UInt16.self) }
        let height = UInt16(bigEndian: h)

        let videoData = data.subdata(in: headerSize..<data.count)

        return MultiDisplayStreamPacket(
            displayID: displayID,
            displayIndex: displayIndex,
            isKeyframe: isKeyframe,
            ptsNanoseconds: ptsNanoseconds,
            width: width,
            height: height,
            videoData: videoData
        )
    }
}
