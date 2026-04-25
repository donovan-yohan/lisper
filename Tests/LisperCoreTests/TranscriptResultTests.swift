import XCTest
@testable import LisperCore

final class TranscriptResultTests: XCTestCase {
    func testPreferredTextUsesEnhancedWhenCleanupSucceeds() {
        let result = TranscriptResult(original: "raw text", cleanup: .succeeded("Clean text."))

        XCTAssertEqual(result.preferredText, "Clean text.")
        XCTAssertEqual(result.preferredSource, .enhanced)
        XCTAssertEqual(result.enhancedText, "Clean text.")
    }

    func testPreferredTextUsesOriginalWhenCleanupDisabled() {
        let result = TranscriptResult(original: "raw text", cleanup: .disabled)

        XCTAssertEqual(result.preferredText, "raw text")
        XCTAssertEqual(result.preferredSource, .original)
        XCTAssertNil(result.enhancedText)
    }

    func testPreferredTextUsesOriginalWhenCleanupFails() {
        let result = TranscriptResult(original: "raw text", cleanup: .failed("timeout"))

        XCTAssertEqual(result.preferredText, "raw text")
        XCTAssertEqual(result.preferredSource, .original)
        XCTAssertNil(result.enhancedText)
    }
}
