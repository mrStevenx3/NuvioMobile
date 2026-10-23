import Combine
import SharedCore
import SwiftUI

// Orbit Studios (Steven, 2026-10-23): the Studios page, from top to bottom —
//  - the focused studio's backdrop over the whole screen (its bottom blurred under the content),
//    the studio's logo top left on the Orbit bar's line;
//  - Steven's own studio icons (vertical, a cinema poster's shape) on one line, the focused one
//    clearly larger with the white frame and a shadow, its neighbours a little back;
//  - "Nouveaux films <studio>": the studio's films of the last year on TMDB (most popular first,
//    topped up with its popular films when it released few), following the focused studio,
//    scrolling sideways.
// Down from the bar lands on the first studio (far left); entering the films row lands on its
// first film; back from a studio, the focus is the studio it was opened from.

struct OrbitStudiosPage: View {
    let collection: NuvioCollection

    @FocusState private var focused: String?
    @Environment(\.displayScale) private var displayScale
    /// The studio the page shows (backdrop, logo, films): the focused one, kept when the focus
    /// goes down to the films.
    @State private var shownId: String?
    @ObservedObject private var films = OrbitStudioFilmsModel.shared
    /// Each studio's colour, sampled from its backdrop (the focused icon takes it).
    @State private var tints: [String: Color] = [:]

    @MainActor private static var lastFocused: String?
    @MainActor private static var leftWithFocus = false
    @MainActor private static var restoringUntil: TimeInterval = 0

    static let tileWidth: CGFloat = 190
    static var tileHeight: CGFloat { floor(tileWidth * 1.5) }
    static let tileSpacing: CGFloat = 30
    static let tilesTop: CGFloat = 268
    static let logoSize = CGSize(width: 400, height: 120)

    private var folders: [CollectionFolder] {
        var seen = Set<String>()
        return collection.folders.filter { seen.insert($0.id).inserted }
    }

    private var shownFolder: CollectionFolder? {
        folders.first { $0.id == shownId } ?? folders.first
    }

    var body: some View {
        let L = OrbitHomeLayout.self
        let folders = folders
        let shown = shownFolder
        ZStack(alignment: .topLeading) {
            OrbitStudiosBackdrop(url: Self.backdropURL(shown), blurFrom: 0.3)
                .ignoresSafeArea()

            logo(shown)
                .padding(.leading, L.margin)
                .padding(.top, 28)

            VStack(alignment: .leading, spacing: 44) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Self.tileSpacing) {
                        ForEach(folders, id: \.id) { folder in
                            NavigationLink(value: FolderRoute(collectionId: collection.id, folder: folder)) {
                                OrbitStudioTile(folder: folder,
                                                collectionBackdropUrl: collection.backdropImageUrl,
                                                focused: focused == folder.id,
                                                dimmed: focused != nil && focused != folder.id,
                                                tint: tints[folder.id])
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
                .focusSection()

                OrbitStudioFilmsRow()
                    .padding(.leading, L.margin)
            }
            .padding(.top, Self.tilesTop)
        }
        .frame(width: L.screenWidth, height: L.screenHeight, alignment: .topLeading)
        .ignoresSafeArea()
        // Menu goes to the Orbit bar (not the hidden system tab bar).
        .onExitCommand { NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil) }
        .animation(.easeInOut(duration: 0.3), value: shownId)
        .onChange(of: focused) { old, id in
            guard let id else {
                if old != nil { Self.lostTilesAt = ProcessInfo.processInfo.systemUptime }
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            // Down from the bar: the first studio, not the one under the bar's button. Not on a
            // return from a studio, nor coming back up from the films.
            if old == nil, now > Self.restoringUntil,
               now - OrbitStudioFilmsRow.lostAt > 0.6,
               let first = folders.first, id != first.id {
                focused = first.id
                return
            }
            Self.lastFocused = id
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
                // A new visit opens on the first studio.
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

    @MainActor private static var lostTilesAt: TimeInterval = 0

    /// Steven (Illumination stayed on the slate a moment): every studio's backdrop is fetched
    /// as the page opens, decoded exactly as `OrbitStudiosBackdrop` asks, so a change is instant.
    private func prefetchBackdrops() {
        let request = ArtworkDecodeRequest(size: .points(width: OrbitHomeLayout.screenWidth,
                                                         height: OrbitHomeLayout.screenHeight),
                                           fill: true, scale: displayScale)
        // Each backdrop fetched, then its colour sampled (the colour store samples only art that
        // is already in memory: asked before the fetch, it answered nothing — Steven saw no tint).
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

    private func logo(_ folder: CollectionFolder?) -> some View {
        let url = folder?.titleLogoUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ZStack(alignment: .topLeading) {
            if let url, !url.isEmpty {
                CachedAsyncImage(string: url, contentMode: .fit,
                                 decodeSize: .points(width: Self.logoSize.width, height: Self.logoSize.height))
                    .frame(maxWidth: Self.logoSize.width, maxHeight: Self.logoSize.height, alignment: .topLeading)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 4)
                    .id(url)
                    .transition(.opacity)
            } else if let title = folder?.title {
                Text(title)
                    .font(.system(size: 52, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 4)
                    .id(title)
                    .transition(.opacity)
            }
        }
        .frame(width: Self.logoSize.width, height: Self.logoSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// One studio icon (Steven's own, vertical): its cover, its focus GIF while focused, larger when
/// focused, a little back when another studio is.
private struct OrbitStudioTile: View {
    let folder: CollectionFolder
    let collectionBackdropUrl: String?
    let focused: Bool
    let dimmed: Bool
    /// The studio's colour (from its backdrop): the focused icon's ground takes it.
    var tint: Color? = nil

    var body: some View {
        let size = CGSize(width: OrbitStudiosPage.tileWidth, height: OrbitStudiosPage.tileHeight)
        let radius: CGFloat = 14
        let gif = folder.focusGifUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        ZStack {
            Color(white: 0.12)
            if let cover = OrbitPlatformTile.coverURL(folder, collectionBackdropUrl: collectionBackdropUrl) {
                // Steven (on trial): the focused icon's grey logo goes bright white, its slate a
                // little deeper (a contrast lift around the middle grey, then a touch of light).
                CachedAsyncImage(string: cover, decodeSize: .points(width: size.width, height: size.height))
                    .contrast(focused ? 1.75 : 1)
                    .brightness(focused ? 0.12 : 0)
                // Steven (on trial): the focused icon's dark ground takes the studio's colour; a
                // screen blend leaves the white logo white and lifts only the dark towards it.
                if let tint {
                    tint
                        .blendMode(.screen)
                        .opacity(focused ? 0.9 : 0)
                }
            } else {
                Text(folder.title)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .padding(14)
            }
            if folder.focusGifEnabled, let gif, !gif.isEmpty {
                AnimatedGifImage(string: gif, fallback: nil, contentMode: .fit, isAnimating: focused, targetSize: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : 0.1), lineWidth: focused ? 5 : 1.5)
        }
        .scaleEffect(focused ? 1.14 : (dimmed ? 0.96 : 1))
        .opacity(dimmed ? 0.72 : 1)
        .shadow(color: .black.opacity(focused ? 0.65 : 0.3), radius: focused ? 30 : 10, y: focused ? 16 : 6)
        .zIndex(focused ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: focused)
        .animation(.easeOut(duration: 0.18), value: dimmed)
        .accessibilityLabel(folder.title)
    }
}

// MARK: - The studio's new films

@MainActor
final class OrbitStudioFilmsModel: ObservableObject {
    static let shared = OrbitStudioFilmsModel()

    @Published private(set) var title: String?
    @Published private(set) var items: [MetaPreview] = []

    private var cache: [String: [MetaPreview]] = [:]
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
            withAnimation(.easeInOut(duration: 0.25)) { title = nil; items = [] }
            return
        }
        guard companies != current else { return }
        current = companies
        pending?.cancel()
        if let cached = cache[companies] {
            withAnimation(.easeInOut(duration: 0.25)) { title = folderTitle; items = cached }
            return
        }
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        let language = TmdbSettingsRepository.shared.snapshot().language
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let found = await Self.fetch(companies: companies, apiKey: key, language: language)
            guard !Task.isCancelled, let self, self.current == companies else { return }
            self.cache[companies] = found
            withAnimation(.easeInOut(duration: 0.25)) {
                self.title = found.isEmpty ? nil : folderTitle
                self.items = found
            }
        }
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
    }

    nonisolated private static func fetch(companies: String, apiKey: String, language: String) async -> [MetaPreview] {
        let lang = language.isEmpty ? "fr-FR" : language
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: Date())
        let since = formatter.string(from: Date().addingTimeInterval(-365 * 24 * 3600))
        let encoded = companies.replacingOccurrences(of: "|", with: "%7C")
        let base = "https://api.themoviedb.org/3/discover/movie?api_key=\(apiKey)&language=\(lang)"
            + "&with_companies=\(encoded)&sort_by=popularity.desc&page=1"
        var found = await results(base + "&primary_release_date.gte=\(since)&primary_release_date.lte=\(today)")
        if found.count < 8 {
            let popular = await results(base + "&vote_count.gte=100")
            let seen = Set(found.map(\.id))
            found += popular.filter { !seen.contains($0.id) }
        }
        return found.compactMap { r -> MetaPreview? in
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
    }

    nonisolated private static func results(_ address: String) async -> [Response.Result] {
        guard let url = URL(string: address),
              let response = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(Response.self, from: response.0) else { return [] }
        return decoded.results ?? []
    }
}

/// "Nouveaux films <studio>", scrolling sideways; entering it lands on its first film.
struct OrbitStudioFilmsRow: View {
    @ObservedObject private var model = OrbitStudioFilmsModel.shared
    @FocusState private var focused: String?
    @MainActor static var lostAt: TimeInterval = 0

    static let posterWidth: CGFloat = 160
    static var posterHeight: CGFloat { 240 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title = model.title, !model.items.isEmpty {
                Text(String(format: String(localized: "Nouveaux films %@"), title))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 22) {
                        ForEach(model.items, id: \.id) { item in
                            NavigationLink(value: TitleRoute(preview: item)) {
                                OrbitStudioFilmPoster(item: item, focused: focused == item.id)
                            }
                            .buttonStyle(OrbitPlatformTileStyle())
                            .focused($focused, equals: item.id)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.trailing, OrbitHomeLayout.margin)
                }
                .scrollClipDisabled()
                .padding(.vertical, -14)
                .id("films-\(title)")
                .transition(.opacity)
            }
        }
        .focusSection()
        .onChange(of: focused) { old, id in
            guard let id else { Self.lostAt = ProcessInfo.processInfo.systemUptime; return }
            if old == nil, let first = model.items.first, id != first.id { focused = first.id }
        }
    }
}

private struct OrbitStudioFilmPoster: View {
    let item: MetaPreview
    let focused: Bool

    var body: some View {
        let size = CGSize(width: OrbitStudioFilmsRow.posterWidth, height: OrbitStudioFilmsRow.posterHeight)
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
