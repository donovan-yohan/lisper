enum TextMutationOperation: Equatable {
    case insert(String)
    case replaceOwnedSpan(with: String)
    case appendFinal(String)
    case fallbackToFinalAppend(String)
}

enum RewriteUnsupportedError: Error, Equatable {
    case unsupported
}

public protocol TextSink: AnyObject {
    var text: String { get }

    func insert(_ text: String) async throws
    func replaceOwnedSpan(with text: String) async throws
    func appendFinal(_ text: String) async throws
}

private protocol FinalAppendFallbackRecording: AnyObject {
    func markFinalAppendFallback()
}

public final class FocusedTextFieldOutputTarget: OutputTarget {
    private let sink: TextSink
    private var ownsSpan = false
    private var rewriteUnsupported = false

    public init(sink: TextSink) {
        self.sink = sink
    }

    public func handle(_ event: TranscriptEvent) async throws {
        switch event {
        case .partial(let text):
            try await handlePartial(text)
        case .final(let text):
            try await handleFinal(text)
        }
    }

    private func handlePartial(_ text: String) async throws {
        if rewriteUnsupported {
            try await sink.appendFinal(text)
            return
        }

        if ownsSpan {
            do {
                try await sink.replaceOwnedSpan(with: text)
            } catch RewriteUnsupportedError.unsupported {
                try await appendWithStickyFallback(text)
                rewriteUnsupported = true
                ownsSpan = false
            }
            return
        }

        try await sink.insert(text)
        ownsSpan = true
    }

    private func handleFinal(_ text: String) async throws {
        if rewriteUnsupported {
            try await sink.appendFinal(text)
            ownsSpan = false
            return
        }

        if ownsSpan {
            do {
                try await sink.replaceOwnedSpan(with: text)
            } catch RewriteUnsupportedError.unsupported {
                try await appendWithStickyFallback(text)
                rewriteUnsupported = true
            }
            ownsSpan = false
            return
        }

        try await sink.appendFinal(text)
        ownsSpan = false
    }

    private func appendWithStickyFallback(_ text: String) async throws {
        if let fallbackRecorder = sink as? FinalAppendFallbackRecording {
            fallbackRecorder.markFinalAppendFallback()
        }
        try await sink.appendFinal(text)
    }
}

final class SimulatedTextSink: TextSink, FinalAppendFallbackRecording {
    enum RewriteFailureMode: Equatable {
        case unsupported
        case unexpected
    }

    enum SimulatedError: Error, Equatable {
        case noOwnedSpan
        case unexpectedRewriteFailure
    }

    private(set) var text: String
    private(set) var operations: [TextMutationOperation] = []
    private(set) var didFallbackToFinalAppend = false

    private let rewriteFailureMode: RewriteFailureMode?
    private var ownedRange: Range<String.Index>?
    private var pendingFinalAppendFallback = false

    init(initialText: String = "", rewriteFailureMode: RewriteFailureMode? = nil) {
        text = initialText
        self.rewriteFailureMode = rewriteFailureMode
    }

    func insert(_ text: String) async throws {
        let insertionStart = self.text.endIndex
        self.text.append(text)
        let insertionEnd = self.text.endIndex
        ownedRange = insertionStart..<insertionEnd
        operations.append(.insert(text))
    }

    func replaceOwnedSpan(with text: String) async throws {
        switch rewriteFailureMode {
        case .unsupported:
            throw RewriteUnsupportedError.unsupported
        case .unexpected:
            throw SimulatedError.unexpectedRewriteFailure
        case .none:
            break
        }

        guard let ownedRange else {
            throw SimulatedError.noOwnedSpan
        }

        let insertionStart = ownedRange.lowerBound
        self.text.replaceSubrange(ownedRange, with: text)
        let insertionEnd = self.text.index(insertionStart, offsetBy: text.count)
        self.ownedRange = insertionStart..<insertionEnd
        operations.append(.replaceOwnedSpan(with: text))
    }

    func appendFinal(_ text: String) async throws {
        self.text.append(text)
        ownedRange = nil
        if pendingFinalAppendFallback {
            didFallbackToFinalAppend = true
            operations.append(.fallbackToFinalAppend(text))
            pendingFinalAppendFallback = false
        } else {
            operations.append(.appendFinal(text))
        }
    }

    func markFinalAppendFallback() {
        pendingFinalAppendFallback = true
    }
}
