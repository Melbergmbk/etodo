import SwiftUI

/// Önizlemenin altındaki düğme; ilerleme İndirmeler listesinde görünür.
struct DownloadBar: View {
    let model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if model.preview == .gallery {
                    Text("Hepsi tek klasöre, orijinal kalitede iner.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(title) { model.startDownload() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canDownload)
        }
        .frame(minHeight: 32)
    }

    private var title: String {
        if model.isBusy { return "Sıraya ekle" }
        return model.preview == .gallery ? "Fotoğrafları indir" : "İndir"
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
        DownloadBar(model: .preview(site: .instagram, preview: .gallery))
    }
    .padding(24)
    .frame(width: 520)
}
