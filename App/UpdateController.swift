import Foundation
import Sparkle
import MedyaCore

/// Sparkle'ı sarar; rozetin ihtiyaç duyduğu iki bilgiyi tutar: yeni sürüm var mı, son başarılı kontrol ne zaman.
@MainActor @Observable
final class UpdateController: NSObject, SPUUpdaterDelegate {
    private static let lastCheckKey = "lastSuccessfulUpdateCheck"

    private(set) var appUpdateAvailable = false
    private(set) var lastSuccessfulCheck: Date? = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    func badge(at now: Date) -> UpdateBadgeState {
        UpdateSchedule.badge(appUpdateAvailable: appUpdateAvailable, lastSuccessfulCheck: lastSuccessfulCheck, now: now)
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in self.appUpdateAvailable = true }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in self.appUpdateAvailable = false }
    }

    /// Ağ/appcast hatası (örn. 404) başarılı kontrol sayılmaz; "güncelleme yok" sayılır.
    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        let ns = error as NSError?
        let completed = ns == nil || (ns?.domain == SUSparkleErrorDomain && ns?.code == Int(SUError.noUpdateError.rawValue))
        guard completed else { return }
        Task { @MainActor in
            let now = Date()
            self.lastSuccessfulCheck = now
            UserDefaults.standard.set(now, forKey: Self.lastCheckKey)
        }
    }
}
