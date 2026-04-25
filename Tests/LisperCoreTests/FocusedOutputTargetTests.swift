import XCTest
@testable import LisperCore

final class FocusedOutputTargetTests: XCTestCase {
    func testFocusedTargetRewritesOwnedSpanAcrossPartialsAndFinal() async throws {
        let sink = SimulatedTextSink(initialText: "prefix ")
        let target = FocusedTextFieldOutputTarget(sink: sink)

        try await target.handle(.partial("hel"))
        try await target.handle(.partial("hello"))
        try await target.handle(.final("hello world"))

        XCTAssertEqual(sink.text, "prefix hello world")
        XCTAssertEqual(sink.operations, [
            .insert("hel"),
            .replaceOwnedSpan(with: "hello"),
            .replaceOwnedSpan(with: "hello world")
        ])
        XCTAssertFalse(sink.didFallbackToFinalAppend)
    }

    func testFocusedTargetUsesStickyFallbackAfterRewriteIsUnsupported() async throws {
        let sink = SimulatedTextSink(initialText: "prefix ", rewriteFailureMode: .unsupported)
        let target = FocusedTextFieldOutputTarget(sink: sink)

        try await target.handle(.partial("hel"))
        try await target.handle(.partial("hello"))
        try await target.handle(.final("hello world"))

        XCTAssertEqual(sink.text, "prefix helhellohello world")
        XCTAssertEqual(sink.operations, [
            .insert("hel"),
            .fallbackToFinalAppend("hello"),
            .appendFinal("hello world")
        ])
        XCTAssertTrue(sink.didFallbackToFinalAppend)
    }

    func testFocusedTargetPropagatesUnexpectedRewriteErrors() async throws {
        let sink = SimulatedTextSink(initialText: "prefix ", rewriteFailureMode: .unexpected)
        let target = FocusedTextFieldOutputTarget(sink: sink)

        try await target.handle(.partial("hel"))

        do {
            try await target.handle(.partial("hello"))
            XCTFail("Expected unexpected rewrite error to propagate")
        } catch let error as SimulatedTextSink.SimulatedError {
            XCTAssertEqual(error, .unexpectedRewriteFailure)
        }

        XCTAssertEqual(sink.text, "prefix hel")
        XCTAssertEqual(sink.operations, [
            .insert("hel")
        ])
        XCTAssertFalse(sink.didFallbackToFinalAppend)
    }
}
