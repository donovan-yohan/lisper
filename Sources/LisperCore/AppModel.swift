import Foundation
import Combine

public enum AppPhase: Equatable {
    case idle
    case starting
    case recording
    case stopping
    case failed
}

public struct AppSessionToken: Equatable, Hashable {
    fileprivate let rawValue: UInt64
}

public protocol WhisperDependencyResolving {
    func resolve() throws -> WhisperDependency
}

extension WhisperDependencyResolver: WhisperDependencyResolving {}

@MainActor
public final class LisperAppModel: ObservableObject {
    @Published public private(set) var phase: AppPhase = .idle
    @Published public private(set) var transcriptText: String = ""
    @Published public private(set) var statusText: String = "Idle"
    @Published public private(set) var diagnosticsText: String = ""

    private let dependencyResolver: any WhisperDependencyResolving
    private let sessionFactory: any WhisperStreamingSessionFactory
    private var activeSession: (any WhisperStreamingSession)?
    private var activeSessionToken: AppSessionToken?
    private var nextSessionIdentifier: UInt64 = 0
    private var committedTranscript: String = ""
    private var liveTranscriptTail: String = ""

    public init(
        dependencyResolver: any WhisperDependencyResolving,
        sessionFactory: any WhisperStreamingSessionFactory
    ) {
        self.dependencyResolver = dependencyResolver
        self.sessionFactory = sessionFactory
    }

    public func startRecording() async throws -> AppSessionToken {
        if phase == .starting || phase == .recording {
            guard let activeSessionToken else {
                fatalError("Recording phase without active session token")
            }
            return activeSessionToken
        }

        resetTranscriptState()
        phase = .starting
        statusText = "Starting recording"
        diagnosticsText = ""

        let token = makeSessionToken()

        let dependency: WhisperDependency
        let session: any WhisperStreamingSession
        do {
            dependency = try dependencyResolver.resolve()
            session = sessionFactory.makeSession(using: dependency)
        } catch {
            phase = .failed
            statusText = "Failed to start recording"
            diagnosticsText = error.localizedDescription
            activeSession = nil
            activeSessionToken = nil
            throw error
        }

        activeSession = session
        activeSessionToken = token

        do {
            try session.start()
        } catch {
            session.stop()
            activeSession = nil
            activeSessionToken = nil
            phase = .failed
            statusText = "Failed to start recording"
            diagnosticsText = error.localizedDescription
            throw error
        }

        phase = .recording
        statusText = "Recording"
        return token
    }

    public func stopRecording() {
        guard phase != .idle else {
            return
        }

        commitLiveTranscriptTail()
        phase = .stopping
        statusText = "Stopping recording"
        activeSession?.stop()
        activeSession = nil
        activeSessionToken = nil
        phase = .idle
        statusText = "Idle"
    }

    public func handle(_ event: WhisperStreamEvent, from sessionToken: AppSessionToken) async {
        guard sessionToken == activeSessionToken else {
            return
        }

        switch event {
        case .started:
            phase = .recording
            statusText = "Recording"
            diagnosticsText = ""
        case .transcript(let transcript):
            applyLiveTranscript(transcript, from: sessionToken)
        case .info(let message):
            statusText = message
        case .stderr(let message):
            diagnosticsText = message
        case .stopped:
            commitLiveTranscriptTail()
            activeSession = nil
            activeSessionToken = nil
            phase = .idle
            statusText = "Idle"
        case .failed(let message):
            commitLiveTranscriptTail()
            phase = .failed
            statusText = "Recording failed"
            diagnosticsText = message
            activeSession?.stop()
            activeSession = nil
            activeSessionToken = nil
        }
    }

    public func reportDiagnostic(_ message: String) {
        diagnosticsText = message
    }

    public func beginInProcessRecording() -> AppSessionToken {
        let token = makeSessionToken()
        activeSessionToken = token
        resetTranscriptState()
        phase = .starting
        statusText = "Starting recording"
        diagnosticsText = ""
        return token
    }

    public func markRecordingActive(for sessionToken: AppSessionToken) {
        guard sessionToken == activeSessionToken else {
            return
        }

        phase = .recording
        statusText = "Recording"
    }

    public func finishRecording(for sessionToken: AppSessionToken) {
        guard sessionToken == activeSessionToken else {
            return
        }

        commitLiveTranscriptTail()
        activeSession = nil
        activeSessionToken = nil
        phase = .idle
        statusText = "Idle"
    }

    public func failRecording(for sessionToken: AppSessionToken?, message: String) {
        if let sessionToken, sessionToken != activeSessionToken {
            return
        }

        commitLiveTranscriptTail()
        activeSession?.stop()
        activeSession = nil
        activeSessionToken = nil
        phase = .failed
        statusText = "Recording failed"
        diagnosticsText = message
    }

    public func applyLiveTranscript(_ transcript: String, from sessionToken: AppSessionToken) {
        applyTranscript(transcript, from: sessionToken)
    }

    public func applyTranscriptSnapshot(_ transcript: String, from sessionToken: AppSessionToken) {
        applyTranscript(transcript, from: sessionToken)
    }

    private func applyTranscript(_ transcript: String, from sessionToken: AppSessionToken) {
        guard sessionToken == activeSessionToken else {
            return
        }

        mergeTranscriptSnapshot(transcript)
        if phase == .recording || phase == .starting {
            statusText = "Recording"
        }
    }

    private func mergeTranscriptSnapshot(_ transcript: String) {
        let normalizedTranscript = normalizeTranscript(transcript)
        guard !normalizedTranscript.isEmpty else {
            return
        }

        if liveTranscriptTail.isEmpty {
            liveTranscriptTail = trimOverlapWithCommittedTranscript(from: normalizedTranscript)
            rebuildTranscriptText()
            return
        }

        if sharesLeadingWords(liveTranscriptTail, normalizedTranscript) {
            liveTranscriptTail = normalizedTranscript
        } else {
            commitLiveTranscriptTail()
            liveTranscriptTail = trimOverlapWithCommittedTranscript(from: normalizedTranscript)
        }

        rebuildTranscriptText()
    }

    private func commitLiveTranscriptTail() {
        let normalizedTail = normalizeTranscript(liveTranscriptTail)
        guard !normalizedTail.isEmpty else {
            liveTranscriptTail = ""
            rebuildTranscriptText()
            return
        }

        if committedTranscript.isEmpty {
            committedTranscript = normalizedTail
        } else {
            committedTranscript += " " + normalizedTail
        }
        liveTranscriptTail = ""
        rebuildTranscriptText()
    }

    private func resetTranscriptState() {
        committedTranscript = ""
        liveTranscriptTail = ""
        transcriptText = ""
    }

    private func rebuildTranscriptText() {
        transcriptText = [committedTranscript, liveTranscriptTail]
            .map(normalizeTranscript)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func trimOverlapWithCommittedTranscript(from transcript: String) -> String {
        let committedWords = normalizeTranscript(committedTranscript).split(separator: " ")
        let transcriptWords = transcript.split(separator: " ")
        let overlapCount = overlapWordCount(suffixWords: committedWords, prefixWords: transcriptWords)
        return transcriptWords.dropFirst(overlapCount).joined(separator: " ")
    }

    private func sharesLeadingWords(_ currentTail: String, _ newTranscript: String) -> Bool {
        let normalizedCurrentTail = normalizeTranscript(currentTail)
        let normalizedNewTranscript = normalizeTranscript(newTranscript)

        if normalizedCurrentTail.hasPrefix(normalizedNewTranscript)
            || normalizedNewTranscript.hasPrefix(normalizedCurrentTail) {
            return true
        }

        let currentWords = normalizedCurrentTail.split(separator: " ")
        let newWords = normalizedNewTranscript.split(separator: " ")
        guard !currentWords.isEmpty, !newWords.isEmpty else {
            return false
        }

        let prefixCount = zip(currentWords, newWords)
            .prefix { $0 == $1 }
            .count

        return prefixCount > 0
    }

    private func overlapWordCount(
        suffixWords: [Substring],
        prefixWords: [Substring]
    ) -> Int {
        guard !suffixWords.isEmpty, !prefixWords.isEmpty else {
            return 0
        }

        let maxOverlap = min(suffixWords.count, prefixWords.count)
        for overlapCount in stride(from: maxOverlap, through: 1, by: -1) {
            if Array(suffixWords.suffix(overlapCount)) == Array(prefixWords.prefix(overlapCount)) {
                return overlapCount
            }
        }

        return 0
    }

    private func normalizeTranscript(_ transcript: String) -> String {
        transcript
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func makeSessionToken() -> AppSessionToken {
        nextSessionIdentifier &+= 1
        return AppSessionToken(rawValue: nextSessionIdentifier)
    }
}
