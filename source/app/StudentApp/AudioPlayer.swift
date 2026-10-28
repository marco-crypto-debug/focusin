import AVFAudio
import Foundation

final class BroadcastAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let standardFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!

    private var isRunning = false
    private var isPrimed = false
    private var queuedBuffers = 0

    private var pending: [AVAudioPCMBuffer] = []
    private let preRollChunks = 2
    private let maxPendingChunks = 8
    private var inFlight: [AVAudioPCMBuffer] = []

    private let lock = NSRecursiveLock()
    private var lastSequenceNumber: UInt16?

    private var receivedCount = 0
    private var droppedCount = 0
    private var lastStatLogAt: TimeInterval = 0

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: standardFormat)
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return }
        do {
            try engine.start()
            player.play()
            isRunning = true
            isPrimed = false
            queuedBuffers = 0
            pending.removeAll()
            inFlight.removeAll()
            DiagLog.log("音訊引擎啟動成功（48kHz Stereo）")
        } catch {
            isRunning = false
            DiagLog.log("音訊引擎啟動失敗: \(error.localizedDescription)")
        }
    }

    func stop() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        isRunning = false
        isPrimed = false
        queuedBuffers = 0
        pending.removeAll()
        lastSequenceNumber = nil
        lock.unlock()

        player.stop()
        engine.stop()

        lock.lock()
        inFlight.removeAll()
        lock.unlock()

        DiagLog.log("音訊引擎已停止")
    }

    func playAirPlay(packet: AirPlayAudioPacket) {
        if !isRunning { start() }
        guard isRunning, !packet.pcm.isEmpty else { return }

        lock.lock()
        if let last = lastSequenceNumber {
            let diff = packet.sequenceNumber &- last
            if diff > 1 && diff < 30000 {
                droppedCount += Int(diff - 1)
            }
        }
        lastSequenceNumber = packet.sequenceNumber
        lock.unlock()

        enqueue(pcm: packet.pcm,
                channels: packet.channels,
                bits: packet.bits,
                isFloat: packet.isFloat,
                interleaved: packet.isInterleaved)
    }

    func play(pcm: Data, format: PeerConnection.AudioFormatInfo) {
        if !isRunning { start() }
        guard isRunning, !pcm.isEmpty else { return }

        enqueue(pcm: pcm,
                channels: format.channels,
                bits: format.bits,
                isFloat: format.isFloat,
                interleaved: format.interleaved)
    }

    private func enqueue(pcm: Data, channels: UInt32, bits: UInt8, isFloat: Bool, interleaved: Bool) {
        let chCount = Int(max(channels, 1))
        let bytesPerSample = max(Int(bits) / 8, 1)
        let frameSize = chCount * bytesPerSample
        guard frameSize > 0 else { return }
        let frames = pcm.count / frameSize
        guard frames > 0 else { return }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: standardFormat, frameCapacity: AVAudioFrameCount(frames)) else {
            lock.lock()
            droppedCount += 1
            lock.unlock()
            return
        }
        buffer.frameLength = AVAudioFrameCount(frames)

        guard let left = buffer.floatChannelData?[0], let right = buffer.floatChannelData?[1] else {
            lock.lock()
            droppedCount += 1
            lock.unlock()
            return
        }

        pcm.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            if isFloat && bits == 32 {
                let fPtr = base.assumingMemoryBound(to: Float.self)
                if interleaved && chCount >= 2 {
                    for f in 0..<frames {
                        left[f] = fPtr[f * 2]
                        right[f] = fPtr[f * 2 + 1]
                    }
                } else if !interleaved && chCount >= 2 {
                    let rPtr = fPtr + frames
                    for f in 0..<frames {
                        left[f] = fPtr[f]
                        right[f] = rPtr[f]
                    }
                } else {
                    for f in 0..<frames {
                        let s = fPtr[f]
                        left[f] = s
                        right[f] = s
                    }
                }
            } else if bits == 16 {
                let iPtr = base.assumingMemoryBound(to: Int16.self)
                let scale: Float = 1.0 / 32768.0
                if interleaved && chCount >= 2 {
                    for f in 0..<frames {
                        left[f] = Float(iPtr[f * 2]) * scale
                        right[f] = Float(iPtr[f * 2 + 1]) * scale
                    }
                } else if !interleaved && chCount >= 2 {
                    let rPtr = iPtr + frames
                    for f in 0..<frames {
                        left[f] = Float(iPtr[f]) * scale
                        right[f] = Float(rPtr[f]) * scale
                    }
                } else {
                    for f in 0..<frames {
                        let s = Float(iPtr[f]) * scale
                        left[f] = s
                        right[f] = s
                    }
                }
            }
        }

        lock.lock()
        defer { lock.unlock() }

        if pending.count >= maxPendingChunks {
            droppedCount += 1
            return
        }
        pending.append(buffer)
        receivedCount += 1

        let now = Date().timeIntervalSinceReferenceDate
        if now - lastStatLogAt > 3 {
            lastStatLogAt = now
            DiagLog.log("音訊播放狀態: 收到=\(receivedCount) 遺漏=\(droppedCount) 待播=\(pending.count) 在飛=\(inFlight.count)")
        }

        if !isPrimed {
            guard pending.count >= preRollChunks else { return }
            isPrimed = true
            while !pending.isEmpty {
                scheduleLocked(pending.removeFirst())
            }
        } else if !pending.isEmpty {
            scheduleLocked(pending.removeFirst())
        }
    }

    private func scheduleLocked(_ buffer: AVAudioPCMBuffer) {
        inFlight.append(buffer)
        queuedBuffers += 1
        player.scheduleBuffer(buffer) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.queuedBuffers = max(self.queuedBuffers - 1, 0)
            self.inFlight.removeAll { $0 === buffer }
            if self.queuedBuffers == 0 {
                self.isPrimed = false
            }
            self.lock.unlock()
        }
        if !player.isPlaying {
            player.play()
        }
    }
}
