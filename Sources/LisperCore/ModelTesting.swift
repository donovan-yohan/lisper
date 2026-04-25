import Foundation

public enum ModelTestStatus: Equatable, Sendable {
    case idle
    case testing
    case succeeded(String)
    case failed(String)
}

public protocol ModelSlotTesting {
    func test(configuration: ModelSlotConfiguration) async -> ModelTestStatus
}
