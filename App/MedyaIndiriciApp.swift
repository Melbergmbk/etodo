import SwiftUI
import AppKit
import MedyaCore
import Sparkle

@main
struct MedyaIndiriciApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window(AppIdentity.displayName, id: "main") {
            RootView(model: model)
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
