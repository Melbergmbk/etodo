import SwiftUI

struct LinkField: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var isDisabled = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("", text: $text, prompt: Text("Linki buraya yapıştır…"))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(focus)
                .lineLimit(1)
                .truncationMode(.middle)
            if !text.isEmpty && !isDisabled {
                Button {
                    text = ""
                    focus.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Temizle")
                .accessibilityLabel("Linki temizle")
            }
            PasteButton(payloadType: String.self) { strings in
                guard let first = strings.first else { return }
                Task { @MainActor in
                    text = first.trimmingCharacters(in: .whitespacesAndNewlines)
                    focus.wrappedValue = true
                }
            }
            .labelStyle(.titleOnly)
            .controlSize(.small)
            .buttonBorderShape(.roundedRectangle)
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .frame(height: 42)
        .surface(radius: 10, strong: true)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(focus.wrappedValue ? 0.55 : 0), lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
        .disabled(isDisabled)
        .animation(.smooth(duration: 0.15), value: focus.wrappedValue)
    }
}

#Preview {
    struct Demo: View {
        @State var text = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
        @FocusState var focused: Bool
        var body: some View {
            VStack(spacing: 16) {
                LinkField(text: .constant(""), focus: $focused)
                LinkField(text: $text, focus: $focused)
            }
            .padding(24)
            .frame(width: 520)
        }
    }
    return Demo()
}
