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
        } catch {
            isRunning = false
            print("[AudioPlayer] 引擎啟動失敗（可能是無音訊輸出裝置）: \(error)")
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
        isPrimed = false
    }

    /// 播放一段 PCM。格式必須與標頭一致。
    func play(pcm: Data, format: PeerConnection.AudioFormatInfo) {
        if !isRunning { start() }
        guard isRunning, !pcm.isEmpty else { return }

        guard let buffer = makeBuffer(pcm: pcm, format: format) else { return }

        // 積壓超過上限 → 丟棄「新到的」這塊（保舊不丟舊）：
        // 已排程/已緩衝的音訊必須保持連續，丟中間的舊塊會製造時間斷層，
        // 聽起來像低頻馬達聲/風鳴；丟掉新到的只會讓延遲有界，播放本身不破音。
        if pending.count >= maxPendingChunks {
            return
        }
        pending.append(buffer)

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

    /// 把一段 PCM 轉成 AVAudioPCMBuffer（依標頭格式與緩衝區佈局精確拷貝）。
    private func makeBuffer(pcm: Data, format: PeerConnection.AudioFormatInfo) -> AVAudioPCMBuffer? {
        let common: AVAudioCommonFormat = format.isFloat ? .pcmFormatFloat32 : .pcmFormatInt16
        guard let audioFormat = AVAudioFormat(commonFormat: common,
                                              sampleRate: format.sampleRate,
                                              channels: format.channels,
                                              interleaved: format.interleaved) else { return nil }

        // 關鍵：非交錯（non-interleaved）時 mBytesPerFrame 是「單聲道」每幀位元組數，
        // 不能直接用來算幀數（雙聲道資料會被算成 2 倍 → 半速播放 + 聲道串擾 + 吱吱聲）。
        let bytesPerSample = max(Int(format.bits) / 8, 1)
        let channelCount = max(Int(format.channels), 1)
        let frames = pcm.count / (channelCount * bytesPerSample)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat,
                                            frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)

        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard buffers.count > 0 else { return nil }
        pcm.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            guard let base = src.baseAddress else { return }
            if buffers.count == 1 {
                // 交錯（interleaved）：單一緩衝區一次拷貝整段
                guard let dst = buffers[0].mData else { return }
                buffers[0].mDataByteSize = UInt32(pcm.count)
                memcpy(dst, base, pcm.count)
            } else {
                // 非交錯（non-interleaved）：資料排列為 [L 全部][R 全部]，
                // 每個聲道各拷一份
                let channelBytes = frames * bytesPerSample
                for i in 0..<buffers.count {
                    guard let dst = buffers[i].mData else { continue }
                    let offset = i * channelBytes
                    guard offset + channelBytes <= pcm.count else { continue }
                    buffers[i].mDataByteSize = UInt32(channelBytes)
                    memcpy(dst, base + offset, channelBytes)
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
        player.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.queuedBuffers = max(self.queuedBuffers - 1, 0)
                // 播放佇列完全乾涸 → 節點已停止/將停止，重設預卷狀態，
                // 待下一個塊累積滿預卷再重新開播（避免碎塊反覆起停）
                if self.queuedBuffers == 0 { self.isPrimed = false }
            }
        }
        queuedBuffers += 1
        if !player.isPlaying { player.play() }
    }
}
