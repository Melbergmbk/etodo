import SwiftUI
import AppKit
import MedyaCore
import Sparkle

@main
struct MedyaIndiriciApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()
    @State private var updates = UpdateController()

    var body: some Scene {
        Window(AppIdentity.displayName, id: "main") {
            RootView(model: model, updates: updates)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
