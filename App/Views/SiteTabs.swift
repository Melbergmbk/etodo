import SwiftUI
import MedyaCore

/// Logolu segment kontrolü. Yerli segment kontrolü logoyu şablon renge boyadığından
/// (seçili sekmede resmî renk gösterilemez) ince bir özel çizim kullanılır.
struct SiteTabs: View {
    let selection: Site?
    var isDisabled = false
    let onSelect: (Site) -> Void

    @Namespace private var pill
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Site.allCases, id: \.self) { site in
                tab(site)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: selection)
    }

    private func tab(_ site: Site) -> some View {
        let selected = site == selection
        return Button { onSelect(site) } label: {
            HStack(spacing: 7) {
                SiteLogo(site: site, selected: selected)
                Text(site.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.16) : Color.white)
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(site.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SiteLogo: View {
    let site: Site
    let selected: Bool

    var body: some View {
        Group {
            switch site {
            case .youtube:
                Image(selected ? "YouTubeLogo" : "YouTubeGlyph").resizable()
            case .instagram:
                Image(selected ? "InstagramLogo" : "InstagramGlyph").resizable()
            case .other:
                Image(systemName: "globe")
                    .resizable()
                    .fontWeight(.medium)
                    .padding(1)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
        }
        .foregroundStyle(.secondary)
        .aspectRatio(contentMode: .fit)
        .frame(width: 17, height: 17)
    }
}

extension Site {
    var title: String {
        switch self {
        case .youtube: "YouTube"
        case .instagram: "Instagram"
        case .other: "Diğer"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SiteTabs(selection: nil) { _ in }
        SiteTabs(selection: .youtube) { _ in }
        SiteTabs(selection: .instagram) { _ in }
        SiteTabs(selection: .other) { _ in }
    }
    .padding(30)
}
