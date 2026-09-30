import AVFAudio
import Foundation

/// 學生端廣播音訊播放器：將教師端送來的 PCM 緩衝區排入 AVAudioEngine 播放。
/// 格式由每幀標頭描述（取樣率/聲道/位深/浮點/交錯），引擎的轉換節點自動適配輸出裝置。
final class BroadcastAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isRunning = false
    /// 已排入節點、尚未播完的緩衝塊數（用於偵測播放佇列是否乾涸）。
    private var queuedBuffers = 0

    // —— 抖動緩衝（jitter buffer）——
    // 網路（尤其 Wi-Fi）會讓每個 80ms 音訊塊到達時間參差不齊；
    // 若一到就立刻排程播放，任一塊遲到就會讓播放佇列乾涸 → 卡頓。
    // 解法：先累積「預卷」塊數再開播，之後每來一塊就補排一塊，
    // 播放佇列永遠保持余量，把抖動吸收掉。
    private var pending: [AVAudioPCMBuffer] = []
    /// 預卷：累積滿 3 塊（≈240ms）才開始播放。
    private let preRollChunks = 3
    /// 積壓上限：超過 8 塊（≈640ms）時丟棄「新到的」資料，保證延遲有界；
    /// 丟新不丟舊，已排程的音訊保持連續，不會產生跳段破音/低頻哼聲。
    private let maxPendingChunks = 8
    private var isPrimed = false

    // —— 崩潰防護 ——
    // 播放節點一經啟動就會鎖定輸出格式；後續若排入「格式不同」的緩衝
    // （例如個別塊的取樣率/聲道數不同），渲染執行緒的取樣率轉換器會
    // 讀到錯位指標 → EXC_BAD_ACCESS（見崩潰報告 IOThread.client + memmove）。
    // 解法：整個廣播期間鎖定第一個塊的格式，其餘格式不符的塊一律丟棄。
    private var lockedFormat: (rate: Double, channels: UInt32, bits: UInt8, isFloat: Bool, interleaved: Bool)?
    /// 已排入節點但尚未播完的緩衝，以強引用保活至播放完成，
    /// 確保渲染執行緒讀取期間資料絕不被提前釋放。
    private var inFlight: [AVAudioPCMBuffer] = []

    // —— 音訊診斷統計（alpha 除錯用）——
    private var receivedCount = 0
    private var droppedCount = 0
    private var lastStatLogAt: TimeInterval = 0

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
    }

    /// 啟動引擎（廣播開始時呼叫）。
    func start() {
        guard !isRunning else { return }
        do {
            try engine.start()
            isRunning = true
            queuedBuffers = 0
            pending.removeAll()
            isPrimed = false
            lockedFormat = nil
        } catch {
            isRunning = false
            DiagLog.log("引擎啟動失敗（可能是無音訊輸出裝置）: \(error)")
        }
    }

    /// 停止並清空（廣播停止時呼叫）。
    func stop() {
        guard isRunning else { return }
        player.stop()
        engine.stop()
        isRunning = false
        queuedBuffers = 0
        pending.removeAll()
        inFlight.removeAll()
        isPrimed = false
        lockedFormat = nil
    }

    /// 播放一段 PCM。格式必須與標頭一致。
    func play(pcm: Data, format: PeerConnection.AudioFormatInfo) {
        if !isRunning { start() }
        guard isRunning, !pcm.isEmpty else { return }

        // 格式鎖：只接受與首塊完全一致的格式；不符（或明顯畸形）的塊直接丟棄，
        // 避免播放節點排入異構格式緩衝造成渲染執行緒崩潰。
        if lockedFormat == nil {
            guard format.sampleRate >= 8000, format.sampleRate <= 96000,
                  format.channels >= 1, format.channels <= 2,
                  format.bits == 16 || format.bits == 32 else {
                droppedCount += 1
                DiagLog.log("拒收畸形塊: rate=\(format.sampleRate) ch=\(format.channels) bits=\(format.bits)")
                return
            }
            lockedFormat = (format.sampleRate, format.channels, format.bits,
                            format.isFloat, format.interleaved)
            DiagLog.log("鎖定格式: rate=\(format.sampleRate) ch=\(format.channels) bits=\(format.bits) float=\(format.isFloat) interleaved=\(format.interleaved)")
        } else {
            let locked = lockedFormat!
            guard format.sampleRate == locked.rate,
                  format.channels == locked.channels,
                  format.bits == locked.bits,
                  format.isFloat == locked.isFloat,
                  format.interleaved == locked.interleaved else {
                droppedCount += 1
                DiagLog.log("丟棄格式不符塊: rate=\(format.sampleRate) ch=\(format.channels) bits=\(format.bits)")
                return
            }
        }

        guard let buffer = makeBuffer(pcm: pcm, format: format) else {
            droppedCount += 1
            return
        }

        // 積壓超過上限 → 丟棄「新到的」這塊（保舊不丟舊）：
        // 已排程/已緩衝的音訊必須保持連續，丟中間的舊塊會製造時間斷層，
        // 聽起來像低頻馬達聲/風鳴；丟掉新到的只會讓延遲有界，播放本身不破音。
        if pending.count >= maxPendingChunks {
            droppedCount += 1
            return
        }
        pending.append(buffer)
        receivedCount += 1
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastStatLogAt > 2 {
            lastStatLogAt = now
            DiagLog.log("接收=\(receivedCount) 塊 丟棄=\(droppedCount) 塊 在飛=\(inFlight.count) 待播=\(pending.count) 播放中=\(player.isPlaying)")
        }

        if !isPrimed {
            // 預卷未滿：繼續累積，不要急著播放
            guard pending.count >= preRollChunks else { return }
            isPrimed = true
            flushPending()
        } else {
            // 正常流：補排最舊的一塊，維持佇列深度
            schedule(pending.removeFirst())
        }
    }

    /// 把一段 PCM 轉成 AVAudioPCMBuffer。
    /// 無論線上格式是否交錯，**一律以「交錯」格式建立緩衝**：
    /// 單一連續記憶體 + 整段拷貝（或手動重排），完全不涉及非交錯緩衝的
    /// 分通道指標運算與「每通道單獨 mDataByteSize」的記憶體佈局假設——
    /// 從根本上排除緩衝越界/野指標類別的渲染執行緒崩潰。
    private func makeBuffer(pcm: Data, format: PeerConnection.AudioFormatInfo) -> AVAudioPCMBuffer? {
        let common: AVAudioCommonFormat = format.isFloat ? .pcmFormatFloat32 : .pcmFormatInt16
        guard let audioFormat = AVAudioFormat(commonFormat: common,
                                              sampleRate: format.sampleRate,
                                              channels: format.channels,
                                              interleaved: true),
              audioFormat.isStandard else { return nil }

        let bytesPerSample = max(Int(format.bits) / 8, 1)
        let channelCount = max(Int(format.channels), 1)
        let frames = pcm.count / (channelCount * bytesPerSample)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat,
                                            frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)

        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard buffers.count == 1, let dst = buffers[0].mData else { return nil }
        buffers[0].mDataByteSize = UInt32(pcm.count)
        pcm.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            guard let base = src.baseAddress else { return }
            if format.interleaved {
                // 交錯：[L0 R0 L1 R1 ...] → 一次整段拷貝
                memcpy(dst, base, pcm.count)
            } else {
                // 非交錯：[L 全部][R 全部] → 手動重排成交錯 [L0 R0 L1 R1 ...]
                let m = dst.assumingMemoryBound(to: UInt8.self)
                for f in 0..<frames {
                    for c in 0..<channelCount {
                        let srcOffset = c * frames * bytesPerSample + f * bytesPerSample
                        let dstOffset = (f * channelCount + c) * bytesPerSample
                        memcpy(m + dstOffset, base + srcOffset, bytesPerSample)
                    }
                }
            }
        }
        return buffer
    }

    /// 把待播緩衝全部排入節點並開始播放。
    private func flushPending() {
        while let buffer = pending.first {
            pending.removeFirst()
            schedule(buffer)
        }
    }

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        // 以強引用保活至播放完成：AVAudioPlayerNode 正常會自行保留，
        // 此處再兜一層，杜絕任何「渲染執行緒讀取已釋放緩衝」的野指標崩潰。
        inFlight.append(buffer)
        player.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.queuedBuffers = max(self.queuedBuffers - 1, 0)
                self.inFlight.removeAll { $0 === buffer }
                // 播放佇列完全乾涸 → 節點已停止/將停止，重設預卷狀態，
                // 待下一個塊累積滿預卷再重新開播（避免碎塊反覆起停）
                if self.queuedBuffers == 0 { self.isPrimed = false }
            }
        }
        queuedBuffers += 1
        if !player.isPlaying { player.play() }
    }
}
