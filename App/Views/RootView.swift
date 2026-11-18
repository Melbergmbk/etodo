import SwiftUI
import MedyaCore

/// Ana pencere akışı: hukuki uyarı → (araç eksikse) kurulum → ana görünüm.
struct RootView: View {
    let model: AppModel
    let updates: UpdateController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.25) }

    var body: some View {
        Group {
            if !model.disclaimerAccepted {
                DisclaimerView { model.acceptDisclaimer() }
                    .transition(.opacity)
            } else {
                switch model.toolsState {
                case .ready:
                    MainView(model: model)
                        .transition(.opacity)
                case .preparing, .failed:
                    SetupView(model: model)
                        .transition(.opacity)
                case .checking:
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
        .windowChrome()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 10) {
                    UpdateBadge(updates: updates)
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Ayarlar (⌘,)")
                    .accessibilityLabel("Ayarlar")
                }
            }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Toast(text: toast)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(motion, value: model.disclaimerAccepted)
        .animation(motion, value: model.toolsState)
        .animation(motion, value: model.toast)
        .task(id: model.disclaimerAccepted) { await model.prepareTools() }
    }
}

/// Kendiliğinden kaybolan küçük bildirim.
private struct Toast: View {
    let text: String

    var body: some View {
        Label {
            Text(text).font(.system(size: 12, weight: .medium))
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .accessibilityAddTraits(.isStaticText)
    }
}

extension View {
    /// Ana pencerenin ortak kenar boşlukları, genişliği ve buzlu cam zemini.
    func windowChrome() -> some View {
        self
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(GlassBackground())
    }
}

/// Başlık çubuğu dahil tüm pencere buzlu cam: macOS 15+ SwiftUI'nin pencere zemini, öncesinde NSVisualEffectView.
private struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .background(WindowGlass().ignoresSafeArea())
                .containerBackground(.clear, for: .window)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content.background(WindowGlass().ignoresSafeArea())
        }
    }
}
