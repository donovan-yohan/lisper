import XCTest
@testable import LisperCore

final class WhisperStreamingTests: XCTestCase {
    func testParserExtractsTranscriptLinesFromWhisperStreamOutput() {
        var parser = WhisperStreamOutputParser()

        XCTAssertEqual(
            parser.consume("[00:00:00.000 --> 00:00:01.200] hello world"),
            .transcript("hello world")
        )
    }

    func testEnvironmentOverridesDependencyResolution() throws {
        let resolver = WhisperDependencyResolver(
            environment: [
                "LISPER_WHISPER_STREAM": "/tmp/whisper-stream",
                "LISPER_WHISPER_MODEL": "/tmp/model.bin"
            ],
            fileExists: { _ in true }
        )

        XCTAssertEqual(
            try resolver.resolve(),
            WhisperDependency(
                streamBinary: URL(fileURLWithPath: "/tmp/whisper-stream"),
                model: URL(fileURLWithPath: "/tmp/model.bin")
            )
        )
    }

    func testDependencyResolverFallsBackToCommonDefaults() throws {
        let expectedStreamPath = "/opt/homebrew/bin/whisper-stream"
        let expectedModelPath = "/opt/homebrew/share/lisper/ggml-base.en.bin"
        let resolver = WhisperDependencyResolver(
            environment: [:],
            fileExists: { path in
                path == expectedStreamPath || path == expectedModelPath
            }
        )

        XCTAssertEqual(
            try resolver.resolve(),
            WhisperDependency(
                streamBinary: URL(fileURLWithPath: expectedStreamPath),
                model: URL(fileURLWithPath: expectedModelPath)
            )
        )
    }

    func testDependencyResolverFallsBackToRepoLocalSetupPaths() throws {
        let expectedStreamPath = ".tools/whisper.cpp/build/bin/whisper-stream"
        let expectedModelPath = ".tools/models/ggml-tiny.en.bin"
        let resolver = WhisperDependencyResolver(
            environment: [:],
            fileExists: { path in
                path == expectedStreamPath || path == expectedModelPath
            }
        )

        XCTAssertEqual(
            try resolver.resolve(),
            WhisperDependency(
                streamBinary: URL(fileURLWithPath: expectedStreamPath),
                model: URL(fileURLWithPath: expectedModelPath)
            )
        )
    }

    func testParserRejectsBracketedLogsThatAreNotRealTimestamps() {
        var parser = WhisperStreamOutputParser()

        XCTAssertEqual(
            parser.consume("[stream --> status] warming up"),
            .info("[stream --> status] warming up")
        )
    }

    func testParserTreatsPlainStreamingChunksAsTranscript() {
        var parser = WhisperStreamOutputParser()

        XCTAssertEqual(
            parser.consume("hello world"),
            .transcript("hello world")
        )
    }

    func testParserStripsAnsiControlSequencesFromStreamingChunks() {
        var parser = WhisperStreamOutputParser()

        XCTAssertEqual(
            parser.consume("\u{001B}[2K\rhello world"),
            .transcript("hello world")
        )
    }

    func testParserTreatsStartSpeakingBannerAsInfo() {
        var parser = WhisperStreamOutputParser()

        XCTAssertEqual(
            parser.consume("[Start speaking]"),
            .info("[Start speaking]")
        )
    }
}
