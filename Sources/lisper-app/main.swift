import AppKit
import SwiftUI
import LisperCore

struct LisperPrototypeApp: App {
    @StateObject private var coordinator = LisperAppCoordinator()
    @Environment(\.openWindow) private var openWindow

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

        MenuBarExtra("Lisper", systemImage: "waveform") {
            Button("Options...") {
                openOptions()
            }

            Button("Show Modal") {
                openWindow(id: "ephemeral-modal")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Quit Lisper") {
                NSApp.terminate(nil)
            }
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

    private func openOptions() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

LisperPrototypeApp.main()
