import XCTest
@testable import LisperCore

final class SessionControllerTests: XCTestCase {
    func testLiveModeStreamsPartialsAndCommitsFinalTranscript() async throws {
        let engine = ScriptedStreamingEngine(partials: ["hel", "hello"], final: "hello")
        let target = RecordingOutputTarget()
        let controller = SessionController(
            mode: .live,
            outputTarget: target,
            engine: engine,
            refinement: PassthroughRefinementProcessor()
        )

        try await controller.runSession()

        XCTAssertEqual(target.events, [
            .partial("hel"),
            .partial("hello"),
            .final("hello")
        ])
    }

    func testFinalModeSuppressesPartialsUntilFinalTranscript() async throws {
        let engine = ScriptedStreamingEngine(partials: ["hel", "hello"], final: "hello")
        let target = RecordingOutputTarget()
        let controller = SessionController(
            mode: .finalOnly,
            outputTarget: target,
            engine: engine,
            refinement: PassthroughRefinementProcessor()
        )

        try await controller.runSession()

        XCTAssertEqual(target.events, [.final("hello")])
    }

    func testFinalModePropagatesRefinementErrors() async throws {
        let engine = ScriptedStreamingEngine(partials: ["hel"], final: "hello")
        let target = RecordingOutputTarget()
        let controller = SessionController(
            mode: .finalOnly,
            outputTarget: target,
            engine: engine,
            refinement: ThrowingRefinementProcessor()
        )

        do {
            try await controller.runSession()
            XCTFail("Expected refinement error to propagate")
        } catch {
            XCTAssertEqual(error as? ThrowingRefinementProcessor.TestError, .failed)
        }
        XCTAssertTrue(target.events.isEmpty)
    }

    func testLiveModePropagatesOutputTargetErrors() async throws {
        let engine = ScriptedStreamingEngine(partials: ["hel"], final: "hello")
        let target = ThrowingOutputTarget()
        let controller = SessionController(
            mode: .live,
            outputTarget: target,
            engine: engine,
            refinement: PassthroughRefinementProcessor()
        )

        do {
            try await controller.runSession()
            XCTFail("Expected output target error to propagate")
        } catch {
            XCTAssertEqual(error as? ThrowingOutputTarget.TestError, .failed)
        }
    }

    func testEmptyStreamDoesNotEmitOutput() async throws {
        let engine = EmptyStreamingEngine()
        let target = RecordingOutputTarget()
        let controller = SessionController(
            mode: .live,
            outputTarget: target,
            engine: engine,
            refinement: PassthroughRefinementProcessor()
        )

        try await controller.runSession()

        XCTAssertTrue(target.events.isEmpty)
    }

    func testEngineErrorPropagatesWithoutEmittingOutput() async throws {
        let engine = ThrowingStreamingEngine()
        let target = RecordingOutputTarget()
        let controller = SessionController(
            mode: .live,
            outputTarget: target,
            engine: engine,
            refinement: PassthroughRefinementProcessor()
        )

        do {
            try await controller.runSession()
            XCTFail("Expected engine error to propagate")
        } catch {
            XCTAssertEqual(error as? ThrowingStreamingEngine.TestError, .failed)
        }

        XCTAssertTrue(target.events.isEmpty)
    }
}

private final class ScriptedStreamingEngine: ASREngine {
    private let partials: [String]
    private let final: String

    init(partials: [String], final: String) {
        self.partials = partials
        self.final = final
    }

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

private final class RecordingOutputTarget: OutputTarget {
    private(set) var events: [TranscriptEvent] = []

    func handle(_ event: TranscriptEvent) async throws {
        events.append(event)
    }
}

private final class PassthroughRefinementProcessor: RefinementProcessor {
    func refine(_ transcript: String) async throws -> String {
        transcript
    }
}

private final class ThrowingRefinementProcessor: RefinementProcessor {
    enum TestError: Error, Equatable {
        case failed
    }

    func refine(_ transcript: String) async throws -> String {
        throw TestError.failed
    }
}

private final class ThrowingOutputTarget: OutputTarget {
    enum TestError: Error, Equatable {
        case failed
    }

    func handle(_ event: TranscriptEvent) async throws {
        throw TestError.failed
    }
}

private final class EmptyStreamingEngine: ASREngine {
    func transcriptEvents() -> AsyncThrowingStream<TranscriptEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private final class ThrowingStreamingEngine: ASREngine {
    enum TestError: Error, Equatable {
        case failed
    }

    func transcriptEvents() -> AsyncThrowingStream<TranscriptEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: TestError.failed)
        }
    }
}
