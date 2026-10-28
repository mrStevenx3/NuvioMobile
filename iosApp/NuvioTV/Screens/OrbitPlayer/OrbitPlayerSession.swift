import AVFoundation
import AVKit
import Combine
import OrbitEngine
import SharedCore
import UIKit

// Orbit's player (Steven's fork, 2026-10-25), written from scratch. Chris's two engines (libmpv and
// his own MKV → HLS remux) are gone; AetherEngine opens every source with FFmpeg and hands the
// picture and the sound to Apple's player, so Dolby Vision, HDR10(+), HLG, Atmos and the Apple TV's
// "match content" all stay the system's. TrueHD Atmos and DTS:X keep their heights (rendered to
// Apple's spatial audio, sent to the receiver as Dolby MAT).
//
// The session owns the engine and everything around playback that is not drawn: resume, watch
// progress and Trakt (`PlaybackProgressRecorder`), the skip-intro planner, the up-next ticks, the
// failure report. The screen (`PlayerScreen`) draws; the controller (`OrbitPlayerViewController`) is
// Apple's player.

@MainActor
final class OrbitPlayerSession: ObservableObject {
    enum Phase: Equatable {
        case loading
        case playing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    /// The first picture is on screen: the loading cover comes off.
    @Published private(set) var firstFrameShown = false
    @Published private(set) var isPaused = false
    @Published private(set) var ended = false
    @Published private(set) var audioTracks: [TrackInfo] = []
    @Published private(set) var activeAudioTrackId: Int?
    @Published private(set) var videoFormat: VideoFormat = .sdr
    /// Seconds, refreshed once a second (for the pause card's "ends at").
    @Published private(set) var positionSec: Double = 0
    @Published private(set) var durationSec: Double = 0

    let context: PlaybackContext
    let engine: AetherEngine?

    /// Once a second while playing: (position, duration).
    var onTick: ((Double, Double) -> Void)?
    /// Every clock update: (previous position, new position), for the skip planner's jump detection.
    var onPositionJump: ((Double, Double) -> Void)?
    /// The resume seek was issued / landed.
    var onResumeSeek: ((Double) -> Void)?
    var onResumeLanded: ((Double) -> Void)?
    /// Played `PlaybackFailoverPolicy.healthySeconds`: the link is good.
    var onPlaybackHealthy: ((Double) -> Void)?

    private(set) var secondsPlayed: Double = 0
    private(set) var startedPlaying = false
    private(set) var failure: PlaybackFailure?

    private let recorder: PlaybackProgressRecorder
    private var bag = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?
    private var lastClock: Double?
    private var lastTickAt: TimeInterval = 0
    private var lastSaveAt: TimeInterval = 0
    private var resumeTarget: Double?
    /// Where the film starts (0, or the resume point).
    private var startPoint: Double = 0
    private var trackersStarted = false
    private var healthyReported = false
    private var stopped = false

    init(context: PlaybackContext) {
        self.context = context
        self.recorder = PlaybackProgressRecorder(context: context)
        self.engine = try? AetherEngine()
    }

    // MARK: - Lifecycle

    func start() {
        guard loadTask == nil else { return }
        guard let engine else {
            fail(String(localized: "Le lecteur n'a pas pu démarrer."), kind: .local)
            return
        }
        observe(engine)
        stageMetadata(on: engine)

        let start = resumePosition()
        resumeTarget = start
        startPoint = start ?? 0
        let options = loadOptions()
        let url = context.url
        if let start { onResumeSeek?(start) }
        loadTask = Task { [weak self] in
            do {
                try await engine.load(url: url, startPosition: start, options: options)
            } catch is CancellationError {
                // Superseded or closed: nothing to report.
            } catch {
                self?.fail(error.localizedDescription, kind: .unknown)
            }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        loadTask?.cancel()
        if startedPlaying {
            recorder.record(positionSec: positionSec, durationSec: durationSec, isPaused: true, speed: 1, flush: true)
            recorder.stopTrakt(positionSec: positionSec, durationSec: durationSec)
            recorder.stopTrackers(positionSec: positionSec, durationSec: durationSec)
        }
        engine?.stop()
        bag.removeAll()
    }

    // MARK: - Controls

    func togglePlayPause() { engine?.togglePlayPause() }

    func seek(to seconds: Double) async {
        await engine?.seek(to: seconds)
    }

    func selectAudioTrack(id: Int) {
        engine?.selectAudioTrack(index: id)
    }

    /// The playing audio track (for the badges).
    var activeAudioTrack: TrackInfo? {
        audioTracks.first { $0.id == activeAudioTrackId }
    }

    // MARK: - Load

    private func resumePosition() -> Double? {
        if let at = context.resumeAtSec, at > 10 { return at }
        if context.startFromBeginning { return nil }
        guard let saved = recorder.resumePositionSec(), saved > 5 else { return nil }
        return saved
    }

    private func loadOptions() -> LoadOptions {
        let settings = PlayerSettingsRepository.shared.uiState.value_ as? PlayerSettingsUiState
        let device = DeviceLanguagePreferences.shared.preferredLanguageCodes()
        var audioLanguages: [String] = []
        var subtitleLanguages: [String] = []
        if let settings {
            audioLanguages = PlayerLanguagePreferencesKt.resolvePreferredAudioLanguageTargets(
                preferredAudioLanguage: settings.preferredAudioLanguage,
                secondaryPreferredAudioLanguage: settings.secondaryPreferredAudioLanguage,
                deviceLanguages: device,
                contentOriginalLanguage: PlayerAudioLanguagePlan.originalLanguage(for: context))
            subtitleLanguages = PlayerLanguagePreferencesKt.resolvePreferredSubtitleLanguageTargets(
                preferredSubtitleLanguage: settings.preferredSubtitleLanguage,
                secondaryPreferredSubtitleLanguage: settings.secondaryPreferredSubtitleLanguage,
                deviceLanguages: device)
        }
        let external: [ExternalSubtitleTrack] = context.externalSubtitles.compactMap { file in
            guard let url = URL(string: file.url) else { return nil }
            return ExternalSubtitleTrack(url: url, name: file.name, language: file.language)
        }
        let matchContent = UserDefaults.standard.object(forKey: PlayerTuning.matchFrameRateKey) as? Bool ?? true
        let heights = UserDefaults.standard.object(forKey: OrbitPlayerSettings.objectAudioKey) as? Bool ?? true
        return LoadOptions(
            httpHeaders: context.requestHeaders,
            matchContentEnabled: matchContent,
            objectAudioRendering: heights ? .apac(.l714) : .off,
            prepareNativeSubtitles: true,
            eagerNativeSubtitleReaders: true,
            serveIFramePlaylist: true,
            nativeSubtitlePreferredLanguages: subtitleLanguages,
            preferredAudioLanguages: audioLanguages,
            preferredSubtitleLanguages: subtitleLanguages,
            externalSubtitles: external
        )
    }

    /// Title, episode line, synopsis and poster for Apple's info panel and Now Playing.
    private func stageMetadata(on engine: AetherEngine) {
        var items: [AVMetadataItem] = [Self.item(.commonIdentifierTitle, context.title as NSString)]
        if let line = OrbitPlayerText.episodeLine(context) {
            items.append(Self.item(.iTunesMetadataTrackSubTitle, line as NSString))
        }
        if let synopsis = context.synopsis, !synopsis.isEmpty {
            items.append(Self.item(.commonIdentifierDescription, synopsis as NSString))
        }
        engine.setExternalMetadata(items)
        let staged = items

        guard let poster = context.poster, let url = URL(string: poster) else { return }
        Task { [weak self] in
            guard let result = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: result.0), let png = image.pngData(),
                  let self, let engine = self.engine
            else { return }
            let artwork = Self.item(.commonIdentifierArtwork, png as NSData)
            engine.setExternalMetadata(staged + [artwork])
        }
    }

    private static func item(_ identifier: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value
        item.extendedLanguageTag = "und"
        return item
    }

    // MARK: - Engine state

    private func observe(_ engine: AetherEngine) {
        engine.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.stateChanged(state) }
            .store(in: &bag)
        engine.$hasFirstFrameReadyForDisplay
            .receive(on: RunLoop.main)
            .sink { [weak self] ready in
                guard let self, ready, !self.firstFrameShown else { return }
                self.firstFrameShown = true
                // Steven (2026-10-28: back to the start of a film just launched, its first seconds
                // of sound had gone by under the loading screen): the sound plays before the first
                // picture is up — once it is, the film goes back to where it started.
                let point = self.startPoint
                Task { [weak self] in await self?.engine?.seek(to: point) }
                if let target = self.resumeTarget {
                    self.resumeTarget = nil
                    self.onResumeLanded?(target)
                }
            }
            .store(in: &bag)
        engine.$audioTracks
            .receive(on: RunLoop.main)
            .sink { [weak self] tracks in self?.audioTracks = tracks }
            .store(in: &bag)
        engine.$activeAudioTrackIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] id in self?.activeAudioTrackId = id }
            .store(in: &bag)
        engine.$videoFormat
            .receive(on: RunLoop.main)
            .sink { [weak self] format in self?.videoFormat = format }
            .store(in: &bag)
        engine.$duration
            .receive(on: RunLoop.main)
            .sink { [weak self] duration in
                if duration.isFinite, duration > 0 { self?.durationSec = duration }
            }
            .store(in: &bag)
        engine.clock.$currentTime
            .receive(on: RunLoop.main)
            .sink { [weak self] time in self?.clockTick(time) }
            .store(in: &bag)
        // Steven: turning subtitles on in Apple's menu did nothing, they went back to off. The
        // engine holds Apple's subtitle choice off (it expects the app to draw subtitles itself) and
        // only reports what was asked; Orbit lets Apple's player draw them, so the pick is handed back
        // to the engine as the app's own — from then on the choice is the viewer's.
        engine.systemCaptionRequest
            .receive(on: RunLoop.main)
            .sink { [weak engine] request in
                guard let engine else { return }
                let tracks = engine.nativeSubtitleTracks
                let wanted = Self.primaryLanguage(request.language)
                let ordinal = tracks.first { Self.primaryLanguage($0.language) == wanted && wanted != nil }?.ordinal
                    ?? (tracks.count == 1 ? tracks[0].ordinal : nil)
                guard let ordinal else { return }
                engine.setNativeSubtitleSelected(track: ordinal)
            }
            .store(in: &bag)
    }

    /// "fre", "fra", "fr-FR" → "fr" (the forms the stream and Apple's player each use).
    nonisolated static func primaryLanguage(_ tag: String?) -> String? {
        guard let tag, !tag.isEmpty, tag != "und" else { return nil }
        let head = String(tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? Substring(tag)).lowercased()
        let bibliographic = ["fre": "fr", "ger": "de", "dut": "nl", "chi": "zh", "cze": "cs", "gre": "el",
                             "per": "fa", "rum": "ro", "slo": "sk", "alb": "sq", "arm": "hy", "baq": "eu",
                             "bur": "my", "geo": "ka", "ice": "is", "mac": "mk", "mao": "mi", "may": "ms",
                             "tib": "bo", "wel": "cy"]
        if let mapped = bibliographic[head] { return mapped }
        if head.count == 3, let alpha2 = Locale.LanguageCode(head).identifier(.alpha2) { return alpha2 }
        return head
    }

    private func stateChanged(_ state: PlaybackState) {
        switch state {
        case .playing:
            isPaused = false
            if phase == .loading { phase = .playing }
            if !startedPlaying {
                startedPlaying = true
            }
            if !trackersStarted, durationSec > 0 {
                trackersStarted = true
                recorder.startTrakt(positionSec: positionSec, durationSec: durationSec)
                recorder.startTrackers(positionSec: positionSec, durationSec: durationSec)
            }
        case .paused:
            isPaused = true
            if phase == .loading, firstFrameShown { phase = .playing }
            if startedPlaying {
                recorder.record(positionSec: positionSec, durationSec: durationSec, isPaused: true, speed: 1, flush: true)
            }
        case .ended:
            ended = true
        case .error(let message):
            let info = engine?.errorInfo
            fail(message, kind: Self.failureKind(info), httpStatus: info?.kind == .sourceRefused ? info?.underlyingCode : nil)
        case .idle, .loading, .seeking:
            break
        }
    }

    private func clockTick(_ time: Double) {
        guard time.isFinite else { return }
        if let last = lastClock {
            onPositionJump?(last, time)
            let delta = time - last
            if !isPaused, delta > 0, delta < 2 { secondsPlayed += delta }
        }
        lastClock = time

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTickAt >= 1 else { return }
        lastTickAt = now
        positionSec = time
        guard durationSec > 0 else { return }
        onTick?(time, durationSec)

        if startedPlaying, now - lastSaveAt >= 5 {
            lastSaveAt = now
            recorder.record(positionSec: time, durationSec: durationSec, isPaused: isPaused, speed: 1, flush: false)
        }
        if !healthyReported, secondsPlayed >= PlaybackFailoverPolicy.healthySeconds {
            healthyReported = true
            onPlaybackHealthy?(secondsPlayed)
        }
    }

    private func fail(_ message: String, kind: PlaybackFailureKind, httpStatus: Int? = nil) {
        guard failure == nil, !stopped else { return }
        failure = PlaybackFailure(reason: message, positionSec: positionSec, secondsPlayed: secondsPlayed,
                                  startedPlaying: startedPlaying, kind: kind, httpStatus: httpStatus)
        phase = .failed(message)
    }

    private static func failureKind(_ info: PlaybackErrorInfo?) -> PlaybackFailureKind {
        guard let info else { return .unknown }
        switch info.kind {
        case .sourceRefused, .sourceRateLimited: return .http
        case .sourceOpenFailed:
            return info.underlyingDomain == NSURLErrorDomain ? .network : .noMedia
        case .softwarePipelineFailed, .nativeItemFailed, .masterPlaylistRejected,
             .audioBridgeProducedNoOutput, .reloadFailed, .audioSessionFailed:
            return .local
        default: return .unknown
        }
    }
}

/// Orbit's player settings (Lecture).
enum OrbitPlayerSettings {
    /// TrueHD Atmos / DTS:X with their heights (default on).
    static let objectAudioKey = "orbit_player_object_audio"
}

/// The player's French copy.
enum OrbitPlayerText {
    /// "S2 · É5 — Title" for an episode, nil for a film.
    static func episodeLine(_ context: PlaybackContext) -> String? {
        guard let season = context.season, let episode = context.episode else { return nil }
        return "S\(season) · É\(episode)"
    }

    /// "Français · Dolby Atmos", "Anglais · 5.1"…
    static func audioLabel(_ track: TrackInfo) -> String {
        var language = track.name
        if let code = track.language, !code.isEmpty, code != "und",
           let name = Locale(identifier: "fr_FR").localizedString(forLanguageCode: code) {
            language = name.prefix(1).uppercased() + name.dropFirst()
        }
        if language.isEmpty { language = String(localized: "Piste \(track.id)") }
        return "\(language) · \(audioFormat(track))"
    }

    static func audioFormat(_ track: TrackInfo) -> String {
        let profile = (track.profile ?? "").lowercased()
        if track.isAtmos || profile.contains("atmos") { return "Dolby Atmos" }
        if track.isDTSX || profile.contains("dts:x") { return "DTS:X" }
        switch track.channels {
        case 0: return track.codec.uppercased()
        case 1: return "Mono"
        case 2: return String(localized: "Stéréo")
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(track.channels) canaux"
        }
    }

    static func hasHeights(_ track: TrackInfo?) -> Bool {
        guard let track else { return false }
        let profile = (track.profile ?? "").lowercased()
        return track.isAtmos || track.isDTSX || profile.contains("atmos") || profile.contains("dts:x")
    }

    static func videoBadge(_ format: VideoFormat) -> String? {
        switch format {
        case .dolbyVision: return "DOLBY VISION"
        case .hdr10Plus: return "HDR10+"
        case .hdr10: return "HDR10"
        case .hlg: return "HLG"
        case .sdr: return nil
        }
    }

    /// "Se termine à 0 h 26".
    static func endsAt(remainingSec: Double) -> String? {
        guard remainingSec.isFinite, remainingSec > 0 else { return nil }
        let end = Date().addingTimeInterval(remainingSec)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: end)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return String(localized: "Se termine à \(hour) h \(String(format: "%02d", minute))")
    }
}
