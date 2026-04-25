import SwiftUI
import LisperCore

struct LisperPrototypeApp: App {
    @StateObject private var coordinator = LisperAppCoordinator()

    var body: some Scene {
        WindowGroup("Lisper") {
            LisperContentView(model: coordinator.model)
        }
    }
}

LisperPrototypeApp.main()
