import XCTest
@testable import LisperCore

final class DemoIntegrationTests: XCTestCase {
    func testDemoArgumentParserParsesConventionalFlags() throws {
        let configuration = try DemoArgumentParser().parse([
            "--mode", "finalOnly",
            "--target", "focusedTextField",
            "--fallback"
        ])

        XCTAssertEqual(configuration, DemoConfiguration(
            mode: .finalOnly,
            targetKind: .focusedTextField,
            focusedTargetBehavior: .fallback
        ))
    }

    func testDemoArgumentParserRejectsUnknownArguments() {
        XCTAssertThrowsError(try DemoArgumentParser().parse(["--bogus"])) { error in
            XCTAssertEqual(error as? DemoArgumentError, .unknownArgument("--bogus"))
            XCTAssertTrue(error.localizedDescription.contains("Usage:"))
        }
    }

    func testScriptedDemoProducesLiveTimelineForModalOutput() async throws {
        let transcript = try await DemoRunner().run(
            mode: .live,
            targetKind: .modal,
            partials: ["Lis", "Lisper"],
            final: "Lisper demo"
        )

        XCTAssertTrue(transcript.contains("mode: live"))
        XCTAssertTrue(transcript.contains("target: modal"))
        XCTAssertTrue(transcript.contains("[partial] Lis"))
        XCTAssertTrue(transcript.contains("[partial] Lisper"))
        XCTAssertTrue(transcript.contains("[final] Lisper demo"))
    }

    func testScriptedDemoIncludesFocusedTargetResultAndFallbackDetails() async throws {
        let transcript = try await DemoRunner().run(
            mode: .live,
            targetKind: .focusedTextField,
            partials: ["thi", "this is"],
            final: "this is lisper"
        )

        XCTAssertTrue(transcript.contains("mode: live"))
        XCTAssertTrue(transcript.contains("target: focusedTextField"))
        XCTAssertTrue(transcript.contains("resulting text: this is lisper"))
        XCTAssertTrue(transcript.contains("fallback happened: no"))
        XCTAssertTrue(transcript.contains("replaceOwnedSpan(with: \"this is\")"))
    }

    func testScriptedDemoIncludesFocusedFallbackDetails() async throws {
        let transcript = try await DemoRunner().run(
            mode: .live,
            targetKind: .focusedTextField,
            focusedTargetBehavior: .fallback,
            partials: ["thi", "this is"],
            final: "this is lisper"
        )

        XCTAssertTrue(transcript.contains("mode: live"))
        XCTAssertTrue(transcript.contains("target: focusedTextField"))
        XCTAssertTrue(transcript.contains("fallback happened: yes"))
        XCTAssertTrue(transcript.contains("fallbackToFinalAppend"))
    }
}
