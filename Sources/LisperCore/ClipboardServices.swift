import Foundation

public enum CopyPasteError: Error, Equatable {
    case copyFailed
    case pasteUnavailable
}

public protocol ClipboardWriting {
    func copy(_ text: String) throws
}

public protocol ActiveFieldPasting {
    func paste(_ text: String) async throws
}

public struct CopyPasteCoordinator {
    public var clipboard: any ClipboardWriting
    public var activeField: (any ActiveFieldPasting)?

    public init(clipboard: any ClipboardWriting, activeField: (any ActiveFieldPasting)?) {
        self.clipboard = clipboard
        self.activeField = activeField
    }

    public func copy(_ text: String) throws {
        try clipboard.copy(text)
    }

    public func pasteIfEnabled(_ text: String, enabled: Bool) async throws {
        guard enabled else {
            return
        }

        guard let activeField else {
            throw CopyPasteError.pasteUnavailable
        }

        try await activeField.paste(text)
    }
}
