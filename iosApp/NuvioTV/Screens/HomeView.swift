import Combine
import SwiftUI
import UIKit
import SharedCore

/// Home (Steven's fork, 2026-10-24): rebuilt for Orbit only. Chris's classic Home (hero carousel,
/// pinned rows, rail plumbing, settle correctors and probes) is gone; this view is just the
/// navigation shell around Orbit Home (Films / Séries) and the Stage strip (Plateformes, Studios),
/// plus every page they push and the Continue Watching source picker.
struct HomeView: View {
    /// Owned by `ContentView` (above the theme rebuild boundary); this view retains / releases it.
    @ObservedObject var model: HomeViewModel
    @State private var resume: ResumeTarget?
    /// The post-play "More like this" pick from a Continue Watching player, pushed once the
    /// picker cover is gone.
    @State private var homePostPlayPending: MetaPreview?
    @State private var homePath = NavigationPath()
    @State private var isScrolledDown = false
    @AppStorage("home_upcoming_row_enabled") private var upcomingRowEnabled = true

    var body: some View {
        NavigationStack(path: $homePath) {
            ZStack(alignment: .top) {
                Theme.Palette.background.ignoresSafeArea()
                OrbitHomeSwitch(model: model,
                                actions: StageHomeActions(resume: { resume = $0 },
                                                          push: { homePath.append($0) }),
                                pushGenre: { homePath.append(OrbitGenreRoute(genre: $0)) },
                                cover: StageCover(pushed: !homePath.isEmpty, resume: resume != nil),
                                isScrolledDown: $isScrolledDown)
            }
            .navigationDestination(for: TitleRoute.self) { route in
                DetailView(preview: route.preview)
            }
            .navigationDestination(for: CatalogRoute.self) { route in
                CatalogGridView(route: route)
            }
            .navigationDestination(for: PersonRoute.self) { route in
                PersonDetailView(personId: route.id, personName: route.name)
            }
            .navigationDestination(for: EntityRoute.self) { route in
                OrbitStudioPage(route: .entity(route))
            }
            .navigationDestination(for: OrbitStudioRoute.self) { route in
                OrbitStudioPage(route: route)
            }
            .navigationDestination(for: FolderRoute.self) { route in
                OrbitPlatformPage(route: route, push: { homePath.append($0) })
            }
            .navigationDestination(for: OrbitGenreRoute.self) { route in
                OrbitGenrePage(genre: route.genre)
            }
            .fullScreenCover(item: $resume, onDismiss: {
                guard let pick = homePostPlayPending else { return }
                homePostPlayPending = nil
                homePath.append(TitleRoute(preview: pick))
            }) { target in
                StreamPickerView(
                    type: target.entry.parentMetaType,
                    videoId: target.entry.videoId,
                    title: target.entry.title,
                    parentMetaId: target.entry.parentMetaId,
                    season: target.entry.seasonNumber?.value,
                    episode: target.entry.episodeNumber?.value,
                    poster: target.entry.poster,
                    episodeStill: { let still: String? = target.entry.episodeThumbnail; return (still ?? "").isEmpty ? nil : still }(),
                    synopsis: { let d: String? = target.entry.pauseDescription; return (d ?? "").isEmpty ? nil : d }(),
                    forceManual: target.forceManual,
                    startFromBeginning: target.startFromBeginning,
                    onOpenTitle: { homePostPlayPending = $0 }
                )
            }
        }
        .onAppear {
            // Retain, don't start: during a theme rebuild the incoming Home appears before the
            // outgoing one disappears, so the count goes 1 → 2 → 1 and the pipeline never restarts.
            model.acquire()
            if upcomingRowEnabled { model.startUpcoming() }
        }
        .onDisappear { model.release() }
        .onChange(of: upcomingRowEnabled) { _, enabled in
            if enabled { model.startUpcoming() } else { model.stopUpcoming() }
        }
    }
}


/// FEAT-15: republishes the one Home-catalog setting the Home SCREEN renders from — "Show Hero".
///
/// Why a dedicated observer rather than `HomeCatalogSettingsRepository.shared.snapshot()`: that
/// call runs `ensureLoaded()` and rebuilds the entire preferences map into fresh
/// `HomeCatalogPreference` values every time. `reportRowFocus` could afford that per focus event;
/// `body` cannot afford it per render, and the hero mode is now a rendering decision. This watches
/// the same `uiState` flow `SettingsViewModel` does (so the two never disagree) and keeps a single
/// Bool. Deliberately NOT folded into `HomeViewModel` — that type is shared with other in-flight
/// work; this is a self-contained, cancellable watcher with the same start/stop lifecycle.
@MainActor
final class HomeHeroSettingsObserver: ObservableObject {
    /// Defaults to `true` (the repository's own default) so the first frames behave exactly as
    /// they did before this change. The Home path drives `ensureLoaded()` → `publish()` early —
    /// `AddonRepository.initialize()` → `syncCatalogs`, `CollectionRepository.initialize()` →
    /// `syncCollections` — so a hero-off user's real value lands before rows do.
    @Published private(set) var heroEnabled = true

    private var watcher: FlowWatcher?

    func start() {
        guard watcher == nil else { return }
        // Codex review: the watcher dies with stop() while Home's tab is hidden, so a Show Hero
        // change made from Settings in the meantime would leave this stale — and a returning
        // Home would mount the retained rows in the WRONG container branch, then structurally
        // swap them when the fresh flow value landed (resetting scroll/focus). Seed
        // synchronously from the repository snapshot before re-subscribing; one snapshot() per
        // Home appearance, not per body pass.
        let current = HomeCatalogSettingsRepository.shared.snapshot().heroEnabled
        if heroEnabled != current { heroEnabled = current }
        watcher = FlowWatcherKt.watch(HomeCatalogSettingsRepository.shared.uiState) { [weak self] emitted in
            guard let self, let state = emitted as? HomeCatalogSettingsUiState else { return }
            // Guarded assignment: this flow republishes on every catalog reorder/rename too, and
            // an unconditional write would invalidate Home on each one.
            if self.heroEnabled != state.heroEnabled { self.heroEnabled = state.heroEnabled }
        }
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
    }

    deinit { watcher?.cancel() }
}

/// UX-7: drives the always-on "focus-follows-backdrop" hero. When focus rests on a poster in a
/// Home catalog row or Continue Watching, the hero adopts that title's artwork/text live; when
/// focus moves to the hero CTA or off every row, the carousel resumes.
///
/// FEAT-15: with Show Hero off this model drives the hero region outright — there is no carousel
/// to resume to, so `focusedItem == nil` resolves to Home's resting title (`heroRestingItem`)
/// instead. Nothing in this class changes between the two modes; the difference lives entirely in
/// what `HomeView.displayHero` falls back to.
///
/// Generation-guarded exactly like `InlineTrailerCardModel`'s dwell timer (see
/// `InlineTrailerCard.swift`): a fast D-pad scrub across a row reports a new item on every card
/// it crosses, and only the one the hand actually stops on may commit — a stale pending Task from
/// an already-superseded report must never land.
@MainActor
final class HomeHeroFocusModel: ObservableObject {
    /// The row-focused item currently driving the hero, or nil when the carousel owns it again.
    @Published private(set) var focusedItem: MetaPreview?
    /// Fired the moment `focusedItem` reverts to nil — either the grace period elapsed or
    /// `cancelAndRevert()` was called. Home uses this to re-stamp its auto-advance timer's "last
    /// change" clock, so the carousel doesn't immediately jump on the very next tick after focus
    /// looks away.
    var onRevert: (() -> Void)?

    /// How long a poster must hold focus before it takes over the hero. Long enough that a fast
    /// scrub across a row commits nothing until the hand actually stops.
    private static let commitDelay: TimeInterval = 0.2
    /// Test seam for `RowStepAB.deferHeroCommitUntilRest`: seconds since the last Home scroll motion.
    nonisolated(unsafe) static var motionClock: () -> TimeInterval = { PinnedRowSettle.secondsSinceMotion() }
    /// Grace period before reverting to nil once focus reports nothing. Bridges the brief gap
    /// between one card losing focus and the next gaining it (row-to-row hops, diagonal D-pad
    /// moves), so the hero doesn't flicker back to the carousel mid-navigation.
    private static let revertGrace: TimeInterval = 0.3

    private var generation = 0
    private var pendingTask: Task<Void, Never>?
    /// Which row's report currently backs `focusedItem` (or the pending commit). Rows update
    /// their `@FocusState` independently on a cross-row hop, so the DESTINATION often reports its
    /// item before the departing row reports `nil` — without this tag, that trailing `nil` would
    /// cancel the destination's pending commit and revert the hero under a still-focused poster
    /// (Codex review finding).
    private var claimSource: String?

    /// beta.19-rc1 verdict (M5, BUG-138): stale hero after a folder. A push takes focus off the
    /// row, the nil report used to revert the hero to the carousel page after `revertGrace`
    /// (painted behind the folder page), and on pop the folder re-reported and paid a commit plus a
    /// resolve, so the carousel title showed for about a second (Steven's video, 2:57.5). While
    /// Home is covered (`HomeView.syncHeroFocusCover`: a push, the Continue Watching stream picker,
    /// the shell) the model is FROZEN: a nil report is ignored and a pending revert is cancelled,
    /// so `focusedItem` and `claimSource` survive the cover.
    private var covered = false
    /// Armed by an uncover: if no report arrives within `uncoverDelay(restoresFocus:)`, the hero
    /// reverts as a nil report would have (focus came back somewhere other than the rows, e.g. the
    /// tab bar). Generation-guarded, and cleared by any report: the FIRST report after the uncover is
    /// the answer, the timer is only the fallback for an uncover that never gets one.
    private var uncoverVerifyTask: Task<Void, Never>?
    /// The fallback after a cover tvOS does not restore row focus from: the shell alone (a tab
    /// switch; focus comes back on the tab bar, never on the card). Short, so a hero left behind by
    /// focus that went elsewhere is corrected quickly.
    nonisolated static let uncoverVerifyDelay: TimeInterval = 0.6
    /// beta.19-rc1 verdict (review r1, A P3): the fallback after a cover tvOS DOES restore focus from
    /// (a pushed folder/Detail page, the Continue Watching stream picker). The restored card's report
    /// is the answer there, and on hardware it may land later than 0.6 s after `homePath` empties
    /// (the pop animation runs first; test90 proves the timing on the simulator only). A 0.6 s check
    /// that lost that race reverted the hero to the carousel, and the late report then re-committed
    /// the folder through a 0.2 s commit plus a resolve: the double swap BUG-138 removes. 1.2 s
    /// doubles the window and still corrects an uncover that never reports; the device pass reads
    /// `[HomeHero] present` after a pop for a second commit to confirm it is enough.
    nonisolated static let uncoverRestoreDelay: TimeInterval = 1.2
    /// Whether the cover in force (or any cover that joined it before it lifted) is one tvOS restores
    /// row focus from. Decides which fallback the uncover arms.
    private var coverRestoresFocus = false

    /// The uncover fallback for a cover of that kind (pure; `HeroFocusCoverTests`).
    nonisolated static func uncoverDelay(restoresFocus: Bool) -> TimeInterval {
        restoresFocus ? uncoverRestoreDelay : uncoverVerifyDelay
    }

    /// Whether `pendingTask` is a revert (a nil report's grace) rather than a commit. A cover
    /// cancels a pending revert but lets a pending COMMIT land: that commit is the card the user
    /// selected from (a select inside the 0.2 s dwell), which is what the pop will restore focus to.
    private var pendingIsRevert = false

    /// beta.19-rc1 verdict (M5, BUG-138): see `covered`. Idempotent.
    ///
    /// beta.19-rc1 verdict (review r1, A P3): `restoresFocus` says whether tvOS hands focus back to
    /// the row card when this cover lifts (a push or the stream picker: true; the shell alone: false).
    /// It picks the uncover fallback (`uncoverDelay`). A cover that joins one already in force can
    /// only lengthen the fallback, never shorten it. Defaults to true, the conservative (longer) wait.
    func setCovered(_ isCovered: Bool, restoresFocus: Bool = true) {
        if isCovered, covered {
            if restoresFocus { coverRestoresFocus = true }
            return
        }
        guard isCovered != covered else { return }
        covered = isCovered
        uncoverVerifyTask?.cancel()
        uncoverVerifyTask = nil
        if isCovered {
            coverRestoresFocus = restoresFocus
            if pendingIsRevert {
                generation &+= 1
                pendingTask?.cancel()
                pendingTask = nil
                pendingIsRevert = false
            }
            return
        }
        let delay = Self.uncoverDelay(restoresFocus: coverRestoresFocus)
        coverRestoresFocus = false
        let generationAtUncover = generation
        uncoverVerifyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, !self.covered,
                  self.generation == generationAtUncover else { return }
            self.uncoverVerifyTask = nil
            self.claimSource = nil
            guard self.focusedItem != nil else { return }
            self.focusedItem = nil
            self.onRevert?()
        }
    }

    /// Called on every focus change a row reports — `nil` when nothing in that row holds focus.
    /// `source` is a stable identity for the reporting row (`section.key`, "continue-watching").
    func reportFocus(_ item: MetaPreview?, from source: String) {
        // A nil from a row that doesn't own the current claim is the trailing edge of a
        // cross-row hop; the row that DOES own the claim already spoke for itself.
        if item == nil, let claimSource, claimSource != source { return }
        // beta.19-rc1 verdict (M5, BUG-138): frozen while Home is covered — the nil is focus
        // leaving for the covering screen, not the user leaving the row. A pending revert dies; a
        // pending commit (the card selected inside its dwell) is left to land.
        if item == nil && covered {
            if pendingIsRevert {
                generation &+= 1
                pendingTask?.cancel()
                pendingTask = nil
                pendingIsRevert = false
            }
            return
        }
        // Any real report answers the uncover check (a non-nil one by itself; a nil one through
        // the ordinary revert grace below).
        uncoverVerifyTask?.cancel()
        uncoverVerifyTask = nil
        if item != nil { claimSource = source }

        // Already the committed TITLE (or already nil, reporting nil again): don't restart timers
        // — otherwise every re-render-driven refocus of the same card would keep pushing the
        // commit out. But a PENDING task must still die here: without that, a commit scheduled
        // for a card the focus already left lands late and drives the hero from a stale poster
        // (e.g. skim onto a card, then into a collection row before the 0.2s commit — the leaving
        // row's nil report matched this guard and the stale commit fired anyway; Codex review
        // finding).
        if (item == nil && focusedItem == nil)
            || (item != nil && focusedItem?.id == item?.id && focusedItem?.type == item?.type) {
            generation &+= 1
            pendingTask?.cancel()
            pendingTask = nil
            pendingIsRevert = false
            if item == nil { claimSource = nil }
            // Same title ≠ same preview: one id can be represented by different previews across
            // rows (a Continue Watching adaptation carries no description; a catalog card does).
            // Adopt the newly focused card's content immediately — the title is already
            // committed, so there's no dwell to honor — and leave a byte-identical re-report as
            // the pure no-op it should be (Codex review finding).
            //
            // BUG-151 (Steven rc3/rc4): the adopted preview carries the title's localized copy only
            // when the item on screen already shows it (its commit was localized); a title
            // committed in the catalog's language keeps that language on screen
            // (`StageLocalizedCopyStore.adoptMode`). The equality check runs on the prepared
            // preview, so a raw re-report of an already localized title stays a no-op.
            if let item {
                let adopted = StageLocalizedCopyStore.shared.preparedForAdopt(item, shown: focusedItem)
                if focusedItem?.isEqual(adopted) != true {
                    requestLogoIfNeeded(adopted)
                    focusedItem = adopted
                    enrichIfNeeded(adopted)
                }
            }
            return
        }

        generation &+= 1
        let generationAtStart = generation
        pendingTask?.cancel()

        if let item {
            pendingIsRevert = false
            pendingTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.commitDelay * 1_000_000_000))
                guard !Task.isCancelled, let self, self.generation == generationAtStart else { return }
                // beta.18 verdict (BUG-126): with `RowStepAB.deferHeroCommitUntilRest`, hold the
                // commit (logo lookup, hero crossfade, enrichment) until the engine's reveal motion
                // has been quiet for 0.12 s, polling every 50 ms, capped at 0.5 s. A newer focus
                // report bumps `generation` and voids the wait.
                if RowStepAB.isSet(RowStepAB.deferHeroCommitUntilRest, in: RowStepAB.mask) {
                    var elapsed: TimeInterval = 0
                    while let wait = RowStepAB.heroCommitDelay(sinceMotion: Self.motionClock(), elapsed: elapsed) {
                        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                        elapsed += wait
                        guard !Task.isCancelled, self.generation == generationAtStart else { return }
                    }
                }
                // BUG-151 (Steven rc3/rc4): a new title takes the stage, so its text is new
                // anyway: commit it with the cached localized name, synopsis and genres (the
                // user's TMDB Metadata Language, as Detail shows it). A cache miss commits the
                // catalog copy unchanged and starts the lookup for the title's next commit;
                // nothing already on screen is ever swapped (the BUG-42 rule).
                let committed = StageLocalizedCopyStore.shared.preparedForCommit(item)
                self.requestLogoIfNeeded(committed)
                self.focusedItem = committed
                self.enrichIfNeeded(committed)
            }
        } else {
            pendingIsRevert = true
            pendingTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.revertGrace * 1_000_000_000))
                guard !Task.isCancelled, let self, self.generation == generationAtStart else { return }
                self.pendingIsRevert = false
                self.focusedItem = nil
                self.claimSource = nil
                self.onRevert?()
            }
        }
    }

    /// FEAT-42: kicks a `TitleLogoStore` lookup for a card that is ABOUT to take over the hero —
    /// called immediately before both `focusedItem = item` publishes above (the same-title
    /// fast-path and the dwell-committed path), never from the raw per-card focus report, so a
    /// fast scrub across a row spends nothing: only the item the hand actually settles on (or
    /// re-settles on) ever reaches this. `HeroArtResolver.present`'s own `logoPlan` reads whatever
    /// this starts, so by the time `present` runs for this item a lookup already has a head start
    /// on the resolve's `laterSwapDeadline` window.
    ///
    /// Two guards: a collection folder already carries its OWN logo (`titleLogoUrl`, via
    /// `folderHeroPreview`) or none at all — either way it has no sensible TMDB id to look up
    /// under, matching `logoPlan`'s own folder short-circuit. And `isLookupCandidate` skips an
    /// item that already has a usable `logo` string — nothing to look up.
    private func requestLogoIfNeeded(_ item: MetaPreview) {
        guard !isCollectionHero(item) else { return }
        guard TitleLogoStore.isLookupCandidate(item.logo) else { return }
        TitleLogoStore.shared.lookupIfNeeded([item])
    }

    /// Addons frequently represent absent metadata as `""` rather than nil (HomeCatalogParser
    /// preserves whatever the addon sent), so "missing" must cover both.
    private func nonBlank(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// A catalog/CW preview commonly omits `description`/`banner` (Home only fetches the light
    /// list shape). Once a card commits to being the hero, fill those two gaps from TMDB — same
    /// service Detail already leans on — so the hero shows a synopsis instead of blank space.
    /// Fire-and-forget: on any miss (TMDB disabled, no key, no match, network failure) the hero
    /// simply keeps showing what it already had.
    ///
    /// BUG-42 scope decision (2026-08-05). The shared publish is now enrichment-FIRST: the hero
    /// carousel's items, and any row item the hero already fetched, arrive from
    /// `HomeRepository.publishCurrentState` already localized, so this layer is no longer the
    /// carousel's enrichment path — it only ever runs for a row poster that took over the hero
    /// (UX-7), and only for items the shared overlay does not cover. It is kept for exactly that
    /// surface, and reduced to a strict GAP FILL: it may add a synopsis/backdrop/logo/genres the
    /// preview never had, but it may NEVER replace a field that is already on screen. Replacing
    /// the committed title with TMDB's localized one is what produced the raw-then-localized
    /// double commit this fix removes ("The Devil's Mouth" swapping to "La Bouche du Diable"), and
    /// the focus takeover has no hold to hide it behind — it must commit the instant focus dwells.
    /// Consequence to know about: a focused row card outside the hero's fetched set shows its
    /// addon (usually English) title — matching the card under it — while its filled-in synopsis
    /// can be localized. Closing that gap means localizing row metadata broadly, which is the
    /// fetch-volume product call flagged in `HomeRepository.withTmdbEnrichment`, not a change here.
    private func enrichIfNeeded(_ item: MetaPreview) {
        // BUG-38 round three: a collection folder's preview is not a title — TMDB has nothing
        // for its synthetic id, and its artwork is already the user's configured assets.
        guard !isCollectionHero(item) else { return }
        guard nonBlank(item.description_) == nil || nonBlank(item.banner) == nil else { return }
        let settings = TmdbSettingsRepository.shared.snapshot()
        // rc13: `hasApiKey` is gone — the TMDB key is bundled at build time (`TmdbConfig.API_KEY`),
        // so "enabled" is the whole gate now.
        guard settings.enabled,
              settings.useArtwork || settings.useBasicInfo else { return }
        // suspend fun → Swift completion; result may arrive off the main thread, so hop back
        // (same convention as PersonDetailViewModel.start()).
        // FEAT-42 crash fix (2026-09-12): calls `fetchPreviewEnrichmentChecked`, not the
        // unchecked `fetchPreviewEnrichment` — a suspend function exported without `@Throws`
        // treats any non-cancellation exception as unhandled and aborts the process, which is
        // what `TitleLogoStore.lookupOne` hit under `-debug.heroLogoStoreOnly` (see its doc).
        TmdbMetadataService.shared.fetchPreviewEnrichmentChecked(
            type: item.type, id: item.id, settings: settings
        ) { [weak self] enrichment, error in
            DispatchQueue.main.async {
                guard error == nil else {
                    NSLog("[HomeHeroFocusModel] enrichIfNeeded failed item=%@ error=%@", item.id, String(describing: error))
                    return
                }
                // Merge whenever THIS title still (or again) owns the hero — identity, not
                // generation: a same-item refocus inside the grace window bumps the generation
                // without recommitting, and a generation gate here silently threw away the
                // in-flight enrichment for the title actually on screen (Codex review finding).
                // A different committed title fails the id/type check and rejects as before.
                // The merge BASE is the currently committed preview, not this request's `item`:
                // the same id may have been re-adopted from a richer row (CW → catalog) while the
                // fetch was in flight, and rebuilding from the stale capture would roll that back.
                guard let self, let enrichment, enrichment.hasContent(),
                      let base = self.focusedItem,
                      base.id == item.id, base.type == item.type
                else { return }
                // Field gating mirrors the shared hero path (HomeRepository.withTmdbEnrichment):
                // artwork fields only under useArtwork, text fields only under useBasicInfo — a
                // focused-row hero must not bypass the user's TMDB category preferences.
                let useArtwork = settings.useArtwork
                let useBasicInfo = settings.useBasicInfo
                let mergedBanner = self.nonBlank(base.banner) ?? (useArtwork ? enrichment.backdrop : nil)
                let mergedLogo = self.nonBlank(base.logo) ?? (useArtwork ? enrichment.logo : nil)
                let mergedDescription = self.nonBlank(base.description_) ?? (useBasicInfo ? enrichment.description_ : nil)
                let mergedGenres = base.genres.isEmpty && useBasicInfo ? enrichment.genres : base.genres
                // H-1C (beta.15): `enrichment.hasContent()` above only says the RESPONSE carried
                // something — not that the merge just computed actually ADDED anything to THIS
                // base. Every field it could fill may already be non-blank (the gap-fill guard at
                // the top of this function already required BOTH description and banner to be
                // present for it to have run at all — description alone, or banner alone, still
                // gets here with nothing left to fill), or gating (useArtwork/useBasicInfo off)
                // may zero out everything enrichment offered. A same-content reassignment still
                // republishes `focusedItem` — `@Published` doesn't check equality — which restarts
                // `HeroCrossfadeImage`'s `.task(id:)` for the row-focus hero path with nothing to
                // show for it. Skip the assignment entirely when nothing actually changed.
                // Codex wave-3 r2 (P2): compare NORMALIZED against normalized — an absent field is
                // commonly `""` in addon previews, which `nonBlank` maps to nil; comparing the
                // merged nil against the raw `""` would read as a change and republish a
                // semantically identical item, restarting the image task for nothing.
                guard mergedBanner != self.nonBlank(base.banner) || mergedLogo != self.nonBlank(base.logo) ||
                      mergedDescription != self.nonBlank(base.description_) || mergedGenres != base.genres
                else { return }
                self.focusedItem = MetaPreview(
                    id: base.id,
                    type: base.type,
                    // BUG-42: the committed title is left alone. Carousel parity no longer needs an
                    // override here — a row item the hero also carries is localized by the SHARED
                    // publish, so both copies already agree — and swapping a title the viewer is
                    // reading is the exact double commit this fix removes (see the doc comment).
                    name: base.name,
                    poster: base.poster,
                    banner: mergedBanner,
                    logo: mergedLogo,
                    posterShape: base.posterShape,
                    description: mergedDescription,
                    releaseInfo: base.releaseInfo,
                    rawReleaseDate: base.rawReleaseDate,
                    popularity: base.popularity,
                    voteCount: base.voteCount,
                    imdbRating: base.imdbRating,
                    genres: mergedGenres,
                    rawPosterUrl: nil,
                    landscapePoster: nil,
                    rawLandscapePosterUrl: nil,
                    customPosterApplied: false
                )
            }
        }
    }

    /// Hard reset: the CTA reclaimed the hero, or the row is going away. No grace period — this
    /// is a deliberate hand-back, not a between-cards focus hop.
    func cancelAndRevert() {
        generation &+= 1
        pendingTask?.cancel()
        pendingTask = nil
        pendingIsRevert = false
        uncoverVerifyTask?.cancel()
        uncoverVerifyTask = nil
        claimSource = nil
        let wasCommitted = focusedItem != nil
        focusedItem = nil
        if wasCommitted { onRevert?() }
    }
}

/// Wave H (BUG-86 phenomena B/C/D, BUG-90): everything the hero paints for ONE item, committed as a
/// single value. Before this type the hero was three independent paint pipelines racing each other —
/// text driven straight off `displayHero`, the backdrop cross-fading inside `HeroCrossfadeImage`
/// 0.3–0.5s behind it, and `HeroLogo` running its own `.task` that swapped Text→Image under its own
/// `withAnimation`. The tester filmed all three: the old backdrop under the new title (C), the title
/// text and the title logo drawn superimposed on every hero change (B), and a folder cover painting
/// before the folder backdrop (D). One value, committed once, removes the races by construction:
/// there is no state in which the hero shows one item's text over another item's artwork.
///
/// `backdrop`/`logo` are the DECODED bitmaps, not URLs — resolution happens in `HeroArtResolver`
/// before the commit, so a renderer can never be mid-fetch. `logo == nil` after the resolver's
/// deadline means "this item has no logo (or it did not arrive in time)": `HeroLogo` draws the text
/// wordmark, and a logo that lands later is DROPPED rather than swapped in behind the reader's eyes.
struct HeroPresentation: Equatable {
    let item: MetaPreview
    let backdrop: UIImage?
    let logo: UIImage?
    /// `"\(type):\(id)"` — the same stable identity `HeroCrossfadeImage` keys its paint bookkeeping
    /// on, so the two agree about what "the same item" means.
    let identity: String
    /// beta.19-rc1 verdict (M5, BUG-138): how `HeroLogo` must draw `logo` (`.dark` = a near-black
    /// wordmark drawn as a white silhouette). Decided by `HeroArtResolver` before the commit. A
    /// `.blank` verdict is committed with `logo == nil` (the text wordmark), so `HeroLogo` never
    /// receives a bitmap marked blank; the verdict is kept for the `present … logoInk=` probe. A
    /// `var` with a default so the memberwise init stays source-compatible (critique #25).
    var logoInk: HeroLogoInk = .legible

    /// `MetaPreview` is a Kotlin export and does not conform to Swift's `Equatable`, so the
    /// synthesized conformance is unavailable; images compare by REFERENCE (`ArtworkStore` hands out
    /// one decoded instance per URL, so identity is the honest test and pixel comparison would be
    /// absurd here).
    static func == (lhs: HeroPresentation, rhs: HeroPresentation) -> Bool {
        lhs.identity == rhs.identity
            && lhs.backdrop === rhs.backdrop
            && lhs.logo === rhs.logo
            && lhs.logoInk == rhs.logoInk
            && lhs.item.isEqual(rhs.item)
    }
}

/// Wave H rule (3): a hero item is painted only when its backdrop AND its logo are resolved, or a
/// deadline passed — and text, logo and backdrop then change in ONE transaction.
///
/// beta.19-rc1 verdict (M5, BUG-138): still one commit, but the TEXT (logo wordmark, meta line,
/// synopsis) is then phased by `HeroTextLayer`: the old text fades out over 0.12 s and the new text
/// is swapped in while invisible, so the two are never on screen together. The artwork follows the
/// commit at once, as before.
///
/// `HomeView.displayHero` remains the TARGET (what focus/the carousel/the settings say the hero
/// SHOULD be showing); `presented` is what is actually on screen. They differ only for the length of
/// one resolve, which is bounded by `laterSwapDeadline` (`folderDeadline` for collection folders).
///
/// Cache-warm path (the overwhelmingly common one, since every row focus prefetches its backdrops
/// and logos): both bitmaps are already resident, `present` commits synchronously inside one
/// `withAnimation`, and nothing ever renders half a hero. Cold path: the PREVIOUS presentation stays
/// on screen — never a blank, never a poster stand-in — while both fetches race a deadline, and
/// whatever has landed when the deadline (or the second fetch) fires is committed, once.
///
/// Late arrivals are dropped on purpose. A logo that resolves after its item was committed with the
/// text wordmark would be exactly the Text→Image swap this class exists to remove (BUG-90); the item
/// picks it up from cache the next time it is presented.
///
/// FEAT-42: which of four places the currently PRESENTED logo bitmap came from (or `.none` for no
/// logo / the text wordmark) — see `presentedLogoSource` and `HeroLogoPlan`.
enum HeroLogoSource: String {
    /// The item's own `logo` field, already populated by the shared layer or a row's addon.
    case addon
    /// `TitleLogoStore`'s own TMDB preview-enrichment lookup — the FEAT-42 path that reaches
    /// catalog items the shared enrichment overlay never touched (past `HOME_ROW_ENRICHMENT_PREFIX`,
    /// or a TMDB-id catalog the overlay skips entirely).
    case tmdb
    /// The synthesized `images.metahub.space/logo/medium/<imdb id>/img` guess for IMDb-backed
    /// items — synchronous by construction (no lookup to wait on), so Cinemeta rows never pay the
    /// `.pending` cost.
    case metahub
    /// No logo bitmap is presented — no candidate resolved (a plain miss, or nothing to look up),
    /// or the resolve hit its deadline before one arrived. `HeroLogo` draws the text wordmark.
    case none
}

/// FEAT-42: what `HeroArtResolver.logoPlan` decided to do about a target's logo BEFORE any fetch
/// runs. `.url` already carries the `HeroLogoSource` it will present if the fetch lands; `.pending`
/// means a `TitleLogoStore` lookup is already in flight and worth waiting on (inside the existing
/// `laterSwapDeadline` — no new budget); `.none` means there is nothing to look up or wait for.
enum HeroLogoPlan: Equatable {
    case url(URL, HeroLogoSource)
    case pending
    case none
}

extension RowRestSource {
    /// beta.19-rc1 verdict (review r1, A P2): the rows have not moved for
    /// `TrailerStartGate.restQuiet`, whatever the settle corrector's pending flag says: `isAtRest()`
    /// with `restPending` read as false, over the same clocks per source. The hero sharpen's rest
    /// ceiling releases only on a quiet stretch (`HeroSharpen.restStep`'s `quietAge`), so a stuck
    /// settle decision gives way and real motion never does.
    @MainActor var rowsQuiet: Bool {
        let since: TimeInterval
        switch self {
        case .motionClock:
            since = RowsMotionClock.secondsSinceMotion()
        case .pinnedHome:
            since = min(PinnedRowSettle.secondsSinceMotion(), RowsMotionClock.secondsSinceMotion())
        case .custom(let signal):
            since = signal.secondsSinceMotion
        }
        return TrailerStartGate.isAtRest(sinceMotion: since, restPending: false)
    }
}

@MainActor
final class HeroArtResolver: ObservableObject {
    /// The hero that is actually painted. `nil` = no hero region at all (the same state
    /// `displayHero == nil` produced before this type existed).
    @Published private(set) var presented: HeroPresentation?

    /// FEAT-42: where `presented`'s logo bitmap came from — `.none` when `presented` has no logo
    /// (or `presented` itself is nil). Set inside the SAME animation transaction as `presented` in
    /// every commit path (`commit`, the same-identity gap-fill branch, `adoptLateBackdrop`, and the
    /// nil-target revert in `present`), so a viewer can never observe `presented` and
    /// `presentedLogoSource` disagreeing about the same hero. Not part of `HeroPresentation`
    /// itself/`HeroPresentation.==` — it is diagnostic (the `debug_hero` `plgs=` field, the
    /// `hero_probe_blob` `logoSrc=` field), not something any renderer branches on.
    @Published private(set) var presentedLogoSource: HeroLogoSource = .none

    /// How long a swap between two TITLES waits for cold artwork before committing with whatever
    /// landed. Titles always have a poster on their card, and the resolve now falls back to it
    /// inside this same budget, so a miss here is a short wait on the previous hero and then the
    /// poster, never a blank screen.
    static let laterSwapDeadline: UInt64 = 400_000_000
    /// Collection folders get longer: their artwork is the user's own configured backdrop/logo, it
    /// has no poster stand-in (`folderHeroPreview` passes `poster: nil` on purpose), and the row's
    /// `.onAppear` prefetch usually makes this moot anyway.
    ///
    /// 2026-09-08: rig-only knob so `HeroFolderSwapTests` can force a deadline miss and prove the
    /// `adoptLateBackdrop` late-arrival path — on the simulator's real image hosts the fetch
    /// routinely answers in under 60 ms, well inside even a shortened deadline, so the rig needs a
    /// way to make the miss happen on demand rather than hoping for a slow network. `#if DEBUG`
    /// only: the `debug.heroFolderDeadlineMs` launch/default override is never read in a release
    /// build, where `folderDeadline` stays the plain compile-time constant it always was — the
    /// `#if DEBUG` guard is the whole point, not an incidental detail. Read via
    /// `UserDefaults.integer(forKey:)`, not `object(forKey:) as? Int` — a `-debug.heroFolderDeadlineMs
    /// <ms>` launch argument lands in the argument domain as a STRING, and `as? Int` on a string
    /// always fails, silently disarming the knob; `integer(forKey:)` coerces it (and answers `0`,
    /// treated below as "absent", for any key that is missing entirely). Read once (`UserDefaults`
    /// lookups are not free on a hot path this is adjacent to) and cached in a `static let`, so a
    /// value set before launch (via `-debug.heroFolderDeadlineMs <ms>` or a prior `defaults write`)
    /// applies for the whole process lifetime.
    #if DEBUG
    private static let debugFolderDeadlineOverrideMs: Int =
        UserDefaults.standard.integer(forKey: "debug.heroFolderDeadlineMs")
    static var folderDeadline: UInt64 {
        if debugFolderDeadlineOverrideMs > 0 { return UInt64(debugFolderDeadlineOverrideMs) * 1_000_000 }
        return 1_500_000_000
    }
    #else
    static let folderDeadline: UInt64 = 1_500_000_000
    #endif

    /// `defaults write com.nuvio.media.NuvioTV debug.heroLogoStoreOnly -bool YES`, or as a launch
    /// argument on device/CI/UI tests. When set, `present` calls `logoPlan` with `addonLogo: nil`
    /// and `allowMetahub: false`, so a logo can only ever come from `TitleLogoStore` (steps 3/5 of
    /// `logoPlan`'s doc comment) — never the item's own logo (step 1) or the synchronous metahub
    /// guess (step 4).
    ///
    /// Exists so `test62HeroLogoOnRowFocus` can prove the store path deterministically. In
    /// production, and on the fixture `test62` walks, a row's own logo (filled in by the Kotlin row
    /// overlay for its leading items) or the metahub guess almost always resolves before the store
    /// does, so `plgs=tmdb` on any given card was only ever provable by timing luck, not by
    /// contract. This knob removes both faster candidates so every read that produces a logo at all
    /// is forced through the store, without changing `logoPlan`'s priority order for anyone who
    /// hasn't passed it.
    ///
    /// Production never sets this — an item's own logo and the metahub guess are both legitimate
    /// candidates, and disabling them here would blank real heroes that have neither a resolved
    /// store URL nor a pending lookup. `#if DEBUG` only, matching `debugFolderDeadlineOverrideMs`
    /// immediately above: never read in a release build, where `heroLogoStoreOnly` is a compile-time
    /// `false` and `present` always passes `allowMetahub: true` and the item's own logo unchanged.
    #if DEBUG
    private static let heroLogoStoreOnlyByKnob =
        UserDefaults.standard.bool(forKey: "debug.heroLogoStoreOnly")
    static var heroLogoStoreOnly: Bool { heroLogoStoreOnlyByKnob }
    #else
    static let heroLogoStoreOnly: Bool = false
    #endif

    /// The in-flight resolve, if any. Also the whole of `isIdle` — the carousel's auto-advance tick
    /// must not page while a commit is pending, or the resolve it started is thrown away and the
    /// next page starts cold (the same reason the tick already holds for a trailer attempt).
    private var resolveTask: Task<Void, Never>?
    /// The identity the newest `present` call asked for. A resolve that finishes after a newer call
    /// has superseded it fails this check and commits nothing.
    private var targetIdentity: String?
    /// The item the newest `present` call asked for, kept whole so a repeat call with a
    /// byte-identical target can be recognised as the no-op it is — see the guard in `present`.
    private var lastTarget: MetaPreview?

    /// rc12 (Codex Finding A): when the FIRST `present` for the CURRENT `targetIdentity` started
    /// resolving, so a later `present` for that same identity inherits the original budget instead
    /// of restarting it (see `resolveDeadline` and the wiring in `present`). nil whenever no resolve
    /// is outstanding for the current target: cleared with the target itself, reset to nil the
    /// moment the identity changes, and cleared again on the cache-warm path that commits without
    /// starting a resolve at all.
    private var targetResolveStartedAt: Date?

    // beta.19-rc1 verdict (I1, BUG-134): the post-commit sharpen (`HeroSharpen`). None of these is
    // `@Published`: they decide what to fetch, never what to draw, so nothing re-renders on them.

    /// The form the presented backdrop is drawn in. `HomeView` sets it (`setSharpenForm`).
    private(set) var sharpenForm: HeroSharpen.Form = .classic
    /// The URL the presented backdrop bitmap was decoded from. nil when there is no backdrop, and for
    /// the poster stand-in: a different picture, which is never sharpened.
    private var presentedBackdropURL: URL?
    /// beta.19-rc1 verdict (review r2, P3-2): the presented backdrop is the card-size stand-in (the
    /// same picture, `backdrop=small`), committed because the legacy re-decode missed the deadline.
    /// That legacy decode, landing late, may replace it (`adoptLateBackdrop`); nothing else may. Set
    /// by `commit`, cleared by any commit or sharpen that puts another backdrop on screen. A plain
    /// stored property: nothing draws from it.
    private var presentedBackdropIsStandIn = false
    /// beta.19-rc1 verdict (review r3, P3 #1): which `commit` put the presentation on screen (bumped
    /// by every commit that changes it) and when (`systemUptime`). The late stand-in replacement
    /// waits out that commit's own backdrop cross-fade (`lateStandInFadeWait`) and replaces only the
    /// stand-in of the commit it was called for. Plain stored properties: nothing draws from them.
    private var presentedCommitSerial = 0
    private var presentedCommittedAt: TimeInterval = 0
    /// The URL the presented logo bitmap was decoded from (nil = the text wordmark). The `.pending`
    /// path learns it from `TitleLogoStore.awaitLogoURL` (`HeroPresentArtWait.logoURL`).
    private var presentedLogoURL: URL?
    /// The dwell, then the fetch, for the hero on screen. Cancelled by any `present` that moves the
    /// hero to another identity; not counted by `isIdle`, so it never holds the carousel tick.
    private var sharpenTask: Task<Void, Never>?
    /// Bumped by every schedule and cancel. A sharpen whose generation moved adopts nothing.
    private var sharpenGeneration = 0
    /// beta.19-rc1 verdict (review r1, A P2): the rows' rest signal the sharpen waits on before it
    /// fetches and again before it adopts (`HeroSharpen.restStep`). `HomeView` assigns it from the
    /// same place, and with the same value, as the hero trailer model's (`.onAppear` and
    /// `.onChange(of: heroContainerPinned)`): pinned Home reads the settle corrector plus the rows'
    /// motion clock, classic Home the clock alone. A plain stored property: nothing draws from it,
    /// and HomeView's body observes nothing new.
    var restSource: RowRestSource = .motionClock

    var isIdle: Bool { resolveTask == nil }

    /// rc12 (Codex Finding A): the ABSOLUTE deadline rule for a resolve that is restarted for the
    /// SAME target identity.
    ///
    /// `present` is driven from two `.onChange`s and a same-identity payload update (a synopsis or
    /// a genre list landing from TMDB, `heroPayloadSignature` moving) cancels the resolve in flight
    /// and starts a new one. The same-identity branch further up only short-circuits an
    /// already-PRESENTED title, so while the FIRST resolve is still running each such update used
    /// to hand the new resolve a fresh `laterSwapDeadline` — Codex measured an update at 300 ms
    /// holding the PREVIOUS title on screen until 496 ms, where the pre-rc12 warm-backdrop case
    /// committed immediately. Budgets must not be stackable: the viewer is looking at a stale hero
    /// for the sum, not for one 400 ms window.
    ///
    /// So the wait inherits the first present's clock. `previousStart` is when this identity first
    /// began resolving (nil for a genuinely new target, which gets the whole `budget`); the answer
    /// is whatever is LEFT of `budget`, and 0 once it is spent — a zero-nanosecond sleep, which
    /// fires the deadline on the next turn and commits whatever is ready (the existing
    /// deadline-commit path, unchanged). A non-positive `elapsed` (a clock that moved backwards)
    /// answers the full budget rather than a negative remainder.
    ///
    /// BUG-90 is untouched: this only ever SHORTENS how long the previous hero is held, and a logo
    /// or backdrop that lands after the deadline is still dropped by `HeroPresentArtWait`, never
    /// swapped in behind the reader's eyes.
    nonisolated static func resolveDeadline(previousStart: Date?, now: Date, budget: UInt64) -> UInt64 {
        guard let previousStart else { return budget }
        let elapsed = now.timeIntervalSince(previousStart)
        guard elapsed > 0 else { return budget }
        let elapsedNanos = elapsed * 1_000_000_000
        let budgetNanos = Double(budget)
        guard elapsedNanos < budgetNanos else { return 0 }
        return UInt64((budgetNanos - elapsedNanos).rounded())
    }

    /// FEAT-42: decides where (if anywhere) a target's presented logo should come from, in
    /// priority order, BEFORE any fetch runs. Pure and `nonisolated static` so
    /// `HeroLogoPlanTests` can drive every combination directly.
    ///
    /// 1. `addonLogo` — the item's own `logo` field wins outright when it is non-blank and
    ///    parses as a URL. A blank string or one that fails `URL(string:)` falls through to the
    ///    next step rather than producing a broken `.url`.
    /// 2. `isFolder` — a collection folder never gets a store/metahub lookup: it has no sensible
    ///    TMDB id to look up under (`folderHeroPreview` already sets its OWN `logo` from
    ///    `titleLogoUrl` when it has one, which step 1 already covers), so this stops here at
    ///    `.none` rather than falling through to metahub with a folder's synthetic id.
    /// 3. `storeURL` — `TitleLogoStore`'s own resolved TMDB lookup, when one already landed.
    ///    Checked BEFORE metahub deliberately: metahub is a synthesized guess that often 404s,
    ///    while a resolved TMDB URL is a confirmed hit — a stale metahub source must never win
    ///    once the real answer is in hand.
    /// 4. Metahub — synthesized only for IMDb-backed ids (`tt…`, and season/episode-suffixed ids
    ///    like `tt…:1:1`, whose first `:`-separated component is checked). Synchronous by
    ///    construction (no network round trip to decide this branch), so Cinemeta rows never pay
    ///    the `.pending` wait — and it is checked BEFORE `.pending` so an IMDb item with a lookup
    ///    still in flight uses the synchronous guess rather than waiting on the store (a lookup
    ///    that finishes later still wins on this item's NEXT presentation via step 3). Skipped
    ///    entirely when `allowMetahub` is `false` — the plan falls straight through to step 5.
    /// 5. `storePending` — a `TitleLogoStore` lookup is in flight and this item has no faster
    ///    candidate; `.pending` tells `present` to wait for it inside the existing
    ///    `laterSwapDeadline`, never a new budget.
    /// 6. `.none` — nothing to show and nothing to wait for. This is also where a TMDB-disabled
    ///    session lands by construction: with TMDB off `TitleLogoStore` never writes a `.pending`
    ///    entry (`lookupIfNeeded`'s own settings guard), so `storeURL` is always nil and
    ///    `storePending` is always false here — no separate "is TMDB on" parameter is needed.
    ///
    /// `allowMetahub` defaults to `true` for every existing caller and test. `present` passes
    /// `false` only under the `debug.heroLogoStoreOnly` `#if DEBUG` launch knob (see
    /// `HeroArtResolver.heroLogoStoreOnly`'s doc comment) — a UI-test-only way to prove the store
    /// path deterministically on a fixture whose faster candidates (an item's own logo, or the
    /// metahub guess) would otherwise almost always win first. Production never passes `false`.
    nonisolated static func logoPlan(addonLogo: String?, id: String, isFolder: Bool,
                                     storeURL: String?, storePending: Bool,
                                     allowMetahub: Bool = true) -> HeroLogoPlan {
        if let addonLogo, !addonLogo.isEmpty, let url = URL(string: addonLogo) {
            return .url(url, .addon)
        }
        if isFolder { return .none }
        if let storeURL, !storeURL.isEmpty, let url = URL(string: storeURL) {
            return .url(url, .tmdb)
        }
        if allowMetahub {
            let imdbId = id.split(separator: ":").first.map(String.init) ?? id
            if imdbId.hasPrefix("tt"),
               let url = URL(string: "https://images.metahub.space/logo/medium/\(imdbId)/img") {
                return .url(url, .metahub)
            }
        }
        if storePending { return .pending }
        return .none
    }

    /// Point the hero at `target`. Cancels any resolve in flight; the previous presentation stays on
    /// screen until this one can be committed whole.
    func present(_ target: MetaPreview?, isFolder: Bool) {
        // Idempotent by contract. `HomeView` drives this from TWO `.onChange`s — the target's
        // identity and the target's payload — and a genuinely new hero changes both, so the second
        // one arrives with nothing left to do. Without this guard that repeat would cancel and
        // restart a resolve that had just started, resetting its deadline clock, and re-run the
        // same-identity branch below for a payload that had not moved at all.
        if let target, let last = lastTarget,
           "\(target.type):\(target.id)" == targetIdentity, last.isEqual(target) { return }
        if target == nil, targetIdentity == nil, lastTarget == nil { return }
        lastTarget = target
        resolveTask?.cancel()
        resolveTask = nil

        guard let target else {
            targetIdentity = nil
            targetResolveStartedAt = nil
            // beta.19-rc1 verdict (I1, BUG-134): no hero, nothing to sharpen.
            cancelSharpen()
            guard presented != nil else { return }
            presentedBackdropURL = nil
            presentedBackdropIsStandIn = false
            presentedLogoURL = nil
            // FEAT-42: reset together with `presented`, in the same transaction — see
            // `presentedLogoSource`'s doc comment on why the two may never disagree.
            withAnimation(.easeInOut(duration: 0.3)) {
                presented = nil
                presentedLogoSource = .none
            }
            return
        }

        let identity = "\(target.type):\(target.id)"
        // rc12 (Codex Finding A): read the OUTGOING target before overwriting it. A present for the
        // identity that is already the target inherits that target's resolve clock (see
        // `resolveDeadline`); any other present is a genuinely new swap and starts a fresh budget,
        // which is what a nil inheritance means.
        let inheritedResolveStart = targetIdentity == identity ? targetResolveStartedAt : nil
        targetIdentity = identity
        targetResolveStartedAt = inheritedResolveStart

        // Same item, new payload: the ONE change allowed after a commit (Wave H invariant 2) is a
        // silent gap-fill of text the item did not carry when it was committed — a synopsis landing
        // from TMDB, say. The artwork is kept exactly as it is: re-resolving it here is the
        // raw-then-enriched repaint the tester filmed, and `same=1` on the probe line is precisely
        // the signature a healthy launch must not contain.
        if identity == presented?.identity, let current = presented {
            // beta.19-rc1 verdict (M5): the logo's ink verdict rides along with the logo bitmap.
            let refreshed = HeroPresentation(item: target, backdrop: current.backdrop,
                                             logo: current.logo, identity: identity,
                                             logoInk: current.logoInk)
            // beta.19-rc1 verdict (I1, BUG-134): a gap-fill keeps the artwork, so it keeps a
            // pending sharpen as well. A hero the target has come BACK to (A → B → A before B
            // committed, which cancelled A's sharpen) arms one again; `HeroSharpen.plan` makes a
            // re-arm on a hero that is already sharp a no-op (`sharpen none`).
            if sharpenTask == nil { scheduleSharpen(identity: identity) }
            guard refreshed != current else { return }
            // `same=1` means REPAINT: the probe line the photo contract forbids on a healthy
            // launch.
            //
            // Internal review r1 (P2), the contract it now encodes. The old test compared the two
            // BITMAPS, which could never differ - `refreshed` is built from `current.backdrop` and
            // `current.logo` by construction, so `!==` was structurally false and `same=1` was
            // unreachable. That made test31's `same=1` filter vacuous and, worse, hid the one
            // same-identity path that DOES repaint text the viewer is reading: `enrichIfNeeded`
            // (and a Kotlin re-publish) moving `name` / `genres` / `releaseInfo` / `description` at
            // a stable identity - the English-replaced-by-French flip the tester filmed.
            //
            // So the test is now what actually changes ON SCREEN (see `isVisibleRepaint`), and a
            // text repaint after the commit IS a violation. The ONE exception, the allowed silent
            // gap-fill, is a field that was empty or nil being FILLED - a synopsis or a genre list
            // landing from TMDB for an item committed without one. That adds text, replaces
            // nothing, and stays silent.
            //
            // A refresh that changes nothing visible still logs nothing at all, deliberately,
            // rather than a `same=0` line: Leg C counts one `paint` per `present` for the focused
            // folder and a present-with-no-paint would break that count.
            if HeroArtResolver.isVisibleRepaint(current: current.item, target: target) {
                // FEAT-42: the logo bitmap is untouched here (built from `current.logo` above,
                // same as the backdrop) — `presentedLogoSource` is passed through unchanged for
                // the log line, never recomputed, since a gap-fill never re-resolves artwork.
                logPresent(identity: identity,
                           backdrop: refreshed.backdrop != nil ? "cached" : "none",
                           logo: refreshed.logo != nil ? "cached" : "text",
                           logoOrigin: presentedLogoSource,
                           logoInk: refreshed.logoInk,
                           waitedMs: 0, same: true)
            }
            presented = refreshed   // deliberately unanimated: a gap-fill must not move anything
            return
        }

        // beta.19-rc1 verdict (I1, BUG-134): the hero is moving to another identity, so the one on
        // screen no longer sharpens (the commit below arms the newcomer's own).
        cancelSharpen()

        let backdropURL = heroBackdropURL(for: target).flatMap { URL(string: $0) }
        // FEAT-42 (decision b′): resolver-side lookup, no payload merge. `logoPlan` decides in
        // priority order (own logo → folder stops → `TitleLogoStore`'s resolved URL → a
        // synchronous metahub guess for IMDb ids → a `TitleLogoStore` lookup already in flight →
        // nothing) — see that function's own doc comment. The URL never enters `MetaPreview`, so
        // `heroPayloadSignature`/`isVisibleRepaint`/`headHashHex` are untouched by construction.
        //
        // Under the `debug.heroLogoStoreOnly` knob (`#if DEBUG` only, see `heroLogoStoreOnly`'s doc
        // comment) the item's own logo is withheld and the metahub guess is disallowed, so the
        // plan can only resolve through the store — a UI-test-only override, never live in a
        // release build.
        let storeOnly = HeroArtResolver.heroLogoStoreOnly
        let plan = HeroArtResolver.logoPlan(
            addonLogo: storeOnly ? nil : target.logo, id: target.id, isFolder: isFolder,
            storeURL: TitleLogoStore.shared.logoURL(for: target),
            storePending: TitleLogoStore.shared.isLookupPending(for: target),
            allowMetahub: !storeOnly
        )
        // The origin this presentation will log/commit IF a logo bitmap actually ends up
        // resolved — `.pending` always implies a `TitleLogoStore`/TMDB answer by construction (see
        // `logoPlan`'s doc comment, step 5). Every commit site below still gates this on the final
        // `logo != nil`: a plan that names a source whose fetch then misses presents no logo at
        // all, and `presentedLogoSource` must read `.none` for that, not the source that failed.
        let planLogoOrigin: HeroLogoSource = {
            switch plan {
            case .url(_, let source): return source
            case .pending: return .tmdb
            case .none: return .none
            }
        }()
        let logoURL: URL? = {
            if case .url(let url, _) = plan { return url }
            return nil
        }()
        // beta.19-rc1 verdict (review r1, B P2-1): the legacy-size lookup, not the any-bucket seed. A
        // Continue Watching / landscape / Upcoming / saga card decodes the same backdrop URL at its
        // drawn size (768–1024 px), and the seed form handed that card bitmap to the hero, which
        // committed it 3–5× upscaled. `.legacy` accepts only a decode ≥ min(1920, source) (or a
        // sharper rendition, the sharpen's `original`); a card-only entry is a miss, and the
        // backdrop fetch below re-decodes it from the URLCache bytes inside the same deadline. The
        // backdrop fetch below already decodes `.legacy` (its default) with the same floor on its
        // memory check.
        let cachedBackdrop = ArtworkStore.cached(backdropURL, decode: .legacy)
        // beta.19-rc1 verdict (review r2, P3-1): the logo is drawn in a bounded slot, so it is looked
        // up (and fetched, below) at that slot's request, not `.legacy`: the legacy floor is 1920 px
        // for a URL never decoded itself, so a `w500` logo refused the `original` Detail had decoded
        // for its slot, and the `w500` fetch then had to make the 400 ms deadline or the hero
        // committed the text wordmark. Any decode of the picture that covers the slot is a hit now.
        let logoRequest = HeroSharpen.heroLogoRequest
        let cachedLogo = ArtworkStore.cached(logoURL, decode: logoRequest)
        let needsBackdrop = backdropURL != nil && cachedBackdrop == nil
        // beta.19-rc1 verdict (review r1, B P2-1): the SAME picture at a card's size, when that is
        // all memory holds for a title's backdrop. Never committed while the legacy re-decode makes
        // the deadline (it normally does: the bytes are in the URLCache, and the fetch below goes to
        // the front of the six-slot gate). If it misses, this stands in rather than the item's
        // poster (a different picture, which `adoptLateBackdrop` then never replaces): it records
        // the backdrop URL like any backdrop, so the post-commit sharpen upgrades it at rest. Title
        // heroes only, the same gate as the poster stand-in: folders keep their `none` → `late`
        // path untouched. Review r2 (P3-2): the legacy re-decode that missed the deadline replaces
        // it when it lands, at the next rest (`adoptLateBackdrop`), usually well before the sharpen.
        let backdropStandIn: UIImage? = needsBackdrop && !isFolder && !isCollectionHero(target)
            ? ArtworkStore.cached(backdropURL) : nil
        // `.pending` has no `logoURL` of its own yet (the fetch only starts once
        // `TitleLogoStore.awaitLogoURL` answers), so it must opt into the wait independently of
        // the `logoURL != nil` check below.
        let needsLogo = (logoURL != nil && cachedLogo == nil) || plan == .pending

        // Codex branch review: the poster stand-in for a primary that never lands.
        //
        // `heroBackdropURL(for:)` synthesizes `images.metahub.space/background/medium/tt…/img` for
        // any IMDb-backed item that carries no `banner`, and that URL 404s for plenty of real
        // titles. The image-driven `HeroCrossfadeImage` used to own the recovery (it took a
        // `fallbackURL` and swapped to the poster when the primary failed); the Wave H resolver
        // hands it a decoded bitmap instead, so with no fallback here those titles committed a
        // BLANK hero even though their poster was on screen in the row below.
        //
        // Title heroes ONLY. A collection folder must never paint its cover: a square cover
        // scaled-to-fill into the 16:9 hero and then replaced is the "background pops in larger
        // then shrinks" the tester filmed (Wave H hole H2), which is why `folderHeroPreview` passes
        // `poster: nil` in the first place. The `isFolder` flag and the type predicate both gate
        // it, since either alone would be a single point of failure for that regression.
        let posterFallbackURL: URL? = {
            // Review r1 (B P2-1): a same-picture stand-in (above) beats the poster.
            guard !isFolder, !isCollectionHero(target), needsBackdrop, backdropStandIn == nil else { return nil }
            guard let poster = target.poster, !poster.isEmpty,
                  let url = URL(string: poster), url != backdropURL else { return nil }
            return url
        }()
        // beta.19-rc1 verdict (review r1, B P2-1): the poster stand-in deliberately keeps the
        // any-bucket seed lookup (spec P-B §I1.7 item 2): the card's own decode of the poster is the
        // right stand-in, and requiring a legacy-size one would put a fresh decode (or, when the card
        // drew an upgraded rendition the item's own poster URL never fetched, a fresh download) inside
        // the 400 ms deadline.
        let cachedPosterFallback = ArtworkStore.cached(posterFallbackURL)
        let needsPosterFallback = posterFallbackURL != nil && cachedPosterFallback == nil

        guard needsBackdrop || needsLogo else {
            // Nothing to wait for, so there is no clock to carry: a same-identity payload update
            // after this point is handled by the gap-fill branch above (this commit makes
            // `presented.identity` match), and should the hero ever be re-resolved for this
            // identity later it deserves the whole budget (rc12, Codex Finding A).
            targetResolveStartedAt = nil
            // beta.19-rc1 verdict (M5, BUG-138): a cache-warm logo (prefetched by a row) has no
            // ink memo yet the first time; `inkedLogo` samples it here, synchronously, once per URL.
            let inked = Self.inkedLogo(cachedLogo, url: logoURL)
            commit(item: target, backdrop: cachedBackdrop, logo: inked.logo, identity: identity,
                   backdropSource: cachedBackdrop != nil ? "cached" : "none",
                   logoSource: inked.logo != nil ? "cached" : "text",
                   logoOrigin: inked.logo != nil ? planLogoOrigin : .none,
                   logoInk: inked.ink,
                   waitedMs: 0,
                   backdropURL: backdropURL, logoURL: logoURL)
            return
        }

        let started = Date()
        // rc12 (Codex Finding A): the budget is absolute per TARGET, not per resolve. A resolve
        // restarted for the identity that is already resolving keeps the first present's clock, so
        // the previous hero is held for at most one `laterSwapDeadline` no matter how many
        // same-identity payload updates land inside it. `started` itself stays "now" on purpose:
        // `waited=` on the probe line measures THIS resolve's own segment, the way every existing
        // oracle reads it.
        targetResolveStartedAt = inheritedResolveStart ?? started
        let deadline = Self.resolveDeadline(previousStart: inheritedResolveStart, now: started,
                                            budget: isFolder ? Self.folderDeadline : Self.laterSwapDeadline)
        let wait = HeroPresentArtWait(backdrop: cachedBackdrop, logo: cachedLogo,
                                      needsBackdrop: needsBackdrop, needsLogo: needsLogo,
                                      posterFallback: cachedPosterFallback,
                                      needsPosterFallback: needsPosterFallback)

        // Round 3: the two fetches are unstructured and are NEVER cancelled, exactly as
        // `HeroCommitCoordinator.prepare(_:)` issues the head's pair. The task-group form this
        // replaced could not honour its own deadline: a group awaits every child on the way out
        // even after `cancelAll()`, and `ArtworkStore.fetch` parks on shared unstructured work that
        // ignores waiter cancellation by design (a cancelled awaiter still lets the image land in
        // the cache for the next viewer). So one stalled backdrop deferred the whole PRESENTATION
        // by the URLSession timeout instead of by 400 ms, holding the previous hero on screen for
        // tens of seconds. `deadline` is now a real ceiling: `present` commits at most ~deadline
        // after the target changed, whatever the network is doing.
        //
        // Nothing is wasted by letting the fetches run on. `ArtworkStore` caches what lands, so a
        // backdrop that misses this deadline is already warm the next time the item is presented.
        //
        // `.head` admission (`ArtworkStore.FetchAdmission`): this IS the hero being shown, so it
        // goes to the front of the six-slot gate rather than queueing behind a screenful of row
        // poster prefetches.
        if needsBackdrop, let backdropURL {
            Task { @MainActor [weak self] in
                let image = try? await ArtworkStore.fetch(backdropURL, admission: .head)
                wait.resolveBackdrop(image)
                // 2026-09-08 finding: on a cold cache this fetch routinely lands AFTER the deadline
                // already committed with no backdrop (see `adoptLateBackdrop`'s doc comment). Past
                // the deadline `wait.resolveBackdrop` above is a no-op (pinned by
                // `HeroPresentArtWaitTests.testStalledBackdropResumesAtTheDeadlineWithTheCachedLogo`),
                // so the image reaching here is read off this closure's own local, never off `wait`.
                if wait.hitDeadline, let image {
                    self?.adoptLateBackdrop(image, identity: identity, startedAt: started, url: backdropURL)
                }
            }
        }
        if needsLogo, let logoURL {
            // `.url` case (the plan already names a concrete URL — addon, TMDB store, or
            // metahub) and it wasn't cached.
            Task { @MainActor [weak self] in
                let image = try? await ArtworkStore.fetch(logoURL, decode: logoRequest, admission: .head)
                // beta.19-rc1 verdict (M5, BUG-138): sample the ink OFF the main actor and memoize
                // it BEFORE the wait sees the bitmap, so the commit reads the memo (`inkedLogo`).
                if let image { _ = await HeroLogoInk.prepare(image, url: logoURL.absoluteString) }
                wait.resolveLogo(image, url: logoURL)
                // FEAT-42 repair: metahub is a synthesized GUESS (BUG-17) — a miss here does not
                // mean the item has no logo, only that this guess was wrong. Kick a real
                // `TitleLogoStore` lookup so the item's NEXT presentation can use step 3 of
                // `logoPlan` (a confirmed TMDB URL) instead of repeating the same bad guess. Only
                // for the metahub source: an addon-supplied or already-cached TMDB URL that 404s
                // is a dead link, not a guess worth re-resolving.
                guard image == nil, case .url(_, .metahub) = plan else { return }
                self?.repairMetahubMiss(for: target)
            }
        } else if needsLogo, plan == .pending {
            // `.pending` case — no URL to fetch yet; await the in-flight `TitleLogoStore` lookup
            // first, then fetch whatever it resolves to. Past `deadline` this is a no-op the same
            // way every other late arrival in this class is: `wait.resolveLogo` guards on
            // `!finished` and drops it.
            Task { @MainActor in
                guard let resolvedURLString = await TitleLogoStore.shared.awaitLogoURL(for: target),
                      let resolvedURL = URL(string: resolvedURLString) else {
                    wait.resolveLogo(nil)
                    return
                }
                let image = try? await ArtworkStore.fetch(resolvedURL, decode: logoRequest, admission: .head)
                // beta.19-rc1 verdict (M5): same off-main ink sample as the `.url` path, keyed on
                // the URL the store resolved (handed to the wait so the commit can read the memo).
                if let image { _ = await HeroLogoInk.prepare(image, url: resolvedURL.absoluteString) }
                wait.resolveLogo(image, url: resolvedURL)
            }
        }
        // Concurrent with the primary, deliberately, so the fallback costs the commit no extra
        // time: the poster is either in hand by the moment the primary misses, or it is still in
        // flight and the same `deadline` covers both. Starting it only after the miss would push
        // a cold poster past the budget on exactly the titles that need it. `.head` for the same
        // reason the other two are: the hero is what the whole screen is waiting on.
        // beta.19-rc1 verdict (I1, BUG-134): the same URL and the same download as before, decoded
        // into the poster prewarm's 896 px bucket (`HeroCommitCoordinator.posterPixelsDecode`) so
        // the entry also serves the row's poster card. The lookup above (`cached`, any bucket, any
        // rendition) already finds the card's own decode when the row drew it first.
        if needsPosterFallback, let posterFallbackURL {
            Task { @MainActor in
                let image = try? await ArtworkStore.fetch(posterFallbackURL,
                                                          decode: HeroCommitCoordinator.posterPixelsDecode,
                                                          admission: .head)
                wait.resolvePosterFallback(image)
            }
        }

        resolveTask = Task { [weak self] in
            let deadlineTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: deadline)
                guard !Task.isCancelled else { return }
                wait.deadlineElapsed()
            }
            // Resumed by the last needed fetch, by `deadlineTask`, or by cancellation, whichever
            // is first. A superseded `present` cancels this task; the handler stops the wait and
            // the identity guard below then commits nothing.
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    wait.attach(continuation)
                }
            } onCancel: {
                Task { @MainActor in wait.cancelWait() }
            }
            deadlineTask.cancel()
            guard !Task.isCancelled, let self, self.targetIdentity == identity else { return }
            self.resolveTask = nil
            // Review r1 (B P2-1): the legacy decode when it made the deadline, else the same picture
            // at card size (`backdropStandIn`), probe token `small` (append-only vocabulary).
            let usedStandIn = wait.backdrop == nil && backdropStandIn != nil
            let backdrop = wait.backdrop ?? backdropStandIn
            // beta.19-rc1 verdict (M5, BUG-138): a `.blank` logo commits as no logo (the text
            // wordmark); a `.dark` one carries its verdict to `HeroLogo`. A fetched logo's verdict
            // is already memoized (above); the wait names the URL it came from, else it is the
            // cached `logoURL` bitmap.
            let inked = Self.inkedLogo(wait.logo, url: wait.logoURL ?? logoURL)
            let logo = inked.logo
            let backdropSource = wait.usedPosterFallback
                ? "poster"
                : (usedStandIn ? "small" : Self.source(cached: cachedBackdrop, resolved: backdrop, empty: "none"))
            self.commit(item: target, backdrop: backdrop, logo: logo, identity: identity,
                        backdropSource: backdropSource,
                        logoSource: logo == nil
                            ? "text" : Self.source(cached: cachedLogo, resolved: logo, empty: "text"),
                        logoOrigin: logo != nil ? planLogoOrigin : .none,
                        logoInk: inked.ink,
                        waitedMs: Int(Date().timeIntervalSince(started) * 1000),
                        // beta.19-rc1 verdict (I1): the poster stand-in is not the backdrop's
                        // picture, so it records no backdrop URL and is never sharpened.
                        backdropURL: wait.usedPosterFallback ? nil : backdropURL,
                        logoURL: wait.logoURL ?? logoURL,
                        // Review r2 (P3-2): the late legacy decode may replace a `small` stand-in.
                        backdropIsStandIn: usedStandIn)
            // 2026-09-08 finding: a backdrop that lands during the deadline hand-off ITSELF — after
            // `deadlineElapsed()` above already finished the wait, but before this task's `commit`
            // just above runs — is lost by both existing paths. `resolveBackdrop`'s own `!finished`
            // guard drops it (see `wait.lateBackdrop` below, which is exactly this image, retained
            // for this one read). And the fetch closure's `adoptLateBackdrop` call is rejected too:
            // `resolveTask` was still non-nil at that moment, since clearing it is `self.resolveTask
            // = nil` above, a few lines into THIS task. By the time execution reaches here,
            // `resolveTask` is nil, `presented` already carries this identity (the `commit` just
            // above set it), and `presented`'s backdrop is nil (that commit had nothing to paint) —
            // every `shouldAdoptLateBackdrop` guard now passes. The fetch closure's own
            // `adoptLateBackdrop` call stays for the ordinary later-arrival case (the ordering above
            // is a hand-off race, not the common case); a second call here is harmless because
            // `presentedBackdrop == nil` fails after the first adoption commits one.
            // beta.19-rc1 verdict (review r2, P3-2): the same race when the commit painted the
            // card-size stand-in instead of nothing (the second call is just as harmless: the first
            // adoption clears `presentedBackdropIsStandIn`).
            if backdrop == nil || usedStandIn, let late = wait.lateBackdrop {
                self.adoptLateBackdrop(late, identity: identity, startedAt: started, url: backdropURL)
            }
        }
    }

    /// `cached` / `fetched` / the caller's empty token, for the probe line. The backdrop's fourth
    /// token, `poster`, is decided by the wait rather than here: it is the one value a bitmap
    /// alone cannot identify.
    private static func source(cached: UIImage?, resolved: UIImage?, empty: String) -> String {
        if cached != nil { return "cached" }
        return resolved != nil ? "fetched" : empty
    }

    /// beta.19-rc1 verdict (M5, BUG-138): the logo a commit may paint, and how. `.blank` (nothing
    /// readable: transparent, a placeholder, an opaque dark box) drops the bitmap so `HeroLogo`
    /// draws the title text; `.dark` keeps it, marked for the white-silhouette treatment; anything
    /// else is drawn as it always was. Reads the per-URL memo, which the fetch tasks fill off the
    /// main actor; a cache-warm logo with no memo yet (prefetched by a row) is sampled here,
    /// synchronously, and memoized — a 32×32 draw, its cost logged once per process.
    private static func inkedLogo(_ logo: UIImage?, url: URL?) -> (logo: UIImage?, ink: HeroLogoInk) {
        guard let logo else { return (nil, .legible) }
        let key = url?.absoluteString
        let ink: HeroLogoInk
        if let key, let memo = HeroLogoInk.cachedVerdict(for: key) {
            ink = memo
        } else {
            let start = ProcessInfo.processInfo.systemUptime
            ink = HeroLogoInk.verdict(of: logo)
            if let key { HeroLogoInk.remember(ink, for: key) }
            if !loggedLogoInkSyncSample {
                loggedLogoInkSyncSample = true
                let line = String(format: "logoInk sync-sample ms=%.2f",
                                  (ProcessInfo.processInfo.systemUptime - start) * 1000)
                if HomeHeroProbe.enabled { HomeHeroProbe.log(line) } else { NSLog("[HomeHero] %@", line) }
            }
        }
        return (ink == .blank ? nil : logo, ink)
    }

    /// One-shot latch for `inkedLogo`'s cost line.
    private static var loggedLogoInkSyncSample = false

    /// THE commit. One assignment, one animation, every field of the hero at once.
    ///
    /// BUG-95 (beta.18) note on the `withAnimation` below, because the fix plan for that bug
    /// explicitly asked this line to lose it and this comment is the record of why it did not.
    /// The bug itself was that this transaction reached `HeroCrossfadeImage`'s ZStack while it had
    /// NO children (no bitmap resolved yet) and so no size of its own; SwiftUI then interpolated
    /// that size from collapsed to full the moment the first bitmap landed, so a fixed
    /// `.scaledToFill()` computed its crop against a box that was still growing — the tester's
    /// "blank panel → logo → heavily-cropped mosaic → settles ~35 frames later" (full mechanism on
    /// `HeroCrossfadeImage.body`, which fixes it: `Color.clear` makes that container's size
    /// INVARIANT, so there is no longer any geometry here for a transaction to reach).
    ///
    /// beta.19-rc1 verdict (M5, BUG-138): this transaction NO LONGER drives the hero text. It used
    /// to: `HomeHeroForeground` keyed its info block on `.id(presentation.identity)` +
    /// `.transition(.opacity)` off this publish, so for 0.3 s the old and the new title, meta line
    /// and synopsis cross-dissolved in one slot (Steven's "doubled title"). The text now reads
    /// `HeroTextLayer`'s `TextSwapModel` (fade the old text out, swap while invisible, fade the new
    /// one in), its block is `.transition(.identity)`, and every write of that model runs in an
    /// animation-free transaction with only its own scoped opacity curve, so nothing here reaches
    /// it. The `withAnimation` itself stays: this batch leaves the artwork path exactly as it was
    /// (`HeroCrossfadeImage` cross-fades the bitmaps in place and its two layers opt out of this
    /// transaction, `.transaction { $0.animation = nil }`), and the hero region's own
    /// insert/remove at the nil boundary keeps its fade. Dropping it is a separate, device-checked
    /// change.
    ///
    /// beta.19-rc1 verdict (I1, BUG-134): `backdropURL` / `logoURL` are where the two bitmaps were
    /// decoded from (nil for the poster stand-in and for the text wordmark), kept for the post-commit
    /// sharpen, which every commit arms (`scheduleSharpen`).
    ///
    /// beta.19-rc1 verdict (review r2, P3-2): `backdropIsStandIn` marks a `backdrop=small` commit (see
    /// `presentedBackdropIsStandIn`).
    private func commit(item: MetaPreview, backdrop: UIImage?, logo: UIImage?, identity: String,
                        backdropSource: String, logoSource: String, logoOrigin: HeroLogoSource,
                        logoInk: HeroLogoInk, waitedMs: Int, backdropURL: URL?, logoURL: URL?,
                        backdropIsStandIn: Bool = false) {
        logPresent(identity: identity, backdrop: backdropSource, logo: logoSource,
                   logoOrigin: logoOrigin, logoInk: logoInk, waitedMs: waitedMs, same: false)
        let next = HeroPresentation(item: item, backdrop: backdrop, logo: logo, identity: identity,
                                    logoInk: logoInk)
        guard next != presented else { return }
        presentedBackdropURL = backdrop != nil ? backdropURL : nil
        presentedBackdropIsStandIn = backdrop != nil && backdropIsStandIn
        presentedLogoURL = logo != nil ? logoURL : nil
        // Review r3 (P3 #1): the backdrop cross-fade this commit starts runs from here.
        presentedCommitSerial &+= 1
        presentedCommittedAt = ProcessInfo.processInfo.systemUptime
        // FEAT-42: set in the SAME transaction as `presented` — see `presentedLogoSource`'s doc
        // comment.
        withAnimation(.easeInOut(duration: 0.3)) {
            presented = next
            presentedLogoSource = logoOrigin
        }
        scheduleSharpen(identity: identity)
    }

    // MARK: beta.19-rc1 verdict (I1, BUG-134): post-commit sharpen

    /// `HomeView` reports the hero form (`heroSharpenForm`). A change under a hero that stays re-arms
    /// its sharpen: a classic hero needs a larger bitmap than a Nuvio-style one, and the plan skips a
    /// bitmap that is already large enough.
    func setSharpenForm(_ form: HeroSharpen.Form) {
        guard form != sharpenForm else { return }
        sharpenForm = form
        guard let identity = presented?.identity, targetIdentity == identity, resolveTask == nil else { return }
        scheduleSharpen(identity: identity)
    }

    /// Arms the sharpen for the hero just committed: after `HeroSharpen.dwell` on the same identity,
    /// `runSharpen`. Replaces any sharpen already armed or running.
    ///
    /// Timeline (warm cache): the commit lands at t0 (the art cross-fades t0 → t0 + 0.3, the text
    /// swaps by t0 + 0.24). From t0 + 0.6 the sharpen waits for the rows to have rested
    /// `HeroSharpen.fetchRestHold` (beta.19-rc1 verdict, review r1, A P2); then the plan runs and,
    /// when the bitmap on screen is short of what the form draws, the sharper file is fetched with no
    /// deadline; when it lands (the backdrop and the logo both, or `fetchCeiling`) the sharpen waits
    /// for the next at-rest reading, and only then does `adoptSharpened` cross-fade the backdrop to
    /// it over 0.3 s and swap the logo bitmap in place. A `present` for another identity at any point
    /// before then cancels it, so a row walk (rows never at rest between presses) starts no fetch and
    /// no adoption can land inside a slide.
    private func scheduleSharpen(identity: String) {
        cancelSharpen()
        let generation = sharpenGeneration
        sharpenTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(HeroSharpen.dwell * 1_000_000_000))
            guard !Task.isCancelled, let self, self.sharpenGeneration == generation else { return }
            await self.runSharpen(identity: identity, generation: generation)
        }
    }

    private func cancelSharpen() {
        sharpenTask?.cancel()
        sharpenTask = nil
        sharpenGeneration &+= 1
    }

    /// Plans from the bitmaps on screen (`HeroSharpen.plan` / `logoPlan`), fetches the backdrop and
    /// the logo concurrently with `.normal` admission, no deadline and no request timeout (the hero is
    /// already painted, so nothing waits on these and the six-slot gate's `.head` front stays for the
    /// fetches that do), waits at most `HeroSharpen.fetchCeiling` for both, then hands whatever
    /// landed to `adoptSharpened`. A sharpened file stays in `ArtworkStore`, so presenting this hero
    /// again in the session commits the sharp bitmap straight from the cache (the `.legacy` lookup
    /// returns the largest adequate decode of any rendition) and the next plan finds nothing to do.
    ///
    /// beta.19-rc1 verdict (review r1, A P2): both ends are held off row motion. The fetch starts only
    /// once the rows have rested `HeroSharpen.fetchRestHold`, so a held hero mid-walk queues no 1–5 MB
    /// `original` on the six-slot gate the row posters share (`ArtworkStore` work cannot be
    /// cancelled once it starts, so not starting it is the only cancellation there is); and the
    /// adoption waits for an at-rest reading, so its body re-evaluation and full-screen cross-fade
    /// never land inside a slide, a settle or a morph scroll.
    private func runSharpen(identity: String, generation: Int) async {
        defer { if sharpenGeneration == generation { sharpenTask = nil } }
        guard let fetchRest = await waitForRowsAtRest(hold: HeroSharpen.fetchRestHold, generation: generation) else {
            return
        }
        // TODO(I1): skip under a "Reduce Data" setting once tvOS has one (there is none today).
        guard let presented, presented.identity == identity, targetIdentity == identity,
              resolveTask == nil else { return }
        let scale = ArtworkDecodeMath.screenScale
        let form = sharpenForm
        let backdropSize = HeroSharpen.pixelSize(of: presented.backdrop)
        let logoSize = HeroSharpen.pixelSize(of: presented.logo)
        let backdropFrom = presented.backdrop != nil ? presentedBackdropURL : nil
        let logoFrom = presented.logo != nil ? presentedLogoURL : nil
        let sourceSize = backdropFrom.flatMap { ArtworkStore.recordedSourceSize($0) }
        let backdropPlan = backdropFrom.flatMap {
            HeroSharpen.plan(backdropURL: $0, presentedPixelSize: backdropSize, form: form,
                             scale: scale, sourceSize: sourceSize)
        }
        let logoPlan = logoFrom.flatMap {
            HeroSharpen.logoPlan(logoURL: $0, presentedPixelSize: logoSize, scale: scale)
        }
        guard backdropPlan != nil || logoPlan != nil else {
            HeroSharpen.log("none item=\(identity) form=\(form.rawValue) bd=\(HeroSharpen.sizeToken(backdropSize)) "
                            + "logo=\(HeroSharpen.sizeToken(logoSize))")
            return
        }
        // Review r1 (A P2): ` rest=<rest|ceiling> restMs=<n>` appended LAST (append-only vocabulary):
        // how the fetch's rest wait ended and how long it took.
        HeroSharpen.log("start item=\(identity) form=\(form.rawValue) "
                        + "bd=\(HeroSharpen.urlToken(from: backdropFrom, plan: backdropPlan)) "
                        + "req=\(HeroSharpen.requestBucket(backdropPlan, aspect: sourceSize ?? backdropSize)) "
                        + "logo=\(HeroSharpen.urlToken(from: logoFrom, plan: logoPlan)) "
                        + "lreq=\(HeroSharpen.requestBucket(logoPlan, aspect: logoSize))"
                        + HeroSharpen.restToken(fetchRest))
        let started = Date()
        // The same first-terminal-event wait `present` resolves with, here bounded by the ceiling
        // instead of the swap deadline, and with no poster stand-in.
        let wait = HeroPresentArtWait(backdrop: nil, logo: nil,
                                      needsBackdrop: backdropPlan != nil, needsLogo: logoPlan != nil)
        if let backdropPlan {
            Task { @MainActor in
                let image = try? await ArtworkStore.fetch(backdropPlan.url, decode: backdropPlan.request)
                wait.resolveBackdrop(image)
            }
        }
        if let logoPlan {
            Task { @MainActor in
                let image = try? await ArtworkStore.fetch(logoPlan.url, decode: logoPlan.request)
                wait.resolveLogo(image, url: logoPlan.url)
            }
        }
        let ceiling = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(HeroSharpen.fetchCeiling * 1_000_000_000))
            guard !Task.isCancelled else { return }
            wait.deadlineElapsed()
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                wait.attach(continuation)
            }
        } onCancel: {
            Task { @MainActor in wait.cancelWait() }
        }
        ceiling.cancel()
        guard !Task.isCancelled, sharpenGeneration == generation else { return }
        // Review r1 (A P2): the bitmaps are decoded; the adoption lands at the next at-rest reading
        // (a press since then moved the identity and cancelled this sharpen).
        guard let adoptRest = await waitForRowsAtRest(hold: HeroSharpen.adoptRestHold, generation: generation) else {
            return
        }
        adoptSharpened(backdrop: wait.backdrop, logo: wait.logo, identity: identity,
                       backdropURL: backdropPlan?.url, logoURL: logoPlan?.url,
                       timedOut: wait.hitDeadline, startedAt: started, rest: adoptRest)
    }

    /// beta.19-rc1 verdict (review r1, A P2): polls `restSource` every `HeroSharpen.restPoll` until
    /// the rows have been at rest for `hold`, or, past `HeroSharpen.restCeiling`, still for `hold`
    /// with only a settle decision outstanding (`HeroSharpen.restStep` decides; real motion never
    /// passes the ceiling). Returns how the wait ended (`rest` / `ceiling`) and how long
    /// it took, or nil when the sharpen was cancelled or superseded meanwhile (its generation moved).
    /// A timestamp read and a few comparisons per poll, on the main actor; no view state is written.
    private func waitForRowsAtRest(hold: TimeInterval, generation: Int) async -> HeroSharpen.RestOutcome? {
        await waitForRowsAtRest(hold: hold, while: { self.sharpenGeneration == generation })
    }

    /// The rest wait itself. `isCurrent` is re-read before every poll; the wait answers nil the first
    /// time it is false (the hero moved on). beta.19-rc1 verdict (review r2, P3-2): factored out of
    /// the generation form above so the late stand-in replacement (`adoptLateBackdrop`) waits on the
    /// same signal, guarded by its own condition.
    private func waitForRowsAtRest(hold: TimeInterval, while isCurrent: () -> Bool) async -> HeroSharpen.RestOutcome? {
        let started = ProcessInfo.processInfo.systemUptime
        var restBegan: TimeInterval?
        var quietBegan: TimeInterval?
        while true {
            guard !Task.isCancelled, isCurrent() else { return nil }
            let now = ProcessInfo.processInfo.systemUptime
            if restSource.isAtRest() {
                if restBegan == nil { restBegan = now }
            } else {
                restBegan = nil
            }
            if restSource.rowsQuiet {
                if quietBegan == nil { quietBegan = now }
            } else {
                quietBegan = nil
            }
            switch HeroSharpen.restStep(restAge: restBegan.map { now - $0 }, quietAge: quietBegan.map { now - $0 },
                                        hold: hold, waited: now - started) {
            case .go(let via):
                return HeroSharpen.RestOutcome(via: via, waitedMs: Int(((now - started) * 1000).rounded()))
            case .wait(let seconds):
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    /// Adopts a sharpened backdrop and/or logo onto the hero on screen: a same-identity update of
    /// `presented`, built from the LIVE presentation's item (a gap-fill that landed during the fetch
    /// is kept, as in `adoptLateBackdrop`) and its live `logoInk` (the same picture at a higher
    /// resolution has the same ink; spec P-A §9.2 item 2). `presentedLogoSource` is unchanged: the
    /// logo still comes from the same place.
    ///
    /// On screen: `HeroCrossfadeImage` cross-fades the backdrop in place (0.3 s, two versions of one
    /// picture, same aspect, same crop); `HeroTextLayer`'s `TextSwapModel` sees the same identity and
    /// takes the update as a silent gap-fill, so the title, meta line and synopsis do not move and the
    /// logo bitmap is replaced in the same slot at the same geometry.
    ///
    /// Not routed through `commit`: that logs a `present` line, and the probe oracles read a second
    /// `present` for one item with nothing between as a double paint (test62). The sharpen logs its
    /// own `sharpen adopt` line, and `HeroCrossfadeImage` logs its cross-fade as `sharpen paint`.
    ///
    /// beta.19-rc1 verdict (review r1, A P2): `rest` is how the adoption's rest wait ended; it rides
    /// the `adopt`/`skip` lines LAST as ` rest=<rest|ceiling> restMs=<n>`, and `ms=` (fetch start →
    /// now) now includes that wait.
    private func adoptSharpened(backdrop: UIImage?, logo: UIImage?, identity: String,
                                backdropURL: URL?, logoURL: URL?, timedOut: Bool, startedAt: Date,
                                rest: HeroSharpen.RestOutcome) {
        let waitedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        guard HeroSharpen.shouldAdoptSharpened(targetIdentity: targetIdentity,
                                               presentedIdentity: presented?.identity,
                                               resolveTaskIsNil: resolveTask == nil,
                                               identity: identity),
              let presented else {
            HeroSharpen.log("skip item=\(identity) reason=superseded ms=\(waitedMs)" + HeroSharpen.restToken(rest))
            return
        }
        let sharpBackdrop = HeroSharpen.adoptable(backdrop, over: presented.backdrop)
        let sharpLogo = HeroSharpen.adoptable(logo, over: presented.logo)
        guard sharpBackdrop != nil || sharpLogo != nil else {
            HeroSharpen.log("skip item=\(identity) reason=\(timedOut ? "timeout" : "nogain") "
                            + "bd=\(HeroSharpen.sizeToken(HeroSharpen.pixelSize(of: backdrop))) ms=\(waitedMs)"
                            + HeroSharpen.restToken(rest))
            return
        }
        let next = HeroPresentation(item: presented.item,
                                    backdrop: sharpBackdrop ?? presented.backdrop,
                                    logo: sharpLogo ?? presented.logo,
                                    identity: identity,
                                    logoInk: presented.logoInk)
        if let sharpBackdrop {
            HeroSharpen.noteAdopted(sharpBackdrop)
            presentedBackdropURL = backdropURL
            // Review r2 (P3-2): the stand-in is gone; a late legacy decode must not replace this.
            presentedBackdropIsStandIn = false
        }
        if sharpLogo != nil { presentedLogoURL = logoURL }
        HeroSharpen.log("adopt item=\(identity) bd=\(HeroSharpen.adoptToken(from: presented.backdrop, to: sharpBackdrop)) "
                        + "logo=\(HeroSharpen.adoptToken(from: presented.logo, to: sharpLogo)) ms=\(waitedMs)"
                        + HeroSharpen.restToken(rest))
        withAnimation(.easeInOut(duration: 0.3)) {
            self.presented = next
        }
    }

    /// 2026-09-08 finding (simulator rig, the tester's real collections): when Home focus lands on
    /// a collection folder, `present`'s backdrop fetch routinely misses `folderDeadline` (1.5 s) on
    /// a cold cache — the probe logs `present item=nuvio.folder:… backdrop=none logo=text
    /// waited=1509` — and `commit` paints the hero with NO backdrop. Unlike a title hero, which
    /// falls back to its poster (`posterFallbackURL` above), a folder has no stand-in —
    /// `folderHeroPreview` passes `poster: nil` on purpose, so a square cover never gets scaled
    /// into the 16:9 hero and then replaced (Wave H hole H2). So the deadline miss is a BLANK
    /// screen, not a poster, and it used to stay blank until focus moved to a different folder
    /// whose art happened to already be cached. The fetch itself is never cancelled by the
    /// deadline (round 3's design: the image still lands in `ArtworkStore` for next time) — this
    /// method is where that late image gets painted onto the CURRENT hero instead of being wasted
    /// on a folder the viewer has since left.
    ///
    /// The safety argument is entirely `presentedBackdrop == nil`, mirrored in
    /// `shouldAdoptLateBackdrop` below so it can be pinned by a unit test with no `ArtworkStore`
    /// and no live view (`HeroArtResolverLateBackdropTests`). A hero that already has ANY bitmap on
    /// screen — a title's primary, a title's poster stand-in, or a folder's own earlier-landed
    /// backdrop — must never have that bitmap swapped out from under the viewer; that is exactly
    /// the late-arrival repaint BUG-90 forbids and the "double commit" BUG-42 exists to prevent.
    /// `presented?.backdrop == nil` is true in exactly the one case this method exists for: the
    /// deadline already committed with nothing to show, so painting something can only help. The
    /// other guards (`targetIdentity`, `presented?.identity`, `resolveTask == nil`) only rule out a
    /// newer `present` having superseded this one in the meantime.
    ///
    /// Commits with `presented.item` — the LIVE presentation's item — never the item `present`
    /// captured when this resolve started. A same-identity payload refresh (the allowed silent
    /// gap-fill in `present`'s identity-match branch: a synopsis or genre list landing from TMDB
    /// after the commit) can land in the gap between this resolve starting and this method running.
    /// Identity does not change on a gap-fill, so `presented` is updated directly without going
    /// through `commit` — which means `presented.item` is always at least as fresh as the item this
    /// resolve started with. Committing the stale captured item instead would rewind that text, and
    /// because the identity is unchanged, `commit`'s `same=0` line would make the rollback invisible
    /// to the photo oracle: nothing would look wrong that flags this class of regression.
    ///
    /// beta.19-rc1 verdict (review r2, P3-2): the one bitmap a late arrival may replace is the
    /// card-size stand-in (`backdrop=small`, `presentedBackdropIsStandIn`): the SAME picture at a
    /// card's size, committed only because this very legacy re-decode missed the deadline (the
    /// six-slot gate busy, the URLCache re-decode landing 50 ms late). It used to be dropped here, so
    /// the hero stayed on a 768 px card bitmap (3.3× upscaled on the Nuvio form, 5× on classic)
    /// through the sharpen's dwell, its rest hold and a TMDB `original` download, while a 1280–1920 px
    /// decode of the same picture sat in memory. Now it replaces the stand-in, but only with a
    /// strictly larger bitmap (`HeroSharpen.adoptable`), only while the stand-in is still on screen
    /// for this identity, and only at the next at-rest reading (the sharpen's own rest wait,
    /// `HeroSharpen.adoptRestHold`), so its full-screen cross-fade never lands inside a slide (review
    /// r1, A P2). Review r3 (P3 #1): that rest wait starts only once the stand-in commit's own
    /// cross-fade is over (`lateStandInFadeWait`), so the previous title's backdrop always finishes
    /// fading out. It is a same-identity update: `HeroTextLayer` takes it as a silent gap-fill (no text
    /// fade), the logo and its ink verdict are carried, `HeroCrossfadeImage` cross-fades two versions
    /// of one picture and logs it as `sharpen paint` (`HeroSharpen.noteAdopted`), never
    /// `paint … same=1`, and the probe reads `present … backdrop=late`, the one same-item re-present
    /// test62 allows. The poster stand-in (a different picture) is still never replaced.
    private func adoptLateBackdrop(_ image: UIImage, identity: String, startedAt: Date, url: URL?) {
        guard HeroArtResolver.shouldAdoptLateBackdrop(
            targetIdentity: targetIdentity, presentedIdentity: presented?.identity,
            presentedBackdrop: presented?.backdrop, presentedIsSmallStandIn: presentedBackdropIsStandIn,
            resolveTaskIsNil: resolveTask == nil, identity: identity
        ), let presented else { return }
        guard presented.backdrop != nil else {
            commitLateBackdrop(image, over: presented, identity: identity, startedAt: startedAt, url: url)
            return
        }
        // Review r2 (P3-2): over the `small` stand-in. Larger only, and at rest.
        guard HeroSharpen.adoptable(image, over: presented.backdrop) != nil else { return }
        // beta.19-rc1 verdict (review r3, P3 #1): and never inside the stand-in commit's own
        // cross-fade. The rest wait alone does not hold it off: the rows read at rest right after a
        // Right onto a card already in view (nothing scrolls, so nothing stamps), on classic Home,
        // and on a pinned step that arms no settle. The legacy decode landing 50 ms after the
        // commit then started `HeroCrossfadeImage`'s next swap with the previous title's backdrop
        // still ~90 % opaque, and `crossfade(to:)` drops that outgoing bitmap in one frame. So the
        // replacement first sleeps out the rest of that commit's span (`lateStandInFadeWait`), and
        // replaces only the stand-in of THIS commit (`commitSerial`): a newer commit restarts its
        // own fade, and its own resolve makes its own call here.
        let commitSerial = presentedCommitSerial
        let fadeWait = Self.lateStandInFadeWait(
            sinceCommit: ProcessInfo.processInfo.systemUptime - presentedCommittedAt)
        Task { @MainActor [weak self] in
            if fadeWait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(fadeWait * 1_000_000_000))
            }
            guard let self else { return }
            let standInStillUp = {
                self.presentedBackdropIsStandIn && self.targetIdentity == identity
                    && self.presented?.identity == identity && self.presentedCommitSerial == commitSerial
            }
            guard await self.waitForRowsAtRest(hold: HeroSharpen.adoptRestHold, while: standInStillUp) != nil,
                  HeroArtResolver.shouldAdoptLateBackdrop(
                    targetIdentity: self.targetIdentity, presentedIdentity: self.presented?.identity,
                    presentedBackdrop: self.presented?.backdrop,
                    presentedIsSmallStandIn: self.presentedBackdropIsStandIn,
                    resolveTaskIsNil: self.resolveTask == nil, identity: identity),
                  self.presentedCommitSerial == commitSerial,
                  let live = self.presented,
                  HeroSharpen.adoptable(image, over: live.backdrop) != nil else { return }
            HeroSharpen.noteAdopted(image)
            self.commitLateBackdrop(image, over: live, identity: identity, startedAt: startedAt, url: url)
        }
    }

    /// `adoptLateBackdrop`'s commit: the live presentation with `image` as its backdrop.
    private func commitLateBackdrop(_ image: UIImage, over presented: HeroPresentation, identity: String,
                                    startedAt: Date, url: URL?) {
        // FEAT-42: the logo (if any) is `presented.logo`, unchanged by this backdrop-only
        // adoption — its origin is whatever is already recorded on `presentedLogoSource`, passed
        // straight through rather than recomputed.
        commit(item: presented.item, backdrop: image, logo: presented.logo, identity: identity,
               backdropSource: "late",
               logoSource: presented.logo != nil ? "cached" : "text",
               logoOrigin: presentedLogoSource,
               logoInk: presented.logoInk,   // beta.19-rc1 verdict (M5): carried, never re-sampled
               waitedMs: Int(Date().timeIntervalSince(startedAt) * 1000),
               // beta.19-rc1 verdict (I1): the late image is the resolve's own backdrop URL; the
               // logo's URL is carried like its bitmap.
               backdropURL: url, logoURL: presentedLogoURL)
    }

    /// FEAT-42 repair path: `logoPlan`'s metahub guess (step 4) 404'd for `target`. Kicks a real
    /// `TitleLogoStore` lookup, purely for the item's NEXT presentation (this one already
    /// committed, or is about to, with no logo) — never bundled with the pending/`.url` fetch
    /// itself, which must stay focused on THIS presentation's own budget. A no-op if a lookup for
    /// this item/scope is already resolved or in flight (`TitleLogoStore.lookupIfNeeded`'s own
    /// `results[key] == nil` guard).
    private func repairMetahubMiss(for target: MetaPreview) {
        TitleLogoStore.shared.lookupIfNeeded([target])
    }

    /// Pure predicate behind `adoptLateBackdrop` — see that method's doc comment for the finding
    /// and the full safety argument. Factored out the same way `isVisibleRepaint` was, so the
    /// no-double-commit guard can be pinned by a unit test with no `ArtworkStore` and no live view.
    ///
    /// beta.19-rc1 verdict (review r2, P3-2): `presentedIsSmallStandIn` (default false, every
    /// pre-existing caller) lets the late arrival replace the card-size stand-in of the same picture,
    /// the one bitmap it may replace. A poster stand-in is never marked, so it still blocks.
    nonisolated static func shouldAdoptLateBackdrop(targetIdentity: String?, presentedIdentity: String?,
                                        presentedBackdrop: UIImage?, presentedIsSmallStandIn: Bool = false,
                                        resolveTaskIsNil: Bool, identity: String) -> Bool {
        guard targetIdentity == identity else { return false }
        guard presentedIdentity == identity else { return false }
        guard presentedBackdrop == nil || presentedIsSmallStandIn else { return false }
        guard resolveTaskIsNil else { return false }
        return true
    }

    /// beta.19-rc1 verdict (review r3, P3 #1): how long one commit's backdrop swap occupies
    /// `HeroCrossfadeImage` (`crossfade(to:)`): the 0.3 s fade of the outgoing bitmap, then its
    /// release at 0.4 s. A second swap inside this span would drop that outgoing bitmap mid-fade.
    nonisolated static let commitCrossfadeSpan: TimeInterval = 0.4

    /// beta.19-rc1 verdict (review r3, P3 #1): how long the late replacement of the card-size
    /// stand-in still sleeps before its rest wait, `sinceCommit` seconds after the stand-in's commit:
    /// the rest of `commitCrossfadeSpan`, 0 once it is over. A negative or non-finite reading (no
    /// clock should give one) waits the whole span.
    nonisolated static func lateStandInFadeWait(sinceCommit: TimeInterval) -> TimeInterval {
        guard sinceCommit.isFinite, sinceCommit >= 0 else { return commitCrossfadeSpan }
        return max(0, commitCrossfadeSpan - sinceCommit)
    }

    /// `present item=<type:id> backdrop=<cached|fetched|poster|late|none> logo=<cached|fetched|text>
    /// waited=<ms> same=<0|1> frame=<w>x<h>|none`. `frame=` is BUG-95's append-only diagnostic —
    /// see `logPresent`. `backdrop=poster` is a TITLE hero whose primary backdrop missed or
    /// stalled and whose own poster stood in for it. `backdrop=late` (2026-09-08, append-only
    /// addition to the vocabulary) is `adoptLateBackdrop` painting a backdrop that arrived after
    /// the deadline already committed with none — see that method's doc comment; it can appear for
    /// either a title or a folder hero, though the finding that motivated it was folder-only.
    /// `same=1` is a re-present of the item already on screen that
    /// actually swaps its backdrop or logo bitmap, i.e. the repaint signature. A healthy
    /// cold-launch photo has none. A same-identity present that only refreshes TEXT (the allowed
    /// gap-fill) paints nothing and logs nothing, so it can never be misread as a repaint.
    /// Internal review r1 (P2): does a same-identity `present` change anything the viewer can
    /// READ? This is the whole `same=1` contract, factored out so it can be unit-tested without a
    /// live view (`HeroArtResolverVisibleRepaintTests`).
    ///
    /// The hero's text is exactly three things: the wordmark slot (`HeroLogo`, which renders
    /// `item.name` whenever no logo bitmap resolved), the meta line (`releaseInfo` then up to three
    /// `genres`), and the synopsis (`description_`). Each counts as a repaint only when the value
    /// ALREADY on screen was non-empty and has been replaced - a nil-or-empty value being filled in
    /// is the allowed silent gap-fill.
    ///
    /// Artwork is deliberately NOT a term. The same-identity branch never re-resolves it (a late
    /// wordmark for an already-committed item is dropped by design, BUG-90), so no bitmap can move
    /// here; and when the logo bitmap is nil the visible wordmark is `item.name`, which the name
    /// term already covers. Testing the item's logo URL instead would log `same=1` for a change
    /// that paints nothing - the same vacuousness the bitmap test had, pointed the other way.
    static func isVisibleRepaint(current: MetaPreview, target: MetaPreview) -> Bool {
        func replaced(_ before: String?, _ after: String?) -> Bool {
            guard let before, !before.isEmpty else { return false }
            return before != (after ?? "")
        }
        if replaced(current.name, target.name) { return true }
        if replaced(current.releaseInfo, target.releaseInfo) { return true }
        if replaced(current.description_, target.description_) { return true }
        // Genres are a LIST, and only the first three ever reach the meta line - a fourth genre
        // arriving changes nothing on screen and must not read as a repaint.
        let currentGenres = Array(current.genres.prefix(3))
        if !currentGenres.isEmpty && currentGenres != Array(target.genres.prefix(3)) { return true }
        return false
    }

    /// BUG-95 (beta.18): `frame=<w>x<h>|none` (append-only) is diagnostic —
    /// `HeroCrossfadeImage.lastReportedSize`, the container's own last-measured layout size, read
    /// here because the resolver has no view access of its own. Proof, photographable off the
    /// About pane's ring buffer, that the container's size no longer differs between a hero with
    /// no bitmap yet and one that just painted. `item=` already leads this line rather than
    /// trailing it (unlike `paint`, where Wave H had to insert new fields BEFORE it), so there is
    /// no "everything after item=" ordering to protect here; `frame=` is appended at the very end
    /// regardless, the same append-only discipline. `none` means no `HeroCrossfadeImage` has
    /// completed a layout pass yet this launch — expected on the very first `present` line, before
    /// SwiftUI's first layout.
    ///
    /// FEAT-42: `logoSrc=<addon|tmdb|metahub|none>` is appended AFTER `frame=` — the About pane's
    /// probe blob truncates lines in the middle, not at the end, so a field appended last is the
    /// one most likely to survive a photo of a long line. `none` covers both "no logo bitmap
    /// resolved" and "the plan named a source but its fetch missed" — see `commit`'s callers,
    /// which only ever pass a non-`.none` `logoOrigin` alongside a non-nil `logo` bitmap.
    ///
    /// beta.19-rc1 verdict (M5, BUG-138): `logoInk=<legible|dark|blank>` is appended LAST
    /// (append-only, after `logoSrc=`). `blank` is a logo bitmap that drew nothing readable and was
    /// dropped for the text wordmark (so it reads with `logo=text logoSrc=none`); `dark` a
    /// near-black wordmark drawn as a white silhouette. `legible` also stands for "no logo".
    ///
    /// beta.19-rc1 verdict (review r1, B P2-1): `backdrop=small` (a new VALUE, no new field): a title
    /// whose legacy-size backdrop missed the deadline committed the same picture at a card's size
    /// instead of its poster; the post-commit sharpen upgrades it (`[HomeHero] sharpen`).
    /// beta.19-rc1 verdict (review r2, P3-2): usually sooner, by that legacy decode itself: a
    /// `backdrop=late` line for the same item follows at the next rest (`adoptLateBackdrop`).
    private func logPresent(identity: String, backdrop: String, logo: String,
                            logoOrigin: HeroLogoSource, logoInk: HeroLogoInk, waitedMs: Int, same: Bool) {
        guard HomeHeroProbe.enabled else { return }
        let frame: String = HeroCrossfadeImage.lastReportedSize.map {
            String(format: "%.0fx%.0f", $0.width, $0.height)
        } ?? "none"
        HomeHeroProbe.log(String(format: "present item=%@ backdrop=%@ logo=%@ waited=%d same=%d frame=%@ logoSrc=%@ logoInk=%@",
                                 identity, backdrop, logo, waitedMs, same ? 1 : 0, frame, logoOrigin.rawValue,
                                 logoInk.rawValue))
    }
}

/// Round 3: the wait state of ONE `HeroArtResolver.present(_:isFolder:)` resolve. Sibling of
/// `HeadArtPrewarm` (`HomeHeroCommit.swift`) with the same contract and the same reason to exist:
/// the art budget is enforced by a continuation that the FIRST terminal event resumes, instead of
/// by a task group whose implicit "await every child" defeats the deadline. See the block comment
/// in `present(_:isFolder:)` for why the group form could not honour 400 ms.
///
/// It is a sibling rather than a reuse because `HeadArtPrewarm` only records WHETHER each piece
/// landed. The commit here needs the decoded bitmaps themselves, and it starts from the cached
/// values so a fetch that comes back empty leaves the cached image in place.
///
/// `@MainActor`, like the resolver that owns it, so the fetch tasks, the deadline task and the
/// cancellation handler all mutate it on one actor with no locking; global-actor isolation also
/// makes it implicitly `Sendable` for the capture in `withTaskCancellationHandler`.
///
/// Not `private`: `HeroPresentArtWaitTests` drives this state machine directly, which is the only
/// part of the resolve that can be exercised without a live view and a network.
@MainActor
final class HeroPresentArtWait {
    /// What the commit will paint. Seeded with whatever was already cached, and only ever
    /// overwritten by a fetch that actually produced an image.
    private(set) var backdrop: UIImage?
    private(set) var logo: UIImage?
    /// beta.19-rc1 verdict (M5, BUG-138): the URL a FETCHED `logo` came from (nil while `logo` is
    /// the seeded cached bitmap), so the commit can read that URL's ink memo — the `.pending` path
    /// resolves its URL inside its own task and the resolver would not otherwise know it.
    private(set) var logoURL: URL?
    /// True only when the budget expired first. Not consumed by the resolver today (the probe line
    /// reports `cached`/`fetched`/`none`/`poster` per piece, not a timeout token); kept because it
    /// is the one fact the commit cannot otherwise reconstruct, and it is what the unit test
    /// asserts on.
    private(set) var hitDeadline = false
    /// True when `backdrop` is the item's POSTER standing in for a primary that never landed. Read
    /// by the resolver for the probe line's `backdrop=poster` token; also the only way the commit
    /// can tell a poster apart from a primary that happened to be cached.
    private(set) var usedPosterFallback = false
    /// 2026-09-08 finding: a backdrop that resolves AFTER the wait already finished via
    /// `deadlineElapsed()` used to be dropped outright by `resolveBackdrop`'s `!finished` guard —
    /// exactly the deadline-hand-off image `present`'s resolve task needs one turn later to adopt
    /// via `adoptLateBackdrop`. Retained here, read there, once. Set only when the wait finished
    /// via the deadline (`hitDeadline`): a wait finished by `cancelWait()` belongs to a `present`
    /// call that has already been superseded, and must not retain anything for a resolver that has
    /// moved on to a different target.
    private(set) var lateBackdrop: UIImage?

    private var pendingBackdrop: Bool
    private var pendingLogo: Bool
    /// The poster stand-in for a TITLE hero whose primary backdrop misses. Seeded from the cache
    /// when the poster is already resident (the common case, since `heroBackdropPrefetchURLs`
    /// warms it alongside the primary) and otherwise filled by a fetch running concurrently with
    /// the primary's, inside the same deadline. `nil` for folder heroes, which must never fall
    /// back to their cover, which is the "background pops in then shrinks" bug (Wave H, hole H2).
    private var posterFallback: UIImage?
    /// True while the poster fetch above is still in flight.
    private var pendingPoster: Bool
    /// Set when the primary fetch came back empty. Only then may the poster be painted.
    private var primaryMissed = false
    /// Set when the primary fetch produced an image. A poster landing afterwards is discarded: a
    /// fallback never replaces a primary that made the budget.
    private var primaryLanded = false
    private var continuation: CheckedContinuation<Void, Never>?
    /// Set by the first terminal event. Later arrivals are no-ops, which is exactly the
    /// "a late logo for an already-presented item is dropped" rule, and `attach` resumes at once so
    /// a wait that finished before the continuation existed cannot hang.
    private var finished = false

    init(backdrop: UIImage?, logo: UIImage?, needsBackdrop: Bool, needsLogo: Bool,
         posterFallback: UIImage? = nil, needsPosterFallback: Bool = false) {
        self.backdrop = backdrop
        self.logo = logo
        pendingBackdrop = needsBackdrop
        pendingLogo = needsLogo
        self.posterFallback = posterFallback
        pendingPoster = needsPosterFallback
    }

    func attach(_ continuation: CheckedContinuation<Void, Never>) {
        if finished {
            continuation.resume()
        } else {
            self.continuation = continuation
        }
    }

    func resolveBackdrop(_ image: UIImage?) {
        guard !finished else {
            // The wait is already over. If it ended via the deadline, this image is exactly the
            // late arrival `adoptLateBackdrop` exists for — keep it for that one read. If it ended
            // via `cancelWait()` instead, this `present` call has been superseded; there is nothing
            // left waiting to adopt it, so nothing is retained.
            if hitDeadline, let image { lateBackdrop = image }
            return
        }
        pendingBackdrop = false
        if let image {
            backdrop = image
            primaryLanded = true
            // The primary made it, so there is nothing left to wait for and nothing the poster
            // could add. Whatever the poster fetch is doing still lands in `ArtworkStore` for the
            // card that owns it.
            pendingPoster = false
        } else {
            primaryMissed = true
            applyPosterFallback()
        }
        finishIfSettled()
    }

    /// The poster stand-in resolved (or failed). Only ever consulted once the primary has missed.
    func resolvePosterFallback(_ image: UIImage?) {
        guard !finished, !primaryLanded else { return }
        pendingPoster = false
        if let image { posterFallback = image }
        applyPosterFallback()
        finishIfSettled()
    }

    /// Paints the poster if the primary has already missed, one is available, and nothing is on the
    /// backdrop slot yet. A no-op in every other combination, so it is safe to call from either
    /// arrival order.
    private func applyPosterFallback() {
        guard primaryMissed, backdrop == nil, let posterFallback else { return }
        backdrop = posterFallback
        usedPosterFallback = true
        pendingPoster = false
    }

    func resolveLogo(_ image: UIImage?, url: URL? = nil) {
        guard !finished else { return }
        if let image {
            logo = image
            logoURL = url
        }
        pendingLogo = false
        finishIfSettled()
    }

    /// The budget expired. Whatever has not landed is not part of this commit; it stays in flight
    /// inside `ArtworkStore` so it lands in the cache for this item's next presentation.
    func deadlineElapsed() {
        guard !finished else { return }
        hitDeadline = true
        // A primary that is still in flight when the budget expires is "missing" for this commit
        // exactly as a primary that 404'd is, so the poster stands in rather than the hero going
        // out blank. A primary that lands afterwards is dropped, the same rule a late logo follows.
        if backdrop == nil, let posterFallback {
            backdrop = posterFallback
            usedPosterFallback = true
        }
        finish()
    }

    /// A newer `present` superseded this resolve. Stop waiting; the resolver's identity guard is
    /// what actually blocks the commit, this just stops holding the task open.
    func cancelWait() {
        guard !finished else { return }
        finish()
    }

    private func finishIfSettled() {
        guard !pendingBackdrop, !pendingLogo, !pendingPoster else { return }
        finish()
    }

    private func finish() {
        finished = true
        pendingBackdrop = false
        pendingLogo = false
        pendingPoster = false
        let waiter = continuation
        continuation = nil
        waiter?.resume()
    }
}

/// Horizontal "Continue Watching" row of in-progress titles with a progress bar. Tapping a card opens
/// the stream picker for that exact video (the in-progress episode for series), and playback resumes
/// from the saved position.
struct ContinueWatchingRow: View {
    let entries: [WatchProgressEntry]
    let onSelect: (WatchProgressEntry) -> Void
    let onRemove: (WatchProgressEntry) -> Void
    /// Hold-menu actions (Orivio item 3). The row only renders the menu; Home owns what each does.
    let onGoToDetails: (WatchProgressEntry) -> Void
    let onPlayManually: (WatchProgressEntry) -> Void
    let onStartOver: (WatchProgressEntry) -> Void
    let onMarkWatched: (WatchProgressEntry) -> Void
    /// Parent ids of series with Episode Shuffle on — those cards get a small shuffle badge.
    var shuffleParentIds: Set<String> = []
    /// Custom poster URL pattern for this screen (blank = none), observed by `HomeViewModel`.
    var posterPattern: String = ""
    /// UX-7: reports the focused card's entry (or nil) so Home can drive the hero from it.
    /// Defaulted — nil is a plain no-op. Gating and backdrop prefetch live in the callback
    /// (HomeView.reportRowFocus), not here.
    var onItemFocusChange: ((WatchProgressEntry?) -> Void)? = nil
    /// Focus inside the shelf disables the reorder snap-back (mirrors upstream's
    /// hasUserScrolledContinueWatching guard in their CW scroll stabilization).
    @FocusState private var focusedVideoId: String?
    /// Pinned-hero card reach (UX-7 extension, device rounds 4–5) — see `rowCardTopReach` /
    /// `rowCardBottomReach` in BrowseComponents for the mechanism. 0 (no-op) outside pinned Home.
    @Environment(\.rowCardTopReach) private var cardTopReach
    @Environment(\.rowCardBottomReach) private var cardBottomReach
    /// BUG-87/89 (rc11): see `EnvironmentValues.rowCardLinkFrameFloor`. 0 for every row but Home's
    /// last — and, since rc14 (BUG-122), this row too, which is a SHORT row (203pt landscape cards
    /// against the plan's poster-tall frame).
    @Environment(\.rowCardLinkFrameFloor) private var cardLinkFrameFloor
    @Environment(\.pinnedRowIsLast) private var isLastRow
    @Environment(\.posterStyle) private var posterStyle
    /// Home Stage & Strip (P1 §3.3): the strip's per-row focus memory. nil outside the strip, which
    /// leaves the remount restore below inert (Classic).
    @Environment(\.stripFocusMemory) private var stripFocusMemory
    /// Review r1 (A P2-3): the remount restore's horizontal geometry and target, attached only in
    /// the strip (`StripRowScrollRestore`), so Classic's row is structurally unchanged.
    @State private var hScroll = RowHScrollBox()
    @State private var rowPosition = ScrollPosition()
    /// Steven's fork: see `FocusLeadsRow` (Home sets the flag; Settings → Home Screen owns the switch).
    @Environment(\.homeRowFocusLeads) private var homeRowFocusLeads
    @AppStorage(FocusLeadsRow.defaultsKey) private var focusLeadsEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var focusLeads: Bool { homeRowFocusLeads && focusLeadsEnabled }

    /// Steven's fork (`FocusLeadsRow`): glides the shelf so the focused card sits on the leading
    /// edge, through the row's own horizontal `ScrollPosition` (attached whenever this is on).
    private func alignFocusedCardToLeading(_ id: String?) {
        guard focusLeads, let id, entries.contains(where: { $0.videoId == id }) else { return }
        // Device pass 3: see `CatalogRowView.alignFocusedCardToLeading`.
        let animate = !reduceMotion
        DispatchQueue.main.async {
            guard focusedVideoId == id else { return }
            if animate {
                withAnimation(FocusLeadsRow.animation) { rowPosition.scrollTo(id: id, anchor: .leading) }
            } else {
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) { rowPosition.scrollTo(id: id, anchor: .leading) }
            }
        }
    }

    /// rc14 (BUG-122): see `PinnedRowGeometry.shortRowLayoutCompensation`. The natural label is
    /// what `LandscapeCard` lays out inside the reaches — its fixed height plus the caption when
    /// titles are shown (`titleVisible` defaults to `posterStyle.showTitle` here).
    private var shortRowCompensation: CGFloat {
        let caption = posterStyle.showTitle ? PinnedRowTitle.cardLockupCaptionChrome : 0
        let natural = cardTopReach + Theme.Size.landscapeHeight + caption + cardBottomReach
        return PinnedRowGeometry.shortRowLayoutCompensation(floor: cardLinkFrameFloor,
                                                            naturalLabel: natural,
                                                            isLastRow: isLastRow)
    }

    /// Home Stage & Strip (P1 §3.3, remounted rows): the strip mounts this row only inside its
    /// window (`StripMountWindow`), and a remount loses the horizontal offset, leaving the
    /// remembered card unrealized for `.defaultFocus`. On a (re)mount with a remembered card that is
    /// not the first, scroll it back into view on the next runloop with no animation (the minimal
    /// scroll; nothing moves when it is already visible). Inert outside the strip.
    ///
    /// Review r1 (A P2-3): through this row's own horizontal `ScrollPosition` (`StripRowRestore`, as
    /// `CatalogRowView` does), not `proxy.scrollTo(id)`. The row remounts two pages above the
    /// viewport (Up from row 3, the start of a Menu glide), and an item-anchored proxy scroll can
    /// spill into the strip's vertical scroll view (the M3 note) and knock the page off its
    /// boundary. The geometry sample may not have landed on the first runloop, so one retry follows.
    private func restoreStripMemory() {
        guard let memory = stripFocusMemory, memory.drivesDefaultFocus,
              let id = memory.itemId(for: "continue-watching"),
              id != entries.first?.videoId,
              let index = entries.firstIndex(where: { $0.videoId == id }) else { return }
        DispatchQueue.main.async { applyStripMemoryScroll(index: index, attempt: 0) }
    }

    private func applyStripMemoryScroll(index: Int, attempt: Int) {
        guard let sample = hScroll.sample else {
            if attempt == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    applyStripMemoryScroll(index: index, attempt: 1)
                }
            }
            return
        }
        // Steven's fork: a remounted row puts its remembered card back on the leading edge.
        let offset = focusLeads
            ? FocusLeadsRow.offset(index: index, cardWidth: Theme.Size.landscapeWidth,
                                   gap: Theme.Spacing.rowGap, sample: sample)
            : StripRowRestore.offset(index: index, cardWidth: Theme.Size.landscapeWidth,
                                     gap: Theme.Spacing.rowGap, sample: sample)
        guard let x = offset else { return }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { rowPosition.scrollTo(x: x) }
    }

    var body: some View {
        #if DEBUG
        let _ = HomeBodyCounter.tick("ContinueWatchingRow")
        #endif
        // BUG-146 second trim: `StripGeometry.headingGap` (12) in the strip, `md` (16) elsewhere.
        VStack(alignment: .leading, spacing: StripGeometry.headingGap(inStrip: stripFocusMemory != nil)) {
            // Pinned mode overlays the title inside the shelf's reach band instead (see
            // CatalogRowView's structural comment — out-of-bounds frames froze the focus
            // engine; all paddings must stay positive).
            if cardTopReach == 0 {
                Text("Continue Watching")
                    .font(Theme.Font.sectionTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Spacing.rowGap) {
                        // Keyed by videoId (NOT position): on reorder the cards move instead of
                        // swapping contents under the focused position — upstream's jump bug.
                        ForEach(entries, id: \.videoId) { entry in
                            let custom = customImageURL(entry)
                            Button { onSelect(entry) } label: {
                                LandscapeCard(
                                    title: entry.title,
                                    imageURL: custom ?? imageURL(entry),
                                    fallbackImageURL: custom == nil ? nil : imageURL(entry),
                                    progress: fraction(entry),
                                    overlayLeading: episodeCode(entry)
                                )
                                // Drawn over the artwork's top-right corner: an overlay never
                                // affects the card's layout size or focus behaviour.
                                .overlay(alignment: .topTrailing) {
                                    if shuffleParentIds.contains(entry.parentMetaId) {
                                        Image(systemName: "shuffle")
                                            .font(Theme.Font.caption.weight(.semibold))
                                            .foregroundStyle(Color.white.opacity(0.92))
                                            .padding(.horizontal, Theme.Spacing.xs)
                                            .padding(.vertical, Theme.Spacing.xxs)
                                            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                                            .padding(Theme.Spacing.sm)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .padding(.top, cardTopReach)
                                .padding(.bottom, cardBottomReach)
                                // BUG-87/89 (rc11): transparent floor on the REVEALED frame — 0 for
                                // every row but Home's last. `.top` so the artwork and caption do
                                // not move a point.
                                .frame(minHeight: cardLinkFrameFloor > 0 ? cardLinkFrameFloor : nil,
                                       alignment: .top)
                            }
                            .cardFocusButtonStyle()
                            .posterButtonShape()
                            .focused($focusedVideoId, equals: entry.videoId)
                            .contextMenu {
                                // Orivio item 3: the action list and its order come from
                                // `TitleHoldMenuPolicy` (Mark Episode Watched exists for episodes only).
                                ForEach(TitleHoldMenuPolicy.continueWatchingActions(isEpisode: isEpisode(entry)), id: \.self) { action in
                                    Button(role: action.isDestructive ? .destructive : nil) {
                                        perform(action, on: entry)
                                    } label: {
                                        Label(action.title, systemImage: action.systemImage)
                                    }
                                }
                            }
                            .id(entry.videoId)
                            // BUG-175 (Steven rc7): the focused landscape card lifts over its right
                            // neighbour, which LazyHStack otherwise draws on top (Batch F did the
                            // catalog rows; Classic and Stage both use this row).
                            .zIndex(focusedVideoId == entry.videoId ? 1 : 0)
                        }

                        // Steven's fork (`FocusLeadsRow`): room for the last card to reach the
                        // leading edge. Not focusable.
                        if focusLeads {
                            Color.clear
                                .frame(width: FocusLeadsRow.trailingRoom(expandedCardWidth: Theme.Size.landscapeWidth,
                                                                         gap: Theme.Spacing.rowGap),
                                       height: 1)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .scrollTargetLayout(isEnabled: focusLeads)
                    // Always positive — the reach lives inside the buttons (see CatalogRowView).
                    // BUG-146: 12 on top inside the Stage strip, `lg` on Classic (`StripShelfPadding`).
                    .stripShelfPadding()
                }
                .scrollClipDisabled()
                // Steven's fork (device pass 2): see `CatalogRowView`'s `.scrollDisabled`.
                .modifier(FocusLeadsTargetBehavior(enabled: focusLeads))
                // Review r1 (A P2-3): the strip's restore path; absent outside the strip.
                .modifier(StripRowScrollRestore(enabled: stripFocusMemory != nil || focusLeads,
                                                box: hScroll,
                                                position: $rowPosition))
                // BUG-118: see `RowEdgeEffectStyleModifier`.
                .rowEdgeEffectStyle()
                // BUG-37: rides down to the viewport's clip edge when the device rests short —
                // same one-line treatment as every other pinned row title (see
                // `pinnedRowTitleTracking` in BrowseComponents for the geometry and history).
                //
                // beta.19-rc1 verdict (review r1, B P2-3): AFTER `.rowEdgeEffectStyle()`, as
                // `CatalogRowView` and `CollectionRowView` attach theirs. Attached before it, the
                // title sat inside the Soft mask, and with Soft on (the default then) and its leading ramp
                // reaching 110 pt into the frame, a scrolled row drew "Continue Watching" at 0.61
                // alpha at x = 0. The overlay's frame is the same ScrollView frame either way (the
                // mask never changes layout), so `pinnedRowTitleTracking` sees the same geometry.
                .overlay(alignment: .topLeading) {
                    if cardTopReach > 0 {
                        Text("Continue Watching")
                            .font(Theme.Font.sectionTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .shadow(color: .black.opacity(0.7), radius: 8, y: 2)
                            // Wave 4 item 5: a fixed-height LandscapeCard shelf can state its
                            // artwork height directly — Theme.Size.landscapeHeight is
                            // LandscapeCard's own default `height` param, which this row never
                            // overrides. Cosmetic: only makes the probe's `cap=`/`intr=` readings
                            // truthful for this row (the cap itself stays PROBE-ONLY).
                            // Codex r7 P2: `isFocused` picks which clearance the belt judges this
                            // row by — only a FOCUSED row's cards are raised by the treatment.
                            .pinnedRowTitleTracking(rowKey: "continue-watching",
                                                    artworkHeight: Theme.Size.landscapeHeight,
                                                    isFocused: focusedVideoId != nil)
                            .padding(.top, Theme.Size.heroPinnedRowTitleInset)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: entries.first?.videoId) { _, newFirst in
                    // Content-driven reorder while the user is elsewhere: keep the shelf
                    // anchored to the first card instead of drifting mid-list.
                    guard focusedVideoId == nil, let newFirst else { return }
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    if stripFocusMemory != nil {
                        // Review r2 (P3-2): in the strip, through the row's own horizontal
                        // `ScrollPosition` (the P2-3 reason: an item-anchored proxy scroll can spill
                        // into the strip's vertical scroll). Classic keeps the proxy.
                        withTransaction(tx) { rowPosition.scrollTo(edge: .leading) }
                    } else {
                        withTransaction(tx) { proxy.scrollTo(newFirst, anchor: .leading) }
                    }
                }
                // Home Stage & Strip (P1 §3.3): see `restoreStripMemory`. Inert outside the strip.
                .onAppear { restoreStripMemory() }
            }
        }
        .focusSection()
        // rc14 (BUG-122): cancel the floor's layout growth — the buttons keep their tall frames
        // (that is the point), the row's reported height goes back to its natural one. AFTER
        // `.focusSection()` (review r1 P1: a focusable frame that reaches outside its own section
        // is the shape that froze directional resolution on device — see the structural note on
        // `CatalogRowView`), and before the settle tracker so it measures the natural row.
        .padding(.bottom, -shortRowCompensation)
        // Settle re-reveal (2026-08-30) — one line, same as every other pinned row; see
        // `pinnedRowSettleTracking` in BrowseComponents for the mechanism and its guarantees.
        .pinnedRowSettleTracking(rowKey: "continue-watching", isFocused: focusedVideoId != nil)
        // BUG-112 (Item A)
        .pinnedRowUpFallbackTarget(rowKey: "continue-watching",
                                   firstId: entries.first?.videoId,
                                   focus: $focusedVideoId)
        .onChange(of: focusedVideoId) { _, newId in
            alignFocusedCardToLeading(newId)
            onItemFocusChange?(newId.flatMap { id in entries.first { $0.videoId == id } })
        }
    }

    private func fraction(_ entry: WatchProgressEntry) -> Double? {
        // progressFraction covers percentage-only rows (Simkl/Trakt: durationMs == 0).
        entry.progressFraction > 0 ? Double(entry.progressFraction) : nil
    }

    /// Custom poster URL pattern (Continue Watching screen) for this entry's parent title, computed
    /// with the shared resolver because `WatchProgressEntry` carries no raw-URL fields. Landscape
    /// shape: a pattern without `{shape}` resolves nil here, so those cards render exactly as before.
    private func customImageURL(_ entry: WatchProgressEntry) -> String? {
        guard !posterPattern.isEmpty else { return nil }
        return CustomPosterUrls.shared.resolveWithPattern(
            pattern: posterPattern,
            contentId: entry.parentMetaId,
            contentType: entry.parentMetaType,
            shape: PosterShape.landscape
        )
    }

    private func imageURL(_ entry: WatchProgressEntry) -> String? {
        let bg: String? = entry.background
        if let bg, !bg.isEmpty { return bg }
        let poster: String? = entry.poster
        return poster
    }

    /// `S02E05` artwork badge for series entries (nil for movies — no badge). Same code shape as
    /// the Upcoming row so the two shelves read as one system.
    private func episodeCode(_ entry: WatchProgressEntry) -> String? {
        guard let season = entry.seasonNumber?.intValue, let episode = entry.episodeNumber?.intValue else { return nil }
        return String(format: "S%02dE%02d", season, episode)
    }

    private func isEpisode(_ entry: WatchProgressEntry) -> Bool {
        TitleHoldMenuPolicy.isEpisode(season: entry.seasonNumber?.intValue, episode: entry.episodeNumber?.intValue)
    }

    private func perform(_ action: TitleHoldMenuPolicy.CWAction, on entry: WatchProgressEntry) {
        switch action {
        case .playManually: onPlayManually(entry)
        case .goToDetails: onGoToDetails(entry)
        case .markEpisodeWatched: onMarkWatched(entry)
        case .startOver: onStartOver(entry)
        case .remove: onRemove(entry)
        }
    }
}

/// Identifiable wrapper so a progress entry can drive `.fullScreenCover(item:)` for direct resume.
struct ResumeTarget: Identifiable {
    let entry: WatchProgressEntry
    /// Hold menu "Play Manually": open the picker without auto-selecting a source.
    var forceManual: Bool = false
    /// Hold menu "Start Over": play from 0 instead of the saved position.
    var startFromBeginning: Bool = false
    var id: String { entry.videoId }
}

/// Full-bleed hero backdrop drawn behind the scrolling rows (Detail-style): fills the top region
/// to every edge — no corner radius, no inset — and runs under the floating glass tab bar.
///
/// UX-7: `item` now changes far more often than a carousel page turn — every row-poster focus
/// commit swaps it too — so the crossfade lives inside `HeroCrossfadeImage` and this view is
/// never re-identified. An `.id(item.id)`-driven transition here (the original approach) was
/// exactly the BUG-19 identity-churn class: gating a view's identity on focus produced 700–830ms
/// hangs on device once churn stopped being rare (occasional carousel auto-advance) and became
/// frequent (any row focus hop).
struct HomeHeroBackdrop: View {
    /// Wave H: the committed hero — item AND its already-resolved backdrop bitmap. This view no
    /// longer resolves anything itself; `HeroArtResolver` did that before the commit, so the
    /// artwork and the text in front of it can never belong to different items.
    let presentation: HeroPresentation
    /// The item the presentation carries. Everything below reads this rather than the presentation
    /// so the trailer lifecycle is untouched by Wave H.
    private var item: MetaPreview { presentation.item }
    /// Nuvio-style hero: the artwork becomes a right-anchored panel whose LEFT edge fades
    /// out through a gradient mask, so the info panel sits on pure flat background — none of
    /// the artwork ever renders behind the title/description (Christian's spec, 2026-07-30).
    var nuvioStyle: Bool = false
    /// FEAT-25: run the title's trailer in the backdrop, with no focus required. The gating lives
    /// entirely in `HomeView.heroTrailerAutoplayActive`; false here is byte-for-byte the backdrop
    /// this view has always drawn.
    var autoplaysTrailer: Bool = false
    /// FEAT-25: the SAME dwell → resolve → play state machine the inline catalog card runs
    /// (`InlineTrailerCard`), driven from this view's lifecycle instead of from focus. It brings
    /// the resolution cache, the single-player/single-extraction coordinator, the negative-result
    /// TTLs and the storm breaker with it — nothing about the pipeline is reimplemented here.
    /// Owned by `HomeView` (Codex beta.14 r2) so the carousel tick can poll the attempt phase;
    /// this view still drives its whole lifecycle via `syncTrailer()`.
    @ObservedObject var trailerModel: InlineTrailerCardModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// FEAT-25 (device pass 2026-08-21): the "Home is actually frontmost" gate. Neither a Detail
    /// push nor a tab switch fires `onDisappear` on this view (Home's subtree stays mounted in
    /// both), so the trailer kept playing — audibly — under Detail pages and in Settings.
    @Environment(\.tabBarVisibility) private var tabBarVisibility

    /// Cache/zoom identity of the title on screen — also the change signal the trailer restarts on.
    private var trailerKey: String { TrailerResolutionCache.key(type: item.type, id: item.id) }

    var body: some View {
        backdrop
            .onAppear {
                trailerModel.prefersReducedMotion = reduceMotion
                syncTrailer()
            }
            .onChange(of: autoplaysTrailer) { _, _ in syncTrailer() }
            .onChange(of: trailerKey) { _, _ in syncTrailer() }
            .onChange(of: scenePhase) { _, _ in syncTrailer() }
            .onChange(of: reduceMotion) { _, motion in trailerModel.prefersReducedMotion = motion }
            // FEAT-25: imperative on purpose — while covered, this subtree is hierarchy-resident
            // (the player keeps playing, hence the bug) but may not re-render, so an `onChange`
            // of a computed prop could defer teardown indefinitely. `onReceive` fires regardless.
            // `@Published` emits on willSet, so use the payload, not the property.
            .onReceive(tabBarVisibility.$homeSurfaceCovered) { covered in
                syncTrailer(homeCovered: covered)
            }
            .onDisappear { trailerModel.reset() }
    }

    /// Single funnel for every start/stop reason — hero content change, the setting or one of its
    /// gates flipping, backgrounding and coming back, and Home being covered by a Detail push or
    /// a tab switch (or uncovered again — returning re-arms the same 1s dwell, so the trailer
    /// starts fresh rather than resuming mid-scene). Always tears the current playback down
    /// first (`reset()` releases the player slot and clears the state machine's per-dwell memory),
    /// then re-arms only when there is a reason to. `focusChanged(true:)` is the inline card's own
    /// arming call: it starts the same 1s dwell before anything is resolved or requested.
    private func syncTrailer(homeCovered: Bool? = nil) {
        trailerModel.reset()
        guard autoplaysTrailer, scenePhase == .active,
              !(homeCovered ?? tabBarVisibility.homeSurfaceCovered) else { return }
        trailerModel.focusChanged(true, item: item)
    }

    private var backdrop: some View {
        Group {
            if nuvioStyle {
                heroSurface
                    .frame(width: Theme.Size.heroNuvioArtworkWidth, height: Theme.Size.heroBackdropHeight)
                    .clipped()
                    // The left ~30% of the image dissolves into the background color the rest
                    // of the screen is painted with — a smooth black→artwork transition, no
                    // hard edge and no art under the text.
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black.opacity(0.35), location: 0.16),
                                .init(color: .black, location: 0.32),
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                heroSurface
                    .frame(height: Theme.Size.heroBackdropHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    /// The artwork, with the trailer fading in over it once the state machine has something to
    /// play. The image is UNCONDITIONAL and never re-identified — the player is the only thing
    /// that comes and goes — so a trailer starting or ending can't remount the backdrop and
    /// reintroduce the BUG-19 identity churn this view was rebuilt to avoid. Nothing below is a
    /// placeholder: with no trailer (or the setting off) this is exactly the still backdrop, and
    /// the gap before one resolves is the still backdrop too. Never a spinner.
    private var heroSurface: some View {
        ZStack {
            // Wave H: image-driven, not URL-driven. The whole fetch-and-fallback ladder that used
            // to run here now runs in `HeroArtResolver` BEFORE the hero commits, so this view has
            // one job left — cross-fading one committed bitmap into the next in place, at fixed
            // geometry. The identity is the presentation's own (`"\(type):\(id)"`, unique for a
            // collection folder's synthetic id just as it is for a real title).
            HeroCrossfadeImage(image: presentation.backdrop, identity: presentation.identity)

            if let url = trailerModel.playingURL {
                TrailerHeroPlayer(
                    urlString: url,
                    onFailure: { report in trailerModel.playbackFailed(report) },
                    zoomKey: trailerKey,
                    loops: false,
                    onPlaybackEnded: { trailerModel.playbackFinished() },
                    surfaceTag: "home-hero"
                )
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: trailerModel.playingURL)
    }
}

/// BUG-42 (beta.13): release-safe hero commit probe — `defaults write com.nuvio.media.NuvioTV
/// debug.homeHeroProbe -bool YES`, greppable `[HomeHero]`. Same house pattern as
/// `HomeGeometryProbe`/`TrailerProbe` (deliberately not `#if DEBUG`: the reporter is on a release
/// sideload and the console is the only thing that comes back from a device pass). Two lines:
/// `publish` (from `HomeViewModel`, per hero-bearing state) and `paint` (from
/// `HeroCrossfadeImage.crossfade`, per image swap). A healthy cold launch shows exactly ONE
/// `paint first=1` and NO `publish … headChanged=1`.
enum HomeHeroProbe {
    /// BUG-42 (beta.13.5): the defaults knob stays for local/device-pass use, but the reporter is
    /// on a sideload with no way to `defaults write` — Settings → About now exposes the same knob
    /// as a toggle (`heroDiagnosticsKey`), and the probe lines are mirrored into a small persisted
    /// ring buffer the About pane renders, so a cold-launch capture is one TV photo away.
    nonisolated static let enabled = UserDefaults.standard.bool(forKey: "debug.homeHeroProbe")
    nonisolated static let t0 = Date()
    // nonisolated (Codex round 1): the target defaults to MainActor isolation, and the
    // nonisolated `log` below reads this — pure Date math, safe from any executor.
    nonisolated static var sinceLaunchMs: Int { Int(Date().timeIntervalSince(t0) * 1000) }

    nonisolated static let linesKey = "debug.homeHeroProbe.lines"
    /// H-1A (beta.15): the buffer used to be a flat 24-line ring, front-evicted — so on a busy
    /// cold launch (addons syncing, rows filling in, hero enrichment landing) the LAUNCH HEAD —
    /// exactly the diagnostically valuable part: init, first publish, first paint — was the first
    /// thing evicted once logging ran past 24 lines, and a tester's photo of the About pane showed
    /// only recent noise with the actual double-paint evidence already gone. Now HEAD-PRESERVING:
    /// the first `headMaxLines` lines are captured once and never evicted; only the TAIL rolls,
    /// keeping the most recent `tailMaxLines`. A single elision marker line separates the two once
    /// eviction has actually started (never shown on a launch short enough that nothing was
    /// dropped). Max displayed lines: `headMaxLines` + 1 marker + `tailMaxLines` = 57.
    ///
    /// Wave H raised the head 16 → 24: the launch head now carries a `present` line per hero commit
    /// alongside the `publish`/`paint`/`commit` lines, and the photo contract the device pass reads
    /// (one publish before the first commit, `gate=`, zero `headChanged`/`same=1`) has to fit
    /// inside the frozen head or the evidence rolls out of the pane before the tester photographs
    /// it — the exact failure H-1A introduced the head-preserving buffer for.
    nonisolated static let headMaxLines = 24
    nonisolated static let tailMaxLines = 32
    nonisolated(unsafe) private static var headLines: [String] = []
    nonisolated(unsafe) private static var tailLines: [String] = []
    /// Lines dropped from the tail stream once `tailLines` is full. Stays 0 (no marker rendered)
    /// until eviction genuinely begins.
    nonisolated(unsafe) private static var elidedTailCount = 0
    nonisolated private static let bufferLock = NSLock()

    /// H-1A: monotonic per-process instance counter, guarded by `bufferLock` alongside the ring
    /// buffer it stamps lines for. `HomeViewModel`/`HeroCrossfadeImage` each mint one id at init
    /// and stamp it (`vm=<n>` / `item=<id>`) into every probe line they log, so a photographed
    /// pane can tell two overlapping instances apart instead of interleaving their lines under one
    /// identity — exactly the ambiguity a sync-driven theme remount (see `AppThemeModel`) produces.
    nonisolated(unsafe) private static var nextInstanceId = 0
    nonisolated static func newInstanceId() -> Int {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        nextInstanceId += 1
        return nextInstanceId
    }

    /// NSLogs `line` (the greppable `[HomeHero]` console contract is unchanged) and appends it to
    /// the persisted, head-preserving ring buffer. `headLines`/`tailLines` are fresh statics for
    /// this process, so the very first call of a launch already starts the buffer clean — no
    /// separate "did we reset yet" flag needed (the old flat-ring implementation carried one; it's
    /// moot once the head is captured once and frozen rather than continuously re-derived from
    /// whatever UserDefaults happened to hold from the previous launch).
    nonisolated static func log(_ line: String) {
        NSLog("[HomeHero] %@", line)
        bufferLock.lock()
        defer { bufferLock.unlock() }
        let stamped = "\(sinceLaunchMs)ms \(line)"
        if headLines.count < headMaxLines {
            headLines.append(stamped)
        } else {
            tailLines.append(stamped)
            if tailLines.count > tailMaxLines {
                tailLines.removeFirst()
                elidedTailCount += 1
            }
        }
        var display = headLines
        if elidedTailCount > 0 {
            display.append("\u{2026} \(elidedTailCount) lines elided \u{2026}")
        }
        display.append(contentsOf: tailLines)
        UserDefaults.standard.set(display, forKey: linesKey)
    }
}

/// BUG-95 (beta.18, 2026-09-08): the tester still saw a collection folder's mosaic backdrop
/// "re-crop itself after it appears when the previous image had a different size" even after the
/// `Color.clear`/frame fix of `ecc00536` pinned `HeroCrossfadeImage`'s own container size. Root
/// cause: the leaves were SwiftUI `Image(uiImage:).resizable().scaledToFill()` — SwiftUI computes
/// that layer's aspect-fill geometry as part of its own layout pass, and when `crossfade(to:)`
/// swaps in a bitmap with a different aspect ratio than the outgoing one, the NEW layer's
/// aspect-fill size differs from the OLD layer's, even though the surrounding container's size is
/// now invariant. `.transaction { $0.animation = nil }` on each `Image` only strips animation from
/// that image's OWN modifiers (opacity, etc.) — it cannot stop SwiftUI from interpolating the
/// parent ZStack's placement of a child whose intrinsic-fill geometry just changed, because that
/// interpolation is driven by whatever transaction is active on the PARENT when the child's layout
/// inputs change, not by a transaction override written on the child itself. `ecc00536` fixed the
/// container-collapse jump; this is the layer-crop jump underneath it — the class of bug that fix
/// could not close on hardware (see u/mrStevenx3's rc5 report).
///
/// `HeroBitmapLayer` below replaces both `Image` leaves with a `UIViewRepresentable`-hosted
/// `UIImageView`. UIKit computes the aspect-fill crop at LAYOUT time, directly from the view's
/// `bounds` and the bitmap — there is no SwiftUI layout pass for it to participate in, so a bitmap
/// swap between two different aspect ratios can never be interpolated by any transaction, ambient
/// or explicit: `updateUIView` only ever swaps `image`, never touches `bounds`, and `bounds` itself
/// is driven solely by the (already-invariant, per `ecc00536`) container frame above it.
struct HeroBitmapLayer: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if view.image !== image {
            view.image = image
        }
    }

    /// Take exactly the proposed size — never the bitmap's own intrinsic size — so SwiftUI's
    /// layout never has a reason to size this view off the image at all; the crop is entirely
    /// `UIImageView`'s job once `bounds` lands.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        let resolved = proposal.replacingUnspecifiedDimensions()
        return CGSize(width: resolved.width, height: resolved.height)
    }
}

/// UX-7 flash-free backdrop swapper: unlike `HomeHeroBackdrop`'s old approach, this view is NEVER
/// re-identified as `url` changes — see the BUG-19 note on `HomeHeroBackdrop`. Instead it holds up
/// to two decoded images itself and crossfades between them in place, so churn as fast as a row
/// focus hop never re-triggers view construction, layout, or a load-from-scratch flash.
struct HeroCrossfadeImage: View {
    let url: String?
    /// Second-chance artwork (the item's poster) for when `url` — typically a synthesized metahub
    /// background that may 404 — fails to fetch. Without it an IMDb item with no banner and a dead
    /// metahub entry would keep the previous title's backdrop (or blank on first load) even though
    /// a perfectly good poster exists (Codex review finding).
    let fallbackURL: String?
    /// H-1C (beta.15): the displayed item's stable identity (`"\(type):\(id)"`, constructed at the
    /// single call site in `HomeHeroBackdrop.heroSurface`) — landed in H-1A purely as a probe
    /// stamp (`item=<identity>` on every paint/suppression log line below), and load-bearing from
    /// H-1C onward, where it distinguishes a same-title URL upgrade (TMDB enrichment rewriting
    /// this title's banner) from a genuine title change (see `paintedIdentity`/
    /// `isSameTitleUpgrade` further down).
    let identity: String
    /// Wave H: the already-decoded bitmap to display, for the image-driven call site
    /// (`HomeHeroBackdrop`). nil in URL-driven mode, and nil here in image-driven mode means "this
    /// hero has no artwork" — the same terminal state `fadeToEmpty()` has always produced.
    private let directImage: UIImage?
    /// Which of the two modes this instance is in. A per-call-site CONSTANT (each call site uses
    /// exactly one initializer), so it can safely pick between the two task bodies without ever
    /// re-identifying the view mid-session.
    private let imageDriven: Bool
    @State private var current: UIImage?
    @State private var previous: UIImage?
    /// Drives the outgoing image's fade — animated 1 → 0 on every swap (see `crossfade(to:)`).
    @State private var previousOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Same trick as `HeroLogo.init`: seed `current` synchronously from the memory cache when the
    /// URL is already resident, so a cached backdrop is on screen from this view's very first
    /// frame — no placeholder flash as focus moves across a row.
    init(url: String?, fallbackURL: String? = nil, identity: String) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.identity = identity
        self.directImage = nil
        self.imageDriven = false
        let resolved: URL? = {
            guard let url, !url.isEmpty else { return nil }
            return URL(string: url)
        }()
        let seeded = ArtworkStore.cached(resolved)
        _current = State(initialValue: seeded)
        // Codex wave-3 (P2): when init seeds `current`, the first task's cachedPrimary hit is the
        // SAME UIImage instance, so `crossfade`'s same-image guard returns before recording
        // `paintedIdentity` — a later same-title enrichment would then be misclassified as a title
        // change and repaint the fallback poster. Seed the painted state here alongside the image.
        _paintedIdentity = State(initialValue: seeded != nil ? identity : nil)
        _paintedFallbackURL = State(initialValue: seeded != nil ? fallbackURL : nil)
    }

    /// Wave H: image-driven mode. The caller has already resolved the artwork (see
    /// `HeroArtResolver`), so there is no ladder, no deadline and no fallback here — one bitmap in,
    /// one cross-fade out. The whole point is that a hero's text, logo and backdrop change in the
    /// same transaction; a view that fetched its own image could never guarantee that.
    init(image: UIImage?, identity: String) {
        self.url = nil
        self.fallbackURL = nil
        self.identity = identity
        self.directImage = image
        self.imageDriven = true
        _current = State(initialValue: image)
        _paintedIdentity = State(initialValue: image != nil ? identity : nil)
        _paintedFallbackURL = State(initialValue: nil)
    }

    /// BUG-42 probe: an init-seeded first frame IS the first paint (no `crossfade` runs for it).
    /// Logged from the task, not `init` — SwiftUI may re-run `init` on parent updates while keeping
    /// the `@State`, so only the first task on a view that has painted nothing yet counts.
    @State private var paintCount = 0
    @State private var didLogSeededPaint = false
    /// H-1C (beta.15): which item's identity the currently-committed `current` image belongs to —
    /// set in `crossfade(to:)`, cleared in `fadeToEmpty()`. This view is never re-identified (see
    /// the type doc), so it lives across many different items over time; comparing a task run's
    /// `identity` against this tells a same-title URL upgrade (TMDB enrichment rewriting THIS
    /// title's banner mid-display) apart from a genuine title change.
    @State private var paintedIdentity: String?
    /// Codex wave-3 (P2): the fallback URL that was current when `paintedIdentity` was recorded.
    /// A same-title task run whose fallback URL CHANGED (e.g. a CW→catalog re-adoption swapping
    /// the poster while the primary keeps failing) is not the enrichment-repaint shape H-1C
    /// suppresses — the new poster must still commit through the existing ladder, or a failing
    /// primary pins the stale poster indefinitely.
    @State private var paintedFallbackURL: String?

    /// BUG-95 (beta.18) diagnostic only: the container's LAST rendered size, reported by the
    /// `onGeometryChange` in `body` below. `HeroArtResolver.logPresent` has no view access of its
    /// own, so it reads this static to append `frame=<w>x<h>` to the `present` probe line — proof,
    /// photographable off the About pane's ring buffer, that this view's size no longer differs
    /// between a hero with no bitmap yet and one that just painted (see the fix note on `body`).
    /// `@MainActor` because every reader/writer (this view, `HeroArtResolver`) already runs there;
    /// never read by anything that decides what to draw.
    @MainActor static var lastReportedSize: CGSize?

    var body: some View {
        GeometryReader { geo in
        ZStack {
            // BUG-95 (beta.18): folder backdrop grew into place — a folder hero (`poster: nil`,
            // Wave H's `HeroArtResolver`) commits with `backdrop == nil` on its FIRST paint while
            // the fetch is still in flight, so `current`/`previous` were both nil and this ZStack
            // had NO children at all. A childless ZStack ignores whatever size its parent proposes
            // (`HomeHeroBackdrop`'s fixed `.frame(width: heroNuvioArtworkWidth, height:
            // heroBackdropHeight)`) and collapses to nothing; the first bitmap to land then gave it
            // its first real child and its size jumped from that collapsed point straight to the
            // full frame — and because `HeroArtResolver.commit` committed that bitmap inside a
            // `withAnimation`, SwiftUI interpolated the jump, so `.scaledToFill()` computed its
            // crop against a box that started tiny and grew over ~0.3s: exactly the tester's video
            // (blank panel → logo → heavily-cropped mosaic → settles less cropped ~35 frames
            // later). `Color.clear` is a shape-backed view — it always reports the FULL proposed
            // size whether or not a bitmap child exists alongside it — so this ZStack's own size is
            // now CONSTANT across every state the crossfade passes through, with nothing left for
            // any transaction (ambient or explicit) to animate. `.clipped()` below is
            // belt-and-braces: once the box can no longer collapse, a `.scaledToFill()` image can
            // never overflow it either.
            Color.clear
            // Content-mode/frame/clipping are the caller's job (parity with what
            // CachedAsyncImage used to provide at these call sites). Both leaves below are
            // `HeroBitmapLayer` (UIKit-backed), not SwiftUI `Image` — see that type's doc comment
            // above `HeroCrossfadeImage` for why: a UIImageView computes its aspect-fill crop at
            // UIKit layout time from its own bounds, so no SwiftUI transaction can ever interpolate
            // it when the bitmap's aspect ratio changes mid-crossfade.
            if let current {
                HeroBitmapLayer(image: current)
                    // BUG-95 belt-and-braces: this layer has no animation of its own to protect
                    // (unlike `previous` below), so pin it to the ambient transaction unconditionally
                    // — a future caller-side `withAnimation` (e.g. `HeroArtResolver.commit`, which
                    // still wraps its commit for reasons explained on that function) can no longer
                    // interpolate anything about this image, geometry included, by accident. Belt
                    // and braces only: `HeroBitmapLayer` itself is already immune (see its doc).
                    .transaction { $0.animation = nil }
            }
            // The OUTGOING image sits on top and fades out to reveal the new one beneath —
            // stacked the other way (opaque newcomer above) the animated removal is invisible
            // and every swap reads as a hard cut.
            if let previous {
                HeroBitmapLayer(image: previous)
                    // BUG-95 belt-and-braces, same as `current` above — applied BEFORE `.opacity`
                    // in the chain, so it only pins the image content itself; the `.opacity`
                    // modifier stacked on top of it is deliberately left OUTSIDE this override and
                    // keeps animating exactly as `crossfade(to:)`/`fadeToEmpty()`'s own explicit
                    // `withAnimation` calls below intend.
                    .transaction { $0.animation = nil }
                    .opacity(previousOpacity)
            }
        }
        // BUG-95 gate run (beta.18): `Color.clear` alone was not enough — the simulator layout probe
        // showed a filled container at 1250x1250 for a square bitmap, because `.scaledToFill()`
        // reports a size LARGER than the proposal and a ZStack sizes to the union of its children.
        // The GeometryReader takes exactly the proposed size no matter what its children want,
        // and this frame pins the stack to it; the images are cropped inside, never resized by.
        .frame(width: geo.size.width, height: geo.size.height)
        .clipped()
        // BUG-95 diagnostic only (see `lastReportedSize`'s own doc) — never consulted by any
        // drawing or state-machine decision in this file.
        .onGeometryChange(for: CGSize.self, of: { proxy in
            proxy.size
        }, action: { newSize in
            HeroCrossfadeImage.lastReportedSize = newSize
        })
        // Keyed on BOTH urls: between same-title previews the primary can stay identical while
        // only the fallback poster changes (CW adaptation without a poster → catalog card with
        // one) — keyed on the primary alone, a terminally-failed primary never retried the newly
        // available fallback.
        // Codex wave-3 r2 (P2): `identity` is part of the key — two consecutive items resolving to
        // the SAME url/fallback pair (shared artwork) must still rerun the task, or
        // `paintedIdentity` stays owned by the previous item and a later enrichment of the new
        // item bypasses the same-title fallback suppression.
        .task(id: taskKey) {
            // Wave H: image-driven mode has no ladder to run — commit what the resolver handed us.
            if imageDriven {
                applyDirectImage()
                return
            }
            // BUG-42: is this the hero's very first paint (nothing on screen yet)? Later swaps keep
            // the "show the cached poster now, upgrade later" rule below — it exists so a stalled
            // metahub fetch can't pin the PREVIOUS title's art. On first paint there is no previous
            // art to pin, and the poster→backdrop crossfade IS the "one cover, then another loads
            // over it" the reporter filmed. So on first paint the poster waits for the primary up
            // to `firstPaintFallbackDeadline` before it is allowed to show.
            let firstPaint = current == nil && previous == nil
            // H-1C: the SAME title is already on screen with correct art, and this task run is
            // only here because enrichment (or any other source) rewrote a URL for that same
            // title — the exact shape that produced the "poster paints over already-correct
            // backdrop" bug. Keyed STRICTLY on identity, never on "did the URL change": a genuine
            // title change must still run the full stale-art-protection ladder below unchanged —
            // keying on URL instead would reintroduce the mismatched-art bug that ladder prevents.
            // `current != nil` also rules this out on true first paint (where there is nothing to
            // protect yet), matching `firstPaint`'s own current==nil check.
            let isSameTitleUpgrade = (identity == paintedIdentity) && current != nil
            // Codex wave-3 (P2): fallback suppression additionally requires the fallback URL to be
            // UNCHANGED since the painted state — see `paintedFallbackURL`. The terminal
            // keep-good-art guard at the bottom stays keyed on `isSameTitleUpgrade` alone.
            let suppressFallback = isSameTitleUpgrade && fallbackURL == paintedFallbackURL
            if !firstPaint, paintCount == 0, !didLogSeededPaint, HomeHeroProbe.enabled {
                didLogSeededPaint = true
                // Wave H: `url=`/`same=` for parity with `crossfade`'s line; `same=0` because a
                // seeded first paint has nothing behind it (see the image-driven twin).
                HomeHeroProbe.log(String(format: "paint kind=seededPrimary first=1 sinceLaunch=%dms hadArt=0 url=%@ same=0 item=%@", HomeHeroProbe.sinceLaunchMs, paintURLKind("cachedPrimary"), identity))
            }
            guard let url, !url.isEmpty, let resolvedURL = URL(string: url) else {
                // This title genuinely has no artwork: fade down to the flat background rather
                // than keep presenting the PREVIOUS title's backdrop under the new title's text.
                fadeToEmpty()
                return
            }
            if let hit = ArtworkStore.cached(resolvedURL) {
                crossfade(to: hit, kind: "cachedPrimary", first: firstPaint)
                return
            }
            let resolvedFallback: URL? = {
                guard let fallbackURL, !fallbackURL.isEmpty, fallbackURL != url else { return nil }
                return URL(string: fallbackURL)
            }()
            // Primary is a cache miss, but the fallback poster may already be resident (it's
            // usually the card image on screen): show it NOW as this title's provisional art,
            // then upgrade when the primary lands. Without this, a slow/unreachable metahub
            // fetch pins the PREVIOUS title's backdrop for a whole URLSession timeout while a
            // perfectly good cached poster sits hidden.
            var showedArt = false
            // BUG-42: on first paint the resident poster is held back (see above); it becomes the
            // deadline's fallback instead of the immediate paint.
            var heldFallback: UIImage? = nil
            if let resolvedFallback, let fallbackHit = ArtworkStore.cached(resolvedFallback) {
                if firstPaint {
                    heldFallback = fallbackHit
                } else if suppressFallback {
                    // H-1C: never repaint the poster over this same title's already-correct art —
                    // only `primary`/`cachedPrimary` may commit while an upgrade is in flight.
                    if HomeHeroProbe.enabled {
                        HomeHeroProbe.log(String(format: "paint suppressed kind=sameTitleFallback sinceLaunch=%dms item=%@", HomeHeroProbe.sinceLaunchMs, identity))
                    }
                } else {
                    crossfade(to: fallbackHit, kind: "fallbackCached", first: false)
                    showedArt = true
                }
            }
            // Race BOTH candidates rather than awaiting the primary serially — a stalled primary
            // must not pin stale/blank art for a whole URLSession timeout while a fetchable
            // poster exists. The fallback promotes itself only until the primary lands; a
            // late-arriving primary still upgrades the hero. Old art stays on screen mid-flight
            // (never blank), and `.task(id:)` cancellation stops a slow fetch for a title the
            // user already focused past from landing over the correct, newer image. No
            // `cancelAll()` on the primary's win: `ArtworkStore` coalesces in-flight fetches, so
            // the drained fallback just parks in cache.
            var primaryLanded = false
            // BUG-42: how long a FETCHED poster waits for the real backdrop before it is allowed
            // to paint. First paint: 600 ms from task start — long enough for a warm CDN hit,
            // short enough that a dead metahub entry never leaves the hero blank past the rows
            // (BUG-26 launch timing). Later swaps: 150 ms from the moment the fetched poster
            // ARRIVES (not from task start — on a slow network both fetches outlive a start-anchored
            // window and the flash comes back; Codex gate 8): the two fetches routinely complete
            // 1–4 ms apart (sim log 2026-08-18), and without a grace the poster painted, then the
            // backdrop painted over it a frame later — the reporter's "one cover then another" on
            // every hero move. A CACHED poster on a later swap still paints immediately
            // (stale-art protection).
            let firstPaintDeadline: UInt64 = 600_000_000
            let laterSwapGrace: UInt64 = 150_000_000
            enum Arrival { case primary(UIImage?), fallback(UIImage?), deadline }
            await withTaskGroup(of: Arrival.self) { group in
                group.addTask { .primary(try? await ArtworkStore.fetch(resolvedURL)) }
                if let resolvedFallback {
                    group.addTask { .fallback(try? await ArtworkStore.fetch(resolvedFallback)) }
                }
                if firstPaint {
                    group.addTask {
                        try? await Task.sleep(nanoseconds: firstPaintDeadline)
                        return .deadline
                    }
                }
                var deadlinePassed = false
                var graceArmed = firstPaint
                // BUG-42: once the FIRST paint has been committed with the poster (deadline hit),
                // a late backdrop must not paint over it — that IS the double commit. The item's
                // next visit finds the backdrop cached and paints it once, from the start.
                var firstPaintCommittedWithFallback = false
                for await arrival in group {
                    guard !Task.isCancelled else { return }
                    switch arrival {
                    case let .primary(image):
                        guard let image else { continue }
                        showedArt = true
                        primaryLanded = true
                        if firstPaintCommittedWithFallback {
                            if HomeHeroProbe.enabled {
                                HomeHeroProbe.log(String(format: "paint suppressed kind=primaryAfterFirstPaintFallback sinceLaunch=%dms item=%@", HomeHeroProbe.sinceLaunchMs, identity))
                            }
                            continue
                        }
                        crossfade(to: image, kind: "primary", first: firstPaint)
                    case let .fallback(image):
                        guard let image else { continue }
                        if primaryLanded { continue }
                        if deadlinePassed {
                            if suppressFallback {
                                // H-1C: same suppression as the immediate branch above — the
                                // fetched poster must not repaint over this same title's art.
                                if HomeHeroProbe.enabled {
                                    HomeHeroProbe.log(String(format: "paint suppressed kind=sameTitleFallback sinceLaunch=%dms item=%@", HomeHeroProbe.sinceLaunchMs, identity))
                                }
                            } else {
                                showedArt = true
                                if firstPaint { firstPaintCommittedWithFallback = true }
                                crossfade(to: image, kind: "fallbackFetched", first: firstPaint)
                            }
                        } else {
                            heldFallback = image
                            if !graceArmed {
                                graceArmed = true
                                group.addTask {
                                    try? await Task.sleep(nanoseconds: laterSwapGrace)
                                    return .deadline
                                }
                            }
                        }
                    case .deadline:
                        deadlinePassed = true
                        if !primaryLanded, let held = heldFallback {
                            if suppressFallback {
                                // H-1C: same suppression again — the held poster must not repaint
                                // over this same title's art either.
                                if HomeHeroProbe.enabled {
                                    HomeHeroProbe.log(String(format: "paint suppressed kind=sameTitleFallback sinceLaunch=%dms item=%@", HomeHeroProbe.sinceLaunchMs, identity))
                                }
                            } else {
                                showedArt = true
                                if firstPaint { firstPaintCommittedWithFallback = true }
                                crossfade(to: held, kind: "fallbackHeld", first: firstPaint)
                            }
                        }
                    }
                }
            }
            // Every source failed terminally and nothing provisional made it up: same rule as
            // the no-URL case — stale art under a mismatched title is worse than the flat
            // background.
            guard !Task.isCancelled, !showedArt else { return }
            if isSameTitleUpgrade {
                // H-1C: the SAME title is already on screen with good art — the whole point of
                // suppressing the fallback repaints above is defeated if a failed upgrade then
                // fades that good art to the flat background anyway. Keep it. A genuine title
                // change (isSameTitleUpgrade false) still falls through to fadeToEmpty() below,
                // unchanged.
                if HomeHeroProbe.enabled {
                    HomeHeroProbe.log(String(format: "paint suppressed kind=sameTitleFadeToEmpty sinceLaunch=%dms item=%@", HomeHeroProbe.sinceLaunchMs, identity))
                }
                return
            }
            fadeToEmpty()
        }
        }
    }

    /// The `.task(id:)` key. URL-driven keeps its exact historical spelling (identity + both URLs
    /// — see the comment at the call site). Image-driven keys on the bitmap's own object identity,
    /// which is what actually changes there; `ArtworkStore` vends one decoded instance per URL, so
    /// this is stable across re-renders and changes exactly when the artwork does.
    private var taskKey: String {
        guard imageDriven else { return "\(identity)|\(url ?? "")|\(fallbackURL ?? "")" }
        let stamp = directImage.map { String(UInt(bitPattern: ObjectIdentifier($0).hashValue)) } ?? "nil"
        return "image|\(identity)|\(stamp)"
    }

    /// Wave H: commit the caller-resolved bitmap. Same bookkeeping as the URL ladder's terminal
    /// paints — `crossfade` owns the probe line, the `paintedIdentity` state and the fade — so the
    /// two modes report identically.
    private func applyDirectImage() {
        let firstPaint = current == nil && previous == nil
        if !firstPaint, paintCount == 0, !didLogSeededPaint, HomeHeroProbe.enabled {
            didLogSeededPaint = true
            // `same=0` on purpose: this line is the FIRST paint of this view instance (init seeded
            // it from the presentation), so there is nothing it could be repainting over, even
            // though `paintedIdentity` was seeded alongside it.
            HomeHeroProbe.log(String(format: "paint kind=seededPrimary first=1 sinceLaunch=%dms hadArt=0 url=image same=0 item=%@", HomeHeroProbe.sinceLaunchMs, identity))
        }
        guard let directImage else {
            fadeToEmpty()
            return
        }
        crossfade(to: directImage, kind: "image", first: firstPaint)
    }

    /// Which source the painted bitmap came from, for the probe's `url=` field: `banner` (the
    /// item's own backdrop), `metahub` (the synthesized CDN backdrop), `poster` (the fallback
    /// ladder), `image` (Wave H's resolver-supplied bitmap), `none` (no primary URL at all).
    private func paintURLKind(_ kind: String) -> String {
        if imageDriven { return "image" }
        if kind.hasPrefix("fallback") { return "poster" }
        guard let url, !url.isEmpty else { return "none" }
        return url.contains("images.metahub.space") ? "metahub" : "banner"
    }

    /// The no-artwork terminal state: fade the last image out to the flat background (scrim and
    /// background color remain — the same look a titles-without-art hero always had).
    private func fadeToEmpty() {
        guard current != nil || previous != nil else { return }
        previous = current
        current = nil
        // H-1C: nothing is committed any more — the next task run must not treat whatever item
        // this was as a same-title upgrade just because its identity string is still sitting here.
        paintedIdentity = nil
        paintedFallbackURL = nil
        if reduceMotion || previous == nil {
            previous = nil
            previousOpacity = 0
            return
        }
        previousOpacity = 1
        withAnimation(.easeInOut(duration: 0.3)) {
            previousOpacity = 0
        }
        let fading = previous
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if previous === fading { previous = nil }
        }
    }

    /// `first` = this task started with nothing on screen (the hero's first paint); `hadArt` on the
    /// log line says whether THIS swap replaced an image (a second commit) or filled a blank.
    private func crossfade(to image: UIImage, kind: String = "swap", first: Bool = false) {
        guard image !== current else {
            // Codex wave-3 r2 (P2): the image is already on screen, but THIS commit may belong to
            // a different item that resolved to the same bitmap (identity joined the task key
            // above) — refresh the painted ownership so the suppression state tracks the item
            // actually being displayed, not the one that first loaded the pixels.
            paintedIdentity = identity
            paintedFallbackURL = fallbackURL
            return
        }
        paintCount += 1
        if HomeHeroProbe.enabled, imageDriven, current != nil, identity == paintedIdentity,
           HeroSharpen.isAdopted(image) {
            // beta.19-rc1 verdict (I1, BUG-134): the resolver's post-commit sharpen, a sharper
            // version of the picture already on screen. Logged as its own console line, not as
            // `paint … same=1`: that token is the repaint signature the photo contract forbids
            // (test31, test62), and this is the one same-item repaint that is intended.
            HeroSharpen.log("paint item=\(identity)")
        } else if HomeHeroProbe.enabled {
            // Wave H adds `url=` and `same=`. Both sit BEFORE `item=`, which stays last: the
            // harness parses the item id as "everything after `item=`" (NuvioTVUITests test31), so
            // appending past it would silently make that oracle unparseable. No existing field is
            // renamed or reordered relative to the others.
            // `same=1` means this paint replaced art that was already this same item's — a repaint,
            // which after Wave H should only ever be a genuine re-resolve, never a raw-then-
            // enriched swap.
            let same = identity == paintedIdentity ? 1 : 0
            HomeHeroProbe.log(String(format: "paint kind=%@ first=%d sinceLaunch=%dms hadArt=%d url=%@ same=%d item=%@", kind, first ? 1 : 0, HomeHeroProbe.sinceLaunchMs, current == nil ? 0 : 1, paintURLKind(kind), same, identity))
        }
        previous = current
        current = image
        // H-1C: record which item this committed image belongs to — the same-title-upgrade check
        // near the top of the `.task` compares its `identity` against this on the NEXT task run
        // for this (persistent, never-re-identified) view instance.
        paintedIdentity = identity
        paintedFallbackURL = fallbackURL
        if reduceMotion || previous == nil {
            previous = nil
            previousOpacity = 0
            return
        }
        // Fade the old image (now stacked on top) out over the new one, then release the decoded
        // bitmap once it's invisible — unless another swap has already taken over the slot.
        previousOpacity = 1
        withAnimation(.easeInOut(duration: 0.3)) {
            previousOpacity = 0
        }
        let fading = previous
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if previous === fading { previous = nil }
        }
    }
}

/// Gradient scrims over the hero backdrop: a subtle top darkening under the tab bar, and a bottom
/// fade to the app background so the backdrop blends into the rows region below.
struct HomeHeroScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.55), location: 0.0),
                .init(color: .black.opacity(0.15), location: 0.18),
                .init(color: .clear, location: 0.42),
                .init(color: Theme.Palette.background.opacity(0.85), location: 0.82),
                .init(color: Theme.Palette.background, location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: Theme.Size.heroBackdropHeight)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// One page of the hero carousel — a single focusable target that opens the detail screen.
/// Two layouts (UX-2 hero redesign — the tester's "hero info on the right" meant the ARTWORK
/// on the right, clarified by Christian's reference photos 2026-07-30):
/// - **Classic** (default): logo/meta/synopsis on the lower left — the original layout.
/// - **Nuvio-style** (Settings → Home Screen → "Nuvio-Style Hero"): title/description in a
///   fixed-width panel on the LEFT, raised toward the top of the backdrop, while the artwork
///   reads on the right behind `HomeHeroLeadingScrim` — upstream's modern-home look.
/// Both obey the fixed-slot rule: every slot has a FIXED height/width, so all pages are
/// layout-identical and advancing the carousel can never reflow anything around it. The same rule
/// is what lets a focus takeover (UX-7) — and FEAT-15's focus panel, where every repaint is a
/// takeover — swap titles without moving the rows underneath.
///
/// Accessibility note for the CTA-less form (`showsCTA: false`): the info block keeps its combined
/// accessibility element, but with no focusable descendant tvOS VoiceOver has no way to land on
/// it. That is not a regression — Show Hero off previously rendered no hero region at all — but it
/// does mean the synopsis is sighted-only in that mode. Restoring it needs a focusable element,
/// which is exactly what the mode removes on purpose; a non-competing route (e.g. folding the
/// synopsis into the focused card's accessibility value) would belong in the row components.
struct HomeHeroForeground: View {
    /// Wave H: the committed hero — the item AND its resolved logo bitmap. Taking the logo as a
    /// value instead of letting `HeroLogo` fetch its own is what removes BUG-86 phenomenon B /
    /// BUG-90: the wordmark and the title text can no longer be drawn superimposed, because there
    /// is no longer a moment where one has arrived and the other has not.
    ///
    /// beta.19-rc1 verdict (M5, BUG-138): the presentation whose TEXT is on screen —
    /// `HeroTextLayer`'s `TextSwapModel.shown`, which lags the resolver's committed hero by one
    /// fade-out (0.12 s) so the old and the new text are never drawn together. The CTA follows it.
    let textPresentation: HeroPresentation
    /// The info block's opacity, applied OUTSIDE its `.id` through `textAnimation` (see
    /// `TextSwapModel`'s type doc). 1 and nil for a host with no swap model.
    var textOpacity: Double = 1
    var textAnimation: Animation? = nil
    /// The item the presentation carries; every layout below reads this, unchanged.
    private var item: MetaPreview { textPresentation.item }
    /// Bound to the CTA button — the hero page's ONLY focusable element. The info block above
    /// it is static content (Christian's spec 2026-07-30: the title is no longer selectable;
    /// a "Go to Movie"/"Go to Show" button below the description carries focus instead).
    var heroFocused: FocusState<Bool>.Binding
    /// Compact slots for the PINNED hero (device round 6): smaller logo slot, 2-line synopsis,
    /// tighter vertical padding — the pinned split must leave the rows viewport large enough
    /// for a reach-extended focus frame plus the engine's reveal margin. Classic and full
    /// Nuvio (never pinned) always pass false and are layout-identical to before.
    var compact: Bool = false
    /// FEAT-15: false in the Show-Hero-off focus panel, which has no carousel and therefore no
    /// reason to own a focusable element (see `HomeView.heroCarousel`). The CTA's fixed slot is
    /// not left empty — `synopsisSlotHeight` absorbs it — so the panel's total height, and with it
    /// the pinned rows viewport, is unchanged in both modes.
    var showsCTA: Bool = true
    /// FEAT-15: forces the Nuvio (leading text column / trailing artwork) layout regardless of the
    /// stored `hero_nuvio_style` preference. The focus panel always uses it: it is the layout the
    /// request is modelled on, the pinned geometry has only ever been device-tuned for it, and its
    /// Settings row is hidden while Show Hero is off.
    var forceNuvioLayout: Bool = false
    /// BUG-38 round three: set when `item` is a collection folder's preview — the CTA then opens
    /// the folder page instead of a Detail route for an id no addon can resolve.
    var folderRoute: FolderRoute? = nil
    /// Wave 10: how many points the PINNED hero is yielding to the rows below it, so the focused
    /// row fits at the canonical rest. Spent on the two elastic slots rather than clipped off the
    /// frame — the logo slot first, then the synopsis — because a hard-clipped hero was the
    /// alternative the product review rejected. 0 everywhere except pinned mode at a Poster Size
    /// that needs it (Large today; Small/Medium compute 0 and are bit-identical to Wave 9).
    var compression: CGFloat = 0
    @AppStorage("hero_nuvio_style") private var heroNuvioStyle = false

    /// FEAT-61 (Steven rc3; Batch M D8, 2026-10-19: the Synopsis Length setting is gone and Long is
    /// how Classic always draws, "4 where it fits"): the extra synopsis height and the logo height
    /// it takes (`PinnedRowGeometry.LongSynopsis`, which asks for 4 lines and falls back to fewer
    /// when the poster size and font leave no room, e.g. Large). nil for collection folder heroes
    /// in the carousel (nothing to lengthen), for the non-pinned Nuvio-style hero (already 3–5
    /// lines) and whenever no extra line fits, so those draw exactly what shipped. The hero's
    /// FRAME, and the rows' plan, never change (BUG-87/89: the rows never pay): this only moves
    /// height between the logo, the frame's unused slack and the synopsis.
    private var longSynopsis: PinnedRowGeometry.LongSynopsis.Grant? {
        // Review r1 (P3): folders are excluded only in the carousel (its merged folder box); the
        // Show Hero OFF panel draws a folder's description in the same column, so it follows Long.
        guard !(isCollectionHero(item) && showsCTA) else { return nil }
        let grant: PinnedRowGeometry.LongSynopsis.Grant
        if compact && usesNuvioLayout {
            grant = PinnedRowGeometry.LongSynopsis.pinned(compression: compression,
                                                          showsCTA: showsCTA,
                                                          lineHeight: Theme.Font.synopsisLineHeight)
        } else if !compact && !usesNuvioLayout {
            grant = PinnedRowGeometry.LongSynopsis.classic(showsCTA: showsCTA,
                                                           lineHeight: Theme.Font.synopsisLineHeight)
        } else {
            return nil
        }
        return grant.isGrowing ? grant : nil
    }

    /// The compression split across the two elastic slots, each bounded by its own floor.
    ///
    /// FEAT-29 (Steven's beta.17 report): SYNOPSIS gives first now, logo takes the remainder — the
    /// reverse of Wave 10's original order. A collection FOLDER hero has no synopsis text to
    /// protect (`HomeView.folderHeroPreview` always sends `description: nil`), so its give ceiling
    /// is the WHOLE synopsis slot (`heroSynopsisSlotHeightPinned`, 72 — a genuine 0 floor) rather
    /// than the floor-bounded `heroSynopsisSlotPinnedGive` (36) title heroes use; at Large,
    /// `min(68.3, 72) == 68.3` covers the whole compression and the folder's logo slot gives up
    /// nothing (matches the FEAT-29 design note: "0 at Large since 68.3 ≤ 72"). A TITLE hero keeps
    /// its floor-bounded synopsis ceiling (36) and its own logo-give ceiling
    /// (`heroLogoSlotPinnedGive`, 32) — at Large the two sum to the same 68pt Wave 10 always gave
    /// (36 + 32), so nothing changes there; the swapped order only changes which slot gives first
    /// at INTERMEDIATE compressions (a synced custom Poster Size between Medium and Large), where
    /// the logo now stays at its full 110pt until the synopsis alone has given all 36 of its own
    /// pt — the same regression class this fix closes for folder heroes, closed here too.
    ///
    /// BUG-87 (beta.18): the ceiling is stated against the slot this hero form ACTUALLY has. In
    /// FEAT-15's panel (`showsCTA == false`) the synopsis has already absorbed the CTA slot and the
    /// `md` above it — 144pt, not 72 — so its give against the same one-line floor is 108, and a
    /// folder hero's is the whole 144. Charging the carousel's 36/72 there capped the give 72pt
    /// short of what the panel can really yield, which is why Steven's shape could not be made to
    /// fit: the FRAME would have shrunk past what the CONTENT gave up, the exact overflow
    /// `Theme.Size.heroPinnedCompressionCap` exists to prevent. Carousel numbers are unchanged.
    ///
    /// rc2 (2026-09-06): the split itself now lives in `PinnedRowGeometry.HeroSlotGive`, which is a
    /// pure value function and therefore unit-tested rather than reasoned about here — these two
    /// properties are thin wrappers over it. The behaviour change it carries is for the PANEL form
    /// only: it no longer drains the panel's whole 108pt of synopsis give before touching the logo.
    /// It spends the carousel's own 36 first, then the logo's 32, and only reaches the extra 72 the
    /// panel absorbed from the CTA for compressions past those two plus the frame's 2pt of slack.
    /// At the tester's 68.33 that is synopsis 36 + logo 32 ⇒ a 108pt synopsis slot ⇒ **3 lines**,
    /// the beta.17 reading he asked to keep, where the drain-synopsis-first order gave 2. Carousel
    /// and collection-folder heroes are numerically unchanged at every compression.
    /// rc14 (BUG-119, review r1 P3): the folder-hero split (synopsis slot drained first, logo
    /// unbounded) only applies where the folder hero is DRAWN as the merged logo-only box — the
    /// carousel. The panel renders a folder through the three-slot column with real text in the
    /// synopsis slot now, so it takes the title hero's floors.
    private var splitsAsFolderHero: Bool { isCollectionHero(item) && showsCTA }

    private var synopsisSlotGive: CGFloat {
        PinnedRowGeometry.HeroSlotGive.split(compression: compression,
                                             showsCTA: showsCTA,
                                             folderHero: splitsAsFolderHero).synopsis
    }
    private var logoSlotGive: CGFloat {
        PinnedRowGeometry.HeroSlotGive.split(compression: compression,
                                             showsCTA: showsCTA,
                                             folderHero: splitsAsFolderHero).logo
    }

    /// The compact (pinned) logo slot's height after `logoSlotGive`, or the classic fixed slot
    /// outside pinned mode. Shared by the title-hero column (`nuvioLayout`'s non-folder branch)
    /// and the folder-hero merged box's total-height arithmetic (both need the SAME number the
    /// three-slot layout would have used, so the panel's total height never changes — see that
    /// layout's comment).
    private var logoSlotHeight: CGFloat {
        // FEAT-61 (Steven rc3): Long's logo give, on top of the compression's (nil = no extra line fits).
        if compact, let long = longSynopsis {
            return Theme.Size.heroLogoSlotHeightPinned - logoSlotGive - long.logoGive
        }
        return compact ? Theme.Size.heroLogoSlotHeightPinned - logoSlotGive : Theme.Size.heroLogoSlotHeight
    }

    private var usesNuvioLayout: Bool { forceNuvioLayout || heroNuvioStyle }

    /// rc14: the pinned hero's slot gap (12) — see `Theme.Size.heroPinnedSlotGap`. Classic keeps
    /// `Spacing.md`.
    private var slotGap: CGFloat { compact ? Theme.Size.heroPinnedSlotGap : Theme.Spacing.md }

    var body: some View {
        VStack(alignment: .leading, spacing: slotGap) {
            // Wave H: the info block is ONE unit — logo, meta line and synopsis change together,
            // never one item's text against another's logo.
            //
            // beta.19-rc1 verdict (M5, BUG-138): it no longer CROSS-fades. Under Wave H the block
            // was `.transition(.opacity)` inside the resolver's 0.3 s commit transaction, so the old
            // and the new block were both on screen for 0.3 s (Steven's doubled title). Now
            // `HeroTextLayer`'s `TextSwapModel` fades the old text OUT, swaps it while invisible and
            // fades the new text IN: the swap is a hard cut (`.transition(.identity)`, in an
            // animation-free transaction) and only the opacity, applied OUTSIDE the `.id`, animates
            // (`textAnimation`'s scoped curve). `hero_info` names the block for the UI legs (all
            // builds); in DEBUG, `HeroInfoLiveCounter` counts live blocks from INSIDE the `.id`
            // (`debug_heroText … maxLive=`, test89: a second live block reads 2).
            //
            // Two deliberate details kept from Wave H. The `.id` is on this block and NOT on the CTA
            // below it: the CTA is the hero's only focusable element, and re-identifying a focused
            // view hands the tvOS focus engine a removal it did not ask for (the CTA is not faded
            // either). And the block stays wrapped in a ZStack rather than sitting directly in the
            // VStack: should two copies ever be alive at once again, as VStack children they would
            // stack VERTICALLY — the hero would grow by its own height and shove every row down, the
            // moving-block input BUG-87's corrector then chases. Overlaid in a ZStack they occupy the
            // same fixed-height slot and nothing reflows.
            ZStack(alignment: .topLeading) {
                Group {
                    if usesNuvioLayout {
                        nuvioLayout
                    } else {
                        classicLayout
                    }
                }
                .accessibilityElement(children: .combine)
                #if DEBUG
                .onAppear { HeroInfoLiveCounter.appear() }
                .onDisappear { HeroInfoLiveCounter.disappear() }
                #endif
                .id(textPresentation.identity)
                .transition(.identity)
                .animation(textAnimation) { $0.opacity(textOpacity) }
                .accessibilityIdentifier("hero_info")
            }
            #if DEBUG
            .overlay(alignment: .topLeading) {
                // 2026-09-10 diagnostic (invisible, harness-readable): the measured-line-height
                // inputs to `synopsisLineLimit` (BUG "1–2 lines" — see that property's doc). `synL`
                // is the resolved line limit, `synLH` the measured `Theme.Font.bodyLineHeight`
                // feeding it (rounded for a stable harness read), `synSlot` the synopsis slot
                // height it applies to. No probe existed inside `HomeHeroForeground` before this —
                // added here rather than threading these private computed properties out to
                // `HomeView`'s `debug_env`/`debug_hero` probes, which live in a different struct
                // and cannot see them.
                //
                // P2 fix: this was previously a plain VStack child below the hero ZStack, so its
                // own text height plus the VStack's `spacing` shifted the CTA down and grew the
                // hero's measured content height in DEBUG builds — changing the very geometry it
                // was added to observe. Attached as an `.overlay` on the ZStack instead, it draws
                // on top without being sized into the VStack's layout.
                Text("debug_hero_synopsis synL=\(synopsisLineLimit) synLH=\(Int(Theme.Font.synopsisLineHeight.rounded())) synSlot=\(Int(synopsisSlotHeight.rounded()))")
                    .font(.system(size: 8))
                    .opacity(0.011)
                    .accessibilityIdentifier("debug_hero_synopsis")
                    .allowsHitTesting(false)
            }
            #endif

            // The CTA sits below the description and above the page dots (which render
            // outside the TabView). D-pad left/right still pages the carousel while this
            // button holds focus — it is the page's focus anchor.
            if showsCTA {
                Group {
                    if let folderRoute {
                        NavigationLink(value: folderRoute) {
                            Text(ctaTitle)
                                .font(Theme.Font.body)
                        }
                    } else {
                        NavigationLink(value: TitleRoute(preview: item)) {
                            Text(ctaTitle)
                                .font(Theme.Font.body)
                        }
                    }
                }
                .buttonStyle(.glass)
                .focused(heroFocused)
                .frame(height: Theme.Size.heroButtonSlotHeight, alignment: .center)
                .accessibilityLabel("\(ctaTitle): \(item.name)")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        // rc14: pinned vertical padding 16 → 12 (`heroPinnedVerticalPad`) — part of the chrome
        // shave that hands `HeroSlotGive.split` 22pt of free slack. Classic keeps `lg`.
        .padding(.vertical, compact ? Theme.Size.heroPinnedVerticalPad : Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Fixed synopsis slot. FEAT-15: with no CTA the panel would otherwise centre itself inside
    /// the hero region's fixed frame and leave a dead band where the button used to be, so the
    /// synopsis absorbs the CTA slot AND the gap that preceded it — same arithmetic on the
    /// same existing tokens, no new Theme constant, and the summed panel height comes out
    /// IDENTICAL, which is what keeps the pinned rows viewport (and every `heroPinned*` reach
    /// constant tuned against it) untouched. rc14 numbers (chrome shave: 12pt pads, 12pt gaps):
    ///     carousel form  24 padding + 110 logo + 12 + 32 meta + 12 + 72 synopsis + 12 + 56 CTA = 330
    ///     panel form     24 padding + 110 logo + 12 + 32 meta + 12 + 140 synopsis            = 330
    /// both inside the 352pt `heroCarouselHeightPinned` frame the caller pins; the 22 left over is
    /// `heroPinnedFrameSlack`, which the split spends first. The line limit grows with the slot:
    /// 140pt fits four `Theme.Font.synopsis` lines, so the panel FEAT-15 asks for shows twice the
    /// description the pinned carousel could.
    ///
    /// BUG-87 (beta.18): the compact branch resolves the panel's slot from
    /// `heroSynopsisSlotHeightPinnedPanel` (which IS `72 + 56 + 16`) before subtracting the give,
    /// instead of subtracting the give from 72 and adding the CTA terms back afterwards. Same
    /// number in every configuration that shipped; it stops being the same one once the give can
    /// exceed 72, which is what the panel's real ceiling now allows.
    private var synopsisSlotHeight: CGFloat {
        guard compact else {
            let base = Theme.Size.heroSynopsisSlotHeightNuvio
            return showsCTA ? base : base + Theme.Size.heroButtonSlotHeight + Theme.Spacing.md
        }
        let slot = showsCTA ? Theme.Size.heroSynopsisSlotHeightPinned
                            : Theme.Size.heroSynopsisSlotHeightPinnedPanel
        // FEAT-61 (Steven rc3): Long's growth (nil = no extra line fits, the shipped expression).
        if let long = longSynopsis {
            return slot - synopsisSlotGive + long.synopsisGrowth
        }
        return slot - synopsisSlotGive
    }

    /// Lines the synopsis may use, tracking `synopsisSlotHeight` above.
    ///
    /// Wave 10: a compressed synopsis slot must drop a line with it, or the text clips inside its
    /// own frame instead of shortening.
    ///
    /// BUG-87 (beta.18): DERIVED from the resolved slot rather than from a give>0 flag. The pinned
    /// slot is exactly two 36pt lines, so the line height is the constant divided by two and the
    /// limit is however many whole lines the slot still holds. That reproduces every number the
    /// flag produced — carousel 72 → 2, carousel compressed 36 → 1, panel 144 → 4, panel at Wave
    /// 10's Large give (108) → 3 — and keeps holding once the panel's give can take the slot below
    /// 72, where the flag would have claimed three lines in a one-line box.
    ///
    /// 2026-09-10: the `/ 2` above assumed a 36pt line, which is not `Theme.Font.body`'s real
    /// rendered line height — the system face is ≈35pt and Open Sans (FEAT-31) is ≈39.5pt at the
    /// same size. That mismatch undercounted Open Sans (a 108pt slot drew 2 lines while this
    /// counted 3 — the tester's report) and, after this batch's Large reach change puts the
    /// No-Zoom panel slot at 107.67, overcounts the system face too (36 rounds it down to 2 when
    /// the real ~35pt line fits 3). Measured via `Theme.Font.bodyLineHeight` instead of assumed.
    private var synopsisLineLimit: Int {
        guard compact else { return showsCTA ? 3 : 5 }
        // FEAT-61 (Steven rc3): Long's line count, sized to the grown slot above.
        if let long = longSynopsis { return long.lines }
        // Measured, not assumed — see `Theme.Font.synopsisLineHeight` (rc14: the synopsis is set
        // in `Theme.Font.synopsis`, one text style below `body`, so its own metric is the one that
        // counts). A slot that is short of a whole line by less than `lineTolerance` still gets
        // the line: the synopsis `Text` sits in a fixed-height frame, so an overhang that small is
        // clipped by the frame and never seen, whereas rounding it away costs a whole visible line
        // (the 107.67-vs-108 case).
        let lineHeight = Theme.Font.synopsisLineHeight
        let lineTolerance: CGFloat = 1
        guard lineHeight > 0 else { return 1 }
        return max(1, Int(((synopsisSlotHeight + lineTolerance) / lineHeight).rounded(.down)))
    }

    /// "movie" is the only meta type that reads as a film; series/tv both read as shows.
    private var ctaTitle: String {
        if folderRoute != nil { return String(localized: "Open Folder") }
        return item.type == "movie"
            ? String(localized: "Go to Movie")
            : String(localized: "Go to Show")
    }

    /// Nuvio-style: fixed-width text column on the left (logo, meta, 3-line synopsis) — the
    /// artwork owns the rest of the frame to the right.
    ///
    /// FEAT-29: a collection FOLDER hero (`isCollectionHero(item)`) renders a single MERGED box
    /// instead — `folderHeroPreview` always sends `description: nil, genres: []`, so the
    /// three-slot column used to draw an empty meta line and an empty synopsis under a wordmark
    /// that Wave 10's (pre-fix) give order shrank first. One generously-sized, vertically centred
    /// `HeroLogo` reads as the reference footage instead (`zoom-nuvio-collection-t96.png`). The
    /// box's total height is `logoSlotHeight + md + heroMetaSlotHeight + md + synopsisSlotHeight`
    /// — the EXACT sum the three-slot VStack below would have consumed (two `Spacing.md` gaps
    /// between three children, `.frame(height:)` on each) — so the outer `heroCarouselHeightPinned
    /// - compression` frame this whole view sits inside never changes and rows below cannot
    /// reflow; only what is drawn inside the box differs.
    private var nuvioLayout: some View {
        Group {
            if isCollectionHero(item) && showsCTA {
                folderBox(height: logoSlotHeight + slotGap + Theme.Size.heroMetaSlotHeight
                                  + slotGap + synopsisSlotHeight)
            } else {
                // rc14 (BUG-119, Steven 2026-09-13 + rc13 verdict): in the CTA-less PANEL form a
                // focused collection folder keeps the three-slot column — wordmark, then the
                // folder's collection name as the meta line and a one-line description in the
                // synopsis slot — instead of the carousel's merged logo-only box. "I can still see
                // the top row, and there's no title or description in this mode": the panel's job
                // is to describe the focused tile, and a folder has a name even when it has no
                // synopsis. The merged box stays for the carousel (FEAT-29's reference footage).
                VStack(alignment: .leading, spacing: slotGap) {
                    HeroLogo(item: item, image: textPresentation.logo, ink: textPresentation.logoInk)
                        .frame(height: logoSlotHeight, alignment: .bottomLeading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(metaLine)
                        .font(Theme.Font.metaStrong)
                        .foregroundStyle(Theme.Palette.textPrimary.opacity(0.9))
                        .lineLimit(1)
                        .frame(height: Theme.Size.heroMetaSlotHeight, alignment: .leading)

                    Text(synopsis)
                        .font(Theme.Font.synopsis)
                        .foregroundStyle(Theme.Palette.textPrimary.opacity(0.85))
                        .lineLimit(synopsisLineLimit)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: synopsisSlotHeight, alignment: .topLeading)
                        // Wave H: a description that arrives after its hero was committed (the
                        // one gap-fill the commit protocol still allows) lands with NO motion. The
                        // slot's height is fixed either way, so there is nothing to animate but
                        // the text itself, and animating that is the "empty synopsis, then it
                        // pops in" the tester filmed.
                        .animation(nil, value: synopsis)
                }
            }
        }
        .frame(width: Theme.Size.heroInfoPanelWidth, alignment: .leading)
    }

    /// The original bottom-left layout. FEAT-29: gets the same folder-hero merged-box treatment as
    /// `nuvioLayout` — it already has its own logo slot to merge into, and `compression` is always
    /// 0 in classic (the in-scroll hero, `heroCarousel`'s `compact: false` call site), so the box
    /// total is the fixed sum below rather than `logoSlotHeight`/`synopsisSlotHeight`'s compact
    /// arithmetic.
    private var classicLayout: some View {
        Group {
            if isCollectionHero(item) {
                folderBox(height: Theme.Size.heroLogoSlotHeight + Theme.Spacing.md
                                  + Theme.Size.heroMetaSlotHeight + Theme.Spacing.md
                                  + Theme.Size.heroSynopsisSlotHeight)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HeroLogo(item: item, image: textPresentation.logo, ink: textPresentation.logoInk)
                        .frame(height: classicLogoSlotHeight, alignment: .bottomLeading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(metaLine)
                        .font(Theme.Font.metaStrong)
                        .foregroundStyle(Theme.Palette.textPrimary.opacity(0.9))
                        .lineLimit(1)
                        .frame(height: Theme.Size.heroMetaSlotHeight, alignment: .leading)

                    Text(synopsis)
                        .font(Theme.Font.synopsis)
                        .foregroundStyle(Theme.Palette.textPrimary.opacity(0.85))
                        .lineLimit(classicSynopsisLineLimit)
                        .frame(maxWidth: 1000, alignment: .leading)
                        .frame(height: classicSynopsisSlotHeight, alignment: .topLeading)
                        // Wave H: see the same line in `nuvioLayout` — a late description must
                        // not animate.
                        .animation(nil, value: synopsis)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// FEAT-61 (Steven rc3): the in-scroll Classic hero's three synopsis/logo numbers. With no
    /// extra line (`longSynopsis == nil`) it returns the shipped constants untouched; Long grows the synopsis
    /// into the 452 pt frame's 46 pt of unused slack first, then the logo down to 110.
    private var classicLogoSlotHeight: CGFloat {
        guard let long = longSynopsis else { return Theme.Size.heroLogoSlotHeight }
        return Theme.Size.heroLogoSlotHeight - long.logoGive
    }
    private var classicSynopsisSlotHeight: CGFloat {
        guard let long = longSynopsis else { return Theme.Size.heroSynopsisSlotHeight }
        return Theme.Size.heroSynopsisSlotHeight + long.synopsisGrowth
    }
    private var classicSynopsisLineLimit: Int { longSynopsis?.lines ?? 2 }

    /// FEAT-29's merged folder box, `height` tall (the exact sum the three-slot column would have
    /// consumed, so the hero's total height never moves).
    ///
    /// BUG-159 (was BUG-154; Steven, beta.19-rc3 follow-up 2026-10-08, photos 2 and 3): with Show
    /// Hero ON a focused collection folder showed the wordmark and "Open Folder" and nothing else,
    /// while the Show Hero OFF panel read "Aventure · 8 sources" (rc14's BUG-119
    /// `folderHeroDescription`, which `HomeRowPreviews.folder` already puts in the preview's
    /// `description`). A folder has no synopsis, so the box's own bottom `heroMetaSlotHeight` carries
    /// that one line in `Theme.Font.meta` and the wordmark takes the rest (`HeroFolderBoxLayout`).
    /// The line budget for TITLE heroes (rt4) is untouched: this is the folder branch only. A
    /// preview with no description keeps the full-height wordmark.
    ///
    /// B1 (rc4 verdict 2026-10-16): that reading was wrong. Steven's 10-08 words were about the
    /// Stage heading's add-on name and he wants the source count off BOTH Homes, so the line now
    /// rides Show Catalog Details in Headings (`HeadingDetailsSetting`, default off): off, the
    /// preview's description is nil and this box shows the wordmark alone, as before rc4.
    @ViewBuilder
    private func folderBox(height: CGFloat) -> some View {
        let line = synopsis.trimmingCharacters(in: .whitespacesAndNewlines)
        let split = HeroFolderBoxLayout.split(boxHeight: height, hasLine: !line.isEmpty)
        VStack(alignment: .leading, spacing: 0) {
            HeroLogo(item: item, image: textPresentation.logo,
                     maxHeight: min(Theme.Size.heroFolderLogoHeightOverride
                                        ?? Theme.Size.heroFolderLogoSlotHeight,
                                    split.logo),
                     ink: textPresentation.logoInk)
                .frame(height: split.logo, alignment: .leading)
            if split.line > 0 {
                Text(line)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.Palette.textPrimary.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: split.line, alignment: .bottomLeading)
                    .accessibilityIdentifier("hero_folder_line")
                    // Wave H: a late description must not animate (see the synopsis slots).
                    .animation(nil, value: line)
            }
        }
        .frame(height: height, alignment: .top)
    }

    private var synopsis: String {
        let description: String? = item.description_
        return description ?? ""
    }

    private var metaLine: String {
        var parts: [String] = []
        let release: String? = item.releaseInfo
        if let release, !release.isEmpty { parts.append(release) }
        let genres = item.genres.prefix(3)
        if !genres.isEmpty { parts.append(genres.joined(separator: " \u{00B7} ")) }
        return parts.joined(separator: "  \u{00B7}  ")
    }
}

/// beta.19-rc1 verdict (M5, BUG-138): the hero's text layer. Owns and OBSERVES the text swap model
/// (`HeroTextSwapModel`, `.classic` timing), so a hero change re-renders this layer and
/// `HomeHeroForeground`, never `HomeView`'s body, which holds no swap model and observes nothing
/// new (critique #11).
///
/// The resolver's committed `presentation` still drives the artwork (`HomeHeroBackdrop`, unchanged)
/// the instant it commits; the TEXT follows one fade-out later: old text out over 0.12 s, swapped
/// while invisible, new text in over 0.12 s. A same-identity update (a late synopsis, spec B's
/// post-commit sharpen) is a silent gap-fill. The CTA follows the visible text, so it never opens
/// a title whose name is not on screen.
///
/// Lives in this file, not `HeroTextSwap.swift`, because `HomeHeroForeground`'s memberwise init is
/// file-private (it has a private `@AppStorage`).
struct HeroTextLayer: View {
    /// The resolver's committed hero (`HeroArtResolver.presented`).
    let presentation: HeroPresentation
    var heroFocused: FocusState<Bool>.Binding
    var compact: Bool
    var showsCTA: Bool
    var forceNuvioLayout: Bool
    var compression: CGFloat
    /// `HomeView.heroFolderRoutes`: looked up for the VISIBLE text's item, so a folder CTA opens the
    /// folder whose name is on screen.
    var folderRoutes: [String: FolderRoute]

    @StateObject private var textSwap = HeroTextSwapModel(timing: .classic, identity: { $0.identity })
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// BUG-190: an explicit internal init, the one entry point Home (`HomeHeroTextSlot`) and the
    /// Classic folder rows page (`FolderDetailView.classicRowsPage`, through the same slot) share. `folderRoutes` defaults to none: a
    /// folder page's cards are titles, never folders.
    init(presentation: HeroPresentation,
         heroFocused: FocusState<Bool>.Binding,
         compact: Bool,
         showsCTA: Bool,
         forceNuvioLayout: Bool,
         compression: CGFloat,
         folderRoutes: [String: FolderRoute] = [:]) {
        self.presentation = presentation
        self.heroFocused = heroFocused
        self.compact = compact
        self.showsCTA = showsCTA
        self.forceNuvioLayout = forceNuvioLayout
        self.compression = compression
        self.folderRoutes = folderRoutes
    }

    var body: some View {
        let text = textSwap.shown ?? presentation
        HomeHeroForeground(textPresentation: text,
                           textOpacity: textSwap.textOpacity,
                           textAnimation: textSwap.opacityAnimation,
                           heroFocused: heroFocused,
                           compact: compact,
                           showsCTA: showsCTA,
                           forceNuvioLayout: forceNuvioLayout,
                           folderRoute: isCollectionHero(text.item) ? folderRoutes[text.item.id] : nil,
                           compression: compression)
            .onAppear { textSwap.seed(presentation) }
            .onChange(of: presentation) { _, next in
                textSwap.receive(next, reduceMotion: reduceMotion)
            }
            #if DEBUG
            .overlay(alignment: .topLeading) {
                // Invisible, harness-readable (test89): the swap's live state plus the live info
                // block high-water mark. Append-only: `phase= shown= pending= swaps= maxLive=`.
                // `maxLive=1` is the "never two titles at once" oracle; a block that lingers next to
                // its successor reads 2 (see `HeroInfoLiveCounter`).
                Text("debug_heroText \(textSwap.debugLine) maxLive=\(HeroInfoLiveCounter.max)")
                    .font(.system(size: 8))
                    .opacity(0.011)
                    .accessibilityIdentifier("debug_heroText")
                    .allowsHitTesting(false)
            }
            #endif
    }
}

#if DEBUG
/// beta.19-rc1 verdict (M3/R2, BUG-133): the inline trailer event log (`InlineTrailerDebugLog`,
/// written by `InlineTrailerCardModel`) as an invisible, harness-readable label. A LEAF view that
/// observes the log itself, so an event re-renders this label and never `HomeView`'s body
/// (critique #11).
///
/// Spelling: `debug_trailerMorph <last event> aborts=N`. The event is the log's own line
/// (`event=gate|reveal|wide|shrink|dissolve|abort|defer|play|mute host=card|hero key=…`); `aborts=`
/// is appended after it (`abortCount` moves in the same `note` that publishes `last`).
struct TrailerMorphDebugLabel: View {
    @ObservedObject private var log = InlineTrailerDebugLog.shared

    var body: some View {
        Text("debug_trailerMorph \(log.last) aborts=\(log.abortCount)")
            .font(.system(size: 8))
            .opacity(0.011)
            .accessibilityIdentifier("debug_trailerMorph")
            .allowsHitTesting(false)
    }
}

/// beta.19-rc1 verdict (B2, BUG-131): the trailer listener lifecycle (`TrailerListenerDebug`,
/// mirrored from every `[TrailerRepack] listener …` line) as an invisible, harness-readable label.
/// A LEAF view, like `TrailerMorphDebugLabel`.
///
/// Spelling: `debug_trailerListener <last> rebuilds=N recent=<newest six, " | "-joined>`. `last` is
/// overwritten by the `start`/`ready` lines a moment after a rebuild, so an oracle for "a rebuild
/// happened" (test91: `rebuild reason=active`) reads `rebuilds=` or `recent=`, never `last`.
/// `rebuilds` moves in the same `note` that publishes `last`/`recent`.
struct TrailerListenerDebugLabel: View {
    @ObservedObject private var listener = TrailerListenerDebug.shared

    var body: some View {
        Text("debug_trailerListener \(listener.last) rebuilds=\(listener.rebuilds) recent=\(listener.recent)")
            .font(.system(size: 8))
            .opacity(0.011)
            .accessibilityIdentifier("debug_trailerListener")
            .allowsHitTesting(false)
    }
}
#endif

/// BUG-38 round three: the `MetaPreview.type` a collection folder's hero preview carries, and
/// the scheme its synthetic id starts with. Both are namespaced so no addon catalog item can
/// satisfy `isCollectionHero` by accident (Codex round 1: Stremio manifests may declare ANY
/// media type — "collection" included — and a real title misclassified here would lose its hero
/// trailer and enrichment). The predicate requires BOTH the dotted type and the id scheme; a
/// catalog would have to ship that exact pair, which nothing does.
/// BUG-159 (Steven, beta.19-rc3 follow-up 2026-10-08): how `HomeHeroForeground.folderBox` splits
/// FEAT-29's merged folder box between the wordmark and the one-line folder description
/// (`HomeView.folderHeroDescription`). Pure, so the "the box never changes height" invariant is
/// asserted in `PinnedRowGeometryTests` rather than reasoned about.
nonisolated enum HeroFolderBoxLayout {
    /// `logo + line == boxHeight` always. With a line, the line takes `heroMetaSlotHeight` (the
    /// meta slot's own height, so it reads at the meta line's size) unless the box is so short that
    /// would leave the wordmark under `minLogo`, in which case the line is dropped rather than the
    /// wordmark squeezed: the wordmark is the folder's identity, the line is its caption.
    static let minLogo: CGFloat = 48

    static func split(boxHeight: CGFloat, hasLine: Bool) -> (logo: CGFloat, line: CGFloat) {
        let box = max(0, boxHeight)
        let line = Theme.Size.heroMetaSlotHeight
        guard hasLine, box - line >= minLogo else { return (box, 0) }
        return (box - line, line)
    }
}

let collectionHeroType = "nuvio.folder"
let collectionHeroIdScheme = "nuvio-folder://"

func isCollectionHero(_ item: MetaPreview) -> Bool {
    item.type == collectionHeroType && item.id.hasPrefix(collectionHeroIdScheme)
}

/// Resolves the logo artwork URL for a hero item. Catalog previews (Cinemeta rows especially)
/// usually omit `logo` even when logo art exists, so for IMDb-id items fall back to metahub —
/// the same CDN Cinemeta's own full meta points at. A miss there just 404s and `HeroLogo`
/// shows its text wordmark, so the synthesized URL is strictly additive (BUG-17).
func heroLogoURL(for item: MetaPreview) -> URL? {
    heroLogoURL(logo: item.logo, id: item.id)
}

/// Same chain for a Continue Watching entry, so the CW row's prefetch warms the logo the hero will
/// actually wait on (`background`/`parentMetaId` play the banner/id roles, exactly as they do for
/// `heroBackdropURL(for:)`).
func heroLogoURL(for entry: WatchProgressEntry) -> URL? {
    heroLogoURL(logo: nil, id: entry.parentMetaId)
}

private func heroLogoURL(logo: String?, id: String) -> URL? {
    if let logo, !logo.isEmpty { return URL(string: logo) }
    let imdbId = id.split(separator: ":").first.map(String.init) ?? id
    guard imdbId.hasPrefix("tt") else { return nil }
    return URL(string: "https://images.metahub.space/logo/medium/\(imdbId)/img")
}

/// Resolves the backdrop artwork URL for a hero item — a carousel page, or (UX-7) a row poster
/// that has taken over the hero. `banner` covers the common case; IMDb-id items without one fall
/// back to metahub's background art (the same CDN `heroLogoURL` leans on above) before finally
/// falling back to poster art. Every step is strictly additive — a miss just moves to the next
/// source, never a hard failure.
func heroBackdropURL(for item: MetaPreview) -> String? {
    heroBackdropURL(banner: item.banner, id: item.id, poster: item.poster)
}

/// Same chain for a Continue Watching entry (`background` plays the banner role, the parent meta
/// id carries the IMDb id) — the CW row's prefetch must warm the URL the hero will actually
/// render, not a poster the metahub branch would shadow.
func heroBackdropURL(for entry: WatchProgressEntry) -> String? {
    heroBackdropURL(banner: entry.background, id: entry.parentMetaId, poster: entry.poster)
}

private func heroBackdropURL(banner: String?, id: String, poster: String?) -> String? {
    if let banner, !banner.isEmpty { return banner }
    let imdbId = id.split(separator: ":").first.map(String.init) ?? id
    if imdbId.hasPrefix("tt") {
        return "https://images.metahub.space/background/medium/\(imdbId)/img"
    }
    return (poster?.isEmpty == false) ? poster : nil
}

/// Prefetch wants BOTH candidates the hero can render — the resolved primary AND the poster
/// `HeroArtResolver` falls back to when the primary (typically a synthesized metahub URL) 404s or
/// stalls. Warming only the primary made exactly the fallback scenario the cold, flashing one, and
/// keeping the poster warm here is what makes the resolver's fallback usually free: it commits the
/// cached poster the instant the primary misses instead of spending its budget fetching one.
/// Cheap in practice: row posters are the card images already on screen, so `ArtworkStore`'s
/// cache check absorbs the duplicates.
/// Wave H: the LOGO is in here too. The hero now commits only once both its backdrop and its logo
/// have resolved (or a deadline passed), so a cold logo is a delayed hero — and every row-focus
/// prefetch warms both for the whole row rather than leaving the logo to be fetched at paint time.
func heroBackdropPrefetchURLs(for item: MetaPreview) -> [String] {
    var urls: [String] = []
    if let primary = heroBackdropURL(for: item) { urls.append(primary) }
    if let poster = item.poster, !poster.isEmpty, !urls.contains(poster) { urls.append(poster) }
    if let logo = heroLogoURL(for: item)?.absoluteString, !urls.contains(logo) { urls.append(logo) }
    return urls
}

/// beta.19-rc1 verdict (review r2, P3-1): `heroBackdropPrefetchURLs(for:)` as typed prefetch items
/// for the hero carousel's warm-up (`prefetchHeroArt`): the title logo at
/// `HeroSharpen.heroLogoRequest`, the request `HeroArtResolver.present` looks it up and fetches it
/// with (so the hero's own fetch joins this one while it is in flight instead of downloading the file
/// a second time), the backdrop and the poster at `.legacy` as before. The row-focus prefetches keep
/// the plain URL list: they run before the hero presents a row's item, and a slot-sized fetch joins
/// the larger legacy work still in flight (`ArtworkStore.inflightKeys`).
func heroArtPrefetchItems(for item: MetaPreview) -> [ArtworkPrefetchItem] {
    let logo = heroLogoURL(for: item)?.absoluteString
    let backdrop = heroBackdropURL(for: item)
    let logoRequest = HeroSharpen.heroLogoRequest
    return heroBackdropPrefetchURLs(for: item).compactMap { string in
        guard let url = URL(string: string) else { return nil }
        // A logo URL that is also the backdrop or the poster keeps the legacy decode those need.
        let logoOnly = string == logo && string != backdrop && string != item.poster
        return ArtworkPrefetchItem(url: url, decode: logoOnly ? logoRequest : .legacy)
    }
}

/// Continue Watching flavor of `heroBackdropPrefetchURLs(for:)`.
func heroBackdropPrefetchURLs(for entry: WatchProgressEntry) -> [String] {
    var urls: [String] = []
    if let primary = heroBackdropURL(for: entry) { urls.append(primary) }
    if let poster = entry.poster, !poster.isEmpty, !urls.contains(poster) { urls.append(poster) }
    if let logo = heroLogoURL(for: entry)?.absoluteString, !urls.contains(logo) { urls.append(logo) }
    return urls
}

/// The hero page's logo artwork, with the title text as its stand-in when the item has no logo (or
/// its logo did not resolve before the hero's commit deadline).
///
/// Wave H: STATELESS. It used to own a `.task` that fetched the logo and swapped Text→Image under
/// its own `withAnimation(.easeIn(0.25))` — with SwiftUI's default cross-dissolve that draws the
/// title text and the wordmark superimposed for the length of the fade, which is exactly what the
/// tester filmed on every hero change (BUG-86 phenomenon B, and BUG-90). There is nothing to fetch
/// here now: `HeroArtResolver` resolves the logo BEFORE the hero commits and hands it down as a
/// value, so text and image are two branches of one atomic state, never two overlapping paints.
///
/// `.id(item.id)` + `.transition(.identity)` make the branch swap a hard cut rather than a fade —
/// the fade belongs to the whole info block one level up (`HomeHeroForeground`), which fades the
/// OLD hero's text out and then the NEW hero's in (beta.19-rc1 verdict M5, `TextSwapModel`), never
/// one item's text against its own logo.
///
/// beta.19-rc1 verdict (M5, BUG-138): `ink` is the resolver's verdict on the bitmap
/// (`HeroLogoInk`). A near-black, low-chroma wordmark (`.dark`) would vanish on the dark hero, so it
/// is drawn as a template in the primary text colour (a white silhouette); everything else
/// (`.legible`, including red, blue and every brand colour) is drawn exactly as before. `.blank`
/// never reaches here with a bitmap: the resolver commits it as no logo, so the text stand-in shows.
struct HeroLogo: View {
    let item: MetaPreview
    /// The resolved wordmark, or nil for the text stand-in. Supplied by the caller — see the type
    /// doc for why this view may not fetch it itself.
    let image: UIImage?
    /// FEAT-29: caps how tall the wordmark (or its text stand-in's own font metrics — unaffected,
    /// this only bounds the `Image` branch) may render. Defaults to the classic title-hero cap
    /// (`heroLogoSlotHeight`), unchanged for every existing call site. The folder-hero merged box
    /// (`HomeHeroForeground.nuvioLayout`/`.classicLayout`) passes `heroFolderLogoSlotHeight`
    /// instead, so a collection wordmark reads at the reference size regardless of what the
    /// shared title-hero logo slot is doing under Wave 10 compression.
    var maxHeight: CGFloat = Theme.Size.heroLogoSlotHeight
    /// beta.19-rc1 verdict (M5): see the type doc.
    var ink: HeroLogoInk = .legible

    var body: some View {
        Group {
            if let image {
                logoImage(image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    // Tints only the `.template` rendering (`.dark`); the `.original` bitmap
                    // ignores the foreground style, so `.legible` draws exactly as before.
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(
                        maxWidth: Theme.Size.heroLogoMaxWidth,
                        maxHeight: maxHeight,
                        alignment: .bottomLeading
                    )
            } else {
                Text(item.name)
                    .font(Theme.Font.hero)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
        }
        .id(item.id)
        .transition(.identity)
    }

    /// `.template` for a `.dark` wordmark (the silhouette), `.original` otherwise — explicit, so
    /// the foreground style above can never tint a brand-coloured logo.
    private func logoImage(_ image: UIImage) -> Image {
        Image(uiImage: image).renderingMode(ink == .dark ? .template : .original)
    }
}

/// Page-position dots for the hero carousel. Rendered once, outside the sliding pages, so they
/// stay put while the carousel animates.
struct HeroPageDots: View {
    let count: Int
    let index: Int

    /// Capsule height of each dot.
    nonisolated static let dotHeight: CGFloat = 10
    /// The laid-out height of this view: a dot plus the vertical padding. Read by
    /// `Theme.Size.heroPinnedRowsViewportBudget(showsCTA:)`, whose panel-form budget is taller by
    /// exactly this plus the header's `Spacing.sm` (2026-09-30), so the two cannot drift.
    nonisolated static let height: CGFloat = dotHeight + 2 * Theme.Spacing.xs

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index
                          ? Theme.Palette.textPrimary
                          : Theme.Palette.textSecondary.opacity(0.45))
                    .frame(width: i == index ? 34 : 10, height: Self.dotHeight)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .glassEffect(.regular, in: .capsule)
        .animation(.easeInOut(duration: 0.3), value: index)
        .accessibilityHidden(true)
    }
}

/// rc14 (BUG-112 residue): the Up-input bookkeeping `HomeView.revealTopAfterUpIntoHero` reads —
/// a reference box so the window-level swipe catcher can stamp it without a Home body re-evaluation
/// (review r1 P3). `MainActor` like everything that touches it.
@MainActor
final class HomeRowInputBox {
    /// beta.18 verdict (BUG-126): the row-focus ownership state, moved here from `@State` so a row
    /// hop does not re-evaluate Home's body (see `RowStepAB.handlerOnlyRowStateOffBody`). Handlers
    /// only; nothing renders these.
    var focusedRowKey: String?
    /// `systemUptime` of the last change of `focusedRowKey` to a different row.
    var lastRowFocusChangeAt: TimeInterval?
    /// When the last Up INPUT arrived — a press via `handleRowsMove`/`handleHeroUp`, a swipe via the
    /// catcher's `onAnySwipeUp` — consumed or not. `-1` = never.
    var lastUpInputAt: TimeInterval = -1
    /// When a row last released focus (`handleRowFocusOwnership`'s `owns: false` branch).
    var lastRowReleasedAt: TimeInterval?
    /// Voids a pending deferred re-check when a newer hero focus gain or a reveal supersedes it.
    var revealGeneration = 0
    /// review r1 (P3-3): `systemUptime` of the last up-into-hero reveal scroll; latch for the
    /// `alreadyRevealing` decline.
    var lastRevealAt: TimeInterval?
    /// H9 (P4 §6.2): the row that last took focus. Written on every `owns == true` report and never
    /// cleared on release (unlike `focusedRowKey`), so it still names the Left origin's row while
    /// the rail holds focus.
    var lastOwnedRowKey: String?
    /// BUG-156 (review r1 P2-4): a pop restore is between its first rung and its landing / expiry;
    /// the first directional press retires it (`handleRowsMove`).
    var returnPending = false
    /// BUG-156 (device pass 2026-10-15): the live restore's origin, for the hero re-grab; nil outside
    /// an attempt. `returnRegrabbed` latches the one re-grab per attempt.
    var returnOrigin: HomeReturnFocusMemory.Origin?
    /// Re-grabs issued for the live attempt (`heroRegrabLimit`).
    var returnRegrabs = 0
    /// H9: where Classic's rail route returns focus (captured when the rail arms).
    var railReturnTarget: HomeRailReturnTarget?
    /// BUG-156: the card each row last focused and the row + card a push left from. Written from
    /// the rows' focus reports and the `homePath` edges; handlers only, never rendered.
    var returnFocus = HomeReturnFocusMemory()
    /// BUG-156: stales the rungs of an older pop restore (a new push, a newer pop).
    var returnGeneration = 0
}

/// H9 (P4 §2.5): Classic Home's rail return target — the hero CTA, or a row (its first card).
nonisolated enum HomeRailReturnTarget: Equatable, Sendable {
    case hero
    case row(String)
}

/// BUG-156 (P2; Steven, beta.19-rc3 follow-ups 2026-10-09 and 10-14): "after leaving a folder, Home
/// doesn't come back to where I was". Classic Home kept no focused-card id at all and relied on the
/// focus engine's own restoration when a pushed folder page, Detail or See All grid popped, and that
/// restoration loses the card whenever the focused view it remembers was replaced while Home was
/// covered (the In Row trailer's morphed card collapsing back to a poster when the push tore the
/// trailer down is one such replacement), so the engine falls back to its default candidate.
///
/// This is the pure half: the card each row last focused (from the row's own `@FocusState`, via
/// `PinnedRowFocusOwnership.noteFocusedItem`), the origin a push left from (captured on the
/// `homePath` 0 → 1 edge, so a row change during the cover cannot redirect it), and the request the
/// pop issues. `HomeView.restoreRowAfterPop` runs the rungs. A push from the hero CTA records no
/// origin: native restoration handles the CTA, and a row request there would steal it.
nonisolated struct HomeReturnFocusMemory: Equatable, Sendable {
    struct Origin: Equatable, Sendable {
        let rowKey: String
        let itemId: String?
    }

    /// How long after a row released focus a push still counts as "from that row" when the release
    /// report beat the `homePath` change (the two are separate SwiftUI updates with no set order).
    static let releaseGrace: TimeInterval = 0.3

    private(set) var itemByRow: [String: String] = [:]
    private(set) var origin: Origin?

    mutating func remember(rowKey: String, itemId: String) {
        itemByRow[rowKey] = itemId
    }

    /// The push edge. `focusedRowKey` is the row that owns focus right now; when it is already nil
    /// (its release arrived first), `lastOwnedRowKey` counts only if that release is younger than
    /// `releaseGrace`. The hero CTA holding focus means the push came from the hero: no origin.
    mutating func notePush(focusedRowKey: String?, lastOwnedRowKey: String?,
                           sinceRowRelease: TimeInterval?, heroFocused: Bool) {
        guard !heroFocused else {
            origin = nil
            return
        }
        let row = focusedRowKey
            ?? (sinceRowRelease.map { $0 >= 0 && $0 < Self.releaseGrace } == true ? lastOwnedRowKey : nil)
        origin = row.map { Origin(rowKey: $0, itemId: itemByRow[$0]) }
    }

    /// The pop edge: the origin to restore, once. A second pop without a push returns nil.
    mutating func takeOrigin() -> Origin? {
        defer { origin = nil }
        return origin
    }

    /// The restore rungs: the remembered card on the first two, the row's first card on the last
    /// (that card is what the earlier rungs could not reach: an id gone from the row, an unrealized
    /// card). The same shape as the strip's rungs (`StripPager.requestRowFocus`).
    static let rungDelays: [TimeInterval] = [0, 0.3, 0.7]
    /// Device pass 2026-10-15: the engine's own restoration fired 0.98 s after the pop on the
    /// Living Room ATV; the attempt (and its hero re-grab) lives 1.5 s.
    static let expiry: TimeInterval = 1.5

    /// The last rung lands on the row's first card (nothing left to force onto).
    static func isLastRung(_ rung: Int) -> Bool { rung >= rungDelays.count }

    static func request(for origin: Origin, rung: Int, generation: Int) -> PinnedRowFocusRequest {
        let last = isLastRung(rung)
        return PinnedRowFocusRequest(rowKey: origin.rowKey, generation: generation,
                                     itemId: last ? nil : origin.itemId, forceFirst: last)
    }
}

#if DEBUG
/// BUG-156: the `debug_homeReturn` readout (`own=<rowKey> foc=<rowKey>/<itemId> ret=<last restore
/// event>`; `ret` is free text and comes last). A
/// LEAF observing its own sink, so a card hop re-renders this label and never Home's body.
@MainActor
final class HomeReturnDebug: ObservableObject {
    static let shared = HomeReturnDebug()
    @Published private(set) var foc = "-"
    @Published private(set) var ret = "-"
    /// The row that owns focus right now (`handleRowFocusOwnership`), "-" while none does (the hero
    /// CTA, the tab bar, a pushed page).
    @Published private(set) var own = "-"

    func setOwn(_ rowKey: String?) {
        let next = rowKey ?? "-"
        if own != next { own = next }
    }

    func setFoc(rowKey: String, itemId: String) {
        let next = "\(rowKey)/\(itemId)"
        if foc != next { foc = next }
    }

    func setRet(_ event: String) {
        if ret != event { ret = event }
    }
}

struct HomeReturnDebugLabel: View {
    @ObservedObject private var debug = HomeReturnDebug.shared

    var body: some View {
        Text(verbatim: "debug_homeReturn own=\(debug.own) foc=\(debug.foc) ret=\(debug.ret)")
            .font(.system(size: 8))
            .opacity(0.011)
            .accessibilityIdentifier("debug_homeReturn")
            .allowsHitTesting(false)
    }
}
#endif
