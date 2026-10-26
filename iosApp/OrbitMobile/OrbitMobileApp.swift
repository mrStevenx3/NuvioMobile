import AVFAudio
import CoreText
import SharedCore
import SwiftUI
import UIKit

// Orbit for iPhone and iPad (v1). Same data and visual pieces as the Apple TV app (SharedCore, the
// Orbit stores and tiles); only the layout is the phone's own. The launch work below is
// `NuvioTVApp.init()`'s, minus what only the TV has (the JS plugins, the Top Shelf, the TV's
// legacy-setting migrations and debug probes).

@main
struct OrbitMobileApp: App {
    init() {
        _ = NetworkPathMonitor.shared
        ArtworkDecodeMath.seedScreenScale()
        OrbitMobileFonts.registerIfNeeded()
        OrbitMobileDefaults.apply()

        // Profiles, sync platform, add-on profile context, sync backend (appleMain: iOS too).
        TvOsProviderInstallerKt.installTvOsSharedProviders()
        // Not on iOS: `TvOsPluginsInstallerKt.installTvOsPlugins()` (tvosMain only) — no JS
        // scrapers in v1, the add-ons' own streams only.

        HeroTrailerAudioState.shared.setMuted(value: !UserDefaults.standard.bool(forKey: "trailer_audio_default_on"))
        LocalizedStrings.shared.provider = SharedStringProvider()
        StreamProbe.syncSink()
        TrailerExtractionPreferences.shared.maxVideoFps = Int32(TrailerTuning.maxFps)

        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback)
            try? session.setActive(true)
        }
    }

    var body: some Scene {
        WindowGroup {
            OrbitMobileGate()
                .preferredColorScheme(.dark)
        }
    }
}

/// `AppFontRegistrar` lives in NuvioTVApp.swift (not compiled here): the same registration.
enum OrbitMobileFonts {
    private static let filenames = ["OpenSans-Regular.ttf", "OpenSans-SemiBold.ttf", "OpenSans-Bold.ttf"]

    static func registerIfNeeded() {
        if UIFont(name: "OpenSans-Regular", size: 12) == nil {
            for filename in filenames {
                let name = (filename as NSString).deletingPathExtension
                let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                    ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                    ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Resources/Fonts")
                guard let url else { continue }
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        Theme.Font.apply(Theme.AppFontFamily.fromDefaults())
    }
}

/// The part of `OrbitSettingsPins` that matters on a fresh phone install (the rest resets Chris's
/// TV-only look settings, which this app never had): TMDB enrichment on — Orbit's logos, French
/// posters, sagas and cast come from it.
enum OrbitMobileDefaults {
    private static let onceKey = "orbit.mobile.defaults.v1"

    static func apply() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: onceKey) else { return }
        defaults.set(true, forKey: onceKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            TmdbSettingsRepository.shared.setEnabled(value: true)
        }
    }
}

// MARK: - Gate (ContentView's auth → profile → shell flow)

struct OrbitMobileGate: View {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var profiles = ProfilesViewModel()
    /// As in ContentView: `@State`, so Home's publications never re-render the gate.
    @State private var home = HomeViewModel()
    @State private var entered = false
    @State private var pendingURL: URL?
    @Environment(\.scenePhase) private var scenePhase
    @MainActor private static var autoEnterConsumed = false

    var body: some View {
        Group {
            switch auth.gate {
            case .loading:
                ZStack {
                    OrbitHomeLayout.background.ignoresSafeArea()
                    ProgressView().tint(.white)
                }
            case .welcome:
                OrbitMobileWelcome(model: auth)
            case .main:
                if entered {
                    OrbitMobileRoot(home: home, activeProfile: profiles.activeProfile,
                                    onSwitchProfile: { entered = false })
                        .environmentObject(auth)
                        .environmentObject(profiles)
                } else {
                    OrbitMobileProfilePicker(model: profiles) { entered = true }
                }
            }
        }
        .onAppear { auth.start() }
        .onChange(of: auth.gate) { _, gate in
            if gate == .welcome { Self.autoEnterConsumed = true }
            if gate == .main { autoEnterIfRemembered() }
            if gate != .main {
                entered = false
                home.stop()
            }
        }
        .onChange(of: entered) { _, isEntered in
            if isEntered {
                if let url = pendingURL {
                    pendingURL = nil
                    ExternalPlaybackReturnRouter.handle(url)
                }
            } else {
                home.stop()
                SyncManager.shared.stopPeriodicNuvioSyncPull()
            }
        }
        // Infuse's x-callback return (the only URL the phone app handles in v1).
        .onOpenURL { url in
            guard ExternalPlaybackReturnRouter.isCallback(url) else { return }
            if auth.gate == .main, entered { ExternalPlaybackReturnRouter.handle(url) } else { pendingURL = url }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                guard auth.gate == .main, entered else { return }
                let profileId = ProfileRepository.shared.activeProfileId
                SyncManager.shared.requestForegroundPull(profileId: profileId, force: false)
                SyncManager.shared.startPeriodicNuvioSyncPull(profileId: profileId)
                Task { _ = try? await DeviceSessionRegistration.shared.registerIfAuthenticated(force: false) }
            case .background:
                SyncManager.shared.stopPeriodicNuvioSyncPull()
            default:
                break
            }
        }
    }

    /// ContentView's "Open Last Profile at Launch", once per process.
    private func autoEnterIfRemembered() {
        guard !entered else { return }
        let consumed = Self.autoEnterConsumed
        Self.autoEnterConsumed = true
        profiles.start()
        guard let profile = profiles.rememberedStartupProfile(alreadyFiredThisLaunch: consumed) else { return }
        profiles.select(profile)
        entered = true
    }
}

// MARK: - Welcome (placeholder: WelcomeView / AuthView / QrSignInView are remote-driven)

struct OrbitMobileWelcome: View {
    @ObservedObject var model: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false

    var body: some View {
        ZStack {
            OrbitHomeLayout.background.ignoresSafeArea()
            VStack(spacing: 22) {
                Image("OrbitMark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 70)
                Text(String(localized: "Bienvenue sur Orbit"))
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                VStack(spacing: 12) {
                    TextField(String(localized: "E-mail"), text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(String(localized: "Mot de passe"), text: $password)
                        .textContentType(creating ? .newPassword : .password)
                }
                .textFieldStyle(.roundedBorder)
                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button {
                    model.clearError()
                    if creating { model.signUp(email: email, password: password) } else { model.signIn(email: email, password: password) }
                } label: {
                    Text(creating ? String(localized: "Créer le compte") : String(localized: "Se connecter"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .disabled(model.isBusy || email.isEmpty || password.isEmpty)
                Button(creating ? String(localized: "J'ai déjà un compte") : String(localized: "Créer un compte")) {
                    creating.toggle()
                }
                .foregroundStyle(.white.opacity(0.8))
                Button(String(localized: "Continuer sans compte")) { model.continueAsGuest() }
                    .foregroundStyle(.white.opacity(0.6))
                if model.isBusy { ProgressView().tint(.white) }
            }
            .padding(24)
            .frame(maxWidth: 420)
        }
    }
}

// MARK: - Profiles (placeholder: OrbitProfilePicker is focus-driven)

struct OrbitMobileProfilePicker: View {
    @ObservedObject var model: ProfilesViewModel
    var onSelected: () -> Void

    @State private var pinFor: NuvioProfile?
    @State private var pin = ""
    @State private var pinError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 36) {
                Text(String(localized: "Qui regarde ?"))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 24)], spacing: 28) {
                    ForEach(model.profiles, id: \.profileIndex) { (profile: NuvioProfile) in
                        Button { choose(profile) } label: {
                            VStack(spacing: 10) {
                                OrbitAvatar(profile: profile, size: 96, avatars: model.avatars)
                                    .overlay(alignment: .bottomTrailing) {
                                        if profile.pinEnabled {
                                            Image(systemName: "lock.fill")
                                                .font(.caption.bold())
                                                .padding(7)
                                                .background(Circle().fill(.black.opacity(0.7)))
                                        }
                                    }
                                Text(profile.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(OrbitPlainStyle())
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 640)
            }
        }
        .onAppear { model.start() }
        .alert(String(localized: "Code du profil"), isPresented: Binding(get: { pinFor != nil }, set: { if !$0 { pinFor = nil } })) {
            SecureField(String(localized: "Code"), text: $pin)
                .keyboardType(.numberPad)
            Button(String(localized: "Annuler"), role: .cancel) { pin = "" }
            Button(String(localized: "Valider")) { verify() }
        } message: {
            Text(pinError ?? pinFor?.name ?? "")
        }
    }

    private func choose(_ profile: NuvioProfile) {
        if profile.pinEnabled {
            pin = ""
            pinError = nil
            pinFor = profile
        } else {
            model.select(profile)
            onSelected()
        }
    }

    private func verify() {
        guard let profile = pinFor else { return }
        let entered = pin
        pin = ""
        model.verifyPin(profile, pin: entered) { (result: PinVerifyResult?) in
            if result?.unlocked == true {
                model.select(profile)
                onSelected()
            } else {
                pinError = result?.message ?? String(localized: "Code incorrect")
                pinFor = profile
            }
        }
    }
}
