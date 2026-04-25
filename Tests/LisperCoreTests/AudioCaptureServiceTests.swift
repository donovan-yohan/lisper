import XCTest
@testable import LisperCore

@MainActor
final class AudioCaptureServiceTests: XCTestCase {
    func testRollingAudioBufferKeepsMostRecentWindow() {
        var buffer = RollingAudioBuffer(maxSamples: 4)

        buffer.append([1, 2, 3])
        buffer.append([4, 5])

        XCTAssertEqual(buffer.snapshot(), [2, 3, 4, 5])
    }

    func testApplyLiveTranscriptUsesCurrentSessionToken() async throws {
        let model = LisperAppModel(
            dependencyResolver: FakeDependencyResolver(),
            sessionFactory: FakeSessionFactory()
        )

        let token = try await model.startRecording()
        model.applyLiveTranscript("hello live", from: token)

        XCTAssertEqual(model.transcriptText, "hello live")
        XCTAssertEqual(model.statusText, "Recording")
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

private final class FakeSessionFactory: WhisperStreamingSessionFactory {
    func makeSession(using dependency: WhisperDependency) -> any WhisperStreamingSession {
        FakeWhisperSession()
    }
}

private final class FakeWhisperSession: WhisperStreamingSession {
    let updates: AsyncStream<WhisperStreamEvent>

    init() {
        updates = AsyncStream { continuation in
            continuation.finish()
        }
    }

    func start() throws {}

    func stop() {}
}
