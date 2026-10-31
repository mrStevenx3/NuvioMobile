import Combine
import SharedCore
import SwiftUI
import UIKit

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

/// Steven (2026-10-29: "fais comme l'accueil"): redrawn only when what it shows changes (its own
/// focus lives in its strips and its own state).
extension OrbitEpisodesSection: Equatable {
    static func == (a: OrbitEpisodesSection, b: OrbitEpisodesSection) -> Bool {
        a.meta.id == b.meta.id && a.meta.videos.count == b.meta.videos.count
            && a.episodeRatings == b.episodeRatings && a.watchedEpisodeKeys == b.watchedEpisodeKeys
            && a.startSeason == b.startSeason && a.returning == b.returning && a.passed == b.passed
    }
}

/// A section of a page drawn again only when its key changes (Home's rows' rule, for sections
/// built inside their page).
struct OrbitStillSection<Key: Equatable, Content: View>: View, Equatable {
    let key: Key
    @ViewBuilder let content: () -> Content

    var body: some View { content() }

    static func == (a: OrbitStillSection, b: OrbitStillSection) -> Bool { a.key == b.key }
}

struct OrbitEpisodesSection: View {
    let meta: MetaDetails
    let episodeRatings: [String: Double]
    let watchedEpisodeKeys: Set<String>
    /// The season of the series' next episode (the hero's Play), shown first.
    let startSeason: Int?
    let focus: FocusState<OrbitDetailFocus?>.Binding
    let onPlay: (MetaVideo) -> Void
    /// Held on an episode: play it choosing the source (Steven, 2026-10-31: the long press did nothing).
    var onPlayManually: ((MetaVideo) -> Void)? = nil
    /// Steven (2026-10-29: "applique-le de PARTOUT"): the seasons and the episodes are UIKit strips
    /// the focus engine scrolls; the page restores its focus through them and hears it from them.
    var seasonsRef: OrbitStripRef? = nil
    var episodesRef: OrbitStripRef? = nil
    var onStripFocus: (OrbitDetailFocus?) -> Void = { _ in }
    /// Back from a page or the player: the card the focus is going back to. Steven (2026-10-29: the
    /// focus landed a second on the row above or below first) — the other row cannot take it meanwhile.
    var returning: OrbitDetailFocus? = nil
    /// The focus has gone on below the episodes (the cast and further): the episode's text above
    /// the next row fades. Steven (2026-10-31: "quand je passe au casting, je ne dois plus voir la
    /// synopsis de l'épisode en haut").
    var passed = false
    @State private var ownSeasonsRef = OrbitStripRef()
    @State private var ownEpisodesRef = OrbitStripRef()
    /// The focus in the strips (the page's own focus no longer sees it).
    @State private var stripFocus: OrbitDetailFocus?

    @AppStorage(EpisodeSpoilerRules.defaultsKey) private var hideSpoilers = false
    @State private var shownSeason: Int?
    /// Steven (2026-10-26): the focused episode always at the margin, the row sliding under it
    /// (as on Home) — its text stays put under it.
    @State private var episodeAnchor: String?
    /// The focus is (or was last) on a season's poster.
    @State private var comingFromSeason = false
    static let detailsWidth: CGFloat = 1300
    /// The episode's line and its two lines of synopsis, with a little room (was 136).
    static let detailsHeight: CGFloat = 118

    /// Steven (2026-10-29): the episodes a little larger with the larger seasons (was 384 × 216).
    /// (Steven, 2026-10-31, photo: the episode's synopsis cut at the screen's foot — smaller, and the
    /// gaps above them tighter, so its two lines show whole: 60 points up.)
    static let stillSize = CGSize(width: 352, height: 198)
    /// Steven (2026-10-24, 2026-10-29 twice): larger season posters (180 × 270, then 210 × 315).
    static let seasonSize = CGSize(width: 240, height: 360)
    /// The episode row's height (card, title, a little room): fixed, so a season change — the old
    /// row fading out while the new one fades in — never stacks two rows (the page bounced).
    /// Steven (2026-10-29): the episodes closer to their synopsis (the room under them was 36).
    static var episodeRowHeight: CGFloat { stillSize.height + 12 + 30 + 2 }
    /// Steven (2026-10-29): the episodes further from the seasons above them (they sit lower).
    static let seasonsToEpisodes: CGFloat = 28

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
            if case .episode(let id)? = stripFocus { return list.first { $0.id == id } }
            return nil
        }()
        let shown = focusedEpisode ?? nextUp
        let seasonList = seasons
        let still = Self.stillSize
        VStack(alignment: .leading, spacing: 20) {
            Text(String(localized: "Épisodes"))
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.leading, OrbitDetailLayout.margin)

            if seasonList.count > 1 {
                // The season shown takes the focus coming in (Steven, 2026-10-28).
                OrbitStripView(count: seasonList.count, identity: seasonList.map { "\($0)" }.joined(separator: ","),
                               spacing: 32, height: Self.seasonSize.height + 44, margin: OrbitDetailLayout.margin,
                               alignment: .top, lead: season.flatMap { seasonList.firstIndex(of: $0) } ?? 0,
                               entersOnLead: true, width: { _ in Self.seasonSize.width + 20 },
                               ref: seasonsRef ?? ownSeasonsRef,
                               tile: { i, focused in
                                   let s = seasonList[i]
                                   return AnyView(OrbitSeasonCard(label: OrbitEpisodeFormat.seasonLabel(s),
                                                                  poster: posterURL(season: s),
                                                                  focused: focused, selected: s == season))
                               },
                               onFocus: { i in
                                   guard let i else { return }
                                   let s = seasonList[i]
                                   comingFromSeason = true
                                   stripFocus = .season(s)
                                   if s != shownSeason { shownSeason = s }
                                   onStripFocus(.season(s))
                               },
                               onSelect: { i in shownSeason = seasonList[i] })
                    .frame(height: Self.seasonSize.height + 44)
                    .disabled(returningToEpisode)
                    .focusSection()
                    .padding(.bottom, Self.seasonsToEpisodes - 20)
            }

            // A ZStack: the old season's row and the new one cross-fade.
            ZStack(alignment: .topLeading) {
                // Down from a season's poster: its first episode; else the next one to watch.
                let leadIndex = comingFromSeason ? 0 : (nextUp.flatMap { up in list.firstIndex { $0.id == up.id } } ?? 0)
                OrbitStripView(count: list.count, identity: "season-\(season ?? -1)|\(list.count)", spacing: 36,
                               height: still.height + 12 + 30, margin: OrbitDetailLayout.margin, alignment: .top,
                               pinned: true, lead: leadIndex, width: { _ in still.width },
                               ref: episodesRef ?? ownEpisodesRef,
                               tile: { i, focused in
                                   AnyView(OrbitEpisodeCard(episode: list[i], fallbackArt: meta.background ?? meta.poster,
                                                            watched: isWatched(list[i]), focused: focused))
                               },
                               onFocus: { i in
                                   guard let i else { return }
                                   comingFromSeason = false
                                   stripFocus = .episode(list[i].id)
                                   onStripFocus(.episode(list[i].id))
                               },
                               onSelect: { i in onPlay(list[i]) },
                               menu: onPlayManually.map { manual in
                                   { i in
                                       guard list.indices.contains(i) else { return nil }
                                       let episode = list[i]
                                       return UIMenu(children: [
                                           UIAction(title: String(localized: "Play Manually"),
                                                    image: UIImage(systemName: "list.bullet")) { _ in manual(episode) }
                                       ])
                                   }
                               })
                    .frame(height: still.height + 12 + 30)
                    .disabled(returningToSeason)
                    .id("season-\(season ?? -1)")
                    .transition(.opacity)
            }
            .frame(height: Self.episodeRowHeight, alignment: .topLeading)
            .focusSection()
            .animation(.easeInOut(duration: 0.25), value: season)

            // Fixed and overlapping: the old episode's text fades out under the new one, in place.
            ZStack(alignment: .topLeading) {
                OrbitEpisodeDetails(episode: shown,
                                    rating: shown.flatMap { rating(for: $0) },
                                    hidesSynopsis: shown.map { EpisodeSpoilerRules.hidesSpoilers(settingOn: hideSpoilers,
                                                                                                 isWatched: isWatched($0)) } ?? false)
            }
            .frame(width: Self.detailsWidth, height: Self.detailsHeight, alignment: .topLeading)
            .clipped()
            .opacity(passed ? 0 : 1)
            .animation(.easeOut(duration: 0.18), value: passed)
            .padding(.leading, OrbitDetailLayout.margin)
            // (Steven, 2026-10-31, photo: a series without seasons — too much room between the
            // episodes and the cast. The text's room held for two lines, closer to the next row.)
            .padding(.bottom, -20)
        }
    }

    private var returningToEpisode: Bool {
        if case .episode? = returning { return true }
        return false
    }
    private var returningToSeason: Bool {
        if case .season? = returning { return true }
        return false
    }

    /// Where an episode sits in its season's row (the page's way back).
    static func place(of id: String, in meta: MetaDetails) -> (season: Int?, index: Int)? {
        guard let episode = meta.videos.first(where: { $0.id == id }) else { return nil }
        let season = episode.season?.value
        let list = meta.videos.filter { $0.season?.value == season }
            .sorted { ($0.episode?.value ?? 0) < ($1.episode?.value ?? 0) }
        guard let index = list.firstIndex(where: { $0.id == id }) else { return nil }
        return (season, index)
    }

    /// Where a season sits in the seasons' row.
    static func place(ofSeason s: Int, in meta: MetaDetails) -> Int? {
        let all = Set(meta.videos.compactMap { $0.season?.value })
        let seasons = all.filter { $0 > 0 }.sorted() + (all.contains(0) ? [0] : [])
        return seasons.firstIndex(of: s)
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
                // (Steven, 2026-10-31: the seasons not shown no longer dimmed — all in their colours;
                // the one shown keeps its light rim.)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : (selected ? 0.55 : 0)), lineWidth: focused ? 4 : 3))
            .scaleEffect(focused ? 1.05 : 1)
            .modifier(OrbitCardShadow(focused: focused, lit: 0.5, radius: 14, y: 8))
            Text(label)
                .font(.system(size: 22, weight: focused || selected ? .bold : .medium))
                .foregroundStyle(Color.white.opacity(focused || selected ? 1 : 0.6))
                .lineLimit(1)
                // (Steven, 2026-10-30: the label too close under the focused, enlarged poster — it
                // steps down with it.)
                .offset(y: focused ? 14 : 0)
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
            .modifier(OrbitCardShadow(focused: focused, lit: 0.55, radius: 18, y: 10))
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
                // Steven (2026-10-31): the episode's note in yellow; the line kept bright, the synopsis
                // under it a little more see-through, so the two read apart.
                HStack(spacing: 0) {
                    Text(OrbitEpisodeFormat.caption(episode, rating: nil))
                        .foregroundStyle(Color.white.opacity(0.85))
                    if let note = OrbitEpisodeFormat.note(rating) {
                        // (Steven, 2026-10-31: only the star in yellow.)
                        Text(" · ").foregroundStyle(Color.white.opacity(0.85))
                        Text("★ ").foregroundStyle(OrbitEpisodeFormat.noteColour)
                        Text(note).foregroundStyle(Color.white.opacity(0.85))
                    }
                }
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(1)
                let overview: String? = episode.overview
                if hidesSynopsis {
                    Text(String(localized: "Résumé masqué jusqu'au visionnage"))
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                } else if let overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .lineSpacing(4)
                        .lineLimit(2)
                }
            }
        }
        .frame(width: OrbitEpisodesSection.detailsWidth, height: OrbitEpisodesSection.detailsHeight, alignment: .topLeading)
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
    /// The note's yellow (the sources' one).
    static let noteColour = Color(red: 1, green: 0.84, blue: 0.3)

    static func note(_ rating: Double?) -> String? {
        guard let rating, rating > 0, let text = OrbitDetailFormat.rating(String(rating)) else { return nil }
        return text
    }

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
