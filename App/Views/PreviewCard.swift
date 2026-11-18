import SwiftUI
import MedyaCore

struct PreviewCard: View {
    enum Content {
        case media(MediaInfo)
        case gallery
    }

    let content: Content

    var body: some View {
        HStack(spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .surface()
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch content {
        case .media(let info): info.title.isEmpty ? "Başlıksız" : info.title
        case .gallery: "Galeri gönderisi"
        }
    }

    private var subtitle: String? {
        switch content {
        case .media(let info): info.uploader
        case .gallery: nil  // X görsel gönderileri de buraya düşer
        }
    }

    private var thumbnail: some View {
        Thumbnail(url: thumbnailURL, symbol: symbol)
            .overlay(alignment: .bottomTrailing) {
                if case .media(let info) = content, let duration = info.duration, duration > 0 {
                    Text(Self.format(duration))
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(5)
                }
            }
    }

    private var thumbnailURL: URL? {
        if case .media(let info) = content { return info.thumbnailURL }
        return nil
    }

    private var symbol: String {
        if case .gallery = content { return "photo.on.rectangle.angled" }
        return "play.rectangle"
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private struct Thumbnail: View {
    let url: URL?
    let symbol: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack {
            shape.fill(.quaternary)
            AsyncImage(url: url, transaction: Transaction(animation: .smooth(duration: 0.25))) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill).transition(.opacity)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: 128, height: 72)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

extension PreviewCard {
    /// Bilgi gelirken gösterilen iskelet kart.
    struct Skeleton: View {
        var body: some View {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .frame(width: 128, height: 72)
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().frame(width: 230, height: 11)
                    Capsule().frame(width: 150, height: 11)
                    Capsule().frame(width: 96, height: 9)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.quaternary)
            .shimmering()
            .padding(12)
            .surface()
            .accessibilityElement()
            .accessibilityLabel("Bilgi alınıyor")
        }
    }
}

/// Zamana bağlı parıltı; `repeatForever` kullanılmaz, böylece animasyon başka görünümlere sızmaz
/// ve iskelet kaldırıldığında arkada iz kalmaz.
private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay {
                    TimelineView(.animation) { context in
                        let period = 1.3
                        let t = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: period) / period
                        GeometryReader { geo in
                            LinearGradient(colors: [.clear, .white.opacity(0.45), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: geo.size.width * 0.45)
                                .offset(x: geo.size.width * (-0.45 + t * 1.45))
                                .blendMode(.plusLighter)
                        }
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
        }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

#Preview {
    VStack(spacing: 16) {
        PreviewCard(content: .media(AppModel.sampleInfo))
        PreviewCard(content: .gallery)
        PreviewCard.Skeleton()
    }
    .padding(24)
    .frame(width: 520)
}
