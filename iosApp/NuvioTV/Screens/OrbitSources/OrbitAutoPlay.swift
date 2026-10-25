import Combine
import Foundation
import SharedCore

// Orbit's automatic source start (Steven's fork, 2026-10-25), rewritten from scratch.
//
// Settings › Lecture automatique on: when the source page opens, the shared streams repository
// asks the add-ons and ranks what they return (quality, cached on the debrid service, the same
// release as the last episode); this keeps that ranking (it is shared with the phone app) and does
// the rest on the Apple TV:
//  1. wait for the repository to settle its best candidate and the ordered fallbacks;
//  2. drop the links that failed recently, and the uncached ones under "Sources en cache uniquement";
//  3. try them in order: a direct link plays at once, a debrid one is prepared first (20 s at most);
//  4. a link that will not prepare is remembered as failed for a while, and the next one is tried
//     (the same add-on first), up to `PlaybackFailoverPolicy.maxAutoAttempts` tries;
//  5. a player that fails later (`continueAfterFailure`) continues the same walk.
// The page acts on `events`: play a pick, or show the list when nothing could start.

/// The repository's auto-play fields for the page's request, as one value (`StreamsViewModel`).
struct OrbitAutoPlayFeed: Equatable {
    var requestToken: String?
    var autoPlayStream: StreamItem?
    var autoPlayCandidates: [StreamItem]
    var isDirectAutoPlayFlow: Bool
    var isAnyLoading: Bool
    /// The request has produced something (add-on groups, or an empty-state reason).
    var hasOutcome: Bool

    static var empty: OrbitAutoPlayFeed {
        OrbitAutoPlayFeed(requestToken: nil, autoPlayStream: nil, autoPlayCandidates: [],
                          isDirectAutoPlayFlow: false, isAnyLoading: false, hasOutcome: false)
    }
}

@MainActor
final class OrbitAutoPlay: ObservableObject {
    enum Phase: Equatable {
        case idle, searching, preparing, playing, stopped
    }

    /// A source ready to play.
    struct Pick {
        /// The stream as listed (before a debrid resolve): the failed-link memory's identity.
        let listed: StreamItem
        let resolved: StreamItem
        let url: URL
        /// 1-based.
        let attempt: Int
        /// It replaces a player that failed (the page swaps it in place).
        let isFailover: Bool
        var streamKey: String { listed.playbackStreamKey }
    }

    enum Event {
        case play(Pick)
        /// Nothing could start: show the list.
        case gaveUp(duringFailover: Bool)
    }

    @Published private(set) var phase: Phase = .idle
    let events = PassthroughSubject<Event, Never>()

    /// The walk continues after a failed playback.
    private(set) var isFailoverWalk = false

    private let type: String
    private let videoId: String
    private let season: KotlinInt?
    private let episode: KotlinInt?

    private var candidates: [StreamItem] = []
    private var triedIndices: Set<Int> = []
    private var triedKeys: Set<String> = []
    private var attempts = 0
    private var sawDirectFlow = false
    /// Bumped on every step: a late resolve (or timeout) from an older one is ignored.
    private var generation = 0
    private var timeout: Task<Void, Never>?

    private static let searchDeadline: TimeInterval = 40
    private static let prepareDeadline: TimeInterval = 20

    init(type: String, videoId: String, season: Int?, episode: Int?) {
        self.type = type
        self.videoId = videoId
        self.season = season.map { KotlinInt(int: Int32($0)) }
        self.episode = episode.map { KotlinInt(int: Int32($0)) }
    }

    /// Settings › Lecture automatique.
    static var isEnabled: Bool {
        PlayerSettingsRepository.shared.ensureLoaded()
        let settings = PlayerSettingsRepository.shared.uiState.value_ as? PlayerSettingsUiState
        return settings?.streamAutoPlayMode == StreamAutoPlayMode.firstStream
    }

    // MARK: - Lifecycle

    /// Once, before the page's first load.
    func start() {
        guard phase == .idle else { return }
        phase = .searching
        log("start \(videoId)")
        arm(deadline: Self.searchDeadline) { [weak self] in
            guard let self, self.phase == .searching else { return }
            self.log("nothing settled within \(Int(Self.searchDeadline)) s")
            self.giveUp()
        }
    }

    /// One `StreamsViewModel.autoPlayFeed` value; acts only while searching.
    func ingest(_ feed: OrbitAutoPlayFeed) {
        guard phase == .searching else { return }
        let expected = StreamsRepository.shared.requestToken(
            type: type, videoId: videoId, season: season, episode: episode, manualSelection: false)
        guard feed.requestToken == expected else { return }
        if feed.isDirectAutoPlayFlow { sawDirectFlow = true }

        if let best = feed.autoPlayStream {
            var streams = feed.autoPlayCandidates
            if !streams.contains(best) { streams.insert(best, at: 0) }
            StreamsRepository.shared.consumeAutoPlay()
            walk(streams)
        } else if !feed.isDirectAutoPlayFlow, feed.hasOutcome, !feed.isAnyLoading || sawDirectFlow {
            log("the repository settled nothing")
            giveUp()
        }
    }

    /// Menu on the loading screen, or the player closed while the next source prepared.
    func cancel() {
        guard phase == .searching || phase == .preparing else { return }
        generation += 1
        timeout?.cancel()
        phase = .stopped
        log("cancelled after \(attempts) attempt(s)")
    }

    /// A player this started failed: the next candidate, the failed link's add-on first. False when
    /// there is no walk to continue.
    func continueAfterFailure(of streamKey: String, addonId: String?) -> Bool {
        guard phase == .playing, !candidates.isEmpty else { return false }
        if !streamKey.isEmpty { triedKeys.insert(streamKey) }
        isFailoverWalk = true
        log("playback failed — next source (\(attempts)/\(PlaybackFailoverPolicy.maxAutoAttempts) used)")
        tryNext(preferring: addonId)
        return true
    }

    // MARK: - Walk

    private func walk(_ streams: [StreamItem]) {
        timeout?.cancel()
        let rejected = RejectedStreamLinks.rejected(for: videoId)
        let cachedOnly = (PlayerSettingsRepository.shared.uiState.value_ as? PlayerSettingsUiState)?
            .streamAutoPlayCachedOnly ?? false
        candidates = streams.filter { stream in
            let key = stream.playbackStreamKey
            if !key.isEmpty, rejected.contains(key) { return false }
            if cachedOnly, !Self.isCachedOnDebrid(stream) { return false }
            return true
        }
        log("candidates=\(streams.count) eligible=\(candidates.count) cachedOnly=\(cachedOnly)")
        tryNext(preferring: nil)
    }

    private func tryNext(preferring addonId: String?) {
        while true {
            guard attempts < PlaybackFailoverPolicy.maxAutoAttempts, let index = nextIndex(preferring: addonId) else {
                giveUp()
                return
            }
            let stream = candidates[index]
            triedIndices.insert(index)
            let key = stream.playbackStreamKey
            if !key.isEmpty { triedKeys.insert(key) }

            let direct: String? = stream.playableDirectUrl
            if let direct, !direct.isEmpty, let url = URL(string: direct) {
                attempts += 1
                play(listed: stream, resolved: stream, url: url)
                return
            }
            // A YouTube-only stream is never auto-resolved (its link expires within hours), and a
            // debrid link this Apple TV cannot prepare is skipped without counting against it.
            guard DirectDebridPlaybackResolver.shared.shouldResolveToPlayableStream(stream: stream) else { continue }
            attempts += 1
            prepare(stream)
            return
        }
    }

    /// The first untried, non-rejected candidate, from `addonId` when it still has one.
    private func nextIndex(preferring addonId: String?) -> Int? {
        let rejected = RejectedStreamLinks.rejected(for: videoId)
        let open = candidates.indices.filter { index in
            guard !triedIndices.contains(index) else { return false }
            let key = candidates[index].playbackStreamKey
            return key.isEmpty || (!triedKeys.contains(key) && !rejected.contains(key))
        }
        if let addonId, let same = open.first(where: { candidates[$0].addonId == addonId }) { return same }
        return open.first
    }

    private func prepare(_ stream: StreamItem) {
        phase = .preparing
        generation += 1
        let step = generation
        let season = season
        let episode = episode
        log("preparing #\(attempts) key=\(stream.playbackStreamKey)")
        Task { [weak self] in
            var outcome: (resolved: StreamItem, url: URL)?
            var blameLink = true
            do {
                let result = try await DirectDebridPlaybackResolver.shared.resolveToPlayableStreamChecked(
                    stream: stream, season: season, episode: episode)
                if let success = result as? DirectDebridPlayableResult.Success {
                    let link: String? = success.stream.playableDirectUrl
                    if let link, !link.isEmpty, let url = URL(string: link) { outcome = (success.stream, url) }
                } else if result is DirectDebridPlayableResult.MissingApiKey || result is DirectDebridPlayableResult.Stale {
                    blameLink = false   // the account, or a link for another provider: not the link's fault
                }
            } catch {
                blameLink = PlaybackFailureClassifier.fromNSError(error, origin: .remote).kind.remembersLink
            }
            self?.finishPreparing(step, stream, outcome, blameLink: blameLink)
        }
        arm(deadline: Self.prepareDeadline) { [weak self] in
            // A slow service or network is not proof the link is dead.
            self?.finishPreparing(step, stream, nil, blameLink: false)
        }
    }

    private func finishPreparing(_ step: Int, _ stream: StreamItem, _ outcome: (resolved: StreamItem, url: URL)?,
                                 blameLink: Bool) {
        guard step == generation, phase == .preparing else { return }
        generation += 1
        timeout?.cancel()
        if let outcome {
            play(listed: stream, resolved: outcome.resolved, url: outcome.url)
            return
        }
        log("attempt #\(attempts) failed key=\(stream.playbackStreamKey) blame=\(blameLink)")
        // Offline, every provider fails: never blame the links then.
        if blameLink, NetworkPathMonitor.shared.isSatisfied {
            RejectedStreamLinks.reject(stream.playbackStreamKey, title: videoId)
            if stream.isAddonDebridCandidate {
                DirectDebridPlaybackResolver.shared.invalidate(stream: stream, season: season, episode: episode)
            }
        }
        tryNext(preferring: stream.addonId)
    }

    private func play(listed: StreamItem, resolved: StreamItem, url: URL) {
        timeout?.cancel()
        generation += 1
        phase = .playing
        log("play #\(attempts) key=\(listed.playbackStreamKey) failover=\(isFailoverWalk)")
        events.send(.play(Pick(listed: listed, resolved: resolved, url: url, attempt: attempts,
                               isFailover: isFailoverWalk)))
    }

    private func giveUp() {
        timeout?.cancel()
        generation += 1
        phase = .stopped
        log("gave up after \(attempts) attempt(s)")
        events.send(.gaveUp(duringFailover: isFailoverWalk))
    }

    private func arm(deadline: TimeInterval, _ fire: @escaping @MainActor () -> Void) {
        timeout?.cancel()
        timeout = Task {
            try? await Task.sleep(for: .seconds(deadline))
            guard !Task.isCancelled else { return }
            fire()
        }
    }

    // MARK: - Helpers

    /// A link the active debrid service already has cached.
    private static func isCachedOnDebrid(_ stream: StreamItem) -> Bool {
        let debrid = DebridSettingsRepository.shared.snapshot()
        guard debrid.canResolvePlayableLinks, stream.isAddonDebridCandidate else { return false }
        let active: String? = debrid.activeResolverProviderId
        func matches(_ value: String?) -> Bool {
            let wanted = (active ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wanted.isEmpty, let value else { return true }
            return value.caseInsensitiveCompare(wanted) == .orderedSame
        }
        if stream.isDirectDebridStream {
            let service: String? = stream.clientResolve?.service
            return matches(service)
        }
        if stream.isCachedDebridTorrentStream {
            let provider: String? = stream.debridCacheStatus?.providerId
            return matches(provider)
        }
        return false
    }

    /// Keys, counts and reasons only: never a link or an add-on id (they can hold an API key).
    private func log(_ line: String) {
        NSLog("%@", "[AutoPlay] \(line)")
    }
}
