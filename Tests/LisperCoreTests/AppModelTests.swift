import XCTest
@testable import LisperCore

@MainActor
final class AppModelTests: XCTestCase {
    func testStartAndStopRecordingTransitionsThroughSessionStates() async throws {
        let dependencyResolver = FakeDependencyResolver()
        let session = FakeWhisperSession()
        let sessionFactory = FakeSessionFactory(session: session)
        let model = LisperAppModel(
            dependencyResolver: dependencyResolver,
            sessionFactory: sessionFactory
        )

        _ = try await model.startRecording()

        XCTAssertEqual(model.phase, .recording)
        XCTAssertEqual(model.statusText, "Recording")
        XCTAssertTrue(session.didStart)
        model.stopRecording()

        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.statusText, "Idle")
        XCTAssertTrue(session.didStop)
    }

    func testTranscriptUpdatesReplaceVisibleTextAndSetDiagnostics() async throws {
        let dependencyResolver = FakeDependencyResolver()
        let session = FakeWhisperSession()
        let sessionFactory = FakeSessionFactory(session: session)
        let model = LisperAppModel(
            dependencyResolver: dependencyResolver,
            sessionFactory: sessionFactory
        )

        let token = try await model.startRecording()
        await model.handle(.transcript("hel"), from: token)
        await model.handle(.transcript("hello"), from: token)
        await model.handle(.stderr("microphone permission denied"), from: token)

        XCTAssertEqual(model.transcriptText, "hello")
        XCTAssertEqual(model.diagnosticsText, "microphone permission denied")
    }

    func testTranscriptUpdatesAccumulateAcrossRollingWindowResets() async throws {
        let dependencyResolver = FakeDependencyResolver()
        let session = FakeWhisperSession()
        let sessionFactory = FakeSessionFactory(session: session)
        let model = LisperAppModel(
            dependencyResolver: dependencyResolver,
            sessionFactory: sessionFactory
        )

        let token = try await model.startRecording()
        await model.handle(.transcript("hello there"), from: token)
        await model.handle(.transcript("general kenobi"), from: token)

        XCTAssertEqual(model.transcriptText, "hello there general kenobi")
    }

    func testStopRecordingPreservesAccumulatedTranscript() async throws {
        let dependencyResolver = FakeDependencyResolver()
        let session = FakeWhisperSession()
        let sessionFactory = FakeSessionFactory(session: session)
        let model = LisperAppModel(
            dependencyResolver: dependencyResolver,
            sessionFactory: sessionFactory
        )

        let token = try await model.startRecording()
        await model.handle(.transcript("hello there"), from: token)
        await model.handle(.transcript("general kenobi"), from: token)

        model.stopRecording()

        XCTAssertEqual(model.transcriptText, "hello there general kenobi")
        XCTAssertEqual(model.phase, .idle)
    }

    func testStartingNewSessionClearsCommittedTranscript() async throws {
        let dependencyResolver = FakeDependencyResolver()
        let firstSession = FakeWhisperSession()
        let secondSession = FakeWhisperSession()
        let sessionFactory = SequencedSessionFactory(sessions: [firstSession, secondSession])
        let model = LisperAppModel(
            dependencyResolver: dependencyResolver,
            sessionFactory: sessionFactory
        )

        let firstToken = try await model.startRecording()
        await model.handle(.transcript("hello there"), from: firstToken)
        await model.handle(.transcript("general kenobi"), from: firstToken)
        model.stopRecording()

        _ = try await model.startRecording()

        XCTAssertEqual(model.transcriptText, "")
        XCTAssertNil(model.transcriptResult)
        XCTAssertEqual(model.phase, .recording)
    }

    func testStopRecordingCreatesProcessingTranscriptResultWhenPostProcessingEnabled() async throws {
        let dependencyResolver = FakeDependencyResolver()
        let session = FakeWhisperSession()
        let sessionFactory = FakeSessionFactory(session: session)
        let model = LisperAppModel(
            dependencyResolver: dependencyResolver,
            sessionFactory: sessionFactory
        )

        let token = try await model.startRecording()
        await model.handle(.transcript("hello there"), from: token)

        model.stopRecording()

        XCTAssertEqual(model.transcriptResult, TranscriptResult(original: "hello there", cleanup: .processing))
    }

    func testFinishRecordingCreatesDisabledTranscriptResultWhenPostProcessingDisabled() {
        let dependencyResolver = FakeDependencyResolver()
        let session = FakeWhisperSession()
        let sessionFactory = FakeSessionFactory(session: session)
        let model = LisperAppModel(
            dependencyResolver: dependencyResolver,
            sessionFactory: sessionFactory
        )
        var settings = LisperSettings.defaults
        settings.automation.postProcessingEnabled = false
        let token = model.beginInProcessRecording()
        model.updateSettings(settings)
        model.applyLiveTranscript("no cleanup", from: token)

        model.finishRecording(for: token)

        XCTAssertEqual(model.transcriptResult, TranscriptResult(original: "no cleanup", cleanup: .disabled))
    }

    func testFailurePreservesTranscriptResultForCopyFallback() async throws {
        let dependencyResolver = FakeDependencyResolver()
        let session = FakeWhisperSession()
        let sessionFactory = FakeSessionFactory(session: session)
        let model = LisperAppModel(
            dependencyResolver: dependencyResolver,
            sessionFactory: sessionFactory
        )

        let token = try await model.startRecording()
        await model.handle(.transcript("partial result"), from: token)
        await model.handle(.failed("engine stopped"), from: token)

        XCTAssertEqual(model.phase, .failed)
        XCTAssertEqual(model.transcriptText, "partial result")
        XCTAssertEqual(model.transcriptResult, TranscriptResult(original: "partial result", cleanup: .processing))
    }

    func testCleanupCompletionUpdatesExistingTranscriptResult() async throws {
        let dependencyResolver = FakeDependencyResolver()
        let session = FakeWhisperSession()
        let sessionFactory = FakeSessionFactory(session: session)
        let model = LisperAppModel(
            dependencyResolver: dependencyResolver,
            sessionFactory: sessionFactory
        )

        let token = try await model.startRecording()
        await model.handle(.transcript("hello there"), from: token)
        model.stopRecording()

        model.completeCleanup(.succeeded("Hello there."))

        XCTAssertEqual(model.transcriptResult, TranscriptResult(original: "hello there", cleanup: .succeeded("Hello there.")))
        XCTAssertEqual(model.transcriptResult?.preferredText, "Hello there.")
    }

    func testCopyFeedbackEventCanBeReportedAndResetsWithNewSession() async throws {
        let dependencyResolver = FakeDependencyResolver()
        let firstSession = FakeWhisperSession()
        let secondSession = FakeWhisperSession()
        let sessionFactory = SequencedSessionFactory(sessions: [firstSession, secondSession])
        let model = LisperAppModel(
            dependencyResolver: dependencyResolver,
            sessionFactory: sessionFactory
        )

        model.reportCopyFeedback(source: .enhanced, message: "Text copied")

        XCTAssertEqual(model.copyFeedbackEvent?.source, .enhanced)
        XCTAssertEqual(model.copyFeedbackEvent?.message, "Text copied")

        _ = try await model.startRecording()
        model.stopRecording()
        _ = try await model.startRecording()

        XCTAssertNil(model.copyFeedbackEvent)
    }

    func testAudioFeedbackStateIsExposedAndUpdatable() {
        let dependencyResolver = FakeDependencyResolver()
        let session = FakeWhisperSession()
        let sessionFactory = FakeSessionFactory(session: session)
        let model = LisperAppModel(
            dependencyResolver: dependencyResolver,
            sessionFactory: sessionFactory
        )

        model.applyAudioSamples([1.0])

        XCTAssertGreaterThan(model.audioFeedback.currentEnergy, 0)
        XCTAssertGreaterThan(model.audioFeedback.particleIntensity, 0)
    }

    func testStaleEventsFromPriorSessionAreIgnored() async throws {
        let dependencyResolver = FakeDependencyResolver()
        let firstSession = FakeWhisperSession()
        let secondSession = FakeWhisperSession()
        let sessionFactory = SequencedSessionFactory(sessions: [firstSession, secondSession])
        let model = LisperAppModel(
            dependencyResolver: dependencyResolver,
            sessionFactory: sessionFactory
        )

        let firstToken = try await model.startRecording()
        model.stopRecording()
        let secondToken = try await model.startRecording()

        await model.handle(.transcript("stale"), from: firstToken)
        await model.handle(.transcript("fresh"), from: secondToken)

        XCTAssertEqual(model.transcriptText, "fresh")
    }

    func testStartupFailureCleansUpSessionObject() async {
        let dependencyResolver = FakeDependencyResolver()
        let session = ThrowingStartSession()
        let sessionFactory = FakeSessionFactory(session: session)
        let model = LisperAppModel(
            dependencyResolver: dependencyResolver,
            sessionFactory: sessionFactory
        )

        do {
            _ = try await model.startRecording()
            XCTFail("Expected startRecording() to throw")
        } catch {
            XCTAssertEqual(session.didStop, true)
            XCTAssertEqual(model.phase, .failed)
            XCTAssertEqual(model.statusText, "Failed to start recording")
            XCTAssertEqual(model.diagnosticsText, ThrowingStartSession.TestError.failed.localizedDescription)
        }
    }
}

private final class FakeDependencyResolver: WhisperDependencyResolving {
    func resolve() throws -> WhisperDependency {
        WhisperDependency(
            streamBinary: URL(fileURLWithPath: "/tmp/whisper-stream"),
            model: URL(fileURLWithPath: "/tmp/model.bin")
        )
    }
}

private final class FakeSessionFactory<Session: WhisperStreamingSession>: WhisperStreamingSessionFactory {
    private let session: Session
    private let configure: (Session, WhisperDependency) -> Void

    init(
        session: Session,
        configure: @escaping (Session, WhisperDependency) -> Void = { _, _ in }
    ) {
        self.session = session
        self.configure = configure
    }

    func makeSession(using dependency: WhisperDependency) -> any WhisperStreamingSession {
        configure(session, dependency)
        return session
    }
}

private final class SequencedSessionFactory: WhisperStreamingSessionFactory {
    private var sessions: [any WhisperStreamingSession]

    init(sessions: [any WhisperStreamingSession]) {
        self.sessions = sessions
    }

    func makeSession(using dependency: WhisperDependency) -> any WhisperStreamingSession {
        precondition(!sessions.isEmpty, "No more scripted sessions")
        return sessions.removeFirst()
    }
}

private final class FakeWhisperSession: WhisperStreamingSession {
    let updates: AsyncStream<WhisperStreamEvent>
    private let continuation: AsyncStream<WhisperStreamEvent>.Continuation

    private(set) var didStart = false
    private(set) var didStop = false

    init() {
        var continuation: AsyncStream<WhisperStreamEvent>.Continuation!
        updates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() throws {
        didStart = true
    }

    func stop() {
        didStop = true
        continuation.finish()
    }
}

private final class ThrowingStartSession: WhisperStreamingSession {
    enum TestError: Error, Equatable, LocalizedError {
        case failed

        var errorDescription: String? {
            "failed"
        }
    }

    let updates: AsyncStream<WhisperStreamEvent>
    private let continuation: AsyncStream<WhisperStreamEvent>.Continuation

    private(set) var didStop = false

    init() {
        var continuation: AsyncStream<WhisperStreamEvent>.Continuation!
        updates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() throws {
        throw TestError.failed
    }

    func stop() {
        didStop = true
        continuation.finish()
    }
}
