import Foundation

public enum ModelSlot: String, Equatable, Sendable, Codable, CaseIterable {
    case speechToText
    case cleanupText
}

public enum ModelSlotKind: String, Equatable, Sendable, Codable {
    case local
    case remote
}

public struct ModelSlotConfiguration: Equatable, Sendable, Codable {
    public var slot: ModelSlot
    public var kind: ModelSlotKind
    public var endpointURL: String
    public var apiKeyReference: String?

    public init(
        slot: ModelSlot,
        kind: ModelSlotKind,
        endpointURL: String,
        apiKeyReference: String?
    ) {
        self.slot = slot
        self.kind = kind
        self.endpointURL = endpointURL
        self.apiKeyReference = apiKeyReference
    }

    public static func local(slot: ModelSlot) -> ModelSlotConfiguration {
        ModelSlotConfiguration(slot: slot, kind: .local, endpointURL: "", apiKeyReference: nil)
    }
}
