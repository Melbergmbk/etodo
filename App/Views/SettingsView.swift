import SwiftUI
import AppKit
import MedyaCore

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("Genel", systemImage: "gearshape") }
            ToolsSettings(model: model)
                .tabItem { Label("Araçlar", systemImage: "wrench.and.screwdriver") }
            PrivacySettings()
                .tabItem { Label("Gizlilik", systemImage: "lock") }
            AboutSettings()
                .tabItem { Label("Hakkında", systemImage: "info.circle") }
        }
        .frame(width: 600)
    }
}

enum SystemSettingsLink {
    static let fullDiskAccess = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    static func openFullDiskAccess() { NSWorkspace.shared.open(fullDiskAccess) }
}

// MARK: Genel

private struct GeneralSettings: View {
    @Bindable var model: AppModel

    private var usesKeychain: Bool { [.chrome, .brave, .edge].contains(model.browser) }

    var body: some View {
        Form {
            Section {
                Picker("Tarayıcı", selection: $model.browser) {
                    ForEach(Browser.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if usesKeychain {
                    Note(symbol: "key", title: "Mac bir kez şifre sorabilir",
                         text: "Giriş gereken bir bağlantıda \(model.browser.displayName) çerezleri ilk kez okunurken macOS bir Anahtar Zinciri penceresi gösterir. Mac'inin giriş şifresini yazıp \"Her Zaman İzin Ver\"i seçersen bir daha sorulmaz.")
                }
                Note(symbol: "lock.shield",
                     title: model.browser == .safari ? "Safari için Tam Disk Erişimi gerekir" : "macOS erişime izin vermezse",
                     text: "Sistem Ayarları › Gizlilik ve Güvenlik › Tam Disk Erişimi bölümünde \(AppIdentity.displayName) uygulamasını aç, sonra uygulamayı kapatıp yeniden başlat.") {
                    Button("Tam Disk Erişimi Ayarlarını Aç") { SystemSettingsLink.openFullDiskAccess() }
                        .controlSize(.small)
                }
            } header: {
                Text("Giriş gereken bağlantılar")
            } footer: {
                Text("Instagram gibi giriş isteyen bağlantılarda bu tarayıcıdaki oturumun kullanılır. Çerezler yalnızca gerektiğinde, bu Mac'te okunur.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Kayıt") {
                LabeledContent("Varsayılan kayıt yeri") {
                    HStack(spacing: 8) {
                        Label(DestinationPicker.rootName(model.destination), systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(FolderLayout.root(in: model.destination).path)
                        Button("Değiştir…") { model.chooseOtherFolder() }
                            .controlSize(.small)
                            .disabled(model.isBusy)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Form içinde simgeli kısa açıklama satırı.
private struct Note<Accessory: View>: View {
    let symbol: String
    let title: String
    let text: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory.padding(.top, 2)
            }
        }
    }
}

extension Note where Accessory == EmptyView {
    init(symbol: String, title: String, text: String) {
        self.init(symbol: symbol, title: title, text: text) { EmptyView() }
    }
}

// MARK: Gizlilik

private struct PrivacySettings: View {
    var body: some View {
        Form {
            Section("Uygulamanın bağlandığı yerler") {
                Place(symbol: "arrow.triangle.2.circlepath", title: "GitHub",
                      text: "Uygulama güncellemeleri ve yt-dlp, Python, deno indirmeleri")
                Place(symbol: "film", title: "ffmpeg.martin-riedl.de", text: "ffmpeg ve ffprobe indirmesi")
                Place(symbol: "shippingbox", title: "PyPI (pypi.org)", text: "gallery-dl kurulumu ve güncellemesi")
                Place(symbol: "globe", title: "İndirdiğin siteler",
                      text: "YouTube, Instagram ve yapıştırdığın diğer bağlantılar")
            }
            Section("Verilerin") {
                Place(symbol: "lock.laptopcomputer", title: "Çerezler bilgisayarından çıkmaz",
                      text: "Giriş gereken bağlantılarda tarayıcı çerezlerin yalnızca bu Mac'te, indirme için okunur.")
                Place(symbol: "chart.bar.xaxis", title: "Analitik ve takip yok",
                      text: "Hesap, sunucu ya da kullanım istatistiği yok.")
                Place(symbol: "list.bullet.rectangle", title: "Linkler kaydedilmez",
                      text: "İşlem kaydında yalnızca araç sürümleri ve indirilen dosyaların adları tutulur.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Place: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13))
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Hakkında

private struct AboutSettings: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Sürüm \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text(AppIdentity.displayName)
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 8)
            Text(version)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 10) {
                Text(Disclaimer.title)
                    .font(.system(size: 13, weight: .semibold))
                DisclaimerText()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .surface(radius: 10)
            .padding(.top, 18)
        }
        .padding(24)
    }
}
