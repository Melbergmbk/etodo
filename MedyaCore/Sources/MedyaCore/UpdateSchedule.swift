import Foundation

public enum UpdateBadgeState: Sendable, Equatable {
    case hidden, updateAvailable, checkOverdue
}

public struct UpdateSchedule {
    public static let interval: TimeInterval = 2 * 24 * 3600

    public static func shouldCheck(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// Hiç başarılı kontrol yoksa (ilk kurulum) rozet gösterilmez; ilk kontrol zaten hemen yapılır.
    public static func badge(appUpdateAvailable: Bool, lastSuccessfulCheck: Date?, now: Date) -> UpdateBadgeState {
        if appUpdateAvailable { return .updateAvailable }
        guard let last = lastSuccessfulCheck else { return .hidden }
        return now.timeIntervalSince(last) >= interval ? .checkOverdue : .hidden
    }
}
