import Foundation
import CWhisper

public enum WhisperRuntimeDefaults {
    public static let sampleRate: Int = 16_000
    public static let windowDurationSeconds: Double = 5.0
    public static let updateIntervalSeconds: Double = 1.0
    public static let languageCode = "en"
    public static let threadCount: Int = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
}

public struct WhisperTranscriptNormalizer {
    public static func normalize(_ segments: [String]) -> String {
        segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public enum WhisperLibraryTranscriberError: Error, LocalizedError {
    case modelLoadFailed(String)
    case transcriptionFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path):
            return "Failed to load whisper model at \(path)"
        case .transcriptionFailed(let code):
            return "whisper_full failed with code \(code)"
        }
    }
}

public final class WhisperLibraryTranscriber: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var modelURL: URL
        public var languageCode: String
        public var sampleRate: Int
        public var windowDurationSeconds: Double
        public var updateIntervalSeconds: Double

        public init(
            modelURL: URL,
            languageCode: String = WhisperRuntimeDefaults.languageCode,
            sampleRate: Int = WhisperRuntimeDefaults.sampleRate,
            windowDurationSeconds: Double = WhisperRuntimeDefaults.windowDurationSeconds,
            updateIntervalSeconds: Double = WhisperRuntimeDefaults.updateIntervalSeconds
        ) {
            self.modelURL = modelURL
            self.languageCode = languageCode
            self.sampleRate = sampleRate
            self.windowDurationSeconds = windowDurationSeconds
            self.updateIntervalSeconds = updateIntervalSeconds
        }
    }

    public let configuration: Configuration
    public private(set) var context: OpaquePointer?

    public init(configuration: Configuration) throws {
        self.configuration = configuration

        var contextParams = whisper_context_default_params()
        contextParams.use_gpu = true
        contextParams.flash_attn = true

        let modelPath = configuration.modelURL.path
        guard let ctx = modelPath.withCString({ whisper_init_from_file_with_params($0, contextParams) }) else {
            throw WhisperLibraryTranscriberError.modelLoadFailed(modelPath)
        }

        context = ctx
    }

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    public static var libraryVersion: String {
        guard let version = whisper_version() else {
            return ""
        }
        return String(cString: version)
    }

    public func transcribe(samples: [Float]) throws -> String {
        guard let context, !samples.isEmpty else {
            return ""
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_special = false
        params.print_realtime = false
        params.print_timestamps = false
        params.no_timestamps = true
        params.single_segment = true
        params.no_context = true
        params.max_tokens = 32
        params.n_threads = Int32(WhisperRuntimeDefaults.threadCount)

        let result = try configuration.languageCode.withCString { languagePointer in
            params.language = languagePointer
            return try samples.withUnsafeBufferPointer { buffer in
                let code = whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
                guard code == 0 else {
                    throw WhisperLibraryTranscriberError.transcriptionFailed(code)
                }

                let segmentCount = Int(whisper_full_n_segments(context))
                let segments = (0..<segmentCount).compactMap { index -> String? in
                    guard let text = whisper_full_get_segment_text(context, Int32(index)) else {
                        return nil
                    }

                    return String(cString: text)
                }

                return WhisperTranscriptNormalizer.normalize(segments)
            }
        }

        return result
    }
}
