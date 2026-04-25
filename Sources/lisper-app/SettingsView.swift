import Security
import SwiftUI
import LisperCore

public struct LisperSettingsView: View {
    @ObservedObject private var model: LisperAppModel
    @State private var draft: LisperSettings

    public init(model: LisperAppModel) {
        _model = ObservedObject(wrappedValue: model)
        _draft = State(initialValue: model.settings)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HotkeySettingsPane(settings: settingsBinding)
                ModelSettingsPane(settings: settingsBinding)
                AutomationSettingsPane(settings: settingsBinding)
                AppearanceSettingsPane(settings: settingsBinding)
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .background(settingsBackground)
        .frame(minWidth: 680, minHeight: 620)
        .onReceive(model.$settings) { settings in
            guard settings != draft else {
                return
            }
            draft = settings
        }
    }

    private var settingsBinding: Binding<LisperSettings> {
        Binding(
            get: { draft },
            set: { settings in
                draft = settings
                model.updateSettings(settings)
            }
        )
    }

    private var settingsBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.cyan.opacity(0.05),
                Color.pink.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

public struct HotkeySettingsPane: View {
    @Binding var settings: LisperSettings
    @State private var isRecordingHotkey = false

    public var body: some View {
        SettingsSection(title: "Hotkey", systemImage: "keyboard") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.hotkey.displayName)
                        .font(.headline)
                    Text("Tap to toggle, hold to talk")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(isRecordingHotkey ? "Press a key..." : "Record") {
                    isRecordingHotkey.toggle()
                    if !isRecordingHotkey {
                        settings.hotkey = .rightOption
                    }
                }
            }
        }
    }
}

public struct ModelSettingsPane: View {
    @Binding var settings: LisperSettings
    @State private var speechTestStatus: ModelTestStatus = .idle
    @State private var cleanupTestStatus: ModelTestStatus = .idle

    public var body: some View {
        SettingsSection(title: "Models", systemImage: "sparkles") {
            VStack(spacing: 18) {
                ModelSlotEditor(
                    title: "Speech-to-text",
                    subtitle: "Local speech model by default",
                    configuration: speechModelBinding,
                    testStatus: $speechTestStatus
                )

                Divider()

                ModelSlotEditor(
                    title: "Cleanup text",
                    subtitle: "Lightweight cleanup model by default",
                    configuration: cleanupModelBinding,
                    testStatus: $cleanupTestStatus
                )
            }
        }
    }

    private var speechModelBinding: Binding<ModelSlotConfiguration> {
        Binding(
            get: { settings.speechToTextModel },
            set: { settings.speechToTextModel = $0 }
        )
    }

    private var cleanupModelBinding: Binding<ModelSlotConfiguration> {
        Binding(
            get: { settings.cleanupModel },
            set: { settings.cleanupModel = $0 }
        )
    }
}

public struct AutomationSettingsPane: View {
    @Binding var settings: LisperSettings

    public var body: some View {
        SettingsSection(title: "Automation", systemImage: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Post-processing", isOn: automationBinding(\.postProcessingEnabled))
                Toggle("Auto-copy preferred result", isOn: automationBinding(\.autoCopyEnabled))
                Toggle("Auto-paste into active field", isOn: automationBinding(\.autoPasteEnabled))
            }
            .toggleStyle(.switch)
        }
    }

    private func automationBinding(_ keyPath: WritableKeyPath<AutomationSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.automation[keyPath: keyPath] },
            set: { settings.automation[keyPath: keyPath] = $0 }
        )
    }
}

public struct AppearanceSettingsPane: View {
    @Binding var settings: LisperSettings

    public var body: some View {
        SettingsSection(title: "Appearance", systemImage: "circle.lefthalf.filled") {
            Picker("Theme", selection: $settings.appearance) {
                Text("System").tag(AppearanceSettings.system)
                Text("Light").tag(AppearanceSettings.light)
                Text("Dark").tag(AppearanceSettings.dark)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
        }
    }
}

private struct ModelSlotEditor: View {
    let title: String
    let subtitle: String
    @Binding var configuration: ModelSlotConfiguration
    @Binding var testStatus: ModelTestStatus
    @State private var apiKeyInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Mode", selection: kindBinding) {
                    Text("Local").tag(ModelSlotKind.local)
                    Text("Remote").tag(ModelSlotKind.remote)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Endpoint")
                        .foregroundStyle(.secondary)
                    TextField("https://api.example.com/model", text: endpointBinding)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("API key")
                        .foregroundStyle(.secondary)
                    SecureField(apiKeyPlaceholder, text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKeyInput) { _, value in
                            saveAPIKey(value)
                        }
                }
            }
            .font(.callout)

            HStack(spacing: 10) {
                Button {
                    runTest()
                } label: {
                    Label("Test", systemImage: "checkmark.seal")
                }
                .disabled(testStatus == .testing)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)

                Spacer()
            }
        }
    }

    private var kindBinding: Binding<ModelSlotKind> {
        Binding(
            get: { configuration.kind },
            set: { kind in
                configuration.kind = kind
            }
        )
    }

    private var endpointBinding: Binding<String> {
        Binding(
            get: { configuration.endpointURL },
            set: { configuration.endpointURL = $0 }
        )
    }

    private var apiKeyPlaceholder: String {
        configuration.apiKeyReference == nil ? "Stored in Keychain" : "Key saved in Keychain"
    }

    private var statusText: String {
        switch testStatus {
        case .idle:
            return "Not tested"
        case .testing:
            return "Testing..."
        case .succeeded(let message):
            return message
        case .failed(let message):
            return message
        }
    }

    private var statusColor: Color {
        switch testStatus {
        case .idle, .testing:
            return .secondary
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }

    private func runTest() {
        testStatus = .testing
        Task {
            let status = await testConfiguration()
            await MainActor.run {
                testStatus = status
            }
        }
    }

    private func testConfiguration() async -> ModelTestStatus {
        guard configuration.kind == .remote else {
            return .succeeded("Local model available")
        }

        let endpoint = configuration.endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty, let url = URL(string: endpoint), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return .failed("Invalid endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        if let token = AppKeychain.load(reference: keychainReference), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failed("No HTTP response")
            }

            if (200..<400).contains(httpResponse.statusCode) {
                return .succeeded("Endpoint reachable")
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return .failed("Auth rejected")
            }

            return .failed("HTTP \(httpResponse.statusCode)")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private var keychainReference: String {
        "lisper.\(configuration.slot.rawValue).api-key"
    }

    private func saveAPIKey(_ value: String) {
        if value.isEmpty {
            AppKeychain.delete(reference: keychainReference)
            configuration.apiKeyReference = nil
            return
        }

        do {
            try AppKeychain.save(value, reference: keychainReference)
            configuration.apiKeyReference = keychainReference
        } catch {
            testStatus = .failed("Could not save key")
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
        }
    }
}

private enum AppKeychain {
    static func save(_ value: String, reference: String) throws {
        delete(reference: reference)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Lisper",
            kSecAttrAccount as String: reference,
            kSecValueData as String: Data(value.utf8)
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func load(reference: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Lisper",
            kSecAttrAccount as String: reference,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func delete(reference: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Lisper",
            kSecAttrAccount as String: reference
        ]
        SecItemDelete(query as CFDictionary)
    }
}
