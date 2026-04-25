@preconcurrency import AVFoundation
import Foundation

public struct RollingAudioBuffer {
    private let maxSamples: Int
    private var samples: [Float]

    public init(maxSamples: Int) {
        self.maxSamples = Swift.max(0, maxSamples)
        self.samples = []
        self.samples.reserveCapacity(self.maxSamples)
    }

    public mutating func append(_ newSamples: [Float]) {
        guard maxSamples > 0, !newSamples.isEmpty else {
            return
        }

        samples.append(contentsOf: newSamples)

        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    public func snapshot() -> [Float] {
        samples
    }
}

public enum AudioCaptureServiceError: Error, LocalizedError {
    case microphonePermissionDenied
    case invalidInputFormat
    case converterCreationFailed
    case engineStartFailed(String)

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission denied"
        case .invalidInputFormat:
            return "Microphone input format is unavailable"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        case .engineStartFailed(let message):
            return "Failed to start audio engine: \(message)"
        }
    }
}

public final class AudioCaptureService: @unchecked Sendable {
    public var onSamples: (([Float]) -> Void)?

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(WhisperRuntimeDefaults.sampleRate),
        channels: 1,
        interleaved: false
    )!
    private let lock = NSLock()

    private var buffer: RollingAudioBuffer
    private var converter: AVAudioConverter?
    private(set) public var isRunning = false

    public init(maxSamples: Int = WhisperRuntimeDefaults.sampleRate * 8) {
        self.buffer = RollingAudioBuffer(maxSamples: maxSamples)
    }

    public func start() async throws {
        guard !isRunning else {
            return
        }

        let granted = await requestMicrophoneAccess()
        guard granted else {
            throw AudioCaptureServiceError.microphonePermissionDenied
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw AudioCaptureServiceError.invalidInputFormat
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureServiceError.converterCreationFailed
        }
        self.converter = converter

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.consume(buffer: buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            isRunning = true
        } catch {
            inputNode.removeTap(onBus: 0)
            self.converter = nil
            throw AudioCaptureServiceError.engineStartFailed(error.localizedDescription)
        }
    }

    public func stop() {
        guard isRunning else {
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        isRunning = false
    }

    public func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return buffer.snapshot()
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func consume(buffer inputBuffer: AVAudioPCMBuffer) {
        guard isRunning, let converter else {
            return
        }

        let convertedSamples = convert(buffer: inputBuffer, using: converter)
        guard !convertedSamples.isEmpty else {
            return
        }

        lock.lock()
        buffer.append(convertedSamples)
        lock.unlock()

        onSamples?(convertedSamples)
    }

    private func convert(buffer inputBuffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> [Float] {
        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(max(1, Int(ceil(Double(inputBuffer.frameLength) * ratio))))

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return []
        }

        let conversionState = ConversionState(inputBuffer: inputBuffer)
        var conversionError: NSError?

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if conversionState.didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            conversionState.didProvideInput = true
            outStatus.pointee = .haveData
            return conversionState.inputBuffer
        }

        converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)

        guard conversionError == nil,
              let channelData = outputBuffer.floatChannelData?[0] else {
            return []
        }

        let frameCount = Int(outputBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData, count: frameCount))
    }
}

private final class ConversionState: @unchecked Sendable {
    let inputBuffer: AVAudioPCMBuffer
    var didProvideInput = false

    init(inputBuffer: AVAudioPCMBuffer) {
        self.inputBuffer = inputBuffer
    }
}
