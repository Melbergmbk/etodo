import SwiftUI
import MedyaCore

/// Süren, sıradaki, olmayan ve biten indirmeler tek listede.
struct DownloadsList: View {
    let model: AppModel

    private var rowCount: Int { model.queue.count + model.history.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("İndirmeler")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.hasFinished {
                    Button("Bitenleri temizle") { model.clearFinished() }
                        .buttonStyle(.link)
                        .font(.system(size: 11.5))
                        .help("Listeden kaldırır; indirilen dosyalara dokunmaz.")
                }
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.queue) { item in
                        QueueRow(model: model, item: item).rowSeparator()
                    }
                    ForEach(model.history) { record in
                        HistoryRow(model: model, record: record).rowSeparator()
                    }
                }
                // 5'ten fazla satırda kaydırma çubuğu düğmelerin üstüne binmesin.
                .padding(.trailing, rowCount > 5 ? 12 : 0)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(CGFloat(rowCount), 5) * 46)
        }
    }
}

private struct QueueRow: View {
    let model: AppModel
    let item: QueueItem

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .frame(height: 46)
    }

    @ViewBuilder
    private var status: some View {
        switch item.state {
        case .queued:
            Text("\(item.detail) · Sırada").secondaryLine()
        case .failed:
            Button { model.showError(item.id) } label: {
                Text("\(item.detail) · İndirilemedi — nedenini gör")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        case .running:
            running
        }
    }

    @ViewBuilder
    private var running: some View {
        switch model.phase {
        case .downloading(let fraction, let speed, let eta):
            HStack(spacing: 8) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .frame(width: 120)
                    .animation(.smooth(duration: 0.4), value: fraction)
                Text(["%\(Int((fraction * 100).rounded()))", speed.map(DownloadBar.speed), eta.map { "\(PreviewCard.format($0)) kaldı" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .secondaryLine()
                    .monospacedDigit()
            }
        case .finishing:
            HStack(spacing: 8) {
                ProgressView().progressViewStyle(.linear).controlSize(.mini).frame(width: 120)
                Text(isAudio ? "MP3'e dönüştürülüyor…" : "Tamamlanıyor…").secondaryLine()
            }
        default:
            HStack(spacing: 8) {
                ProgressView().progressViewStyle(.linear).controlSize(.mini).frame(width: 120)
                Text("Başlıyor…").secondaryLine()
            }
        }
    }

    private var isAudio: Bool {
        if case .audio = item.request.format { true } else { false }
    }

    @ViewBuilder
    private var actions: some View {
        if case .failed = item.state {
            RowIcon(symbol: "arrow.clockwise", help: "Tekrar dene") { model.retry(item.id) }
        }
        RowIcon(symbol: "xmark", help: item.state == .running ? "İptal" : "Listeden çıkar") { model.cancel(item.id) }
    }
}

private struct HistoryRow: View {
    let model: AppModel
    let record: DownloadRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(record.detail) · \(record.finishedAt.formatted(.relative(presentation: .named).locale(Locale(identifier: "tr_TR"))))")
                    .secondaryLine()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Göster") { model.reveal(record) }
                .controlSize(.small)
            RowIcon(symbol: "arrow.clockwise", help: "Tekrar indir") { model.downloadAgain(record) }
        }
        .frame(height: 46)
    }
}

private struct RowIcon: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(hovering ? 0.08 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

private extension View {
    /// Çizgi satırın içinde kalır; liste yüksekliği satır sayısı × 46 ile tam hesaplanır.
    func rowSeparator() -> some View {
        overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }
}

private extension Text {
    func secondaryLine() -> some View {
        font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
    }
}
