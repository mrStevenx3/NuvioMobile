import Combine
import SharedCore
import SwiftUI

// Orbit × Disney+ (Steven, 2026-10-25): the Disney+ folder in Disney+'s own look, with Orbit's DNA
// kept (one focusable canvas — the page moves, the focus stays; the collection bar top left with
// the house; the platform's intro; trailers on a rest).
//
//  - A near-black navy page. The hero: a carousel of the new titles, its art full width fading
//    into the page, the logo, "TP · 2025 · Animation · 1 h 40", two lines of synopsis, DÉTAILS and
//    the dots. Left / Right go through it; it moves on by itself after a trailer or a long rest.
//    (Steven, pass 2: no brand tiles, as in Disney+'s 2026 app.)
//  - Then the rows: the Top 10 as Disney+'s own cards (the rank in turquoise on a dark arc, the
//    poster without its title, the logo, the rating and the year under it), the others as 16:9
//    tiles with the title's logo, its name and "TP · 2025 · Animation" under them.
//  - At the top centre, "Disney+ · Hulu": Hulu shows the Hulu titles of Disney+ (TMDB: Hulu's
//    network for the series, its companies for the films).

enum OrbitDisneyLayout {
    /// The newest app's page: a deep slate blue (Steven's video), lighter at the top left.
    static let background = Color(red: 0.075, green: 0.095, blue: 0.14)
    static let backgroundGlow = Color(red: 0.16, green: 0.22, blue: 0.31)
    static let turquoise = Color(red: 0.13, green: 0.73, blue: 0.80)
    static let brandBlue = Color(red: 0.06, green: 0.22, blue: 0.62)
    /// Hulu's green (#1CE783).
    static let huluGreen = Color(red: 0.11, green: 0.91, blue: 0.51)
    static let margin: CGFloat = OrbitHomeLayout.margin
    /// The hero's art (full width), its text block.
    /// Steven: the hero larger, its art running on under the first row's posters.
    static let heroArtHeight: CGFloat = 1080
    static let infoTop: CGFloat = 200
    static let logoSize = CGSize(width: 620, height: 190)
    static let synopsisWidth: CGFloat = 820
    /// The first row's top: its heading and the top of its cards on the first screen.
    /// A tile's name and meta line under it.
    static let labelHeight: CGFloat = 76
    /// Where the current row's top rests once the hero has gone.
    static let restTop: CGFloat = 160
    /// The platform's logo at the hero's bottom right (Steven).
    static let cornerLogo = CGSize(width: 190, height: 64)
    static var cornerLogoCentre: CGPoint {
        // (Steven: it floated mid-hero — at the bottom right, on the dots' line, right on the margin.)
        CGPoint(x: OrbitHomeLayout.screenWidth - margin - cornerLogo.width / 2, y: rowsTop(hulu: false) - 44 - 6)
    }
    static let headingHeight: CGFloat = 54
    static let tile = CGSize(width: 400, height: 225)
    /// Measured on Steven's Disney+ 2026 video: wider and taller than the other posters.
    static let top10 = CGSize(width: 385, height: 620)
    static let top10Gap: CGFloat = 36
    /// Disney+ 2026 mixes 16:9 rows and portrait ones (posters with their title).
    static let poster = CGSize(width: 295, height: 411)
    static let gap: CGFloat = 26
    static let rowGap: CGFloat = 58
    static let radius: CGFloat = 12
    static let horizontal = Animation.easeOut(duration: 0.24)
    static let vertical = Animation.easeInOut(duration: 0.4)

    // Disney+'s newest app (Steven's video, 2026-10-27), measured in 1080p: the focused title open
    // in a fixed 16:9 frame at the margin, the others as posters, one meta line under the frame.
    // (Re-measured on Steven's newest video, 4 weeks old: a little smaller, the row above showing
    // at the top of the screen.)
    static let open = CGSize(width: 825, height: 465)
    static let posterNew = CGSize(width: 296, height: 440)
    static let gapNew: CGFloat = 30
    static let headingNew: CGFloat = 46
    static let metaNew: CGFloat = 52
    static let rowGapNew: CGFloat = 35
    /// The current row's heading on the newest app: the row above shows at the screen's top.
    static let restTopNew: CGFloat = 222
    /// The brands under the hero (Disney, Pixar, Marvel, Star Wars, National Geographic).
    static let brandTile = CGSize(width: 300, height: 170)
    static let brandGap: CGFloat = 36
    /// The brands' hub (newest app): a row of pills, then the focused brand's band — its logo, its
    /// line, TOUT PARCOURIR and its titles.
    static let pill = CGSize(width: 170, height: 92)
    static let hubHeight: CGFloat = 740
    /// The first row's top: the brands' (Disney+), or the first row's heading (Hulu).
    static func rowsTop(hulu: Bool) -> CGFloat { 915 }
    /// Steven (2026-10-27): his Top 10 cards (the turquoise arc) kept — true brings them back in
    /// place of the newest app's posters with their rank.
    static let classicTop10 = false
}

/// One row of the Disney+ page.
struct OrbitDisneyRow: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [MetaPreview]
    let top10: Bool
    /// Portrait posters (the franchises and the genres), as in Disney+'s 2026 app.
    var portrait = false
    /// The brands under the hero (no titles: five studio tiles).
    var brands = false

    static func == (a: OrbitDisneyRow, b: OrbitDisneyRow) -> Bool {
        a.id == b.id && a.top10 == b.top10 && a.items.map(\.id) == b.items.map(\.id)
    }

    var cardSize: CGSize { top10 ? OrbitDisneyLayout.top10 : portrait ? OrbitDisneyLayout.poster : OrbitDisneyLayout.tile }
    /// The 16:9 tiles have their name and meta line under them.
    var hasLabels: Bool { !top10 && !portrait }
    /// Drawn as before (Steven's Top 10 cards, when kept).
    var classic: Bool { top10 && OrbitDisneyLayout.classicTop10 }
    var height: CGFloat {
        let L = OrbitDisneyLayout.self
        // (Steven: the next row's title was against the band.)
        if brands { return L.hubHeight + 64 }
        if classic { return L.headingHeight + cardSize.height + L.rowGap }
        return L.headingNew + L.open.height + L.metaNew + L.rowGapNew
    }
    /// Netflix-like (Disney+'s newest app): the row runs on in a loop; the Top 10 stops at its 10th.
    var loops: Bool { !top10 && !brands && items.count > 1 }
    var slotCount: Int { loops ? items.count * 30 : items.count }
    func item(atSlot slot: Int) -> Int { items.isEmpty ? 0 : slot % items.count }
}

struct OrbitDisneyPage: View {
    let route: FolderRoute
    let push: (TitleRoute) -> Void

    /// A Disney+ folder (not the Disney studio).
    static func handles(_ route: FolderRoute) -> Bool {
        let t = route.folderTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        return t.contains("disney+") || t.contains("disneyplus")
    }

    @StateObject private var model: FolderDetailViewModel
    @StateObject private var extras = OrbitPlatformExtrasModel()
    @StateObject private var hulu = OrbitHuluRowsModel()
    @StateObject private var trailer = OrbitNativeTrailerHost()
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.orbitPushStudio) private var pushStudio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true
    /// A title was opened over the page: no trailer starts again behind it (Steven: Prime's kept
    /// playing, its sound under the title's page).
    @State private var covered = false

    /// 0: Disney+, 1: Hulu.
    /// Steven: Accueil (0, where Disney+ opens: the franchises' band), Disney+ (1), Hulu (2).
    @State private var mode = 0
    /// A franchise opened from the band: on the way back, the bar out of reach a moment (Steven:
    /// the focus did not come back on the brand).
    @State private var studioOpened = false
    /// 0: the hero; then the rows.
    @State private var current = 0
    /// The page's scroll, followed by the hero alone (its fade).
    @StateObject private var heroFade = OrbitScrollTracker()
    @State private var heroIndex = 0
    /// Each row's focused title (a box per row: a press redraws its row alone — native pages).
    @State private var leads = OrbitLeadStore()
    @FocusState private var canvasFocused: Bool
    /// Steven (2026-10-26): the page built like Home — sections the system moves (Nouvel accueil).
    @State private var nativeHasFocus = false
    @State private var nativeHeroFocused = false
    @State private var nativeFocusStamp: TimeInterval = 0
    /// The page holds the focus (the canvas's, or one of the native sections').
    private var pageFocused: Bool { nativeHasFocus }
    @State private var motion = OrbitHomeMotion()
    @State private var trailerKey: String?
    @State private var search: OrbitPlatformSearchModel?
    @State private var heroClock: Task<Void, Never>?

    init(route: FolderRoute, push: @escaping (TitleRoute) -> Void) {
        self.route = route
        self.push = push
        _model = StateObject(wrappedValue: FolderDetailViewModel(route: route))
    }

    // MARK: Data

    private var isHulu: Bool { mode == 2 }

    private var rows: [OrbitDisneyRow] {
        guard !isHulu else { return huluRows }
        // Steven: the franchises' band on Accueil only, after the first two rows.
        guard mode == 0 else { return disneyRows }
        var list = homeRows
        list.insert(Self.brandsRow, at: min(2, list.count))
        return list
    }

    /// Accueil (Steven: "il faut que les rangées mélangent les contenus Hulu et Disney+, sinon cet
    /// onglet n'a plus d'intérêt"): each Disney+ row with Hulu's of the same kind, in turn — the
    /// Top 10 with Hulu's most popular, the Nouveautés with Hulu's newest, a genre with Hulu's.
    @State private var homeMemo = OrbitRowsMemo<[OrbitDisneyRow]>()

    private var homeRows: [OrbitDisneyRow] {
        let huluExtras = (hulu.seriesRows + hulu.movieRows).map {
            OrbitPlatformExtrasModel.Extra(id: $0.id, title: $0.title, items: $0.items)
        }
        return homeMemo.get(OrbitRowsKey(rows: model.stripRows, filter: nil,
                                         extras: extras.movieRows + extras.seriesRows + huluExtras,
                                         variant: "home")) { buildHomeRows() }
    }

    private func buildHomeRows() -> [OrbitDisneyRow] {
        func fold(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        var used = Set<String>()
        return disneyRows.map { row in
            let h = fold(row.title)
            let series = h.contains("serie")
            let pool = series ? hulu.seriesRows : hulu.movieRows
            var mates: [MetaPreview] = []
            if row.top10 {
                mates = pool.first(where: { $0.id.hasPrefix("hulu-popular-") })?.items ?? []
            } else if h.contains("nouveau") || h.contains("nouvelle") {
                mates = pool.first(where: { $0.id.hasPrefix("hulu-new-") })?.items ?? []
            } else {
                // A genre: Hulu's films and series of that genre.
                let same = (hulu.seriesRows + hulu.movieRows).filter {
                    $0.id.contains("genre") && fold($0.title) == h && !used.contains($0.id)
                }
                same.forEach { used.insert($0.id) }
                mates = Self.alternate(same.first?.items ?? [], same.dropFirst().first?.items ?? [])
            }
            guard !mates.isEmpty else { return row }
            var seen = Set<String>()
            let mixed = Self.alternate(row.items, mates).filter { seen.insert(Self.identity($0)).inserted }
            return OrbitDisneyRow(id: row.id, title: row.title,
                                  items: row.top10 ? Array(mixed.prefix(10)) : Array(mixed.prefix(30)),
                                  top10: row.top10, portrait: row.portrait)
        }
    }

    private static let brandsRow = OrbitDisneyRow(id: "disney-brands", title: "", items: [], top10: false, brands: true)

    /// Steven (option A, as on Disney+): films and series together, no Films / Séries switch. His
    /// Top 10 rows first (films, then series), his Nouveautés, then the franchises and genres
    /// (TMDB), films and series in turn.
    /// Built once per change of what they are made of (fluidity: every press rebuilt them).
    @State private var disneyMemo = OrbitRowsMemo<[OrbitDisneyRow]>()

    private var disneyRows: [OrbitDisneyRow] {
        disneyMemo.get(OrbitRowsKey(rows: model.stripRows, filter: nil,
                                    extras: extras.movieRows + extras.seriesRows)) { buildDisneyRows() }
    }

    private func buildDisneyRows() -> [OrbitDisneyRow] {
        // Steven: Marvel, Star Wars (and Comédie, Animation) came twice, once for the films and once
        // for the series. One row per title, its films and series in turn.
        var extraRows: [OrbitPlatformExtrasModel.Extra] = []
        for row in Self.alternate(extras.movieRows, extras.seriesRows) {
            if let i = extraRows.firstIndex(where: { $0.title == row.title }) {
                let merged = extraRows[i]
                extraRows[i] = OrbitPlatformExtrasModel.Extra(id: merged.id, title: merged.title,
                                                              items: Self.alternate(merged.items, row.items))
            } else {
                extraRows.append(row)
            }
        }
        let catalogs: [(OrbitDisneyRow, Int)] = model.stripRows.compactMap { row in
            guard row.status == .loaded, let items = row.section?.items, !items.isEmpty else { return nil }
            guard extraRows.isEmpty || OrbitCatalogFilter.isKept(row.heading) else { return nil }
            var seen = Set<String>()
            let unique = items.filter { seen.insert("\($0.type):\($0.id)").inserted }
            let heading = row.heading.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let top10 = heading.contains("top 10") || heading.contains("top10")
            let isSeries = heading.contains("serie") || unique.first.map { $0.type != "movie" } == true
            return (OrbitDisneyRow(id: row.id, title: top10 ? Self.top10Title(series: isSeries) : row.heading,
                                   items: top10 ? Array(unique.prefix(10)) : unique, top10: top10),
                    (isSeries ? 2 : 0) + (top10 ? 1 : 0))
        }
        // Steven: Nouveaux films, Top 10 des films, Nouvelles séries, Top 10 des séries (stable).
        let ordered = catalogs.enumerated()
            .sorted { $0.element.1 != $1.element.1 ? $0.element.1 < $1.element.1 : $0.offset < $1.offset }
            .map(\.element.0)
        var shown = Set(ordered.flatMap { $0.items.map(Self.identity) })
        var more: [OrbitDisneyRow] = []
        for extra in extraRows {
            let fresh = extra.items.filter { !shown.contains(Self.identity($0)) }
            guard fresh.count >= 8 else { continue }
            let kept = Array(fresh.prefix(24))
            kept.forEach { shown.insert(Self.identity($0)) }
            more.append(OrbitDisneyRow(id: extra.id, title: extra.title, items: kept, top10: false, portrait: true))
        }
        return ordered + more
    }

    /// Hulu: its Top 10 series (and films, when TMDB credits any to Hulu), then its rows.
    private var huluRows: [OrbitDisneyRow] {
        var out: [OrbitDisneyRow] = []
        var shown = Set<String>()
        // Steven: Hulu opens on its Nouvelles séries.
        if let newest = hulu.seriesRows.first(where: { $0.id.hasPrefix("hulu-new-") }) {
            out.append(OrbitDisneyRow(id: newest.id, title: String(localized: "Nouvelles séries"),
                                      items: newest.items, top10: false))
            newest.items.forEach { shown.insert(Self.identity($0)) }
        }
        if let popular = hulu.seriesRows.first {
            out.append(OrbitDisneyRow(id: "hulu-top10-series", title: Self.top10Title(series: true),
                                      items: Array(popular.items.prefix(10)), top10: true))
        }
        if let popular = hulu.movieRows.first {
            out.append(OrbitDisneyRow(id: "hulu-top10-movies", title: Self.top10Title(series: false),
                                      items: Array(popular.items.prefix(10)), top10: true))
        }
        // Steven: a title showed in two rows (The Bear in Drame and Comédie): each row leaves out the
        // titles of the rows above; a row left with fewer than 6 is dropped.
        for row in Self.alternate(hulu.seriesRows, hulu.movieRows) where !out.contains(where: { $0.id == row.id }) {
            let fresh = row.items.filter { !shown.contains(Self.identity($0)) }
            guard fresh.count >= 6 else { continue }
            fresh.forEach { shown.insert(Self.identity($0)) }
            out.append(OrbitDisneyRow(id: row.id, title: row.title, items: fresh, top10: false,
                                      portrait: row.id.contains("genre")))
        }
        return out
    }

    /// a1, b1, a2, b2… then the rest of the longer one.
    private static func alternate<T>(_ a: [T], _ b: [T]) -> [T] {
        var out: [T] = []
        for i in 0..<max(a.count, b.count) {
            if i < a.count { out.append(a[i]) }
            if i < b.count { out.append(b[i]) }
        }
        return out
    }

    private static func top10Title(series: Bool) -> String {
        series ? String(localized: "Top 10 des séries en France aujourd'hui")
               : String(localized: "Top 10 des films en France aujourd'hui")
    }

    /// The hero's titles: the new films and series in turn (Disney+), the most popular (Hulu).
    /// The hero's candidates, before the ones without a logo are left out.
    private var heroPool: (items: [MetaPreview], fresh: Bool) {
        if isHulu {
            return (Self.alternate(hulu.seriesRows.first?.items ?? [], hulu.movieRows.first?.items ?? []), false)
        }
        let fresh = model.stripRows.filter { row in
            let h = row.heading.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return row.status == .loaded && (h.contains("nouveau") || h.contains("nouvelle"))
        }.map { $0.section?.items ?? [] }
        let items = fresh.count >= 2 ? Self.alternate(fresh[0], fresh[1]) : fresh.first ?? []
        if items.isEmpty { return (rows.first(where: { !$0.top10 && !$0.brands })?.items ?? [], false) }
        return (items, true)
    }

    private var heroItems: [MetaPreview] {
        // Steven: Swiping Right on the Devil (Hulu's) in Disney+'s hero — Hulu's titles left out.
        // Steven: a title whose logo is missing (its name written instead) is left out of the hero,
        // once its details are known.
        Array(heroPool.items.filter { item in
            guard item.banner != nil else { return false }
            guard let meta = metaStore.meta(for: item) else { return true }
            return (isHulu || !orbitIsHuluTitle(meta)) && OrbitInfo.make(item, meta: meta).logo != nil
        }.prefix(6))
    }

    private var sectionCount: Int { 1 + rows.count }

    /// The row a section shows (nil: the hero).
    private func rowIndex(of section: Int) -> Int? { section >= 1 ? section - 1 : nil }

    /// Each row's top in the page.
    private func rowTops(_ rows: [OrbitDisneyRow]) -> [CGFloat] {
        var y = OrbitDisneyLayout.rowsTop(hulu: isHulu)
        return rows.map { row in defer { y += row.height }; return y }
    }

    /// How far the page has moved up: none on the hero, else the current row at its rest.
    private func scroll(_ rows: [OrbitDisneyRow]) -> CGFloat {
        guard let r = rowIndex(of: current), rows.indices.contains(r) else { return 0 }
        return rowTops(rows)[r] - OrbitDisneyLayout.restTopNew
    }

    private static func identity(_ item: MetaPreview) -> String {
        let year: String = item.releaseInfo.map { String($0.prefix(4)) } ?? ""
        return item.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) + "|" + year
    }

    private func lead(of row: OrbitDisneyRow) -> Int {
        let slot = leads[row.id] ?? 0
        if row.brands { return min(slot, OrbitDisneyBrand.all.count - 1) }
        return row.loops ? row.item(atSlot: slot) : min(slot, max(0, row.items.count - 1))
    }

    /// Disney+'s logo (drawn white in the bar and over the hero's title).
    private var brandLogoURL: String? {
        model.titleLogoUrl ?? route.titleLogoUrl ?? OrbitPlatformLogos.url(.disney)
    }

    private var heroItem: MetaPreview? {
        let items = heroItems
        return items.isEmpty ? nil : items[min(heroIndex, items.count - 1)]
    }

    // MARK: Body

    var body: some View {
        let rows = rows
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        let offset = scroll(rows)
        let hero = heroItem

        ZStack(alignment: .topLeading) {
            OrbitDisneyLayout.background
            // (Newest app: a lighter slate in the top left corner.)
            RadialGradient(colors: [OrbitDisneyLayout.backgroundGlow.opacity(0.7), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 1400)
                .allowsHitTesting(false)

            // Steven (device: back to the top, the hero came back in two steps): the hero stays in
            // place and fades with the page's move; the tiles and rows move up over it.
            // Steven (video: the hero went at the press, the rows came later): it fades as the
            // page actually moves, frame by frame (its own little view follows the scroll).
            // Steven: on the first row the hero's bottom stays in sight above it — the art goes up
            // with the page (only its text fades), and fades only past the first row.
            OrbitDisneyHeroScroll(tracker: heroFade,
                                  keepsUntil: OrbitDisneyLayout.rowsTop(hulu: isHulu) - OrbitDisneyLayout.restTopNew) {
                OrbitDisneyHero(item: hero, meta: hero.flatMap { metaStore.meta(for: $0) },
                                count: heroItems.count, index: min(heroIndex, max(0, heroItems.count - 1)),
                                focused: pageFocused && current == 0, isHulu: isHulu, brandLogoURL: brandLogoURL,
                                dotsY: OrbitDisneyLayout.rowsTop(hulu: isHulu) - 44,
                                newcomer: heroPool.fresh,
                                fade: heroFade,
                                trailerURL: trailerURL(for: hero),
                                onTrailerFailure: { trailer.playbackFailed($0) },
                                onTrailerEnded: {
                                    trailer.playbackFinished()
                                    advanceHero()
                                })
            }

                            nativeSections(rows)
                    // A page of its own for each mode (Steven, Hulu: the Disney+ page's scroll and
                    // row places stayed — no hero, rows over each other).
                    .id(mode)
                    .disabled(search != nil)
            

            // Under the bar: a shade so the rows never run under it unreadable.
            // (Newest app: the row above shows there, only a little dimmed.)
            LinearGradient(colors: [OrbitDisneyLayout.background.opacity(0.7), OrbitDisneyLayout.background.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: W, height: 120)
                .opacity(offset > 0 ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: offset > 0)
                .allowsHitTesting(false)

            if rows.isEmpty {
                if model.isLoading || hulu.isLoading {
                    ProgressView().frame(width: W, height: H)
                } else if isHulu {
                    Text(String(localized: "Aucun titre Hulu trouvé sur Disney+ en France."))
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: W, height: H)
                }
            }

            // The page's one focusable stop, under the bar's band.

            CollectionFilterBar(filter: Binding(get: { mode == 0 ? nil : "tab" }, set: { if $0 == nil { mode = 0 } }),
                                onSearch: openSearch, showsTypes: false, showsAll: true,
                                switchItems: ["Disney+", "Hulu"],
                                switchSelection: Binding(get: { mode - 1 }, set: { mode = $0 + 1 }),
                                switchLogo: { index, lit in
                                    AnyView(OrbitDisneyBrandLogo(hulu: index == 1, logoURL: brandLogoURL,
                                                                 height: 46, dark: lit, alignment: .center))
                                }, centreLeads: true)
                .disabled(search != nil || (pageFocused && current > 0))
                .opacity(search != nil ? 0 : 1)

            OrbitPlatformIntro(title: model.folderTitle, logoUrl: model.titleLogoUrl ?? route.titleLogoUrl,
                               brand: OrbitDisneyLayout.brandBlue, hidesCorner: true,
                               settlesAt: OrbitDisneyLayout.cornerLogoCentre,
                               settledScale: OrbitDisneyLayout.cornerLogo.height / OrbitPlatformIntro.logoSize.height)

            if let search {
                OrbitPlatformSearchLayer(model: search, platform: model.folderTitle,
                                         onOpen: { push(TitleRoute(preview: $0, platform: detailPlatform)) },
                                         onClose: closeSearch)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .clipped()
        .background(OrbitDisneyLayout.background)
        .ignoresSafeArea()
        .background { ViewerInputClockInstaller().frame(width: 0, height: 0) }
        .onAppear {
            covered = false
            // Back from a franchise: the focus put back on its brand (the system's own landing in
            // the bar overruled). The bar itself never locked (Steven: the house out of reach).
            if studioOpened {
                studioOpened = false
                let appeared = ProcessInfo.processInfo.systemUptime
                for delay in [0.1, 0.3, 0.6, 0.9] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        guard !ViewerInputClock.shared.hasInput(since: appeared) else { return }
                        leads.box(Self.brandsRow.id).focusRequest &+= 1
                    }
                }
            }
            tabBarVisibility.pushImmersive()
            OrbitHomeButtonHost.shared.enter(.ownBar)
            model.buildsStripState = true
            model.start()
            extras.load(title: model.folderTitle)
            hulu.load()
            trailer.restSource = .custom(motion)
            startHeroClock()
            refreshAfterMove()
        }
        .onDisappear {
            covered = true
            tabBarVisibility.popImmersive()
            OrbitHomeButtonHost.shared.leave(.ownBar)
            trailer.reset(abortStages: true)
            heroClock?.cancel()
            model.stop()
        }
        .onChange(of: model.folderTitle) { _, title in extras.load(title: title) }
        .onChange(of: canvasFocused) { _, _ in refreshAfterMove() }
        .onChange(of: rows.map(\.id)) { _, _ in
            if current >= sectionCount { current = max(0, sectionCount - 1) }
            refreshAfterMove()
        }
        .onChange(of: heroItems.map(\.id)) { _, ids in
            if heroIndex >= ids.count { heroIndex = 0 }
            refreshAfterMove()
        }
        .onChange(of: mode) { _, _ in resetPage() }
    }

    /// The native page: the sections (an invisible stop for the hero, whose art stays behind, then
    /// the rows drawn as before) as real buttons the system moves.
    private func nativeSections(_ rows: [OrbitDisneyRow]) -> some View {
        OrbitNativeSections(
            count: 1 + rows.count, hasHero: true,
            height: { s in s == 0 ? OrbitDisneyLayout.rowsTop(hulu: isHulu) - OrbitDisneyLayout.restTopNew : (rows.indices.contains(s - 1) ? rows[s - 1].height : 0) },
            // Newest app (Steven's video): the row above stays in sight at the screen's top.
            topLine: OrbitDisneyLayout.restTopNew, current: current, hidesAbove: false,
            onFocus: { s in
                withAnimation(.easeInOut(duration: 0.3)) { current = s }
                refreshAfterMove()
            },
            onMove: { move($0) }, onSelect: select, onExit: exitAction(),
            onFocusChange: { has in
                nativeHeroFocused = has
                if has { nativeEnter(0) } else { nativeLeave() }
            },
            rowsFocusable: true,
            tracker: heroFade,
            focusRow: { s in if rows.indices.contains(s - 1) { leads.box(rows[s - 1].id).focusRequest &+= 1 } }
        ) { s, focused in
            if s == 0 {
                Color.clear
            } else if rows.indices.contains(s - 1) {
                let row = rows[s - 1]
                if row.brands {
                    OrbitDisneyBrandsHub(box: leads.box(row.id), isCurrent: s == current,
                                         onEnter: { nativeEnter(s) }, onLeave: nativeLeave, onSelect: select,
                                         onOpen: { item in
                                             covered = true
                                             trailer.reset(abortStages: true)
                                             push(TitleRoute(preview: item, platform: detailPlatform))
                                         })
                } else if row.classic {
                    OrbitDisneyRowView(row: row, box: leads.box(row.id), isCurrent: s == current,
                                       focused: focused, metaStore: metaStore,
                                       onEnter: { nativeEnter(s) }, onLeave: nativeLeave, onSelect: select,
                                       onLeadChange: { refreshAfterMove() })
                } else {
                    OrbitDisneyOpenRow(row: row, box: leads.box(row.id), isCurrent: s == current,
                                       aboveCurrent: s < current, isHulu: isHulu, metaStore: metaStore,
                                       onEnter: { nativeEnter(s) }, onLeave: nativeLeave, onSelect: select,
                                       onLeadChange: { refreshAfterMove() })
                }
            }
        }
    }

    /// The focus came into section `s` (a row's title, or the hero).
    private func nativeEnter(_ s: Int) {
        let clock = ViewerInputClock.shared
        let recent = clock.hasInput(since: ProcessInfo.processInfo.systemUptime - 0.6)
        OrbitTrace.log("disney enter \(s) current=\(current) last=\(clock.lastKindLabel) recent=\(recent)")
        // Steven (Disney+ / Hulu: the page ran down on its own, Up went down): a row taking the focus
        // against the viewer's press (below on Up, above on Down) is the system's — the focus goes
        // back to the row the press meant.
        if recent, s >= 1, (clock.lastKind == .up && s > current) || (clock.lastKind == .down && s < current) {
            let meant = clock.lastKind == .up ? current - 1 : current + 1
            OrbitTrace.log("disney enter \(s) refused, back to \(meant)")
            let rows = rows
            if meant >= 1, rows.indices.contains(meant - 1) {
                if current != meant { withAnimation(.easeInOut(duration: 0.3)) { current = meant } }
                leads.box(rows[meant - 1].id).focusRequest &+= 1
            } else if meant <= 0 {
                withAnimation(.easeInOut(duration: 0.3)) { current = 0 }
            }
            return
        }
        nativeFocusStamp = ProcessInfo.processInfo.systemUptime
        if !nativeHasFocus { nativeHasFocus = true }
        if current != s { withAnimation(.easeInOut(duration: 0.3)) { current = s } }
        refreshAfterMove()
    }

    /// A section let the focus go: the page lost it unless another section took it just after.
    private func nativeLeave() {
        let left = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard nativeFocusStamp < left, !nativeHeroFocused, nativeHasFocus else { return }
            nativeHasFocus = false
            refreshAfterMove()
        }
    }

    private func trailerURL(for item: MetaPreview?) -> String? {
        guard let item, trailerKey == "\(item.type):\(item.id)" else { return nil }
        return trailer.playingURL
    }

    // MARK: Input

    private func move(_ direction: MoveCommandDirection) {
        let rows = rows
        switch direction {
        case .down:
            guard current + 1 < sectionCount else { return }
            goTo(current + 1)
            return
        case .up:
            guard current > 0 else { return }   // the bar takes it at the top
            goTo(current - 1)
            return
        case .left, .right:
            let step = direction == .right ? 1 : -1
            if current == 0 {
                let n = heroItems.count
                guard n > 1 else { return }
                withAnimation(.easeInOut(duration: 0.3)) { heroIndex = (heroIndex + step + n) % n }
            } else if let r = rowIndex(of: current), rows.indices.contains(r) {
                let row = rows[r]
                let next = (leads[row.id] ?? 0) + step
                guard next >= 0, next < (row.brands ? OrbitDisneyBrand.all.count : row.slotCount) else { return }
                withAnimation(OrbitDisneyLayout.horizontal) { leads[row.id] = next }
            }
        @unknown default:
            return
        }
        refreshAfterMove()
    }

    /// Menu: back to the hero from below it; on the hero, the system's own (the page closes).
    private func exitAction() -> (() -> Void)? {
        guard current > 0 else { return nil }
        return { goTo(0) }
    }

    private func goTo(_ section: Int) {
        withAnimation(reduceMotion ? nil : OrbitDisneyLayout.vertical) { current = section }
        refreshAfterMove()
    }

    /// The detail page's Disney+ touch.
    private var detailPlatform: OrbitDetailPlatform {
        OrbitDetailPlatform(theme: .disney, logoUrl: model.titleLogoUrl ?? route.titleLogoUrl)
    }

    private func select() {
        covered = true
        trailer.reset(abortStages: true)
        if current == 0 {
            if let heroItem { push(TitleRoute(preview: heroItem, platform: detailPlatform)) }
        } else if let r = rowIndex(of: current), rows.indices.contains(r) {
            let row = rows[r]
            if row.brands {
                let brand = OrbitDisneyBrand.all[lead(of: row)]
                let route = brand.route()
                // Steven: from Disney+, no opening — neither the studio's going in, nor Disney+'s
                // coming back (the way back counts as a title's).
                if let pushStudio {
                    studioOpened = true
                    OrbitStudioIntro.skipNext = true
                    OrbitNavClock.titleOpenedAt = ProcessInfo.processInfo.systemUptime
                    pushStudio(route)
                }
                return
            }
            guard row.items.indices.contains(lead(of: row)) else { return }
            push(TitleRoute(preview: row.items[lead(of: row)], platform: detailPlatform))
        }
    }

    private func resetPage() {
        current = 0
        heroIndex = 0
        leads.reset()
        refreshAfterMove()
    }

    private func advanceHero() {
        let n = heroItems.count
        guard n > 1 else { return }
        withAnimation(.easeInOut(duration: 0.5)) { heroIndex = (heroIndex + 1) % n }
        motion.stamp()
        refreshAfterMove()
    }

    /// Disney+'s carousel moves on by itself: after a long rest on the hero with no trailer playing.
    private func startHeroClock() {
        heroClock?.cancel()
        heroClock = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard current == 0, pageFocused, search == nil, trailer.playingURL == nil,
                      motion.secondsSinceMotion > 12 else { continue }
                advanceHero()
            }
        }
    }

    private func openSearch() {
        trailer.reset()
        trailerKey = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            search = OrbitPlatformSearchModel(tabs: model.tabs, platformKey: "\(route.collectionId)|\(route.folderId)",
                                              landscape: false)
        }
    }

    private func closeSearch() {
        withAnimation(.easeInOut(duration: 0.25)) { search = nil }
        refreshAfterMove()
    }

    /// After any move: the look-ahead (TMDB meta: logos, clean posters, ratings) and the hero's trailer.
    private func refreshAfterMove() {
        let rows = rows
        motion.stamp()
        var metaItems: [MetaPreview] = []
        if let heroItem { metaItems.append(heroItem) }
        metaItems += heroItems
        // (The candidates' details asked, the ones without a logo found out.)
        metaItems += heroPool.items.prefix(16)
        let r = rowIndex(of: current) ?? 0
        for i in max(0, r - 1)...max(0, min(rows.count - 1, r + 2)) where rows.indices.contains(i) {
            let row = rows[i]
            let lead = lead(of: row)
            metaItems += row.items.indices.filter { $0 >= lead - 1 && $0 <= lead + 6 }.map { row.items[$0] }
        }
        // The Top 10 cards need their clean poster and logo: all ten asked at once (Steven: a card
        // still loading showed as a grey block at the right).
        metaItems += rows.filter(\.top10).flatMap(\.items)
        OrbitMetaStore.shared.request(metaItems)

        trailer.reset()
        trailerKey = nil
        guard trailersOn, !covered, pageFocused, current == 0, search == nil, UIAccessibility.isVideoAutoplayEnabled,
              let item = heroItem else { return }
        trailer.prefersReducedMotion = reduceMotion
        trailer.restSource = .custom(motion)
        trailerKey = "\(item.type):\(item.id)"
        trailer.focusChanged(true, item: item)
    }
}

// MARK: - Hero

/// The carousel's title: its art across the page (its trailer after a rest), fading into the page;
/// the logo, the meta line, the synopsis, DÉTAILS and the dots on the left.
private struct OrbitDisneyHero: View {
    let item: MetaPreview?
    let meta: OrbitMeta?
    let count: Int
    let index: Int
    let focused: Bool
    let isHulu: Bool
    let brandLogoURL: String?
    /// The dots' line (Disney+: centred on the screen, under the hero).
    var dotsY: CGFloat = 755
    /// Taken from Disney+'s Nouveautés: "Nouveau film" / "Nouvelle série" even without a date.
    var newcomer = false
    /// The page's scroll: the text, the logo and the dots fade with it (the art stays).
    let fade: OrbitScrollTracker
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let L = OrbitDisneyLayout.self
        let size = CGSize(width: OrbitHomeLayout.screenWidth, height: L.heroArtHeight)
        let banner: String? = item?.banner
        ZStack(alignment: .topLeading) {
            ZStack {
                OrbitSwapImage(url: banner ?? meta?.backdrop, fallback: nil, size: size)
                if let trailerURL, let item {
                    TrailerHeroPlayer(urlString: trailerURL,
                                      onFailure: onTrailerFailure,
                                      zoomKey: TrailerResolutionCache.key(type: item.type, id: item.id),
                                      loops: false,
                                      onPlaybackEnded: onTrailerEnded,
                                      cornerRadius: 0)
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity.animation(.easeOut(duration: 0.6)))
                }
                LinearGradient(stops: [
                    .init(color: L.background.opacity(0.92), location: 0),
                    .init(color: L.background.opacity(0.55), location: 0.4),
                    .init(color: .clear, location: 0.7),
                ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.5),
                    .init(color: L.background.opacity(0.45), location: 0.78),
                    .init(color: L.background.opacity(0.85), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            OrbitScrollFaded(tracker: fade, distance: 300) {
            ZStack(alignment: .topLeading) {
            if let item {
                info(item)
                    .offset(x: L.margin, y: L.infoTop)
            }
            // Steven: the platform's logo at the hero's bottom right, in white (where the opening's
            // logo glides to).
            OrbitDisneyBrandLogo(hulu: isHulu, logoURL: brandLogoURL, height: L.cornerLogo.height,
                                 alignment: .trailing, huluInColour: true)
                .frame(width: L.cornerLogo.width, height: L.cornerLogo.height)
                .shadow(color: .black.opacity(0.45), radius: 8)
                .position(L.cornerLogoCentre)
                .id(isHulu)
                .transition(.opacity)
            if count > 1 {
                HStack(spacing: 10) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(i == index ? 1 : 0.35))
                            .frame(width: i == index ? 26 : 10, height: 10)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: index)
                .position(x: size.width / 2, y: dotsY)
            }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func heroNews(_ item: MetaPreview) -> String? {
        let tv = item.type == "series" || item.type == "tv"
        switch OrbitTitleNews.of(item, meta) {
        case .newSeason: return String(localized: "Nouvelle saison")
        case .newEpisodes: return String(localized: "Nouveaux épisodes")
        case .soon: return String(localized: "Bientôt")
        case nil:
            guard newcomer || orbitIsFresh(item, meta) else { return nil }
            return tv ? String(localized: "Nouvelle série") : String(localized: "Nouveau film")
        }
    }

    private func info(_ item: MetaPreview) -> some View {
        let L = OrbitDisneyLayout.self
        let info = OrbitInfo.make(item, meta: meta)
        return VStack(alignment: .leading, spacing: 0) {
            // The platform's mark sits right on the title's logo, both at the box's bottom (Steven:
            // the Hulu mark floated high above a short logo).
            // (Steven: the Disney+ logo floated above the title's — closer.)
            VStack(alignment: .leading, spacing: 6) {
                // Steven: Disney+'s in white over its own programmes; Hulu's only at the hero's
                // bottom right.
                // (Steven: no logo over the title — the platform's is at the bottom right already.)
                Color.clear
                .frame(height: 52, alignment: .bottomLeading)
                OrbitTitleMark(name: item.name, logo: info.logo, maxSize: L.logoSize, textSize: 64,
                               fallbackLogo: info.logoFallback, hugsLogo: true)
            }
            .frame(width: L.logoSize.width, height: 52 + 6 + L.logoSize.height, alignment: .bottomLeading)
            // Steven: "Nouveau film" / "Nouvelle série" on the hero's newcomers (a new season or
            // new episodes first).
            if let news = heroNews(item) {
                OrbitNewBadge(text: news)
                    .padding(.top, 22)
            }
            OrbitDisneyMetaLine(certification: meta?.certification, parts: info.parts)
                .padding(.top, 24)
            Text(info.synopsis)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineSpacing(4)
                .lineLimit(2)
                .frame(width: 640, alignment: .topLeading)
                .padding(.top, 16)
            HStack(spacing: 16) {
                // Disney+'s newest app: a plain grey box, white when focused.
                Text(String(localized: "DÉTAILS"))
                    .font(.system(size: 22, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(focused ? Color.black : Color.white)
                    .padding(.horizontal, 32)
                    .frame(height: 60)
                    .background(RoundedRectangle(cornerRadius: 4).fill(focused ? Color.white : Color.white.opacity(0.25)))
                    .animation(.easeOut(duration: 0.18), value: focused)
            }
            .padding(.top, 28)
        }
        .frame(width: L.synopsisWidth, alignment: .topLeading)
        .id("\(item.type):\(item.id)")
        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
    }
}

/// "[12]  2025 · Animation · 1 h 40".
private struct OrbitDisneyMetaLine: View {
    let certification: String?
    let parts: [String]

    var body: some View {
        HStack(spacing: 14) {
            if let certification { OrbitDisneyRating(text: certification, size: 20) }
            Text(parts.joined(separator: "  ·  "))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
        }
        .frame(height: 34)
    }
}

/// The age rating in an outlined box, as on Disney+.
private struct OrbitDisneyRating: View {
    let text: String
    let size: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy))
            .foregroundStyle(Color.white)
            .padding(.horizontal, size * 0.35)
            .padding(.vertical, size * 0.08)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.85), lineWidth: 2))
    }
}

// MARK: - Rows

/// A row: its heading, its cards from the focused one (at the margin) onwards.
private struct OrbitDisneyRowView: View {
    let row: OrbitDisneyRow
    @ObservedObject var box: OrbitLeadBox
    let isCurrent: Bool
    let focused: Bool
    @ObservedObject var metaStore: OrbitMetaStore
    let onEnter: () -> Void
    let onLeave: () -> Void
    let onSelect: () -> Void
    let onLeadChange: () -> Void

    var body: some View {
        let L = OrbitDisneyLayout.self
        let size = row.cardSize
        VStack(alignment: .leading, spacing: 0) {
            Text(row.title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isCurrent ? 1 : 0.7))
                .lineLimit(1)
                .frame(height: L.headingHeight, alignment: .topLeading)
                .padding(.leading, L.margin + 2)
            OrbitNativeTileStrip(count: row.items.count, spacing: row.top10 ? L.top10Gap : L.gap, height: size.height,
                                 lastWidth: size.width, box: box, alignment: .top,
                                 onEnter: onEnter, onLeave: onLeave, onSelect: onSelect,
                                 onLeadChange: { _ in onLeadChange() }) { index, lit in
                let item = row.items[index]
                let meta = metaStore.meta(for: item)
                if row.top10 {
                    OrbitDisneyTop10Card(item: item, rank: index + 1, meta: meta, focused: lit)
                } else if row.portrait {
                    OrbitDisneyPoster(item: item, focused: lit)
                } else {
                    OrbitDisneyTile(item: item, meta: meta, focused: lit)
                }
            }
            .frame(width: OrbitHomeLayout.screenWidth, height: size.height, alignment: .topLeading)
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
    }
}

/// Disney+'s Top 10 card (Steven's reference): the rank in turquoise top left on a dark arc, the
/// poster without its title, a shade to the bottom with the logo, then the rating and the year.
private struct OrbitDisneyTop10Card: View {
    let item: MetaPreview
    let rank: Int
    let meta: OrbitMeta?
    let focused: Bool

    var body: some View {
        let L = OrbitDisneyLayout.self
        let size = L.top10
        let info = OrbitInfo.make(item, meta: meta)
        ZStack(alignment: .topLeading) {
            // As on Disney+ (Steven's video): the card's corner is a teal gradient, and the poster
            // sits inside a large circle whose edge curves across that corner (the arc bulges
            // towards the corner, it is the poster's edge, not a disc over it).
            // Measured on the video: the corner spans almost half the card's width on both edges, a
            // blue-teal brighter in the corner, darker towards the poster.
            // Colours read off the video's pixels: a deep blue (not teal) in the corner, near navy at the arc.
            // Steven: still too light — the video reaches navy much sooner (blue only in the very corner).
            LinearGradient(stops: [
                .init(color: Color(red: 0.02, green: 0.36, blue: 0.58), location: 0),
                .init(color: Color(red: 0.04, green: 0.22, blue: 0.38), location: 0.45),
                .init(color: Color(red: 0.07, green: 0.13, blue: 0.24), location: 1),
            ], startPoint: .topLeading, endPoint: UnitPoint(x: 0.3, y: 0.24))
            Group {
                if let poster = meta?.cleanPoster {
                    OrbitImage(url: poster, mode: .fill, size: size)
                } else {
                    Color(red: 0.07, green: 0.08, blue: 0.12)
                }
            }
            .frame(width: size.width, height: size.height)
            .mask {
                // Through (0.47 w, 0) and (0, 0.47 w), bulging slightly towards the corner.
                Circle()
                    .frame(width: size.width * 5.23, height: size.width * 5.23)
                    .position(x: size.width * 2.07, y: size.width * 2.07)
            }
            // Steven (device: the 10 ran past the blue arc): two digits smaller and tighter.
            Text("\(rank)")
                .font(.system(size: rank >= 10 ? 62 : 82, weight: .heavy, design: .rounded))
                .kerning(rank >= 10 ? -4 : 0)
                .foregroundStyle(Color(red: 0.15, green: 0.80, blue: 0.92))
                .padding(.leading, size.width * 0.055)
                .padding(.top, size.width * 0.02)
            // The bottom: a shade, the logo, the rating and the year.
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                OrbitTitleMark(name: item.name, logo: info.logo,
                               maxSize: CGSize(width: size.width * 0.8, height: size.height * 0.2), textSize: 26,
                               fallbackLogo: info.logoFallback)
                    .frame(width: size.width * 0.8, height: size.height * 0.2, alignment: .bottom)
                HStack(spacing: 10) {
                    if let certification = meta?.certification { OrbitDisneyRating(text: certification, size: 16) }
                    if let year = info.parts.first {
                        Text(year)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                }
                .frame(height: 26)
            }
            .padding(.bottom, 16)
            .frame(width: size.width, height: size.height)
            .background(alignment: .bottom) {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: L.background.opacity(0.85), location: 0.45),
                    .init(color: L.background, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: size.height * 0.5)
            }
        }
        // Top-leading: the arc's circle is wider than the card; centred, it pushed the whole card
        // left (Steven: a grey strip on every card's right).
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        // Steven: the focused card's rank rose above the others' — a frame, no lift, on the Top 10.
        .modifier(OrbitDisneyFocus(focused: focused, lifts: false))
    }
}

/// A portrait poster (its title on the art), as in Disney+'s 2026 rows.
private struct OrbitDisneyPoster: View {
    let item: MetaPreview
    let focused: Bool
    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        let L = OrbitDisneyLayout.self
        let size = L.poster
        ZStack {
            Color(red: 0.07, green: 0.08, blue: 0.12)
            // Steven: an empty poster (its image did not load): the name under it, never a blank card.
            Text(item.name)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(20)
            OrbitImage(url: item.poster, fallback: item.rawPosterUrl, mode: .fill, size: size)
            if let text = orbitDisneyLabel(item, metaStore.meta(for: item)) {
                OrbitNewBadge(text: text).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .modifier(OrbitDisneyFocus(focused: focused))
        .onAppear { OrbitMetaStore.shared.request([item]) }
    }
}

/// A 16:9 tile: the title's backdrop, its logo bottom left.
private struct OrbitDisneyTile: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let focused: Bool

    var body: some View {
        let L = OrbitDisneyLayout.self
        let size = L.tile
        let info = OrbitInfo.make(item, meta: meta)
        let banner: String? = item.banner
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color(red: 0.07, green: 0.08, blue: 0.12)
                OrbitImage(url: banner ?? meta?.backdrop, fallback: item.poster, size: size, placeholder: item.poster)
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                OrbitTitleMark(name: item.name, logo: info.logo,
                               maxSize: CGSize(width: size.width * 0.6, height: size.height * 0.34), textSize: 24,
                               fallbackLogo: info.logoFallback)
                    .padding(.leading, 16)
                    .padding(.bottom, 14)
                if let text = orbitDisneyLabel(item, meta) {
                    OrbitNewBadge(text: text).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
            .modifier(OrbitDisneyFocus(focused: focused))
            // Disney+ 2026: the name and "TP · 2025 · Animation" under the tile.
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(focused ? 1 : 0.85))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    if let certification = meta?.certification { OrbitDisneyRating(text: certification, size: 15) }
                    Text(info.parts.prefix(2).joined(separator: " · "))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(.top, 14)
            .frame(width: size.width, height: L.labelHeight, alignment: .topLeading)
        }
    }
}

/// Disney+'s focus: a white frame, a small lift from the card's left edge.
private struct OrbitDisneyFocus: ViewModifier {
    let focused: Bool
    var lifts = true

    func body(content: Content) -> some View {
        content
            .animation(.easeOut(duration: 0.18)) { view in
                view
                    .overlay {
                        RoundedRectangle(cornerRadius: OrbitDisneyLayout.radius, style: .continuous)
                            .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 4)
                    }
                    .shadow(color: .black.opacity(focused ? 0.55 : 0.2), radius: focused ? 20 : 6, y: focused ? 12 : 4)
                    .scaleEffect(focused && lifts ? 1.06 : 1, anchor: .leading)
            }
    }
}

// MARK: - Hulu (TMDB)

/// Hulu inside Disney+ in the viewer's region: the series of Hulu's network, the films of Hulu's
/// companies — most popular, newest, then a few genres.
@MainActor
final class OrbitHuluRowsModel: ObservableObject {
    nonisolated struct Row: Equatable {
        let id: String
        let title: String
        let items: [MetaPreview]
        static func == (a: Row, b: Row) -> Bool { a.id == b.id && a.items.map(\.id) == b.items.map(\.id) }
    }

    @Published private(set) var movieRows: [Row] = []
    @Published private(set) var seriesRows: [Row] = []
    @Published private(set) var isLoading = false
    private var loaded = false

    nonisolated private static let network = 453
    nonisolated private static let seriesGenres: [(Int, String)] = [(18, "Drame"), (35, "Comédie"), (80, "Crime"),
                                                        (9648, "Mystère"), (10765, "Science-Fiction & Fantastique")]
    nonisolated private static let movieGenres: [(Int, String)] = [(27, "Horreur"), (53, "Thriller"), (35, "Comédie"), (18, "Drame")]

    func load() {
        guard !loaded else { return }
        loaded = true
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        guard !key.isEmpty else { return }
        let language = TmdbSettingsRepository.shared.snapshot().language
        isLoading = true
        Task { [weak self] in
            let lang = language.isEmpty ? "fr-FR" : language
            let companies = await Self.huluCompanies(apiKey: key)
            async let series = Self.rows(tv: true, filter: "&with_networks=\(Self.network)", apiKey: key, lang: lang)
            var m: [Row] = []
            if !companies.isEmpty {
                m = await Self.rows(tv: false, filter: "&with_companies=\(companies)", apiKey: key, lang: lang)
            }
            let s = await series
            guard let self else { return }
            self.seriesRows = s
            self.movieRows = m
            self.isLoading = false
        }
    }

    /// Hulu's TMDB companies ("Hulu", "Hulu Originals"…), joined for `with_companies`.
    nonisolated private struct CompanySearch: Decodable {
        nonisolated struct Company: Decodable {
            let id: Int
            let name: String?
        }
        let results: [Company]?
    }

    nonisolated private static func huluCompanies(apiKey: String) async -> String {
        guard let url = URL(string: "https://api.themoviedb.org/3/search/company?api_key=\(apiKey)&query=Hulu"),
              let result = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(CompanySearch.self, from: result.0) else { return "" }
        let ids = (decoded.results ?? []).filter { ($0.name ?? "").lowercased().hasPrefix("hulu") }.map { String($0.id) }
        return ids.prefix(6).joined(separator: "|")
    }

    nonisolated private static func rows(tv: Bool, filter: String, apiKey: String, lang: String) async -> [Row] {
        let media = tv ? "tv" : "movie"
        let region = OrbitPlatformExtrasModel.region(language: lang)
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let dateKey = tv ? "first_air_date" : "primary_release_date"
        var specs: [(id: String, title: String, query: String)] = [
            ("hulu-popular-\(media)", tv ? "Séries Hulu populaires" : "Films Hulu populaires", "&sort_by=popularity.desc"),
            ("hulu-new-\(media)", tv ? "Nouvelles séries Hulu" : "Nouveaux films Hulu",
             "&sort_by=\(dateKey).desc&\(dateKey).lte=\(today)"),
        ]
        for (genre, name) in tv ? seriesGenres : movieGenres {
            specs.append(("hulu-genre-\(genre)-\(media)", name, "&sort_by=popularity.desc&with_genres=\(genre)"))
        }
        let lists = await withTaskGroup(of: (Int, [MetaPreview]).self) { group in
            for (index, spec) in specs.enumerated() {
                group.addTask {
                    let address = "https://api.themoviedb.org/3/discover/\(media)?api_key=\(apiKey)&language=\(lang)"
                        + "&watch_region=\(region)&with_watch_providers=337&with_watch_monetization_types=flatrate"
                        + filter + spec.query
                    // Hulu's titles are often not translated on TMDB: kept without a French synopsis.
                    async let first = OrbitPlatformExtrasModel.fetch(address + "&page=1", tv: tv, requiresOverview: false)
                    async let second = OrbitPlatformExtrasModel.fetch(address + "&page=2", tv: tv, requiresOverview: false)
                    return (index, await first + second)
                }
            }
            var out: [Int: [MetaPreview]] = [:]
            for await (index, items) in group { out[index] = items }
            return out
        }
        return specs.enumerated().compactMap { index, spec in
            let items = lists[index] ?? []
            guard items.count >= 5 else { return nil }
            return Row(id: spec.id, title: spec.title, items: Array(items.prefix(20)))
        }
    }
}


/// The hero following the page's scroll (its bottom in sight above the first row), fading only
/// once the page goes past it.
private struct OrbitDisneyHeroScroll<Content: View>: View {
    @ObservedObject var tracker: OrbitScrollTracker
    let keepsUntil: CGFloat
    let content: Content

    init(tracker: OrbitScrollTracker, keepsUntil: CGFloat, @ViewBuilder content: () -> Content) {
        self.tracker = tracker
        self.keepsUntil = keepsUntil
        self.content = content()
    }

    var body: some View {
        let y = max(0, tracker.y)
        content
            .offset(y: -y)
            .opacity(Double(1 - min(1, max(0, (y - keepsUntil) / 420))))
    }
}

/// Steven: "Nouveau", black on white, on the titles out lately (the last three months).
struct OrbitNewBadge: View {
    var text: String = String(localized: "Nouveau")

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white))
    }
}

/// Disney+'s label on a tile: a new season or new episodes first, "Bientôt" for what is announced,
/// else "Nouveau" for what came out lately.
func orbitDisneyLabel(_ item: MetaPreview, _ meta: OrbitMeta?) -> String? {
    switch OrbitTitleNews.of(item, meta) {
    case .newSeason: return String(localized: "Nouvelle saison")
    case .newEpisodes: return String(localized: "Nouveaux épisodes")
    case .soon: return String(localized: "Bientôt")
    case nil: return orbitIsFresh(item, meta) ? String(localized: "Nouveau") : nil
    }
}

/// Out in the last 90 days (its release, or a series' first airing).
func orbitIsFresh(_ item: MetaPreview, _ meta: OrbitMeta? = nil) -> Bool {
    // (Steven: none on Disney+'s own rows — his catalogs carry no date; TMDB's is used then.)
    let known: String? = item.rawReleaseDate
    guard let raw = (known?.count ?? 0) >= 10 ? known : meta?.released, raw.count >= 10 else { return false }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    guard let date = formatter.date(from: String(raw.prefix(10))) else { return false }
    let age = Date().timeIntervalSince(date)
    return age >= 0 && age < 90 * 24 * 3600
}

/// A Hulu title (its network or a producer is Hulu): Hulu's logo on it, wherever it shows.
func orbitIsHuluTitle(_ meta: OrbitMeta?) -> Bool {
    meta?.producers.contains { $0.lowercased().contains("hulu") } ?? false
}

/// A Disney+ programme of its own: made by Disney's studios or for Disney+ (TMDB's producers).
func orbitIsDisneyOwn(_ meta: OrbitMeta?) -> Bool {
    guard let producers = meta?.producers, !producers.isEmpty else { return false }
    let marks = ["disney", "pixar", "marvel studios", "lucasfilm", "national geographic"]
    return producers.contains { name in
        let lower = name.lowercased()
        return marks.contains { lower.contains($0) }
    }
}

/// Disney+'s or Hulu's logo in white (black on a focused white pill).
struct OrbitDisneyBrandLogo: View {
    let hulu: Bool
    let logoURL: String?
    var height: CGFloat = 44
    var dark = false
    var alignment: Alignment = .bottomLeading
    /// Steven: Hulu's own green on the hero (white in the bar).
    var huluInColour = false

    var body: some View {
        Group {
            if hulu {
                // Hulu's own logo (Steven's file), drawn white.
                Image("HuluLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: height * 0.62)
                    .frame(height: height, alignment: alignment)
                    .foregroundStyle(huluInColour && !dark ? OrbitDisneyLayout.huluGreen : (dark ? Color.black : Color.white))
            } else {
                // Steven's own file (sharp at every size, no margins, no wait), drawn plain white
                // (black on a focused pill).
                Image("DisneyPlusLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
                    .frame(width: height * 2.6, height: height, alignment: alignment)
                    .foregroundStyle(dark ? Color.black : Color.white)
            }
        }
        .foregroundStyle(dark ? Color.black : Color.white)
    }

    private var name: some View {
        Text("Disney+")
            .font(.system(size: height * 0.8, weight: .bold, design: .rounded))
            .fixedSize()
    }
}

// MARK: - Disney+'s newest app (Steven's video, 2026-10-27)

/// One of the brands under the hero: its studio page (Steven's folder of that studio when he has
/// one, else TMDB's company).
struct OrbitDisneyBrand {
    let name: String
    /// What the folder's title contains.
    let keys: [String]
    /// TMDB's company, when no folder of his matches.
    let company: String
    /// The hub's band (Disney+'s newest app: each brand its colour) and its line.
    let colours: [Color]
    let tagline: String
    /// Steven's own file for this brand (Star Wars, National Geographic), and whether it keeps its
    /// colours (National Geographic's yellow frame).
    var asset: String? = nil
    var assetInColour = false
    /// The folder's logo keeps its colours (Marvel's red box).
    var logoInColour = false

    static let all: [OrbitDisneyBrand] = [
        .init(name: "Disney", keys: ["walt disney", "disney"], company: "2",
              colours: [Color(red: 0.05, green: 0.27, blue: 0.70), Color(red: 0.03, green: 0.12, blue: 0.38)],
              tagline: String(localized: "Découvrez la magie de Disney")),
        .init(name: "Pixar", keys: ["pixar"], company: "3",
              colours: [Color(red: 0.16, green: 0.30, blue: 0.48), Color(red: 0.07, green: 0.12, blue: 0.22)],
              tagline: String(localized: "Des histoires pour tous les âges")),
        .init(name: "Marvel", keys: ["marvel"], company: "420",
              colours: [Color(red: 0.62, green: 0.06, blue: 0.08), Color(red: 0.22, green: 0.02, blue: 0.04)],
              tagline: String(localized: "L'univers Marvel"), logoInColour: true),
        .init(name: "Star Wars", keys: ["star wars", "lucasfilm"], company: "1",
              // (Steven: the band read as gone on Star Wars — a deep space blue, no longer near black.)
              colours: [Color(red: 0.16, green: 0.22, blue: 0.40), Color(red: 0.03, green: 0.05, blue: 0.13)],
              tagline: String(localized: "Il y a bien longtemps, dans une galaxie lointaine…"), asset: "StarWarsLogo"),
        .init(name: "National Geographic", keys: ["national geographic", "nat geo"], company: "7521",
              colours: [Color(red: 0.55, green: 0.45, blue: 0.05), Color(red: 0.16, green: 0.13, blue: 0.03)],
              tagline: String(localized: "Explorez notre monde"), asset: "NatGeoLogo", assetInColour: true),
    ]

    /// His folder for this studio (never Disney+ itself).
    var folder: (collectionId: String, folder: CollectionFolder)? {
        guard let collections = CollectionRepository.shared.collections.value_ as? [NuvioCollection] else { return nil }
        // Each key in turn (Steven: Star Wars before Lucasfilm).
        for key in keys {
            for collection in collections {
                for folder in collection.folders {
                    let title = folder.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                    guard !title.contains("+"), !title.contains("plus") else { continue }
                    if title.contains(key) { return (collection.id, folder) }
                }
            }
        }
        return nil
    }

    var logoURL: String? {
        let logo = folder?.folder.titleLogoUrl?.trimmingCharacters(in: .whitespaces) ?? ""
        return logo.isEmpty ? nil : logo
    }

    func route() -> OrbitStudioRoute {
        if let found = folder { return .folder(collectionId: found.collectionId, folder: found.folder) }
        return OrbitStudioRoute(name: name, companies: company, isNetwork: false, logo: nil, collectionId: nil, folderId: nil)
    }
}

/// The brands' row: five dark tiles, the studio's logo in white (Marvel in its red).
private struct OrbitDisneyBrandsRow: View {
    @ObservedObject var box: OrbitLeadBox
    let onEnter: () -> Void
    let onLeave: () -> Void
    let onSelect: () -> Void

    var body: some View {
        let L = OrbitDisneyLayout.self
        OrbitNativeTileStrip(count: OrbitDisneyBrand.all.count, spacing: L.brandGap, height: L.brandTile.height,
                             lastWidth: L.brandTile.width, box: box, alignment: .top,
                             onEnter: onEnter, onLeave: onLeave, onSelect: onSelect) { index, lit in
            OrbitDisneyBrandTile(brand: OrbitDisneyBrand.all[index], focused: lit)
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: L.brandTile.height, alignment: .topLeading)
    }
}

private struct OrbitDisneyBrandTile: View {
    let brand: OrbitDisneyBrand
    let focused: Bool

    var body: some View {
        let L = OrbitDisneyLayout.self
        let logoBox = CGSize(width: L.brandTile.width * 0.68, height: L.brandTile.height * 0.46)
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.12))
            if let logo = brand.logoURL {
                if brand.name == "Marvel" {
                    CachedAsyncImage(string: logo, contentMode: .fit,
                                     decodeSize: .points(width: logoBox.width, height: logoBox.height),
                                     loading: { Color.clear }, failure: { name })
                        .frame(width: logoBox.width, height: logoBox.height)
                } else {
                    Color.white
                        .frame(width: logoBox.width, height: logoBox.height)
                        .mask {
                            CachedAsyncImage(string: logo, contentMode: .fit,
                                             decodeSize: .points(width: logoBox.width, height: logoBox.height),
                                             loading: { Color.clear }, failure: { name })
                                .frame(width: logoBox.width, height: logoBox.height)
                        }
                }
            } else {
                name
            }
        }
        .frame(width: L.brandTile.width, height: L.brandTile.height)
        .modifier(OrbitDisneyFocus(focused: focused))
    }

    private var name: some View {
        Text(brand.name)
            .font(.system(size: 32, weight: .heavy))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 16)
    }
}

/// A row as in Disney+'s newest app: the focused title open in a 16:9 frame fixed at the margin
/// (its art cross-fading as the focus moves, the posters sliding behind), the others as posters,
/// one meta line under the frame. Built as Netflix's rows (Steven: the same moves).
private struct OrbitDisneyOpenRow: View {
    let row: OrbitDisneyRow
    @ObservedObject var box: OrbitLeadBox
    let isCurrent: Bool
    var aboveCurrent = false
    let isHulu: Bool
    @ObservedObject var metaStore: OrbitMetaStore
    let onEnter: () -> Void
    let onLeave: () -> Void
    let onSelect: () -> Void
    let onLeadChange: () -> Void

    /// Where the Top 10's open title is (it stops at its end); every other row keeps it at the margin.
    @State private var openX: CGFloat?

    var body: some View {
        let L = OrbitDisneyLayout.self
        let leadSlot = min(box.lead, max(0, row.slotCount - 1))
        let lead = row.item(atSlot: leadSlot)
        // (Newest app: the row above shows at the screen's top, closed.)
        let opens = isCurrent
        let frameX = row.top10 ? top10FrameX(lead: lead) : L.margin
        VStack(alignment: .leading, spacing: 0) {
            Text(row.title)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.white.opacity(isCurrent ? 0.92 : 0.7))
                .lineLimit(1)
                .frame(height: L.headingNew, alignment: .topLeading)
                .padding(.leading, L.margin + 2)
            OrbitNativeTileStrip(count: row.slotCount, spacing: L.gapNew, height: L.open.height,
                                 lastWidth: row.top10 ? OrbitHomeLayout.screenWidth : L.open.width, box: box,
                                 alignment: .center, keepsLeadAtMargin: true,
                                 onEnter: onEnter, onLeave: onLeave, onSelect: onSelect,
                                 onLeadChange: { new in
                                     onLeadChange()
                                     prefetch(around: row.item(atSlot: new))
                                 }) { slot, lit in
                let index = row.item(atSlot: slot)
                let item = row.items[index]
                let isLead = opens && slot == leadSlot
                // The frame is drawn by the row, fixed: the lead tile keeps its room, its poster kept
                // (hidden) under it — Steven's video, Left: the title just left showed a hole a
                // beat, its poster drawn anew.
                // (Steven's video, Right: a hole beside the frame — the next title's poster hidden at
                // the press, its room growing. Its poster sits at the right of its room — beside its
                // neighbour all along the slide, under the frame at its end — and hides only then.)
                ZStack(alignment: .trailing) {
                    Group {
                        if row.top10 {
                            OrbitDisneyTop10Poster(item: item, meta: metaStore.meta(for: item), rank: index + 1,
                                                   focused: lit && !isLead)
                        } else {
                            OrbitDisneyPosterNew(item: item, meta: metaStore.meta(for: item),
                                                 rank: nil, isHulu: isHulu, focused: lit && !isLead)
                        }
                    }
                    .opacity(isLead ? 0 : 1)
                    // (Steven's video: the poster faded in with the row's slide — a hole a beat. At once;
                    // hidden only once the slide is over, under the frame.)
                    .animation(isLead ? .linear(duration: 0.01).delay(0.4) : nil, value: isLead)
                }
                .frame(width: isLead ? L.open.width : nil, height: isLead ? L.open.height : nil, alignment: .trailing)
            }
            // Arriving on the row, it is open at once (only Left / Right move the frame's content).
            .animation(nil, value: isCurrent)
            .animation(nil, value: aboveCurrent)
            .frame(width: OrbitHomeLayout.screenWidth, height: L.open.height, alignment: .topLeading)
            .coordinateSpace(.named("disneyRow"))
            .overlay(alignment: .topLeading) {
                if opens, row.items.indices.contains(lead) {
                    let item = row.items[lead]
                    OrbitDisneyOpenFrame(item: item, meta: metaStore.meta(for: item), isHulu: isHulu, lit: isCurrent,
                                         rank: row.top10 ? lead + 1 : nil)
                        .offset(x: frameX)
                        .animation(OrbitDisneyLayout.horizontal, value: openX)
                }
            }
            if row.items.indices.contains(lead) {
                let item = row.items[lead]
                let meta = metaStore.meta(for: item)
                let info = OrbitInfo.make(item, meta: meta)
                HStack(spacing: 12) {
                    if let certification = meta?.certification { OrbitDisneyRating(text: certification, size: 15) }
                    // (Steven: the Top 10 says its genre only, under the open title.)
                    Text(row.top10 ? (meta?.genre ?? item.genres.first ?? "") : info.parts.joined(separator: " • "))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                }
                .frame(height: L.metaNew, alignment: .center)
                .padding(.leading, frameX)
                .id("\(item.type):\(item.id)")
                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2)), removal: .identity))
                .opacity(isCurrent ? 1 : 0)
                .animation(isCurrent ? .easeOut(duration: 0.2) : nil, value: isCurrent)
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
        .onAppear { prefetch(around: lead, includingIt: true) }
        // (Steven: Up from the franchises to the Top 10, the frame sat at the margin, the title's
        // room further right: the row, scrolled for its closed poster, put back on the open one.)
        .onChange(of: isCurrent) { _, now in
            guard now else { return }
            box.realign &+= 1
            DispatchQueue.main.async { box.realign &+= 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { box.realign &+= 1 }
        }
    }

    /// Where the Top 10's open title is: at the margin, or further right once the row has reached
    /// its end (it no longer scrolls). Worked out from the row's own sizes (Steven's photo: the frame,
    /// read off the screen, landed over the next title).
    private func top10FrameX(lead: Int) -> CGFloat {
        let L = OrbitDisneyLayout.self
        let n = row.items.count
        guard n > 0 else { return L.margin }
        let slot = L.posterNew.width + L.gapNew
        let content = CGFloat(n - 1) * slot + L.open.width
        let maxOffset = max(0, L.margin + content + L.margin - OrbitHomeLayout.screenWidth)
        let x = CGFloat(lead) * slot
        return L.margin + x - min(x, maxOffset)
    }

    /// The open art of the focused title and its neighbours, decoded before the focus gets there.
    private func prefetch(around index: Int, includingIt: Bool = false) {
        let L = OrbitDisneyLayout.self
        let request = ArtworkDecodeRequest(size: .points(width: L.open.width, height: L.open.height), fill: true,
                                           scale: UIScreen.main.scale).normalized
        guard !row.items.isEmpty else { return }
        for i in max(0, index - 1)...min(row.items.count - 1, index + 3) where includingIt || i != index {
            let item = row.items[i]
            let banner: String? = item.banner
            guard let raw = (banner ?? metaStore.meta(for: item)?.backdrop).flatMap(URL.init(string:)) else { continue }
            let address = ArtworkURLUpgrade.upgraded(raw, role: .backdrop) ?? raw
            guard ArtworkStore.cached(address, decode: request) == nil else { continue }
            Task { _ = try? await ArtworkStore.fetch(address, decode: request) }
        }
    }
}

/// The open title's frame: its art, its logo bottom left, its badge top left, the platform's logo
/// bottom right; the next title fades in over the last one.
private struct OrbitDisneyOpenFrame: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let isHulu: Bool
    let lit: Bool
    /// The Top 10's rank (its turquoise corner, as on the newest app).
    var rank: Int? = nil

    var body: some View {
        let L = OrbitDisneyLayout.self
        let shape = RoundedRectangle(cornerRadius: L.radius, style: .continuous)
        ZStack {
            Color(red: 0.07, green: 0.08, blue: 0.12)
            content
                .id("\(item.type):\(item.id)")
                .zIndex(1)
                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22)),
                                        removal: .opacity.animation(.linear(duration: 0.01).delay(0.24))))
        }
        .frame(width: L.open.width, height: L.open.height)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.white.opacity(lit ? 1 : 0), lineWidth: 4) }
        .shadow(color: .black.opacity(lit ? 0.5 : 0), radius: 20, y: 10)
        .allowsHitTesting(false)
    }

    private var content: some View {
        let L = OrbitDisneyLayout.self
        let info = OrbitInfo.make(item, meta: meta)
        let banner: String? = item.banner
        return ZStack(alignment: .bottomLeading) {
            if rank != nil { OrbitDisneyTop10Corner.ground(extent: L.open.height * 0.34, size: L.open) } else { Color(red: 0.07, green: 0.08, blue: 0.12) }
            // (Steven: Disney+'s and Hulu's marks on every focused title — the catalog's art: TMDB's first.)
            OrbitSwapImage(url: meta?.backdrop ?? banner, fallback: nil, size: L.open)
                .modifier(OrbitDisneyTop10Corner.Cut(extent: rank == nil ? 0 : L.open.height * 0.34))
            if let rank {
                OrbitDisneyTop10Corner.rankText(rank, size: L.open.height * 0.15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 22)
                    .padding(.top, 10)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            OrbitTitleMark(name: item.name, logo: info.logo, maxSize: CGSize(width: 380, height: 130), textSize: 40,
                           fallbackLogo: info.logoFallback, hugsLogo: true)
                .frame(width: 380, alignment: .leading)
                .padding(.leading, 26)
                .padding(.bottom, 24)
            if rank == nil, let text = orbitDisneyLabel(item, meta) {
                OrbitNewBadge(text: text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
            }
            // (Steven: Swiping Right on the Devil showed Hulu's mark as a poster, Disney+'s open: the
            // title's own platform, everywhere.)
            // (Steven: Disney+'s on every focused title — the app marks Hulu's alone.)
            if isHulu || orbitIsHuluTitle(meta) {
                OrbitDisneyBrandLogo(hulu: true, logoURL: nil, height: 40, alignment: .trailing, huluInColour: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 24)
                    .padding(.bottom, 22)
            }
        }
        .frame(width: L.open.width, height: L.open.height)
    }
}

/// A poster of the newest app's rows: its badge bottom left, the platform's logo bottom right, and
/// in the Top 10, its rank top left.
private struct OrbitDisneyPosterNew: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let rank: Int?
    let isHulu: Bool
    let focused: Bool

    var body: some View {
        let L = OrbitDisneyLayout.self
        let size = L.posterNew
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.07, green: 0.08, blue: 0.12)
            Text(item.name)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // (Steven: Disney+'s and Hulu's marks on every poster — the catalog's art carries them:
            // TMDB's French poster first, the catalog's only without one.)
            OrbitImage(url: meta?.localPoster ?? meta?.titledPoster ?? item.poster, fallback: item.poster ?? item.rawPosterUrl,
                       mode: .fill, size: size)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: UnitPoint(x: 0.5, y: 0.72), endPoint: .bottom)
            if let text = orbitDisneyLabel(item, meta) {
                OrbitNewBadge(text: text)
                    .padding(.leading, 12)
                    .padding(.bottom, 14)
            }
            if let rank {
                Text("\(rank)")
                    .font(.system(size: 46, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.7), radius: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 14)
                    .padding(.top, 8)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .modifier(OrbitDisneyFocus(focused: focused))
    }
}

/// The newest app's Top 10 corner: the title's art cut by a large circle across its top left
/// corner, a turquoise-blue gradient there, the rank in turquoise (as Steven's own cards).
enum OrbitDisneyTop10Corner {
    /// `extent`: the cut's reach on the edges; `size`: the card's. The teal darkens from the corner
    /// right to the cut (Steven: "trop uni" — it spread over the whole card, the corner one shade).
    static func ground(extent: CGFloat, size: CGSize) -> some View {
        LinearGradient(stops: [
            // (Steven, side by side with the app's video: a teal, not a blue — measured on it.)
            .init(color: Color(red: 0.02, green: 0.62, blue: 0.67), location: 0),
            .init(color: Color(red: 0.00, green: 0.36, blue: 0.40), location: 0.55),
            .init(color: Color(red: 0.00, green: 0.19, blue: 0.23), location: 1),
        ], startPoint: .topLeading,
           endPoint: UnitPoint(x: extent / 2 / max(1, size.width), y: extent / 2 / max(1, size.height)))
    }

    static func rankText(_ rank: Int, size: CGFloat) -> some View {
        Text("\(rank)")
            // (Steven, side by side with the app: geometric, not round.)
            .font(.custom("AvenirNext-Bold", size: rank >= 10 ? size * 0.78 : size))
            .kerning(rank >= 10 ? -size * 0.05 : 0)
            .foregroundStyle(Color(red: 0.02, green: 0.76, blue: 0.83))
    }

    /// The art inside a circle through (extent, 0) and (0, extent), bulging slightly towards the
    /// corner (Steven's cards: 0.47 of the width on a poster). No cut with no extent.
    struct Cut: ViewModifier {
        let extent: CGFloat

        @ViewBuilder
        func body(content: Content) -> some View {
            if extent > 0 {
                content.mask {
                    Circle()
                        .frame(width: extent * 11.13, height: extent * 11.13)
                        .position(x: extent * 4.4, y: extent * 4.4)
                }
            } else {
                content
            }
        }
    }
}

/// A Top 10 poster of the newest app: its turquoise corner and rank, its art with its title, the
/// rating and the genre at its foot.
private struct OrbitDisneyTop10Poster: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let rank: Int
    let focused: Bool

    var body: some View {
        let L = OrbitDisneyLayout.self
        let size = L.posterNew
        let genre: String? = meta?.genre ?? item.genres.first
        // (Steven: some posters came up empty — TMDB's when the catalog has none.)
        let poster: String? = meta?.localPoster ?? meta?.titledPoster ?? item.poster ?? meta?.cleanPoster
        ZStack(alignment: .topLeading) {
            OrbitDisneyTop10Corner.ground(extent: size.width * 0.47, size: size)
            OrbitImage(url: poster, fallback: meta?.cleanPoster ?? item.rawPosterUrl, mode: .fill, size: size)
                .frame(width: size.width, height: size.height)
                .modifier(OrbitDisneyTop10Corner.Cut(extent: size.width * 0.47))
            // Steven (side by side with the app: too even): the poster's foot goes to near black,
            // as measured on the video (the art gone by two thirds of the height).
            LinearGradient(stops: [
                .init(color: .clear, location: 0.48),
                .init(color: Color(red: 0.01, green: 0.01, blue: 0.03).opacity(0.85), location: 0.66),
                .init(color: Color(red: 0.01, green: 0.01, blue: 0.03).opacity(0.97), location: 0.76),
                .init(color: Color(red: 0.01, green: 0.01, blue: 0.03), location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .frame(width: size.width, height: size.height)
            OrbitDisneyTop10Corner.rankText(rank, size: 66)
                .padding(.leading, size.width * 0.055)
                .padding(.top, 4)
            // Steven: on the poster (its foot), the rating and the genre only.
            VStack {
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    if let certification = meta?.certification { OrbitDisneyRating(text: certification, size: 15) }
                    if let genre {
                        Text(genre)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 40)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .modifier(OrbitDisneyFocus(focused: focused, lifts: false))
    }
}

/// The brands' hub (newest app): the pills, then the focused brand's band — its logo, its line,
/// TOUT PARCOURIR and a few of its titles. A pill opens its studio page.
private struct OrbitDisneyBrandsHub: View {
    @ObservedObject var box: OrbitLeadBox
    let isCurrent: Bool
    let onEnter: () -> Void
    let onLeave: () -> Void
    let onSelect: () -> Void
    /// A title of the band opened.
    let onOpen: (MetaPreview) -> Void
    @ObservedObject private var films = OrbitStudioFilmsModel.shared
    @FocusState private var browseFocused: Bool
    @FocusState private var filmFocused: Int?
    /// The band's title opened (the focus back on it on the way back).
    @State private var reopenFilm: Int?
    /// The brand it was opened from (the system's landing on the first pill on the way back
    /// switched the band to Disney — Steven's video).
    @State private var reopenBrand: Int?

    var body: some View {
        let L = OrbitDisneyLayout.self
        let W = OrbitHomeLayout.screenWidth
        let brands = OrbitDisneyBrand.all
        let brand = brands[min(max(0, box.lead), brands.count - 1)]
        let titles = films.title == brand.name ? (films.rows.first?.items ?? []) : []
        ZStack(alignment: .topLeading) {
            // Steven: the band there as soon as the brands come in sight; a brand to the next, a
            // plain cross-fade (its colour, its logo, its titles).
            ZStack {
                LinearGradient(colors: brand.colours, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .id(brand.name)
                    .transition(.opacity)
            }
            .frame(width: W, height: L.hubHeight)
            .animation(.easeInOut(duration: 0.4), value: brand.name)
            VStack(alignment: .leading, spacing: 0) {
                // Steven: the pills centred on the screen.
                let pillsWidth = CGFloat(brands.count) * L.pill.width + CGFloat(brands.count - 1) * 18
                OrbitNativeTileStrip(count: brands.count, spacing: 18, height: L.pill.height * 1.12,
                                     lastWidth: L.pill.width, box: box, margin: max(L.margin, (W - pillsWidth) / 2),
                                     alignment: .center,
                                     onEnter: onEnter, onLeave: onLeave, onSelect: onSelect,
                                     onLeadChange: { i in films.focus(title: brands[i].name) }) { i, lit in
                    OrbitDisneyBrandPill(brand: brands[i], focused: lit)
                }
                // Back from a title of the band: the pills out of reach until its poster has the
                // focus again (Steven's video: the system landed on Walt Disney a beat — its band).
                .disabled(reopenFilm != nil)
                .frame(width: W, height: L.pill.height * 1.12, alignment: .topLeading)
                .padding(.top, 26)
                HStack(alignment: .center, spacing: 0) {
                    VStack(spacing: 26) {
                        ZStack {
                            VStack(spacing: 26) {
                                OrbitDisneyWhiteLogo(brand: brand, box: CGSize(width: 460, height: 190), nameSize: 80)
                                Text(brand.tagline)
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .id(brand.name)
                            .transition(.opacity)
                        }
                        // Steven: TOUT PARCOURIR can be pressed (Down from the pills): the brand's page.
                        Button {
                            box.reopen = box.lead
                            onSelect()
                        } label: {
                            Text(String(localized: "TOUT PARCOURIR"))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(browseFocused ? Color.black : Color.white)
                                .padding(.horizontal, 40)
                                .frame(height: 70)
                                .background(Capsule().fill(browseFocused ? Color.white : Color.white.opacity(0.16)))
                                .scaleEffect(browseFocused ? 1.06 : 1)
                                .animation(.easeOut(duration: 0.18), value: browseFocused)
                        }
                        .buttonStyle(OrbitPlainStyle())
                        .focused($browseFocused)
                        // (Steven: Up from the row below took two presses — it stopped here first.)
                        .disabled(!isCurrent || reopenFilm != nil)
                    }
                    .frame(width: 720)
                    // Steven: the band's titles scroll (Right from TOUT PARCOURIR), each opens its page.
                    ZStack(alignment: .leading) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 32) {
                                ForEach(Array(titles.prefix(20).enumerated()), id: \.offset) { i, item in
                                    Button {
                                        reopenFilm = i
                                        reopenBrand = box.lead
                                        onOpen(item)
                                    } label: {
                                        OrbitImage(url: item.poster, fallback: nil, mode: .fill, size: CGSize(width: 295, height: 440))
                                            .frame(width: 295, height: 440)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .strokeBorder(Color.white.opacity(filmFocused == i ? 1 : 0), lineWidth: 4)
                                            }
                                            .scaleEffect(filmFocused == i ? 1.06 : 1)
                                            .shadow(color: .black.opacity(filmFocused == i ? 0.5 : 0), radius: 16, y: 8)
                                            .animation(.easeOut(duration: 0.18), value: filmFocused == i)
                                    }
                                    .buttonStyle(OrbitPlainStyle())
                                    .focused($filmFocused, equals: i)
                                    // Back from it, its poster alone can take the focus (Steven: a
                                    // beat on TOUT PARCOURIR first).
                                    .disabled(reopenFilm.map { $0 != i } ?? !isCurrent)
                                }
                            }
                            .padding(.vertical, 30)
                        }
                        .contentMargins(.leading, 24, for: .scrollContent)
                        .contentMargins(.trailing, L.margin, for: .scrollContent)
                        .scrollClipDisabled()
                        // (Steven: scrolled, the titles ran over the brand's logo and TOUT PARCOURIR:
                        // cut at the column's edge, free above and below for the focused one.)
                        .mask(Rectangle().padding(.vertical, -40))
                        .padding(.vertical, -30)
                        .id(brand.name + "|\(titles.count)")
                        .transition(.opacity)
                    }
                }
                .frame(width: W, alignment: .leading)
                // (Steven: TOUT PARCOURIR out of reach from Star Wars or National Geographic — Down
                // from any pill finds it.)
                .focusSection()
                .padding(.top, 34)
                .animation(.easeInOut(duration: 0.4), value: brand.name)
                .animation(.easeInOut(duration: 0.3), value: titles.count)
            }
        }
        .frame(width: W, height: L.hubHeight, alignment: .topLeading)
        .clipped()
        .onAppear {
            films.focus(title: brand.name)
            // Back from a title of the band: its poster takes the focus again (after the row's own
            // restore on the brand).
            if let back = reopenFilm {
                let appeared = ProcessInfo.processInfo.systemUptime
                let brandBack = reopenBrand ?? box.lead
                let restore = {
                    if box.lead != brandBack {
                        box.lead = brandBack
                        films.focus(title: brands[brandBack].name)
                    }
                    if filmFocused != back { filmFocused = back }
                }
                restore()
                for delay in [0.0, 0.1, 0.3, 0.6, 0.9] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        guard reopenFilm == back, !ViewerInputClock.shared.hasInput(since: appeared) else { return }
                        restore()
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { reopenFilm = nil; reopenBrand = nil }
            }
        }
    }
}

/// A brand's pill: its logo in white on a translucent capsule; focused, the brand's colour with a
/// white ring.
private struct OrbitDisneyBrandPill: View {
    let brand: OrbitDisneyBrand
    let focused: Bool

    var body: some View {
        let L = OrbitDisneyLayout.self
        let logoBox = CGSize(width: L.pill.width * 0.66, height: L.pill.height * 0.5)
        ZStack {
            Capsule().fill(focused ? AnyShapeStyle(LinearGradient(colors: brand.colours, startPoint: .top, endPoint: .bottom))
                                   : AnyShapeStyle(Color.white.opacity(0.14)))
            OrbitDisneyWhiteLogo(brand: brand, box: logoBox, nameSize: 24)
        }
        .frame(width: L.pill.width, height: L.pill.height)
        .overlay { Capsule().strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 5) }
        .scaleEffect(focused ? 1.1 : 1)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

/// The brand's logo, large, in the hub.
private struct OrbitDisneyBrandLogoBig: View {
    let brand: OrbitDisneyBrand

    var body: some View {
        OrbitDisneyWhiteLogo(brand: brand, box: CGSize(width: 460, height: 190), nameSize: 80)
            .id(brand.name)
            .transition(.opacity)
    }
}

/// A brand's logo drawn in white (its shape alone), or its name.
private struct OrbitDisneyWhiteLogo: View {
    let brand: OrbitDisneyBrand
    let box: CGSize
    let nameSize: CGFloat

    var body: some View {
        if let asset = brand.asset {
            // Steven's own files (Star Wars, National Geographic).
            Image(asset)
                .renderingMode(brand.assetInColour ? .original : .template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.white)
                .frame(width: box.width, height: box.height)
        } else if let logo = brand.logoURL, brand.logoInColour {
            CachedAsyncImage(string: logo, contentMode: .fit,
                             decodeSize: .points(width: box.width, height: box.height),
                             loading: { Color.clear }, failure: { name })
                .frame(width: box.width, height: box.height)
        } else if let logo = brand.logoURL {
            Color.white
                .frame(width: box.width, height: box.height)
                .mask {
                    CachedAsyncImage(string: logo, contentMode: .fit,
                                     decodeSize: .points(width: box.width, height: box.height),
                                     loading: { Color.clear }, failure: { name })
                        .frame(width: box.width, height: box.height)
                }
        } else {
            name.frame(width: box.width, height: box.height)
        }
    }

    private var name: some View {
        Text(brand.name)
            .font(.system(size: nameSize, weight: .heavy))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
    }
}
