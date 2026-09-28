import AVFAudio
import Foundation

/// 學生端廣播音訊播放器：將教師端送來的 PCM 緩衝區排入 AVAudioEngine 播放。
/// 格式由每幀標頭描述（取樣率/聲道/位深/浮點/交錯），引擎的轉換節點自動適配輸出裝置。
final class BroadcastAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isRunning = false

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
    }

    /// 播放一段 PCM。格式必須與標頭一致。
    func play(pcm: Data, format: PeerConnection.AudioFormatInfo) {
        if !isRunning { start() }
        guard isRunning, !pcm.isEmpty else { return }

        let common: AVAudioCommonFormat = format.isFloat ? .pcmFormatFloat32 : .pcmFormatInt16
        guard let audioFormat = AVAudioFormat(commonFormat: common,
                                              sampleRate: format.sampleRate,
                                              channels: format.channels,
                                              interleaved: format.interleaved) else { return }
        let bytesPerFrame = Int(audioFormat.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return }
        let frameCount = pcm.count / bytesPerFrame
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat,
                                            frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        // 依實際緩衝區數量（交錯=1，非交錯=聲道數）逐段拷貝
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard buffers.count > 0 else { return }
        pcm.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            guard let base = src.baseAddress else { return }
            for i in 0..<buffers.count {
                guard let dst = buffers[i].mData else { continue }
                let byteSize = Int(buffers[i].mDataByteSize)
                let offset = i * byteSize
                guard offset + byteSize <= pcm.count else { continue }
                memcpy(dst, base + offset, byteSize)
            }
        }

        player.scheduleBuffer(buffer)
        if !player.isPlaying { player.play() }
    }
}
