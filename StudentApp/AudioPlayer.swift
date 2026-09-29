import AVFAudio
import Foundation

/// 學生端廣播音訊播放器：將教師端送來的 PCM 緩衝區排入 AVAudioEngine 播放。
/// 格式由每幀標頭描述（取樣率/聲道/位深/浮點/交錯），引擎的轉換節點自動適配輸出裝置。
final class BroadcastAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isRunning = false
    /// 已排入節點、尚未播完的緩衝塊數（用於延遲保護）。
    private var queuedBuffers = 0

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
    }

    /// 播放一段 PCM。格式必須與標頭一致。
    func play(pcm: Data, format: PeerConnection.AudioFormatInfo) {
        if !isRunning { start() }
        guard isRunning, !pcm.isEmpty else { return }

        // 延遲保護：已排程但未播完的緩衝超過 4 塊（≈320ms）時，丟棄新到的資料，
        // 避免網路抖動造成延遲無限累積（寧可短暫丟聲，也不要越拖越慢）。
        guard queuedBuffers < 4 else { return }

        let common: AVAudioCommonFormat = format.isFloat ? .pcmFormatFloat32 : .pcmFormatInt16
        guard let audioFormat = AVAudioFormat(commonFormat: common,
                                              sampleRate: format.sampleRate,
                                              channels: format.channels,
                                              interleaved: format.interleaved) else { return }

        // 關鍵：非交錯（non-interleaved）時 mBytesPerFrame 是「單聲道」每幀位元組數，
        // 不能直接用來算幀數（雙聲道資料會被算成 2 倍 → 半速播放 + 聲道串擾 + 吱吱聲）。
        let bytesPerSample = max(Int(format.bits) / 8, 1)
        let channelCount = max(Int(format.channels), 1)
        let frames = pcm.count / (channelCount * bytesPerSample)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat,
                                            frameCapacity: AVAudioFrameCount(frames)) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)

        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard buffers.count > 0 else { return }
        pcm.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            guard let base = src.baseAddress else { return }
            if buffers.count == 1 {
                // 交錯（interleaved）：單一緩衝區一次拷貝整段
                guard let dst = buffers[0].mData else { return }
                buffers[0].mDataByteSize = UInt32(pcm.count)
                memcpy(dst, base, pcm.count)
            } else {
                // 非交錯（non-interleaved）：資料排列為 [L 全部][R 全部]，
                // 每個聲道各拷一份（幀數按 聲道數×每採樣位元組 正確計算）
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

        player.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.queuedBuffers = max(self.queuedBuffers - 1, 0)
            }
        }
        queuedBuffers += 1
        if !player.isPlaying { player.play() }
    }
}
