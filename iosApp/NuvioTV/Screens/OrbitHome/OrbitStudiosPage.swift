import Combine
import SharedCore
import SwiftUI

// Orbit Studios (Steven, 2026-10-24, second version): the Studios page in Orbit's own language —
//  - the focused studio's backdrop over the whole screen, its logo and its figures
//    ("Studio · 432 films") on the left as a hero;
//  - the studios as landscape tiles, six to seven a screen, each its logo in white on its own
//    colour (dimmed when another is focused, full when focused, with the white frame and a lift);
//  - two rows of the focused studio's films in small portrait posters, in fixed places on the
//    screen: "Nouveautés" (its real recent releases, no shorts) and "Les incontournables" (its
//    best rated) — "Les plus populaires" takes a missing one's place (Ghibli: no recent film).
// Down from the bar lands on the first studio (far left); entering a row lands on its first film;
// up from the films, back on the studio whose films they are; back from a studio, the focus is
// the studio it was opened from.

struct OrbitStudiosPage: View {
    let collection: NuvioCollection

    @FocusState private var focused: String?
    /// The tile drawn as focused: `focused`, followed in an explicit animation.
    @State private var lit: String?
    @Environment(\.displayScale) private var displayScale
    /// The studio the page shows (backdrop, logo, films): the focused one, kept when the focus
    /// goes down to the films.
    @State private var shownId: String?
    @ObservedObject private var films = OrbitStudioFilmsModel.shared
    /// Each studio's colour, sampled from its backdrop (a known brand colour first).
    @State private var tints: [String: Color] = [:]
    /// The way the focus went along the tiles (right: true): the studio's name slides that way.
    @State private var forward = true

    @MainActor private static var lastFocused: String?
    @MainActor private static var leftWithFocus = false
    @MainActor private static var restoringUntil: TimeInterval = 0
    @MainActor private static var lostTilesAt: TimeInterval = 0

    static let tileSize = CGSize(width: 236, height: 133)
    static let tileSpacing: CGFloat = 24
    static let heroTop: CGFloat = 112
    static let logoSize = CGSize(width: 380, height: 100)

    private var folders: [CollectionFolder] {
        var seen = Set<String>()
        return collection.folders.filter { seen.insert($0.id).inserted }
    }

    private var shownFolder: CollectionFolder? {
        folders.first { $0.id == shownId } ?? folders.first
    }

    private func tint(_ folder: CollectionFolder) -> Color {
        OrbitPlatformBrand.known(title: folder.title) ?? tints[folder.id] ?? OrbitPlatformBrand.color(title: folder.title)
    }

    var body: some View {
        let L = OrbitHomeLayout.self
        let folders = folders
        let shown = shownFolder
        let selectedId = shownId ?? folders.first?.id
        ZStack(alignment: .topLeading) {
            // Steven: less blur, the art shows more (the blur starts under the first row).
            OrbitStudiosBackdrop(url: Self.backdropURL(shown), blurFrom: 0.62)
                .ignoresSafeArea()
            // The studio's name and figures read over any backdrop (a light veil, the backdrop
            // has its own).
            LinearGradient(stops: [
                .init(color: .black.opacity(0.35), location: 0),
                .init(color: .clear, location: 0.45),
            ], startPoint: .leading, endPoint: .trailing)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Everything on one screen (no page scroll: it slid the studio's name under the bar).
            VStack(alignment: .leading, spacing: 0) {
                    hero(shown)
                        .padding(.leading, L.margin)
                        .padding(.top, Self.heroTop)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Self.tileSpacing) {
                            ForEach(folders, id: \.id) { folder in
                                NavigationLink(value: OrbitStudioRoute.folder(collectionId: collection.id, folder: folder)) {
                                    OrbitStudioTile(folder: folder,
                                                    focused: lit == folder.id,
                                                    selected: lit == nil && folder.id == selectedId,
                                                    tint: tint(folder))
                                }
                                .buttonStyle(OrbitPlatformTileStyle())
                                .focused($focused, equals: folder.id)
                            }
                        }
                        .padding(.vertical, 30)
                        .padding(.horizontal, L.margin)
                    }
                    .scrollClipDisabled()
                    .padding(.vertical, -30)
                    .padding(.top, 30)
                    .focusSection()

                    // Two fixed slots: they never move, only their content changes.
                    OrbitStudioFilmsRow(slot: 0)
                        .padding(.top, 40)
                    OrbitStudioFilmsRow(slot: 1)
                        .padding(.top, 30)
            }
            .frame(width: L.screenWidth, alignment: .leading)
        }
        .frame(width: L.screenWidth, height: L.screenHeight, alignment: .topLeading)
        .ignoresSafeArea()
        // Menu goes to the Orbit bar (not the hidden system tab bar).
        .onExitCommand { NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil) }
        .animation(.easeInOut(duration: 0.3), value: shownId)
        .onChange(of: focused) { old, id in
            guard let id else {
                if old != nil { Self.lostTilesAt = ProcessInfo.processInfo.systemUptime }
                withAnimation(.easeInOut(duration: 0.3)) { lit = nil }
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            // Up from the films: back on the studio whose films they are.
            let fromFilms = OrbitStudioFilmsRow.hasFocus || now - OrbitStudioFilmsRow.lostAt < 0.6
            if old == nil, fromFilms, let selected = shownId ?? folders.first?.id, id != selected {
                focused = selected
                return
            }
            // Down from the bar: the first studio, not the one under the bar's button.
            if old == nil, now > Self.restoringUntil, !fromFilms,
               let first = folders.first, id != first.id {
                focused = first.id
                return
            }
            withAnimation(.easeOut(duration: 0.2)) { lit = id }
            Self.lastFocused = id
            if let from = folders.firstIndex(where: { $0.id == shownId }),
               let to = folders.firstIndex(where: { $0.id == id }), from != to {
                forward = to > from
            }
            shownId = id
            if let folder = folders.first(where: { $0.id == id }) {
                films.focus(title: folder.title)
            }
        }
        .onAppear {
            if Self.leftWithFocus, let last = Self.lastFocused, folders.contains(where: { $0.id == last }) {
                Self.leftWithFocus = false
                shownId = last
                restore(last)
            } else {
                shownId = folders.first?.id
            }
            if let folder = shownFolder { films.focus(title: folder.title) }
            prefetchBackdrops()
        }
        .onDisappear {
            let now = ProcessInfo.processInfo.systemUptime
            Self.leftWithFocus = focused != nil || now - Self.lostTilesAt < 1.0
        }
    }

    /// Every studio's backdrop fetched as the page opens (a change is instant), then its colour.
    private func prefetchBackdrops() {
        let request = ArtworkDecodeRequest(size: .points(width: OrbitHomeLayout.screenWidth,
                                                         height: OrbitHomeLayout.screenHeight),
                                           fill: true, scale: displayScale)
        let jobs: [(id: String, raw: String, url: URL)] = folders.compactMap { folder in
            guard let raw = Self.backdropURL(folder), let url = URL(string: raw) else { return nil }
            return (folder.id, raw, url)
        }
        Task(priority: .utility) {
            for job in jobs {
                if ArtworkStore.cached(job.url, decode: request) == nil {
                    _ = try? await ArtworkStore.fetch(job.url, decode: request)
                }
                await MainActor.run { sampleTint(id: job.id, raw: job.raw) }
            }
        }
    }

    private func sampleTint(id: String, raw: String) {
        guard tints[id] == nil else { return }
        if let cached = ArtworkColorStore.shared.cachedColor(for: [raw], use: .wash) {
            tints[id] = cached
            return
        }
        ArtworkColorStore.shared.color(for: [raw], use: .wash) { color in
            if let color { tints[id] = color }
        }
    }

    /// Back from a studio: the tile it was opened from (asked a few times: the engine's own
    /// restoration lands late), until the viewer presses anything.
    private func restore(_ id: String) {
        let start = ProcessInfo.processInfo.systemUptime
        Self.restoringUntil = start + 1.6
        for delay in [0.0, 0.15, 0.35, 0.6, 0.9, 1.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !ViewerInputClock.shared.hasInput(since: start), focused != id else { return }
                focused = id
            }
        }
    }

    static func backdropURL(_ folder: CollectionFolder?) -> String? {
        let url = folder?.heroBackdropUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (url?.isEmpty ?? true) ? nil : url
    }

    static func logoURL(_ folder: CollectionFolder?) -> String? {
        let url = folder?.titleLogoUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (url?.isEmpty ?? true) ? nil : url
    }

    /// The hero: the studio's logo, then its figures.
    /// Steven (2026-10-24): the name slides out the way the focus went and the next one slides in
    /// from the other side (right on the tiles: out to the left, in from the right).
    private var slide: AnyTransition {
        let distance: CGFloat = 90
        return .asymmetric(
            insertion: .offset(x: forward ? distance : -distance).combined(with: .opacity),
            removal: .offset(x: forward ? -distance : distance).combined(with: .opacity))
    }

    private func hero(_ folder: CollectionFolder?) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ZStack(alignment: .bottomLeading) {
                if let url = Self.logoURL(folder) {
                    CachedAsyncImage(string: url, contentMode: .fit,
                                     decodeSize: .points(width: Self.logoSize.width, height: Self.logoSize.height))
                        .frame(maxWidth: Self.logoSize.width, maxHeight: Self.logoSize.height, alignment: .bottomLeading)
                        .shadow(color: .black.opacity(0.45), radius: 18, y: 4)
                        .id(url)
                        .transition(slide)
                } else if let title = folder?.title {
                    Text(title)
                        .font(.system(size: 64, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .shadow(color: .black.opacity(0.45), radius: 18, y: 4)
                        .id(title)
                        .transition(slide)
                }
            }
            .frame(width: Self.logoSize.width, height: Self.logoSize.height, alignment: .bottomLeading)

            Text(films.statsLine ?? " ")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .shadow(color: .black.opacity(0.5), radius: 8)
                .frame(height: 34, alignment: .leading)
                .id(films.statsLine ?? "-")
                .transition(slide)
        }
        .allowsHitTesting(false)
    }
}

/// One studio tile, landscape: its logo in white on its own colour; dimmed while another studio
/// is focused, full with the white frame and a lift when focused (half-way while the focus is on
/// its films below).
private struct OrbitStudioTile: View {
    let folder: CollectionFolder
    let focused: Bool
    var selected: Bool = false
    let tint: Color

    var body: some View {
        let size = OrbitStudiosPage.tileSize
        let radius: CGFloat = 14
        let lift: CGFloat = focused ? 1 : (selected ? 0.6 : 0)
        ZStack {
            Color(white: 0.08)
            LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.55 + 0.45 * lift)
            if let logo = OrbitStudiosPage.logoURL(folder) {
                CachedAsyncImage(string: logo, contentMode: .fit,
                                 decodeSize: .points(width: size.width - 56, height: size.height - 50),
                                 loading: { Color.clear }, failure: { name })
                    .frame(maxWidth: size.width - 56, maxHeight: size.height - 50)
                    // The logos are white or light: kept white on the colour.
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            } else {
                name
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : (selected ? 0.5 : 0.12)),
                              lineWidth: focused ? 4 : (selected ? 3 : 1.5))
        }
        .scaleEffect(focused ? 1.1 : (selected ? 1.05 : 1))
        .shadow(color: .black.opacity(0.3 + 0.3 * lift), radius: 10 + 16 * lift, y: 6 + 8 * lift)
        .zIndex(focused || selected ? 1 : 0)
        .accessibilityLabel(folder.title)
    }

    private var name: some View {
        Text(folder.title)
            .font(.system(size: 26, weight: .heavy))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .padding(16)
    }
}

// MARK: - The studio's films

@MainActor
final class OrbitStudioFilmsModel: ObservableObject {
    static let shared = OrbitStudioFilmsModel()

    @Published private(set) var title: String?
    /// The two rows shown: "Nouveautés" (when the studio has recent releases), "Les
    /// incontournables", "Les plus populaires" — the first two of them.
    @Published private(set) var rows: [(title: String, items: [MetaPreview])] = []
    /// "Studio · 432 films".
    @Published private(set) var statsLine: String?

    private struct Found {
        var recent: [MetaPreview]
        var best: [MetaPreview]
        var popular: [MetaPreview]
        var count: Int
    }

    private var cache: [String: Found] = [:]
    private var pending: Task<Void, Never>?
    private var current: String?

    /// TMDB company ids for a studio folder, from its title.
    static func companies(forTitle raw: String) -> String? {
        let t = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        if t.contains("pixar") { return "3" }
        if t.contains("marvel") { return "420" }
        if t.contains("lucasfilm") || t.contains("starwars") { return "1" }
        if t.contains("dreamworks") { return "521" }
        if t.contains("illumination") { return "6704" }
        if t.contains("ghibli") { return "10342" }
        if t.contains("dc") { return "128064|9993" }
        if t.contains("warner") { return "174" }
        if t.contains("universal") { return "33" }
        if t.contains("sony") || t.contains("columbia") { return "34|5" }
        if t.contains("paramount") { return "4" }
        if t.contains("20th") || t.contains("century") { return "25|127928" }
        if t.contains("a24") { return "41077" }
        if t.contains("blumhouse") { return "3172" }
        if t.contains("legendary") { return "923" }
        if t.contains("lionsgate") { return "1632" }
        if t.contains("pathe") { return "7981|866" }
        if t.contains("gaumont") { return "9" }
        if t.contains("studiocanal") { return "694" }
        if t.contains("disney") { return "2|6125" }
        return nil
    }

    func focus(title folderTitle: String) {
        guard let companies = Self.companies(forTitle: folderTitle) else {
            pending?.cancel()
            current = nil
            withAnimation(.easeInOut(duration: 0.25)) { title = nil; rows = []; statsLine = nil }
            return
        }
        guard companies != current else { return }
        current = companies
        pending?.cancel()
        if let cached = cache[companies] {
            withAnimation(.easeInOut(duration: 0.25)) { show(cached, title: folderTitle) }
            return
        }
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        let language = TmdbSettingsRepository.shared.snapshot().language
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let lists = await Self.fetch(companies: companies, apiKey: key, language: language)
            guard !Task.isCancelled, let self, self.current == companies else { return }
            let found = Found(recent: lists.recent, best: lists.best, popular: lists.popular, count: lists.count)
            self.cache[companies] = found
            withAnimation(.easeInOut(duration: 0.25)) { self.show(found, title: folderTitle) }
        }
    }

    private func show(_ found: Found, title folderTitle: String) {
        title = folderTitle
        var list: [(title: String, items: [MetaPreview])] = []
        if found.recent.count >= 3 { list.append((String(localized: "Nouveautés"), found.recent)) }
        if found.best.count >= 3 { list.append((String(localized: "Les incontournables"), found.best)) }
        let bestIds = Set(found.best.prefix(20).map(\.id))
        let popular = found.popular.filter { !bestIds.contains($0.id) }
        if popular.count >= 3 { list.append((String(localized: "Les plus populaires"), popular)) }
        rows = Array(list.prefix(2))
        statsLine = found.count > 0 ? String(localized: "Studio · \(found.count) films") : String(localized: "Studio")
    }

    nonisolated private struct Response: Decodable {
        nonisolated struct Result: Decodable {
            let id: Int
            let title: String?
            let overview: String?
            let poster_path: String?
            let backdrop_path: String?
            let release_date: String?
            let vote_average: Double?
        }
        let results: [Result]?
        let total_results: Int?
    }

    /// "Nouveautés": the films out in the last eighteen months (feature length, most popular of
    /// them, newest first); "Les incontournables": the best rated (feature length, well known).
    nonisolated private static func fetch(companies: String, apiKey: String, language: String) async
        -> (recent: [MetaPreview], best: [MetaPreview], popular: [MetaPreview], count: Int) {
        let lang = language.isEmpty ? "fr-FR" : language
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: Date())
        let since = formatter.string(from: Date().addingTimeInterval(-548 * 24 * 3600))
        let encoded = companies.replacingOccurrences(of: "|", with: "%7C")
        let base = "https://api.themoviedb.org/3/discover/movie?api_key=\(apiKey)&language=\(lang)"
            + "&with_companies=\(encoded)&with_runtime.gte=60"
        async let recentCall = results(base + "&sort_by=popularity.desc&primary_release_date.gte=\(since)&primary_release_date.lte=\(today)")
        async let bestCall = results(base + "&sort_by=vote_average.desc&vote_count.gte=300")
        async let popularCall = results(base + "&sort_by=popularity.desc&vote_count.gte=50")
        async let allCall = results("https://api.themoviedb.org/3/discover/movie?api_key=\(apiKey)&with_companies=\(encoded)")
        let (recentValue, bestValue, popularValue, allValue) = await (recentCall, bestCall, popularCall, allCall)
        let recent = recentValue.items.sorted { ($0.release_date ?? "") > ($1.release_date ?? "") }
        return (recent.compactMap(preview), bestValue.items.compactMap(preview),
                popularValue.items.compactMap(preview), allValue.total)
    }

    nonisolated private static func preview(_ r: Response.Result) -> MetaPreview? {
        guard let name = r.title, !name.isEmpty, let poster = r.poster_path else { return nil }
        return MetaPreview(id: "tmdb:\(r.id)", type: "movie", name: name,
                           poster: "https://image.tmdb.org/t/p/w500\(poster)",
                           banner: r.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" },
                           logo: nil, posterShape: .poster,
                           description: r.overview, releaseInfo: r.release_date.map { String($0.prefix(4)) },
                           rawReleaseDate: r.release_date, popularity: nil, voteCount: nil,
                           imdbRating: r.vote_average.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil },
                           genres: [], rawPosterUrl: nil, landscapePoster: nil,
                           rawLandscapePosterUrl: nil, customPosterApplied: false)
    }

    nonisolated private static func results(_ address: String) async -> (items: [Response.Result], total: Int) {
        guard let url = URL(string: address),
              let response = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(Response.self, from: response.0) else { return ([], 0) }
        return (decoded.results ?? [], decoded.total_results ?? 0)
    }
}

/// A row of the studio's films in small portrait posters, scrolling sideways; entering it lands
/// on its first film.
struct OrbitStudioFilmsRow: View {
    /// 0: the upper row, 1: the lower one.
    let slot: Int

    @ObservedObject private var model = OrbitStudioFilmsModel.shared
    @FocusState private var focused: String?
    @MainActor static var lostAt: TimeInterval = 0
    /// A film (of either row) holds the focus (read by the studios' line when the focus comes up).
    @MainActor static var hasFocus = false
    @MainActor private static var holders = 0

    static let posterSize = CGSize(width: 150, height: 225)

    private var row: (title: String, items: [MetaPreview])? {
        model.rows.indices.contains(slot) ? model.rows[slot] : nil
    }
    private var items: [MetaPreview] { row?.items ?? [] }

    var body: some View {
        let items = items
        VStack(alignment: .leading, spacing: 14) {
            if let title = model.title, let heading = row?.title {
                Text(heading)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    .frame(height: 40)
                    .padding(.leading, OrbitHomeLayout.margin)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        ForEach(items, id: \.id) { item in
                            NavigationLink(value: TitleRoute(preview: item)) {
                                OrbitStudioFilmPoster(item: item, focused: focused == item.id)
                            }
                            .buttonStyle(OrbitPlatformTileStyle())
                            .focused($focused, equals: item.id)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, OrbitHomeLayout.margin)
                }
                .scrollClipDisabled()
                .padding(.vertical, -16)
                .id("films-\(heading)-\(title)")
                .transition(.opacity)
            }
        }
        // The slot keeps its height when empty (the rows never move).
        .frame(height: 40 + 14 + Self.posterSize.height, alignment: .topLeading)
        .focusSection()
        .onChange(of: focused) { old, id in
            if old == nil, id != nil { Self.holders += 1 }
            if old != nil, id == nil { Self.holders = max(0, Self.holders - 1) }
            Self.hasFocus = Self.holders > 0
            guard let id else { Self.lostAt = ProcessInfo.processInfo.systemUptime; return }
            if old == nil, let first = items.first, id != first.id { focused = first.id }
        }
    }
}

private struct OrbitStudioFilmPoster: View {
    let item: MetaPreview
    let focused: Bool

    var body: some View {
        let size = OrbitStudioFilmsRow.posterSize
        ZStack {
            Color(white: 0.12)
            OrbitImage(url: item.poster, size: size)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 4)
        }
        .scaleEffect(focused ? 1.08 : 1)
        .shadow(color: .black.opacity(focused ? 0.55 : 0.25), radius: 16, y: 8)
        .animation(.easeOut(duration: 0.14), value: focused)
        .accessibilityLabel(item.name)
    }
}
