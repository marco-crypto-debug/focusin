import Foundation
import Darwin

/// UDP 組播傳輸層（v1.5-beta 新架構）
/// - 教師端：以單一組播流發送畫面（AP 複製給所有訂閱的學生機，帶寬與學生數無關）
/// - 學生端：加入組播組接收
/// - 同時內建組播探測統計（AP 吞吐測試工具，Swift 原生版）
final class MulticastTransport {
    /// 組播組位址（與 tools/multicast_probe.py 一致）
    static let group = "239.255.42.99"
    /// 畫面組播埠（H.264 幀）
    static let videoPort: UInt16 = 7100
    /// 測試組播埠（AP 吞吐探測）
    static let probePort: UInt16 = 7000
    /// 探測包魔數：FZMP（FocusIn Multicast Probe）
    static let probeMagic: [UInt8] = [0x46, 0x5A, 0x4D, 0x50]
    /// 畫面幀魔數：FZHV（FocusIn H.264 Video）
    static let videoMagic: [UInt8] = [0x46, 0x5A, 0x48, 0x56]

    // MARK: - Socket 工具

    /// 建立組播發送 socket。
    static func makeSender(ifaceIP: String?, ttl: UInt8 = 1) -> Int32? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        var ttl = ttl
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        if let iface = ifaceIP {
            let addr = inet_addr(iface)
            if addr != INADDR_NONE {
                var a = addr
                setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &a, socklen_t(MemoryLayout<UInt32>.size))
            }
        }
        return fd
    }

    /// 建立組播接收 socket（加入組播組）。
    static func makeReceiver(group: String = MulticastTransport.group,
                             port: UInt16,
                             ifaceIP: String?) -> Int32? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            return nil
        }

        // IP_ADD_MEMBERSHIP：ip_mreq = group(4B) + interface(4B)
        var mreq = ip_mreq()
        mreq.imr_multiaddr.s_addr = inet_addr(group)
        var ifaceAddr = INADDR_ANY
        if let ifaceIP {
            let parsed = inet_addr(ifaceIP)
            if parsed != INADDR_NONE { ifaceAddr = parsed }
        }
        mreq.imr_interface.s_addr = ifaceAddr
        let joinResult = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq,
                                    socklen_t(MemoryLayout<ip_mreq>.size))
        guard joinResult == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    // MARK: - 發送端

    private var sendFD: Int32 = -1
    private var sendGroup = MulticastTransport.group
    private var sendPort: UInt16 = MulticastTransport.videoPort
    private let sendLock = NSLock()

    /// 建立發送端（教師端畫面 / 探測）。
    func startSender(port: UInt16, group: String = MulticastTransport.group, ifaceIP: String?) {
        stop()
        sendFD = MulticastTransport.makeSender(ifaceIP: ifaceIP) ?? -1
        sendGroup = group
        sendPort = port
    }

    /// 發送一筆數據到組播組（不可靠，無回執）。
    func send(_ data: Data) {
        guard sendFD >= 0 else { return }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = sendPort.bigEndian
        addr.sin_addr.s_addr = inet_addr(sendGroup)
        let sock = sendFD
        data.withUnsafeBytes { raw in
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    let sent = sendto(sock, raw.baseAddress, raw.count, 0,
                                      sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    if sent < 0 {
                        DiagLog.log("組播發送失敗: errno=\(errno)")
                    }
                }
            }
        }
    }

    // MARK: - 接收端

    private var recvFD: Int32 = -1
    private var recvThread: Thread?
    private var recvRunning = false
    private var onData: ((Data) -> Void)?

    /// 啟動接收迴圈（學生端接收畫面 / 探測統計）。
    /// - Parameters:
    ///   - port: 監聽埠
    ///   - ifaceIP: 介面 IP（nil = 自動）
    ///   - onData: 收到數據回呼（背景執行緒）
    func startReceiver(port: UInt16, ifaceIP: String?, onData: @escaping (Data) -> Void) {
        stop()
        guard let fd = MulticastTransport.makeReceiver(port: port, ifaceIP: ifaceIP) else {
            DiagLog.log("組播接收啟動失敗（埠 \(port)）")
            return
        }
        recvFD = fd
        self.onData = onData
        recvRunning = true
        recvThread = Thread { [weak self] in
            self?.receiveLoop(fd: fd)
        }
        recvThread?.name = "FocusIn.Multicast.\(port)"
        recvThread?.qualityOfService = .userInteractive
        recvThread?.start()
    }

    private func receiveLoop(fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        while recvRunning {
            let n = recv(fd, &buffer, buffer.count, 0)
            if n > 0 {
                let data = Data(bytes: buffer, count: n)
                if let onData { onData(data) }
            } else if n < 0 && errno == EINTR {
                continue
            } else if n < 0 {
                break
            }
        }
    }

    /// 停止所有收發。
    func stop() {
        recvRunning = false
        if recvFD >= 0 {
            close(recvFD)
            recvFD = -1
        }
        recvThread?.cancel()
        recvThread = nil
        sendLock.lock()
        if sendFD >= 0 {
            close(sendFD)
            sendFD = -1
        }
        sendLock.unlock()
        onData = nil
    }

    deinit { stop() }
}

// MARK: - H.264 幀封裝（v1.5-beta 組播畫面）

extension MulticastTransport {
    /// 封裝 H.264 幀：magic FZHV(4) + key(1) + spsLen(2) + ppsLen(2) + sps + pps + annexB
    static func packH264Frame(_ annexB: Data, key: Bool, sps: Data?, pps: Data?) -> Data {
        var out = Data(MulticastTransport.videoMagic)
        out.append(key ? 1 : 0)
        let spsLen = UInt16(sps?.count ?? 0)
        let ppsLen = UInt16(pps?.count ?? 0)
        withUnsafeBytes(of: spsLen.bigEndian) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: ppsLen.bigEndian) { out.append(contentsOf: $0) }
        if let sps { out.append(sps) }
        if let pps { out.append(pps) }
        out.append(annexB)
        return out
    }

    /// 解析 H.264 幀（學生端）。
    static func unpackH264Frame(_ data: Data) -> (annexB: Data, key: Bool, sps: Data?, pps: Data?)? {
        guard data.count > 9, data.prefix(4).elementsEqual(MulticastTransport.videoMagic) else { return nil }
        let key = data[4] == 1
        var spsLen = UInt16(0)
        data.subdata(in: 5..<7).withUnsafeBytes { spsLen = $0.loadUnaligned(as: UInt16.self) }
        var ppsLen = UInt16(0)
        data.subdata(in: 7..<9).withUnsafeBytes { ppsLen = $0.loadUnaligned(as: UInt16.self) }
        spsLen = UInt16(bigEndian: spsLen)
        ppsLen = UInt16(bigEndian: ppsLen)
        var offset = 9
        var sps: Data?
        if spsLen > 0, offset + Int(spsLen) <= data.count {
            sps = data.subdata(in: offset..<offset + Int(spsLen))
            offset += Int(spsLen)
        }
        var pps: Data?
        if ppsLen > 0, offset + Int(ppsLen) <= data.count {
            pps = data.subdata(in: offset..<offset + Int(ppsLen))
            offset += Int(ppsLen)
        }
        guard offset < data.count else { return nil }
        return (data.subdata(in: offset..<data.count), key, sps, pps)
    }
}

// MARK: - 組播探測（AP 吞吐測試）

/// 組播探測統計：追蹤序號、計算速率與丟包率（每 5 秒窗口）。
final class MulticastProbeStats {
    /// 探測包頭：magic(4) + seq(4, 大端) + 發送時間戳(8) + 檔位(2, 大端)
    static let headerSize = 18

    private(set) var totalPackets = 0
    private(set) var totalBytes = 0
    private var lastSeq: UInt32?
    private var gaps: UInt32 = 0
    private var windowStart = Date()
    private var windowPackets = 0
    private var windowBytes = 0

    /// 重設統計（開始新一輪探測時呼叫）。
    func resetForProbe() {
        totalPackets = 0
        totalBytes = 0
        lastSeq = nil
        gaps = 0
        windowStart = Date()
        windowPackets = 0
        windowBytes = 0
    }

    /// 組裝一筆探測包（發送端用）。
    static func makeProbePacket(seq: UInt32, stage: UInt16, payloadSize: Int) -> Data {
        var data = Data(MulticastTransport.probeMagic)
        withUnsafeBytes(of: seq.bigEndian) { data.append(contentsOf: $0) }
        var ts = Date().timeIntervalSince1970
        withUnsafeBytes(of: &ts) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: stage.bigEndian) { data.append(contentsOf: $0) }
        data.append(Data(count: payloadSize))
        return data
    }

    /// 解析探測包（接收端用），回傳 (seq, stage)；非探測包回傳 nil。
    static func parseProbePacket(_ data: Data) -> (seq: UInt32, stage: UInt16)? {
        guard data.count >= headerSize,
              data.prefix(4).elementsEqual(MulticastTransport.probeMagic) else { return nil }
        var seq: UInt32 = 0
        data.subdata(in: 4..<8).withUnsafeBytes { seq = $0.loadUnaligned(as: UInt32.self) }
        var stage: UInt16 = 0
        data.subdata(in: 16..<18).withUnsafeBytes { stage = $0.loadUnaligned(as: UInt16.self) }
        return (UInt32(bigEndian: seq), UInt16(bigEndian: stage))
    }

    /// 記錄收到一包（接收端統計）。
    func record(packet: Data) {
        guard let (seq, _) = MulticastProbeStats.parseProbePacket(packet) else { return }
        if let last = lastSeq {
            if seq > last {
                gaps += seq - last - 1
            }
        }
        lastSeq = seq
        totalPackets += 1
        totalBytes += packet.count
        windowPackets += 1
        windowBytes += packet.count
    }

    /// 當前窗口（自上次呼叫起）速率 Mbps 與丟包率（0-100）。
    func windowStats() -> (mbps: Double, lossPercent: Double, packets: Int) {
        let elapsed = max(Date().timeIntervalSince(windowStart), 0.001)
        let mbps = Double(windowBytes) * 8 / 1_000_000 / elapsed
        let loss = gaps > 0 ? Double(gaps) / Double(totalPackets + Int(gaps)) * 100 : 0
        let packets = windowPackets
        windowPackets = 0
        windowBytes = 0
        windowStart = Date()
        return (mbps, loss, packets)
    }
}


// MARK: - 音訊組播（Delta：UDP 組播聲音，1 份串流 AP 複製）

extension MulticastTransport {
    /// 音訊組播埠（與畫面 videoPort 分開，避免互相阻塞）。
    static let audioPort: UInt16 = 7200

    /// 打包音訊：FZAU(4) + sampleRate(4, LE) + channels(1) + bits(1) + isFloat(1) + interleaved(1) + reserved(2) + PCM。
    static func packAudio(_ pcm: Data, format: PeerConnection.AudioFormatInfo) -> Data {
        var payload = Data(PeerConnection.audioMagic)
        var sr = UInt32(format.sampleRate.rounded()).littleEndian
        payload.append(Data(bytes: &sr, count: 4))
        payload.append(UInt8(format.channels))
        payload.append(format.bits)
        payload.append(format.isFloat ? 1 : 0)
        payload.append(format.interleaved ? 1 : 0)
        payload.append(0)
        payload.append(0)
        payload.append(pcm)
        return payload
    }

    /// 解包音訊；格式不符（魔數錯 / 太短）回傳 nil。
    static func unpackAudio(_ data: Data) -> (pcm: Data, format: PeerConnection.AudioFormatInfo)? {
        guard data.count > 14, data.prefix(4).elementsEqual(PeerConnection.audioMagic) else { return nil }
        var sr: UInt32 = 0
        data.subdata(in: 4..<8).withUnsafeBytes { sr = $0.loadUnaligned(as: UInt32.self) }
        let info = PeerConnection.AudioFormatInfo(sampleRate: Double(UInt32(littleEndian: sr)),
                                                  channels: UInt32(data[8]),
                                                  bits: data[9],
                                                  isFloat: data[10] == 1,
                                                  interleaved: data[11] == 1)
        return (data.subdata(in: 14..<data.count), info)
    }
}
