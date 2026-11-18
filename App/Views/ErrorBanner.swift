import SwiftUI
import AppKit
import MedyaCore

struct ErrorBanner: View {
    let error: ShownError
    let onClose: (() -> Void)?

    @State private var showDetails = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 13))
                VStack(alignment: .leading, spacing: 6) {
                    Text(error.error.message)
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if error.error.needsFullDiskAccess {
                        FullDiskAccessGuide()
                    }
                    HStack(spacing: 14) {
                        if !detailText.isEmpty {
                            Button(showDetails ? "Ayrıntıları gizle" : "Ayrıntıları göster") {
                                showDetails.toggle()
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 12))
                        }
                    }
                }
                Spacer(minLength: 0)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Kapat")
                    .accessibilityLabel("Kapat")
                }
            }
            if showDetails {
                details
                    .transition(.opacity)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.28), lineWidth: 0.5))
        .animation(.smooth(duration: 0.25), value: showDetails)
    }

    private var detailText: String {
        let raw = error.details.isEmpty ? (error.error.details ?? "") : error.details
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var details: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ScrollView {
                Text(detailText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 110)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Button(copied ? "Kopyalandı" : "Kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(detailText, forType: .string)
                copied = true
            }
            .controlSize(.small)
        }
    }
}

/// Tam Disk Erişimi listesinde uygulama çoğu zaman kendiliğinden görünmez; "+" ile eklemeyi adım adım anlatır.
private struct FullDiskAccessGuide: View {
    private let appPath = Bundle.main.bundleURL.path

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            step(1) { Text("**Ayarları Aç**’a bas; Tam Disk Erişimi listesi açılır.") }
            step(2) { Text("Listede **\(AppIdentity.displayName)** yoksa en alttaki **+** düğmesine bas ve uygulamayı seç. Uygulamanın yeri:") }
            Text(appPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.leading, 22)
            step(3) { Text("**\(AppIdentity.displayName)**’nun anahtarını aç.") }
            step(4) { Text("\(AppIdentity.displayName)’yu kapatıp yeniden aç, linki tekrar dene.") }
            HStack(spacing: 8) {
                Button("Ayarları Aç") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                Button("Uygulamayı Finder’da Göster") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .font(.system(size: 12))
        .padding(.top, 2)
    }

    private func step(_ n: Int, @ViewBuilder _ text: () -> Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .frame(width: 14, height: 14)
                .background(Color.primary.opacity(0.08), in: Circle())
            text().fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Tam Disk Erişimi") {
    ErrorBanner(error: ShownError(error: .browserCookiesUnavailable(.chrome), details: ""), onClose: {})
        .padding(24)
        .frame(width: 520)
}

#Preview {
    ErrorBanner(error: ShownError(error: .instagramLoginRequired(.chrome),
                                  details: "ERROR: [Instagram] DA1b2C3d4E5: Requested content is not available, rate-limit reached or login required"),
                onClose: {})
        .padding(24)
        .frame(width: 520)
}
