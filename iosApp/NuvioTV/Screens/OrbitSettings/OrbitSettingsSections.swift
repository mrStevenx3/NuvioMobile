import Combine
import SwiftUI
import SharedCore

// Orbit Réglages — the six sections' content (Steven, 2026-10-24). The settings' values and their
// storage are unchanged (SettingsViewModel and the services' own view models); only what touches
// the look is gone.

// MARK: - Compte et profils

struct OrbitAccountSection: View {
    @ObservedObject var remote: RemoteSetupViewModel
    @Binding var confirm: OrbitSettingsConfirm?
    @EnvironmentObject private var auth: AuthViewModel
    @StateObject private var server = ActiveServerObserver()
    @StateObject private var lastProfile = RememberLastProfileModel()

    var body: some View {
        OrbitSettingsGroup(title: String(localized: "Compte Nuvio")) {
            if auth.isAnonymous {
                OrbitSettingsAction(title: String(localized: "Se connecter à Nuvio"),
                                    subtitle: String(localized: "Synchronise ta bibliothèque, ta progression et tes profils entre tes appareils. Les données invitées de cette Apple TV seront effacées."),
                                    icon: "person.crop.circle.badge.plus") { confirm = .signOut }
            } else {
                OrbitSettingsAction(title: String(localized: "Se déconnecter"),
                                    subtitle: String(localized: "Connecté avec \(auth.accountEmail ?? "ton compte Nuvio")."),
                                    icon: "rectangle.portrait.and.arrow.right",
                                    destructive: true) { confirm = .signOut }
            }
        }

        OrbitSettingsGroup(title: String(localized: "Profils")) {
            OrbitSettingsToggle(title: String(localized: "Ouvrir le dernier profil au démarrage"),
                                subtitle: String(localized: "Passe le choix du profil. Un profil protégé par un code le demande toujours."),
                                isOn: Binding(get: { lastProfile.enabled }, set: { lastProfile.set($0) }))
        }
        .onAppear { lastProfile.start() }

        OrbitSettingsGroup(title: String(localized: "Serveur")) {
            OrbitSettingsInfo(title: String(localized: "Serveur"),
                              value: server.isCustom ? server.displayHost : String(localized: "Officiel (\(server.displayHost))"))
            OrbitSettingsLink(title: server.isCustom ? String(localized: "Se connecter à un autre serveur")
                                                     : String(localized: "Se connecter à un serveur auto-hébergé"),
                              subtitle: String(localized: "Changer de serveur te déconnecte et efface les données locales de cette Apple TV."),
                              icon: "network") {
                ServerConnectionView()
            }
            if server.isCustom {
                OrbitSettingsAction(title: String(localized: "Revenir au serveur officiel"),
                                    icon: "arrow.uturn.backward", destructive: true) { confirm = .useOfficialServer }
            }
        }

        OrbitSettingsGroup(title: String(localized: "Configuration à distance"),
                           note: String(localized: "Gère tes add-ons, tes clés et tes réglages depuis le navigateur d'un téléphone ou d'un ordinateur sur le même réseau. Rien n'est appliqué sans ta confirmation ici.")) {
            if let url = remote.serverURL {
                HStack(alignment: .top, spacing: 36) {
                    if let qr = remote.qrImage {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Scanne le code, ou ouvre dans un navigateur :")
                            .font(OrbitSettingsLayout.subtitle)
                            .foregroundStyle(Color.white.opacity(0.6))
                        Text(url)
                            .font(.system(size: 34, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white)
                        Text("Garde cet écran ouvert pendant tes changements.")
                            .font(OrbitSettingsLayout.note)
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                .frame(width: OrbitSettingsLayout.rowWidth, alignment: .leading)
                OrbitSettingsAction(title: String(localized: "Arrêter la configuration à distance"), icon: "stop.circle") {
                    remote.stop()
                }
            } else {
                OrbitSettingsAction(title: String(localized: "Démarrer la configuration à distance"),
                                    subtitle: remote.startFailed
                                        ? String(localized: "Impossible de démarrer. Vérifie le réseau et réessaie.")
                                        : nil,
                                    icon: "network") { remote.start() }
            }
        }
    }
}

// MARK: - Lecture

struct OrbitPlaybackSection: View {
    @ObservedObject var model: SettingsViewModel
    @AppStorage(OrbitHomeSetting.trailersKey) private var previews = true
    @AppStorage(OrbitHomeSetting.trailerSoundKey) private var previewSound = false
    @AppStorage(EpisodeSpoilerRules.defaultsKey) private var hideSpoilers = false
    @AppStorage(TrailerStartDelay.storageKey) private var previewDelay = TrailerStartDelay.automatic.rawValue
    @AppStorage(OrbitPlayerSettings.objectAudioKey) private var objectAudio = true

    var body: some View {
        OrbitSettingsGroup(title: String(localized: "En regardant")) {
            OrbitSettingsToggle(title: String(localized: "Passer le générique"),
                                subtitle: String(localized: "Affiche un bouton pour passer les génériques de début et de fin."),
                                isOn: Binding(get: { model.skipIntroEnabled }, set: { model.setSkipIntro($0) }))
            if model.skipIntroEnabled {
                autoSkip(.intro, String(localized: "Passer les génériques de début automatiquement"))
                autoSkip(.recap, String(localized: "Passer les résumés automatiquement"))
                autoSkip(.outro, String(localized: "Passer les génériques de fin automatiquement"))
                autoSkip(.movieCredits, String(localized: "Passer le générique des films automatiquement"),
                         subtitle: String(localized: "Les scènes post-générique restent."))
            }
            OrbitSettingsToggle(title: String(localized: "Préparer l'épisode suivant"),
                                subtitle: String(localized: "Cherche les sources du prochain épisode avant la fin, pour qu'il démarre tout de suite."),
                                isOn: Binding(get: { model.preloadNextEpisodeSources }, set: { model.setPreloadNextEpisodeSources($0) }))
        }

        OrbitSettingsGroup(title: String(localized: "Aperçus et épisodes")) {
            // One switch for every trailer that starts on its own (home, platforms, studios, the
            // film's page), as Netflix's "Autoplay previews".
            OrbitSettingsToggle(title: String(localized: "Lecture automatique des aperçus"),
                                subtitle: String(localized: "Les bandes-annonces démarrent toutes seules dans Orbit."),
                                isOn: Binding(get: { previews }, set: { on in
                                    previews = on
                                    UserDefaults.standard.set(on, forKey: "detail_trailer_background")
                                    UserDefaults.standard.set(on, forKey: "inline_trailers_enabled")
                                }))
            if previews {
                OrbitSettingsToggle(title: String(localized: "Son des aperçus"),
                                    subtitle: String(localized: "Les bandes-annonces qui démarrent toutes seules jouent avec le son."),
                                    isOn: $previewSound)
                // Steven: when a trailer starts once the cursor stops on a title.
                OrbitSettingsChoice(title: String(localized: "Délai avant la lecture"),
                                    subtitle: String(localized: "Automatique : une seconde après l'arrêt du défilement."),
                                    selection: $previewDelay,
                                    options: TrailerStartDelay.allCases.map(\.rawValue),
                                    label: { raw in
                                        switch TrailerStartDelay(rawValue: raw) ?? .automatic {
                                        case .automatic: return String(localized: "Automatique")
                                        case .oneSecond: return "1 s"
                                        case .twoSeconds: return "2 s"
                                        case .threeSeconds: return "3 s"
                                        }
                                    })
            }
            OrbitSettingsToggle(title: String(localized: "Masquer les spoilers"),
                                subtitle: String(localized: "Floute les images et cache le résumé des épisodes pas encore vus."),
                                isOn: $hideSpoilers)
        }

        OrbitSettingsGroup(title: String(localized: "Image et son")) {
            OrbitSettingsToggle(title: String(localized: "Adapter la fréquence d'images"),
                                subtitle: String(localized: "L'Apple TV passe à la fréquence et à la plage dynamique de la vidéo. Active aussi « Adapter le contenu » dans Réglages › Vidéo et audio de l'Apple TV."),
                                isOn: Binding(get: { model.matchFrameRate }, set: { model.setMatchFrameRate($0) }))
            OrbitSettingsToggle(title: String(localized: "Atmos des remux Blu-ray"),
                                subtitle: String(localized: "Garde les effets de hauteur du TrueHD Atmos et du DTS:X (convertis en audio spatial Apple). Désactivé : son multicanal 7.1 sans perte."),
                                isOn: $objectAudio)
        }

        OrbitDefaultPlayerGroup()
    }

    private func autoSkip(_ type: AutoSkipSegmentType, _ title: String, subtitle: String? = nil) -> some View {
        OrbitSettingsToggle(title: title, subtitle: subtitle,
                            isOn: Binding(get: { model.isAutoSkipEnabled(type) }, set: { model.setAutoSkip(type, enabled: $0) }))
    }
}

/// The player streams open in, when an external one (Infuse…) is installed; nothing otherwise.
private struct OrbitDefaultPlayerGroup: View {
    @AppStorage("default_external_player_id") private var playerId = ""
    private let players: [ExternalPlayerApp] = ExternalPlayerPlatform.shared.availablePlayers()

    var body: some View {
        if !players.isEmpty {
            OrbitSettingsGroup(title: String(localized: "Lecteur")) {
                OrbitSettingsChoice(title: String(localized: "Lecteur par défaut"),
                                    subtitle: String(localized: "Maintiens une source pour l'ouvrir dans l'autre lecteur."),
                                    selection: $playerId,
                                    options: [""] + players.map(\.id),
                                    label: { id in id.isEmpty ? "Orbit" : (players.first { $0.id == id }?.name ?? id) })
            }
            .onAppear {
                if !playerId.isEmpty, !players.contains(where: { $0.id == playerId }) { playerId = "" }
            }
        }
    }
}

// MARK: - Langues et sous-titres

struct OrbitLanguagesSection: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        OrbitSettingsGroup(title: String(localized: "Langues préférées"),
                           note: String(localized: "Au début de la lecture, Orbit choisit la piste audio et les sous-titres dans ces langues quand ils existent.")) {
            OrbitSettingsChoice(title: String(localized: "Audio"),
                                selection: Binding(get: { model.preferredAudioLanguage }, set: { model.setPreferredAudioLanguage($0) }),
                                options: OrbitLanguageOptions.audio.map(\.code),
                                label: { OrbitLanguageOptions.name($0, in: OrbitLanguageOptions.audio) })
            OrbitSettingsChoice(title: String(localized: "Sous-titres"),
                                selection: Binding(get: { model.preferredSubtitleLanguage }, set: { model.setPreferredSubtitleLanguage($0) }),
                                options: OrbitLanguageOptions.subtitles.map(\.code),
                                label: { OrbitLanguageOptions.name($0, in: OrbitLanguageOptions.subtitles) })
            OrbitSettingsChoice(title: String(localized: "Langue des fiches"),
                                subtitle: String(localized: "Titres, résumés et logos venant de TMDB."),
                                selection: Binding(get: { model.tmdbLanguageSelection }, set: { model.setTmdbLanguage($0) }),
                                options: OrbitLanguageOptions.metadata.map(\.code),
                                label: { OrbitLanguageOptions.name($0, in: OrbitLanguageOptions.metadata) })
        }

        // Steven (2026-10-25): the size and background are the Apple TV's own (Réglages ›
        // Accessibilité › Sous-titres), which Apple's player follows; only the SDH choice stays.
        OrbitSettingsGroup(title: String(localized: "Sous-titres")) {
            if let style = model.subtitleStyle {
                OrbitSettingsToggle(title: String(localized: "Retirer les sous-titres pour sourds et malentendants"),
                                    subtitle: String(localized: "Choisit la piste normale plutôt que celle avec les descriptions de sons, quand les deux existent."),
                                    isOn: Binding(get: { style.stripSdh }, set: { model.setSubtitleStripSdh($0) }))
            } else {
                OrbitSettingsNote(text: String(localized: "Chargement…"))
            }
        }
    }
}

// MARK: - Sources

struct OrbitSourcesSection: View {
    @ObservedObject var model: SettingsViewModel
    @ObservedObject var plugins: PluginsViewModel
    @Binding var confirm: OrbitSettingsConfirm?
    @AppStorage(SearchRowsMode.defaultsKey) private var searchRowsRaw = SearchRowsMode.defaultValue.rawValue
    @State private var expanded: [String: Bool] = [:]

    var body: some View {
        OrbitSettingsGroup(title: String(localized: "Lecture automatique"),
                           note: String(localized: "Lire lance la meilleure source arrivée, dans l'ordre de la liste : le français d'abord (MULTI, VFF), puis les liens prêts tout de suite, la résolution, le Dolby Vision, l'Atmos, puis le Remux. Si elle échoue, la suivante est essayée. Maintiens Lire pour choisir.")) {
            OrbitSettingsToggle(title: String(localized: "Lancer la meilleure source"),
                                isOn: Binding(get: { model.autoPlayBestSource }, set: { model.setAutoPlayBestSource($0) }))
        }

        OrbitSettingsGroup(title: String(localized: "Recherche"),
                           note: String(localized: "Choisis les catalogues parcourus par la recherche. Moins de catalogues, des résultats plus rapides.")) {
            OrbitSettingsToggle(title: String(localized: "Recherches récentes"),
                                isOn: Binding(get: { model.recentSearchesEnabled }, set: { model.setRecentSearchesEnabled($0) }))
            OrbitSettingsChoice(title: String(localized: "Résultats"),
                                selection: Binding(get: { SearchRowsMode.resolve(searchRowsRaw) }, set: { searchRowsRaw = $0.rawValue }),
                                options: SearchRowsMode.allCases,
                                label: { $0.label })
            if model.searchSourceOptions.isEmpty {
                OrbitSettingsNote(text: String(localized: "Aucun add-on installé ne propose la recherche."))
            } else {
                ForEach(model.searchSourceOptions, id: \.key) { option in
                    let off = SearchRepository.shared.isSearchSourceDisabled(optionKey: option.key,
                                                                             disabledCatalogKeys: model.disabledSearchSourceKeys)
                    OrbitSettingsToggle(title: "\(option.catalogName) · \(option.typeLabel)",
                                        subtitle: option.addonName,
                                        isOn: Binding(get: { !off }, set: { model.setSearchSource(key: option.key, disabled: !$0) }))
                }
            }
        }

        OrbitSettingsGroup(title: String(localized: "Plugins"),
                           note: String(localized: "Les plugins ajoutent des sources. Installe un dépôt par son adresse : il se synchronise sur tes autres appareils.")) {
            OrbitSettingsToggle(title: String(localized: "Activer les plugins"),
                                isOn: Binding(get: { plugins.pluginsEnabled }, set: { plugins.setPluginsEnabled($0) }))
            OrbitSettingsKeyField(placeholder: String(localized: "Adresse du dépôt"),
                                  buttonTitle: String(localized: "Installer"),
                                  busy: plugins.isInstalling) { plugins.addRepository($0) }
            if let status = plugins.statusMessage {
                OrbitSettingsNote(text: status)
            }
            ForEach(plugins.repositories, id: \.manifestUrl) { repo in
                let open = PluginsViewModel.isRepositoryExpanded(stored: expanded[repo.manifestUrl],
                                                                 repositoryCount: plugins.repositories.count)
                let scrapers = PluginsViewModel.sortedScrapers(plugins.scrapers(in: repo))
                let on = scrapers.filter { $0.enabled }.count
                OrbitSettingsAction(title: repo.name,
                                    subtitle: String(localized: "\(on) sur \(scrapers.count) fournisseurs activés"),
                                    icon: open ? "chevron.down" : "chevron.right",
                                    busy: repo.isRefreshing) { expanded[repo.manifestUrl] = !open }
                if let error = repo.errorMessage, !error.isEmpty {
                    OrbitSettingsNote(text: error, tone: Color(red: 1, green: 0.45, blue: 0.42))
                }
                if open {
                    ForEach(scrapers, id: \.id) { scraper in
                        OrbitSettingsToggle(title: scraper.name,
                                            subtitle: scraper.description_.isEmpty ? "v\(scraper.version)" : "\(scraper.description_) · v\(scraper.version)",
                                            isOn: Binding(get: { scraper.enabled }, set: { plugins.toggleScraper(scraper, $0) }))
                    }
                    OrbitSettingsAction(title: String(localized: "Supprimer ce dépôt"), icon: "trash", destructive: true) {
                        confirm = .removePluginRepository(repo.manifestUrl)
                    }
                }
            }
            if !plugins.repositories.isEmpty {
                OrbitSettingsAction(title: String(localized: "Mettre à jour les plugins"), icon: "arrow.clockwise") {
                    plugins.refreshAll()
                }
            }
        }
    }

}

// MARK: - Services connectés

struct OrbitServicesSection: View {
    @ObservedObject var model: SettingsViewModel
    @ObservedObject var trakt: TraktViewModel
    @ObservedObject var simkl: SimklViewModel
    @ObservedObject var mdblist: MdbListViewModel
    @ObservedObject var debrid: DebridViewModel
    @Binding var confirm: OrbitSettingsConfirm?

    private static let error = Color(red: 1, green: 0.45, blue: 0.42)

    var body: some View {
        // Trakt
        OrbitSettingsGroup(title: "Trakt") {
            if !trakt.credentialsConfigured {
                OrbitSettingsNote(text: String(localized: "Trakt n'est pas configuré dans cette version."))
            } else if trakt.isConnected {
                OrbitSettingsAction(title: String(localized: "Déconnecter Trakt"),
                                    subtitle: String(localized: "Connecté en tant que \(trakt.username ?? "ton compte") · ce que tu regardes est suivi automatiquement."),
                                    icon: "checkmark.circle.fill", destructive: true) { confirm = .disconnectTrakt }
            } else if let code = trakt.deviceUserCode {
                OrbitSettingsCodeCard(address: trakt.deviceVerificationUrl ?? "https://trakt.tv/activate", code: code) {
                    trakt.cancelActivation()
                }
            } else {
                OrbitSettingsAction(title: String(localized: "Connecter Trakt"),
                                    subtitle: String(localized: "Ce que tu regardes est marqué vu sur ton profil Trakt."),
                                    icon: "antenna.radiowaves.left.and.right", busy: trakt.isLoading) { trakt.connect() }
                if let message = trakt.errorMessage { OrbitSettingsNote(text: message, tone: Self.error) }
            }
        }

        // Simkl
        OrbitSettingsGroup(title: "Simkl") {
            if !simkl.credentialsConfigured {
                OrbitSettingsNote(text: String(localized: "Simkl n'est pas configuré dans cette version."))
            } else if simkl.isConnected {
                OrbitSettingsAction(title: String(localized: "Déconnecter Simkl"),
                                    subtitle: String(localized: "Connecté en tant que \(simkl.username ?? "ton compte")."),
                                    icon: "checkmark.circle.fill", destructive: true) { confirm = .disconnectSimkl }
                OrbitSettingsAction(title: simkl.isSyncing ? String(localized: "Synchronisation…") : String(localized: "Synchroniser maintenant"),
                                    subtitle: String(localized: "Orbit vérifie Simkl tout seul toutes les 15 minutes au plus."),
                                    icon: "arrow.triangle.2.circlepath", busy: simkl.isSyncing) { simkl.syncNow() }
                if let message = simkl.syncErrorMessage { OrbitSettingsNote(text: message, tone: Self.error) }
                OrbitSettingsChoice(title: String(localized: "Identifiant des animés"),
                                    selection: Binding(get: { simkl.animeIdPreference }, set: { simkl.setAnimeIdPreference($0) }),
                                    options: ["imdb", "mal", "kitsu", "tvdb"],
                                    label: { key in
                                        switch key {
                                        case "mal": return "MyAnimeList"
                                        case "kitsu": return "Kitsu"
                                        case "tvdb": return "TVDB"
                                        default: return "IMDb"
                                        }
                                    })
            } else if let code = simkl.deviceUserCode {
                OrbitSettingsCodeCard(address: simkl.deviceVerificationUrl ?? "https://simkl.com/pin/", code: code) {
                    simkl.cancelActivation()
                }
            } else {
                OrbitSettingsAction(title: String(localized: "Connecter Simkl"),
                                    subtitle: String(localized: "Ce que tu regardes est marqué vu sur ton profil Simkl."),
                                    icon: "antenna.radiowaves.left.and.right", busy: simkl.isLoading) { simkl.connect() }
                if let message = simkl.errorMessage { OrbitSettingsNote(text: message, tone: Self.error) }
            }
        }

        // MDBList
        OrbitSettingsGroup(title: "MDBList") {
            if !mdblist.hasClientId {
                OrbitSettingsNote(text: String(localized: "MDBList n'est pas configuré dans cette version."))
            } else if mdblist.isConnected {
                OrbitSettingsAction(title: String(localized: "Déconnecter MDBList"),
                                    subtitle: String(localized: "Connecté en tant que \(mdblist.username ?? "ton compte")"),
                                    icon: "checkmark.circle.fill", destructive: true) {
                    guard !mdblist.isBusy else { return }
                    confirm = .disconnectMdbList
                }
                OrbitSettingsLink(title: String(localized: "Listes de la bibliothèque"),
                                  subtitle: String(localized: "Choisis les listes affichées dans la bibliothèque."),
                                  icon: "list.bullet.rectangle") {
                    OrbitMdbListListsPage()
                }
            } else if mdblist.isAwaitingApproval, let code = mdblist.userCode {
                OrbitSettingsCodeCard(address: mdblist.verificationUrl ?? "https://mdblist.com/device", code: code) {
                    mdblist.cancel()
                }
            } else {
                OrbitSettingsAction(title: String(localized: "Connecter MDBList"),
                                    subtitle: String(localized: "Synchronise ta liste et ton historique avec MDBList."),
                                    icon: "antenna.radiowaves.left.and.right", busy: mdblist.isBusy) {
                    guard !mdblist.isBusy else { return }
                    mdblist.connect()
                }
            }
            if let message = mdblist.errorMessage { OrbitSettingsNote(text: message, tone: Self.error) }
        }

        // Debrid
        OrbitSettingsGroup(title: "Debrid",
                           note: String(localized: "Un service debrid transforme les torrents en cache en liens directs. Les clés sont par profil.")) {
            ForEach(debrid.providers, id: \.id) { provider in
                debridRows(provider)
            }
            if debrid.hasAnyKey {
                OrbitSettingsToggle(title: String(localized: "Passer les sources par le debrid"),
                                    isOn: Binding(get: { debrid.resolverEnabled }, set: { debrid.setResolverEnabled($0) }))
                if debrid.resolverEnabled {
                    OrbitSettingsChoice(title: String(localized: "Liens préparés à l'avance"),
                                        subtitle: String(localized: "Prépare les meilleures sources pendant que la liste est ouverte, pour que Lire démarre tout de suite. Les services limitent le nombre de liens : garde un petit nombre."),
                                        selection: Binding(get: { debrid.prepareLimit }, set: { debrid.setPrepareLimit($0) }),
                                        options: [0, 1, 2, 3, 4, 5],
                                        label: { $0 == 0 ? String(localized: "Aucun") : ($0 == 1 ? String(localized: "1 lien") : String(localized: "\($0) liens")) })
                }
            }
            if debrid.resolverProviders.count > 1 {
                OrbitSettingsChoice(title: String(localized: "Service préféré"),
                                    selection: Binding(get: { debrid.activeResolverId ?? debrid.resolverProviders[0].id },
                                                       set: { debrid.setPreferredResolver($0) }),
                                    options: debrid.resolverProviders.map(\.id),
                                    label: { id in debrid.resolverProviders.first { $0.id == id }?.displayName ?? id })
            }
        }
        .onAppear { debrid.revalidateConnected() }

        // TMDB and ratings
        OrbitSettingsGroup(title: String(localized: "Fiches et notes")) {
            OrbitSettingsToggle(title: String(localized: "Enrichissement TMDB"),
                                subtitle: String(localized: "Casting, studios, sagas et meilleures images."),
                                isOn: Binding(get: { model.tmdbEnabled }, set: { model.setTmdbEnabled($0) }))
            if model.tmdbHasPersonalKey {
                OrbitSettingsAction(title: String(localized: "Retirer ma clé TMDB"),
                                    subtitle: String(localized: "Orbit reprend la clé intégrée."),
                                    icon: "trash", destructive: true) { model.clearTmdbKey() }
            } else {
                OrbitSettingsKeyField(placeholder: String(localized: "Clé TMDB personnelle (facultatif)")) { model.saveTmdbKey($0) }
            }
            OrbitSettingsToggle(title: String(localized: "Dates de sortie TMDB"),
                                subtitle: String(localized: "Les dates de TMDB remplacent celles des add-ons."),
                                isOn: Binding(get: { model.tmdbUseReleaseDates }, set: { model.setTmdbUseReleaseDates($0) }))
            OrbitSettingsToggle(title: String(localized: "Notes MDBList"),
                                subtitle: String(localized: "IMDb, Rotten Tomatoes, Metacritic, Trakt et Letterboxd sur les fiches."),
                                isOn: Binding(get: { model.mdbListEnabled }, set: { model.setMdbListEnabled($0) }))
            if model.mdbListHasPersonalKey {
                OrbitSettingsAction(title: String(localized: "Retirer ma clé MDBList"), icon: "trash", destructive: true) {
                    model.clearMdbListKey()
                }
            } else if !model.mdbListUsingAccount {
                OrbitSettingsKeyField(placeholder: String(localized: "Clé MDBList")) { model.saveMdbListKey($0) }
            }
        }

        // Where things are kept
        OrbitSettingsGroup(title: String(localized: "Bibliothèque et progression"),
                           note: String(localized: "Connecte d'abord le service plus haut ; sinon Orbit garde la bibliothèque et la progression sur Nuvio.")) {
            OrbitSettingsChoice(title: String(localized: "Bibliothèque"),
                                selection: Binding(get: { model.librarySourceMode }, set: { model.setLibrarySourceMode($0) }),
                                options: ["local", "trakt", "simkl", "mdblist"], label: Self.sourceName)
            OrbitSettingsChoice(title: String(localized: "Progression"),
                                selection: Binding(get: { model.watchProgressSource }, set: { model.setWatchProgressSource($0) }),
                                options: ["nuvio_sync", "trakt", "simkl", "mdblist"], label: Self.sourceName)
            OrbitSettingsChoice(title: String(localized: "« À voir aussi »"),
                                subtitle: String(localized: "TMDB prend le relais si le compte n'est pas connecté."),
                                selection: Binding(get: { simkl.moreLikeThisSource }, set: { simkl.setMoreLikeThisSource($0) }),
                                options: ["trakt", "simkl", "tmdb"], label: Self.sourceName)
        }
    }

    @ViewBuilder
    private func debridRows(_ provider: DebridProvider) -> some View {
        if debrid.isConnected(provider.id) {
            let expired = debrid.authFailedIds.contains(provider.id)
            OrbitSettingsAction(title: expired ? String(localized: "\(provider.displayName) · session expirée")
                                               : String(localized: "\(provider.displayName) · connecté"),
                                subtitle: expired ? String(localized: "Déconnecte puis reconnecte-toi.")
                                                  : (debrid.activeResolverId == provider.id ? String(localized: "Service actif · appuie pour déconnecter")
                                                                                            : String(localized: "Appuie pour déconnecter")),
                                icon: expired ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                                destructive: true) { confirm = .disconnectDebrid(provider.id) }
        } else if debrid.authProviderId == provider.id {
            switch debrid.authPhase {
            case .starting:
                OrbitSettingsNote(text: String(localized: "Demande d'un code à \(provider.displayName)…"))
            case .waiting:
                if let session = debrid.activeSession {
                    OrbitSettingsCodeCard(address: session.friendlyVerificationUrl, code: session.userCode) {
                        debrid.cancelActivation()
                    }
                }
            case .failed(let message):
                OrbitSettingsNote(text: message, tone: Self.error)
                OrbitSettingsAction(title: String(localized: "Fermer"), icon: "xmark") { debrid.cancelActivation() }
            case .idle:
                EmptyView()
            }
        } else {
            OrbitSettingsAction(title: String(localized: "Connecter \(provider.displayName)"),
                                subtitle: String(localized: "Affiche un code à entrer sur ton téléphone."),
                                icon: "antenna.radiowaves.left.and.right") { debrid.connect(provider) }
            OrbitSettingsKeyField(placeholder: String(localized: "Ou colle ta clé \(provider.displayName)")) { key in
                debrid.saveManualKey(provider.id, key: key)
            }
        }
    }

    private static func sourceName(_ key: String) -> String {
        switch key {
        case "local": return String(localized: "Nuvio")
        case "nuvio_sync": return String(localized: "Nuvio")
        case "trakt": return "Trakt"
        case "simkl": return "Simkl"
        case "mdblist": return "MDBList"
        case "tmdb": return "TMDB"
        default: return key
        }
    }
}

// MARK: - MDBList lists

@MainActor
final class OrbitMdbListListsModel: ObservableObject {
    @Published private(set) var options: [MdbListLibraryListOption] = []
    @Published var errorMessage: String?
    private var watcher: FlowWatcher?

    /// The watchlist always shows (it is not a list to hide).
    var rows: [MdbListLibraryListOption] { options.filter { $0.key != "mdblist:watchlist" } }

    func start() {
        guard watcher == nil else { return }
        MdbListTracker.shared.ensureLoaded(profileId: ProfileRepository.shared.activeProfileId)
        watcher = FlowWatcherKt.watchFlow(MdbListTracker.shared.library.listOptions) { [weak self] emitted in
            guard let list = emitted as? [MdbListLibraryListOption] else { return }
            Task { @MainActor in self?.options = list }
        }
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
    }

    func setVisible(_ key: String, _ visible: Bool) {
        guard let index = options.firstIndex(where: { $0.key == key }) else { return }
        let previous = options[index]
        errorMessage = nil
        options[index] = MdbListLibraryListOption(key: previous.key, name: previous.name, visible: visible)
        MdbListTracker.shared.library.setListVisibilityAsync(key: key, visible: visible) { [weak self] (message: String?) in
            Task { @MainActor in
                guard let self, let message else { return }
                if let i = self.options.firstIndex(where: { $0.key == key }) { self.options[i] = previous }
                self.errorMessage = message.isEmpty ? String(localized: "Impossible de modifier cette liste. Réessaie.") : message
            }
        }
    }
}

struct OrbitMdbListListsPage: View {
    @StateObject private var model = OrbitMdbListListsModel()

    var body: some View {
        ZStack(alignment: .top) {
            OrbitHomeLayout.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Listes de la bibliothèque")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.bottom, 26)
                    if model.rows.isEmpty {
                        OrbitSettingsNote(text: String(localized: "Aucune liste dans ton compte MDBList pour l'instant."))
                    }
                    ForEach(model.rows, id: \.key) { option in
                        OrbitSettingsToggle(title: option.name,
                                            isOn: Binding(get: { option.visible }, set: { model.setVisible(option.key, $0) }))
                    }
                    if let error = model.errorMessage {
                        OrbitSettingsNote(text: error, tone: Color(red: 1, green: 0.45, blue: 0.42))
                    }
                }
                .padding(.vertical, 90)
                .frame(maxWidth: .infinity)
            }
            .scrollClipDisabled()
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

// MARK: - À propos

struct OrbitAboutSection: View {
    @AppStorage("debug.streamProbe") private var streamDiagnostics = false
    @State private var cacheCleared = false
    // (Temporary: the title page's smoothness diagnostic — `OrbitDiag`.)
    @AppStorage(OrbitDiag.groundKey) private var diagGround = false
    @AppStorage(OrbitDiag.artKey) private var diagArt = false
    @AppStorage(OrbitDiag.titleKey) private var diagTitle = false
    @AppStorage(OrbitDiag.shadowsKey) private var diagShadows = false
    @AppStorage(OrbitDiag.heroKey) private var diagHero = false

    var body: some View {
        OrbitSettingsGroup(title: String(localized: "Orbit")) {
            OrbitSettingsInfo(title: String(localized: "Version"), value: "\(Self.info("CFBundleShortVersionString") ?? "0.0") (\(Self.info("CFBundleVersion") ?? "0"))")
            OrbitSettingsInfo(title: String(localized: "Build"), value: Self.info("NuvioCommitSHA").flatMap { $0.isEmpty ? nil : $0 } ?? "—")
            OrbitSettingsInfo(title: "tvOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
            OrbitSettingsInfo(title: String(localized: "Appareil"), value: Self.deviceModel)
        }

        // Steven (2026-10-25): the signature, quiet.
        HStack(spacing: 14) {
            Text("Fait avec amour par Steven")
                .font(OrbitSettingsLayout.note)
                .foregroundStyle(Color.white.opacity(0.5))
            // Steven: the rabbit on the right.
            Image("OrbitMark")
                .resizable()
                .scaledToFit()
                .frame(height: 30)
                .opacity(0.6)
                .accessibilityHidden(true)
        }
        .frame(width: OrbitSettingsLayout.rowWidth)
        .padding(.vertical, 6)

        // Steven (2026-10-30): one switch at a time, then a title's page — which one makes it smooth.
        OrbitSettingsGroup(title: "Diagnostic fluidité (page d'un titre)") {
            OrbitSettingsToggle(title: "1 · Couper le fond flouté",
                                subtitle: "Sous les rangées, un fond uni à la place du flou.",
                                isOn: $diagGround)
            OrbitSettingsToggle(title: "2 · Retirer l'image du film en descendant",
                                subtitle: "L'image du haut enlevée au lieu d'être rendue invisible.",
                                isOn: $diagArt)
            OrbitSettingsToggle(title: "3 · Couper le petit titre",
                                subtitle: "Le titre au-dessus de la première rangée.",
                                isOn: $diagTitle)
            OrbitSettingsToggle(title: "4 · Couper les ombres des vignettes",
                                subtitle: "Saga, À voir aussi, épisodes…",
                                isOn: $diagShadows)
            OrbitSettingsToggle(title: "5 · Masquer le haut de page en descendant",
                                subtitle: "Pour remonter, utilise le bouton Menu.",
                                isOn: $diagHero)
        }

        OrbitSettingsGroup(title: String(localized: "Diagnostic")) {
            OrbitSettingsToggle(title: String(localized: "Diagnostic des sources"),
                                subtitle: String(localized: "Note ce qui se passe quand un titre ne trouve aucune source : active-le, lance le titre, puis reviens ici."),
                                isOn: $streamDiagnostics)
            if streamDiagnostics {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(alignment: .leading, spacing: 4) {
                        if StreamProbe.lines.isEmpty {
                            Text("Aucune recherche de source pour l'instant.")
                        } else {
                            ForEach(Array(StreamProbe.lines.enumerated()), id: \.offset) { _, line in
                                Text(line).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    .font(.system(size: 19, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: OrbitSettingsLayout.rowWidth, alignment: .leading)
                }
            }
            OrbitSettingsAction(title: cacheCleared ? String(localized: "Cadrage des bandes-annonces réinitialisé")
                                                    : String(localized: "Réinitialiser le cadrage des bandes-annonces"),
                                subtitle: String(localized: "Si une bande-annonce s'affiche mal cadrée."),
                                icon: cacheCleared ? "checkmark" : "arrow.counterclockwise") {
                TrailerZoomCache.shared.removeAll()
                cacheCleared = true
            }
        }
        .onChange(of: streamDiagnostics) { _, _ in StreamProbe.syncSink() }
    }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private static var deviceModel: String {
        var system = utsname()
        uname(&system)
        return Mirror(reflecting: system.machine).children.reduce(into: "") { out, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            out += String(UnicodeScalar(UInt8(value)))
        }
    }
}
