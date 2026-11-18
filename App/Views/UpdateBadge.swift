import SwiftUI
import MedyaCore

/// Başlık çubuğunun sağındaki güncelleme rozeti; gerekmedikçe görünmez.
struct UpdateBadge: View {
    let updates: UpdateController

    var body: some View {
        switch updates.badge {
        case .hidden:
            EmptyView()
        case .updateAvailable:
            Button(action: updates.checkForUpdates) {
                Label("Yeni sürüm", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Yeni sürüm var")
        case .checkOverdue:
            Button(action: updates.checkForUpdates) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Güncellemeleri kontrol et")
            .accessibilityLabel("Güncellemeleri kontrol et")
        }
    }
}
