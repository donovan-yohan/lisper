import Foundation

public enum TranscriptTextSource: Equatable, Sendable {
    case original
    case enhanced
}

public enum CleanupState: Equatable, Sendable {
    case disabled
    case processing
    case succeeded(String)
    case failed(String)
}

public struct TranscriptResult: Equatable, Sendable {
    public var original: String
    public var cleanup: CleanupState

    public init(original: String, cleanup: CleanupState) {
        self.original = original
        self.cleanup = cleanup
    }

    public var enhancedText: String? {
        if case .succeeded(let text) = cleanup {
            return text
        }
        return nil
    }

    public var preferredText: String {
        enhancedText ?? original
    }

    public var preferredSource: TranscriptTextSource {
        enhancedText == nil ? .original : .enhanced
    }
}

public struct CopyFeedbackEvent: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var source: TranscriptTextSource
    public var message: String

    public init(id: UUID = UUID(), source: TranscriptTextSource, message: String) {
        self.id = id
        self.source = source
        self.message = message
    }
}
