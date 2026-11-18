import SwiftUI
import MedyaCore

/// İlk açılışta (ya da bir araç eksikse) araçları tek tek kurar.
struct SetupView: View {
    let model: AppModel

    private var kinds: [ToolKind] {
        ToolKind.displayOrder.filter(model.setupKinds.contains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.toolsState == .failed ? "Kurulum tamamlanamadı" : "Hazırlanıyor")
                    .font(.system(size: 17, weight: .semibold))
                Text("İlk açılışta indirme araçları kuruluyor. Bu bir kez olur, birkaç dakika sürebilir.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                    if index > 0 { Divider().padding(.leading, 14) }
                    SetupRow(kind: kind, progress: model.setupProgress[kind], isActive: isActive(kind),
                             failed: model.toolsState == .failed)
                }
            }
            .surface(radius: 10, strong: true)
            .padding(.top, 16)

            if model.toolsState == .failed {
                if let error = model.error {
                    ErrorBanner(error: error, diagnostics: model.diagnostics, onClose: nil)
                        .padding(.top, 16)
                        .transition(.opacity)
                }
                HStack {
                    Spacer()
                    Button("Tekrar dene") { Task { await model.prepareTools() } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 16)
            }
        }
    }

    /// Kurulum sırası çekirdeğin sırasıdır; ilk bitmemiş araç etkin sayılır.
    private func isActive(_ kind: ToolKind) -> Bool {
        guard model.toolsState == .preparing else { return false }
        let pending = ToolKind.allCases.filter { model.setupKinds.contains($0) && (model.setupProgress[$0] ?? 0) < 1 }
        return pending.first == kind
    }
}

private struct SetupRow: View {
    let kind: ToolKind
    let progress: Double?
    let isActive: Bool
    let failed: Bool

    private var done: Bool { (progress ?? 0) >= 1 }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(kind.purpose)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            trailing
                .frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityState)
    }

    @ViewBuilder
    private var trailing: some View {
        if done {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 15))
                .transition(.opacity)
        } else if isActive {
            HStack(spacing: 8) {
                ProgressView(value: progress ?? 0)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .animation(.smooth(duration: 0.4), value: progress)
                Text("%\(Int(((progress ?? 0) * 100).rounded()))")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        } else {
            Text(failed ? "Kurulmadı" : "Sırada")
                .font(.system(size: 11.5))
                .foregroundStyle(failed ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
        }
    }

    private var accessibilityState: String {
        if done { return "Kuruldu" }
        if isActive { return "Kuruluyor, yüzde \(Int(((progress ?? 0) * 100).rounded()))" }
        return failed ? "Kurulmadı" : "Sırada"
    }
}
