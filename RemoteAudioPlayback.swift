import AVFoundation
import Foundation

/// Minimal low-latency playback path for the Landline prototype.
/// Network packets contain mono Int16 PCM. They are expanded to Float32 PCM
/// and scheduled on an AVAudioPlayerNode; AVAudioEngine handles conversion to
/// the Mac's current output device format.
@MainActor
final class RemoteAudioPlayback {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var configuredSampleRate: Double?
    private var outputVolume: Float = 0.25

    init() {
        engine.attach(player)
    }

    func setVolume(_ value: Double) {
        outputVolume = Float(max(0, min(1, value)))
        player.volume = outputVolume
    }

    func enqueueNetworkPacket(_ data: Data) {
        guard data.count >= 8 else { return }

        guard let sampleRateValue = readUInt32LE(data, offset: 0),
              let frameCountValue = readUInt32LE(data, offset: 4)
        else { return }

        let sampleRate = Double(sampleRateValue)
        let frameCount = Int(frameCountValue)
        guard sampleRate > 0, frameCount > 0 else { return }

        let payloadBytes = frameCount * MemoryLayout<Int16>.size
        guard data.count >= 8 + payloadBytes else { return }

        do {
            try ensureConfigured(sampleRate: sampleRate)
        } catch {
            NSLog("Landline remote playback setup failed: %@", error.localizedDescription)
            return
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ),
              let output = buffer.floatChannelData?[0]
        else { return }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        for index in 0..<frameCount {
            let byteOffset = 8 + (index * 2)
            let low = UInt16(data[byteOffset])
            let high = UInt16(data[byteOffset + 1]) << 8
            let sample = Int16(bitPattern: low | high)
            output[index] = Float(sample) / Float(Int16.max)
        }

        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    func reset() {
        player.stop()
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
        configuredSampleRate = nil
    }

    private func ensureConfigured(sampleRate: Double) throws {
        if configuredSampleRate == sampleRate, engine.isRunning {
            return
        }

        player.stop()
        if engine.isRunning {
            engine.stop()
        }
        engine.disconnectNodeOutput(player)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw PlaybackError.invalidFormat
        }

        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        player.volume = outputVolume
        configuredSampleRate = sampleRate
    }

    private func readUInt32LE(_ data: Data, offset: Int) -> UInt32? {
        guard data.count >= offset + 4 else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private enum PlaybackError: Error {
        case invalidFormat
    }
}
