import AVFoundation
import Combine
import Foundation

/// One microphone buffer prepared for the Landline network transport.
/// The prototype sends mono, signed 16-bit PCM at the microphone's native
/// sample rate. The transport treats the binary PCM packet as opaque payload data.
struct CapturedAudioFrame: Sendable {
    let sampleRate: UInt32
    let frameCount: UInt32
    let pcm16Mono: Data

    /// Binary wire format (little endian):
    /// [sampleRate UInt32][frameCount UInt32][mono Int16 PCM...]
    var networkPacket: Data {
        var data = Data(capacity: 8 + pcm16Mono.count)
        var rate = sampleRate.littleEndian
        var count = frameCount.littleEndian
        withUnsafeBytes(of: &rate) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        data.append(pcm16Mono)
        return data
    }
}

/// Thread-safe bridge between AVAudioEngine's realtime callback and the
/// MainActor-owned SwiftUI model. The audio callback never touches
/// ObservableObject state directly.
private final class AudioLevelMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedLevel: Double = 0

    func store(_ level: Double) {
        lock.lock()
        storedLevel = level
        lock.unlock()
    }

    func load() -> Double {
        lock.lock()
        let value = storedLevel
        lock.unlock()
        return value
    }

    func reset() {
        store(0)
    }
}

/// A small bounded queue between Core Audio's realtime callback and the
/// network sender. If networking stalls, old frames are discarded rather
/// than allowing latency to grow without bound.
private final class AudioPacketMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [CapturedAudioFrame] = []
    private let maximumFrames = 12

    func append(_ frame: CapturedAudioFrame) {
        lock.lock()
        if frames.count >= maximumFrames {
            frames.removeFirst(frames.count - maximumFrames + 1)
        }
        frames.append(frame)
        lock.unlock()
    }

    func drain() -> [CapturedAudioFrame] {
        lock.lock()
        let result = frames
        frames.removeAll(keepingCapacity: true)
        lock.unlock()
        return result
    }

    func reset() {
        lock.lock()
        frames.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

/// Owns AVAudioEngine outside the MainActor-isolated ObservableObject.
///
/// AVAudioEngine invokes its input tap on a realtime audio queue. Keeping the
/// closure in this nonisolated worker avoids Swift 6 main-actor queue asserts.
private final class AudioEngineWorker: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var tapInstalled = false

    var isRunning: Bool { engine.isRunning }

    func start(levelMailbox: AudioLevelMailbox, packetMailbox: AudioPacketMailbox) throws {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw MicrophoneCapture.MicrophoneError.noInputFormat
        }

        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let result = Self.analyzeAndEncode(buffer)
            levelMailbox.store(result.level)
            if let frame = result.frame {
                packetMailbox.append(frame)
            }
        }
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            if tapInstalled {
                input.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.reset()
            throw error
        }
    }

    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
    }

    private static func analyzeAndEncode(_ buffer: AVAudioPCMBuffer) -> (level: Double, frame: CapturedAudioFrame?) {
        guard let channelData = buffer.floatChannelData else { return (0, nil) }

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 0, frameCount > 0 else { return (0, nil) }

        var sumSquares: Double = 0
        var monoSamples = [Int16](repeating: 0, count: frameCount)

        for frame in 0..<frameCount {
            var mono: Float = 0
            for channel in 0..<channelCount {
                let sample = channelData[channel][frame]
                mono += sample
                let sampleDouble = Double(sample)
                sumSquares += sampleDouble * sampleDouble
            }
            mono /= Float(channelCount)
            let clamped = max(-1.0, min(1.0, mono))
            monoSamples[frame] = Int16(clamped * Float(Int16.max))
        }

        let sampleCount = frameCount * channelCount
        let rms = sqrt(sumSquares / Double(max(sampleCount, 1)))
        let decibels = 20 * log10(max(rms, 0.000_001))
        let normalized = max(0, min(1, (decibels + 52) / 52))
        let level = normalized < 0.045 ? 0 : normalized

        let pcm = monoSamples.withUnsafeBytes { Data($0) }
        let sampleRate = UInt32(max(1, min(Double(UInt32.max), buffer.format.sampleRate.rounded())))
        let frame = CapturedAudioFrame(
            sampleRate: sampleRate,
            frameCount: UInt32(frameCount),
            pcm16Mono: pcm
        )
        return (level, frame)
    }
}

@MainActor
final class MicrophoneCapture: ObservableObject {
    enum PermissionState: Equatable {
        case undetermined
        case granted
        case denied
    }

    enum MicrophoneError: Error {
        case noInputFormat
    }

    @Published private(set) var level: Double = 0
    @Published private(set) var permissionState: PermissionState = .undetermined
    @Published private(set) var isCapturing = false
    @Published private(set) var errorMessage: String?

    private let worker = AudioEngineWorker()
    private let levelMailbox = AudioLevelMailbox()
    private let packetMailbox = AudioPacketMailbox()
    private var meterTask: Task<Void, Never>?

    init() {
        permissionState = Self.currentPermissionState()
    }

    /// Requests microphone permission if needed, then starts hardware capture.
    func beginCapture() async -> Bool {
        errorMessage = nil

        guard await ensurePermission() else {
            level = 0
            return false
        }

        if isCapturing {
            return true
        }

        do {
            levelMailbox.reset()
            packetMailbox.reset()
            try worker.start(levelMailbox: levelMailbox, packetMailbox: packetMailbox)
            isCapturing = true
            startMeterPolling()
            return true
        } catch {
            errorMessage = "Microphone unavailable"
            stopCapture()
            NSLog("Landline microphone start failed: %@", error.localizedDescription)
            return false
        }
    }

    func stopCapture() {
        meterTask?.cancel()
        meterTask = nil

        worker.stop()
        isCapturing = false
        levelMailbox.reset()
        packetMailbox.reset()
        level = 0
    }

    /// Called by the network send pump on the MainActor. The realtime audio
    /// callback only appends into the mailbox; Network work never occurs on
    /// Core Audio's realtime thread.
    func drainNetworkFrames() -> [CapturedAudioFrame] {
        packetMailbox.drain()
    }

    private func ensurePermission() async -> Bool {
        switch Self.currentPermissionState() {
        case .granted:
            permissionState = .granted
            return true
        case .denied:
            permissionState = .denied
            errorMessage = "Microphone access required"
            return false
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            permissionState = granted ? .granted : .denied
            if !granted {
                errorMessage = "Microphone access required"
            }
            return granted
        }
    }

    private static func currentPermissionState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .undetermined
        @unknown default:
            return .undetermined
        }
    }

    private func startMeterPolling() {
        meterTask?.cancel()
        meterTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { break }

                let sample = self.levelMailbox.load()

                // Fast attack, slower release for a readable segmented VU.
                if sample >= self.level {
                    self.level = (self.level * 0.20) + (sample * 0.80)
                } else {
                    self.level = (self.level * 0.72) + (sample * 0.28)
                }

                if self.level < 0.01 {
                    self.level = 0
                }
            }
        }
    }
}
