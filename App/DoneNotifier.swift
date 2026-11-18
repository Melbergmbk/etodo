import AppKit
import UserNotifications

/// Etodo arka plandayken biten indirmeyi Mac bildirimiyle haber verir.
@MainActor
enum DoneNotifier {
    /// İzin penceresi ilk indirmede bir kez çıkar; reddedilirse sessizce geçilir.
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(_ files: [URL]) {
        guard !NSApp.isActive, let first = files.first else { return }
        let content = UNMutableNotificationContent()
        content.title = "İndirme bitti"
        content.body = files.count == 1 ? first.deletingPathExtension().lastPathComponent : "\(files.count) dosya indirildi"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
