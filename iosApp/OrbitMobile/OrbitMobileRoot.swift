import SharedCore
import SwiftUI

/// The shell once a profile is chosen: a tab bar instead of the Orbit bar.
struct OrbitMobileRoot: View {
    /// Owned by the gate (above any rebuild), passed through, never observed here (as MainTabView).
    let home: HomeViewModel
    let activeProfile: NuvioProfile?
    let onSwitchProfile: () -> Void

    /// One TMDB extras model for the three Home tabs (Top 10, new on the platforms, sagas…).
    @StateObject private var extras = OrbitHomeExtrasModel()
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            Tab(String(localized: "Accueil"), systemImage: "house", value: 0) {
                OrbitMobileHome(model: home, extras: extras, kind: .all)
            }
            Tab(String(localized: "Films"), systemImage: "film", value: 1) {
                OrbitMobileHome(model: home, extras: extras, kind: .movies)
            }
            Tab(String(localized: "Séries"), systemImage: "tv", value: 2) {
                OrbitMobileHome(model: home, extras: extras, kind: .series)
            }
            Tab(String(localized: "Plateformes"), systemImage: "square.grid.2x2", value: 3) {
                OrbitMobilePlatforms()
            }
            Tab(String(localized: "Réglages"), systemImage: "gearshape", value: 5) {
                OrbitMobileSettings(activeProfile: activeProfile, onSwitchProfile: onSwitchProfile)
            }
            Tab(String(localized: "Recherche"), systemImage: "magnifyingglass", value: 4, role: .search) {
                OrbitMobileSearch()
            }
        }
        .tint(.white)
        // Home's pipeline runs for the shell's life (a tab switch must not stop it).
        .onAppear {
            home.acquire()
            home.startUpcoming()
            WatchedRepository.shared.ensureLoaded()
            OrbitPlatformLogos.update()
            StageTrendingHeroModel.shared.loadIfNeeded()
            extras.load()
        }
        .onDisappear { home.release() }
    }
}

// MARK: - Plateformes (placeholder for v1)

struct OrbitMobilePlatforms: View {
    var body: some View {
        NavigationStack {
            List(OrbitPlatformBadgeKind.allCases, id: \.self) { kind in
                HStack(spacing: 14) {
                    OrbitPlatformBadge(kind: kind, size: 14)
                    Text(kind.name).font(.body.weight(.semibold))
                    Spacer()
                    Text(String(localized: "Bientôt")).font(.footnote).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
            .scrollContentBackground(.hidden)
            .background(OrbitHomeLayout.background.ignoresSafeArea())
            .navigationTitle(String(localized: "Plateformes"))
        }
    }
}

// MARK: - Réglages (placeholder for v1)

struct OrbitMobileSettings: View {
    let activeProfile: NuvioProfile?
    let onSwitchProfile: () -> Void
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var profiles: ProfilesViewModel

    var body: some View {
        NavigationStack {
            List {
                if let profile = activeProfile {
                    Section(String(localized: "Profil")) {
                        HStack(spacing: 14) {
                            OrbitAvatar(profile: profile, size: 44, avatars: profiles.avatars)
                            Text(profile.name).font(.headline)
                        }
                        Button(String(localized: "Changer de profil"), action: onSwitchProfile)
                    }
                }
                Section(String(localized: "Compte")) {
                    if let email = auth.accountEmail {
                        LabeledContent(String(localized: "Connecté"), value: email)
                    } else if auth.isAnonymous {
                        Text(String(localized: "Invité"))
                    }
                    Button(String(localized: "Se déconnecter"), role: .destructive) { auth.signOut() }
                }
                Section {
                    Text(String(localized: "Les autres réglages arrivent dans une prochaine version ; ceux de l'Apple TV se synchronisent avec votre compte."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(OrbitHomeLayout.background.ignoresSafeArea())
            .navigationTitle(String(localized: "Réglages"))
        }
    }
}
