import SharedCore
import SwiftUI

// Orbit Profils (Steven, 2026-10-24): the profiles' building blocks, written from scratch for
// Orbit (Chris's picker, edit form and PIN pad are gone).
//
// - `OrbitAvatar`: a profile's picture (its avatar, else its colour and initial).
// - `OrbitProfileColor`: a profile's colour (the halo behind it).
// - `OrbitPinPad`: the 4-digit code, Orbit's way (black, white keys).
// - `OrbitPillStyle`: a capsule button, white when focused.

/// A profile's picture: its avatar image (catalogue or custom), else a disc of its colour with its
/// initial.
struct OrbitAvatar: View {
    let profile: NuvioProfile
    var size: CGFloat = 170
    /// The avatar catalogue (for `avatarId`); empty is fine.
    var avatars: [AvatarCatalogItem] = []

    var body: some View {
        ZStack {
            Circle().fill(OrbitProfileColor.of(profile))
            if let url = imageUrl {
                CachedAsyncImage(string: url, decodeSize: .points(width: size * 1.2, height: size * 1.2),
                                 loading: { initialView }, failure: { initialView })
                    .clipShape(Circle())
            } else {
                initialView
            }
        }
        .frame(width: size, height: size)
    }

    private var initialView: some View {
        Text(OrbitProfileColor.initial(profile.name))
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(Color.white)
    }

    private var imageUrl: String? {
        let item = avatars.first { $0.id == profile.avatarId }
        return ProfileModelsKt.profileAvatarImageUrl(profile: profile, avatar: item)
    }
}

enum OrbitProfileColor {
    static func of(_ profile: NuvioProfile) -> Color {
        Color(hexString: profile.avatarColorHex) ?? Color(red: 0.12, green: 0.53, blue: 0.9)
    }

    static func initial(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1)).uppercased()
    }

    /// The colours offered for a profile without an avatar.
    static let palette = ["#E53935", "#1E88E5", "#8E24AA", "#43A047", "#FB8C00", "#D81B60", "#00ACC1", "#5E35B1"]
}

/// A failed PIN check, in French.
func orbitPinError(_ result: PinVerifyResult?) -> String {
    if let message = result?.message, !message.isEmpty { return message }
    if let retry = result?.retryAfterSeconds, retry > 0 {
        return String(localized: "Trop d'essais. Réessaie dans \(retry) s.")
    }
    return String(localized: "Code incorrect. Réessaie.")
}

// MARK: - Pill button

/// A capsule button: soft at rest, white with black text when focused, a small lift.
struct OrbitPillStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        OrbitPillBody(configuration: configuration, destructive: destructive)
    }
}

private struct OrbitPillBody: View {
    let configuration: ButtonStyle.Configuration
    let destructive: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .font(.system(size: 27, weight: .semibold))
            .foregroundStyle(focused ? Color.black : (destructive ? Color(red: 1, green: 0.42, blue: 0.4) : Color.white))
            .padding(.horizontal, 40)
            .frame(height: 72)
            .background(Capsule().fill(focused ? Color.white : Color.white.opacity(0.1)))
            .scaleEffect(focused ? 1.05 : (configuration.isPressed ? 0.97 : 1))
            .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 14, y: 6)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

// MARK: - PIN pad

/// The 4-digit code: the dots, then the keys. It sends the code by itself at the fourth digit.
struct OrbitPinPad: View {
    let title: String
    var subtitle: String? = nil
    let onCancel: () -> Void
    /// The code, and a callback: nil = accepted (the caller closes the pad), else the error to show.
    let onSubmit: (String, @escaping (String?) -> Void) -> Void

    @State private var pin = ""
    @State private var error: String?
    @State private var busy = false

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["cancel", "0", "delete"]]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 34) {
                VStack(spacing: 14) {
                    Text(title)
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 820)
                    }
                }
                HStack(spacing: 26) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < pin.count ? Color.white : Color.clear)
                            .overlay(Circle().strokeBorder(error != nil ? Color(red: 1, green: 0.42, blue: 0.4)
                                                                        : Color.white.opacity(0.6), lineWidth: 3))
                            .frame(width: 30, height: 30)
                    }
                }
                ZStack {
                    if let error {
                        Text(error)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.4))
                            .multilineTextAlignment(.center)
                    } else if busy {
                        ProgressView()
                    }
                }
                .frame(height: 40)
                VStack(spacing: 18) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 18) {
                            ForEach(row, id: \.self) { key in keyButton(key) }
                        }
                    }
                }
            }
        }
        .onExitCommand { onCancel() }
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        Button {
            press(key)
        } label: {
            Group {
                switch key {
                case "delete": Image(systemName: "delete.left")
                case "cancel": Image(systemName: "xmark")
                default: Text(key)
                }
            }
            .font(.system(size: 34, weight: .semibold))
            .frame(width: 130, height: 84)
        }
        .buttonStyle(OrbitPadKeyStyle())
    }

    private func press(_ key: String) {
        guard !busy else { return }
        switch key {
        case "delete":
            error = nil
            if !pin.isEmpty { pin.removeLast() }
        case "cancel":
            onCancel()
        default:
            guard pin.count < 4 else { return }
            error = nil
            pin += key
            guard pin.count == 4 else { return }
            busy = true
            let entered = pin
            onSubmit(entered) { message in
                busy = false
                if let message {
                    error = message
                    pin = ""
                }
            }
        }
    }
}

private struct OrbitPadKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OrbitPadKeyBody(configuration: configuration)
    }
}

private struct OrbitPadKeyBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .foregroundStyle(focused ? Color.black : Color.white)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(focused ? Color.white : Color.white.opacity(0.08)))
            .scaleEffect(focused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}
