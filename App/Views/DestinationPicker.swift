import SwiftUI
import MedyaCore

struct DestinationPicker: View {
    let model: AppModel

    var body: some View {
        OptionRow(label: "Kayıt") {
            Menu {
                ForEach(model.recentFolders, id: \.self) { folder in
                    Toggle(isOn: Binding(get: { folder.standardizedFileURL == model.destination.standardizedFileURL },
                                         set: { _ in model.choose(folder) })) {
                        Text(Self.rootName(folder))
                    }
                }
                Divider()
                Button("Başka bir klasör seç…") { model.chooseOtherFolder() }
            } label: {
                Label(Self.rootName(model.destination), systemImage: "folder")
            }
            .menuStyle(.button)
            .fixedSize()
            .help(FolderLayout.root(in: model.destination).path)
        }
        .disabled(model.isBusy)
    }

    /// Kayıt yeri ayarı üst klasördür; kullanıcıya dosyaların gerçekte gittiği Etodo klasörü gösterilir.
    static func rootName(_ parent: URL) -> String {
        displayName(FolderLayout.root(in: parent))
    }

    /// "İndirilenler › Etodo" gibi kısa, okunur ad.
    static func displayName(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(home) else { return url.lastPathComponent }
        var parts = path.dropFirst(home.count).split(separator: "/").map(String.init)
        if parts.isEmpty { return "Ana klasör" }
        let known = ["Downloads": "İndirilenler", "Desktop": "Masaüstü", "Documents": "Belgeler",
                     "Movies": "Filmler", "Music": "Müzik", "Pictures": "Resimler"]
        if let name = known[parts[0]] { parts[0] = name }
        return parts.suffix(2).joined(separator: " › ")
    }
}
