import SwiftUI
import AppKit
import MedyaCore

/// Ayarlar › Araçlar — "arkada neler çalışıyor".
struct ToolsSettings: View {
    let model: AppModel
    @State private var rollbackTarget: ToolKind?
    @State private var copied = false

    private var statuses: [ToolStatus] {
        ToolKind.displayOrder.compactMap { kind in model.toolStatuses.first { $0.kind == kind } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SummaryStrip(model: model)

            VStack(spacing: 0) {
                ForEach(Array(statuses.enumerated()), id: \.element.kind) { index, status in
                    if index > 0 { Divider().padding(.leading, 14) }
                    ToolRow(status: status)
                }
            }
            .surface(radius: 10, strong: true)
            .padding(.top, 14)

            footer.padding(.top, 14)

            if let error = model.toolsError {
                ErrorBanner(error: error) { model.toolsError = nil }
                    .padding(.top, 12)
                    .transition(.opacity)
            }

            activityLog.padding(.top, 14)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .animation(.smooth(duration: 0.25), value: model.toolAction)
        .animation(.smooth(duration: 0.25), value: model.toolsError)
        .task { await model.refreshToolInfo() }
        .confirmationDialog(rollbackTarget.map { "\($0.title) önceki sürüme dönülsün mü?" } ?? "",
                            isPresented: Binding(get: { rollbackTarget != nil }, set: { if !$0 { rollbackTarget = nil } }),
                            presenting: rollbackTarget) { kind in
            Button("Önceki sürüme dön") { model.rollback(kind) }
            Button("Vazgeç", role: .cancel) {}
        } message: { _ in
            Text("Yeni sürüm silinmez; istersen sonra yeniden ona dönebilirsin. Süren bir indirme varsa bitmesi beklenir.")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Klasörü Finder'da göster") { model.revealToolsFolder() }
            Spacer()
            Menu("Önceki sürüme dön") {
                ForEach(statuses.filter(\.isReady), id: \.kind) { status in
                    Button(status.kind.title) { rollbackTarget = status.kind }
                }
            }
            .menuStyle(.button)
            .fixedSize()
            .disabled(model.toolAction != nil || !statuses.contains(where: \.isReady))
            Button("Şimdi güncelle") { model.updateToolsNow() }
                .buttonStyle(.borderedProminent)
                .disabled(model.toolAction != nil)
        }
        .controlSize(.regular)
    }

    private var activityLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Son işlemler")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(copied ? "Kopyalandı" : "Kopyala") { copyLog() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .disabled(model.activity.isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if model.activity.isEmpty {
                        Text("Henüz kayıt yok.")
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(Array(model.activity.reversed().enumerated()), id: \.offset) { _, entry in
                        Text("\(Self.shortTime(entry.date))  \(entry.message)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(entry.message)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 92)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func copyLog() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let text = model.activity.map { "\(formatter.string(from: $0.date))  \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    static func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "dd.MM HH:mm"
        return f.string(from: date)
    }

    /// "bugün 14:20", "dün 09:05", "16 Kasım 14:20"
    static func relativeTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        let cal = Calendar.current
        if cal.isDateInToday(date) { f.dateFormat = "'bugün' HH:mm" }
        else if cal.isDateInYesterday(date) { f.dateFormat = "'dün' HH:mm" }
        else { f.dateFormat = "d MMMM HH:mm" }
        return f.string(from: date)
    }
}

private struct SummaryStrip: View {
    let model: AppModel

    private enum Tone { case good, warning, busy }

    private var content: (tone: Tone, title: String, detail: String?) {
        switch model.toolAction {
        case .updating:
            return (.busy, "Güncellemeler denetleniyor…", nil)
        case .rollingBack(let kind):
            return (.busy, "\(kind.title) önceki sürüme dönülüyor…", "Süren bir indirme varsa bitmesi bekleniyor.")
        case nil:
            break
        }
        let statuses = model.toolStatuses
        let last = model.lastToolCheck.map { "Son kontrol: \(ToolsSettings.relativeTime($0))" }
        if statuses.isEmpty { return (.busy, "Araçlar denetleniyor…", nil) }
        if statuses.contains(where: { !$0.isReady }) {
            return (.warning, "Bazı araçlar kurulu değil.", "\"Şimdi güncelle\" ile kurulabilir.")
        }
        if statuses.contains(where: { !$0.verified }) {
            return (.warning, "Bazı araçların doğrulama kaydı yok.", "Araç bir sonraki sürümüne güncellendiğinde doğrulanır.")
        }
        return (.good, model.lastToolCheck == nil ? "Her şey hazır ve doğrulanmış." : "Her şey güncel ve doğrulanmış.", last)
    }

    var body: some View {
        let c = content
        let tint: Color = switch c.tone {
        case .good: .green
        case .warning: .orange
        case .busy: .accentColor
        }
        HStack(spacing: 10) {
            Group {
                switch c.tone {
                case .good: Image(systemName: "checkmark.circle.fill")
                case .warning: Image(systemName: "exclamationmark.triangle.fill")
                case .busy: ProgressView().controlSize(.small)
                }
            }
            .foregroundStyle(tint)
            .frame(width: 16, height: 16)
            Text("\(Text(c.title).fontWeight(.semibold))\(c.detail.map { " \($0)" } ?? "")")
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ToolRow: View {
    let status: ToolStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(status.kind.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(status.kind.purpose)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(status.installedVersion.map(status.kind.readableVersion) ?? "—")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .help(status.installedVersion ?? "")
            }
            HStack(spacing: 12) {
                Text("Kaynak: \(status.source)")
                    .foregroundStyle(.secondary)
                if !status.isReady {
                    Text("Kurulu değil").foregroundStyle(.orange)
                } else if status.kind == .galleryDL {
                    Check("Sağlık kontrolü", ok: status.verified)
                } else {
                    Check(status.verified ? "SHA-256 doğrulandı" : "Doğrulama kaydı yok", ok: status.verified)
                    Check("Çalışma izni", ok: true)
                }
            }
            .font(.system(size: 11.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct Check: View {
    let text: String
    let ok: Bool

    init(_ text: String, ok: Bool) {
        self.text = text
        self.ok = ok
    }

    var body: some View {
        Label(text, systemImage: ok ? "checkmark" : "exclamationmark.triangle")
            .labelStyle(TightLabel())
            .foregroundStyle(ok ? Color.green : Color.orange)
    }
}

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 9.5, weight: .bold))
            configuration.title
        }
    }
}
