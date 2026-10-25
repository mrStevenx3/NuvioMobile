import SharedCore
import SwiftUI

// Orbit's source page (Steven's fork, 2026-10-25), rewritten from scratch.
//
// Opened by Play. It lists the sources the add-ons return, best first, and plays the one chosen:
// a direct link at once, a debrid one once the service has prepared it, a YouTube-only one once it
// is extracted on the device. With Settings › Lecture automatique on, the page starts the best
// source by itself (`OrbitAutoPlay`) under Orbit's loading screen, so the list never shows.
//
// Players: Orbit's own, or Infuse / Native Player (Settings › Lecteur par défaut; hold a source to
// open it in the other one). A playback that fails is remembered against its link for a while and,
// depending on who started it, the next automatic source takes over in place, the next episode's
// own page opens, or an alert offers "Essayer la source suivante".
//
// Closing the player closes the page too (Back lands where Play was pressed), under the plain
// loading screen, so the list never flashes on the way out.

struct StreamPickerView: View {
    let type: String
    let videoId: String
    let title: String
    let parentMetaId: String
    let season: Int?
    let episode: Int?
    /// The series' episodes (next-episode playback); fetched here when the caller has none.
    let episodes: [MetaVideo]
    let poster: String?
    let episodeStill: String?
    let synopsis: String?
    let meta: PlaybackMeta?
    let logoUrl: String?
    let backdrop: String?
    /// Never start automatically ("Choisir la source").
    let forceManual: Bool
    /// "Reprendre du début": the playbacks this page starts ignore the saved position.
    let startFromBeginning: Bool
    /// A message shown when the page opens on its list (the next episode's source failed).
    let notice: String?
    /// Kept for the call sites.
    let onOpenTitle: ((MetaPreview) -> Void)?

    @StateObject private var model: StreamsViewModel
    @StateObject private var autoPlay: OrbitAutoPlay

    /// The automatic start is working (the loading screen is up).
    @State private var autoMode: Bool
    /// The loading screen stays up while an automatic pick's player opens.
    @State private var holdCover = false
    /// The page is leaving: the loading screen, plain black.
    @State private var closing = false
    @State private var started = false

    @State private var selected: PlaybackContext?
    @State private var resolvingKey: String?
    @State private var resolveTask: Task<Void, Never>?
    @State private var toast: String?
    @FocusState private var focusedRow: String?
    @State private var filter: OrbitStreamFilter = .all
    @State private var tagCache = OrbitStreamTagCache()
    @State private var externalPlayers: [ExternalPlayerApp] = []
    @AppStorage("default_external_player_id") private var defaultPlayerId = ""

    /// What the closing player leads to (set by a failure before the player closes).
    @State private var afterPlayer: AfterPlayer = .closePage
    @State private var alertQueued: FailureAlert?
    @State private var nextEpisodeQueued: NextEpisodePage?
    @State private var failureAlert: FailureAlert?
    @State private var nextEpisodePage: NextEpisodePage?
    /// The list as shown when the viewer chose: "Essayer la source suivante" walks it.
    @State private var chosenFromList: [StreamItem] = []
    @State private var rejectedKeys: Set<String> = []
    /// A "Reprendre du début" playback has run long enough: later tries resume normally.
    @State private var startOverDone = false
    @State private var fetchedEpisodes: [MetaVideo] = []
    @Environment(\.dismiss) private var dismiss

    private enum AfterPlayer: Equatable {
        case closePage, showList, alert, nextEpisodePage
    }

    init(type: String,
         videoId: String,
         title: String,
         parentMetaId: String? = nil,
         season: Int? = nil,
         episode: Int? = nil,
         episodes: [MetaVideo] = [],
         poster: String? = nil,
         episodeStill: String? = nil,
         synopsis: String? = nil,
         meta: PlaybackMeta? = nil,
         logoUrl: String? = nil,
         backdrop: String? = nil,
         forceManual: Bool = false,
         startFromBeginning: Bool = false,
         notice: String? = nil,
         onOpenTitle: ((MetaPreview) -> Void)? = nil) {
        self.type = type
        self.videoId = videoId
        self.title = title
        self.parentMetaId = parentMetaId ?? videoId
        self.season = season
        self.episode = episode
        self.episodes = episodes
        self.poster = poster
        self.episodeStill = episodeStill
        self.synopsis = synopsis
        self.meta = meta
        self.logoUrl = logoUrl
        self.backdrop = backdrop
        self.forceManual = forceManual
        self.startFromBeginning = startFromBeginning
        self.notice = notice
        self.onOpenTitle = onOpenTitle
        // Decided here, so the loading screen is up from the very first frame.
        _autoMode = State(initialValue: !forceManual && OrbitAutoPlay.isEnabled)
        _model = StateObject(wrappedValue: StreamsViewModel(type: type, videoId: videoId,
                                                            parentMetaId: parentMetaId, season: season, episode: episode))
        _autoPlay = StateObject(wrappedValue: OrbitAutoPlay(type: type, videoId: videoId, season: season, episode: episode))
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            list
                .padding(.horizontal, OrbitHomeLayout.margin)
                .padding(.top, 70)
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(coverShown)
        }
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OrbitStreamBackground(url: backdropUrl))
        .overlay(alignment: .bottom) { toastView }
        .overlay { if coverShown { cover } }
        .onReceive(model.$autoPlayFeed) { autoPlay.ingest($0) }
        .onReceive(autoPlay.events) { handle($0) }
        .onChange(of: rows.first?.key) { _, first in
            // The best source takes the focus when the list arrives, unless the viewer moved it.
            guard let first, !coverShown, focusedRow == nil else { return }
            DispatchQueue.main.async { focusedRow = first }
        }
        .onAppear(perform: appear)
        .onDisappear {
            resolveTask?.cancel()
            model.stop()
        }
        .alert("Impossible de lire cette source",
               isPresented: Binding(get: { failureAlert != nil }, set: { if !$0 { failureAlert = nil } }),
               presenting: failureAlert) { alert in
            if let next = alert.next {
                Button("Essayer la source suivante") {
                    failureAlert = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        playInOrbit(next, rowKey: Self.retryRowKey, attempt: alert.attempt)
                    }
                }
            }
            Button("Retour aux sources", role: .cancel) { failureAlert = nil }
        } message: { alert in
            Text(alert.reason)
        }
        .fullScreenCover(item: playerBinding, onDismiss: playerClosed) { context in
            PlayerScreen(context: context,
                         onPlayNext: { next in selected = next },
                         onPlaybackFailed: { failure in playbackFailed(failure, context: context) },
                         onPlaybackHealthy: { seconds in playbackHealthy(seconds, context: context) })
                .ignoresSafeArea()
                .id(context.id)
        }
        .fullScreenCover(item: $nextEpisodePage, onDismiss: closePage) { page in
            StreamPickerView(type: page.context.contentType,
                             videoId: page.context.videoId,
                             title: page.context.title,
                             parentMetaId: page.context.parentMetaId,
                             season: page.context.season,
                             episode: page.context.episode,
                             episodes: page.context.episodes,
                             poster: page.context.poster,
                             episodeStill: page.context.episodeStill,
                             synopsis: page.context.synopsis,
                             meta: page.context.meta,
                             logoUrl: logoUrl,
                             backdrop: backdrop,
                             forceManual: page.forceManual,
                             notice: String(localized: "La source de l'épisode suivant n'a pas pu démarrer. Choisis-en une."))
        }
    }

    private func appear() {
        externalPlayers = ExternalPlayerPlatform.shared.availablePlayers()
        rejectedKeys = RejectedStreamLinks.rejected(for: videoId)
        if !started {
            started = true
            if autoMode {
                autoPlay.start()
            } else if let notice {
                showToast(notice)
            }
        }
        model.start(forceManual: !autoMode)
        fetchEpisodesIfNeeded()
        // The add-on subtitles start fetching while the viewer chooses.
        SubtitleRepository.shared.fetchAddonSubtitles(type: type, videoId: videoId)
    }

    // MARK: - Loading screen

    private var coverShown: Bool { autoMode || holdCover || closing }

    /// Orbit's loading screen. Menu cancels the automatic start (the list shows); while it only
    /// holds (a player opening, the page leaving) Menu does nothing.
    private var cover: some View {
        // Steven (device: back from the player, the loading screen with "Encore un instant…"):
        // once a player is up, what is left under it is plain black.
        OrbitLoadingView(title: title, logoUrl: logoUrl, backdropUrl: backdropUrl, plain: closing || selected != nil)
            .overlay(OrbitCoverFocus(onMenu: autoMode && !holdCover ? { cancelAutoPlay() } : nil))
    }

    private var backdropUrl: String? { backdrop ?? episodeStill ?? poster }

    // MARK: - List

    private var allEpisodes: [MetaVideo] { episodes.isEmpty ? fetchedEpisodes : episodes }

    /// Every source, best first.
    private var rows: [OrbitStreamRow] {
        var out: [OrbitStreamRow] = []
        var order = 0
        for group in model.groups {
            for (key, stream) in zip(group.rowKeys, group.streams) {
                out.append(OrbitStreamRow(key: key, stream: stream, tags: tagCache.tags(key, stream), order: order))
                order += 1
            }
        }
        return OrbitStreamRow.sorted(out)
    }

    @ViewBuilder
    private var list: some View {
        let all = rows
        let shown = all.filter { filter.matches($0.tags) }
        // A filter shows only when it filters something.
        let filters = OrbitStreamFilter.allCases.filter { f in
            if f == .all { return true }
            let n = all.filter { f.matches($0.tags) }.count
            return n > 0 && n < all.count
        }
        let showsInstant = all.contains { !$0.tags.instant }
        VStack(alignment: .leading, spacing: 34) {
            OrbitStreamHeader(title: title, logoUrl: logoUrl,
                              episodeLine: Self.episodeLine(season: season, episode: episode, episodes: allEpisodes),
                              count: all.count, loading: model.isLoading)
            if let warning = model.credentialWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.yellow.opacity(0.18)))
            }
            if filters.count > 1 {
                HStack(spacing: 16) {
                    ForEach(filters) { f in
                        let key = "filter:\(f.rawValue)"
                        OrbitStreamFilterChip(label: f.label, count: all.filter { f.matches($0.tags) }.count,
                                              selected: filter == f, focused: focusedRow == key) {
                            withAnimation(.easeInOut(duration: 0.2)) { filter = f }
                        }
                        .focused($focusedRow, equals: key)
                    }
                }
                .focusSection()
            }
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(shown) { row in card(row, list: shown, showsInstant: showsInstant) }
                if all.isEmpty, model.isLoading {
                    ForEach(0..<4, id: \.self) { _ in OrbitStreamPlaceholder() }
                }
            }
            .focusSection()
            if let reason = model.emptyReason {
                VStack(alignment: .leading, spacing: 8) {
                    Text(reason)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.white)
                    if let hint = model.emptyReasonHint {
                        Text(hint)
                            .font(.system(size: 23, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
            }
        }
    }

    private func card(_ row: OrbitStreamRow, list: [OrbitStreamRow], showsInstant: Bool) -> some View {
        let stream = row.stream
        return OrbitStreamCard(stream: stream, tags: row.tags,
                               focused: focusedRow == row.key,
                               resolving: resolvingKey == row.key,
                               failedRecently: rejectedKeys.contains(stream.playbackStreamKey),
                               fromYouTube: Self.isYouTubeResolved(stream),
                               showsInstant: showsInstant) {
            chosenFromList = list.map(\.stream)
            choose(stream, rowKey: row.key)
        }
        .focused($focusedRow, equals: row.key)
        .modifier(OrbitOtherPlayerMenu(players: externalPlayers, defaultPlayerId: defaultPlayer?.id,
                                       onExternal: { player in playExternally(stream, rowKey: row.key, playerId: player.id) },
                                       onOrbit: {
                                           chosenFromList = list.map(\.stream)
                                           playInOrbit(stream, rowKey: row.key)
                                       }))
    }

    // MARK: - Choosing a source

    /// The default external player, when it is still installed.
    private var defaultPlayer: ExternalPlayerApp? {
        guard !defaultPlayerId.isEmpty else { return nil }
        return externalPlayers.first { $0.id == defaultPlayerId }
    }

    private func choose(_ stream: StreamItem, rowKey: String) {
        if let player = defaultPlayer {
            playExternally(stream, rowKey: rowKey, playerId: player.id, orbitIfFails: true)
        } else {
            playInOrbit(stream, rowKey: rowKey)
        }
    }

    /// Plays in Orbit's player once the link is ready. Always the viewer's own choice.
    private func playInOrbit(_ stream: StreamItem, rowKey: String, attempt: Int = 0) {
        ready(stream, rowKey: rowKey) { resolved, url in
            NextEpisodeEngine.consecutiveAutoPlays = 0
            selected = context(url: url, stream: resolved, listed: stream, source: .manual, attempt: attempt)
        }
    }

    /// The source's playable link: as is, extracted (YouTube) or prepared by the debrid service.
    /// One at a time; the row shows a spinner meanwhile.
    private func ready(_ stream: StreamItem, rowKey: String, then play: @escaping (StreamItem, URL) -> Void) {
        let direct: String? = stream.playableDirectUrl
        if let direct, !direct.isEmpty, let url = URL(string: direct) {
            play(stream, url)
            return
        }
        guard resolvingKey == nil else { return }
        let youTube = Self.isYouTubeResolved(stream)
        if !youTube, !DirectDebridPlaybackResolver.shared.shouldResolveToPlayableStream(stream: stream) {
            showToast(String(localized: "Cette source demande un compte debrid. Connecte-en un dans Réglages › Services."))
            return
        }
        resolvingKey = rowKey
        let kotlinSeason = season.map { KotlinInt(int: Int32($0)) }
        let kotlinEpisode = episode.map { KotlinInt(int: Int32($0)) }
        resolveTask = Task { @MainActor in
            defer { if resolvingKey == rowKey { resolvingKey = nil } }
            if youTube {
                let resolved: StreamItem? = try? await YouTubeStreamResolver.shared.resolve(stream: stream)
                guard !Task.isCancelled, selected == nil else { return }
                let link: String? = resolved?.playableDirectUrl
                guard let resolved, let link, !link.isEmpty, let url = URL(string: link) else {
                    showToast(Self.youTubeResolveFailedMessage)
                    return
                }
                play(resolved, url)
                return
            }
            let result: DirectDebridPlayableResult?
            do {
                result = try await DirectDebridPlaybackResolver.shared.resolveToPlayableStreamChecked(
                    stream: stream, season: kotlinSeason, episode: kotlinEpisode)
            } catch {
                result = nil
            }
            guard !Task.isCancelled, selected == nil else { return }
            if let success = result as? DirectDebridPlayableResult.Success {
                let link: String? = success.stream.playableDirectUrl
                if let link, !link.isEmpty, let url = URL(string: link) {
                    play(success.stream, url)
                    return
                }
            }
            showToast(Self.debridFailure(result))
            // An expired result set: fetch it again.
            if result is DirectDebridPlayableResult.Stale { model.reload(forceManual: true) }
        }
    }

    // MARK: - External players

    /// Infuse / Native Player. From the default-player route, a hand-off that does not open plays
    /// in Orbit instead; asked for explicitly (hold), it says so.
    private func playExternally(_ stream: StreamItem, rowKey: String, playerId: String,
                                orbitIfFails: Bool = false, autoAttempt: Int? = nil) {
        ready(stream, rowKey: rowKey) { resolved, url in
            handOff(resolved, listed: stream, url: url, playerId: playerId,
                    orbitIfFails: orbitIfFails, autoAttempt: autoAttempt)
        }
    }

    private func handOff(_ stream: StreamItem, listed: StreamItem, url: URL, playerId: String,
                         orbitIfFails: Bool, autoAttempt: Int?) {
        let request = OrbitExternalHandOff.Request(
            url: url.absoluteString, stream: stream, title: title, type: type, videoId: videoId,
            season: season, episode: episode, resumeMs: resumeMs(),
            session: PlaybackProgressRecorder.playbackSession(for: context(url: url, stream: stream, listed: listed)),
            durationMs: durationMs())
        resolvingKey = Self.handOffRowKey
        Task { @MainActor in
            let prepared = await OrbitExternalHandOff.prepare(request, playerId: playerId)
            if resolvingKey == Self.handOffRowKey { resolvingKey = nil }
            guard selected == nil else { return }
            if let prepared {
                // Back from the player lands where Play was pressed.
                closePage()
                OrbitExternalHandOff.open(prepared.url, sessionId: prepared.sessionId)
                return
            }
            if orbitIfFails {
                showToast(String(localized: "Le lecteur externe n'a pas pu s'ouvrir : lecture dans Orbit."))
                NextEpisodeEngine.consecutiveAutoPlays = 0
                selected = context(url: url, stream: stream, listed: listed,
                                   source: autoAttempt == nil ? .manual : .autoPlay,
                                   attempt: max(0, (autoAttempt ?? 1) - 1))
            } else {
                holdCover = false
                showToast(String(localized: "Le lecteur externe n'a pas pu s'ouvrir."))
            }
        }
    }

    /// The saved position for an external player (0 for "Reprendre du début" or a finished title).
    private func resumeMs() -> Int64 {
        guard !startsOver, let progress = savedProgress(), !progress.isCompleted, progress.lastPositionMs > 10_000 else { return 0 }
        return progress.lastPositionMs
    }

    /// The title's length for the external return: the saved one, the episode's, the film's.
    private func durationMs() -> Int64? {
        if let progress = savedProgress(), progress.durationMs > 0 { return progress.durationMs }
        if let season, let episode,
           let video = allEpisodes.first(where: { $0.season?.intValue == season && $0.episode?.intValue == episode }),
           let minutes = video.runtime?.intValue, minutes > 0 {
            return Int64(minutes) * 60_000
        }
        if let minutes = PlaybackMeta.runtimeMinutes(meta?.runtime), minutes > 0 { return Int64(minutes) * 60_000 }
        return nil
    }

    private func savedProgress() -> WatchProgressEntry? {
        WatchProgressRepository.shared.progressForVideo(
            videoId: videoId, parentMetaId: parentMetaId,
            seasonNumber: season.map { KotlinInt(int: Int32($0)) },
            episodeNumber: episode.map { KotlinInt(int: Int32($0)) })
    }

    // MARK: - Automatic start

    private func handle(_ event: OrbitAutoPlay.Event) {
        switch event {
        case .play(let pick):
            // The viewer closed the failed player while the next source was being prepared.
            if pick.isFailover, selected == nil { return }
            holdCover = true
            autoMode = false
            NextEpisodeEngine.consecutiveAutoPlays = 0
            // The first start follows the default player; a retry always stays in Orbit (an
            // external player reports no failure back).
            if !pick.isFailover, let player = defaultPlayer {
                handOff(pick.resolved, listed: pick.listed, url: pick.url, playerId: player.id,
                        orbitIfFails: true, autoAttempt: pick.attempt)
                return
            }
            selected = context(url: pick.url, stream: pick.resolved, listed: pick.listed,
                               source: .autoPlay, attempt: pick.attempt - 1)
        case .gaveUp(let duringFailover):
            autoMode = false
            rejectedKeys = RejectedStreamLinks.rejected(for: videoId)
            if duringFailover {
                guard selected != nil else { return }   // the viewer already left the player
                afterPlayer = .showList
                selected = nil
            }
            holdCover = false
            if duringFailover || !model.groups.isEmpty {
                showToast(String(localized: "Aucune source n'a pu démarrer. Choisis-en une."))
            }
            focusList()
        }
    }

    /// Menu on the loading screen: stop and show the list.
    private func cancelAutoPlay() {
        autoPlay.cancel()
        autoMode = false
        holdCover = false
        focusList()
    }

    private func focusList() {
        DispatchQueue.main.async {
            if focusedRow == nil, let first = rows.first?.key { focusedRow = first }
        }
    }

    // MARK: - After a playback

    private func playbackFailed(_ failure: PlaybackFailure, context ctx: PlaybackContext) {
        guard selected?.id == ctx.id else { return }
        if PlaybackFailoverPolicy.shouldKeep(secondsPlayed: failure.secondsPlayed), ctx.videoId == videoId {
            startOverDone = true
        }
        if PlaybackFailoverPolicy.shouldReject(failure) {
            RejectedStreamLinks.reject(ctx.streamKey, title: ctx.videoId)
            if let listed = ctx.listedStream, listed.isAddonDebridCandidate {
                DirectDebridPlaybackResolver.shared.invalidate(
                    stream: listed,
                    season: ctx.season.map { KotlinInt(int: Int32($0)) },
                    episode: ctx.episode.map { KotlinInt(int: Int32($0)) })
            }
        }
        rejectedKeys = RejectedStreamLinks.rejected(for: videoId)

        var response = PlaybackFailoverPolicy.response(for: ctx.launchSource)
        // A source switched from inside the player for a later episode: that episode's own page.
        if response == .manualAlert, ctx.videoId != videoId { response = .nextEpisodePicker }
        switch response {
        case .autoFailover:
            if !autoPlay.continueAfterFailure(of: ctx.streamKey, addonId: ctx.providerAddonId) {
                handle(.gaveUp(duringFailover: true))
            }
        case .nextEpisodePicker:
            let manual = ctx.launchSource == .manual || !OrbitAutoPlay.isEnabled
            nextEpisodeQueued = NextEpisodePage(context: ctx, forceManual: manual)
            afterPlayer = .nextEpisodePage
            selected = nil
        case .manualAlert:
            alertQueued = FailureAlert(reason: failure.reason, next: nextSource(after: ctx), attempt: ctx.attempt + 1)
            afterPlayer = .alert
            selected = nil
        }
    }

    private func playbackHealthy(_ seconds: Double, context ctx: PlaybackContext) {
        guard PlaybackFailoverPolicy.shouldKeep(secondsPlayed: seconds) else { return }
        RejectedStreamLinks.keep(ctx.streamKey, title: ctx.videoId)
        if ctx.videoId == videoId {
            startOverDone = true
            rejectedKeys = RejectedStreamLinks.rejected(for: videoId)
        }
    }

    /// "Essayer la source suivante": the list as it was when chosen, after the failed one, the same
    /// add-on first, failed links skipped.
    private func nextSource(after ctx: PlaybackContext) -> StreamItem? {
        let list = chosenFromList.isEmpty ? model.groups.flatMap(\.streams) : chosenFromList
        guard let index = PlaybackFailoverPolicy.nextManualIndex(
            streams: list, failedKey: ctx.streamKey, failedAddonId: ctx.providerAddonId,
            rejected: RejectedStreamLinks.rejected(for: videoId)) else { return nil }
        return list[index]
    }

    /// The player's cover. When the page is going to close behind it, the plain loading screen goes
    /// up first and the player leaves without its slide, so the list never shows.
    private var playerBinding: Binding<PlaybackContext?> {
        Binding(
            get: { selected },
            set: { newValue in
                guard newValue == nil, selected != nil, afterPlayer == .closePage else {
                    selected = newValue
                    return
                }
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    closing = true
                    selected = nil
                }
            }
        )
    }

    private func playerClosed() {
        guard selected == nil else { return }   // a context swap (next episode, retry) re-presents
        rejectedKeys = RejectedStreamLinks.rejected(for: videoId)
        let outcome = afterPlayer
        afterPlayer = .closePage
        switch outcome {
        case .alert:
            holdCover = false
            closing = false
            let alert = alertQueued
            alertQueued = nil
            DispatchQueue.main.async { failureAlert = alert }
        case .nextEpisodePage:
            holdCover = true
            let page = nextEpisodeQueued
            nextEpisodeQueued = nil
            DispatchQueue.main.async { nextEpisodePage = page }
        case .showList:
            holdCover = false
            closing = false
            autoPlay.cancel()
        case .closePage:
            autoPlay.cancel()
            closePage()
        }
    }

    /// Leaves without the list showing.
    private func closePage() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { closing = true }
        DispatchQueue.main.async { withTransaction(instant) { dismiss() } }
    }

    // MARK: - Playback context

    private var startsOver: Bool { startFromBeginning && !startOverDone }

    private func context(url: URL, stream: StreamItem, listed: StreamItem,
                         source: PlaybackLaunchSource = .manual, attempt: Int = 0) -> PlaybackContext {
        PlaybackContext(
            url: url,
            title: title,
            contentType: type,
            parentMetaId: parentMetaId,
            videoId: videoId,
            season: season,
            episode: episode,
            poster: poster,
            background: backdropUrl,
            providerName: stream.addonName,
            providerAddonId: stream.addonId,
            streamTitle: stream.streamLabel,
            streamSubtitle: { let s: String? = stream.description_; return s }(),
            externalSubtitles: stream.externalSubtitles.map { sub in
                SubtitleFile(url: sub.url, language: sub.language, name: { let n: String? = sub.name; return n }())
            },
            bingeGroup: { let g: String? = stream.behaviorHints.bingeGroup; return g }(),
            episodes: allEpisodes,
            synopsis: synopsis,
            episodeStill: episodeStill,
            logo: logoUrl,
            meta: meta,
            fileSizeBytes: { let n: Int64? = stream.behaviorHints.videoSize?.int64Value; return n }(),
            streamAudioDelayMs: { let n: Int? = stream.behaviorHints.audioDelayMs?.intValue; return n }(),
            requestHeaders: StreamModelsKt.sanitizePlaybackHeaders(headers: stream.behaviorHints.proxyHeaders?.request),
            launchSource: source,
            streamKey: listed.playbackStreamKey,
            startFromBeginning: startsOver,
            attempt: attempt,
            listedStream: listed,
            // A YouTube link expires within hours: never saved as the title's last source.
            sessionOnlySourceUrl: Self.isYouTubeResolved(listed))
    }

    /// Series paths that come without the episode list get it here (next-episode playback).
    private func fetchEpisodesIfNeeded() {
        guard episodes.isEmpty, fetchedEpisodes.isEmpty,
              ["series", "tv", "show", "tvshow"].contains(type.lowercased()) else { return }
        Task { @MainActor in
            let details = try? await MetaDetailsRepository.shared.fetchChecked(type: type, id: parentMetaId, cacheResult: true)
            let videos = details?.videos ?? []
            if !videos.isEmpty { fetchedEpisodes = videos }
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 18)
                .background(Capsule().fill(.ultraThinMaterial))
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if toast == message { withAnimation { toast = nil } }
        }
    }

    // MARK: - Helpers

    private static let retryRowKey = "retry-next"
    private static let handOffRowKey = "external-handoff"

    /// The add-on gave only a YouTube video id (resolved on the device when chosen).
    nonisolated static func isYouTubeResolved(_ stream: StreamItem?) -> Bool {
        let id: String? = stream?.youTubeIdToResolve
        return !(id ?? "").isEmpty
    }

    static var youTubeResolveFailedMessage: String { String(localized: "Impossible de charger cette vidéo YouTube.") }

    /// "S2 · É5 · Titre de l'épisode".
    static func episodeLine(season: Int?, episode: Int?, episodes: [MetaVideo]) -> String? {
        guard let season, let episode else { return nil }
        let marker = "S\(season) · É\(episode)"
        let name: String? = episodes.first { $0.season?.intValue == season && $0.episode?.intValue == episode }?.title
        guard let name, !name.isEmpty else { return marker }
        return "\(marker) · \(name)"
    }

    private static func debridFailure(_ result: DirectDebridPlayableResult?) -> String {
        switch result {
        case is DirectDebridPlayableResult.MissingApiKey:
            return String(localized: "Connecte un compte debrid dans Réglages › Services.")
        case is DirectDebridPlayableResult.NotCached:
            return String(localized: "Pas en cache sur ton service debrid.")
        case is DirectDebridPlayableResult.Stale:
            return String(localized: "Ce lien a expiré. Actualisation des sources.")
        case let error as DirectDebridPlayableResult.Error:
            return error.message ?? String(localized: "Impossible d'ouvrir ce lien.")
        default:
            return String(localized: "Impossible d'ouvrir ce lien.")
        }
    }

    private struct NextEpisodePage: Identifiable {
        let id = UUID()
        let context: PlaybackContext
        let forceManual: Bool
    }

    private struct FailureAlert: Identifiable {
        let id = UUID()
        let reason: String
        let next: StreamItem?
        let attempt: Int
    }
}

/// Holds the focus while the loading screen is up (so Menu reaches it, never the list or the page)
/// and turns Menu into "show the list" while the automatic start works.
private struct OrbitCoverFocus: View {
    let onMenu: (() -> Void)?
    @FocusState private var focused: Bool

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .focusable()
            .focused($focused)
            .onExitCommand { onMenu?() }
            .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

/// Hold a source: the other player(s). Only when Infuse or Native Player is installed.
private struct OrbitOtherPlayerMenu: ViewModifier {
    let players: [ExternalPlayerApp]
    let defaultPlayerId: String?
    let onExternal: (ExternalPlayerApp) -> Void
    let onOrbit: () -> Void

    func body(content: Content) -> some View {
        if players.isEmpty {
            content
        } else {
            content.contextMenu {
                if defaultPlayerId != nil {
                    Button(action: onOrbit) { Label("Lire dans Orbit", systemImage: "play.tv") }
                }
                ForEach(players.filter { $0.id != defaultPlayerId }, id: \.id) { player in
                    Button { onExternal(player) } label: {
                        Label("Ouvrir dans \(player.name)", systemImage: "arrow.up.forward.app")
                    }
                }
            }
        }
    }
}
