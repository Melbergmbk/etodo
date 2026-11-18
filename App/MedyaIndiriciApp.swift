import SwiftUI
import MedyaCore
import Sparkle

@main
struct MedyaIndiriciApp: App {
    var body: some Scene {
        WindowGroup {
            Text(AppIdentity.displayName)
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}
