import Foundation

public enum DemoTargetKind: Equatable {
    case modal
    case focusedTextField
}

public enum DemoFocusedTargetBehavior: Equatable {
    case rewriteSuccess
    case fallback
}

public struct DemoConfiguration: Equatable {
    public let mode: TranscriptionMode
    public let targetKind: DemoTargetKind
    public let focusedTargetBehavior: DemoFocusedTargetBehavior

    public init(
        mode: TranscriptionMode,
        targetKind: DemoTargetKind,
        focusedTargetBehavior: DemoFocusedTargetBehavior = .rewriteSuccess
    ) {
        self.mode = mode
        self.targetKind = targetKind
        self.focusedTargetBehavior = focusedTargetBehavior
    }
}

public struct DemoArgumentParser {
    public init() {}

    public func parse(_ arguments: [String]) throws -> DemoConfiguration {
        var mode: TranscriptionMode = .live
        var targetKind: DemoTargetKind = .modal
        var focusedTargetBehavior: DemoFocusedTargetBehavior = .rewriteSuccess
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--mode":
                guard let value = iterator.next() else {
                    throw DemoArgumentError.missingValue(flag: "--mode")
                }
                mode = try parseMode(value)
            case "--target":
                guard let value = iterator.next() else {
                    throw DemoArgumentError.missingValue(flag: "--target")
                }
                targetKind = try parseTargetKind(value)
            case "--fallback":
                focusedTargetBehavior = .fallback
            default:
                if argument.hasPrefix("--mode=") {
                    mode = try parseMode(String(argument.dropFirst("--mode=".count)))
                } else if argument.hasPrefix("--target=") {
                    targetKind = try parseTargetKind(String(argument.dropFirst("--target=".count)))
                } else {
                    throw DemoArgumentError.unknownArgument(argument)
                }
            }
        }

        return DemoConfiguration(
            mode: mode,
            targetKind: targetKind,
            focusedTargetBehavior: focusedTargetBehavior
        )
    }

    private func parseMode(_ value: String) throws -> TranscriptionMode {
        switch value.lowercased() {
        case "live":
            return .live
        case "finalonly", "final-only":
            return .finalOnly
        default:
            throw DemoArgumentError.invalidValue(flag: "--mode", value: value, expected: "live or finalOnly")
        }
    }

    private func parseTargetKind(_ value: String) throws -> DemoTargetKind {
        switch value.lowercased() {
        case "modal":
            return .modal
        case "focusedtextfield", "focused-text-field", "focused":
            return .focusedTextField
        default:
            throw DemoArgumentError.invalidValue(flag: "--target", value: value, expected: "modal or focusedTextField")
        }
    }
}

public enum DemoArgumentError: Error, LocalizedError, Equatable {
    case unknownArgument(String)
    case missingValue(flag: String)
    case invalidValue(flag: String, value: String, expected: String)

    public var errorDescription: String? {
        switch self {
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)\nUsage: swift run lisper-demo [--mode live|finalOnly] [--target modal|focusedTextField] [--fallback]"
        case .missingValue(let flag):
            return "Missing value for \(flag)\nUsage: swift run lisper-demo [--mode live|finalOnly] [--target modal|focusedTextField] [--fallback]"
        case .invalidValue(let flag, let value, let expected):
            return "Invalid value for \(flag): \(value). Expected \(expected).\nUsage: swift run lisper-demo [--mode live|finalOnly] [--target modal|focusedTextField] [--fallback]"
        }
    }
}

public struct DemoRunner {
    public init() {}

    public func run(
        mode: TranscriptionMode,
        targetKind: DemoTargetKind,
        focusedTargetBehavior: DemoFocusedTargetBehavior = .rewriteSuccess,
        partials: [String],
        final: String
    ) async throws -> String {
        let engine = ScriptedStreamingEngine(partials: partials, final: final)

        switch targetKind {
        case .modal:
            let target = RecordingModalOutputTarget()
            let loggingTarget = LoggingOutputTarget(wrapping: target)
            let controller = SessionController(
                mode: mode,
                outputTarget: loggingTarget,
                engine: engine,
                refinement: PassthroughRefinementProcessor()
            )

            try await controller.runSession()
            return renderTranscript(
                mode: mode,
                targetKind: targetKind,
                partials: partials,
                final: final,
                deliveredEvents: loggingTarget.events,
                focusedSummary: nil
            )

        case .focusedTextField:
            let sink = SimulatedTextSink(
                initialText: "",
                rewriteFailureMode: focusedTargetBehavior == .fallback ? .unsupported : nil
            )
            let target = FocusedTextFieldOutputTarget(sink: sink)
            let loggingTarget = LoggingOutputTarget(wrapping: target)
            let controller = SessionController(
                mode: mode,
                outputTarget: loggingTarget,
                engine: engine,
                refinement: PassthroughRefinementProcessor()
            )

            try await controller.runSession()
            let summary = FocusedSummary(
                resultingText: sink.text,
                fallbackOccurred: sink.didFallbackToFinalAppend,
                operations: sink.operations
            )
            return renderTranscript(
                mode: mode,
                targetKind: targetKind,
                partials: partials,
                final: final,
                deliveredEvents: loggingTarget.events,
                focusedSummary: summary
            )
        }
    }
}

private struct FocusedSummary {
    let resultingText: String
    let fallbackOccurred: Bool
    let operations: [TextMutationOperation]
}

private struct ScriptedStreamingEngine: ASREngine {
    let partials: [String]
    let final: String

    func transcriptEvents() -> AsyncThrowingStream<TranscriptEvent, Error> {
        AsyncThrowingStream { continuation in
            for partial in partials {
                continuation.yield(.partial(partial))
            }
            continuation.yield(.final(final))
            continuation.finish()
        }
    }
}

private final class RecordingModalOutputTarget: OutputTarget {
    private(set) var events: [TranscriptEvent] = []

    func handle(_ event: TranscriptEvent) async throws {
        events.append(event)
    }
}

private final class LoggingOutputTarget: OutputTarget {
    private let wrapped: OutputTarget
    private(set) var events: [TranscriptEvent] = []

    init(wrapping wrapped: OutputTarget) {
        self.wrapped = wrapped
    }

    func handle(_ event: TranscriptEvent) async throws {
        events.append(event)
        try await wrapped.handle(event)
    }
}

private struct PassthroughRefinementProcessor: RefinementProcessor {
    func refine(_ transcript: String) async throws -> String {
        transcript
    }
}

private func renderTranscript(
    mode: TranscriptionMode,
    targetKind: DemoTargetKind,
    partials: [String],
    final: String,
    deliveredEvents: [TranscriptEvent],
    focusedSummary: FocusedSummary?
) -> String {
    var lines: [String] = [
        "Lisper demo",
        "mode: \(mode.displayName)",
        "target: \(targetKind.displayName)",
        "script:"
    ]

    for (index, partial) in partials.enumerated() {
        switch mode {
        case .live:
            lines.append("  \(index + 1). [partial] \(partial)")
        case .finalOnly:
            lines.append("  \(index + 1). [partial] \(partial) (suppressed)")
        }
    }

    lines.append("  \(partials.count + 1). [final] \(final)")
    lines.append("delivered:")

    if deliveredEvents.isEmpty {
        lines.append("  (none)")
    } else {
        for event in deliveredEvents {
            switch event {
            case .partial(let text):
                lines.append("  [partial] \(text)")
            case .final(let text):
                lines.append("  [final] \(text)")
            }
        }
    }

    if let focusedSummary {
        lines.append("focused text field:")
        lines.append("  resulting text: \(focusedSummary.resultingText)")
        lines.append("  fallback happened: \(focusedSummary.fallbackOccurred ? "yes" : "no")")
        lines.append("  operations:")
        if focusedSummary.operations.isEmpty {
            lines.append("    (none)")
        } else {
            for operation in focusedSummary.operations {
                lines.append("    - \(operation.description)")
            }
        }
    }

    return lines.joined(separator: "\n")
}

private extension TranscriptionMode {
    var displayName: String {
        switch self {
        case .live:
            return "live"
        case .finalOnly:
            return "finalOnly"
        }
    }
}

private extension DemoTargetKind {
    var displayName: String {
        switch self {
        case .modal:
            return "modal"
        case .focusedTextField:
            return "focusedTextField"
        }
    }
}

private extension TextMutationOperation {
    var description: String {
        switch self {
        case .insert(let text):
            return "insert(\(text.debugDescription))"
        case .replaceOwnedSpan(let text):
            return "replaceOwnedSpan(with: \(text.debugDescription))"
        case .appendFinal(let text):
            return "appendFinal(\(text.debugDescription))"
        case .fallbackToFinalAppend(let text):
            return "fallbackToFinalAppend(\(text.debugDescription))"
        }
    }
}
