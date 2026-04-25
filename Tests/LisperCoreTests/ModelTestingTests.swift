import XCTest
@testable import LisperCore

final class ModelTestingTests: XCTestCase {
    func testFakeTesterReturnsSuccessForRemoteConfigurationWithEndpoint() async {
        let tester = FakeModelSlotTester()
        let configuration = ModelSlotConfiguration(
            slot: .speechToText,
            kind: .remote,
            endpointURL: "https://example.test/transcribe",
            apiKeyReference: "speech-key"
        )

        let status = await tester.test(configuration: configuration)

        XCTAssertEqual(status, .succeeded("OK"))
    }

    func testFakeTesterReturnsFailureForRemoteConfigurationWithoutEndpoint() async {
        let tester = FakeModelSlotTester()
        let configuration = ModelSlotConfiguration(
            slot: .cleanupText,
            kind: .remote,
            endpointURL: "",
            apiKeyReference: nil
        )

        let status = await tester.test(configuration: configuration)

        XCTAssertEqual(status, .failed("Missing endpoint"))
    }
}

private struct FakeModelSlotTester: ModelSlotTesting {
    func test(configuration: ModelSlotConfiguration) async -> ModelTestStatus {
        guard configuration.kind == .remote else {
            return .succeeded("Local")
        }

        if configuration.endpointURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failed("Missing endpoint")
        }

        return .succeeded("OK")
    }
}
