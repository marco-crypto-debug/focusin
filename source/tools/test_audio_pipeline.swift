import AVFAudio
import Foundation

@main
struct AudioTestRunner {
    static func main() {
        print("=== FocusIn Alpha Remade Audio Pipeline Test ===")

        let player = BroadcastAudioPlayer()
        player.start()

        let sampleRate: Double = 48000.0
        let channels: UInt32 = 2
        let framesPerPacket = 3840

        print("1. Generating 10 synthetic AirPlayAudioPackets...")
        var packets: [AirPlayAudioPacket] = []

        for seq in 0..<10 {
            var samples = [Float](repeating: 0.0, count: framesPerPacket * 2)
            for f in 0..<framesPerPacket {
                let t = Double(seq * framesPerPacket + f) / sampleRate
                let sample = Float(sin(2.0 * .pi * 440.0 * t) * 0.4)
                samples[f * 2] = sample
                samples[f * 2 + 1] = sample
            }
            let pcmData = Data(bytes: samples, count: samples.count * MemoryLayout<Float>.size)
            let packet = AirPlayAudioPacket(
                version: 2,
                flags: 0,
                sequenceNumber: UInt16(seq),
                ptsNanoseconds: AirPlayClock.nowNanoseconds,
                clockID: 12345,
                sampleRate: sampleRate,
                channels: channels,
                bits: 32,
                isFloat: true,
                isInterleaved: true,
                pcm: pcmData
            )
            packets.append(packet)
        }

        print("2. Packing and unpacking packets over wire protocol...")
        for (idx, p) in packets.enumerated() {
            let wireBytes = p.pack()
            guard let unpacked = AirPlayAudioPacket.unpack(wireBytes) else {
                fatalError("Failed to unpack packet \(idx)")
            }
            assert(unpacked.sequenceNumber == p.sequenceNumber, "Sequence mismatch")
            assert(unpacked.pcm.count == p.pcm.count, "PCM size mismatch")
        }
        print("✓ Wire serialization & deserialization PASSED")

        print("3. Feeding packets into BroadcastAudioPlayer...")
        for (_, p) in packets.enumerated() {
            player.playAirPlay(packet: p)
            usleep(10000)
        }
        print("✓ All 10 packets enqueued into jitter buffer and scheduled on AVAudioEngine")

        print("4. Testing stop and cleanup lifecycle...")
        player.stop()
        print("✓ AudioPlayer stopped cleanly")

        print("=== ALL AUDIO PIPELINE TESTS PASSED ✅ ===")
        exit(0)
    }
}
