import SwiftUI

struct DownloadBar: View {
    let model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            status
                .frame(maxWidth: .infinity, alignment: .leading)
            action
        }
        .frame(minHeight: 32)
        .animation(.smooth(duration: 0.25), value: phaseKey)
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .idle:
            if model.preview == .gallery {
                Text("Hepsi tek klasöre, orijinal kalitede iner.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                // Boş görünüm yer kaplamaz; düğme sağda kalsın diye esnek bir boşluk.
                Color.clear.frame(height: 1)
            }
        case .starting:
            progress(nil, left: "İndirme başlıyor…", right: "")
        case .downloading(let fraction, let speed, let eta):
            progress(fraction,
                     left: ["%\(Int((fraction * 100).rounded()))", speed.map(Self.speed)].compactMap { $0 }.joined(separator: " · "),
                     right: eta.map { "\(PreviewCard.format($0)) kaldı" } ?? "")
        case .finishing:
            progress(nil, left: model.formatKind == .audio && model.preview != .gallery ? "MP3'e dönüştürülüyor…" : "Tamamlanıyor…",
                     right: "")
        case .done(let files):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text(files.count > 1 ? "\(files.count) dosya indirildi" : "İndirildi")
                        .font(.system(size: 13, weight: .semibold))
                    if let first = files.first {
                        Text(files.count > 1 ? DestinationPicker.displayName(first.deletingLastPathComponent()) : first.lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private func progress(_ fraction: Double?, left: String, right: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let fraction {
                    ProgressView(value: fraction)
                        .animation(.smooth(duration: 0.4), value: fraction)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .controlSize(.small)
            HStack {
                Text(left)
                Spacer()
                Text(right)
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var action: some View {
        switch model.phase {
        case .starting, .downloading, .finishing:
            Button("İptal") { model.cancelDownload() }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
        case .done:
            Button("Finder'da göster") { model.revealInFinder() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        case .idle:
            Button(model.preview == .gallery ? "Fotoğrafları indir" : "İndir") { model.startDownload() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canDownload)
        }
    }

    private var phaseKey: Int {
        switch model.phase {
        case .idle: 0
        case .starting: 1
        case .downloading: 2
        case .finishing: 3
        case .done: 4
        }
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        let tr = Locale(identifier: "tr_TR")
        if bytesPerSecond >= 1_000_000 {
            return (bytesPerSecond / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(tr)) + " MB/sn"
        }
        return (bytesPerSecond / 1_000).formatted(.number.precision(.fractionLength(0)).locale(tr)) + " KB/sn"
    }
}

#Preview {
    VStack(spacing: 24) {
        DownloadBar(model: .preview(site: .youtube, preview: .media(AppModel.sampleInfo)))
        DownloadBar(model: .preview(site: .youtube, preview: .media(AppModel.sampleInfo),
                                    phase: .downloading(fraction: 0.62, bytesPerSecond: 3_100_000, eta: 14)))
        DownloadBar(model: .preview(site: .youtube, preview: .media(AppModel.sampleInfo), phase: .finishing))
        DownloadBar(model: .preview(site: .youtube, preview: .media(AppModel.sampleInfo),
                                    phase: .done([URL(fileURLWithPath: "/tmp/Big Buck Bunny [aqz-KE-bpKQ].mp4")])))
        DownloadBar(model: .preview(site: .instagram, preview: .gallery))
    }
    .padding(24)
    .frame(width: 520)
}
