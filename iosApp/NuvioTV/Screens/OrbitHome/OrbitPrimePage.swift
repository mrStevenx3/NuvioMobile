import Combine
import SharedCore
import SwiftUI

// Orbit × Prime Video (Steven, 2026-10-25, pass 3: Prime's TV app, not its website). Orbit's DNA
// kept (one focusable canvas; the house and Search top left; the intro; trailers on a rest).
//
//  - Prime's blue-black. The top of the screen always shows a title: the new titles in turn on
//    arrival (its trailer on a rest), then the focused title once in the rows — its art on the right
//    fading to the left, "prime" above the logo on Amazon's own (today's mark, not "AMAZON
//    ORIGINAL"), the green "Série n° 2 en France" for a title of the Top 10, two lines of synopsis,
//    "✓ Inclus avec Prime" and the age.
//  - On arrival, the TV app's buttons (Lecture, +, i) and, under them, the "Tout · Films · Séries"
//    pills (they switch as the cursor moves along them).
//  - The rows below: 16:9 tiles (TMDB's backdrop, the French logo, "prime" on Amazon's own), the
//    focused one framed in white and a little larger, in place; Amazon's own titles in tall
//    posters; the Top 10 with Prime's wide grey ranks tucked under its tiles.

enum OrbitPrimeLayout {
    static let background = Color(red: 0.03, green: 0.05, blue: 0.09)
    static let green = Color(red: 0.16, green: 0.84, blue: 0.55)
    static let blue = Color(red: 0.10, green: 0.55, blue: 0.95)
    static let margin: CGFloat = OrbitHomeLayout.margin
    static let artHeight: CGFloat = 860
    static let infoTop: CGFloat = 170
    static let logoSize = CGSize(width: 560, height: 190)
    static let synopsisWidth: CGFloat = 800
    /// The first row on arrival.
    static let rowsTopOnArrival: CGFloat = 790
    /// Once in the rows: the current row's top (the title's details stay above it).
    static let rowLine: CGFloat = 580
    static let headingHeight: CGFloat = 50
    static let tile = CGSize(width: 340, height: 191)
    /// Steven: the Amazon Original posters are larger still on Prime's TV app.
    /// Measured on Prime's 2026 TV app: as tall as the opened card (16:9) beside them.
    static let poster = CGSize(width: 267, height: 400)
    static var openWidth: CGFloat { poster.height * 16 / 9 }
    /// His Top 10 images (16:9, the card on the right 76 %, the rank behind it), the card at a tile's size.
    static var top10Image: CGSize { CGSize(width: tile.width / 0.76, height: tile.width / 0.76 * 9 / 16) }
    /// The current row's top when it is the Amazon Original row (its posters need the room).
    static let originalsLine: CGFloat = 230
    static let gap: CGFloat = 22
    static let rowGap: CGFloat = 40
    static let radius: CGFloat = 10
    static let focusScale: CGFloat = 1.07
    static let horizontal = Animation.easeOut(duration: 0.24)
    static let vertical = Animation.easeInOut(duration: 0.38)
}

struct OrbitPrimeRow: Identifiable, Equatable {
    enum Kind: Equatable { case tiles, originals, top10 }

    let id: String
    let title: String
    let items: [MetaPreview]
    let kind: Kind

    static func == (a: OrbitPrimeRow, b: OrbitPrimeRow) -> Bool {
        a.id == b.id && a.kind == b.kind && a.items.map(\.id) == b.items.map(\.id)
    }

    var cardHeight: CGFloat {
        switch kind {
        case .tiles: return OrbitPrimeLayout.tile.height
        case .originals: return OrbitPrimeLayout.poster.height
        case .top10: return OrbitPrimeLayout.top10Image.height
        }
    }
    var height: CGFloat { OrbitPrimeLayout.headingHeight + cardHeight + OrbitPrimeLayout.rowGap }

    private func slot(_ index: Int, lead: Int, current: Bool) -> CGFloat {
        let L = OrbitPrimeLayout.self
        switch kind {
        case .tiles: return L.tile.width
        case .originals: return current && index == lead ? L.openWidth : L.poster.width
        case .top10: return L.top10Image.width
        }
    }

    /// From the focused one (at the margin); the focused Amazon Original poster opens wide.
    func x(of index: Int, lead: Int, current: Bool) -> CGFloat {
        let L = OrbitPrimeLayout.self
        guard index > lead else { return index == lead ? 0 : -(slot(index, lead: lead, current: current) + L.gap) }
        var x: CGFloat = 0
        for i in lead..<index { x += slot(i, lead: lead, current: current) + L.gap }
        return x
    }
}

/// Amazon's own title: Steven's add-on marks it in its image address ("/img/v…/tv/123/o0/…").
func orbitPrimeIsOwn(_ item: MetaPreview) -> Bool {
    let poster: String = item.poster ?? ""
    return poster.range(of: #"/img/v\d+/(movie|tv)/\d+/o"#, options: .regularExpression) != nil
}

/// Steven: the "prime" mark only on Amazon's own productions (TMDB's producers) — the add-on's
/// "Amazon Original et exclusivités" also holds titles it only carries.
@MainActor
func orbitPrimeIsMade(_ item: MetaPreview) -> Bool {
    OrbitPlatformBadgeKind.original(OrbitMetaStore.shared.meta(for: item)) == .prime
}

struct OrbitPrimePage: View {
    let route: FolderRoute
    let push: (TitleRoute) -> Void

    static func handles(_ route: FolderRoute) -> Bool {
        let t = route.folderTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        return t.contains("primevideo") || t.contains("amazon") || t == "prime"
    }

    @StateObject private var model: FolderDetailViewModel
    @StateObject private var extras = OrbitPlatformExtrasModel()
    @StateObject private var trailer = OrbitNativeTrailerHost()
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true
    /// A title was opened over the page: no trailer starts again behind it (Steven: Prime's kept
    /// playing, its sound under the title's page).
    @State private var covered = false

    /// nil: Tout; "movie"; "series".
    @State private var typeFilter: String? = nil
    /// 0: the hero; then the rows. (Tout / Films / Séries: in the bar, Steven, as on Prime 2026.)
    @State private var current = 0
    @State private var heroIndex = 0
    /// Steven (as on Prime's app): ⓘ beside Lecture — Right from Lecture lights it, Right again goes to
    /// the next title, Left comes back to Lecture.
    @State private var heroOnInfo = false
    /// Each row's focused title (a box per row: a press redraws its row alone — native pages).
    @State private var leads = OrbitLeadStore()
    @FocusState private var canvasFocused: Bool
    /// Steven (2026-10-26): the page built like Home — sections the system moves.
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

    /// Built once per change of what they are made of (fluidity: every press rebuilt them).
    @State private var catalogsMemo = OrbitRowsMemo<[Catalog]>()

    private var catalogs: [Catalog] {
        catalogsMemo.get(OrbitRowsKey(rows: model.stripRows, filter: typeFilter)) { buildCatalogs() }
    }

    private func buildCatalogs() -> [Catalog] {
        CollectionTypeFilter.rows(model.stripRows, filter: typeFilter).compactMap { row in
            guard row.status == .loaded, let items = row.section?.items, !items.isEmpty else { return nil }
            var seen = Set<String>()
            let unique = items.filter { seen.insert("\($0.type):\($0.id)").inserted }
            let heading = row.heading.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return Catalog(id: row.id, heading: row.heading, items: unique,
                           top10: heading.contains("top 10") || heading.contains("top10"),
                           fresh: heading.contains("nouveau") || heading.contains("nouvelle"))
        }
    }

    private static func alternate<T>(_ a: [T], _ b: [T]) -> [T] {
        var out: [T] = []
        for i in 0..<max(a.count, b.count) {
            if i < a.count { out.append(a[i]) }
            if i < b.count { out.append(b[i]) }
        }
        return out
    }

    /// His Nouveautés, Amazon's own titles (portrait), his Top 10, then the genres (TMDB).
    private var rows: [OrbitPrimeRow] {
        let extraRows: [OrbitPlatformExtrasModel.Extra] = switch typeFilter {
        case "movie"?: extras.movieRows
        case "series"?: extras.seriesRows
        default: Self.alternate(extras.movieRows, extras.seriesRows)
        }
        let all = catalogs
        var out: [OrbitPrimeRow] = []
        for c in all where c.fresh {
            out.append(OrbitPrimeRow(id: c.id, title: c.heading, items: c.items, kind: .tiles))
        }
        var seen = Set<String>()
        let own = all.flatMap(\.items).filter { orbitPrimeIsOwn($0) && seen.insert(Self.identity($0)).inserted }
        if own.count >= 4 {
            let title: String = switch typeFilter {
            case "movie"?: String(localized: "Films Amazon Original et exclusivités")
            case "series"?: String(localized: "Séries Amazon Original et exclusivités")
            default: String(localized: "Programmes Amazon Original et exclusivités")
            }
            out.append(OrbitPrimeRow(id: "prime-originals-\(typeFilter ?? "all")", title: title,
                                     items: Array(own.prefix(20)), kind: .originals))
        }
        for c in all where c.top10 {
            let isSeries = c.heading.lowercased().contains("série") || c.items.first.map { $0.type != "movie" } == true
            out.append(OrbitPrimeRow(id: c.id,
                                     title: isSeries ? String(localized: "Top 10 des séries en France")
                                                     : String(localized: "Top 10 des films en France"),
                                     items: Array(c.items.prefix(10)), kind: .top10))
        }
        if extraRows.isEmpty {
            for c in all where !c.fresh && !c.top10 {
                out.append(OrbitPrimeRow(id: c.id, title: c.heading, items: c.items, kind: .tiles))
            }
        }
        var shown = Set(out.flatMap { $0.items.map(Self.identity) })
        var merged: [String: Int] = [:]
        for extra in extraRows {
            let fresh = extra.items.filter { !shown.contains(Self.identity($0)) && $0.banner != nil }
            guard fresh.count >= 8 else { continue }
            let kept = Array(fresh.prefix(24))
            kept.forEach { shown.insert(Self.identity($0)) }
            if let i = merged[extra.title] {
                // Tout: one row per genre, its films and series in turn.
                let row = out[i]
                out[i] = OrbitPrimeRow(id: row.id, title: row.title, items: Self.alternate(row.items, kept), kind: .tiles)
            } else {
                merged[extra.title] = out.count
                out.append(OrbitPrimeRow(id: extra.id, title: extra.title, items: kept, kind: .tiles))
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

    private var heroItems: [MetaPreview] {
        let fresh = catalogs.filter(\.fresh).map(\.items)
        let items = fresh.count >= 2 ? Self.alternate(fresh[0], fresh[1]) : (fresh.first ?? catalogs.first?.items ?? [])
        // Steven (as on Disney+): a title without its logo (its name written instead) left out of
        // the hero once its details are known.
        let logoed = items.filter { item in
            guard let meta = metaStore.meta(for: item) else { return true }
            return OrbitInfo.make(item, meta: meta).logo != nil
        }
        return Array((logoed.isEmpty ? items : logoed).prefix(6))
    }

    /// The hero's candidates (their details asked, the ones without a logo found out).
    private var heroCandidates: [MetaPreview] {
        let fresh = catalogs.filter(\.fresh).map(\.items)
        let items = fresh.count >= 2 ? Self.alternate(fresh[0], fresh[1]) : (fresh.first ?? catalogs.first?.items ?? [])
        return Array(items.prefix(16))
    }

    private var heroItem: MetaPreview? {
        let items = heroItems
        return items.isEmpty ? nil : items[min(heroIndex, items.count - 1)]
    }

    private func topRank(_ item: MetaPreview) -> Int? {
        let tops = catalogs.filter(\.top10)
        for top in tops {
            if let i = top.items.prefix(10).firstIndex(where: { Self.identity($0) == Self.identity(item) }) { return i + 1 }
        }
        return nil
    }

    /// "Série n° 2 en France".
    private func rankLine(_ item: MetaPreview) -> String? {
        topRank(item).map { rank in
            item.type == "movie" ? String(localized: "Film n° \(String(rank)) en France")
                                 : String(localized: "Série n° \(String(rank)) en France")
        }
    }

    private func badge(_ item: MetaPreview) -> String? {
        // Prime Video's own words, a series' news first (TMDB's episode dates).
        switch OrbitTitleNews.of(item, metaStore.meta(for: item)) {
        case .newSeason: return String(localized: "NOUVELLE SAISON")
        case .newEpisodes: return String(localized: "NOUVEAUX ÉPISODES")
        case .soon: return String(localized: "BIENTÔT DISPONIBLE")
        case nil: break
        }
        // (Steven, side by side with the app: "NOUVEAU FILM" on every tile of Nouveaux films said
        // the row's own name again — only a series' news stays.)
        return nil
    }

    private var sectionCount: Int { 1 + rows.count }

    private func rowIndex(of section: Int) -> Int? { section >= 1 ? section - 1 : nil }

    private func rowTops(_ rows: [OrbitPrimeRow]) -> [CGFloat] {
        var y = OrbitPrimeLayout.rowsTopOnArrival
        return rows.map { row in defer { y += row.height }; return y }
    }

    /// How far the rows have moved up: none on arrival, else the current row at its line.
    private func scroll(_ rows: [OrbitPrimeRow]) -> CGFloat {
        guard let r = rowIndex(of: current), rows.indices.contains(r) else { return 0 }
        let line = rows[r].kind == .originals ? OrbitPrimeLayout.originalsLine : OrbitPrimeLayout.rowLine
        return rowTops(rows)[r] - line
    }

    private func lead(of row: OrbitPrimeRow) -> Int {
        min(leads[row.id] ?? 0, max(0, row.items.count - 1))
    }

    /// The title the top of the screen shows: the hero's on arrival, else the focused one.
    private var shownItem: MetaPreview? {
        guard let r = rowIndex(of: current) else { return heroItem }
        let rows = rows
        guard rows.indices.contains(r) else { return heroItem }
        let row = rows[r]
        return row.items.indices.contains(lead(of: row)) ? row.items[lead(of: row)] : heroItem
    }

    // MARK: Body

    var body: some View {
        let rows = rows
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        let offset = scroll(rows)
        let onArrival = current == 0
        let onOriginals = rowIndex(of: current).map { rows.indices.contains($0) && rows[$0].kind == .originals } ?? false

        ZStack(alignment: .topLeading) {
            OrbitPrimeLayout.background

            // (Native: the top follows the current row's own lead box — a press in a row redraws it.)
            OrbitLeadReader(box: leads.box(rowIndex(of: current).flatMap { rows.indices.contains($0) ? rows[$0].id : nil } ?? "-")) { _ in
            if let shown = shownItem {
                OrbitPrimeTop(item: shown, meta: metaStore.meta(for: shown), line: rankLine(shown),
                              onArrival: onArrival, buttonsLit: pageFocused && current == 0 && !heroOnInfo,
                              infoLit: pageFocused && current == 0 && heroOnInfo,
                              count: heroItems.count, index: min(heroIndex, max(0, heroItems.count - 1)),
                              trailerURL: current == 0 ? trailerURL(for: shown) : nil,
                              onTrailerFailure: { trailer.playbackFailed($0) },
                              onTrailerEnded: {
                                  trailer.playbackFinished()
                                  advanceHero()
                              })
                    // On the Amazon Original row, its large posters take the screen (the trailer
                    // plays in the opened one).
                    // (Native: the Amazon Original row sits on the rows' line — the top stays, its
                    // art the focused title's: Steven, the row showed no image above it.)
                    
                    .animation(.easeInOut(duration: 0.3), value: onOriginals)
            }
            }


                            nativeSections(rows)
                    // Steven: Films / Séries came up on the Top 10 — each filter its own page, from its top.
                    .id(typeFilter ?? "all")
                    .disabled(search != nil)
            

            if rows.isEmpty, model.isLoading {
                ProgressView().frame(width: W, height: H)
            }


            CollectionFilterBar(filter: $typeFilter, onSearch: openSearch, showsAll: true, centred: true,
                                searchTrailing: OrbitPlatformIntro.searchBesideLogo)
                .disabled(search != nil || (pageFocused && current > 0))
                .opacity(search != nil ? 0 : 1)

            OrbitPlatformIntro(title: model.folderTitle, logoUrl: model.titleLogoUrl ?? route.titleLogoUrl,
                               brand: OrbitPrimeLayout.blue, white: true, cornerTop: true)

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
        .background(OrbitPrimeLayout.background)
        .ignoresSafeArea()
        .background { ViewerInputClockInstaller().frame(width: 0, height: 0) }
        // (Steven: the vertical move stuttered — the whole page animated with it; the top's own
        // fades carry the change.)
        .onAppear {
            covered = false
            tabBarVisibility.pushImmersive()
            OrbitHomeButtonHost.shared.enter(.ownBar)
            model.buildsStripState = true
            model.start()
            extras.load(title: model.folderTitle)
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
    private func nativeSections(_ rows: [OrbitPrimeRow]) -> some View {
        OrbitNativeSections(
            count: 1 + rows.count, hasHero: true,
            height: { s in s == 0 ? OrbitPrimeLayout.rowsTopOnArrival - OrbitPrimeLayout.rowLine : (rows.indices.contains(s - 1) ? rows[s - 1].height : 0) },
            topLine: OrbitPrimeLayout.rowLine, current: current, hidesAbove: true,
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
                let rowLead = lead(of: row)
                let leadItem: MetaPreview? = row.items.indices.contains(rowLead) ? row.items[rowLead] : nil
                OrbitPrimeRowView(row: row, box: leads.box(row.id), isCurrent: s == current,
                                  focused: focused,
                                  trailerURL: s == current && row.kind == .originals ? trailerURL(for: leadItem) : nil,
                                  onTrailerFailure: { trailer.playbackFailed($0) },
                                  onTrailerEnded: { trailer.playbackFinished() },
                                  badges: Dictionary(row.items.map { ($0.id, badge($0) ?? "") },
                                                     uniquingKeysWith: { a, _ in a }),
                                  metaStore: metaStore,
                                       onEnter: { nativeEnter(s) }, onLeave: nativeLeave, onSelect: select,
                                       onLeadChange: { refreshAfterMove() })
                    .equatable()
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
            withAnimation(reduceMotion ? nil : OrbitPrimeLayout.vertical) { current += 1 }
        case .up:
            guard current > 0 else { return }
            withAnimation(reduceMotion ? nil : OrbitPrimeLayout.vertical) { current -= 1 }
            heroOnInfo = false
        case .left, .right:
            let step = direction == .right ? 1 : -1
            if current == 0 {
                if step > 0, !heroOnInfo {
                    withAnimation(.easeOut(duration: 0.18)) { heroOnInfo = true }
                    return
                }
                if step < 0, heroOnInfo {
                    withAnimation(.easeOut(duration: 0.18)) { heroOnInfo = false }
                    return
                }
                heroOnInfo = false
                let n = heroItems.count
                guard n > 1 else { return }
                withAnimation(.easeInOut(duration: 0.3)) { heroIndex = (heroIndex + step + n) % n }
            } else if let r = rowIndex(of: current), rows.indices.contains(r) {
                let row = rows[r]
                let next = lead(of: row) + step
                guard row.items.indices.contains(next) else { return }
                withAnimation(reduceMotion ? nil : OrbitPrimeLayout.horizontal) { leads[row.id] = next }
            }
        @unknown default:
            return
        }
        refreshAfterMove()
    }

    /// The detail page's Prime Video touch.
    private func detailPlatform(_ item: MetaPreview) -> OrbitDetailPlatform {
        OrbitDetailPlatform(theme: .prime, own: orbitPrimeIsMade(item) ? .prime : nil,
                            logoUrl: model.titleLogoUrl ?? route.titleLogoUrl)
    }

    private func select() {
        covered = true
        trailer.reset(abortStages: true)
        guard let shownItem else { return }
        var platform = detailPlatform(shownItem)
        // Steven: the hero's Lecture plays the title at once; ⓘ opens its page.
        platform.autoPlay = current == 0 && !heroOnInfo
        push(TitleRoute(preview: shownItem, platform: platform))
    }

    private func exitAction() -> (() -> Void)? {
        guard current > 0 else { return nil }
        return {
            withAnimation(reduceMotion ? nil : OrbitPrimeLayout.vertical) { current = 0 }
            refreshAfterMove()
        }
    }

    private func advanceHero() {
        let n = heroItems.count
        guard n > 1, current == 0 else { return }
        withAnimation(.easeInOut(duration: 0.5)) { heroIndex = (heroIndex + 1) % n }
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
                                              landscape: true)
        }
    }

    private func closeSearch() {
        withAnimation(.easeInOut(duration: 0.25)) { search = nil }
        refreshAfterMove()
    }

    private func refreshAfterMove() {
        let rows = rows
        motion.stamp()
        var metaItems: [MetaPreview] = heroItems + heroCandidates
        let r = rowIndex(of: current) ?? 0
        for i in r...max(r, min(rows.count - 1, r + 2)) where rows.indices.contains(i) {
            let row = rows[i]
            let lead = lead(of: row)
            metaItems += row.items.indices.filter { $0 >= lead - 1 && $0 <= lead + 7 }.map { row.items[$0] }
        }
        OrbitMetaStore.shared.request(metaItems)
        // Steven's video: Top 10 frames empty a while (his add-on draws each image on demand): all
        // ten fetched as soon as the page has them.
        let top10Size = OrbitPrimeLayout.top10Image
        let decode = ArtworkDecodeRequest(size: .points(width: top10Size.width, height: top10Size.height), fill: false,
                                          scale: UIScreen.main.scale).normalized
        for row in rows where row.kind == .top10 {
            OrbitMetaStore.shared.request(row.items)
            for item in row.items {
                guard let raw = (item.poster ?? item.rawPosterUrl).flatMap(URL.init(string:)),
                      ArtworkStore.cached(raw, decode: decode) == nil else { continue }
                Task { _ = try? await ArtworkStore.fetch(raw, decode: decode) }
            }
        }

        trailer.reset()
        trailerKey = nil
        // The hero's trailer plays whether or not it has the focus (the bar can); on the Amazon
        // Original row, the opened poster's.
        guard trailersOn, !covered, search == nil, UIAccessibility.isVideoAutoplayEnabled else { return }
        var target: MetaPreview?
        if current == 0 {
            target = heroItem
        } else if let r = rowIndex(of: current), rows.indices.contains(r), rows[r].kind == .originals, pageFocused {
            let row = rows[r]
            target = row.items.indices.contains(lead(of: row)) ? row.items[lead(of: row)] : nil
        }
        guard let item = target else { return }
        trailer.prefersReducedMotion = reduceMotion
        trailer.restSource = .custom(motion)
        trailerKey = "\(item.type):\(item.id)"
        trailer.focusChanged(true, item: item)
    }
}

// MARK: - Pieces

/// "prime" with Amazon's smile.
struct OrbitPrimeMark: View {
    var size: CGFloat = 22
    var color: Color = .white

    var body: some View {
        VStack(alignment: .trailing, spacing: -size * 0.15) {
            Text("prime")
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(color)
            OrbitPrimeSmile()
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                .frame(width: size * 2.1, height: size * 0.32)
        }
        .shadow(color: .black.opacity(0.5), radius: 4)
    }
}

struct OrbitPrimeSmile: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX * 0.9, y: rect.minY + rect.height * 0.2),
                       control: CGPoint(x: rect.midX, y: rect.maxY * 1.4))
        p.move(to: CGPoint(x: rect.maxX * 0.78, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX * 0.9, y: rect.minY + rect.height * 0.2))
        p.addLine(to: CGPoint(x: rect.maxX * 0.84, y: rect.maxY * 0.75))
        return p
    }
}

/// The small white badge top right ("NOUVEAU FILM").
private struct OrbitPrimeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Rectangle().fill(Color.white.opacity(0.9)))
    }
}

/// Prime's green line ("Série n° 2 en France").
private struct OrbitPrimeLine: View {
    let text: String
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: size * 0.4) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                .font(.system(size: size * 1.15, weight: .semibold))
            Text(text)
                .font(.system(size: size, weight: .bold))
        }
        .foregroundStyle(OrbitPrimeLayout.green)
    }
}

/// The top of the screen: a title's art on the right (its trailer on a rest), its details on the
/// left; on arrival, the TV app's buttons and the dots.
private struct OrbitPrimeTop: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let line: String?
    let onArrival: Bool
    let buttonsLit: Bool
    var infoLit = false
    let count: Int
    let index: Int
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let L = OrbitPrimeLayout.self
        let size = CGSize(width: OrbitHomeLayout.screenWidth, height: L.artHeight)
        let banner: String? = item.banner
        let info = OrbitInfo.make(item, meta: meta)
        ZStack(alignment: .topLeading) {
            ZStack {
                OrbitSwapImage(url: banner ?? meta?.backdrop, fallback: nil, size: size)
                if let trailerURL {
                    TrailerHeroPlayer(urlString: trailerURL, onFailure: onTrailerFailure,
                                      zoomKey: TrailerResolutionCache.key(type: item.type, id: item.id),
                                      loops: false, onPlaybackEnded: onTrailerEnded, cornerRadius: 0)
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity.animation(.easeOut(duration: 0.6)))
                }
                LinearGradient(stops: [
                    .init(color: L.background.opacity(0.97), location: 0),
                    .init(color: L.background.opacity(0.6), location: 0.38),
                    .init(color: .clear, location: 0.64),
                ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [
                    .init(color: .clear, location: onArrival ? 0.5 : 0.25),
                    .init(color: L.background.opacity(0.9), location: onArrival ? 0.82 : 0.6),
                    .init(color: L.background, location: onArrival ? 1 : 0.72),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .animation(.easeInOut(duration: 0.3), value: onArrival)

            VStack(alignment: .leading, spacing: 0) {
                if orbitPrimeIsMade(item) {
                    OrbitPrimeMark(size: 28, color: L.blue)
                        .padding(.bottom, 10)
                }
                OrbitTitleMark(name: item.name, logo: info.logo, maxSize: onArrival ? L.logoSize : CGSize(width: 440, height: 140),
                               textSize: onArrival ? 64 : 48, fallbackLogo: info.logoFallback, hugsLogo: true)
                    .frame(width: L.logoSize.width, alignment: .leading)
                if let line {
                    OrbitPrimeLine(text: line)
                        .padding(.top, 20)
                }
                Text(info.synopsis)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineSpacing(4)
                    .lineLimit(2)
                    .frame(width: L.synopsisWidth, alignment: .topLeading)
                    .padding(.top, 14)
                HStack(spacing: 12) {
                    // Prime 2026: the rating out of five first.
                    if let percent = meta?.percent {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill").foregroundStyle(Color.white.opacity(0.9))
                            Text(String(format: "%.1f/5", Double(percent) / 20).replacingOccurrences(of: ".", with: ","))
                                .foregroundStyle(Color.white.opacity(0.9))
                        }
                    }
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(L.blue)
                    Text(String(localized: "Inclus avec Prime"))
                        .foregroundStyle(Color.white.opacity(0.9))
                    if let certification = meta?.certification {
                        Text(certification == "TP" ? String(localized: "TP") : "\(certification)+")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.22)))
                    }
                    Text(info.parts.joined(separator: "  ·  "))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(1)
                .padding(.top, 14)
                if onArrival {
                    HStack(spacing: 18) {
                        HStack(spacing: 14) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(Color.black)
                                .frame(width: 66, height: 66)
                                .background(Circle().fill(Color.white))
                            Text(String(localized: "Lecture"))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                        .scaleEffect(buttonsLit ? 1.06 : 1, anchor: .leading)
                        // (+ removed, Steven: it could not be used. ⓘ back, as on Prime's app: the
                        // title's page.)
                        Image(systemName: "info")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(infoLit ? Color.black : Color.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(infoLit ? Color.white : Color.white.opacity(0.22)))
                            .scaleEffect(infoLit ? 1.1 : 1)
                            .padding(.leading, 10)
                    }
                    .padding(.top, 26)
                    .animation(.easeOut(duration: 0.18), value: buttonsLit)
                    .animation(.easeOut(duration: 0.18), value: infoLit)
                    .transition(.opacity)
                }
            }
            .frame(width: L.synopsisWidth, alignment: .topLeading)
            .offset(x: L.margin, y: L.infoTop)
            .id("\(item.type):\(item.id)-info")
            .transition(.opacity.animation(.easeInOut(duration: 0.25)))

            if onArrival, count > 1 {
                HStack(spacing: 10) {
                    ForEach(0..<count, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(i == index ? 1 : 0.35))
                            .frame(width: i == index ? 11 : 8, height: i == index ? 11 : 8)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: index)
                .frame(width: size.width)
                .offset(y: L.rowsTopOnArrival - 70)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// A row: its heading, then its titles from the focused one (at the margin).
extension OrbitPrimeRowView: Equatable {
    static func == (a: OrbitPrimeRowView, b: OrbitPrimeRowView) -> Bool {
        a.row == b.row && a.box === b.box && a.isCurrent == b.isCurrent && a.focused == b.focused
            && a.trailerURL == b.trailerURL && a.badges == b.badges
    }
}

private struct OrbitPrimeRowView: View {
    let row: OrbitPrimeRow
    @ObservedObject var box: OrbitLeadBox
    let isCurrent: Bool
    let focused: Bool
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void
    let badges: [String: String]
    @ObservedObject var metaStore: OrbitMetaStore
    let onEnter: () -> Void
    let onLeave: () -> Void
    let onSelect: () -> Void
    let onLeadChange: () -> Void

    var body: some View {
        let L = OrbitPrimeLayout.self
        let lead = min(box.lead, max(0, row.items.count - 1))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if row.kind == .originals {
                    Text("Prime").foregroundStyle(L.blue)
                }
                Text(row.title).foregroundStyle(Color.white.opacity(isCurrent ? 1 : 0.8))
                if row.kind == .top10 {
                    Image(systemName: "chart.line.uptrend.xyaxis.circle")
                        .foregroundStyle(Color.white.opacity(0.9))
                }
            }
            .font(.system(size: 26, weight: .bold))
            .lineLimit(1)
            .frame(height: L.headingHeight, alignment: .topLeading)
            .padding(.leading, L.margin)
            OrbitNativeTileStrip(count: row.items.count, spacing: L.gap, height: row.cardHeight,
                                 lastWidth: row.kind == .originals ? L.openWidth : row.x(of: 1, lead: 0, current: false) - L.gap,
                                 box: box, alignment: .top,
                                 // Steven: the row of opening posters scrolls as Home's first row —
                                 // the open one held at the margin, the row sliding under it.
                                 keepsLeadAtMargin: row.kind == .originals,
                                 onEnter: onEnter, onLeave: onLeave, onSelect: onSelect,
                                 onLeadChange: { _ in onLeadChange() },
                                 leftSlide: row.kind == .originals ? { _ in L.poster.width + L.gap } : nil,
                                 // (UIKit strip: the open title's room; the others measured.)
                                 width: row.kind == .originals ? { index in isCurrent && index == lead ? L.openWidth : L.poster.width } : nil) { index, lit in
                let item = row.items[index]
                let meta = metaStore.meta(for: item)
                let badge = badges[item.id].flatMap { $0.isEmpty ? nil : $0 }
                switch row.kind {
                case .tiles:
                    OrbitPrimeTile(item: item, meta: meta, badge: badge, focused: lit)
                case .originals:
                    // Steven: as Netflix's — the open frame drawn by the row, fixed at the margin;
                    // the lead keeps its room (its poster at the room's right, under the frame).
                    if isCurrent && index == lead {
                        // (Steven, 2026-10-29: as Home's new films — the lead's room left empty.)
                        Color.clear
                            .frame(width: L.openWidth, height: L.poster.height)
                    } else {
                        OrbitPrimePoster(item: item, meta: meta, badge: badge, open: false,
                                         focused: lit, trailerURL: nil,
                                         onTrailerFailure: onTrailerFailure, onTrailerEnded: onTrailerEnded)
                            .transition(.identity)
                    }
                case .top10:
                    OrbitPrimeTop10Image(item: item, meta: meta, focused: lit)
                }
            }
            .animation(nil, value: isCurrent)
            .frame(width: OrbitHomeLayout.screenWidth, height: row.cardHeight, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                if row.kind == .originals, isCurrent, row.items.indices.contains(lead) {
                    let item = row.items[lead]
                    ZStack(alignment: .topLeading) {
                        Color(white: 0.09)
                        // The next title fades in over the last one (Netflix's own frame).
                        OrbitPrimePoster(item: item, meta: metaStore.meta(for: item),
                                         badge: badges[item.id].flatMap { $0.isEmpty ? nil : $0 }, open: true,
                                         focused: focused, trailerURL: trailerURL,
                                         onTrailerFailure: onTrailerFailure, onTrailerEnded: onTrailerEnded)
                            .id("\(item.type):\(item.id)")
                            .zIndex(1)
                            .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22)),
                                                    removal: .opacity.animation(.linear(duration: 0.01).delay(0.24))))
                    }
                    .frame(width: L.openWidth, height: L.poster.height, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
                    .offset(x: L.margin)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
    }
}

/// His Top 10 image as it is (Steven: his add-on's ranks): the 16:9 card on the right, its big rank
/// behind; focused, a white frame around the card only.
private struct OrbitPrimeTop10Image: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let focused: Bool

    var body: some View {
        let L = OrbitPrimeLayout.self
        let size = L.top10Image
        let card = CGRect(x: size.width * 0.24, y: (size.height - L.tile.height) / 2,
                          width: L.tile.width, height: L.tile.height)
        ZStack(alignment: .topLeading) {
            // Under his image while it comes (or if it never does): TMDB's art in the card's place.
            OrbitImage(url: meta?.backdrop ?? item.banner, mode: .fill, size: card.size)
                .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
                .offset(x: card.minX, y: card.minY)
            OrbitImage(url: item.poster, fallback: item.rawPosterUrl, mode: .fit, size: size)
        }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: L.radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(focused ? 0.95 : 0), lineWidth: 3)
                    .frame(width: card.width, height: card.height)
                    .offset(x: card.minX, y: card.minY)
            }
            .scaleEffect(focused ? L.focusScale : 1, anchor: .leading)
            // (Steven, device: the focused tile rose before the others — its focus follows the move's own curve.)
    }
}

/// A 16:9 tile: TMDB's backdrop, the French logo, "prime" on Amazon's own, the badge; focused, a
/// white frame and a little larger, in place.
private struct OrbitPrimeTile: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let badge: String?
    let focused: Bool

    var body: some View {
        let L = OrbitPrimeLayout.self
        let size = L.tile
        let info = OrbitInfo.make(item, meta: meta)
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.10, green: 0.13, blue: 0.18)
            OrbitImage(url: meta?.backdrop ?? item.banner, fallback: item.poster, size: size)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            OrbitTitleMark(name: item.name, logo: info.logo,
                           maxSize: CGSize(width: size.width * 0.55, height: size.height * 0.42), textSize: 24,
                           fallbackLogo: info.logoFallback)
                .padding(.leading, 14)
                .padding(.bottom, 14)
            if orbitPrimeIsMade(item) {
                OrbitPrimeMark(size: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(12)
            }
            if let badge {
                OrbitPrimeBadge(text: badge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(5)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .modifier(OrbitPrimeFocus(focused: focused))
    }
}

/// A tall poster of Amazon's own titles (TMDB's, in French when it has one); focused, it opens wide
/// (as on Prime's TV app) and its trailer plays in it after a rest.
private struct OrbitPrimePoster: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let badge: String?
    let open: Bool
    let focused: Bool
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let L = OrbitPrimeLayout.self
        let size = CGSize(width: open ? L.openWidth : L.poster.width, height: L.poster.height)
        let info = OrbitInfo.make(item, meta: meta)
        let poster: String? = meta?.localPoster ?? meta?.titledPoster
        let openSize = CGSize(width: L.openWidth, height: L.poster.height)
        let shape = RoundedRectangle(cornerRadius: L.radius, style: .continuous)
        // Steven (2026-10-26: "exactement comme dans Nouveaux films de l'accueil"): the closed poster
        // always there at its own size; the open frame a view of its own at its full size, fading
        // in over it — no pane revealed from one side, no grey.
        ZStack(alignment: .topLeading) {
            ZStack {
                Color(red: 0.10, green: 0.13, blue: 0.18)
                OrbitImage(url: poster ?? item.banner, fallback: item.poster, mode: .fill, size: L.poster)
                if orbitPrimeIsMade(item) {
                    OrbitPrimeMark(size: 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(16)
                }
                if let badge {
                    OrbitPrimeBadge(text: badge)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                }
            }
            .frame(width: L.poster.width, height: L.poster.height)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.white.opacity(focused && !open ? 0.95 : 0), lineWidth: 3) }
            if open {
                ZStack(alignment: .bottomLeading) {
                    // (Steven's video: the poster stretched under the art showed as a coloured smear
                    // while the row came in — the page's own dark until the art, fetched ahead, lands.)
                    Color(white: 0.09)
                    OrbitSwapImage(url: meta?.backdrop ?? item.banner, fallback: nil, size: openSize)
                    if let trailerURL {
                        TrailerHeroPlayer(urlString: trailerURL, onFailure: onTrailerFailure,
                                          zoomKey: TrailerResolutionCache.key(type: item.type, id: item.id),
                                          loops: false, onPlaybackEnded: onTrailerEnded, cornerRadius: L.radius)
                            .frame(width: openSize.width, height: openSize.height)
                            .transition(.opacity.animation(.easeOut(duration: 0.6)))
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
                    // Prime's own app (Steven's video): the mark above the logo, then "✓ Inclus avec
                    // Prime", the rating, the age and the genres.
                    VStack(alignment: .leading, spacing: 12) {
                        if orbitPrimeIsMade(item) { OrbitPrimeMark(size: 22, color: L.blue) }
                        OrbitTitleMark(name: item.name, logo: info.logo, maxSize: CGSize(width: 420, height: 130), textSize: 44,
                                       fallbackLogo: info.logoFallback, hugsLogo: true)
                            .frame(width: 420, alignment: .leading)
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(L.blue)
                            Text(String(localized: "Inclus avec Prime")).foregroundStyle(Color.white.opacity(0.95))
                            if let percent = meta?.percent {
                                HStack(spacing: 5) {
                                    Image(systemName: "star.fill")
                                    Text(String(format: "%.1f/5", Double(percent) / 20).replacingOccurrences(of: ".", with: ","))
                                }
                                .foregroundStyle(Color.white.opacity(0.9))
                            }
                            if let certification = meta?.certification {
                                Text(certification == "TP" ? String(localized: "TP") : "\(certification)+")
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.22)))
                            }
                            if let genres = meta?.genre ?? item.genres.first {
                                Text(genres).foregroundStyle(Color.white.opacity(0.8))
                            }
                        }
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                    }
                    .padding(.leading, 26)
                    .padding(.bottom, 24)
                    if let badge {
                        OrbitPrimeBadge(text: badge)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(6)
                    }
                }
                .frame(width: openSize.width, height: openSize.height)
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.white.opacity(focused ? 0.95 : 0), lineWidth: 3) }
                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .shadow(color: .black.opacity(focused ? 0.55 : 0.2), radius: focused ? 18 : 6, y: focused ? 10 : 4)
        // (Steven, device: the focused tile rose before the others — its focus follows the move's own curve.)
    }
}

/// The TV app's focus: a white frame, a little larger, in place (from the top-left corner).
private struct OrbitPrimeFocus: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: OrbitPrimeLayout.radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(focused ? 0.95 : 0), lineWidth: 3)
            }
            .shadow(color: .black.opacity(focused ? 0.55 : 0.2), radius: focused ? 18 : 6, y: focused ? 10 : 4)
            .scaleEffect(focused ? OrbitPrimeLayout.focusScale : 1, anchor: .leading)
            // (Steven, device: the focused tile rose before the others — its focus follows the move's own curve.)
    }
}
