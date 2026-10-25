import Combine
import SharedCore
import SwiftUI

// Orbit Detail (Steven, 2026-10-23): a series' seasons and episodes, rebuilt from scratch for the
// Orbit page (the legacy `EpisodesSection` is no longer used here).
//
//     Épisodes
//     [S1] [S2] [S3] … [Spéciaux]          the seasons, their posters (the series' as fallback)
//     [E1 still] [E2 still] [E3 still] …    the season's episodes, 16:9 stills
//     S1E3 · 6 oct. 2004 · 43 min · ★ 8,2   the focused episode's line and synopsis
//     Lorem ipsum…
//
//  - The season the focus is on is the one shown (its episodes swap in a crossfade); the season
//    being shown stays marked while the focus is on its episodes.
//  - Entering the section from above lands on the next episode to watch, not on a season.
//  - Watched episodes carry a tick; episodes not out yet are dimmed with their date.
//  - Select plays the episode (the source picker, as from the hero).

struct OrbitEpisodesSection: View {
    let meta: MetaDetails
    let episodeRatings: [String: Double]
    let watchedEpisodeKeys: Set<String>
    /// The season of the series' next episode (the hero's Play), shown first.
    let startSeason: Int?
    let focus: FocusState<OrbitDetailFocus?>.Binding
    let onPlay: (MetaVideo) -> Void

    @AppStorage(EpisodeSpoilerRules.defaultsKey) private var hideSpoilers = false
    @State private var shownSeason: Int?
    /// Steven (2026-10-25: the episode's text stayed far left under a card on the right): where
    /// each card is on screen (written as the row scrolls, never a page update), and the focused
    /// one's place the text follows.
    @State private var cardX = OrbitEpisodeCardPlaces()
    @State private var focusedX: CGFloat = OrbitDetailLayout.margin
    static let detailsWidth: CGFloat = 900

    static let stillSize = CGSize(width: 384, height: 216)
    /// Steven (2026-10-24): larger season posters.
    static let seasonSize = CGSize(width: 180, height: 270)
    /// The episode row's height (card, title, the row's padding): fixed, so a season change —
    /// the old row fading out while the new one fades in — never stacks two rows (the page
    /// bounced).
    static var episodeRowHeight: CGFloat { stillSize.height + 12 + 30 + 2 * 18 }

    private var seasons: [Int] {
        let all = Set(meta.videos.compactMap { $0.season?.value })
        // Specials last.
        return all.filter { $0 > 0 }.sorted() + (all.contains(0) ? [0] : [])
    }

    private var currentSeason: Int? {
        if let shownSeason, seasons.contains(shownSeason) { return shownSeason }
        if let startSeason, seasons.contains(startSeason) { return startSeason }
        return seasons.first
    }

    private func episodes(of season: Int?) -> [MetaVideo] {
        meta.videos
            .filter { $0.season?.value == season }
            .sorted { ($0.episode?.value ?? 0) < ($1.episode?.value ?? 0) }
    }

    private func isWatched(_ episode: MetaVideo) -> Bool {
        guard let s = episode.season?.value, let e = episode.episode?.value else { return false }
        return watchedEpisodeKeys.contains("\(s):\(e)")
    }

    var body: some View {
        let season = currentSeason
        let list = episodes(of: season)
        let nextUp = list.first(where: { !isWatched($0) && OrbitEpisodeFormat.isOut($0) }) ?? list.first
        let focusedEpisode: MetaVideo? = {
            if case .episode(let id)? = focus.wrappedValue { return list.first { $0.id == id } }
            return nil
        }()
        let shown = focusedEpisode ?? nextUp
        VStack(alignment: .leading, spacing: 20) {
            Text(String(localized: "Épisodes"))
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.leading, OrbitDetailLayout.margin)

            if seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 24) {
                        ForEach(seasons, id: \.self) { s in
                            Button { shownSeason = s } label: {
                                OrbitSeasonCard(label: OrbitEpisodeFormat.seasonLabel(s),
                                                poster: posterURL(season: s),
                                                focused: focus.wrappedValue == .season(s),
                                                selected: s == season)
                            }
                            .buttonStyle(OrbitPlainStyle())
                            .focused(focus, equals: .season(s))
                        }
                    }
                    .padding(.horizontal, OrbitDetailLayout.margin)
                    .padding(.vertical, 16)
                }
                .scrollClipDisabled()
                .focusSection()
            }

            // A ZStack: the old season's row and the new one overlap while they cross-fade.
            ZStack(alignment: .topLeading) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 28) {
                        ForEach(list, id: \.id) { episode in
                            Button { onPlay(episode) } label: {
                                OrbitEpisodeCard(episode: episode,
                                                 fallbackArt: meta.background ?? meta.poster,
                                                 watched: isWatched(episode),
                                                 focused: focus.wrappedValue == .episode(episode.id))
                            }
                            .buttonStyle(OrbitPlainStyle())
                            .focused(focus, equals: .episode(episode.id))
                            .id(episode.id)
                            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minX }) { x in
                                cardX.x[episode.id] = x
                                if focus.wrappedValue == .episode(episode.id) { place(x) }
                            }
                        }
                    }
                    .padding(.horizontal, OrbitDetailLayout.margin)
                    .padding(.vertical, 18)
                }
                .scrollClipDisabled()
                .id("season-\(season ?? -1)")
                .transition(.opacity)
                .onAppear {
                    if let nextUp { DispatchQueue.main.async { proxy.scrollTo(nextUp.id, anchor: .leading) } }
                }
            }
            }
            .frame(height: Self.episodeRowHeight, alignment: .topLeading)
            .focusSection()
            .animation(.easeInOut(duration: 0.25), value: season)

            // Fixed and overlapping: the old episode's text fades out under the new one, in place
            // (it hung over the cast row and pushed the page while both took room).
            ZStack(alignment: .topLeading) {
                OrbitEpisodeDetails(episode: shown,
                                    rating: shown.flatMap { rating(for: $0) },
                                    hidesSynopsis: shown.map { EpisodeSpoilerRules.hidesSpoilers(settingOn: hideSpoilers,
                                                                                                 isWatched: isWatched($0)) } ?? false)
            }
            .frame(width: Self.detailsWidth, height: 110, alignment: .topLeading)
            .clipped()
            // Under the focused episode (kept on screen at the right edge).
            .padding(.leading, focusedX)
            .animation(.easeOut(duration: 0.22), value: focusedX)
        }
        // Steven: entering from above (the hero) lands on the season being shown — the season
        // row is no longer skipped (the engine took the poster under Lire, or the episodes).
        .onChange(of: focus.wrappedValue) { old, new in
            if case .episode(let id)? = new, let x = cardX.x[id] { place(x) }
            guard case .season(let s)? = new else { return }
            // Up from the episodes too: back on the season they belong to (the engine took the
            // poster above the focused episode).
            let fromEpisodes: Bool = { if case .episode? = old { return true }; return false }()
            if old == nil || old?.section == .hero || fromEpisodes, let season, s != season {
                DispatchQueue.main.async { focus.wrappedValue = .season(season) }
                return
            }
            if s != shownSeason { shownSeason = s }
        }
    }

    private func place(_ x: CGFloat) {
        let maxX = OrbitHomeLayout.screenWidth - OrbitDetailLayout.margin - Self.detailsWidth
        let clamped = min(max(x, OrbitDetailLayout.margin), maxX)
        if abs(clamped - focusedX) > 1 { focusedX = clamped }
    }

    private func posterURL(season: Int) -> String? {
        let poster: String? = meta.videos.first { $0.season?.value == season && !($0.seasonPoster ?? "").isEmpty }?.seasonPoster
        return poster ?? meta.poster
    }

    private func rating(for episode: MetaVideo) -> Double? {
        guard let s = episode.season?.value, let e = episode.episode?.value else { return episode.rating?.doubleValue }
        return episodeRatings["\(s):\(e)"] ?? episode.rating?.doubleValue
    }
}

/// Where each episode card is on screen (a box: written on every scroll frame, never a page update).
final class OrbitEpisodeCardPlaces {
    var x: [String: CGFloat] = [:]
}

private struct OrbitSeasonCard: View {
    let label: String
    let poster: String?
    let focused: Bool
    let selected: Bool

    var body: some View {
        let size = OrbitEpisodesSection.seasonSize
        VStack(spacing: 10) {
            ZStack {
                Color(white: 0.12)
                OrbitImage(url: poster, size: size)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : (selected ? 0.55 : 0)), lineWidth: focused ? 4 : 3))
            .scaleEffect(focused ? 1.05 : 1)
            .opacity(focused || selected ? 1 : 0.65)
            .shadow(color: .black.opacity(focused ? 0.5 : 0.2), radius: 14, y: 8)
            Text(label)
                .font(.system(size: 22, weight: focused || selected ? .bold : .medium))
                .foregroundStyle(Color.white.opacity(focused || selected ? 1 : 0.6))
                .lineLimit(1)
        }
        .frame(width: size.width + 20)
        .animation(.easeOut(duration: 0.16), value: focused)
        .animation(.easeOut(duration: 0.2), value: selected)
    }
}

private struct OrbitEpisodeCard: View {
    let episode: MetaVideo
    let fallbackArt: String?
    let watched: Bool
    let focused: Bool

    var body: some View {
        let size = OrbitEpisodesSection.stillSize
        let still: String? = episode.thumbnail
        let out = OrbitEpisodeFormat.isOut(episode)
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Color(white: 0.12)
                OrbitImage(url: (still ?? "").isEmpty ? fallbackArt : still, size: size)
                    .opacity(out ? 1 : 0.4)
                if watched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.black, Color.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                        .padding(12)
                }
                if !out, let date = OrbitEpisodeFormat.date(episode.released) {
                    Text(date)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 5))
            .scaleEffect(focused ? 1.06 : 1)
            .shadow(color: .black.opacity(focused ? 0.55 : 0.2), radius: 18, y: 10)
            Text(OrbitEpisodeFormat.title(episode))
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color.white.opacity(out ? 1 : 0.6))
                .lineLimit(1)
                .frame(width: size.width, alignment: .leading)
        }
        .animation(.easeOut(duration: 0.16), value: focused)
    }
}

/// The focused (else next) episode's line and synopsis, a fixed height so nothing below moves.
private struct OrbitEpisodeDetails: View {
    let episode: MetaVideo?
    let rating: Double?
    let hidesSynopsis: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let episode {
                Text(OrbitEpisodeFormat.caption(episode, rating: rating))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                let overview: String? = episode.overview
                if hidesSynopsis {
                    Text(String(localized: "Résumé masqué jusqu'au visionnage"))
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                } else if let overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineSpacing(4)
                        .lineLimit(2)
                }
            }
        }
        .frame(width: OrbitEpisodesSection.detailsWidth, height: 110, alignment: .topLeading)
        // Swapped at once: two texts cross-fading overlapped into an unreadable mix.
    }
}

enum OrbitEpisodeFormat {
    static func seasonLabel(_ season: Int) -> String {
        season <= 0 ? String(localized: "Spéciaux") : String(format: String(localized: "Saison %d"), season)
    }

    /// "E3 · Le nouveau départ"
    static func title(_ episode: MetaVideo) -> String {
        if let e = episode.episode?.value { return "E\(e) · \(episode.title)" }
        return episode.title
    }

    /// "S1E3 · 6 oct. 2004 · 43 min · ★ 8,2"
    static func caption(_ episode: MetaVideo, rating: Double?) -> String {
        var parts: [String] = []
        if let s = episode.season?.value, let e = episode.episode?.value { parts.append("S\(s)E\(e)") }
        if let date = date(episode.released) { parts.append(date) }
        if let runtime = episode.runtime?.value, runtime > 0 { parts.append(OrbitDetailFormat.runtime("\(runtime)m") ?? "\(runtime) min") }
        if let rating, rating > 0, let text = OrbitDetailFormat.rating(String(rating)) { parts.append("★ \(text)") }
        return parts.joined(separator: " · ")
    }

    // Made once (fluidity: they were created again for every episode card drawn).
    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let mediumDay: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static func releaseDate(_ raw: String?) -> Date? {
        guard let raw, raw.count >= 10 else { return nil }
        return isoDay.date(from: String(raw.prefix(10)))
    }

    /// "6 oct. 2004" in the viewer's language.
    static func date(_ raw: String?) -> String? {
        guard let date = releaseDate(raw) else { return nil }
        return mediumDay.string(from: date)
    }

    /// Out already (no date counts as out).
    static func isOut(_ episode: MetaVideo) -> Bool {
        guard let date = releaseDate(episode.released) else { return true }
        return date <= Date()
    }
}
