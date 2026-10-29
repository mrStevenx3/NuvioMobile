import AVKit
import OrbitEngine
import SharedCore
import SwiftUI
import UIKit

/// Every playback in Orbit (Steven's fork, 2026-10-25): Apple's player fed by AetherEngine
/// (`OrbitPlayerSession`, `OrbitPlayerViewController`), with Orbit's loading cover, pause card,
/// skip-intro and up-next on top. Call sites are unchanged.
struct PlayerScreen: View {
    let context: PlaybackContext
    var onPlayNext: ((PlaybackContext) -> Void)? = nil
    /// The playback failed; the host decides what plays next.
    var onPlaybackFailed: ((PlaybackFailure) -> Void)? = nil
    /// Fired once when the link has played `PlaybackFailoverPolicy.healthySeconds`.
    var onPlaybackHealthy: ((Double) -> Void)? = nil
    /// Kept for the call sites (Chris's post-play row is gone).
    var onOpenTitle: ((MetaPreview) -> Void)? = nil
    /// Steven (2026-10-28: the loading screen blinked — the sources' loading screen, then the
    /// player's own, black while its art loaded, then the film): opened over the sources' loading
    /// screen, the player stays see-through until its first picture — that one screen is all
    /// that shows until the film. `onPictureShown` tells the host when.
    var overLoadingCover = false
    var onPictureShown: () -> Void = {}

    @StateObject private var session: OrbitPlayerSession
    @StateObject private var upNext: NextEpisodeEngine
    @State private var skipPlanner = SkipSegmentPlanner()
    @State private var skipPrompt: SkipPrompt?
    @State private var pauseCardShown = false
    /// Steven (2026-10-29: the loading screen cut to the film at once): it goes on a soft fade to the
    /// film's first picture — never inside the presentation's first moment (UIKit's animations are
    /// off then, which made the fade a cut), so a stream that starts at once still fades.
    @State private var loadingGone = false
    @State private var loadingRemoved = false
    /// When the reveal of the film began (nil: the loading screen still whole).
    @State private var revealStart: Date?
    static let revealTime: Double = 0.9

    /// The TV is changing its picture mode (match frame rate / dynamic range).
    @MainActor static func displaySwitching() -> Bool {
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows where window.avDisplayManager.isDisplayModeSwitchInProgress { return true }
        }
        return false
    }
    @State private var appearedAt = ProcessInfo.processInfo.systemUptime
    @State private var pauseCardTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    init(context: PlaybackContext,
         onPlayNext: ((PlaybackContext) -> Void)? = nil,
         onPlaybackFailed: ((PlaybackFailure) -> Void)? = nil,
         onPlaybackHealthy: ((Double) -> Void)? = nil,
         onOpenTitle: ((MetaPreview) -> Void)? = nil,
         overLoadingCover: Bool = false,
         onPictureShown: @escaping () -> Void = {}) {
        self.overLoadingCover = overLoadingCover
        self.onPictureShown = onPictureShown
        self.context = context
        self.onPlayNext = onPlayNext
        self.onPlaybackFailed = onPlaybackFailed
        self.onPlaybackHealthy = onPlaybackHealthy
        self.onOpenTitle = onOpenTitle
        _session = StateObject(wrappedValue: OrbitPlayerSession(context: context))
        _upNext = StateObject(wrappedValue: NextEpisodeEngine(context: context, onPlayNext: onPlayNext ?? { _ in }))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            OrbitPlayerContainer(
                session: session,
                skip: skipPrompt,
                upNext: upNextAction,
                onSkip: { target in skipSeek(to: target, kind: .chip) },
                onPlayNow: { _ = upNext.playNow() },
                onDismissUpNext: { _ = upNext.dismissIfVisible() },
                onMenu: { upNext.dismissIfVisible() }
            )
            .ignoresSafeArea()

            if pauseCardShown {
                OrbitPauseCard(context: context, session: session)
                    .transition(.opacity)
            }

            if let caption = upNextCaption {
                OrbitUpNextCard(caption: caption, title: upNext.nextEpisodeTitle)
                    .transition(.opacity)
            }

            // (Steven's video: a see-through player showed black — tvOS keeps its own ground under
            // the cover. The player opens on the very same loading screen instead, already lit.)
            if !loadingRemoved {
                // Steven (2026-10-29: "comme si le titre dévoilait l'ouverture du film… à toi de me
                // surprendre"; his videos: every animated exit came out as a cut): the film opens out of
                // its title — the logo rushes towards the viewer while a hole opens from its centre and
                // widens to the screen's edges, the film showing through it. Drawn frame by frame from
                // the clock (a timeline), so no presentation or transaction can turn it into a cut.
                // (Steven, 2026-10-29: no reveal effect — the logo, lit, simply gives way to the film.)
                OrbitLoadingView(title: context.title, logoUrl: context.logo, backdropUrl: context.background,
                                 lightsUp: !overLoadingCover)
                    .opacity(loadingGone ? 0 : 1)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: pauseCardShown)
        .animation(.easeInOut(duration: 0.25), value: upNext.phase)
        .onAppear {
            appearedAt = ProcessInfo.processInfo.systemUptime
            start()
        }
        .onChange(of: session.firstFrameShown) { _, shown in
            if shown {
                onPictureShown()
                // Steven (2026-10-29: "aucun effet"; his video: the screen black for two seconds at the
                // film's first picture): the TV was switching its picture mode (frame rate, HDR) right
                // then — the reveal played on a blank screen. It waits for the switch to be over.
                let wait = max(0.35, appearedAt + 0.55 - ProcessInfo.processInfo.systemUptime)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(wait))
                    let since = ProcessInfo.processInfo.systemUptime
                    while Self.displaySwitching(), ProcessInfo.processInfo.systemUptime - since < 6 {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    if ProcessInfo.processInfo.systemUptime - since > 0.05 {
                        // (The picture back after a switch: a moment for the TV to show it.)
                        try? await Task.sleep(for: .milliseconds(350))
                    }
                    withAnimation(.easeInOut(duration: 0.5)) { loadingGone = true }
                    try? await Task.sleep(for: .seconds(0.55))
                    loadingRemoved = true
                }
            } else {
                loadingGone = false
                loadingRemoved = false
                revealStart = nil
            }
        }
        .onDisappear {
            pauseCardTask?.cancel()
            session.stop()
            upNext.stop()
        }
        .onChange(of: session.phase) { _, phase in
            guard case .failed = phase else { return }
            if let failure = session.failure { onPlaybackFailed?(failure) }
            dismiss()
        }
        .onChange(of: session.ended) { _, ended in
            // The next episode takes over when its card is up; otherwise back to the page.
            if ended, upNext.phase == .hidden { dismiss() }
        }
        .onChange(of: session.isPaused) { _, paused in pauseChanged(paused) }
    }

    // MARK: - Start

    private func start() {
        session.onTick = { position, duration in
            upNext.onProgress(positionSec: position, durationSec: duration)
            updateSkipPrompt(position: position, duration: duration)
        }
        // Deliberate entries (the resume seek, a scrub) are never auto-skipped.
        session.onPositionJump = { from, to in
            _ = skipPlanner.observeTick(fromSec: from, toSec: to, now: ProcessInfo.processInfo.systemUptime)
        }
        session.onResumeSeek = { target in
            skipPlanner.beginSeek(kind: .resume, targetSec: target, now: ProcessInfo.processInfo.systemUptime)
        }
        session.onResumeLanded = { landed in
            skipPlanner.seekCompleted(atSec: landed, now: ProcessInfo.processInfo.systemUptime)
        }
        session.onPlaybackHealthy = onPlaybackHealthy
        session.start()
        if onPlayNext != nil { upNext.startNative() }
        fetchSkipSegments()
    }

    // MARK: - Pause card

    private func pauseChanged(_ paused: Bool) {
        pauseCardTask?.cancel()
        guard paused else {
            pauseCardShown = false
            return
        }
        pauseCardTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled, session.isPaused, session.firstFrameShown else { return }
            pauseCardShown = true
        }
    }

    // MARK: - Up next

    private var upNextAction: OrbitUpNextAction? {
        switch upNext.phase {
        case .counting: return .playNext
        case .stillWatching: return .continueWatching
        default: return nil
        }
    }

    private var upNextCaption: String? {
        switch upNext.phase {
        case .hidden: return nil
        case .searching: return String(localized: "Recherche de l'épisode suivant…")
        case .counting(let seconds): return String(localized: "Lecture dans \(seconds)")
        case .stillWatching: return String(localized: "Vous regardez toujours ?")
        case .noStream: return String(localized: "Aucune source trouvée pour l'épisode suivant.")
        }
    }

    // MARK: - Skip intro / recap / credits

    private func fetchSkipSegments() {
        if let season = context.season, let episode = context.episode {
            SkipIntroRepository.shared.getSkipIntervalsForContentId(
                contentId: context.parentMetaId,
                season: Int32(season),
                episode: Int32(episode),
                requireSkipIntroEnabled: true
            ) { intervals, _ in
                let list = intervals ?? []
                DispatchQueue.main.async { applySkipIntervals(list) }
            }
        } else if context.contentType.lowercased() == "movie" {
            SkipIntroRepository.shared.getMovieSkipIntervals(
                contentId: context.parentMetaId,
                videoId: context.videoId,
                requireSkipIntroEnabled: true
            ) { intervals, _ in
                let list = intervals ?? []
                DispatchQueue.main.async { applySkipIntervals(list) }
            }
        }
    }

    private func applySkipIntervals(_ intervals: [SkipInterval]) {
        guard !intervals.isEmpty else { return }
        skipPlanner.setIntervals(intervals)
        upNext.skipIntervals = intervals
    }

    private func updateSkipPrompt(position: Double, duration: Double) {
        let settings = PlayerSettingsRepository.shared.uiState.value_ as? PlayerSettingsUiState
        let autoSkipTypes: [AutoSkipSegmentType]? = settings.flatMap { $0.skipIntroEnabled ? Array($0.autoSkipSegmentTypes) : nil }
        let decision = skipPlanner.evaluate(positionSec: position, durationSec: duration,
                                            isPlaying: !session.isPaused, autoSkipTypes: autoSkipTypes,
                                            now: ProcessInfo.processInfo.systemUptime)
        if let target = decision.autoSkipTargetSec { skipSeek(to: target, kind: .auto) }
        if decision.prompt != skipPrompt { skipPrompt = decision.prompt }
    }

    private func skipSeek(to target: Double, kind: SkipSegmentPlanner.SeekKind) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        skipPlanner.beginSeek(kind: kind, targetSec: target, fromSec: session.positionSec, now: startedAt)
        if skipPrompt != nil { skipPrompt = nil }
        Task { @MainActor in
            await session.seek(to: target)
            guard skipPlanner.seekInFlight?.startedAt == startedAt else { return }
            skipPlanner.seekCompleted(atSec: target, now: ProcessInfo.processInfo.systemUptime)
        }
    }
}
