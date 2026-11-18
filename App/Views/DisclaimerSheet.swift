import SwiftUI
import AppKit
import MedyaCore

/// Hukuki uyarı metni (tasarım §11a, birebir).
enum Disclaimer {
    static let title = "Kullanmadan önce"
    static let paragraphs = [
        "Bu uygulama yalnızca kişisel ve ticari olmayan kullanım içindir. İndirdiğin içeriklerin hakları, onları üretenlere aittir. İçerikleri yalnızca hak sahibinin izin verdiği ya da kanunun kişisel kullanıma imkân tanıdığı ölçüde kullan; başkalarıyla paylaşmak, yeniden yayımlamak veya ticari amaçla kullanmak senin sorumluluğundadır. İndirme yaptığın platformların kullanım koşullarına uymak da sana aittir.",
        "Uygulama hiçbir veriyi bilgisayarından dışarı göndermez; tarayıcı çerezlerin yalnızca senin bilgisayarında, indirme için kullanılır.",
    ]
    static let button = "Anladım"
}

/// Metnin kendisi; ilk açılışta ve Ayarlar › Hakkında'da aynı biçimde.
struct DisclaimerText: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Disclaimer.paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(.system(size: 13))
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
    }
}

/// İlk açılışta bir kez gösterilir; "Anladım" ile kapanır ve hatırlanır.
struct DisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Disclaimer.title)
                        .font(.system(size: 17, weight: .semibold))
                    Text("\(AppIdentity.displayName) · ilk açılış")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)

            DisclaimerText()
                .padding(16)
                .surface()
                .padding(.top, 18)

            HStack {
                Spacer()
                Button(Disclaimer.button, action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 18)
        }
    }
}

#Preview {
    DisclaimerView {}.windowChrome()
}
