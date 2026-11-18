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
            switch model.toolsState {
            case .ready:
                content
            case .checking, .preparing, .failed:
                PreparingView(model: model)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .background(WindowGlass().ignoresSafeArea())
        .animation(motion, value: model.toolsState)
        .task { await model.prepareTools() }
    }

    private var content: some View {
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
                ErrorBanner(error: error) { model.error = nil }
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
            PreviewCard.Skeleton()
                .padding(.top, 16)
                .transition(.opacity)
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

private struct PreparingView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            switch model.toolsState {
            case .preparing(let fraction):
                Text("Hazırlanıyor…")
                    .font(.system(size: 14, weight: .semibold))
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 260)
                    .animation(.smooth, value: fraction)
                Text("İlk açılışta gerekli araçlar indiriliyor. Bu bir kez olur.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            case .failed:
                if let error = model.error {
                    ErrorBanner(error: error, onClose: nil)
                }
                Button("Tekrar dene") { Task { await model.prepareTools() } }
                    .controlSize(.large)
            default:
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
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
private struct WindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = GlassView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
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
    MainView(model: .preview())
}

#Preview("Önizleme yüklü") {
    MainView(model: .preview(site: .youtube, link: "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
                             preview: .media(AppModel.sampleInfo)))
}

#Preview("Yükleniyor") {
    MainView(model: .preview(site: .youtube, link: "https://www.youtube.com/watch?v=aqz-KE-bpKQ", preview: .loading))
}

#Preview("İndiriliyor") {
    MainView(model: .preview(site: .youtube, link: "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
                             preview: .media(AppModel.sampleInfo),
                             phase: .downloading(fraction: 0.62, bytesPerSecond: 3_100_000, eta: 14)))
}

#Preview("Hata") {
    MainView(model: .preview(site: .instagram, link: "https://www.instagram.com/p/DA1b2C3d4E5/",
                             error: ShownError(error: .instagramLoginRequired(.chrome),
                                               details: "ERROR: [Instagram] DA1b2C3d4E5: Requested content is not available, rate-limit reached or login required")))
}

#Preview("Instagram galerisi") {
    MainView(model: .preview(site: .instagram, link: "https://www.instagram.com/p/DA1b2C3d4E5/", preview: .gallery))
}
