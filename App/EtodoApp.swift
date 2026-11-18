import SwiftUI
import AppKit
import MedyaCore
import Sparkle

@main
struct EtodoApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()
    @State private var updates = UpdateController()

    var body: some Scene {
        Window(AppIdentity.displayName, id: "main") {
            RootView(model: model, updates: updates)
                .onAppear { delegate.model = model }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(before: .appSettings) {
                Button("Güncellemeleri Kontrol Et…") { updates.checkForUpdates() }
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.isBusy == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "İndirme sürüyor"
        alert.informativeText = "Şimdi çıkarsan indirme yarım kalır."
        alert.addButton(withTitle: "Çık")
        alert.addButton(withTitle: "Vazgeç")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// İndirme, kurulum ya da güncelleme sürerken kapanırsa araçlar arkada çalışmaya devam etmesin.
    func applicationWillTerminate(_ notification: Notification) {
        RunningProcesses.shared.terminateAll()
    }
}
