import SwiftUI
import LisperCore

struct LisperPrototypeApp: App {
    @StateObject private var coordinator = LisperAppCoordinator()

    var body: some Scene {
        WindowGroup("Lisper", id: "ephemeral-modal") {
            EphemeralModalView(model: coordinator.model)
                .preferredColorScheme(preferredColorScheme)
        }
        .windowResizability(.contentSize)

        Settings {
            LisperSettingsView(model: coordinator.model)
                .preferredColorScheme(preferredColorScheme)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch coordinator.model.settings.appearance {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

LisperPrototypeApp.main()
