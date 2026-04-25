import XCTest
@testable import LisperCore

final class WhisperLibraryTranscriberTests: XCTestCase {
    func testWhisperRuntimeDefaultsUseExpectedWindowing() {
        XCTAssertEqual(WhisperRuntimeDefaults.windowDurationSeconds, 5.0)
        XCTAssertEqual(WhisperRuntimeDefaults.updateIntervalSeconds, 1.0)
    }

    func testTranscriptNormalizerJoinsDecodedSegments() {
        XCTAssertEqual(
            WhisperTranscriptNormalizer.normalize(["hello", "world"]),
            "hello world"
        )
    }

    func testWhisperLibraryBindingExposesVersionString() {
        XCTAssertFalse(WhisperLibraryTranscriber.libraryVersion.isEmpty)
    }
}
