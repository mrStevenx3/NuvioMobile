import SharedCore
import SwiftUI

// Orbit Profils — adding or editing a profile (Steven, 2026-10-24): the avatar large on the left
// (as it will look), on the right the name, the avatars (or a plain colour), the colours; Save in
// white, Delete in red at the bottom. Menu leaves without saving.

struct OrbitProfileEditor: View {
    @ObservedObject var model: ProfilesViewModel
    let target: OrbitProfileEditTarget

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorHex: String
    @State private var avatarId: String?
    /// The picture's address: an Orbit avatar, or a custom one set elsewhere (the phone app).
    @State private var avatarUrl: String?
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool


    init(model: ProfilesViewModel, target: OrbitProfileEditTarget) {
        self.model = model
        self.target = target
        _name = State(initialValue: target.profile?.name ?? "")
        _colorHex = State(initialValue: target.profile?.avatarColorHex ?? OrbitProfileColor.palette[1])
        _avatarId = State(initialValue: target.profile?.avatarId)
        _avatarUrl = State(initialValue: target.profile?.avatarId == nil ? target.profile?.avatarUrl : nil)
    }

    private var catalogItem: AvatarCatalogItem? {
        model.avatars.first { $0.id == avatarId }
    }

    private var color: Color {
        Color(hexString: colorHex) ?? Color(red: 0.12, green: 0.53, blue: 0.9)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [color.opacity(0.35), color.opacity(0.08), .clear],
                           center: UnitPoint(x: 0.2, y: 0.4), startRadius: 0, endRadius: 1000)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: colorHex)
                .allowsHitTesting(false)

            HStack(alignment: .top, spacing: 90) {
                // The preview.
                VStack(spacing: 28) {
                    preview
                    Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Nouveau profil") : name)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .frame(width: 420)
                }
                .padding(.top, 70)
                .frame(width: 440)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 46) {
                        Text(target.profile == nil ? String(localized: "Ajouter un profil") : String(localized: "Modifier le profil"))
                            .font(.system(size: 52, weight: .bold))
                            .foregroundStyle(Color.white)

                        nameSection
                        orbitAvatarsSection
                        nuvioAvatarsSection
                        colorSection
                        actionButtons
                        deleteSection
                    }
                    .padding(.vertical, 70)
                    .padding(.trailing, 60)
                }
                .scrollClipDisabled()
            }
            .padding(.leading, 110)
        }
        .onExitCommand { dismiss() }
        .onAppear { if target.profile == nil { DispatchQueue.main.async { nameFocused = true } } }
    }

    @ViewBuilder
    private var nameSection: some View {
            section(String(localized: "Nom")) {
                TextField(String(localized: "Nom du profil"), text: $name)
                    .font(.system(size: 30, weight: .semibold))
                    .focused($nameFocused)
                    .frame(width: 900)
            }
    }

    @ViewBuilder
    private var orbitAvatarsSection: some View {
            section(String(localized: "Avatars Orbit")) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(118), spacing: 26), count: 7),
                          alignment: .leading, spacing: 26) {
                    ForEach(OrbitAvatarCatalog.all) { avatar in
                        Button {
                            avatarId = nil
                            avatarUrl = avatar.url
                        } label: {
                            CachedAsyncImage(string: avatar.url, decodeSize: .points(width: 130, height: 130))
                                .frame(width: 112, height: 112)
                                .clipShape(Circle())
                        }
                        .buttonStyle(OrbitSwatchStyle(selected: avatarId == nil && avatarUrl == avatar.url))
                        .accessibilityLabel(avatar.name)
                    }
                }
            }
    }

    @ViewBuilder
    private var nuvioAvatarsSection: some View {
            if !model.avatars.isEmpty {
                section(String(localized: "Avatars Nuvio")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(118), spacing: 26), count: 7),
                              alignment: .leading, spacing: 26) {
                        // A plain colour (no avatar).
                        Button { avatarId = nil; avatarUrl = nil } label: {
                            ZStack {
                                Circle().fill(color)
                                Text(OrbitProfileColor.initial(name))
                                    .font(.system(size: 46, weight: .bold))
                                    .foregroundStyle(Color.white)
                            }
                            .frame(width: 112, height: 112)
                        }
                        .buttonStyle(OrbitSwatchStyle(selected: avatarId == nil && avatarUrl == nil))
                        .accessibilityLabel(String(localized: "Couleur unie"))

                        ForEach(model.avatars, id: \.id) { item in
                            Button { avatarId = item.id; avatarUrl = nil } label: {
                                CachedAsyncImage(string: ProfileModelsKt.avatarStorageUrl(storagePath: item.storagePath),
                                                 decodeSize: .points(width: 130, height: 130))
                                    .frame(width: 112, height: 112)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(OrbitSwatchStyle(selected: avatarId == item.id))
                            .accessibilityLabel(item.displayName.isEmpty ? String(localized: "Avatar") : item.displayName)
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private var colorSection: some View {
            section(String(localized: "Couleur")) {
                HStack(spacing: 26) {
                    ForEach(OrbitProfileColor.palette, id: \.self) { hex in
                        Button {
                            colorHex = hex
                            avatarId = nil
                            avatarUrl = nil
                        } label: {
                            Circle()
                                .fill(Color(hexString: hex) ?? .gray)
                                .frame(width: 76, height: 76)
                        }
                        .buttonStyle(OrbitSwatchStyle(selected: hex == colorHex && avatarId == nil && avatarUrl == nil))
                    }
                }
            }
    }

    @ViewBuilder
    private var actionButtons: some View {
            HStack(spacing: 24) {
                Button { save() } label: {
                    HStack(spacing: 12) {
                        if model.isBusy { ProgressView() }
                        Text("Enregistrer")
                    }
                }
                .buttonStyle(OrbitPillStyle())
                Button(String(localized: "Annuler")) { dismiss() }
                    .buttonStyle(OrbitPillStyle())
            }
    }

    @ViewBuilder
    private var deleteSection: some View {
            if let profile = target.profile, model.profiles.count > 1 {
                Button {
                    confirmingDelete = true
                } label: {
                    Label(String(localized: "Supprimer le profil"), systemImage: "trash")
                }
                .buttonStyle(OrbitPillStyle(destructive: true))
                .alert(String(localized: "Supprimer « \(profile.name) » ?"), isPresented: $confirmingDelete) {
                    Button(String(localized: "Supprimer"), role: .destructive) {
                        model.deleteProfile(profile) { dismiss() }
                    }
                    Button(String(localized: "Annuler"), role: .cancel) {}
                } message: {
                    Text("Sa bibliothèque, sa progression et ses réglages seront effacés.")
                }
            }
    }

    private var preview: some View {
        let size: CGFloat = 300
        return ZStack {
            Circle().fill(color)
            if let item = catalogItem {
                CachedAsyncImage(string: ProfileModelsKt.avatarStorageUrl(storagePath: item.storagePath),
                                 decodeSize: .points(width: size * 1.2, height: size * 1.2))
                    .clipShape(Circle())
            } else if let url = avatarUrl, avatarId == nil {
                CachedAsyncImage(string: url, decodeSize: .points(width: size * 1.2, height: size * 1.2))
                    .clipShape(Circle())
            } else {
                Text(OrbitProfileColor.initial(name))
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title.uppercased())
                .font(.system(size: 20, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(Color.white.opacity(0.5))
            content()
        }
    }

    private func save() {
        guard !model.isBusy else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? String(localized: "Profil") : trimmed
        // A Nuvio avatar: its id and its address (shown on other devices without the catalogue).
        // An Orbit or custom avatar: its address. A colour: neither.
        let finalAvatarUrl: String? = catalogItem.map { ProfileModelsKt.avatarStorageUrl(storagePath: $0.storagePath) }
            ?? avatarUrl
        if let profile = target.profile {
            model.updateProfile(profile, name: finalName, colorHex: colorHex,
                                avatarId: avatarId, avatarUrl: finalAvatarUrl) { dismiss() }
        } else {
            model.createProfile(name: finalName, colorHex: colorHex,
                                avatarId: avatarId, avatarUrl: finalAvatarUrl) { dismiss() }
        }
    }
}

/// A round choice (avatar, colour): a white ring when chosen, a lift when focused.
private struct OrbitSwatchStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        OrbitSwatchBody(configuration: configuration, selected: selected)
    }
}

private struct OrbitSwatchBody: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 1 : (focused ? 0.6 : 0)), lineWidth: selected ? 5 : 3))
            .scaleEffect(focused ? 1.14 : 1)
            .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: 14, y: 6)
            .animation(.easeOut(duration: 0.14), value: focused)
    }
}
