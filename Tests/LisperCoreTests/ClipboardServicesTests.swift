import XCTest
@testable import LisperCore

final class ClipboardServicesTests: XCTestCase {
    func testCopyWritesTextToClipboardService() throws {
        let clipboard = FakeClipboardWriter()
        let coordinator = CopyPasteCoordinator(clipboard: clipboard, activeField: nil)

        try coordinator.copy("hello")

        XCTAssertEqual(clipboard.copiedText, "hello")
    }

    func testDisabledPasteDoesNotRequireActiveField() async throws {
        let coordinator = CopyPasteCoordinator(clipboard: FakeClipboardWriter(), activeField: nil)

        try await coordinator.pasteIfEnabled("hello", enabled: false)
    }

    func testEnabledPasteWritesToActiveField() async throws {
        let activeField = FakeActiveFieldPaster()
        let coordinator = CopyPasteCoordinator(clipboard: FakeClipboardWriter(), activeField: activeField)

        try await coordinator.pasteIfEnabled("hello", enabled: true)

        XCTAssertEqual(activeField.pastedText, "hello")
    }

    func testEnabledPasteWithoutActiveFieldThrowsUnavailable() async {
        let coordinator = CopyPasteCoordinator(clipboard: FakeClipboardWriter(), activeField: nil)

        do {
            try await coordinator.pasteIfEnabled("hello", enabled: true)
            XCTFail("Expected pasteIfEnabled to throw")
        } catch {
            XCTAssertEqual(error as? CopyPasteError, .pasteUnavailable)
        }
    }
}

private final class FakeClipboardWriter: ClipboardWriting {
    private(set) var copiedText: String?

    func copy(_ text: String) throws {
        copiedText = text
    }
}

private final class FakeActiveFieldPaster: ActiveFieldPasting {
    private(set) var pastedText: String?

    func paste(_ text: String) async throws {
        pastedText = text
    }
}
