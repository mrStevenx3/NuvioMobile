import SwiftUI
import SharedCore

// Orbit Réglages (Steven, 2026-10-24): the settings, rebuilt from scratch. Orbit is a platform of
// its own, like Netflix or Disney+: one look, so no theme, poster, layout or font settings — only
// what touches how Steven watches (playback, languages, sources, accounts).
//
// Layout (as the Apple TV's own settings, Orbit's way): the six sections on the left; the
// focused section's settings on the right, changing as the focus walks the list. Right goes into
// the settings, Menu from them comes back to the list, Menu on the list goes up to the Orbit bar.
// Choices and sub-pages open on top (the page's own navigation stack).

enum OrbitSettingsSection: String, CaseIterable, Identifiable, Hashable {
    case account
    case playback
    case languages
    case sources
    case services
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return String(localized: "Compte et profils")
        case .playback: return String(localized: "Lecture")
        case .languages: return String(localized: "Langues et sous-titres")
        case .sources: return String(localized: "Sources")
        case .services: return String(localized: "Services connectés")
        case .about: return String(localized: "À propos")
        }
    }

    var icon: String {
        switch self {
        case .account: return "person.crop.circle"
        case .playback: return "play.rectangle"
        case .languages: return "captions.bubble"
        case .sources: return "square.stack.3d.up"
        case .services: return "link"
        case .about: return "info.circle"
        }
    }

    /// Search's "Open search sources" sends "sources".
    init?(openRequest raw: String) {
        switch raw {
        case "sources": self = .sources
        default: self.init(rawValue: raw)
        }
    }
}

/// A question asked before something that cannot be undone.
enum OrbitSettingsConfirm: Identifiable, Equatable {
    case signOut
    case useOfficialServer
    case disconnectTrakt
    case disconnectSimkl
    case disconnectMdbList
    case disconnectDebrid(String)
    case removePluginRepository(String)

    var id: String {
        switch self {
        case .signOut: return "signOut"
        case .useOfficialServer: return "official"
        case .disconnectTrakt: return "trakt"
        case .disconnectSimkl: return "simkl"
        case .disconnectMdbList: return "mdblist"
        case .disconnectDebrid(let id): return "debrid:\(id)"
        case .removePluginRepository(let url): return "plugin:\(url)"
        }
    }
}

struct OrbitSettingsView: View {
    /// The section to open (Search asks for "sources"); consumed on arrival.
    @Binding var openRequest: OrbitSettingsSection?

    @StateObject private var model = SettingsViewModel()
    @StateObject private var trakt = TraktViewModel()
    @StateObject private var simkl = SimklViewModel()
    @StateObject private var debrid = DebridViewModel()
    @StateObject private var remote = RemoteSetupViewModel()
    @StateObject private var plugins = PluginsViewModel()
    @StateObject private var mdblist = MdbListViewModel()
    @EnvironmentObject private var auth: AuthViewModel

    @State private var selected: OrbitSettingsSection = .account
    @FocusState private var focusedSection: OrbitSettingsSection?
    @State private var confirm: OrbitSettingsConfirm?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                OrbitHomeLayout.background.ignoresSafeArea()

                HStack(alignment: .top, spacing: 70) {
                    sectionList
                    content
                }
                .padding(.leading, OrbitHomeLayout.margin)
                .padding(.top, 140)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            model.start()
            trakt.start()
            simkl.start()
            debrid.start()
            plugins.start()
            mdblist.start()
            takeOpenRequest()
        }
        .onDisappear {
            model.stop()
            trakt.stop()
            simkl.stop()
            debrid.stop()
            plugins.stop()
            mdblist.stop()
            remote.stop()
        }
        .onChange(of: openRequest) { _, _ in takeOpenRequest() }
        .alert(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
               presenting: confirm) { asked in
            Button(confirmButton(asked), role: .destructive) { perform(asked) }
            Button(String(localized: "Annuler"), role: .cancel) {}
        } message: { asked in
            Text(confirmMessage(asked))
        }
        .alert(String(localized: "Appliquer les changements du navigateur ?"),
               isPresented: Binding(get: { remote.pendingChange != nil }, set: { if !$0 { remote.rejectPending() } })) {
            Button(String(localized: "Appliquer")) { remote.confirmPending() }
            Button(String(localized: "Refuser"), role: .cancel) { remote.rejectPending() }
        } message: {
            Text(remote.pendingSummary)
        }
    }

    private func takeOpenRequest() {
        guard let request = openRequest else { return }
        selected = request
        openRequest = nil
        DispatchQueue.main.async { focusedSection = request }
    }

    // MARK: Sections list

    private var sectionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Réglages")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.leading, 8)
                .padding(.bottom, 28)
            ForEach(OrbitSettingsSection.allCases) { section in
                Button {
                    selected = section
                } label: {
                    OrbitSettingsSectionLabel(section: section, selected: selected == section)
                }
                .buttonStyle(OrbitSettingsSectionStyle(selected: selected == section))
                .focused($focusedSection, equals: section)
            }
        }
        .frame(width: 470, alignment: .leading)
        .focusSection()
        .onChange(of: focusedSection) { _, section in
            if let section, section != selected { selected = section }
        }
        // Menu on the list: up to the Orbit bar.
        .onExitCommand { NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil) }
        .defaultFocus($focusedSection, selected)
    }

    // MARK: Content

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 46) {
                Text(selected.title)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color.white)
                sectionContent(selected)
            }
            .padding(.top, 6)
            .padding(.bottom, 120)
            .padding(.horizontal, 24)
            .id(selected)
        }
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        // Menu in the settings: back to the list, on the section being read.
        .onExitCommand { focusedSection = selected }
    }

    @ViewBuilder
    private func sectionContent(_ section: OrbitSettingsSection) -> some View {
        switch section {
        case .account:
            OrbitAccountSection(remote: remote, confirm: $confirm)
        case .playback:
            OrbitPlaybackSection(model: model)
        case .languages:
            OrbitLanguagesSection(model: model)
        case .sources:
            OrbitSourcesSection(model: model, plugins: plugins, confirm: $confirm)
        case .services:
            OrbitServicesSection(model: model, trakt: trakt, simkl: simkl, mdblist: mdblist,
                                 debrid: debrid, confirm: $confirm)
        case .about:
            OrbitAboutSection()
        }
    }

    // MARK: Confirmations

    private var confirmTitle: String {
        switch confirm {
        case .signOut: return auth.isAnonymous ? String(localized: "Passer à un compte Nuvio ?") : String(localized: "Se déconnecter ?")
        case .useOfficialServer: return String(localized: "Revenir au serveur officiel ?")
        case .disconnectTrakt: return String(localized: "Déconnecter Trakt ?")
        case .disconnectSimkl: return String(localized: "Déconnecter Simkl ?")
        case .disconnectMdbList: return String(localized: "Déconnecter MDBList ?")
        case .disconnectDebrid: return String(localized: "Déconnecter ce service ?")
        case .removePluginRepository: return String(localized: "Supprimer ce dépôt ?")
        case nil: return ""
        }
    }

    private func confirmButton(_ asked: OrbitSettingsConfirm) -> String {
        switch asked {
        case .signOut: return auth.isAnonymous ? String(localized: "Continuer") : String(localized: "Se déconnecter")
        case .useOfficialServer: return String(localized: "Changer")
        case .removePluginRepository: return String(localized: "Supprimer")
        default: return String(localized: "Déconnecter")
        }
    }

    private func confirmMessage(_ asked: OrbitSettingsConfirm) -> String {
        switch asked {
        case .signOut:
            return auth.isAnonymous
                ? String(localized: "Les données invitées de cette Apple TV (profils, bibliothèque, progression) seront effacées. Tu pourras ensuite te connecter depuis l'écran d'accueil.")
                : String(localized: "Les données locales de cette Apple TV seront effacées. Tes données synchronisées restent sur ton compte Nuvio.")
        case .useOfficialServer:
            return String(localized: "Tu seras déconnecté du serveur auto-hébergé et les données locales de cette Apple TV seront effacées. Nuvio se reconnectera à api.nuvio.tv.")
        case .disconnectTrakt:
            return String(localized: "Le suivi s'arrête et l'accès de cette Apple TV est révoqué. Ton historique Trakt n'est pas touché.")
        case .disconnectSimkl:
            return String(localized: "Le suivi s'arrête et l'autorisation de cette Apple TV est effacée. Ton historique Simkl n'est pas touché.")
        case .disconnectMdbList:
            return String(localized: "MDBList ne se synchronisera plus sur cette Apple TV.")
        case .disconnectDebrid:
            return String(localized: "La clé de ce service est retirée de ce profil. Les liens ne passeront plus par lui.")
        case .removePluginRepository:
            return String(localized: "Le dépôt et ses fournisseurs seront retirés de cette Apple TV.")
        }
    }

    private func perform(_ asked: OrbitSettingsConfirm) {
        switch asked {
        case .signOut: auth.signOut()
        case .useOfficialServer: ServerConnectionController.shared.useOfficial()
        case .disconnectTrakt: trakt.disconnect()
        case .disconnectSimkl: simkl.disconnect()
        case .disconnectMdbList: mdblist.disconnect()
        case .disconnectDebrid(let id): debrid.disconnect(id)
        case .removePluginRepository(let url):
            if let repo = plugins.repositories.first(where: { $0.manifestUrl == url }) {
                plugins.removeRepository(repo)
            }
        }
        confirm = nil
    }
}

// MARK: - Section list rows

private struct OrbitSettingsSectionLabel: View {
    let section: OrbitSettingsSection
    let selected: Bool

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: section.icon)
                .font(.system(size: 28, weight: .semibold))
                .frame(width: 40)
            Text(section.title)
                .font(.system(size: 30, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
    }
}

/// The section rows: white when focused; the open section stays marked while the focus is in its
/// settings.
private struct OrbitSettingsSectionStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        OrbitSettingsSectionBody(configuration: configuration, selected: selected)
    }
}

private struct OrbitSettingsSectionBody: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .foregroundStyle(focused ? Color.black : Color.white.opacity(selected ? 1 : 0.6))
            .padding(.horizontal, 26)
            .frame(width: 470, height: 76, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(focused ? Color.white : (selected ? Color.white.opacity(0.12) : Color.clear))
            )
            .scaleEffect(focused ? 1.03 : 1)
            .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 16, y: 8)
            .animation(.easeOut(duration: 0.16), value: focused)
    }
}
