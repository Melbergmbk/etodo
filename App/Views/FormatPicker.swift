import SwiftUI
import MedyaCore

struct FormatPicker: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OptionRow(label: "Biçim") {
                HStack(spacing: 6) {
                    Chip(title: "MP4 video", selected: model.formatKind == .video) { model.formatKind = .video }
                    Chip(title: "MP3 ses", selected: model.formatKind == .audio) { model.formatKind = .audio }
                }
            }
            OptionRow(label: "Kalite") {
                quality
            }
            if model.offersSubtitles {
                OptionRow(label: "Altyazı") {
                    Toggle("Türkçe ya da İngilizce altyazı ekle (varsa)", isOn: $model.subtitles)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }
            }
            if showsQuickTimeNote {
                Label("Bu kalite Mac'in QuickTime oynatıcısında açılmaz; IINA ya da VLC ile açılır. Her yerde açılması için 1080p seç.",
                      systemImage: "info.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 70)
            }
        }
        .disabled(model.isBusy)
    }

    @ViewBuilder
    private var quality: some View {
        if model.formatKind == .audio {
            Picker("Kalite", selection: $model.audioKbps) {
                ForEach(AppModel.audioRates, id: \.self) { Text(Self.withSize("\($0) kbps", info?.estimatedAudioBytes(kbps: $0))).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        } else if model.qualityOptions.isEmpty || model.qualityIsOriginal {
            Text(model.qualityIsOriginal ? "Orijinal kalite" : "En iyi kalite")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            Picker("Kalite", selection: $model.videoHeight) {
                ForEach(model.qualityOptions, id: \.self) {
                    Text(Self.withSize(Self.label(for: info?.qualityName(forHeight: $0) ?? $0), info?.estimatedVideoBytes(maxHeight: $0))).tag(Optional($0))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var showsQuickTimeNote: Bool {
        guard model.formatKind == .video, !model.qualityIsOriginal, let info else { return false }
        return !info.opensInQuickTime(maxHeight: model.videoHeight)
    }

    private var info: MediaInfo? {
        if case .media(let info) = model.preview { return info }
        return nil
    }

    /// "1080p · ≈ 245 MB"; boyut bilinmiyorsa yalnız etiket.
    static func withSize(_ label: String, _ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return label }
        return "\(label)  ·  ≈ \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }

    static func label(for height: Int) -> String {
        switch height {
        case 2160...: "\(height)p · 4K"
        case 1440..<2160: "\(height)p · 2K"
        default: "\(height)p"
        }
    }
}

struct OptionRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

private struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.06)),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .opacity(isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.smooth(duration: 0.15), value: selected)
    }
}

#Preview {
    FormatPicker(model: .preview(site: .youtube, preview: .media(AppModel.sampleInfo)))
        .padding(24)
        .frame(width: 520)
}
