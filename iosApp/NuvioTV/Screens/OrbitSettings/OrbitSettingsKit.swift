import SwiftUI

// Orbit Réglages (Steven, 2026-10-24): the settings' own building blocks, written from scratch for
// Orbit (Chris's settings kit is gone). One look, Orbit's: rows on a soft slate that turn white
// with black text when focused, a small lift, French copy, no accent colour to choose.
//
// - `OrbitSettingsGroup`: a titled block of rows, with an optional note under it.
// - `OrbitSettingsToggle`: on / off (Select flips it).
// - `OrbitSettingsChoice`: one value among several; Select opens the list of choices (a page,
//   as in the Apple TV's own settings).
// - `OrbitSettingsAction`: a button (destructive in red).
// - `OrbitSettingsLink`: opens a page.
// - `OrbitSettingsInfo`: a value to read (focusable, so the page always scrolls to it).
// - `OrbitSettingsKeyField`: a field and its Save button (API keys, add-on addresses).
// - `OrbitSettingsCodeCard`: a device sign-in code (Trakt, Simkl, MDBList, debrid).

enum OrbitSettingsLayout {
    static let rowWidth: CGFloat = 1080
    static let radius: CGFloat = 16
    static let rest = Color.white.opacity(0.07)
    static let title = Font.system(size: 29, weight: .semibold)
    static let subtitle = Font.system(size: 22, weight: .regular)
    static let value = Font.system(size: 26, weight: .medium)
    static let heading = Font.system(size: 26, weight: .bold)
    static let note = Font.system(size: 21, weight: .regular)
}

// MARK: - Group

struct OrbitSettingsGroup<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 20, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.leading, 6)
            content()
            if let note, !note.isEmpty {
                OrbitSettingsNote(text: note)
            }
        }
        .frame(width: OrbitSettingsLayout.rowWidth, alignment: .leading)
    }
}

struct OrbitSettingsNote: View {
    let text: String
    var tone: Color = Color.white.opacity(0.5)

    var body: some View {
        Text(text)
            .font(OrbitSettingsLayout.note)
            .foregroundStyle(tone)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .frame(width: OrbitSettingsLayout.rowWidth, alignment: .leading)
    }
}

// MARK: - Row look

/// The row's look: the slate at rest, white with black text when focused, a small lift.
struct OrbitSettingsRowStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        OrbitSettingsRowBody(configuration: configuration, destructive: destructive)
    }
}

private struct OrbitSettingsRowBody: View {
    let configuration: ButtonStyle.Configuration
    let destructive: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .foregroundStyle(focused ? Color.black : (destructive ? Color(red: 1, green: 0.42, blue: 0.4) : Color.white))
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
            .frame(width: OrbitSettingsLayout.rowWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: OrbitSettingsLayout.radius, style: .continuous)
                    .fill(focused ? Color.white : OrbitSettingsLayout.rest)
            )
            .environment(\.orbitRowFocused, focused)
            .scaleEffect(focused ? 1.02 : (configuration.isPressed ? 0.99 : 1))
            .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 18, y: 8)
            .animation(.easeOut(duration: 0.16), value: focused)
    }
}

private struct OrbitRowFocusedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The row holding this content is focused (its text turns dark on the white row).
    var orbitRowFocused: Bool {
        get { self[OrbitRowFocusedKey.self] }
        set { self[OrbitRowFocusedKey.self] = newValue }
    }
}

/// Title, subtitle and an optional trailing part, as every row lays them out.
private struct OrbitSettingsRowLabel<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.orbitRowFocused) private var focused

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 40)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(OrbitSettingsLayout.title)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(OrbitSettingsLayout.subtitle)
                        .opacity(focused ? 0.65 : 0.55)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 20)
            trailing()
        }
    }
}

// MARK: - Rows

struct OrbitSettingsToggle: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            OrbitSettingsRowLabel(title: title, subtitle: subtitle) {
                OrbitSwitch(on: isOn)
            }
        }
        .buttonStyle(OrbitSettingsRowStyle())
        .accessibilityValue(isOn ? Text("Activé") : Text("Désactivé"))
    }
}

/// An on / off switch drawn in Orbit's colours.
private struct OrbitSwitch: View {
    let on: Bool
    @Environment(\.orbitRowFocused) private var focused

    var body: some View {
        let track: Color = on
            ? (focused ? Color.black : Color.white)
            : (focused ? Color.black.opacity(0.18) : Color.white.opacity(0.18))
        let knob: Color = on ? (focused ? Color.white : Color.black) : Color.white
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(track)
            Circle().fill(knob).padding(4)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .frame(width: 76, height: 42)
        .animation(.easeOut(duration: 0.18), value: on)
    }
}

struct OrbitSettingsChoice<Value: Hashable>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        NavigationLink {
            OrbitSettingsChoicePage(title: title, selection: $selection, options: options, label: label)
        } label: {
            OrbitSettingsRowLabel(title: title, subtitle: subtitle) {
                HStack(spacing: 12) {
                    Text(label(selection))
                        .font(OrbitSettingsLayout.value)
                        .opacity(0.7)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 22, weight: .bold))
                        .opacity(0.45)
                }
            }
        }
        .buttonStyle(OrbitSettingsRowStyle())
    }
}

/// The list of choices: the current one ticked; Select picks and goes back.
struct OrbitSettingsChoicePage<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Value?

    var body: some View {
        ZStack(alignment: .top) {
            OrbitHomeLayout.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.bottom, 26)
                    ForEach(options, id: \.self) { option in
                        Button {
                            selection = option
                            dismiss()
                        } label: {
                            OrbitSettingsRowLabel(title: label(option)) {
                                if option == selection {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 26, weight: .bold))
                                }
                            }
                        }
                        .buttonStyle(OrbitSettingsRowStyle())
                        .focused($focused, equals: option)
                    }
                }
                .padding(.vertical, 90)
                .frame(maxWidth: .infinity)
            }
            .scrollClipDisabled()
        }
        .defaultFocus($focused, selection)
    }
}

struct OrbitSettingsAction: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var destructive = false
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OrbitSettingsRowLabel(title: title, subtitle: subtitle, icon: icon) {
                if busy { ProgressView() }
            }
        }
        .buttonStyle(OrbitSettingsRowStyle(destructive: destructive))
    }
}

struct OrbitSettingsLink<Destination: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            OrbitSettingsRowLabel(title: title, subtitle: subtitle, icon: icon) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .bold))
                    .opacity(0.45)
            }
        }
        .buttonStyle(OrbitSettingsRowStyle())
    }
}

struct OrbitSettingsInfo: View {
    let title: String
    let value: String

    var body: some View {
        // A button doing nothing: focusable, so the page scrolls to every line.
        Button {} label: {
            OrbitSettingsRowLabel(title: title) {
                Text(value)
                    .font(OrbitSettingsLayout.value)
                    .opacity(0.7)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .buttonStyle(OrbitSettingsRowStyle())
    }
}

/// A field (API key, add-on address) and its button.
struct OrbitSettingsKeyField: View {
    let placeholder: String
    var buttonTitle: String = String(localized: "Enregistrer")
    var busy = false
    let onSave: (String) -> Void
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 18) {
            TextField(placeholder, text: $text)
                .font(OrbitSettingsLayout.title)
                .focused($fieldFocused)
                .frame(maxWidth: .infinity)
            Button {
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, !busy else { return }
                onSave(value)
                text = ""
            } label: {
                HStack(spacing: 10) {
                    if busy { ProgressView() }
                    Text(buttonTitle).font(OrbitSettingsLayout.title)
                }
            }
            .buttonStyle(OrbitSettingsCompactStyle())
        }
        .frame(width: OrbitSettingsLayout.rowWidth)
    }
}

/// A small button beside a field.
struct OrbitSettingsCompactStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OrbitSettingsCompactBody(configuration: configuration)
    }
}

private struct OrbitSettingsCompactBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .foregroundStyle(focused ? Color.black : Color.white)
            .padding(.horizontal, 34)
            .frame(height: 76)
            .background(Capsule().fill(focused ? Color.white : OrbitSettingsLayout.rest))
            .scaleEffect(focused ? 1.04 : 1)
            .animation(.easeOut(duration: 0.16), value: focused)
    }
}

/// A device sign-in: the address to open, the code to type, then Cancel.
struct OrbitSettingsCodeCard: View {
    let address: String
    let code: String
    var waiting: String = String(localized: "En attente de validation… cet écran se met à jour tout seul.")
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sur ton téléphone ou ton ordinateur, va sur")
                    .font(OrbitSettingsLayout.subtitle)
                    .foregroundStyle(Color.white.opacity(0.6))
                Text(address)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text("et entre ce code :")
                    .font(OrbitSettingsLayout.subtitle)
                    .foregroundStyle(Color.white.opacity(0.6))
                Text(code)
                    .font(.system(size: 76, weight: .bold, design: .monospaced))
                    .kerning(10)
                    .foregroundStyle(Color.white)
                    .padding(.vertical, 6)
                HStack(spacing: 14) {
                    ProgressView()
                    Text(waiting)
                        .font(OrbitSettingsLayout.note)
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .padding(30)
            .frame(width: OrbitSettingsLayout.rowWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: OrbitSettingsLayout.radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 2)
            )
            OrbitSettingsAction(title: String(localized: "Annuler"), icon: "xmark", action: onCancel)
        }
    }
}

// MARK: - Languages

enum OrbitLanguageOptions {
    static let languages: [(name: String, code: String)] = [
        ("Français", "fr"), ("Anglais", "en"), ("Espagnol", "es"), ("Allemand", "de"),
        ("Italien", "it"), ("Portugais", "pt"), ("Japonais", "ja"), ("Coréen", "ko"),
        ("Chinois", "zh"), ("Russe", "ru"), ("Hindi", "hi"), ("Arabe", "ar"), ("Vietnamien", "vi"),
    ]
    static var audio: [(name: String, code: String)] {
        [("Langue de l'Apple TV", "device"), ("Version originale", "original")] + languages
    }
    static var subtitles: [(name: String, code: String)] {
        [("Désactivés", "none"), ("Langue de l'Apple TV", "device")] + languages
    }
    static var metadata: [(name: String, code: String)] {
        [("Langue de l'Apple TV", "device")] + languages
    }

    static func name(_ code: String, in options: [(name: String, code: String)]) -> String {
        options.first { $0.code == code }?.name ?? code
    }
}
