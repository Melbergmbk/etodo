import SwiftUI
import AppKit

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
                    HStack(spacing: 14) {
                        if error.error.needsFullDiskAccess {
                            Button("Ayarları Aç") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .controlSize(.small)
                        }
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

#Preview {
    ErrorBanner(error: ShownError(error: .instagramLoginRequired(.chrome),
                                  details: "ERROR: [Instagram] DA1b2C3d4E5: Requested content is not available, rate-limit reached or login required"),
                onClose: {})
        .padding(24)
        .frame(width: 520)
}
