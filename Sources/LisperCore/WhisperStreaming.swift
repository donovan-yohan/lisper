import Foundation

public struct WhisperDependency: Equatable, Sendable {
    public let streamBinary: URL
    public let model: URL

    public init(streamBinary: URL, model: URL) {
        self.streamBinary = streamBinary
        self.model = model
    }
}

public enum WhisperStreamEvent: Equatable, Sendable {
    case started
    case transcript(String)
    case info(String)
    case stderr(String)
    case stopped
    case failed(String)
}

public struct WhisperStreamOutputParser {
    public init() {}

    public mutating func consume(_ line: String) -> WhisperStreamEvent? {
        let normalized = normalizeOutputChunk(line)
        guard !normalized.isEmpty else {
            return nil
        }

        if let transcript = parseTranscriptLine(normalized) {
            return .transcript(transcript)
        }

        if normalized.hasPrefix("stderr:") {
            return .stderr(normalized.dropFirst("stderr:".count).trimmingCharacters(in: .whitespaces))
        }

        if normalized.hasPrefix("info:") {
            return .info(normalized.dropFirst("info:".count).trimmingCharacters(in: .whitespaces))
        }

        if normalized == "[Start speaking]" || normalized.hasPrefix("[") || normalized.hasPrefix("### ") {
            return .info(normalized)
        }

        return .transcript(normalized)
    }

    private func parseTranscriptLine(_ line: String) -> String? {
        guard let closingBracketIndex = line.firstIndex(of: "]") else {
            return nil
        }

        let prefix = line[..<closingBracketIndex]
        guard prefix.hasPrefix("["),
              isTimestampRange(String(prefix)) else {
            return nil
        }

        let transcriptStart = line.index(after: closingBracketIndex)
        let transcript = line[transcriptStart...].trimmingCharacters(in: .whitespaces)
        return transcript.isEmpty ? nil : transcript
    }

    private func isTimestampRange(_ prefix: String) -> Bool {
        let pattern = #"^\[\d{2}:\d{2}:\d{2}\.\d{3}\s+-->\s+\d{2}:\d{2}:\d{2}\.\d{3}$"#
        return prefix.range(of: pattern, options: .regularExpression) != nil
    }

    private func normalizeOutputChunk(_ chunk: String) -> String {
        let withoutANSI = stripANSIEscapeSequences(from: chunk)

        return withoutANSI
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripANSIEscapeSequences(from text: String) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "\u{001B}" {
                let nextIndex = text.index(after: index)
                if nextIndex < text.endIndex, text[nextIndex] == "[" {
                    index = text.index(after: nextIndex)
                    while index < text.endIndex {
                        let character = text[index]
                        if character.isLetter {
                            index = text.index(after: index)
                            break
                        }
                        index = text.index(after: index)
                    }
                    continue
                }
            }

            result.append(text[index])
            index = text.index(after: index)
        }

        return result
    }
}

public enum WhisperDependencyResolverError: Error, Equatable, LocalizedError {
    case invalidOverride(key: String, value: String)
    case missingStreamBinary(candidates: [String])
    case missingModel(candidates: [String])

    public var errorDescription: String? {
        switch self {
        case .invalidOverride(let key, let value):
            return "Invalid value for \(key): \(value)"
        case .missingStreamBinary(let candidates):
            return "Could not find whisper-stream binary. Tried: \(candidates.joined(separator: ", "))"
        case .missingModel(let candidates):
            return "Could not find whisper model. Tried: \(candidates.joined(separator: ", "))"
        }
    }
}

public struct WhisperDependencyResolver {
    private let environment: [String: String]
    private let fileExists: (String) -> Bool

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.environment = environment
        self.fileExists = fileExists
    }

    public func resolve() throws -> WhisperDependency {
        let streamBinary = try resolvePath(
            envKey: "LISPER_WHISPER_STREAM",
            candidates: streamBinaryCandidates(),
            missingError: .missingStreamBinary(candidates: streamBinaryCandidates())
        )

        let model = try resolvePath(
            envKey: "LISPER_WHISPER_MODEL",
            candidates: modelCandidates(),
            missingError: .missingModel(candidates: modelCandidates())
        )

        return WhisperDependency(
            streamBinary: streamBinary,
            model: model
        )
    }

    private func resolvePath(
        envKey: String,
        candidates: [String],
        missingError: WhisperDependencyResolverError
    ) throws -> URL {
        if let override = environment[envKey] {
            guard fileExists(override) else {
                throw WhisperDependencyResolverError.invalidOverride(key: envKey, value: override)
            }
            return URL(fileURLWithPath: override)
        }

        for candidate in candidates {
            if fileExists(candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        throw missingError
    }

    private func streamBinaryCandidates() -> [String] {
        [
            ".tools/whisper.cpp/build/bin/whisper-stream",
            "/opt/homebrew/bin/whisper-stream",
            "/usr/local/bin/whisper-stream",
            "./whisper-stream"
        ]
    }

    private func modelCandidates() -> [String] {
        [
            ".tools/models/ggml-tiny.en.bin",
            "/opt/homebrew/share/lisper/ggml-base.en.bin",
            "/usr/local/share/lisper/ggml-base.en.bin",
            "./models/ggml-base.en.bin",
            "./ggml-base.en.bin"
        ]
    }

}

public protocol WhisperStreamingSession: AnyObject {
    var updates: AsyncStream<WhisperStreamEvent> { get }

    func start() throws
    func stop()
}

public protocol WhisperStreamingSessionFactory {
    func makeSession(using dependency: WhisperDependency) -> any WhisperStreamingSession
}
