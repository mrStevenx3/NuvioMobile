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
    static let background = Color(red: 0.047, green: 0.055, blue: 0.086)
    static let turquoise = Color(red: 0.13, green: 0.73, blue: 0.80)
    static let brandBlue = Color(red: 0.06, green: 0.22, blue: 0.62)
    static let margin: CGFloat = OrbitHomeLayout.margin
    /// The hero's art (full width), its text block.
    static let heroArtHeight: CGFloat = 900
    static let infoTop: CGFloat = 200
    static let logoSize = CGSize(width: 620, height: 190)
    static let synopsisWidth: CGFloat = 820
    /// The first row's top: its heading and the top of its cards on the first screen.
    static let rowsTop: CGFloat = 800
    /// A tile's name and meta line under it.
    static let labelHeight: CGFloat = 76
    /// Where the current row's top rests once the hero has gone.
    static let restTop: CGFloat = 160
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
}

/// One row of the Disney+ page.
struct OrbitDisneyRow: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [MetaPreview]
    let top10: Bool
    /// Portrait posters (the franchises and the genres), as in Disney+'s 2026 app.
    var portrait = false

    static func == (a: OrbitDisneyRow, b: OrbitDisneyRow) -> Bool {
        a.id == b.id && a.top10 == b.top10 && a.items.map(\.id) == b.items.map(\.id)
    }

    var cardSize: CGSize { top10 ? OrbitDisneyLayout.top10 : portrait ? OrbitDisneyLayout.poster : OrbitDisneyLayout.tile }
    /// The 16:9 tiles have their name and meta line under them.
    var hasLabels: Bool { !top10 && !portrait }
    var height: CGFloat {
        OrbitDisneyLayout.headingHeight + cardSize.height + (hasLabels ? OrbitDisneyLayout.labelHeight : 0) + OrbitDisneyLayout.rowGap
    }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true
    /// A title was opened over the page: no trailer starts again behind it (Steven: Prime's kept
    /// playing, its sound under the title's page).
    @State private var covered = false

    /// 0: Disney+, 1: Hulu.
    @State private var mode = 0
    /// 0: the hero; then the rows.
    @State private var current = 0
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

    private var isHulu: Bool { mode == 1 }

    private var rows: [OrbitDisneyRow] {
        isHulu ? huluRows : disneyRows
    }

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
        var shown = Set<String>()
        for row in Self.alternate(hulu.seriesRows, hulu.movieRows) {
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
    private var heroItems: [MetaPreview] {
        if isHulu {
            let items = Self.alternate(hulu.seriesRows.first?.items ?? [], hulu.movieRows.first?.items ?? [])
            return Array(items.prefix(6))
        }
        let fresh = model.stripRows.filter { row in
            let h = row.heading.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return row.status == .loaded && (h.contains("nouveau") || h.contains("nouvelle"))
        }.map { $0.section?.items ?? [] }
        var items = fresh.count >= 2 ? Self.alternate(fresh[0], fresh[1]) : fresh.first ?? []
        if items.isEmpty { items = rows.first(where: { !$0.top10 })?.items ?? rows.first?.items ?? [] }
        return Array(items.filter { $0.banner != nil }.prefix(6))
    }

    private var sectionCount: Int { 1 + rows.count }

    /// The row a section shows (nil: the hero).
    private func rowIndex(of section: Int) -> Int? { section >= 1 ? section - 1 : nil }

    /// Each row's top in the page.
    private func rowTops(_ rows: [OrbitDisneyRow]) -> [CGFloat] {
        var y = OrbitDisneyLayout.rowsTop
        return rows.map { row in defer { y += row.height }; return y }
    }

    /// How far the page has moved up: none on the hero, else the current row at its rest.
    private func scroll(_ rows: [OrbitDisneyRow]) -> CGFloat {
        guard let r = rowIndex(of: current), rows.indices.contains(r) else { return 0 }
        return rowTops(rows)[r] - OrbitDisneyLayout.restTop
    }

    private static func identity(_ item: MetaPreview) -> String {
        let year: String = item.releaseInfo.map { String($0.prefix(4)) } ?? ""
        return item.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) + "|" + year
    }

    private func lead(of row: OrbitDisneyRow) -> Int {
        min(leads[row.id] ?? 0, max(0, row.items.count - 1))
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

            // Steven (device: back to the top, the hero came back in two steps): the hero stays in
            // place and fades with the page's move; the tiles and rows move up over it.
            OrbitDisneyHero(item: hero, meta: hero.flatMap { metaStore.meta(for: $0) },
                            count: heroItems.count, index: min(heroIndex, max(0, heroItems.count - 1)),
                            focused: pageFocused && current == 0, isHulu: isHulu,
                            trailerURL: trailerURL(for: hero),
                            onTrailerFailure: { trailer.playbackFailed($0) },
                            onTrailerEnded: {
                                trailer.playbackFinished()
                                advanceHero()
                            })
                .opacity(offset < 1 ? 1 : 0)
                .animation(reduceMotion ? nil : OrbitDisneyLayout.vertical, value: offset < 1)

                            nativeSections(rows)
                    .disabled(search != nil)
            

            // Under the bar: a shade so the rows never run under it unreadable.
            LinearGradient(colors: [OrbitDisneyLayout.background, OrbitDisneyLayout.background.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: W, height: 150)
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

            CollectionFilterBar(filter: .constant(nil), onSearch: openSearch, showsTypes: false,
                                switchItems: ["Disney+", "Hulu"], switchSelection: $mode)
                .disabled(search != nil || (pageFocused && current > 0))
                .opacity(search != nil ? 0 : 1)

            OrbitPlatformIntro(title: model.folderTitle, logoUrl: model.titleLogoUrl ?? route.titleLogoUrl,
                               brand: OrbitDisneyLayout.brandBlue)

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
            height: { s in s == 0 ? OrbitDisneyLayout.rowsTop - OrbitDisneyLayout.restTop : (rows.indices.contains(s - 1) ? rows[s - 1].height : 0) },
            topLine: OrbitDisneyLayout.restTop, current: current, hidesAbove: true,
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
            focusRow: { s in if rows.indices.contains(s - 1) { leads.box(rows[s - 1].id).focusRequest &+= 1 } }
        ) { s, focused in
            if s == 0 {
                Color.clear
            } else if rows.indices.contains(s - 1) {
                let row = rows[s - 1]
                OrbitDisneyRowView(row: row, box: leads.box(row.id), isCurrent: s == current,
                                   focused: focused, metaStore: metaStore,
                                       onEnter: { nativeEnter(s) }, onLeave: nativeLeave, onSelect: select,
                                       onLeadChange: { refreshAfterMove() })
            }
        }
    }

    /// The focus came into section `s` (a row's title, or the hero).
    private func nativeEnter(_ s: Int) {
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
                let next = lead(of: row) + step
                guard row.items.indices.contains(next) else { return }
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
                    .init(color: .clear, location: 0.45),
                    .init(color: L.background.opacity(0.75), location: 0.75),
                    .init(color: L.background, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            if let item {
                info(item)
                    .offset(x: L.margin, y: L.infoTop)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func info(_ item: MetaPreview) -> some View {
        let L = OrbitDisneyLayout.self
        let info = OrbitInfo.make(item, meta: meta)
        return VStack(alignment: .leading, spacing: 0) {
            // The platform's mark sits right on the title's logo, both at the box's bottom (Steven:
            // the Hulu mark floated high above a short logo).
            VStack(alignment: .leading, spacing: 18) {
                Group {
                    if isHulu {
                        Text("hulu")
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.11, green: 0.91, blue: 0.51))
                    } else if orbitIsDisneyOwn(meta) {
                        // Steven: the Disney+ mark only on its own programmes, no "Nouveau".
                        Text("Disney+")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 52, alignment: .bottomLeading)
                OrbitTitleMark(name: item.name, logo: info.logo, maxSize: L.logoSize, textSize: 64,
                               fallbackLogo: info.logoFallback, hugsLogo: true)
            }
            .frame(width: L.logoSize.width, height: 52 + 18 + L.logoSize.height, alignment: .bottomLeading)
            OrbitDisneyMetaLine(certification: meta?.certification, parts: info.parts)
                .padding(.top, 24)
            Text(info.synopsis)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineSpacing(4)
                .lineLimit(2)
                .frame(width: L.synopsisWidth, alignment: .topLeading)
                .padding(.top, 16)
            HStack(spacing: 16) {
                Text(String(localized: "DÉTAILS"))
                    .font(.system(size: 21, weight: .bold))
                    .kerning(2)
                    .foregroundStyle(focused ? L.background : Color.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 7).fill(focused ? Color.white : Color.white.opacity(0.18)))
                    .scaleEffect(focused ? 1.05 : 1, anchor: .leading)
                    .animation(.easeOut(duration: 0.18), value: focused)
            }
            .padding(.top, 28)
            if count > 1 {
                HStack(spacing: 10) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(i == index ? 1 : 0.35))
                            .frame(width: i == index ? 26 : 10, height: 10)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: index)
                .padding(.top, 30)
            }
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
            if orbitIsFresh(item) {
                OrbitNewBadge().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .modifier(OrbitDisneyFocus(focused: focused))
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
                if orbitIsFresh(item) {
                    OrbitNewBadge().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12)
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


/// Steven: "Nouveau", black on white, on the titles out lately (the last three months).
struct OrbitNewBadge: View {
    var body: some View {
        Text(String(localized: "Nouveau"))
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white))
    }
}

/// Out in the last 90 days (its release, or a series' first airing).
func orbitIsFresh(_ item: MetaPreview) -> Bool {
    guard let raw = item.rawReleaseDate, raw.count >= 10 else { return false }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    guard let date = formatter.date(from: String(raw.prefix(10))) else { return false }
    let age = Date().timeIntervalSince(date)
    return age >= 0 && age < 90 * 24 * 3600
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
