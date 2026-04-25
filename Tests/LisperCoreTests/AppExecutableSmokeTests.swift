import XCTest
import Carbon
@testable import LisperCore

final class AppExecutableSmokeTests: XCTestCase {
    func testHotkeyConstantIsDocumentedAndStable() {
        XCTAssertEqual(LisperDefaults.hotkeyDisplay, "Control + Option + Space")
        XCTAssertEqual(LisperDefaults.hotkeyKeyCode, 49)
        XCTAssertEqual(LisperDefaults.hotkeyCarbonModifiers, UInt32(controlKey | optionKey))
        XCTAssertEqual(LisperDefaults.whisperCaptureID, 0)
        XCTAssertEqual(LisperDefaults.whisperStepMilliseconds, 1000)
        XCTAssertEqual(LisperDefaults.whisperLengthMilliseconds, 5000)
    }

    func testProcessSessionConfiguresWhisperStreamWithResolvedDependency() throws {
        let dependency = WhisperDependency(
            streamBinary: URL(fileURLWithPath: "/tmp/whisper-stream"),
            model: URL(fileURLWithPath: "/tmp/model.bin")
        )
        let launcher = RecordingProcessLauncher()
        let session = WhisperProcessSession(
            dependency: dependency,
            processFactory: { launcher }
        )

        try session.start()
        session.stop()

        XCTAssertEqual(launcher.executableURL, dependency.streamBinary)
        XCTAssertEqual(launcher.currentDirectoryURL, LisperDefaults.diagnosticsDirectoryURL)
        XCTAssertEqual(launcher.arguments, [
            "-m", dependency.model.path,
            "-c", "0",
            "--step", "1000",
            "--length", "5000",
            "--keep", "200",
            "-kc",
            "-l", "en",
            "-f", LisperDefaults.whisperTranscriptLogURL.path,
            "-sa"
        ])
        XCTAssertTrue(launcher.didRun)
        XCTAssertTrue(launcher.didTerminate)
    }
}

private final class RecordingProcessLauncher: WhisperProcessLaunching {
    var executableURL: URL?
    var arguments: [String]?
    var currentDirectoryURL: URL?
    var standardOutput: Pipe?
    var standardError: Pipe?
    var terminationHandler: ((Int32) -> Void)?
    var isRunning: Bool {
        didRun && !didTerminate
    }

    private(set) var didRun = false
    private(set) var didTerminate = false

    func run() throws {
        didRun = true
    }

    func terminate() {
        didTerminate = true
        terminationHandler?(0)
    }
}
