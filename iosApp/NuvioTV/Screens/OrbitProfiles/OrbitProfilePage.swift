import SharedCore
import SwiftUI

// Orbit Profils — the profile page (Steven, 2026-10-24), opened from the avatar at the end of the
// Orbit bar: the profile large on the left on a halo of its colour (its name, "Profil principal"),
// on the right three actions in the settings' style — change profile, edit it, its PIN code.
// Menu goes up to the bar.

struct OrbitProfilePage: View {
    let activeProfile: NuvioProfile?
    let onSwitchProfile: () -> Void

    @EnvironmentObject private var model: ProfilesViewModel
    @State private var editing: OrbitProfileEditTarget?
    @State private var pinFlow: OrbitPinFlow?
    @State private var pinMessage: String?

    /// The live copy (its PIN state refreshes after a change).
    private var profile: NuvioProfile? {
        guard let index = activeProfile?.profileIndex else { return activeProfile }
        return model.profiles.first { $0.profileIndex == index } ?? activeProfile
    }

    var body: some View {
        let profile = profile
        let tint = profile.map(OrbitProfileColor.of) ?? Color(white: 0.3)
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [tint.opacity(0.4), tint.opacity(0.1), .clear],
                           center: UnitPoint(x: 0.22, y: 0.45), startRadius: 0, endRadius: 1100)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            HStack(alignment: .center, spacing: 110) {
                // The profile.
                VStack(spacing: 26) {
                    if let profile {
                        OrbitAvatar(profile: profile, size: 300, avatars: model.avatars)
                            .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
                        Text(profile.name)
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if profile.profileIndex == 1 {
                            Text("Profil principal")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                    }
                }
                .frame(width: 520)

                actions(profile)
                .focusSection()
            }
            .padding(.leading, 120)
            .frame(maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onAppear { model.start() }
        // Menu: up to the Orbit bar.
        .onExitCommand { NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil) }
        .fullScreenCover(item: $editing) { target in
            OrbitProfileEditor(model: model, target: target)
        }
        .fullScreenCover(item: $pinFlow) { flow in
            pinPad(flow)
        }
    }

    @ViewBuilder
    private func actions(_ profile: NuvioProfile?) -> some View {
        // The actions.
        VStack(alignment: .leading, spacing: 40) {
            OrbitSettingsGroup(title: String(localized: "Profil")) {
                OrbitSettingsAction(title: String(localized: "Changer de profil"),
                                    subtitle: String(localized: "Retour à « Qui regarde ? »."),
                                    icon: "person.2", action: onSwitchProfile)
                if let profile {
                    OrbitSettingsAction(title: String(localized: "Modifier le profil"),
                                        subtitle: String(localized: "Nom, avatar et couleur."),
                                        icon: "pencil") { edit(profile) }
                }
            }
            if let profile {
                OrbitSettingsGroup(title: String(localized: "Code PIN"),
                                   note: pinMessage ?? (model.isCloudAccount ? nil
                                       : String(localized: "Le code PIN demande un compte Nuvio."))) {
                    if model.isCloudAccount {
                        if profile.pinEnabled {
                            OrbitSettingsAction(title: String(localized: "Changer le code"),
                                                subtitle: String(localized: "Le profil demande son code à l'ouverture."),
                                                icon: "lock.rotation") { pinFlow = .current(remove: false) }
                            OrbitSettingsAction(title: String(localized: "Retirer le code"),
                                                icon: "lock.open", destructive: true) { pinFlow = .current(remove: true) }
                        } else {
                            OrbitSettingsAction(title: String(localized: "Ajouter un code PIN"),
                                                subtitle: String(localized: "4 chiffres, demandés à l'ouverture du profil."),
                                                icon: "lock") { pinFlow = .new(current: nil) }
                        }
                    }
                }
            }
        }

    }

    private func edit(_ profile: NuvioProfile) {
        if profile.pinEnabled {
            pinFlow = .unlockToEdit
        } else {
            editing = OrbitProfileEditTarget(profile: profile)
        }
    }

    @ViewBuilder
    private func pinPad(_ flow: OrbitPinFlow) -> some View {
        switch flow {
        case .unlockToEdit:
            OrbitPinPad(title: String(localized: "Code du profil"),
                        subtitle: String(localized: "Pour modifier ce profil."),
                        onCancel: { pinFlow = nil },
                        onSubmit: { pin, done in
                            guard let profile else { pinFlow = nil; return }
                            model.verifyPin(profile, pin: pin) { result in
                                guard result?.unlocked == true else { done(orbitPinError(result)); return }
                                pinFlow = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    editing = OrbitProfileEditTarget(profile: profile)
                                }
                            }
                        })
        case .current(let remove):
            OrbitPinPad(title: String(localized: "Code actuel"),
                        subtitle: remove ? String(localized: "Pour retirer le code.") : String(localized: "Avant d'en choisir un nouveau."),
                        onCancel: { pinFlow = nil },
                        onSubmit: { pin, done in
                            guard let profile else { pinFlow = nil; return }
                            if remove {
                                model.clearPin(profileIndex: profile.profileIndex, currentPin: pin) { result in
                                    guard result?.unlocked == true else { done(orbitPinError(result)); return }
                                    pinFlow = nil
                                    pinMessage = String(localized: "Code retiré.")
                                }
                            } else {
                                model.verifyPin(profile, pin: pin) { result in
                                    guard result?.unlocked == true else { done(orbitPinError(result)); return }
                                    pinFlow = .new(current: pin)
                                }
                            }
                        })
        case .new(let current):
            OrbitPinPad(title: String(localized: "Choisis un code à 4 chiffres"),
                        subtitle: String(localized: "Il sera demandé à l'ouverture de ce profil."),
                        onCancel: { pinFlow = nil },
                        onSubmit: { pin, done in
                            guard let profile else { pinFlow = nil; return }
                            model.setPin(profileIndex: profile.profileIndex, pin: pin, currentPin: current) { result in
                                guard result?.unlocked == true else { done(orbitPinError(result)); return }
                                pinFlow = nil
                                pinMessage = String(localized: "Code enregistré.")
                            }
                        })
        }
    }
}

enum OrbitPinFlow: Identifiable {
    /// The profile's code, before editing it.
    case unlockToEdit
    /// The current code, before removing it or choosing a new one.
    case current(remove: Bool)
    /// A new code (with the verified current one when changing it).
    case new(current: String?)

    var id: String {
        switch self {
        case .unlockToEdit: return "unlock"
        case .current(let remove): return "current-\(remove)"
        case .new(let current): return "new-\(current ?? "-")"
        }
    }
}
