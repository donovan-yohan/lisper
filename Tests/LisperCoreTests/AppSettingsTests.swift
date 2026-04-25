import XCTest
@testable import LisperCore

final class AppSettingsTests: XCTestCase {
    func testDefaultsMatchMVPPolicy() {
        let settings = LisperSettings.defaults

        XCTAssertEqual(settings.hotkey.displayName, "Right Option")
        XCTAssertTrue(settings.automation.postProcessingEnabled)
        XCTAssertFalse(settings.automation.autoCopyEnabled)
        XCTAssertFalse(settings.automation.autoPasteEnabled)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.speechToTextModel.kind, .local)
        XCTAssertEqual(settings.cleanupModel.kind, .local)
    }
}
