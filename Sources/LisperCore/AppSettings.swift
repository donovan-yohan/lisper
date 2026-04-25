import Foundation

public struct LisperSettings: Equatable, Sendable {
    public var hotkey: HotkeySettings
    public var automation: AutomationSettings
    public var appearance: AppearanceSettings
    public var speechToTextModel: ModelSlotConfiguration
    public var cleanupModel: ModelSlotConfiguration

    public init(
        hotkey: HotkeySettings,
        automation: AutomationSettings,
        appearance: AppearanceSettings,
        speechToTextModel: ModelSlotConfiguration,
        cleanupModel: ModelSlotConfiguration
    ) {
        self.hotkey = hotkey
        self.automation = automation
        self.appearance = appearance
        self.speechToTextModel = speechToTextModel
        self.cleanupModel = cleanupModel
    }

    public static let defaults = LisperSettings(
        hotkey: .rightOption,
        automation: .defaults,
        appearance: .system,
        speechToTextModel: .local(slot: .speechToText),
        cleanupModel: .local(slot: .cleanupText)
    )
}

public struct HotkeySettings: Equatable, Sendable {
    public var displayName: String
    public var keyCode: Int
    public var modifierFlags: UInt64

    public init(displayName: String, keyCode: Int, modifierFlags: UInt64) {
        self.displayName = displayName
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    public static let rightOption = HotkeySettings(displayName: "Right Option", keyCode: 61, modifierFlags: 0)
}

public struct AutomationSettings: Equatable, Sendable {
    public var postProcessingEnabled: Bool
    public var autoCopyEnabled: Bool
    public var autoPasteEnabled: Bool

    public init(
        postProcessingEnabled: Bool,
        autoCopyEnabled: Bool,
        autoPasteEnabled: Bool
    ) {
        self.postProcessingEnabled = postProcessingEnabled
        self.autoCopyEnabled = autoCopyEnabled
        self.autoPasteEnabled = autoPasteEnabled
    }

    public static let defaults = AutomationSettings(
        postProcessingEnabled: true,
        autoCopyEnabled: false,
        autoPasteEnabled: false
    )
}

public enum AppearanceSettings: String, Equatable, Sendable, CaseIterable {
    case system
    case light
    case dark
}
