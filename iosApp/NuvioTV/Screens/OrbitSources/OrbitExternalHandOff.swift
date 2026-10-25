import Foundation
import SharedCore
import UIKit

// Handing a source to Infuse or Native Player (Steven's fork, 2026-10-25, rewritten): the link, the
// resume position, the subtitles (the stream's own, then the add-ons', the preferred language
// first), and — for players that report back — the x-callback return that records where the
// viewer stopped (`ExternalPlaybackReturn`).

@MainActor
enum OrbitExternalHandOff {
    struct Request {
        let url: String
        let stream: StreamItem
        let title: String
        let type: String
        let videoId: String
        let season: Int?
        let episode: Int?
        let resumeMs: Int64
        /// For the return session: the playback it records (nil: no return).
        let session: WatchProgressPlaybackSession?
        let durationMs: Int64?
    }

    /// Players that report the stop position back.
    static let reportingPlayers: Set<String> = ["infuse", "nativeplayer"]
    private static let subtitleCap = 10
    /// The longest the hand-off waits for the add-on subtitles still fetching.
    private static let subtitleWait: TimeInterval = 1.5

    /// Builds the player's URL; nil when it cannot take this source. `open` then launches it.
    static func prepare(_ request: Request, playerId: String) async -> (url: URL, sessionId: String?)? {
        let addon = await addonSubtitles(type: request.type, videoId: request.videoId)
        var sessionId: String?
        var success: String?
        var failure: String?
        if reportingPlayers.contains(playerId), let session = request.session {
            let prepared = ExternalPlaybackReturn.shared.prepare(
                playerId: playerId, sourceUrl: request.url, playbackSession: session,
                durationMs: request.durationMs.map { KotlinLong(value: $0) })
            let callbacks = ExternalPlaybackCallbacks.shared.build(
                scheme: AppCallbackScheme.value, playerId: playerId, sessionId: prepared.id)
            sessionId = prepared.id
            success = callbacks.first.map { $0 as String }
            failure = callbacks.second.map { $0 as String }
        }
        let playback = ExternalPlayerPlaybackRequest(
            sourceUrl: request.url,
            title: request.title,
            streamTitle: nil,
            sourceHeaders: [:],
            resumePositionMs: request.resumeMs,
            subtitles: subtitles(stream: request.stream, addon: addon),
            season: request.season.map { KotlinInt(int: Int32($0)) },
            episode: request.episode.map { KotlinInt(int: Int32($0)) },
            episodeTitle: nil,
            skipSegmentsJson: nil,
            callbackSuccessUrl: success,
            callbackErrorUrl: failure)
        let intent = ExternalPlayerPlatform.shared.buildIntent(request: playback, playerId: playerId)
        guard let built = intent as? ExternalPlayerIntentResultSuccess, let url = built.intent as? URL else {
            if let sessionId { ExternalPlaybackReturn.shared.cancelLaunch(sessionId: sessionId) }
            return nil
        }
        return (url, sessionId)
    }

    /// Leaves the app for the player (a beat after the page has started closing).
    static func open(_ url: URL, sessionId: String?) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            UIApplication.shared.open(url, options: [:]) { opened in
                if !opened, let sessionId { ExternalPlaybackReturn.shared.cancelLaunch(sessionId: sessionId) }
            }
        }
    }

    // MARK: - Subtitles

    private static func addonSubtitles(type: String, videoId: String) async -> [AddonSubtitle] {
        let repository = SubtitleRepository.shared
        repository.fetchAddonSubtitles(type: type, videoId: videoId)
        let key = repository.requestKey(type: type, videoId: videoId)
        let deadline = Date().addingTimeInterval(subtitleWait)
        while (repository.completedRequest.value_ as? String) != key, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let subtitles = repository.addonSubtitles.value_ as? [AddonSubtitle] ?? []
        guard let settings = playerSettings() else { return subtitles }
        return PlayerTrackSelectionKt.filterAddonSubtitlesForSettings(subtitles: subtitles, settings: settings)
    }

    /// The stream's own subtitles, then the add-ons' (preferred language first), no duplicates.
    private static func subtitles(stream: StreamItem, addon: [AddonSubtitle]) -> [SubtitleInput] {
        let targets: [String] = playerSettings().map {
            PlayerTrackSelectionKt.preferredSubtitleTargetsForSettings(settings: $0)
        } ?? []
        func rank(_ language: String) -> Int {
            targets.firstIndex {
                PlayerLanguagePreferencesKt.languageMatchesPreference(trackLanguage: language, targetLanguage: $0)
            } ?? targets.count
        }
        let own = stream.externalSubtitles.map { sub in
            SubtitleInput(url: sub.url, name: { let n: String? = sub.name; return n }() ?? sub.language, lang: sub.language)
        }
        let ranked = addon.enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (rank(lhs.element.language), rank(rhs.element.language))
                return a != b ? a < b : lhs.offset < rhs.offset
            }
            .map { SubtitleInput(url: $0.element.url, name: $0.element.display, lang: $0.element.language) }
        var seen = Set<String>()
        var out: [SubtitleInput] = []
        for item in own + ranked where out.count < subtitleCap {
            let key = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            out.append(item)
        }
        return out
    }

    private static func playerSettings() -> PlayerSettingsUiState? {
        PlayerSettingsRepository.shared.ensureLoaded()
        return PlayerSettingsRepository.shared.uiState.value_ as? PlayerSettingsUiState
    }
}
