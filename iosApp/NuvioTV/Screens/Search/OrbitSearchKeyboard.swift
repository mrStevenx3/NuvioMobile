import SwiftUI

/// Steven's fork (Orbit, Netflix-style Search): the query in large type with a single row of keys
/// under it — 123 / SPACE / a…z / ⌫ — drawn and focused by the app itself. Replaces tvOS's system
/// search field under the Orbit bar, where the remote could not reach the system keyboard.
struct OrbitSearchKeyboard: View {
    @ObservedObject var queryBox: SearchQueryBox

    @State private var digits = false
    @FocusState private var focusedKey: String?

    private static let letters = "abcdefghijklmnopqrstuvwxyz".map(String.init)
    private static let numbers = "0123456789".map(String.init)
    private static let modeKey = "#mode"
    private static let spaceKey = "#space"
    private static let deleteKey = "#delete"
    private static let dictateKey = "#dictate"

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 24) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48, weight: .semibold))
                Text(queryBox.text.isEmpty ? String(localized: "Rechercher") : queryBox.text)
                    .font(.system(size: 52, weight: .bold))
                    .lineLimit(1)
                    .opacity(queryBox.text.isEmpty ? 0.35 : 1)
            }
            .foregroundStyle(Color.white)

            HStack(spacing: 10) {
                key(Self.modeKey) { Text(digits ? "abc" : "123").font(.system(size: 22, weight: .semibold)) }
                key(Self.spaceKey) { Text("ESPACE").font(.system(size: 22, weight: .semibold)) }
                ForEach(digits ? Self.numbers : Self.letters, id: \.self) { char in
                    key(char) { Text(char).font(.system(size: 34, weight: .semibold)) }
                }
                key(Self.deleteKey) { Image(systemName: "delete.left").font(.system(size: 28, weight: .semibold)) }
                dictateKey
            }
            .focusSection()
            // Up from the results lands back on the key last used (the engine's default otherwise).
            .defaultFocus($focusedKey, "a", priority: .automatic)

            Rectangle()
                .fill(Color.white.opacity(0.5))
                .frame(height: 2)
        }
    }

    private func key<Label: View>(_ id: String, @ViewBuilder label: () -> Label) -> some View {
        let focused = focusedKey == id
        let wide = id.hasPrefix("#") && id != Self.deleteKey
        return Button { press(id) } label: {
            label()
                .foregroundStyle(focused ? Color.black : Color.white)
                .frame(minWidth: wide ? 96 : 46, minHeight: 58)
                .padding(.horizontal, wide ? 8 : 0)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(focused ? Color.white : (wide ? Color.white.opacity(0.14) : Color.clear))
                }
                .scaleEffect(focused ? 1.12 : 1)
                .animation(.easeOut(duration: 0.12), value: focused)
        }
        .buttonStyle(OrbitKeyButtonStyle())
        .focused($focusedKey, equals: id)
    }

    /// Pass 2 (Steven: Siri dictation is a must): a system text field drawn as a mic key. Selecting
    /// it opens tvOS's full-screen keyboard on the query, where holding the Siri button dictates and
    /// the iPhone keyboard types; the results update behind it as the text changes.
    private var dictateKey: some View {
        let focused = focusedKey == Self.dictateKey
        // Pass 3: the visible key is drawn like the letters, beside (not inside) the system field,
        // so it has no grey field box and the glyph is never scaled as a bitmap by the field's lift.
        // The field itself sits on top, nearly transparent: it takes the focus and the Select.
        return ZStack {
            Image(systemName: "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(focused ? Color.black : Color.white)
                .frame(minWidth: 46, minHeight: 58)
                .padding(.horizontal, 6)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(focused ? Color.white : Color.clear)
                }
                .scaleEffect(focused ? 1.12 : 1)
                .animation(.easeOut(duration: 0.12), value: focused)
                .allowsHitTesting(false)
            TextField("", text: $queryBox.text)
                .textFieldStyle(.plain)
                .frame(width: 58, height: 58)
                .opacity(0.011)
                .focused($focusedKey, equals: Self.dictateKey)
                .accessibilityLabel(Text("Dicter"))
        }
    }

    private func press(_ id: String) {
        switch id {
        case Self.modeKey:
            digits.toggle()
        case Self.spaceKey:
            if !queryBox.text.isEmpty, !queryBox.text.hasSuffix(" ") { queryBox.text += " " }
        case Self.deleteKey:
            if !queryBox.text.isEmpty { queryBox.text.removeLast() }
        default:
            queryBox.text += id
        }
    }
}

private struct OrbitKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}
