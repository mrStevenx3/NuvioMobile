import Combine
import SharedCore
import SwiftUI

// Orbit × HBO Max (Steven, 2026-10-25: his video of the TV app). Orbit's DNA kept (one focusable
// canvas; the house and the platform's pill top left; the intro; trailers on a rest).
//
//  - HBO Max's night blue. On arrival, a full-screen carousel of the new titles: the art (its
//    trailer on a rest) under a gradient from the left, "HBO ORIGINAL" above the logo on HBO's own,
//    the blue "NOUVEAU" tag, three lines of synopsis, the white "Voir le film" button, the dots in
//    the middle, the first row's heading peeking at the bottom.
//  - The rows: tall posters (HBO's own carry his add-on's "HBO Original" mark), the focused one
//    framed in white, the blue "NOUVEAU" tag top left; his Top 10 images (the thin dark-glass rank on
//    the left). Down from the carousel, it goes and the rows climb to the top, the row above still
//    showing over the current one, as in the TV app.

enum OrbitHBOLayout {
    static let background = Color(red: 0.02, green: 0.03, blue: 0.09)
    /// HBO Max's blue (the "NOUVEAU" tag, the intro).
    static let blue = Color(red: 0.16, green: 0.27, blue: 0.98)
    static let margin: CGFloat = OrbitHomeLayout.margin
    static let infoTop: CGFloat = 400
    static let logoSize = CGSize(width: 620, height: 210)
    static let synopsisWidth: CGFloat = 760
    /// The first row's heading peeks at the bottom of the carousel.
    static let rowsTopOnArrival: CGFloat = 985
    /// Once in the rows: the first row's top; the next ones keep the row above in view over them.
    static let firstRowLine: CGFloat = 130
    static let aboveRowShows: CGFloat = 0.55
    static let headingHeight: CGFloat = 48
    /// The Top 10's own heading (HBO Max 2026: "TOP 10" in dark glass, "DES SÉRIES / DU JOUR" beside it).
    static let top10HeadingHeight: CGFloat = 116
    static let poster = CGSize(width: 240, height: 360)
    /// The Top 10's rank, drawn by Orbit (it fills when focused, as in the TV app), the poster over its right.
    static let rankWidth: CGFloat = 112
    static let rankWidthTen: CGFloat = 190
    static let rankUnderPoster: CGFloat = 34
    /// Steven (official screenshots): some rows are wide tiles (the genres here).
    static let tile = CGSize(width: 400, height: 225)
    /// "Sello HBO" (the app's own): its large landscape cards.
    static let featured = CGSize(width: 640, height: 360)
    /// "Universo Max": its round brand tiles.
    static let universe: CGFloat = 210
    static let gap: CGFloat = 24
    static let rowGap: CGFloat = 44
    static let radius: CGFloat = 6
    static let focusScale: CGFloat = 1.06
    static let horizontal = Animation.easeOut(duration: 0.24)
    static let vertical = Animation.easeInOut(duration: 0.38)
}

struct OrbitHBORow: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [MetaPreview]
    let top10: Bool
    var wide: Bool = false
    /// HBO Max's "Sello HBO": large landscape cards of HBO's own.
    var featured: Bool = false
    /// HBO Max's "Universo Max": the round brands (each opens its studio).
    var universe: Bool = false

    static func == (a: OrbitHBORow, b: OrbitHBORow) -> Bool {
        a.id == b.id && a.top10 == b.top10 && a.wide == b.wide && a.featured == b.featured && a.universe == b.universe
            && a.items.map(\.id) == b.items.map(\.id)
    }

    var count: Int { universe ? OrbitHBOBrand.all.count : items.count }

    var cardHeight: CGFloat {
        if universe { return OrbitHBOLayout.universe }
        if featured { return OrbitHBOLayout.featured.height }
        return wide ? OrbitHBOLayout.tile.height : OrbitHBOLayout.poster.height
    }
    var headingHeight: CGFloat { top10 ? OrbitHBOLayout.top10HeadingHeight : OrbitHBOLayout.headingHeight }
    var height: CGFloat { headingHeight + cardHeight + OrbitHBOLayout.rowGap }

    private func rankWidth(_ index: Int) -> CGFloat {
        guard top10 else { return 0 }
        return (index == 9 ? OrbitHBOLayout.rankWidthTen : OrbitHBOLayout.rankWidth) - OrbitHBOLayout.rankUnderPoster
    }

    func slot(_ index: Int) -> CGFloat {
        let L = OrbitHBOLayout.self
        if universe { return L.universe + L.gap }
        if featured { return L.featured.width + L.gap }
        return rankWidth(index) + (wide ? L.tile.width : L.poster.width) + L.gap
    }

    /// From the focused one (at the margin).
    func x(of index: Int, lead: Int) -> CGFloat {
        guard index > lead else { return index == lead ? 0 : -slot(index) }
        var x: CGFloat = 0
        for i in lead..<index { x += slot(i) }
        return x
    }
}

/// HBO's own title: Steven's add-on marks it in its image address ("/h/v11/…" HBO Original,
/// "/m/v11/…" Max Original; on the Top 10, "/poster/v11/h3/…").
enum OrbitHBOOwn {
    case hbo, max

    /// Steven: Orbit decides (not his add-on's art): TMDB's producers and networks — "HBO…" an HBO
    /// production, "HBO Max" / "Max" a Max one.
    static func made(_ meta: OrbitMeta?) -> OrbitHBOOwn? {
        guard let meta else { return nil }
        let makers = meta.producers.map { $0.lowercased() }
        if makers.contains(where: { $0.hasPrefix("hbo") && !$0.contains("max") }) { return .hbo }
        if makers.contains(where: { $0 == "max" || $0.contains("hbo max") || $0.contains("max original") }) { return .max }
        return nil
    }

    static func of(_ item: MetaPreview) -> OrbitHBOOwn? {
        let poster: String = item.poster ?? ""
        if poster.range(of: #"/h/v\d+/|/poster/v\d+/h\d+/"#, options: [.regularExpression, .caseInsensitive]) != nil { return .hbo }
        if poster.range(of: #"/m/v\d+/|/poster/v\d+/m\d+/"#, options: [.regularExpression, .caseInsensitive]) != nil { return .max }
        return nil
    }

    /// An original from before 2020 ("/H/v…", "/M/v…"): his add-on leaves its poster without the mark
    /// (TMDB's often has the official one), so the French poster can show instead.
    static func isPlain(_ item: MetaPreview) -> Bool {
        (item.poster ?? "").range(of: #"/[HM]/v\d+/"#, options: .regularExpression) != nil
    }
}

struct OrbitHBOPage: View {
    let route: FolderRoute
    let push: (TitleRoute) -> Void

    static func handles(_ route: FolderRoute) -> Bool {
        let t = route.folderTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        return t.contains("hbo") || t == "max"
    }

    @StateObject private var model: FolderDetailViewModel
    @StateObject private var extras = OrbitPlatformExtrasModel()
    @StateObject private var originals = OrbitHBOOriginalsModel()
    @StateObject private var trailer = OrbitNativeTrailerHost()
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.orbitPushStudio) private var pushStudio
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true
    /// A title was opened over the page: no trailer starts again behind it (Steven: Prime's kept
    /// playing, its sound under the title's page).
    @State private var covered = false

    /// nil: Accueil; "movie"; "series".
    @State private var typeFilter: String? = nil
    /// 0: the carousel; then the rows.
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

    private struct Catalog {
        let id: String
        let heading: String
        let items: [MetaPreview]
        let top10: Bool
        let fresh: Bool
    }

    /// Steven: the TV app's "HBO" tab, HBO's own programmes only.
    private var onHBO: Bool { typeFilter == "hbo" }

    /// Built once per change of what they are made of (fluidity: every press rebuilt them).
    @State private var catalogsMemo = OrbitRowsMemo<[Catalog]>()

    private var catalogs: [Catalog] {
        catalogsMemo.get(OrbitRowsKey(rows: model.stripRows, filter: typeFilter, variant: onHBO ? "hbo" : "")) { buildCatalogs() }
    }

    private func buildCatalogs() -> [Catalog] {
        let source = CollectionTypeFilter.rows(model.stripRows, filter: onHBO ? nil : typeFilter)
        let hasOriginals = source.contains { Self.isOriginalsCatalog($0.heading) }
        return source.compactMap { row in
            guard row.status == .loaded, let items = row.section?.items, !items.isEmpty else { return nil }
            var seen = Set<String>()
            var unique = items.filter { seen.insert("\($0.type):\($0.id)").inserted }
            let heading = row.heading.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let top10 = heading.contains("top 10") || heading.contains("top10")
            var fresh = heading.contains("nouveau") || heading.contains("nouvelle")
            var title = row.heading
            if onHBO {
                // HBO: no Top 10 (its ranks are everyone's), only the originals (HBO and HBO Max:
                // Steven, Paolo is an HBO Max Original).
                guard !top10 else { return nil }
                if Self.isOriginalsCatalog(row.heading) {
                    // Steven (the Nouveautés looked empty: 4 originals among the 20 newest titles):
                    // the originals catalogs, newest first, are this tab's Nouveautés.
                    let series = unique.first.map { $0.type != "movie" } ?? heading.contains("serie")
                    title = series ? String(localized: "Nouvelles séries") : String(localized: "Nouveaux films")
                    fresh = true
                } else if fresh, hasOriginals {
                    return nil
                }
                unique = unique.filter { OrbitHBOOwn.of($0) != nil }
                guard unique.count >= 3 else { return nil }
            }
            return Catalog(id: row.id, heading: title, items: unique, top10: top10, fresh: fresh)
        }
    }

    /// His "Séries originales HBO" / "Films originaux HBO".
    private static func isOriginalsCatalog(_ heading: String) -> Bool {
        heading.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains("origina")
    }

    private static func alternate<T>(_ a: [T], _ b: [T]) -> [T] {
        var out: [T] = []
        for i in 0..<max(a.count, b.count) {
            if i < a.count { out.append(a[i]) }
            if i < b.count { out.append(b[i]) }
        }
        return out
    }

    /// His Nouveautés, HBO's own, his Top 10, then the genres (TMDB).
    private var rows: [OrbitHBORow] {
        let extraRows: [OrbitPlatformExtrasModel.Extra] = switch typeFilter {
        case "movie"?: extras.movieRows
        case "series"?: extras.seriesRows
        default: Self.alternate(extras.movieRows, extras.seriesRows)
        }
        let all = catalogs
        var out: [OrbitHBORow] = []
        if onHBO {
            // Steven (rows of 4 titles): TMDB's own lists of the originals, full, when they arrived.
            if !originals.rows.isEmpty {
                return originals.rows.map { OrbitHBORow(id: $0.id, title: $0.title, items: $0.items, top10: false) }
            }
            return all.map { OrbitHBORow(id: "hbo-\($0.id)", title: $0.heading, items: $0.items, top10: false) }
        }
        for c in all where c.fresh {
            out.append(OrbitHBORow(id: c.id, title: c.heading, items: c.items, top10: false))
        }
        // Steven: "À la une sur HBO" repeated the Nouveautés: only HBO's own not already above.
        var seen = Set(out.flatMap { $0.items.map(Self.identity) })
        // Not from the Top 10 (Steven: its ranked images showed in this row).
        let own = all.filter { !$0.top10 }.flatMap(\.items).filter { OrbitHBOOwn.of($0) != nil && seen.insert(Self.identity($0)).inserted }
        if own.count >= 4 {
            out.append(OrbitHBORow(id: "hbo-originals-\(typeFilter ?? "all")",
                                   title: String(localized: "À la une sur HBO"), items: Array(own.prefix(20)), top10: false))
        }
        for c in all where c.top10 {
            let isSeries = c.heading.lowercased().contains("série") || c.items.first.map { $0.type != "movie" } == true
            out.append(OrbitHBORow(id: c.id,
                                   title: isSeries ? String(localized: "Top 10 des séries aujourd'hui")
                                                   : String(localized: "Top 10 des films aujourd'hui"),
                                   items: Array(c.items.prefix(10)), top10: true))
        }
        // HBO Max's own rows (Steven's video): "Universo Max", then "Sello HBO" (HBO's own, large).
        if typeFilter == nil {
            out.append(OrbitHBORow(id: "hbo-universe", title: String(localized: "Univers HBO Max"), items: [], top10: false,
                                   universe: true))
            var seal = Set<String>()
            let finest = all.filter { !$0.top10 }.flatMap(\.items)
                .filter { OrbitHBOOwn.of($0) == .hbo && $0.banner != nil && seal.insert(Self.identity($0)).inserted }
            if finest.count >= 3 {
                out.append(OrbitHBORow(id: "hbo-seal", title: String(localized: "Le label HBO : vos incontournables"),
                                       items: Array(finest.prefix(12)), top10: false, featured: true))
            }
        }
        if extraRows.isEmpty {
            for c in all where !c.fresh && !c.top10 {
                out.append(OrbitHBORow(id: c.id, title: c.heading, items: c.items, top10: false))
            }
        }
        var shown = Set(out.flatMap { $0.items.map(Self.identity) })
        var merged: [String: Int] = [:]
        for extra in extraRows {
            let fresh = extra.items.filter { !shown.contains(Self.identity($0)) }
            guard fresh.count >= 8 else { continue }
            let kept = Array(fresh.prefix(24))
            kept.forEach { shown.insert(Self.identity($0)) }
            if let i = merged[extra.title] {
                // Accueil: one row per genre, its films and series in turn.
                let row = out[i]
                out[i] = OrbitHBORow(id: row.id, title: row.title, items: Self.alternate(row.items, kept), top10: false, wide: true)
            } else {
                merged[extra.title] = out.count
                out.append(OrbitHBORow(id: extra.id, title: extra.title, items: kept, top10: false, wide: true))
            }
        }
        return out
    }

    private static func identity(_ item: MetaPreview) -> String {
        let year: String = item.releaseInfo.map { String($0.prefix(4)) } ?? ""
        return item.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) + "|" + year
    }

    private var freshIdentities: Set<String> {
        Set(catalogs.filter(\.fresh).flatMap { $0.items.map(Self.identity) })
    }

    private var freshRowIDs: Set<String> { Set(catalogs.filter(\.fresh).map(\.id)) }

    private func isNew(_ item: MetaPreview) -> Bool { freshIdentities.contains(Self.identity(item)) }

    private var heroItems: [MetaPreview] {
        let fresh = onHBO && !originals.rows.isEmpty
            ? originals.rows.filter { $0.id.hasPrefix(OrbitHBOOriginalsModel.newPrefix) }.map(\.items)
            : catalogs.filter(\.fresh).map(\.items)
        let items = fresh.count >= 2 ? Self.alternate(fresh[0], fresh[1]) : (fresh.first ?? catalogs.first?.items ?? [])
        // Steven (the HBO tab showed only documentaries): fiction first, documentaries after.
        let withArt = items.filter { $0.banner != nil }
        let isDoc: (MetaPreview) -> Bool = { item in item.genres.contains { $0.hasPrefix("Documentaire") } }
        return Array((withArt.filter { !isDoc($0) } + withArt.filter(isDoc)).prefix(6))
    }

    private var heroItem: MetaPreview? {
        let items = heroItems
        return items.isEmpty ? nil : items[min(heroIndex, items.count - 1)]
    }

    private var sectionCount: Int { 1 + rows.count }

    private func rowIndex(of section: Int) -> Int? { section >= 1 ? section - 1 : nil }

    private func rowTops(_ rows: [OrbitHBORow]) -> [CGFloat] {
        var y = OrbitHBOLayout.rowsTopOnArrival
        return rows.map { row in defer { y += row.height }; return y }
    }

    /// None on the carousel; the first row at the top; then the row above half in view.
    private func scroll(_ rows: [OrbitHBORow]) -> CGFloat {
        guard let r = rowIndex(of: current), rows.indices.contains(r) else { return 0 }
        let L = OrbitHBOLayout.self
        let line = r == 0 ? L.firstRowLine : L.firstRowLine + rows[r - 1].height * L.aboveRowShows
        return rowTops(rows)[r] - line
    }

    private func lead(of row: OrbitHBORow) -> Int {
        min(leads[row.id] ?? 0, max(0, row.items.count - 1))
    }

    private var focusedItem: MetaPreview? {
        guard let r = rowIndex(of: current) else { return heroItem }
        let rows = rows
        guard rows.indices.contains(r) else { return heroItem }
        let row = rows[r]
        return row.items.indices.contains(lead(of: row)) ? row.items[lead(of: row)] : nil
    }

    // MARK: Body

    var body: some View {
        let rows = rows
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        let offset = scroll(rows)
        let onArrival = current == 0

        ZStack(alignment: .topLeading) {
            OrbitHBOLayout.background
            // HBO Max's glow, top left.
            RadialGradient(colors: [OrbitHBOLayout.blue.opacity(0.22), .clear], center: .topLeading,
                           startRadius: 0, endRadius: 1300)
                .frame(width: W, height: H)

            if let hero = heroItem {
                OrbitHBOHero(item: hero, meta: metaStore.meta(for: hero), isNew: isNew(hero),
                             buttonLit: pageFocused && onArrival,
                             count: heroItems.count, index: min(heroIndex, max(0, heroItems.count - 1)),
                             trailerURL: onArrival ? trailerURL(for: hero) : nil,
                             onTrailerFailure: { trailer.playbackFailed($0) },
                             onTrailerEnded: {
                                 trailer.playbackFinished()
                                 advanceHero()
                             })
                    // Steven (device: back to the top, the art came down from above): it stays in
                    // place and fades; only the rows move.
                    .opacity(onArrival ? 1 : 0)
            }

                            nativeSections(rows)
                    // Steven: Films / Séries came up on the Top 10 — each filter its own page, from its top.
                    .id(typeFilter ?? "all")
                    .disabled(search != nil)
            

            // Under the bar: the night blue, so the row above fades out under it.
            LinearGradient(colors: [OrbitHBOLayout.background, OrbitHBOLayout.background.opacity(0.85),
                                    OrbitHBOLayout.background.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: W, height: 130)
                .opacity(onArrival ? 0 : 1)
                .allowsHitTesting(false)

            if rows.isEmpty, model.isLoading {
                ProgressView().frame(width: W, height: H)
            }


            CollectionFilterBar(filter: $typeFilter, onSearch: openSearch, showsAll: true, showsHBO: true, centred: true)
                .disabled(search != nil || (pageFocused && current > 0))
                .opacity(search != nil ? 0 : 1)

            OrbitPlatformIntro(title: model.folderTitle, logoUrl: model.titleLogoUrl ?? route.titleLogoUrl,
                               brand: OrbitHBOLayout.blue)

            if let search {
                OrbitPlatformSearchLayer(model: search, platform: model.folderTitle,
                                         onOpen: { push(TitleRoute(preview: $0, platform: detailPlatform($0))) },
                                         onClose: closeSearch)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .clipped()
        .background(OrbitHBOLayout.background)
        .ignoresSafeArea()
        .background { ViewerInputClockInstaller().frame(width: 0, height: 0) }
        .animation(reduceMotion ? nil : OrbitHBOLayout.vertical, value: offset)
        // Steven (device, Apple TV: the first row's title ran over the carousel's poster while it
        // faded): leaving, the carousel is gone before the rows reach it; coming back, it fades in
        // once they have moved off it.
        .animation(onArrival ? .easeInOut(duration: 0.3).delay(0.14) : .easeOut(duration: 0.14), value: onArrival)
        .onAppear {
            covered = false
            tabBarVisibility.pushImmersive()
            OrbitHomeButtonHost.shared.enter(.ownBar)
            model.buildsStripState = true
            model.start()
            extras.load(title: model.folderTitle)
            originals.load()
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
        .onChange(of: heroItems.map(\.id)) { _, _ in refreshAfterMove() }
        .onChange(of: typeFilter) { _, _ in
            current = 0
            heroIndex = 0
            leads.reset()
            refreshAfterMove()
        }
    }

    /// The native page: the sections (an invisible stop for the hero, whose art stays behind, then
    /// the rows drawn as before) as real buttons the system moves.
    private func nativeSections(_ rows: [OrbitHBORow]) -> some View {
        OrbitNativeSections(
            count: 1 + rows.count, hasHero: true,
            height: { s in s == 0 ? OrbitHBOLayout.rowsTopOnArrival - OrbitHBOLayout.firstRowLine : (rows.indices.contains(s - 1) ? rows[s - 1].height : 0) },
            topLine: nativeLine(rows), current: current, hidesAbove: false,
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
            focusRow: { s in if rows.indices.contains(s - 1) { leads.box(rows[s - 1].id).focusRequest &+= 1 } },
            line: nativeRowLine(rows)
        ) { s, focused in
            if s == 0 {
                Color.clear
            } else if rows.indices.contains(s - 1) {
                let row = rows[s - 1]
                OrbitHBORowView(row: row, box: leads.box(row.id), isCurrent: s == current,
                                focused: focused,
                                news: freshRowIDs.contains(row.id) || row.id.hasPrefix(OrbitHBOOriginalsModel.newPrefix) ? [] : Set(row.items.filter(isNew).map(\.id)),
                                metaStore: metaStore,
                                onEnter: { nativeEnter(s) }, onLeave: nativeLeave, onSelect: select,
                                onLeadChange: { refreshAfterMove() })
            }
        }
    }

    /// Each section's line, as the drawn page had it: the hero and the first row high under the
    /// bar, the next rows lower, the row above half in view (Steven: the first Down left the top empty).
    private func nativeRowLine(_ rows: [OrbitHBORow]) -> (Int) -> CGFloat {
        { s in
            let L = OrbitHBOLayout.self
            guard s >= 2, rows.indices.contains(s - 2) else { return L.firstRowLine }
            return L.firstRowLine + rows[s - 2].height * L.aboveRowShows
        }
    }

    /// The line a focused row rests on (the row above half in view, its usual height).
    private func nativeLine(_ rows: [OrbitHBORow]) -> CGFloat {
        let L = OrbitHBOLayout.self
        let average = rows.isEmpty ? 0 : rows.map(\.height).reduce(0, +) / CGFloat(rows.count)
        return L.firstRowLine + average * L.aboveRowShows
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
            current += 1
        case .up:
            guard current > 0 else { return }
            current -= 1
        case .left, .right:
            let step = direction == .right ? 1 : -1
            if current == 0 {
                let n = heroItems.count
                guard n > 1 else { return }
                withAnimation(.easeInOut(duration: 0.4)) { heroIndex = (heroIndex + step + n) % n }
            } else if let r = rowIndex(of: current), rows.indices.contains(r) {
                let row = rows[r]
                let next = lead(of: row) + step
                guard row.items.indices.contains(next) else { return }
                withAnimation(reduceMotion ? nil : OrbitHBOLayout.horizontal) { leads[row.id] = next }
            }
        @unknown default:
            return
        }
        refreshAfterMove()
    }

    /// The detail page's HBO Max touch.
    private func detailPlatform(_ item: MetaPreview) -> OrbitDetailPlatform {
        let own: OrbitDetailOwn? = switch OrbitHBOOwn.made(metaStore.meta(for: item)) {
        case .hbo?: .hbo
        case .max?: .hboMax
        case nil: nil
        }
        return OrbitDetailPlatform(theme: .hbo, own: own, logoUrl: model.titleLogoUrl ?? route.titleLogoUrl)
    }

    private func select() {
        if let r = rowIndex(of: current), rows.indices.contains(r), rows[r].universe {
            let brands = OrbitHBOBrand.all
            let brand = brands[min(max(0, leads[rows[r].id] ?? 0), brands.count - 1)]
            guard let pushStudio else { return }
            covered = true
            trailer.reset(abortStages: true)
            // As Disney+'s brands (Steven): no opening going in, nor HBO Max's coming back.
            OrbitStudioIntro.skipNext = true
            OrbitNavClock.titleOpenedAt = ProcessInfo.processInfo.systemUptime
            pushStudio(brand.route)
            return
        }
        covered = true
        trailer.reset(abortStages: true)
        if let focusedItem { push(TitleRoute(preview: focusedItem, platform: detailPlatform(focusedItem))) }
    }

    private func exitAction() -> (() -> Void)? {
        guard current > 0 else { return nil }
        return {
            current = 0
            refreshAfterMove()
        }
    }

    private func advanceHero() {
        let n = heroItems.count
        guard n > 1, current == 0 else { return }
        withAnimation(.easeInOut(duration: 0.6)) { heroIndex = (heroIndex + 1) % n }
        motion.stamp()
        refreshAfterMove()
    }

    private func startHeroClock() {
        heroClock?.cancel()
        heroClock = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard current == 0, search == nil, trailer.playingURL == nil,
                      motion.secondsSinceMotion > 14 else { continue }
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

    private func refreshAfterMove() {
        let rows = rows
        motion.stamp()
        var metaItems: [MetaPreview] = heroItems
        let r = rowIndex(of: current) ?? 0
        for i in max(0, r - 1)...max(r, min(rows.count - 1, r + 2)) where rows.indices.contains(i) {
            let row = rows[i]
            let lead = lead(of: row)
            metaItems += row.items.indices.filter { $0 >= lead - 1 && $0 <= lead + 8 }.map { row.items[$0] }
        }
        OrbitMetaStore.shared.request(metaItems)

        trailer.reset()
        trailerKey = nil
        // The carousel's trailer plays whether or not it has the focus (the bar can).
        guard trailersOn, !covered, search == nil, current == 0, UIAccessibility.isVideoAutoplayEnabled,
              let item = heroItem else { return }
        trailer.prefersReducedMotion = reduceMotion
        trailer.restSource = .custom(motion)
        trailerKey = "\(item.type):\(item.id)"
        trailer.focusChanged(true, item: item)
    }
}

// MARK: - Pieces

/// HBO Max's mark at a poster's foot, centred, on a soft shade (its top left is the "NOUVEAU" tag's).
private struct OrbitHBOPosterMark: View {
    let own: OrbitHBOOwn
    let width: CGFloat
    /// Steven: where the poster leaves room — its top (its title at its foot), else its foot.
    var atTop = true
    /// The "NOUVEAU" tag sits at the top left: the mark under it.
    var belowTag = false

    var body: some View {
        ZStack(alignment: atTop ? .top : .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: atTop ? .bottom : .top,
                           endPoint: atTop ? .top : .bottom)
                .frame(height: atTop ? 70 : 60)
            Image(own == .hbo ? "HBOOriginalLogo" : "MaxOriginalLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.white)
                .frame(width: width * (own == .hbo ? 0.5 : 0.36), height: own == .hbo ? 13 : 22)
                .padding(atTop ? .top : .bottom, atTop && belowTag ? 38 : 12)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: atTop ? .top : .bottom)
        .allowsHitTesting(false)
    }
}

/// "HBO ORIGINAL" / "HBO MAX ORIGINAL" above a title's logo.
private struct OrbitHBOMark: View {
    let own: OrbitHBOOwn
    var size: CGFloat = 20

    var body: some View {
        // Steven's own files: "HBO ORIGINAL", and Max's own "max ORIGINAL".
        Image(own == .hbo ? "HBOOriginalLogo" : "MaxOriginalLogo")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.white)
            .frame(height: own == .hbo ? size * 1.1 : size * 1.9)
            .shadow(color: .black.opacity(0.5), radius: 4)
    }
}

/// HBO Max's words: a series' new season or episodes first, "BIENTÔT" for what is announced, else
/// "NOUVEAU" for what came out lately.
private func orbitHBOLabel(_ item: MetaPreview, _ meta: OrbitMeta?, isNew: Bool) -> String? {
    switch OrbitTitleNews.of(item, meta) {
    case .newSeason: return String(localized: "NOUVELLE SAISON")
    case .newEpisodes: return String(localized: "NOUVEL ÉPISODE")
    case .soon: return String(localized: "BIENTÔT")
    case nil: return isNew ? String(localized: "NOUVEAU") : nil
    }
}

/// The blue "NOUVEAU" tag.
private struct OrbitHBONewTag: View {
    var text: String = String(localized: "NOUVEAU")
    var size: CGFloat = 15
    /// On the posters and tiles (Steven, the app's video): white, the text dark; blue on the hero only.
    var white = false

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy))
            .kerning(size * 0.06)
            .foregroundStyle(white ? Color.black : Color.white)
            .padding(.horizontal, size * 0.45)
            .padding(.vertical, size * 0.18)
            .background(RoundedRectangle(cornerRadius: 3).fill(white ? Color.white : OrbitHBOLayout.blue))
    }
}

/// The carousel: the art full screen (its trailer on a rest), the details on the left, the button,
/// the dots in the middle.
private struct OrbitHBOHero: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let isNew: Bool
    let buttonLit: Bool
    let count: Int
    let index: Int
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let L = OrbitHBOLayout.self
        let size = CGSize(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
        let info = OrbitInfo.make(item, meta: meta)
        let own = OrbitHBOOwn.made(meta)
        ZStack(alignment: .topLeading) {
            ZStack {
                OrbitSwapImage(url: item.banner ?? meta?.backdrop, fallback: nil, size: size)
                if let trailerURL {
                    TrailerHeroPlayer(urlString: trailerURL, onFailure: onTrailerFailure,
                                      zoomKey: TrailerResolutionCache.key(type: item.type, id: item.id),
                                      loops: false, onPlaybackEnded: onTrailerEnded, cornerRadius: 0)
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity.animation(.easeOut(duration: 0.6)))
                }
                LinearGradient(stops: [
                    .init(color: L.background.opacity(0.92), location: 0),
                    .init(color: L.background.opacity(0.55), location: 0.36),
                    .init(color: .clear, location: 0.62),
                ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [
                    .init(color: L.background.opacity(0.55), location: 0),
                    .init(color: .clear, location: 0.18),
                    .init(color: .clear, location: 0.62),
                    .init(color: L.background.opacity(0.95), location: 0.92),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            VStack(alignment: .leading, spacing: 0) {
                if let own {
                    OrbitHBOMark(own: own, size: 22)
                        .padding(.bottom, 12)
                }
                OrbitTitleMark(name: item.name, logo: info.logo, maxSize: L.logoSize, textSize: 66,
                               fallbackLogo: info.logoFallback, hugsLogo: true)
                    .frame(width: L.logoSize.width, alignment: .leading)
                HStack(spacing: 12) {
                    if let text = orbitHBOLabel(item, meta, isNew: isNew) { OrbitHBONewTag(text: text) }
                    Text(info.parts.joined(separator: "  ·  "))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(.top, 22)
                Text(info.synopsis)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineSpacing(4)
                    .lineLimit(3)
                    .frame(width: L.synopsisWidth, alignment: .topLeading)
                    .padding(.top, 14)
                // HBO Max's own button (Steven's video): ⓘ then "Voir la série" — the title's page.
                HStack(spacing: 10) {
                    Image(systemName: "info.circle").font(.system(size: 22, weight: .semibold))
                    Text(item.type == "movie" ? String(localized: "Voir le film") : String(localized: "Voir la série"))
                }
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 26)
                    .frame(height: 54)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(buttonLit ? 1 : 0.82)))
                    .scaleEffect(buttonLit ? 1.06 : 1, anchor: .leading)
                    .animation(.easeOut(duration: 0.18), value: buttonLit)
                    .padding(.top, 26)
            }
            .frame(width: L.synopsisWidth, alignment: .topLeading)
            .offset(x: L.margin, y: L.infoTop)
            .id("\(item.type):\(item.id)-info")
            .transition(.opacity.animation(.easeInOut(duration: 0.3)))

            if count > 1 {
                HStack(spacing: 10) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(i == index ? 1 : 0.35))
                            .frame(width: i == index ? 22 : 8, height: 8)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: index)
                .frame(width: size.width)
                .offset(y: L.rowsTopOnArrival - 60)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// A row: its heading, then its titles from the focused one (at the margin).
private struct OrbitHBORowView: View {
    let row: OrbitHBORow
    @ObservedObject var box: OrbitLeadBox
    let isCurrent: Bool
    let focused: Bool
    let news: Set<String>
    @ObservedObject var metaStore: OrbitMetaStore
    let onEnter: () -> Void
    let onLeave: () -> Void
    let onSelect: () -> Void
    let onLeadChange: () -> Void

    var body: some View {
        let L = OrbitHBOLayout.self
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if row.top10 {
                    OrbitHBOTop10Heading(series: row.title.lowercased().contains("série"))
                } else {
                    Text(row.title)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(Color.white.opacity(isCurrent ? 1 : 0.75))
                        .lineLimit(1)
                }
            }
            .frame(height: row.headingHeight, alignment: .topLeading)
            .padding(.leading, L.margin)
            OrbitNativeTileStrip(count: row.count, spacing: L.gap, height: row.cardHeight,
                                 lastWidth: row.slot(max(0, row.count - 1)) - L.gap, box: box, alignment: .top,
                                 onEnter: onEnter, onLeave: onLeave, onSelect: onSelect,
                                 onLeadChange: { _ in onLeadChange() }) { index, lit in
                if row.universe {
                    OrbitHBOBrandTile(brand: OrbitHBOBrand.all[index], focused: lit)
                } else if row.featured {
                    let item = row.items[index]
                    OrbitHBOFeaturedCard(item: item, meta: metaStore.meta(for: item), focused: lit)
                } else if row.top10 {
                    let item = row.items[index]
                    OrbitHBOTop10Card(item: item, meta: metaStore.meta(for: item), rank: index + 1, focused: lit)
                } else if row.wide {
                    let item = row.items[index]
                    OrbitHBOTile(item: item, meta: metaStore.meta(for: item), isNew: news.contains(item.id), focused: lit)
                } else {
                    let item = row.items[index]
                    OrbitHBOPoster(item: item, meta: metaStore.meta(for: item), isNew: news.contains(item.id), focused: lit)
                }
            }
            .frame(width: OrbitHomeLayout.screenWidth, height: row.cardHeight, alignment: .topLeading)
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
        .opacity(isCurrent ? 1 : 0.85)
    }
}

/// HBO Max's Top 10 heading (2026, Steven's screenshot): "TOP 10" in dark glass with a silver rim,
/// "DES SÉRIES" / "DU JOUR" beside it.
private struct OrbitHBOTop10Heading: View {
    let series: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            // (Steven: TOP 10 read faint on the dark page — a brighter rim, lighter glass.)
            OrbitHBOGlassText(text: "TOP 10", size: 80, filled: false, bright: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(series ? String(localized: "DES SÉRIES") : String(localized: "DES FILMS"))
                Text(String(localized: "DU JOUR"))
            }
            .font(.system(size: 25, weight: .medium))
            .kerning(1.5)
            .foregroundStyle(Color.white.opacity(0.92))
        }
    }
}

/// HBO Max's glass lettering: a thin silver rim around dark glass; filled (the focused rank), light
/// silver all through.
private struct OrbitHBOGlassText: View {
    let text: String
    let size: CGFloat
    let filled: Bool
    var bright = false

    var body: some View {
        let font = Font.system(size: size, weight: .medium)
        let w = max(1.5, size * (bright ? 0.03 : 0.022))
        // (Steven: the 1 and the 0 of 10 touching.)
        let tight: CGFloat = text == "10" ? -size * 0.09 : 0
        let offsets: [CGSize] = (0..<16).map { i in
            let a = Double(i) / 16 * 2 * .pi
            return CGSize(width: cos(a) * w, height: sin(a) * w)
        }
        let rim = LinearGradient(colors: [Color(white: 0.97), Color(white: 0.55), Color(white: 0.3), Color(white: 0.85)],
                                 startPoint: .bottomLeading, endPoint: .topTrailing)
        let glass = LinearGradient(colors: bright ? [Color(red: 0.03, green: 0.04, blue: 0.06), Color(red: 0.15, green: 0.17, blue: 0.24)]
                                          : [Color(red: 0.03, green: 0.04, blue: 0.06), Color(red: 0.15, green: 0.17, blue: 0.24)],
                                   startPoint: .top, endPoint: .bottom)
        let lit = LinearGradient(colors: [Color.white, Color(white: 0.78)], startPoint: .top, endPoint: .bottom)
        ZStack {
            ForEach(offsets.indices, id: \.self) { i in
                Text(text).font(font).kerning(tight).foregroundStyle(rim).offset(offsets[i])
            }
            // Steven (device: the rank arrived offset, then filled): both fills drawn, the lit one
            // faded in on the move's own curve (a style swap cannot animate; it jumped afterwards).
            Text(text).font(font).kerning(tight).foregroundStyle(glass)
            Text(text).font(font).kerning(tight).foregroundStyle(lit).opacity(filled ? 1 : 0)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
        .fixedSize()
    }
}

/// A Top 10 title: its rank drawn by Orbit on the left (filled when focused, as in the TV app), the
/// poster over its right part (TMDB's, in French when it has one; never his ranked image).
private struct OrbitHBOTop10Card: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let rank: Int
    let focused: Bool

    var body: some View {
        let L = OrbitHBOLayout.self
        let rankW = rank == 10 ? L.rankWidthTen : L.rankWidth
        let poster: String? = meta?.titledPoster ?? meta?.localPoster ?? meta?.cleanPoster
        ZStack(alignment: .bottomLeading) {
            OrbitHBOGlassText(text: String(rank), size: L.poster.height * 0.52, filled: focused)
                .frame(width: rankW, alignment: .trailing)
                // (Steven: the 1, narrow, almost all behind its poster — a little out, still tucked.)
                .offset(x: rank == 1 ? -10 : 0, y: L.poster.height * 0.1)
            ZStack {
                Color(red: 0.08, green: 0.10, blue: 0.20)
                if let poster {
                    OrbitImage(url: poster, fallback: nil, mode: .fill, size: L.poster)
                }
                // (Steven: the official posters print HBO's mark already — no Orbit mark on them.)
            }
            .frame(width: L.poster.width, height: L.poster.height)
            .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
            .modifier(OrbitHBOFocus(focused: focused))
            .offset(x: rankW - L.rankUnderPoster)
        }
        .frame(width: rankW - L.rankUnderPoster + L.poster.width, height: L.poster.height, alignment: .bottomLeading)
    }
}

/// "Universo Max"'s brands: HBO Max's own circles, each its studio page (TMDB's network or company).
struct OrbitHBOBrand {
    let name: String
    let ids: String
    let isNetwork: Bool
    let colours: [Color]
    /// Steven's own files (HBO, HBO Max), drawn white; else TMDB's logo.
    var asset: String? = nil
    /// Its name instead of a logo (Warner Bros.: TMDB's shield came out a white blot).
    var text: String? = nil

    var route: OrbitStudioRoute {
        OrbitStudioRoute(name: name, companies: ids, isNetwork: isNetwork, logo: OrbitHBOBrandLogos.shared.logos[name],
                         collectionId: nil, folderId: nil)
    }

    static let all: [OrbitHBOBrand] = [
        .init(name: "HBO", ids: "49", isNetwork: true,
              colours: [Color(white: 0.28), Color(white: 0.10)], asset: "HBOMark"),
        .init(name: "Max Originals", ids: "3186", isNetwork: true,
              colours: [Color(white: 0.22), Color(white: 0.06)], asset: "MaxOriginalLogo"),
        .init(name: "Warner Bros.", ids: "174", isNetwork: false,
              colours: [Color(red: 0.10, green: 0.42, blue: 0.95), Color(red: 0.03, green: 0.20, blue: 0.60)],
              text: "WB"),
        .init(name: "DC", ids: "128064|9993", isNetwork: false,
              colours: [Color(red: 0.08, green: 0.38, blue: 0.90), Color(red: 0.02, green: 0.14, blue: 0.45)]),
        .init(name: "Discovery", ids: "64", isNetwork: true,
              colours: [Color(red: 0.10, green: 0.45, blue: 0.95), Color(red: 0.02, green: 0.20, blue: 0.55)]),
        .init(name: "Cartoon Network", ids: "56", isNetwork: true,
              colours: [Color(white: 0.20), Color(white: 0.02)]),
        .init(name: "Adult Swim", ids: "80", isNetwork: true,
              colours: [Color(red: 0.12, green: 0.30, blue: 0.55), Color(red: 0.03, green: 0.08, blue: 0.20)]),
    ]
}

/// The brands' logos (TMDB's), fetched once.
@MainActor
final class OrbitHBOBrandLogos: ObservableObject {
    static let shared = OrbitHBOBrandLogos()
    @Published private(set) var logos: [String: String] = [:]
    private var started = false

    nonisolated private struct Entity: Decodable { let logo_path: String? }

    func load() {
        guard !started else { return }
        started = true
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        guard !key.isEmpty else { return }
        Task { [weak self] in
            for brand in OrbitHBOBrand.all {
                let first = brand.ids.split(separator: "|").first.map(String.init) ?? brand.ids
                guard let url = URL(string: "https://api.themoviedb.org/3/\(brand.isNetwork ? "network" : "company")/\(first)?api_key=\(key)"),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let entity = try? JSONDecoder().decode(Entity.self, from: data),
                      let path = entity.logo_path else { continue }
                self?.logos[brand.name] = "https://image.tmdb.org/t/p/w500\(path)"
            }
        }
    }
}

/// A brand's circle: its colour, its logo in white (its name while none).
private struct OrbitHBOBrandTile: View {
    let brand: OrbitHBOBrand
    let focused: Bool
    @ObservedObject private var logos = OrbitHBOBrandLogos.shared

    var body: some View {
        let d = OrbitHBOLayout.universe
        let box = CGSize(width: d * 0.62, height: d * 0.36)
        ZStack {
            Circle().fill(RadialGradient(colors: brand.colours, center: .topLeading, startRadius: 0, endRadius: d))
            if let asset = brand.asset {
                Image(asset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.white)
                    .frame(width: box.width, height: box.height)
            } else if brand.text != nil {
                // Steven: Warner Bros.' own shield — white, its WB cut out in the circle's blue.
                ZStack {
                    OrbitWBShield().fill(Color.white)
                    Text("WB")
                        .font(.system(size: d * 0.14, weight: .black, design: .serif))
                        .kerning(-d * 0.006)
                        .foregroundStyle(brand.colours[0])
                        .offset(y: -d * 0.02)
                }
                .frame(width: d * 0.4, height: d * 0.46)
            } else if let logo = logos.logos[brand.name] {
                Color.white
                    .frame(width: box.width, height: box.height)
                    .mask {
                        CachedAsyncImage(string: logo, contentMode: .fit,
                                         decodeSize: .points(width: box.width, height: box.height),
                                         loading: { Color.clear }, failure: { Color.clear })
                            .frame(width: box.width, height: box.height)
                    }
            } else {
                Text(brand.name)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .frame(width: d * 0.75)
            }
        }
        .frame(width: d, height: d)
        .overlay { Circle().strokeBorder(Color.white.opacity(focused ? 0.95 : 0), lineWidth: 4) }
        .shadow(color: .black.opacity(focused ? 0.5 : 0.2), radius: focused ? 16 : 6, y: focused ? 8 : 3)
        .scaleEffect(focused ? OrbitHBOLayout.focusScale : 1)
        .animation(.easeOut(duration: 0.18), value: focused)
        .onAppear { logos.load() }
    }
}

/// Warner Bros.' shield: straight top with two curls inward at the corners, sides bowing in, a point at
/// the foot.
struct OrbitWBShield: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.minX + w * 0.5, y: r.minY + h * 0.06))
        // The top edge, dipping a little to its middle, to the right corner's curl.
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.9, y: r.minY),
                       control: CGPoint(x: r.minX + w * 0.72, y: r.minY + h * 0.07))
        p.addQuadCurve(to: CGPoint(x: r.minX + w, y: r.minY + h * 0.12),
                       control: CGPoint(x: r.minX + w * 0.98, y: r.minY))
        // The right side, bowing in, then out round to the point.
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.92, y: r.minY + h * 0.5),
                       control: CGPoint(x: r.minX + w * 0.86, y: r.minY + h * 0.3))
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.5, y: r.maxY),
                       control: CGPoint(x: r.minX + w * 1.0, y: r.minY + h * 0.82))
        // Mirrored.
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.08, y: r.minY + h * 0.5),
                       control: CGPoint(x: r.minX, y: r.minY + h * 0.82))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.12),
                       control: CGPoint(x: r.minX + w * 0.14, y: r.minY + h * 0.3))
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.1, y: r.minY),
                       control: CGPoint(x: r.minX + w * 0.02, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.5, y: r.minY + h * 0.06),
                       control: CGPoint(x: r.minX + w * 0.28, y: r.minY + h * 0.07))
        p.closeSubpath()
        return p
    }
}

/// "Sello HBO": a large landscape card of HBO's own — its art, "HBO ORIGINAL", its logo.
private struct OrbitHBOFeaturedCard: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let focused: Bool

    var body: some View {
        let L = OrbitHBOLayout.self
        let size = L.featured
        let info = OrbitInfo.make(item, meta: meta)
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.08, green: 0.10, blue: 0.20)
            OrbitImage(url: meta?.backdrop ?? item.banner, fallback: item.banner, size: size)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                OrbitHBOMark(own: OrbitHBOOwn.made(meta) ?? .hbo, size: 16)
                OrbitTitleMark(name: item.name, logo: info.logo, maxSize: CGSize(width: 340, height: 110), textSize: 36,
                               fallbackLogo: info.logoFallback, hugsLogo: true)
                    .frame(width: 340, alignment: .leading)
            }
            .padding(.leading, 24)
            .padding(.bottom, 22)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .modifier(OrbitHBOFocus(focused: focused))
    }
}

/// A wide tile (the genre rows): TMDB's backdrop, the French logo, the blue tag.
private struct OrbitHBOTile: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let isNew: Bool
    let focused: Bool

    var body: some View {
        let L = OrbitHBOLayout.self
        let size = L.tile
        let info = OrbitInfo.make(item, meta: meta)
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.08, green: 0.10, blue: 0.20)
            OrbitImage(url: meta?.backdrop ?? item.banner, fallback: item.banner, size: size)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            OrbitTitleMark(name: item.name, logo: info.logo,
                           maxSize: CGSize(width: size.width * 0.55, height: size.height * 0.4), textSize: 26,
                           fallbackLogo: info.logoFallback)
                .padding(.leading, 16)
                .padding(.bottom, 14)
            if let text = orbitHBOLabel(item, meta, isNew: isNew) {
                OrbitHBONewTag(text: text, size: 13, white: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .modifier(OrbitHBOFocus(focused: focused))
    }
}

/// A tall poster: HBO's own keep his add-on's poster (its "HBO Original" mark), the others TMDB's
/// French one when it has one; focused, a white frame and a little larger.
private struct OrbitHBOPoster: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let isNew: Bool
    let focused: Bool

    var body: some View {
        let L = OrbitHBOLayout.self
        let size = L.poster
        // His ranked Top 10 image ("/poster/v…") is never a poster here.
        let ranked = (item.poster ?? "").contains("/poster/v")
        // Steven: TMDB's poster (no platform mark printed on it), HBO's / Max's mark drawn by Orbit.
        let url: String? = meta?.localPoster ?? meta?.titledPoster ?? meta?.cleanPoster ?? (ranked ? nil : item.poster)

        ZStack(alignment: .topLeading) {
            Color(red: 0.08, green: 0.10, blue: 0.20)
            // (Steven's video: an empty frame at a row's end — no poster known yet: TMDB's, else his.)
            OrbitImage(url: url, fallback: ranked ? meta?.cleanPoster : item.rawPosterUrl,
                       mode: .fill, size: size, lastResort: meta?.backdrop ?? item.banner)
            // (Steven: the official posters print HBO's mark already — no Orbit mark on them; it
            // stays on the hero, the label row's cards and the title's page.)
            if let text = orbitHBOLabel(item, meta, isNew: isNew) {
                OrbitHBONewTag(text: text, size: 13, white: true)
                    .padding(8)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .modifier(OrbitHBOFocus(focused: focused))
    }
}

/// The TV app's focus: a white frame, a little larger, in place.
private struct OrbitHBOFocus: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: OrbitHBOLayout.radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(focused ? 0.95 : 0), lineWidth: 4)
            }
            .shadow(color: .black.opacity(focused ? 0.6 : 0.25), radius: focused ? 18 : 6, y: focused ? 10 : 4)
            .scaleEffect(focused ? OrbitHBOLayout.focusScale : 1)
            // (Steven, device: the focused tile rose before the others — its focus follows the move's own curve.)
    }
}

/// The HBO tab's rows, straight from TMDB (Steven: the add-on's first pages left 4 originals per row):
/// HBO's and HBO Max's networks for the series, HBO's companies for the films, on HBO Max in the
/// viewer's region; the newest first, then the most watched by genre.
@MainActor
final class OrbitHBOOriginalsModel: ObservableObject {
    nonisolated struct Row: Equatable {
        let id: String
        let title: String
        let items: [MetaPreview]
        static func == (a: Row, b: Row) -> Bool { a.id == b.id && a.items.map(\.id) == b.items.map(\.id) }
    }

    nonisolated static let newPrefix = "hbo-orig-new"
    /// HBO (49) and HBO Max (3186) on TMDB.
    nonisolated private static let networks = "49|3186"
    nonisolated private static let seriesGenres: [(Int, String)] = [
        (18, "Drame"), (35, "Comédie"), (80, "Crime"), (10765, "Science-Fiction & Fantastique"),
        (9648, "Mystère"), (99, "Documentaire"),
    ]
    /// A series genre's film counterpart (TMDB numbers them apart for science fiction).
    nonisolated private static let movieGenre: [Int: Int] = [18: 18, 35: 35, 80: 80, 10765: 878, 9648: 9648, 99: 99]
    nonisolated private static let genreNames: [Int: String] = [
        28: "Action", 12: "Aventure", 16: "Animation", 35: "Comédie", 80: "Crime", 99: "Documentaire",
        18: "Drame", 10751: "Familial", 14: "Fantastique", 36: "Histoire", 27: "Horreur", 10402: "Musique",
        9648: "Mystère", 10749: "Romance", 878: "Science-Fiction", 53: "Thriller", 10752: "Guerre", 37: "Western",
        10759: "Action & Aventure", 10764: "Téléréalité", 10765: "Science-Fiction & Fantastique", 10768: "Guerre & Politique",
    ]

    @Published private(set) var rows: [Row] = []
    private var started = false

    func load() {
        guard !started else { return }
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        guard !key.isEmpty else { return }
        started = true
        let language = TmdbSettingsRepository.shared.snapshot().language
        Task { [weak self] in
            let built = await Self.build(apiKey: key, language: language.isEmpty ? "fr-FR" : language)
            guard let self else { return }
            if built.isEmpty { self.started = false } else { self.rows = built }
        }
    }

    nonisolated private static func build(apiKey: String, language: String) async -> [Row] {
        let region = OrbitPlatformExtrasModel.region(language: language)
        let provider = 1899 // HBO Max on TMDB
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let base = "&api_key=\(apiKey)&language=\(language)&watch_region=\(region)&with_watch_providers=\(provider)"
            + "&with_watch_monetization_types=flatrate"
        let companies = await hboCompanies(apiKey: apiKey)
        var specs: [(id: String, title: String, tv: Bool, query: String)] = [
            ("\(newPrefix)-tv", String(localized: "Nouvelles séries"), true,
             "&with_networks=\(networks)&sort_by=first_air_date.desc&first_air_date.lte=\(today)"),
            ("\(newPrefix)-movie", String(localized: "Nouveaux films"), false,
             "&with_companies=\(companies)&sort_by=primary_release_date.desc&primary_release_date.lte=\(today)"),
            ("hbo-orig-popular-tv", String(localized: "Les séries incontournables"), true,
             "&with_networks=\(networks)&sort_by=popularity.desc"),
        ]
        // Steven: films and series together in a genre (the films' genre beside the series' one).
        for (genre, name) in seriesGenres {
            specs.append(("hbo-orig-genre-\(genre)", name, true,
                          "&with_networks=\(networks)&with_genres=\(genre)&sort_by=popularity.desc"))
            if let movieGenre = movieGenre[genre] {
                specs.append(("hbo-orig-genre-\(genre)-movie", name, false,
                              "&with_companies=\(companies)&with_genres=\(movieGenre)&sort_by=popularity.desc"))
            }
        }
        specs.append(("hbo-orig-popular-movie", String(localized: "Films HBO"), false,
                      "&with_companies=\(companies)&sort_by=popularity.desc"))
        let lists = await withTaskGroup(of: (Int, [MetaPreview]).self) { group in
            for (index, spec) in specs.enumerated() {
                group.addTask {
                    let address = "https://api.themoviedb.org/3/discover/\(spec.tv ? "tv" : "movie")?include_adult=false"
                        + base + spec.query
                    async let first = fetch(address + "&page=1", tv: spec.tv)
                    async let second = fetch(address + "&page=2", tv: spec.tv)
                    return (index, await first + second)
                }
            }
            var out: [Int: [MetaPreview]] = [:]
            for await (index, items) in group { out[index] = items }
            return out
        }
        // A title shows once, in its first row (the genres after the newest and the essentials); a
        // genre's films join its series, in turn.
        var shown = Set<String>()
        var out: [Row] = []
        var byTitle: [String: Int] = [:]
        for (index, spec) in specs.enumerated() {
            let fresh = (lists[index] ?? []).filter { !shown.contains("\($0.type):\($0.id)") }
            let isGenre = spec.id.hasPrefix("hbo-orig-genre-")
            if isGenre, let at = byTitle[spec.title] {
                let kept = Array(fresh.prefix(12))
                kept.forEach { shown.insert("\($0.type):\($0.id)") }
                let row = out[at]
                out[at] = Row(id: row.id, title: row.title, items: alternate(row.items, kept))
                continue
            }
            guard fresh.count >= (isGenre ? 3 : 5) else { continue }
            let kept = Array(fresh.prefix(isGenre ? 16 : 24))
            kept.forEach { shown.insert("\($0.type):\($0.id)") }
            if isGenre { byTitle[spec.title] = out.count }
            out.append(Row(id: spec.id, title: spec.title, items: kept))
        }
        return out.filter { $0.items.count >= 5 }
    }

    nonisolated private static func alternate(_ a: [MetaPreview], _ b: [MetaPreview]) -> [MetaPreview] {
        var out: [MetaPreview] = []
        for i in 0..<max(a.count, b.count) {
            if i < a.count { out.append(a[i]) }
            if i < b.count { out.append(b[i]) }
        }
        return out
    }

    /// HBO's production companies (HBO, HBO Films, HBO Documentary Films, HBO Max…), by name.
    nonisolated private static func hboCompanies(apiKey: String) async -> String {
        struct Found: Decodable { struct C: Decodable { let id: Int; let name: String? }; let results: [C]? }
        let fallback = "3268|7429"
        guard let url = URL(string: "https://api.themoviedb.org/3/search/company?api_key=\(apiKey)&query=HBO"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let found = try? JSONDecoder().decode(Found.self, from: data) else { return fallback }
        let ids = (found.results ?? []).filter { ($0.name ?? "").range(of: #"^HBO\b"#, options: [.regularExpression, .caseInsensitive]) != nil }
            .map { String($0.id) }
        return ids.isEmpty ? fallback : ids.joined(separator: "|")
    }

    nonisolated private struct Response: Decodable {
        nonisolated struct Result: Decodable {
            let id: Int
            let title: String?
            let name: String?
            let overview: String?
            let poster_path: String?
            let backdrop_path: String?
            let release_date: String?
            let first_air_date: String?
            let vote_average: Double?
            let genre_ids: [Int]?
        }
        let results: [Result]?
    }

    /// One discover page as previews, with their genres (the carousel keeps documentaries after).
    nonisolated private static func fetch(_ address: String, tv: Bool) async -> [MetaPreview] {
        guard let url = URL(string: address),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return (decoded.results ?? []).compactMap { r -> MetaPreview? in
            guard let name = r.title ?? r.name, !name.isEmpty, let poster = r.poster_path else { return nil }
            let date = r.release_date ?? r.first_air_date
            return MetaPreview(id: "tmdb:\(r.id)", type: tv ? "series" : "movie", name: name,
                               poster: "https://image.tmdb.org/t/p/w780\(poster)",
                               banner: r.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" },
                               logo: nil, posterShape: .poster,
                               description: r.overview ?? "", releaseInfo: date.map { String($0.prefix(4)) },
                               rawReleaseDate: date, popularity: nil, voteCount: nil,
                               imdbRating: r.vote_average.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil },
                               genres: (r.genre_ids ?? []).compactMap { genreNames[$0] }, rawPosterUrl: nil,
                               landscapePoster: nil, rawLandscapePosterUrl: nil, customPosterApplied: false)
        }
    }
}
