import Combine
import CoreImage
import SharedCore
import SwiftUI
import UIKit

// Orbit Home, pass 3 (Steven, 2026-10-25: "trop pauvre encore", tiles of different kinds and sizes
// depending on the row). The row kinds besides the classic one (the open frame and its posters):
//
//  - landscape: 16:9 tiles with the title's logo (Reprendre, the platforms' new titles);
//  - cards: large portrait cards, the art without its title, the logo and the line over it, the
//    trailer in the focused one after a rest;
//  - posters: smaller posters, closer together;
//  - ranked: the Top 10 across the viewer's platforms, the big rank beside each poster.
// Every kind keeps Orbit's focus (the white frame, a little larger) and the lead at the left
// margin; the focused title's meta line and synopsis show under the row (on the card for cards).

nonisolated enum OrbitRowStyle: Equatable {
    case classic, landscape, cards, posters, ranked, sagas
}

enum OrbitTileLayout {
    static let landscape = CGSize(width: 456, height: 256)
    static let card = CGSize(width: 400, height: 560)
    static let poster = CGSize(width: 248, height: 372)
    /// Steven: the sagas' posters larger (their art is the point of the row).
    static let sagaPoster = CGSize(width: 340, height: 510)
    /// Steven: the Top 10 more prominent — larger posters, larger ranks.
    static let rankedPoster = CGSize(width: 300, height: 450)
    static let rankWidth: CGFloat = 190
    /// The extra room for "10" (the last title: nothing after it moves).
    static let tenExtra: CGFloat = 110
    static let infoGap: CGFloat = 26

    static func size(_ style: OrbitRowStyle) -> CGSize {
        switch style {
        case .landscape: return landscape
        case .cards: return card
        case .posters: return poster
        case .ranked: return rankedPoster
        case .sagas: return sagaPoster
        case .classic: return CGSize(width: OrbitHomeLayout.posterWidth, height: OrbitHomeLayout.cardHeight)
        }
    }

    static func gap(_ style: OrbitRowStyle) -> CGFloat {
        switch style {
        case .landscape: return 24
        case .cards: return 30
        case .posters: return 22
        case .ranked: return 18
        case .sagas: return 26
        case .classic: return OrbitHomeLayout.gap
        }
    }

    static func slot(_ style: OrbitRowStyle) -> CGFloat {
        size(style).width + gap(style) + (style == .ranked ? rankWidth : 0)
    }

    /// From a row's heading centre to the next row's (the page's pitch for this kind of row).
    static func pitch(_ style: OrbitRowStyle) -> CGFloat {
        switch style {
        case .classic: return OrbitHomeLayout.rowPitch
        case .cards: return OrbitHomeLayout.cardsTop + card.height + 90
        case .landscape: return OrbitHomeLayout.cardsTop + landscape.height + infoGap + 150
        case .posters: return OrbitHomeLayout.cardsTop + poster.height + infoGap + 150
        case .ranked: return OrbitHomeLayout.cardsTop + rankedPoster.height + infoGap + 150
        case .sagas: return OrbitHomeLayout.cardsTop + sagaPoster.height + infoGap + 150
        }
    }
}

/// A row of tiles of one kind.
struct OrbitHomeTileRowView: View {
    let row: OrbitRow
    let lead: Int
    let isCurrent: Bool
    let focused: Bool
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        let L = OrbitHomeLayout.self
        let T = OrbitTileLayout.self
        let style = row.style
        let size = T.size(style)
        let slot = T.slot(style)
        let visible = Int(L.screenWidth / slot) + 2
        let window = max(0, lead - 2)...max(max(0, lead - 2), min(row.cards.count - 1, lead + visible))
        ZStack(alignment: .topLeading) {
            Text(row.title)
                .font(.system(size: L.headingFont, weight: .bold))
                .foregroundStyle(Color.white)
                .opacity(isCurrent ? 1 : 0.55)
                .lineLimit(1)
                .frame(height: 40, alignment: .center)
                .offset(x: L.margin + 4, y: -20)

            ZStack(alignment: .topLeading) {
                if !row.cards.isEmpty {
                    ForEach(Array(zip(window, row.cards[window])), id: \.1.id) { index, card in
                        let lit = focused && index == lead
                        let meta = metaStore.meta(for: card.preview)
                        Group {
                            switch style {
                            case .landscape:
                                OrbitLandscapeTile(card: card, meta: meta, focused: lit)
                            case .cards:
                                OrbitBigCard(card: card, meta: meta, focused: lit,
                                             trailerURL: index == lead ? trailerURL : nil,
                                             onTrailerFailure: onTrailerFailure, onTrailerEnded: onTrailerEnded)
                            case .ranked:
                                OrbitRankedTile(card: card, meta: meta, rank: index + 1, focused: lit)
                            case .posters, .classic:
                                OrbitSmallPoster(card: card, meta: meta, focused: lit)
                            case .sagas:
                                OrbitSmallPoster(card: card, meta: meta, focused: lit, size: OrbitTileLayout.sagaPoster)
                            }
                        }
                        .offset(x: L.margin + CGFloat(index - lead) * slot)
                        .opacity(index < lead - 1 ? 0 : (index < lead ? 0.5 : 1))
                        .zIndex(lit ? 1 : 0)
                        .transition(.identity)
                    }
                }
            }
            .offset(y: L.cardsTop)

            // The focused title's details under the row (cards carry theirs).
            if style != .cards, row.cards.indices.contains(lead) {
                let card = row.cards[lead]
                let info = OrbitInfo.make(card.preview, meta: metaStore.meta(for: card.preview))
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        Text(card.preview.name)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        OrbitMetaLine(info: info, size: 24)
                    }
                    .frame(height: 34)
                    Text(info.synopsis)
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineSpacing(3)
                        .lineLimit(2)
                        .frame(width: 1100, alignment: .topLeading)
                }
                .id(card.id)
                // Steven's video: two titles' text over each other while they cross-faded. The old
                // one goes at once, the new one fades in.
                .transition(.asymmetric(insertion: .opacity.animation(L.crossfade), removal: .identity))
                .opacity(isCurrent ? 1 : 0)
                .offset(x: L.margin + 6, y: L.cardsTop + size.height + T.infoGap)
            }
        }
        .frame(width: L.screenWidth, height: T.pitch(style), alignment: .topLeading)
    }
}

/// Orbit's focus on a tile: the white frame, a little larger.
private struct OrbitTileFocus: ViewModifier {
    let focused: Bool
    var radius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(focused ? 1 : 0.12), lineWidth: focused ? 4 : 1)
            }
            .shadow(color: .black.opacity(focused ? 0.55 : 0.2), radius: focused ? 18 : 6, y: focused ? 10 : 3)
            .scaleEffect(focused ? 1.05 : 1, anchor: .leading)
            .animation(.easeOut(duration: 0.18), value: focused)
    }
}

/// A 16:9 tile: the art, the logo, the platform badge, the progress for Reprendre.
private struct OrbitLandscapeTile: View {
    let card: OrbitCard
    let meta: OrbitMeta?
    let focused: Bool

    var body: some View {
        let size = OrbitTileLayout.landscape
        let info = OrbitInfo.make(card.preview, meta: meta)
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.1)
            OrbitImage(url: card.landscape ?? meta?.backdrop, fallback: card.poster, size: size)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            OrbitTitleMark(name: card.preview.name, logo: info.logo,
                           maxSize: CGSize(width: size.width * 0.6, height: size.height * 0.36), textSize: 28,
                           fallbackLogo: info.logoFallback)
                .padding(.leading, 18)
                .padding(.bottom, card.progress == nil ? 16 : 26)
            if let progress = card.progress {
                OrbitProgressBar(progress: progress)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
            }
            if let badge = card.badge {
                Text(badge)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.6)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 14)
                    .padding(.bottom, 22)
            }
            if let kind = OrbitPlatformBadgeKind.of(meta) {
                OrbitPlatformBadge(kind: kind, size: 15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(12)
            }
        }
        .frame(width: size.width, height: size.height)
        .modifier(OrbitTileFocus(focused: focused))
    }
}

/// A large portrait card: the art without its title, the logo, the badge and the line over it; the
/// trailer in it after a rest.
private struct OrbitBigCard: View {
    let card: OrbitCard
    let meta: OrbitMeta?
    let focused: Bool
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let size = OrbitTileLayout.card
        let info = OrbitInfo.make(card.preview, meta: meta)
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.1)
            OrbitImage(url: meta?.cleanPoster ?? card.landscape, fallback: card.poster, mode: .fill, size: size)
            if let trailerURL {
                TrailerHeroPlayer(urlString: trailerURL, onFailure: onTrailerFailure,
                                  zoomKey: TrailerResolutionCache.key(type: card.preview.type, id: card.preview.id),
                                  loops: false, onPlaybackEnded: onTrailerEnded, cornerRadius: 18)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity.animation(.easeOut(duration: 0.5)))
            }
            LinearGradient(stops: [
                .init(color: .clear, location: 0.45),
                .init(color: .black.opacity(0.8), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                if let kind = OrbitPlatformBadgeKind.of(meta) {
                    OrbitPlatformBadge(kind: kind, size: 16)
                }
                OrbitTitleMark(name: card.preview.name, logo: info.logo, maxSize: CGSize(width: 330, height: 110),
                               textSize: 36, fallbackLogo: info.logoFallback, hugsLogo: true)
                    .frame(width: 330, alignment: .leading)
                OrbitMetaLine(info: info, size: 20)
                Text(info.synopsis)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(2)
                    .frame(width: 350, alignment: .leading)
                    .opacity(focused ? 1 : 0)
            }
            .padding(22)
        }
        .frame(width: size.width, height: size.height)
        .modifier(OrbitTileFocus(focused: focused, radius: 18))
    }
}

/// A smaller poster (TMDB's French one when it has one).
private struct OrbitSmallPoster: View {
    let card: OrbitCard
    let meta: OrbitMeta?
    let focused: Bool
    var size: CGSize = OrbitTileLayout.poster

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(white: 0.1)
            // A saga keeps its own poster (its card opens its first film, whose meta is not the saga's).
            OrbitImage(url: card.id.hasPrefix("saga:") ? card.poster : (meta?.localPoster ?? card.poster),
                       fallback: card.landscape, mode: .fill, size: size)
        }
        .frame(width: size.width, height: size.height)
        .modifier(OrbitTileFocus(focused: focused, radius: 10))
    }
}

/// A poster of the Top 10 across the platforms: the big rank beside it (Steven's add-on's spirit:
/// coloured with the poster's own dominant colour), the platform's badge on it.
private struct OrbitRankedTile: View {
    let card: OrbitCard
    let meta: OrbitMeta?
    let rank: Int
    let focused: Bool

    @State private var tone: Color?

    var body: some View {
        let T = OrbitTileLayout.self
        let size = T.rankedPoster
        let poster: String? = meta?.localPoster ?? card.poster
        let base = tone ?? Color(white: 0.85)
        HStack(alignment: .bottom, spacing: -34) {
            Text(String(rank))
                .font(.system(size: size.height * 0.7, weight: .heavy, design: .rounded))
                .kerning(-size.height * 0.03)
                .foregroundStyle(LinearGradient(colors: [base.opacity(1), base.opacity(0.75)],
                                                startPoint: .top, endPoint: .bottom))
                .overlay {
                    // A light rim on top, as on his add-on's ranks.
                    Text(String(rank))
                        .font(.system(size: size.height * 0.7, weight: .heavy, design: .rounded))
                        .kerning(-size.height * 0.03)
                        .foregroundStyle(LinearGradient(colors: [Color.white.opacity(0.55), .clear],
                                                        startPoint: .top, endPoint: .center))
                }
                .shadow(color: .black.opacity(0.7), radius: 14, y: 4)
                .lineLimit(1)
                .fixedSize()
                // "10" is wider: its own room, so it no longer runs over the 9's poster (Steven).
                .frame(width: T.rankWidth + 34 + (rank >= 10 ? T.tenExtra : 0), alignment: .trailing)
                .offset(y: size.height * 0.12)
                .animation(.easeInOut(duration: 0.4), value: tone)
            ZStack(alignment: .bottom) {
                Color(white: 0.1)
                OrbitImage(url: poster, fallback: card.landscape, mode: .fill, size: size)
                if let kind = OrbitPlatformBadgeKind.of(meta) {
                    OrbitPlatformBadge(kind: kind, size: 16)
                        .padding(.bottom, 14)
                }
            }
            .frame(width: size.width, height: size.height)
            .modifier(OrbitTileFocus(focused: focused, radius: 12))
        }
        .frame(width: T.rankWidth + size.width + (rank >= 10 ? T.tenExtra : 0), height: size.height, alignment: .bottomLeading)
        .task(id: poster ?? "-") {
            guard let poster else { return }
            tone = await OrbitDominantColor.color(for: poster)
        }
    }
}

/// A poster's dominant colour, lively enough to colour a rank (computed once per image, small).
@MainActor
enum OrbitDominantColor {
    private static var cache: [String: Color] = [:]

    static func color(for url: String) async -> Color? {
        if let known = cache[url] { return known }
        guard let address = URL(string: url),
              let image = try? await ArtworkStore.fetch(address, decode: .init(size: .pixels(48), fill: true, scale: 1)),
              let cg = image.cgImage else { return nil }
        let color = await Task.detached(priority: .utility) { () -> Color? in Self.average(cg) }.value
        if let color { cache[url] = color }
        return color
    }

    nonisolated private static func average(_ cg: CGImage) -> Color? {
        let input = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input,
                                                                       kCIInputExtentKey: CIVector(cgRect: input.extent)]),
              let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    format: .RGBA8, colorSpace: nil)
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
            .getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        // Lively: a grey poster stays a light grey, a coloured one gets its colour, bright.
        let saturation = sat < 0.12 ? sat : max(sat, 0.6)
        return Color(hue: Double(h), saturation: Double(min(saturation, 0.9)), brightness: Double(max(b, 0.85)))
    }
}

/// The page's own rows (TMDB): the Top 10 across the viewer's platforms, and each platform's new
/// titles, for films and for series.
@MainActor
final class OrbitHomeExtrasModel: ObservableObject {
    nonisolated struct Extra: Equatable {
        let id: String
        let title: String
        let items: [MetaPreview]
        let style: OrbitRowStyle
        static func == (a: Extra, b: Extra) -> Bool { a.id == b.id && a.items.map(\.id) == b.items.map(\.id) }
    }

    @Published private(set) var movieRows: [Extra] = []
    @Published private(set) var seriesRows: [Extra] = []
    /// "Parce que vous avez regardé …" (films, series): from the last title watched.
    @Published private(set) var becauseMovie: Extra?
    @Published private(set) var becauseSeries: Extra?
    private var started = false
    private var becauseSeeds: [String: String] = [:]

    func load() {
        guard !started else { return }
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        guard !key.isEmpty else { return }
        started = true
        let language = TmdbSettingsRepository.shared.snapshot().language
        Task { [weak self] in
            async let movies = Self.rows(tv: false, apiKey: key, language: language.isEmpty ? "fr-FR" : language)
            async let series = Self.rows(tv: true, apiKey: key, language: language.isEmpty ? "fr-FR" : language)
            let (m, s) = await (movies, series)
            guard let self else { return }
            if m.isEmpty && s.isEmpty { self.started = false; return }
            self.movieRows = m
            self.seriesRows = s
        }
    }

    /// Steven: from the last title watched — finished (his watched list) or in progress (Reprendre),
    /// so it holds when a title leaves Reprendre. `seed`: (id, name), nil when nothing watched.
    func loadBecause(seed: (id: String, name: String)?, series: Bool) {
        let slot = series ? "tv" : "movie"
        guard let seed, becauseSeeds[slot] != seed.id else { return }
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        guard !key.isEmpty else { return }
        becauseSeeds[slot] = seed.id
        let language = TmdbSettingsRepository.shared.snapshot().language
        Task { [weak self] in
            let items = await Self.recommendations(id: seed.id, tv: series, apiKey: key,
                                                   language: language.isEmpty ? "fr-FR" : language)
            guard let self, items.count >= 6 else { return }
            let row = Extra(id: "orbit-because-\(slot)", title: String(localized: "Parce que vous avez regardé \(seed.name)"),
                            items: Array(items.prefix(20)), style: .posters)
            if series { self.becauseSeries = row } else { self.becauseMovie = row }
        }
    }

    nonisolated private struct FindResult: Decodable {
        nonisolated struct Hit: Decodable { let id: Int }
        let movie_results: [Hit]?
        let tv_results: [Hit]?
    }

    nonisolated private static func recommendations(id: String, tv: Bool, apiKey: String, language: String) async -> [MetaPreview] {
        var tmdbId: Int?
        if id.hasPrefix("tmdb:") {
            tmdbId = Int(id.dropFirst(5).split(separator: ":").first ?? "")
        } else if id.hasPrefix("tt"), let url = URL(string: "https://api.themoviedb.org/3/find/\(id)?api_key=\(apiKey)&external_source=imdb_id"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let found = try? JSONDecoder().decode(FindResult.self, from: data) {
            tmdbId = (tv ? found.tv_results : found.movie_results)?.first?.id
        }
        guard let tmdbId else { return [] }
        let media = tv ? "tv" : "movie"
        return await OrbitPlatformExtrasModel.fetch(
            "https://api.themoviedb.org/3/\(media)/\(tmdbId)/recommendations?api_key=\(apiKey)&language=\(language)&page=1", tv: tv)
            .filter { $0.banner != nil }
    }

    /// A few great sagas (TMDB collections): their poster, opening their first film.
    nonisolated private static let sagaIds = [10, 1241, 119, 9485, 87359, 645, 328, 295, 131635, 10194,
                                              726871, 404609, 2344, 84, 264, 263, 86311, 531241, 748, 556]

    nonisolated private struct CollectionResponse: Decodable {
        nonisolated struct Part: Decodable { let id: Int; let release_date: String? }
        let id: Int
        let name: String?
        let overview: String?
        let poster_path: String?
        let backdrop_path: String?
        let parts: [Part]?
    }

    nonisolated private static func sagas(apiKey: String, language: String) async -> [MetaPreview] {
        let found = await withTaskGroup(of: (Int, MetaPreview?).self) { group in
            for (index, id) in sagaIds.enumerated() {
                group.addTask {
                    guard let url = URL(string: "https://api.themoviedb.org/3/collection/\(id)?api_key=\(apiKey)&language=\(language)"),
                          let (data, _) = try? await URLSession.shared.data(from: url),
                          let c = try? JSONDecoder().decode(CollectionResponse.self, from: data),
                          let name = c.name, let poster = c.poster_path,
                          let first = (c.parts ?? []).filter({ !($0.release_date ?? "").isEmpty })
                              .min(by: { ($0.release_date ?? "") < ($1.release_date ?? "") }) else { return (index, nil) }
                    let preview = MetaPreview(id: "tmdb:\(first.id)", type: "movie", name: name,
                                              poster: "https://image.tmdb.org/t/p/w500\(poster)",
                                              banner: c.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" },
                                              logo: nil, posterShape: .poster, description: c.overview,
                                              releaseInfo: nil, rawReleaseDate: nil, popularity: nil, voteCount: nil,
                                              imdbRating: nil, genres: [], rawPosterUrl: nil, landscapePoster: nil,
                                              rawLandscapePosterUrl: nil, customPosterApplied: false)
                    return (index, preview)
                }
            }
            var out: [Int: MetaPreview] = [:]
            for await (index, item) in group { if let item { out[index] = item } }
            return out
        }
        return sagaIds.indices.compactMap { found[$0] }
    }

    nonisolated private static func rows(tv: Bool, apiKey: String, language: String) async -> [Extra] {
        let media = tv ? "tv" : "movie"
        let region = OrbitPlatformExtrasModel.region(language: language)
        let kinds = OrbitPlatformBadgeKind.allCases
        let since = String(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-150 * 86_400)).prefix(10))
        let dateKey = tv ? "first_air_date" : "primary_release_date"
        let base = "https://api.themoviedb.org/3/discover/\(media)?api_key=\(apiKey)&language=\(language)"
            + "&watch_region=\(region)&with_watch_monetization_types=flatrate&include_adult=false"
        var specs: [(id: String, title: String, style: OrbitRowStyle, address: String, limit: Int)] = [
            // Steven: the Top 10 of everything, on a platform or not (TMDB's titles of the day).
            ("orbit-top-\(media)", tv ? String(localized: "Top 10 des séries aujourd'hui")
                                      : String(localized: "Top 10 des films aujourd'hui"),
             .ranked, "https://api.themoviedb.org/3/trending/\(media)/day?api_key=\(apiKey)&language=\(language)", 10),
        ]
        for kind in kinds {
            guard let id = kind.providerIds.min() else { continue }
            specs.append(("orbit-new-\(kind)-\(media)", String(localized: "Nouveau sur \(kind.name)"), .landscape,
                          base + "&with_watch_providers=\(id)&sort_by=popularity.desc&\(dateKey).gte=\(since)", 20))
        }
        let lists = await withTaskGroup(of: (Int, [MetaPreview]).self) { group in
            for (index, spec) in specs.enumerated() {
                group.addTask {
                    // The Top 10: two pages, room for the titles without art or synopsis left out.
                    let first = await OrbitPlatformExtrasModel.fetch(spec.address + "&page=1", tv: tv)
                    guard spec.style == .ranked else { return (index, first) }
                    return (index, first + (await OrbitPlatformExtrasModel.fetch(spec.address + "&page=2", tv: tv)))
                }
            }
            var out: [Int: [MetaPreview]] = [:]
            for await (index, items) in group { out[index] = items }
            return out
        }
        // Steven: one row for the platforms' new titles (one per platform ran in a long series),
        // the platforms in turn.
        var out: [Extra] = []
        if let top = lists[0], top.filter({ $0.banner != nil }).count >= 10 {
            out.append(Extra(id: specs[0].id, title: specs[0].title,
                             items: Array(top.filter { $0.banner != nil }.prefix(10)), style: .ranked))
        }
        let perPlatform = specs.indices.dropFirst().map { (lists[$0] ?? []).filter { $0.banner != nil } }
        var mixed: [MetaPreview] = []
        var seen = Set<String>()
        for i in 0..<(perPlatform.map(\.count).max() ?? 0) {
            for list in perPlatform where i < list.count {
                if seen.insert(list[i].id).inserted { mixed.append(list[i]) }
            }
        }
        if mixed.count >= 6 {
            out.append(Extra(id: "orbit-new-\(media)", title: String(localized: "Nouveau sur vos plateformes"),
                             items: Array(mixed.prefix(30)), style: .landscape))
        }

        // Prochainement (everywhere: the platforms and the cinemas), their date on the tile.
        let day: TimeInterval = 86_400
        let iso = ISO8601DateFormatter()
        let tomorrow = String(iso.string(from: Date().addingTimeInterval(day)).prefix(10))
        let later = String(iso.string(from: Date().addingTimeInterval(90 * day)).prefix(10))
        let soonAddress = "https://api.themoviedb.org/3/discover/\(media)?api_key=\(apiKey)&language=\(language)"
            + "&region=\(region)&include_adult=false&sort_by=popularity.desc"
            + "&\(dateKey).gte=\(tomorrow)&\(dateKey).lte=\(later)"
        let soon = await OrbitPlatformExtrasModel.fetch(soonAddress + "&page=1", tv: tv, requiresOverview: false)
            .filter { $0.banner != nil }
        if soon.count >= 6 {
            out.append(Extra(id: "orbit-soon-\(media)", title: String(localized: "Prochainement"),
                             items: Array(soon.prefix(20)), style: .landscape))
        }

        // Les mieux notés (the last five years, enough votes).
        let fiveYears = String(iso.string(from: Date().addingTimeInterval(-5 * 365 * day)).prefix(10))
        let bestAddress = "https://api.themoviedb.org/3/discover/\(media)?api_key=\(apiKey)&language=\(language)"
            + "&include_adult=false&sort_by=vote_average.desc&vote_count.gte=\(tv ? 300 : 1000)&\(dateKey).gte=\(fiveYears)"
        let best = await OrbitPlatformExtrasModel.fetch(bestAddress + "&page=1", tv: tv)
        if best.count >= 6 {
            out.append(Extra(id: "orbit-best-\(media)", title: String(localized: "Les mieux notés"),
                             items: Array(best.prefix(20)), style: .posters))
        }

        // Les grandes sagas (films).
        if !tv {
            let sagas = await sagas(apiKey: apiKey, language: language)
            if sagas.count >= 6 {
                out.append(Extra(id: "orbit-sagas", title: String(localized: "Les grandes sagas"), items: sagas, style: .sagas))
            }
        }
        return out
    }
}
