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
            MainView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
