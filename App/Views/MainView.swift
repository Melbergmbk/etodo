import SwiftUI
import AppKit
import MedyaCore

struct MainView: View {
    @Bindable var model: AppModel
    @FocusState private var linkFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.25) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SiteTabs(selection: model.site, isDisabled: model.isBusy) { site in
                model.select(site)
                linkFocused = true
            }
            .frame(maxWidth: .infinity)

            if model.site == nil {
                Text("Nereden indireceğini seç ya da linki yapıştır (⌘V).")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                    .transition(.opacity)
            } else {
                LinkField(text: $model.link, focus: $linkFocused, isDisabled: model.isBusy)
                    .padding(.top, 18)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = model.error {
                ErrorBanner(error: error, diagnostics: model.diagnostics) { model.error = nil }
                    .padding(.top, 16)
                    .transition(.opacity)
            }

            previewSection
        }
        .background(pasteShortcut)
        .animation(motion, value: model.site)
        .animation(motion, value: model.preview)
        .animation(motion, value: model.error)
        .onAppear { if model.site != nil { linkFocused = true } }
    }

    @ViewBuilder
    private var previewSection: some View {
        switch model.preview {
        case .empty:
            EmptyView()
        case .loading:
            // Bilgi gelince iskelet hemen kalkar; yüklü kartın arkasında iz bırakmaz.
            PreviewCard.Skeleton()
                .padding(.top, 16)
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
        case .media(let info):
            VStack(alignment: .leading, spacing: 0) {
                PreviewCard(content: .media(info))
                FormatPicker(model: model)
                    .padding(.top, 16)
                DestinationPicker(model: model)
                    .padding(.top, 10)
                DownloadBar(model: model)
                    .padding(.top, 18)
            }
            .padding(.top, 16)
            .transition(.opacity)
        case .gallery:
            VStack(alignment: .leading, spacing: 0) {
                PreviewCard(content: .gallery)
                DestinationPicker(model: model)
                    .padding(.top, 16)
                DownloadBar(model: model)
                    .padding(.top, 18)
            }
            .padding(.top, 16)
            .transition(.opacity)
        }
    }

    /// Link kutusu odakta değilken ⌘V linki yine kutuya yapıştırır; odaktayken sistemin kendi yapıştırması çalışır.
    @ViewBuilder
    private var pasteShortcut: some View {
        if !linkFocused && !model.isBusy {
            Button("Yapıştır") {
                model.pasteFromClipboard()
                linkFocused = true
            }
            .keyboardShortcut("v", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Kartlar ve alanlar için hafif zemin + ince çerçeve.
struct Surface: ViewModifier {
    var radius: CGFloat = 12
    var strong = false
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let fill = scheme == .dark ? Color.white.opacity(strong ? 0.09 : 0.05) : Color.white.opacity(strong ? 1 : 0.7)
        content
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(strong ? 0.14 : 0.08), lineWidth: 0.5))
    }
}

extension View {
    func surface(radius: CGFloat = 12, strong: Bool = false) -> some View {
        modifier(Surface(radius: radius, strong: strong))
    }
}

/// Buzlu cam pencere zemini; başlık çubuğu da camın üstünde kalır.
struct WindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = GlassView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        // Pencere arka planda kalınca da cam görünsün (görsel yön: "Cam").
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    private final class GlassView: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        }
    }
}

#Preview("Boş") {
    MainView(model: .preview()).windowChrome()
}

#Preview("Önizleme yüklü") {
    MainView(model: .preview(site: .youtube, link: "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
                             preview: .media(AppModel.sampleInfo))).windowChrome()
}

#Preview("Yükleniyor") {
    MainView(model: .preview(site: .youtube, link: "https://www.youtube.com/watch?v=aqz-KE-bpKQ", preview: .loading)).windowChrome()
}

#Preview("İndiriliyor") {
    MainView(model: .preview(site: .youtube, link: "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
                             preview: .media(AppModel.sampleInfo),
                             phase: .downloading(fraction: 0.62, bytesPerSecond: 3_100_000, eta: 14))).windowChrome()
}

#Preview("Hata") {
    MainView(model: .preview(site: .instagram, link: "https://www.instagram.com/p/DA1b2C3d4E5/",
                             error: ShownError(error: .instagramLoginRequired(.chrome),
                                               details: "ERROR: [Instagram] DA1b2C3d4E5: Requested content is not available, rate-limit reached or login required"))).windowChrome()
}

#Preview("Instagram galerisi") {
    MainView(model: .preview(site: .instagram, link: "https://www.instagram.com/p/DA1b2C3d4E5/", preview: .gallery)).windowChrome()
}
