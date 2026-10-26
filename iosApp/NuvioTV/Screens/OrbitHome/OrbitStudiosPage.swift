import Combine
import SharedCore
import SwiftUI
import UIKit

// Orbit Studios (Steven, 2026-10-24, third version): the Studios page in Orbit's own language —
//  - the page on the focused studio's colour; its backdrop whole in a large frame top right
//    (rounded, a shadow, as on the platforms); on the left its logo, "Studio · 432 films" and its
//    latest films;
//  - the studios as landscape tiles, each its logo in white on its own colour;
//  - one row of the studio's films in portrait posters: "Les incontournables" (Steven, 2026-10-25:
//    on every studio; "Les plus populaires" when TMDB has too few).
// Down from the bar lands on the first studio (far left); entering a row lands where the system puts it;
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
    /// The tile a studio was opened from, while the page comes back.
    @State private var restoreTarget: String?

    @MainActor private static var lastFocused: String?
    @MainActor private static var leftWithFocus = false
    @MainActor private static var restoringUntil: TimeInterval = 0
    @MainActor private static var lostTilesAt: TimeInterval = 0

    static let tileSize = CGSize(width: 236, height: 133)
    static let tileSpacing: CGFloat = 24
    static let heroTop: CGFloat = 112
    static let logoSize = CGSize(width: 460, height: 130)
    /// The framed backdrop, top right.
    /// Steven (2026-10-26): the large image takes the top of the screen, the studios under it at
    /// the bottom (their size unchanged).
    static let frameSize = CGSize(width: 1760, height: 690)

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

    @Environment(\.orbitPushStudio) private var pushStudio

    var body: some View {
        let L = OrbitHomeLayout.self
        let folders = folders
        let shown = shownFolder
        let selectedId = shownId ?? folders.first?.id
        ZStack(alignment: .topLeading) {
            // Steven (2026-10-24): the page on the studio's colour; its backdrop in a large frame
            // top right (whole, no blur, a shadow as on the platforms) — the image no longer runs
            // under the tiles and the posters.
            let ground = shown.map(tint) ?? OrbitPlatformBrand.color(title: "")
            ZStack {
                OrbitHomeLayout.background
                LinearGradient(stops: [
                    .init(color: ground.opacity(0.8), location: 0),
                    .init(color: ground.opacity(0.42), location: 0.5),
                    .init(color: ground.opacity(0.15), location: 1),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: shown?.id)

            // Steven (2026-10-24): a panoramic frame across the page, centred; the studio's name
            // on it, bottom left (a soft shade in that corner only).
            OrbitStudioFrame(url: Self.backdropURL(shown), forward: forward,
                             lift: OrbitStudioFrame.lift(title: shown?.title ?? ""))
                .overlay(alignment: .bottomLeading) {
                    hero(shown)
                        .padding(.leading, 36)
                        .padding(.bottom, 26)
                }
                .offset(x: L.margin, y: Self.heroTop)

            // Everything on one screen (no page scroll: it slid the studio's name under the bar).
            VStack(alignment: .leading, spacing: 0) {
                    // The frame's place (it is drawn above).
                    Color.clear
                        .frame(width: 1, height: Self.heroTop + Self.frameSize.height)
                        .allowsHitTesting(false)

                    // Steven (device: from DC to Lucasfilm and on, the row jumped — the system's own
                    // scroll): the row glides on one curve, the focused studio kept at the centre
                    // once past the first ones, at every move alike.
                    ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Self.tileSpacing) {
                            ForEach(folders, id: \.id) { folder in
                                // Steven: the studio's opening before its page — black first, the page
                                // pushed under it (its own opening takes over the black).
                                Button {
                                    let route = OrbitStudioRoute.folder(collectionId: collection.id, folder: folder)
                                    if let pushStudio { OrbitPlatformCurtain.shared.drop { pushStudio(route) } }
                                } label: {
                                    OrbitStudioTile(folder: folder,
                                                    focused: lit == folder.id,
                                                    selected: lit == nil && folder.id == selectedId,
                                                    tint: tint(folder))
                                }
                                .buttonStyle(OrbitPlatformTileStyle())
                                .focused($focused, equals: folder.id)
                                // Back from a studio, only its tile can take the focus for a moment
                                // (Steven, simulator: it went to Walt Disney first, then came back).
                                .disabled(restoreTarget != nil && restoreTarget != folder.id)
                                .id(folder.id)
                            }
                        }
                        .padding(.vertical, 30)
                        .padding(.horizontal, L.margin)
                    }
                    .onChange(of: focused) { _, id in
                        guard let id, folders.contains(where: { $0.id == id }) else { return }
                        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
                    }
                    }
                    .scrollClipDisabled()
                    .padding(.vertical, -30)
                    .padding(.top, 40)
                    .focusSection()

                    // (Steven, 2026-10-26: the row of the studio's films is gone — the studios
                    // alone.)
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
        // Back from a studio, the system lands on its tile straight away (Steven, simulator: it
        // went to another studio first, then came back).
        .defaultFocus($focused, restoreTarget, priority: .userInitiated)
        .onAppear {
            if Self.leftWithFocus, let last = Self.lastFocused, folders.contains(where: { $0.id == last }) {
                Self.leftWithFocus = false
                shownId = last
                restoreTarget = last
                restore(last)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { restoreTarget = nil }
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
        let request = ArtworkDecodeRequest(size: .points(width: Self.frameSize.width,
                                                         height: Self.frameSize.width * 9 / 16),
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
    /// Steven (2026-10-24): the name follows the focus — right on the tiles, it leaves to the right
    /// and the next one comes in from the left.
    /// Steven (2026-10-26): the logo in a plain fade, nothing else (no glide).
    private var slide: AnyTransition {
        .opacity.animation(.easeInOut(duration: 0.35))
    }

    /// Fixed places (Steven: from Disney to Pixar the logo moved, the block was centred and its
    /// height changed): the logos sit on one line, the figures and the latest films under it.
    private func hero(_ folder: CollectionFolder?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                if let url = Self.logoURL(folder) {
                    OrbitBalancedLogo(url: url, area: 38_000, maxSize: Self.logoSize,
                                      whiten: OrbitBalancedLogo.isGrey(folder?.title ?? ""), alignment: .bottomLeading)
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

        }
        .allowsHitTesting(false)
    }
}

/// The studio's backdrop in a frame: whole, rounded, a soft shadow. A new studio's image comes in
/// over the old one with a short glide the way the focus went and a slight zoom settling (the
/// logo on the right glides the same way).
private struct OrbitStudioFrame: View {
    let url: String?
    let forward: Bool
    /// How far the image is lowered in the frame from its centre (0…1 of what the frame cuts):
    /// the panorama crops the top and bottom of a 16:9 image, a head may be cut.
    var lift: CGFloat = 0

    /// Steven: Darth Vader's head was cut (Lucasfilm).
    static func lift(title raw: String) -> CGFloat {
        let t = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if t.contains("lucasfilm") || t.contains("star wars") { return 0.75 }
        return 0
    }

    @State private var zoom: CGFloat = 1
    @State private var shift: CGFloat = 0

    var body: some View {
        let size = OrbitStudiosPage.frameSize
        let radius: CGFloat = 22
        ZStack {
            Color(white: 0.1)
            // The image drawn whole at the frame's width (16:9), the frame showing its middle band,
            // lowered by `lift`.
            let full = CGSize(width: size.width, height: size.width * 9 / 16)
            let spare = max(0, full.height - size.height) / 2
            // Steven (device: Lucasfilm and Illumination switched differently): Lucasfilm's lift
            // belongs to its image — it no longer jumps the whole frame (the old image with it).
            OrbitSwapImage(url: url, fallback: nil, size: full, shiftY: spare * lift)
                .frame(width: full.width, height: full.height)
                .frame(width: size.width, height: size.height)
                .scaleEffect(zoom)
                .offset(x: shift)
            // The name reads at the bottom left; the rest of the image stays clean.
            RadialGradient(colors: [.black.opacity(0.62), .black.opacity(0.25), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 820)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
        // (Steven, 2026-10-26: the image in a plain fade — no glide, no zoom.)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A logo drawn at a balanced size: every logo covers about the same area (a tall, narrow one —
/// Ghibli, DreamWorks — no longer ends up tiny next to a wide one — Illumination), within a
/// maximum box. `whiten`: a grey logo drawn white (its shape kept).
struct OrbitBalancedLogo: View {
    let url: String
    let area: CGFloat
    let maxSize: CGSize
    var whiten = false
    var alignment: Alignment = .center
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    /// Steven's grey logos (unreadable on a colour).
    static func isGrey(_ raw: String) -> Bool {
        let t = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return t.contains("ghibli") || t.contains("pixar")
    }

    var body: some View {
        ZStack(alignment: alignment) {
            if let image, image.size.width > 0, image.size.height > 0 {
                let fitted = Self.size(aspect: image.size.width / image.size.height, area: area, max: maxSize)
                let picture = Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                Group {
                    if whiten {
                        // Steven: Pixar's and Ghibli's thin, half-transparent lines read pale even
                        // whitened — drawn three times over, they come out solid white.
                        ZStack {
                            ForEach(0..<3, id: \.self) { _ in picture.colorMultiply(.black).colorInvert() }
                        }
                    } else {
                        picture
                    }
                }
                .frame(width: fitted.width, height: fitted.height)
            }
        }
        .frame(width: maxSize.width, height: maxSize.height, alignment: alignment)
        .task(id: url) { await load() }
    }

    static func size(aspect: CGFloat, area: CGFloat, max: CGSize) -> CGSize {
        var width = (area * aspect).squareRoot()
        var height = width / aspect
        if width > max.width { width = max.width; height = width / aspect }
        if height > max.height { height = max.height; width = height * aspect }
        return CGSize(width: width, height: height)
    }

    private func load() async {
        guard let address = URL(string: url) else { image = nil; return }
        let request = ArtworkDecodeRequest(size: .points(width: maxSize.width, height: maxSize.height),
                                           fill: false, scale: displayScale)
        if let hit = ArtworkStore.cached(address, decode: request) { image = hit; return }
        image = try? await ArtworkStore.fetch(address, decode: request)
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
                // The thin logos (Pixar, Ghibli) a little larger, to read as well as the others.
                OrbitBalancedLogo(url: logo, area: OrbitBalancedLogo.isGrey(folder.title) ? 10_500 : 7_600,
                                  maxSize: CGSize(width: size.width - 50, height: size.height - 40),
                                  whiten: OrbitBalancedLogo.isGrey(folder.title), alignment: .center)
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
    /// "Derniers films : Thunderbolts*, Les 4 Fantastiques".
    @Published private(set) var latestLine: String?

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
            withAnimation(.easeInOut(duration: 0.25)) { title = nil; rows = []; statsLine = nil; latestLine = nil }
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
        // Steven: "Les incontournables" everywhere (a studio with few new films looked empty).
        if found.best.count >= 3 { list.append((String(localized: "Les incontournables"), found.best)) }
        let bestIds = Set(found.best.prefix(20).map(\.id))
        let popular = found.popular.filter { !bestIds.contains($0.id) }
        if popular.count >= 3 { list.append((String(localized: "Les plus populaires"), popular)) }
        // One row: the essentials (the most popular when TMDB has too few well-rated ones).
        rows = Array(list.prefix(1))
        // Only with real recent releases (Ghibli showed an obscure 1987 documentary).
        let latest = found.recent.count >= 6 ? found.recent.prefix(2).map(\.name) : []
        latestLine = latest.isEmpty ? nil : String(localized: "Derniers films : \(latest.joined(separator: ", "))")
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
        async let popular2Call = results(base + "&sort_by=popularity.desc&vote_count.gte=50&page=2")
        async let allCall = results("https://api.themoviedb.org/3/discover/movie?api_key=\(apiKey)&with_companies=\(encoded)")
        let (recentValue, bestValue, popularValue, popular2Value, allValue) =
            await (recentCall, bestCall, popularCall, popular2Call, allCall)
        let recent = recentValue.items.sorted { ($0.release_date ?? "") > ($1.release_date ?? "") }
        return (recent.compactMap(preview), bestValue.items.compactMap(preview),
                (popularValue.items + popular2Value.items).compactMap(preview), allValue.total)
    }

    nonisolated private static func preview(_ r: Response.Result) -> MetaPreview? {
        guard let name = r.title, !name.isEmpty, let poster = r.poster_path else { return nil }
        return MetaPreview(id: "tmdb:\(r.id)", type: "movie", name: name,
                           poster: "https://image.tmdb.org/t/p/w780\(poster)",
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

/// A row of the studio's films in small portrait posters, scrolling sideways (no return to its
/// start: the focus lands where the system puts it, as in Apple's app).
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
