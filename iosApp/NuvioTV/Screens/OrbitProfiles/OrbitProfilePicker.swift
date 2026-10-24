import SharedCore
import SwiftUI

// Orbit Profils — "Qui regarde ?" (Steven, 2026-10-24), at launch and from the profile page:
// black, the profiles' round avatars large in the middle with their names; the focused one grows
// with a white ring and its colour glows softly behind (as the platforms' halo); a lock on a
// protected profile; "+" to add one. "Gérer les profils" under the row switches to editing (a
// pencil on each avatar), as on Netflix.

struct OrbitProfilePicker: View {
    @ObservedObject var model: ProfilesViewModel
    var onSelected: () -> Void

    @State private var managing = false
    @State private var editing: OrbitProfileEditTarget?
    @State private var pinPrompt: OrbitPinPrompt?
    @FocusState private var focused: Int32?
    @State private var placedFocus = false

    /// The add tile's focus key.
    private static let addKey: Int32 = -1

    private var focusedProfile: NuvioProfile? {
        model.profiles.first { $0.profileIndex == focused }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            halo
            VStack(spacing: 70) {
                title
                tiles
                manageButton
            }
        }
        .animation(.easeInOut(duration: 0.45), value: focused)
        .onAppear {
            model.start()
            placeFocus(model.profiles.map(\.profileIndex))
        }
        .onChange(of: model.profiles.map(\.profileIndex)) { _, indexes in placeFocus(indexes) }
        // Menu while managing: back to choosing (else the system's own Menu).
        .onExitCommand(perform: exitAction)
        .fullScreenCover(item: $editing) { target in
            OrbitProfileEditor(model: model, target: target)
        }
        .fullScreenCover(item: $pinPrompt) { prompt in
            pinPad(prompt)
        }
    }

    /// The focused profile's colour, soft, from the middle.
    @ViewBuilder
    private var halo: some View {
        if let profile = focusedProfile {
            let color = OrbitProfileColor.of(profile)
            RadialGradient(colors: [color.opacity(0.38), color.opacity(0.1), Color.clear],
                           center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 1100)
                .ignoresSafeArea()
                .id(profile.profileIndex)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    private var title: some View {
        let text: String = managing ? String(localized: "Gérer les profils") : String(localized: "Qui regarde ?")
        return Text(text)
            .font(.system(size: 58, weight: .bold))
            .foregroundStyle(Color.white)
    }

    private var tiles: some View {
        HStack(alignment: .top, spacing: 56) {
            ForEach(model.profiles, id: \.profileIndex) { (profile: NuvioProfile) in
                Button {
                    choose(profile)
                } label: {
                    OrbitProfileTile(profile: profile, avatars: model.avatars, managing: managing)
                }
                .buttonStyle(OrbitProfileTileStyle())
                .focused($focused, equals: profile.profileIndex)
            }
            if model.profiles.count < model.maxProfiles {
                Button {
                    editing = OrbitProfileEditTarget(profile: nil)
                } label: {
                    OrbitAddProfileTile()
                }
                .buttonStyle(OrbitProfileTileStyle())
                .focused($focused, equals: Self.addKey)
            }
        }
        .focusSection()
    }

    private var manageButton: some View {
        let label: String = managing ? String(localized: "Terminé") : String(localized: "Gérer les profils")
        let icon: String = managing ? "checkmark" : "pencil"
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { managing.toggle() }
        } label: {
            Label(label, systemImage: icon)
        }
        .buttonStyle(OrbitPillStyle())
        .focusSection()
    }

    private var exitAction: (() -> Void)? {
        guard managing else { return nil }
        return { stopManaging() }
    }

    private func pinPad(_ prompt: OrbitPinPrompt) -> some View {
        let subtitle: String? = prompt.edit ? String(localized: "Ce profil est protégé.") : nil
        return OrbitPinPad(title: String(localized: "Code de \(prompt.profile.name)"),
                           subtitle: subtitle,
                           onCancel: { pinPrompt = nil },
                           onSubmit: { (pin: String, done: @escaping (String?) -> Void) in
                               model.verifyPin(prompt.profile, pin: pin) { (result: PinVerifyResult?) in
                                   if result?.unlocked == true {
                                       pinPrompt = nil
                                       perform(prompt.profile, edit: prompt.edit)
                                   } else {
                                       done(orbitPinError(result))
                                   }
                               }
                           })
    }

    private func stopManaging() {
        withAnimation(.easeInOut(duration: 0.2)) { managing = false }
    }

    /// The first time profiles are there: the active profile (else the first).
    private func placeFocus(_ indexes: [Int32]) {
        guard !placedFocus, !indexes.isEmpty else { return }
        placedFocus = true
        let target = model.activeProfile.map(\.profileIndex).flatMap { indexes.contains($0) ? $0 : nil } ?? indexes[0]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { focused = target }
    }

    private func choose(_ profile: NuvioProfile) {
        if profile.pinEnabled {
            pinPrompt = OrbitPinPrompt(profile: profile, edit: managing)
        } else {
            perform(profile, edit: managing)
        }
    }

    private func perform(_ profile: NuvioProfile, edit: Bool) {
        if edit {
            editing = OrbitProfileEditTarget(profile: profile)
        } else {
            model.select(profile)
            onSelected()
        }
    }
}

struct OrbitPinPrompt: Identifiable {
    let profile: NuvioProfile
    let edit: Bool
    var id: String { "\(profile.profileIndex)-\(edit)" }
}

/// Add (nil) or edit (a profile).
struct OrbitProfileEditTarget: Identifiable {
    let profile: NuvioProfile?
    var id: Int { profile.map { Int($0.profileIndex) } ?? -1 }
}

// MARK: - Tiles

private enum OrbitProfileTileMetrics {
    static let avatar: CGFloat = 210
}

/// A profile: its avatar (a lock if protected, a pencil while managing), its name, "Principal".
private struct OrbitProfileTile: View {
    let profile: NuvioProfile
    let avatars: [AvatarCatalogItem]
    let managing: Bool
    @Environment(\.orbitTileFocused) private var focused

    var body: some View {
        let size = OrbitProfileTileMetrics.avatar
        VStack(spacing: 22) {
            ZStack {
                OrbitAvatar(profile: profile, size: size, avatars: avatars)
                    .opacity(managing ? 0.55 : 1)
                if managing {
                    Image(systemName: "pencil")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.5), radius: 6)
                } else if profile.pinEnabled {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(Color.black.opacity(0.65)))
                        .offset(x: size * 0.36, y: size * 0.36)
                }
            }
            .overlay(Circle().strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 6))
            .scaleEffect(focused ? 1.1 : 1)
            .shadow(color: .black.opacity(focused ? 0.55 : 0.25), radius: focused ? 26 : 10, y: 10)
            Text(profile.name)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.white.opacity(focused ? 1 : 0.6))
                .lineLimit(1)
                .frame(width: size + 30)
        }
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

private struct OrbitAddProfileTile: View {
    @Environment(\.orbitTileFocused) private var focused

    var body: some View {
        let size = OrbitProfileTileMetrics.avatar
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(Color.white.opacity(focused ? 1 : 0.08))
                Circle().strokeBorder(Color.white.opacity(focused ? 0 : 0.35),
                                      style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                Image(systemName: "plus")
                    .font(.system(size: 70, weight: .semibold))
                    .foregroundStyle(focused ? Color.black : Color.white.opacity(0.8))
            }
            .frame(width: size, height: size)
            .scaleEffect(focused ? 1.1 : 1)
            Text("Ajouter")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.white.opacity(focused ? 1 : 0.6))
        }
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

/// No system focus look: the tile draws its own from `orbitTileFocused`.
private struct OrbitProfileTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OrbitProfileTileBody(configuration: configuration)
    }
}

private struct OrbitProfileTileBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .environment(\.orbitTileFocused, focused)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct OrbitTileFocusedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The profile tile holding this content is focused.
    var orbitTileFocused: Bool {
        get { self[OrbitTileFocusedKey.self] }
        set { self[OrbitTileFocusedKey.self] = newValue }
    }
}
