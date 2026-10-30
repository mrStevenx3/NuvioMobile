import Combine
import SharedCore
import SwiftUI

// Orbit × Apple TV (Steven, 2026-10-25: a video of tvOS 26's Apple TV app). Orbit's DNA kept (one
// focusable canvas; the house and the platform's pill top left; the intro; trailers on a rest).
//
//  - tvOS 26's glass: no black page — the shown title's art, blurred and dimmed, colours the whole
//    background, and changes with it.
//  - On arrival, a full-screen carousel of the new titles: the art (its trailer on a rest), the small
//    capsule ("Nouveauté"), the logo, " Série TV · Thriller · Drame  16", three lines of synopsis,
//    "N° 1 des séries sur Apple TV", the white "▶ Regarder" capsule, the dots in the middle.
//  - The rows: tall rounded posters, the focused one lifted larger; his Top 10 images (the white rank
//    inside the poster, top left); one row of large cards (art without its title, the logo and the
//    line over it), like the app's "Pour les détectives en herbe".

enum OrbitAppleTVLayout {
    static let margin: CGFloat = OrbitHomeLayout.margin
    static let infoTop: CGFloat = 330
    static let logoSize = CGSize(width: 600, height: 200)
    static let synopsisWidth: CGFloat = 700
    /// The first row's heading peeks at the bottom of the carousel.
    static let rowsTopOnArrival: CGFloat = 975
    static let firstRowLine: CGFloat = 130
    static let aboveRowShows: CGFloat = 0.5
    static let headingHeight: CGFloat = 50
    /// Measured on Steven's video (tvOS 26, 1920 wide): the Top 10's and the new titles' posters
    /// ≈ 256 × 384, ≈ 36 apart.
    static let poster = CGSize(width: 256, height: 384)
    static let card = CGSize(width: 520, height: 620)
    static let gap: CGFloat = 36
    static let cardGap: CGFloat = 34
    static let rowGap: CGFloat = 46
    static let radius: CGFloat = 20
    static let focusScale: CGFloat = 1.1
    static let horizontal = Animation.easeOut(duration: 0.24)
    static let vertical = Animation.easeInOut(duration: 0.4)
}

extension OrbitAppleTVLayout {
    /// The focused poster's lengthened foot (Apple's app: the art goes on, darkening, its words in it).
    static let captionFoot: CGFloat = 38
}

struct OrbitAppleTVRow: Identifiable, Equatable {
    enum Kind: Equatable { case posters, top10, cards }

    let id: String
    let title: String
    let items: [MetaPreview]
    let kind: Kind

    static func == (a: OrbitAppleTVRow, b: OrbitAppleTVRow) -> Bool {
        a.id == b.id && a.kind == b.kind && a.items.map(\.id) == b.items.map(\.id)
    }

    var cardHeight: CGFloat { kind == .cards ? OrbitAppleTVLayout.card.height : OrbitAppleTVLayout.poster.height }
    /// The posters' rows: room under them for the focused one's lengthened foot (its kind and genre).
    var height: CGFloat { OrbitAppleTVLayout.headingHeight + cardHeight + OrbitAppleTVLayout.rowGap + (kind != .cards ? OrbitAppleTVLayout.captionFoot : 0) }
    /// The titles that fit whole on screen (the last one before the right margin).
    var visibleCount: Int {
        max(1, Int((OrbitHomeLayout.screenWidth - OrbitAppleTVLayout.margin * 2 + (slot - (kind == .cards ? OrbitAppleTVLayout.card.width : OrbitAppleTVLayout.poster.width))) / slot))
    }

    var slot: CGFloat {
        kind == .cards ? OrbitAppleTVLayout.card.width + OrbitAppleTVLayout.cardGap
                       : OrbitAppleTVLayout.poster.width + OrbitAppleTVLayout.gap
    }
}

struct OrbitAppleTVPage: View {
    let route: FolderRoute
    let push: (TitleRoute) -> Void
    /// The zoom into the detail page (HomeView's namespace).
    var zoomSpace: Namespace.ID? = nil

    static func handles(_ route: FolderRoute) -> Bool {
        let t = route.folderTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        return t.contains("appletv")
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

    /// nil: Accueil; "movie"; "series".
    @State private var typeFilter: String? = nil
    /// 0: the carousel; then the rows.
    @State private var current = 0
    @State private var heroIndex = 0
    /// Native: the hero is a carousel the system slides (Steven: as Orbit Home's).
    @FocusState private var heroFocus: Int?
    /// Each row's focused title (a box per row: a press redraws its row alone — native pages).
    @State private var leads = OrbitLeadStore()
    /// Steven (as in the app): each row's first title on screen — the focus moves along a still row,
    /// which scrolls only when the focus would leave the screen.
    @State private var firsts = OrbitLeadStore()
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

    init(route: FolderRoute, push: @escaping (TitleRoute) -> Void, zoomSpace: Namespace.ID? = nil) {
        self.route = route
        self.push = push
        self.zoomSpace = zoomSpace
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

    /// As in the app: the Top 10 first, then the new titles, one row of large cards, the genres (TMDB).
    /// Steven (2026-10-30, slow-motion videos: this page jerky down, Netflix fluid): the rows were
    /// built again on every redraw of the page (each step, each row change — every title's name
    /// folded, every poster matched), several times per redraw; built once per change of the
    /// catalogs now, as Netflix's.
    @State private var rowsMemo = OrbitRowsMemo<[OrbitAppleTVRow]>()

    private var rows: [OrbitAppleTVRow] {
        rowsMemo.get(OrbitRowsKey(rows: model.stripRows, filter: typeFilter,
                                  extras: extras.movieRows + extras.seriesRows, variant: "")) { buildRows() }
    }

    private func buildRows() -> [OrbitAppleTVRow] {
        let extraRows: [OrbitPlatformExtrasModel.Extra] = switch typeFilter {
        case "movie"?: extras.movieRows
        case "series"?: extras.seriesRows
        default: Self.alternate(extras.seriesRows, extras.movieRows)
        }
        let all = catalogs
        var out: [OrbitAppleTVRow] = []
        // Series' Top 10 before the films' (the app's order).
        let tops = all.filter { $0.top10 && Self.isSeries($0) } + all.filter { $0.top10 && !Self.isSeries($0) }
        for c in tops {
            out.append(OrbitAppleTVRow(id: c.id,
                                       title: Self.isSeries(c) ? String(localized: "Top 10 : séries sur Apple TV")
                                                               : String(localized: "Top 10 : films sur Apple TV"),
                                       items: Array(c.items.prefix(10)), kind: .top10))
        }
        let fresh = all.filter(\.fresh)
        if typeFilter == nil, fresh.count >= 2 {
            out.append(OrbitAppleTVRow(id: "atv-new-all", title: String(localized: "Nouveautés sur Apple TV"),
                                       items: Self.alternate(fresh[0].items, fresh[1].items), kind: .posters))
        } else {
            for c in fresh {
                out.append(OrbitAppleTVRow(id: c.id, title: c.heading, items: c.items, kind: .posters))
            }
        }
        if extraRows.isEmpty {
            for c in all where !c.fresh && !c.top10 {
                out.append(OrbitAppleTVRow(id: c.id, title: c.heading, items: c.items, kind: .posters))
            }
        }
        var shown = Set(out.flatMap { $0.items.map(Self.identity) })
        var merged: [String: Int] = [:]
        var cardsDone = false
        for extra in extraRows {
            let freshItems = extra.items.filter { !shown.contains(Self.identity($0)) }
            guard freshItems.count >= 6 else { continue }
            let kept = Array(freshItems.prefix(24))
            kept.forEach { shown.insert(Self.identity($0)) }
            if let i = merged[extra.title] {
                let row = out[i]
                out[i] = OrbitAppleTVRow(id: row.id, title: row.title, items: Self.alternate(row.items, kept), kind: row.kind)
            } else {
                merged[extra.title] = out.count
                // The first genre as the app's large cards ("Pour les amateurs de drame").
                if !cardsDone {
                    cardsDone = true
                    out.append(OrbitAppleTVRow(id: extra.id, title: String(localized: "Pour les amateurs de \(extra.title.lowercased())"),
                                               items: kept, kind: .cards))
                } else {
                    out.append(OrbitAppleTVRow(id: extra.id, title: extra.title, items: kept, kind: .posters))
                }
            }
        }
        return out
    }

    private static func isSeries(_ c: Catalog) -> Bool {
        c.heading.lowercased().contains("série") || c.items.first.map { $0.type != "movie" } == true
    }

    private static func identity(_ item: MetaPreview) -> String {
        let year: String = item.releaseInfo.map { String($0.prefix(4)) } ?? ""
        return item.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) + "|" + year
    }

    /// Steven (2026-10-30: Prime fluid at last, this page still jerky down): every title of every
    /// row asked "new?" on each redraw — and each ask built again the set of all the new titles
    /// (every name folded). Built once per change of the catalogs now, each row's answer kept.
    @State private var freshMemo = OrbitRowsMemo<Set<String>>()
    @State private var newsMemo = OrbitRevisionMemo<Set<String>>()

    private var freshIdentities: Set<String> {
        freshMemo.get(OrbitRowsKey(rows: model.stripRows, filter: typeFilter, variant: "")) {
            Set(catalogs.filter(\.fresh).flatMap { $0.items.map(Self.identity) })
        }
    }

    /// A row's new titles (their ids), kept while its titles are the same.
    private func newIDs(_ items: [MetaPreview], row: String) -> Set<String> {
        let fresh = freshIdentities
        let key = row + "|" + (typeFilter ?? "all") + "|\(items.count)|" + (items.first?.id ?? "") + "|" + (items.last?.id ?? "")
        return newsMemo.get(key, revision: fresh.count) {
            Set(items.filter { fresh.contains(Self.identity($0)) }.map(\.id))
        }
    }

    private func isNew(_ item: MetaPreview) -> Bool { freshIdentities.contains(Self.identity(item)) }

    private var heroItems: [MetaPreview] {
        let fresh = catalogs.filter(\.fresh).map(\.items)
        let items = fresh.count >= 2 ? Self.alternate(fresh[1], fresh[0]) : (fresh.first ?? catalogs.first?.items ?? [])
        let withArt = items.filter { $0.banner != nil }
        let isDoc: (MetaPreview) -> Bool = { item in item.genres.contains { $0.hasPrefix("Documentaire") } }
        return Array((withArt.filter { !isDoc($0) } + withArt.filter(isDoc)).prefix(7))
    }

    private var heroItem: MetaPreview? {
        let items = heroItems
        return items.isEmpty ? nil : items[min(heroIndex, items.count - 1)]
    }

    /// "N° 1 des séries sur Apple TV".
    /// (Each Top 10 title's identity worked out once per change of the catalogs — it was worked out
    /// again for every tile asking.)
    @State private var topMemo = OrbitRowsMemo<[[String]]>()

    private func rankLine(_ item: MetaPreview) -> String? {
        let tops = topMemo.get(OrbitRowsKey(rows: model.stripRows, filter: typeFilter, variant: "top")) {
            catalogs.filter(\.top10).map { $0.items.prefix(10).map(Self.identity) }
        }
        let identity = Self.identity(item)
        for top in tops {
            if let i = top.firstIndex(of: identity) {
                return item.type == "movie" ? String(localized: "N° \(String(i + 1)) des films sur Apple TV")
                                            : String(localized: "N° \(String(i + 1)) des séries sur Apple TV")
            }
        }
        return nil
    }

    private var sectionCount: Int { 1 + rows.count }

    private func rowIndex(of section: Int) -> Int? { section >= 1 ? section - 1 : nil }

    private func rowTops(_ rows: [OrbitAppleTVRow]) -> [CGFloat] {
        var y = OrbitAppleTVLayout.rowsTopOnArrival
        return rows.map { row in defer { y += row.height }; return y }
    }

    /// None on the carousel; the first row at the top; then the row above half in view.
    private func scroll(_ rows: [OrbitAppleTVRow]) -> CGFloat {
        guard let r = rowIndex(of: current), rows.indices.contains(r) else { return 0 }
        let L = OrbitAppleTVLayout.self
        var line = r == 0 ? L.firstRowLine : L.firstRowLine + rows[r - 1].height * L.aboveRowShows
        // A row of large cards keeps its whole height on screen.
        if rows[r].kind == .cards { line = min(line, OrbitHomeLayout.screenHeight - rows[r].height - 20) }
        return rowTops(rows)[r] - line
    }

    private func first(of row: OrbitAppleTVRow) -> Int {
        min(firsts[row.id] ?? 0, lead(of: row))
    }

    private func lead(of row: OrbitAppleTVRow) -> Int {
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
        // Steven (the app's videos): the background takes the carousel's title only — it stays put
        // while the focus runs through the rows (it changed with every poster).
        let ambient = heroItem

        ZStack(alignment: .topLeading) {
            OrbitAppleTVAmbient(item: ambient, meta: ambient.flatMap { metaStore.meta(for: $0) })


                            nativeSections(rows)
                    // Steven: a tab change came up on the Top 10 — each filter its own page, from its hero.
                    .id(typeFilter ?? "all")
                    .disabled(search != nil)
            

            if rows.isEmpty, model.isLoading {
                ProgressView().frame(width: W, height: H)
            }


            // Steven: the app mixes films and series, with no Accueil / Films / Séries.
            CollectionFilterBar(filter: $typeFilter, onSearch: openSearch, showsAll: true, centred: true,
                                searchTrailing: OrbitPlatformIntro.searchBesideLogo)
                .disabled(search != nil || (pageFocused && current > 0))
                .opacity(search != nil ? 0 : 1)

            OrbitPlatformIntro(title: model.folderTitle, logoUrl: model.titleLogoUrl ?? route.titleLogoUrl,
                               brand: Color(white: 0.6), white: true, assetLogo: "AppleTVMark")

            if let search {
                OrbitPlatformSearchLayer(model: search, platform: model.folderTitle,
                                         onOpen: { push(TitleRoute(preview: $0, platform: OrbitDetailPlatform(theme: .appletv))) },
                                         onClose: closeSearch)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .clipped()
        .background(Color.black)
        .ignoresSafeArea()
        .background { ViewerInputClockInstaller().frame(width: 0, height: 0) }
        // Steven (2026-10-30: Apple TV and HBO Max still jerky down, the other platforms smooth): the
        // whole page was animated at every row change (an animation on all of it, by the rows'
        // offset — left from the page before its rows were native); only these two pages still had it.
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
            firsts.reset()
            refreshAfterMove()
        }
    }

    /// The native page: the sections (an invisible stop for the hero, whose art stays behind, then
    /// the rows drawn as before) as real buttons the system moves.
    private func nativeSections(_ rows: [OrbitAppleTVRow]) -> some View {
        OrbitNativeSections(
            count: 1 + rows.count, hasHero: true,
            height: { s in s == 0 ? OrbitAppleTVLayout.rowsTopOnArrival - OrbitAppleTVLayout.firstRowLine : (rows.indices.contains(s - 1) ? rows[s - 1].height : 0) },
            topLine: nativeLine(rows), current: current, hidesAbove: false,
            onFocus: { s in
                withAnimation(.easeInOut(duration: 0.3)) { current = s }
                // (The page's work once the slide is over — see `nativeEnter`.)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { if current == s { refreshAfterMove() } }
            },
            onMove: { move($0) }, onSelect: select, onExit: exitAction(),
            customHero: true,
            focusHero: { heroFocus = min(heroIndex, max(0, heroItems.count - 1)) },
            rowsFocusable: true,
            focusRow: { s in if rows.indices.contains(s - 1) { leads.box(rows[s - 1].id).focusRequest &+= 1 } },
            line: { s in
                let L = OrbitAppleTVLayout.self
                guard s >= 1, rows.indices.contains(s - 1) else { return L.firstRowLine }
                var line = s == 1 ? L.firstRowLine : L.firstRowLine + rows[s - 2].height * L.aboveRowShows
                // A row of large cards keeps its whole height on screen, room for the zoom under it.
                if rows[s - 1].kind == .cards { line = min(line, OrbitHomeLayout.screenHeight - rows[s - 1].height - 60) }
                return line
            }
        ) { s, focused in
            if s == 0 {
                nativeHero
            } else if rows.indices.contains(s - 1) {
                let row = rows[s - 1]
                OrbitAppleTVRowView(row: row, box: leads.box(row.id), isCurrent: s == current,
                                    focused: focused,
                                    newIDs: newIDs(row.items, row: row.id),
                                    rankLine: { rankLine($0) },
                                    trailerURL: s == current && row.kind == .cards ? trailerURL(for: row.items.indices.contains(lead(of: row)) ? row.items[lead(of: row)] : nil) : nil,
                                    onTrailerFailure: { trailer.playbackFailed($0) },
                                    onTrailerEnded: { trailer.playbackFinished() },
                                    zoomSpace: zoomSpace,
                                    metaStore: metaStore,
                                    onEnter: { nativeEnter(s) }, onLeave: nativeLeave, onSelect: select,
                                    onLeadChange: { refreshAfterMove() })
            }
        }
    }

    /// The native hero: a carousel of buttons the system slides (Left / Right), as Orbit Home's.
    private var nativeHero: some View {
        let items = heroItems
        let line = OrbitAppleTVLayout.firstRowLine
        return ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button {
                        push(TitleRoute(preview: item))
                    } label: {
                        OrbitNativeAppleTVHeroPage(live: abs(index - heroIndex) <= 1, line: line) { lit in
                            OrbitAppleTVHero(item: item, meta: metaStore.meta(for: item), isNew: isNew(item), line: rankLine(item),
                                             buttonLit: lit,
                                             count: items.count, index: index,
                                             trailerURL: index == heroIndex && current == 0 ? trailerURL(for: item) : nil,
                                             onTrailerFailure: { trailer.playbackFailed($0) },
                                             onTrailerEnded: {
                                                 trailer.playbackFinished()
                                                 advanceHero()
                                             })
                        }
                    }
                    .buttonStyle(OrbitPlainStyle())
                    .focused($heroFocus, equals: index)
                    .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .onChange(of: heroFocus) { _, page in
            guard let page else {
                nativeHeroFocused = false
                nativeLeave()
                return
            }
            nativeHeroFocused = true
            if heroIndex != page { heroIndex = page }
            nativeEnter(0)
        }
        // The carousel's own clock (or a trailer's end) moves the page: the focus follows.
        .onChange(of: heroIndex) { _, page in
            if heroFocus != nil, heroFocus != page { heroFocus = page }
            // Steven (2026-10-28: the carousel's own clock showed an empty hero): with the focus
            // elsewhere, nothing scrolled the carousel — the page on screen went out of the live
            // ones and drew nothing. The carousel now follows the page itself.
            if heroFocus == nil {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) { proxy.scrollTo(page, anchor: .leading) }
            }
        }
        }
    }

    /// The line a focused row rests on (the row above half in view, its usual height).
    private func nativeBaseLine(_ rows: [OrbitAppleTVRow]) -> CGFloat {
        let L = OrbitAppleTVLayout.self
        let average = rows.isEmpty ? 0 : rows.map(\.height).reduce(0, +) / CGFloat(rows.count)
        return L.firstRowLine + average * L.aboveRowShows
    }

    private func nativeLine(_ rows: [OrbitAppleTVRow]) -> CGFloat {
        let L = OrbitAppleTVLayout.self
        let line = nativeBaseLine(rows)
        // Steven (device: a large card, focused and larger, touched the screen's bottom): a row of
        // large cards keeps its whole height on screen, room for the zoom under it.
        if let r = rowIndex(of: current), rows.indices.contains(r), rows[r].kind == .cards {
            return min(line, OrbitHomeLayout.screenHeight - rows[r].height - 60)
        }
        return line
    }

    /// The focus came into section `s` (a row's title, or the hero).
    private func nativeEnter(_ s: Int) {
        nativeFocusStamp = ProcessInfo.processInfo.systemUptime
        if !nativeHasFocus { nativeHasFocus = true }
        if current != s { withAnimation(.easeInOut(duration: 0.3)) { current = s } }
        // Steven (2026-10-29, video measured frame by frame: the page stopped a frame ~0.15 s into each
        // move down, then jumped): the page's work for the new row (trailer, look-ahead) redrew it in
        // the middle of the slide — it comes once the slide is over.
        let target = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { if current == target { refreshAfterMove() } }
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
                var start = first(of: row)
                if next < start { start = next }
                if next > start + row.visibleCount - 1 { start = next - row.visibleCount + 1 }
                withAnimation(reduceMotion ? nil : OrbitAppleTVLayout.horizontal) {
                    leads[row.id] = next
                    firsts[row.id] = start
                }
            }
        @unknown default:
            return
        }
        refreshAfterMove()
    }

    private func select() {
        covered = true
        trailer.reset(abortStages: true)
        if let focusedItem { push(TitleRoute(preview: focusedItem, zoom: zoomSpace != nil, platform: OrbitDetailPlatform(theme: .appletv))) }
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
            // Every title on screen (the focus moves along a still row now) and a little beyond.
            let start = first(of: row)
            metaItems += row.items.indices.filter { $0 >= start - 1 && $0 <= start + row.visibleCount + 2 }.map { row.items[$0] }
        }
        // The Top 10s' posters (TMDB's, Orbit's rank on them): all asked at once.
        metaItems += rows.filter { $0.kind == .top10 }.flatMap(\.items) // (their genre)
        OrbitMetaStore.shared.request(metaItems)

        trailer.reset()
        trailerKey = nil
        guard trailersOn, !covered, search == nil, UIAccessibility.isVideoAutoplayEnabled else { return }
        // The carousel's trailer; in a row of large cards, the focused card's (Steven: as in the app).
        var target: MetaPreview?
        if current == 0 {
            target = heroItem
        } else if let r = rowIndex(of: current), rows.indices.contains(r), rows[r].kind == .cards, pageFocused {
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

/// tvOS 26's background (Steven checked: fixed, whatever the title): a slate blue warming to brown,
/// from his videos of the app.
private struct OrbitAppleTVAmbient: View {
    let item: MetaPreview?
    let meta: OrbitMeta?

    var body: some View {
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        ZStack {
            LinearGradient(colors: [
                Color(red: 0.33, green: 0.31, blue: 0.25),
                Color(red: 0.25, green: 0.28, blue: 0.29),
                Color(red: 0.18, green: 0.23, blue: 0.30),
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.42, green: 0.47, blue: 0.48).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.45, y: 0.05), startRadius: 0, endRadius: 900)
            RadialGradient(colors: [Color(red: 0.36, green: 0.27, blue: 0.18).opacity(0.45), .clear],
                           center: UnitPoint(x: 0.0, y: 0.35), startRadius: 0, endRadius: 800)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        }
        .frame(width: W, height: H)
        .allowsHitTesting(false)
    }
}

/// " Série TV · Thriller · Drame  16".
private struct OrbitAppleTVLine: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    var size: CGFloat = 21

    var body: some View {
        HStack(spacing: size * 0.4) {
            // Steven's  tv mark in its little round badge, as in the app.
            Image("AppleTVMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.black)
                .frame(width: size * 0.95)
                .frame(width: size * 1.35, height: size * 1.35)
                .background(Circle().fill(Color.white.opacity(0.88)))
            Text(parts)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
            if let certification = meta?.certification, certification != "TP" {
                Text(certification)
                    .font(.system(size: size * 0.7, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
            }
        }
    }

    private var parts: String {
        var parts: [String] = [item.type == "movie" ? String(localized: "Film") : String(localized: "Série TV")]
        let genres = (meta?.genre.map { [$0] } ?? []) + item.genres
        var seen = Set<String>()
        parts += genres.filter { seen.insert($0).inserted }.prefix(2)
        return parts.joined(separator: " · ")
    }
}

/// The small glass capsule ("Nouveauté").
private struct OrbitAppleTVCapsule: View {
    let text: String
    var size: CGFloat = 18

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, size * 0.6)
            .padding(.vertical, size * 0.25)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
    }
}

/// The carousel: the art full screen (its trailer on a rest), the details on the left, the white
/// capsule button, the dots in the middle.
private struct OrbitAppleTVHero: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let isNew: Bool
    let line: String?
    let buttonLit: Bool
    let count: Int
    let index: Int
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let L = OrbitAppleTVLayout.self
        let size = CGSize(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
        let info = OrbitInfo.make(item, meta: meta)
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
                    .init(color: .black.opacity(0.7), location: 0),
                    .init(color: .black.opacity(0.3), location: 0.35),
                    .init(color: .clear, location: 0.6),
                ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.6),
                    .init(color: .black.opacity(0.55), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            VStack(alignment: .leading, spacing: 0) {
                // The TV app's words: a series' new season or episode first, "Bientôt" for what is
                // announced, else what came out lately.
                if let text = { () -> String? in
                    switch OrbitTitleNews.of(item, meta) {
                    case .newSeason: return String(localized: "Nouvelle saison")
                    case .newEpisodes: return String(localized: "Nouvel épisode")
                    case .soon: return String(localized: "Bientôt disponible")
                    case nil: return isNew ? (item.type == "movie" ? String(localized: "Nouveau film")
                                                                   : String(localized: "Nouvelle série")) : nil
                    }
                }() {
                    OrbitAppleTVCapsule(text: text)
                        .padding(.bottom, 16)
                }
                OrbitTitleMark(name: item.name, logo: info.logo, maxSize: L.logoSize, textSize: 66,
                               fallbackLogo: info.logoFallback, hugsLogo: true)
                    .frame(width: L.logoSize.width, alignment: .leading)
                OrbitAppleTVLine(item: item, meta: meta)
                    .padding(.top, 20)
                Text(info.synopsis)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineSpacing(4)
                    .lineLimit(3)
                    .frame(width: L.synopsisWidth, alignment: .topLeading)
                    .padding(.top, 14)
                if let line {
                    Text(line)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.top, 12)
                }
                HStack(spacing: 12) {
                    Image(systemName: "play.fill").font(.system(size: 20, weight: .bold))
                    Text(String(localized: "Regarder")).font(.system(size: 23, weight: .semibold))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 30)
                .frame(height: 60)
                .background(Capsule().fill(Color.white.opacity(buttonLit ? 1 : 0.85)))
                .shadow(color: .black.opacity(buttonLit ? 0.4 : 0), radius: 14, y: 6)
                .scaleEffect(buttonLit ? 1.08 : 1, anchor: .leading)
                .animation(.easeOut(duration: 0.18), value: buttonLit)
                .padding(.top, 24)
            }
            .frame(width: L.synopsisWidth, alignment: .topLeading)
            .offset(x: L.margin, y: L.infoTop)
            .id("\(item.type):\(item.id)-info")
            .transition(.opacity.animation(.easeInOut(duration: 0.3)))

            if count > 1 {
                HStack(spacing: 10) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(i == index ? 1 : 0.4))
                            .frame(width: i == index ? 22 : 8, height: 8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial))
                .animation(.easeInOut(duration: 0.3), value: index)
                .frame(width: size.width)
                .offset(y: L.rowsTopOnArrival - 64)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// A row: its heading, then its titles from the focused one (at the margin).
private struct OrbitAppleTVRowView: View {
    let row: OrbitAppleTVRow
    @ObservedObject var box: OrbitLeadBox
    let isCurrent: Bool
    let focused: Bool
    let newIDs: Set<String>
    let rankLine: (MetaPreview) -> String?
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void
    let zoomSpace: Namespace.ID?
    @ObservedObject var metaStore: OrbitMetaStore
    let onEnter: () -> Void
    let onLeave: () -> Void
    let onSelect: () -> Void
    let onLeadChange: () -> Void

    /// Half the focused title's growth, plus a little air.
    private var headingLift: CGFloat {
        row.kind == .cards ? OrbitAppleTVLayout.card.height * 0.03 + 10
                           : OrbitAppleTVLayout.poster.height * (OrbitAppleTVLayout.focusScale - 1) / 2 + 10
    }

    var body: some View {
        let L = OrbitAppleTVLayout.self
        let lead = min(box.lead, max(0, row.items.count - 1))
        VStack(alignment: .leading, spacing: 0) {
            Text(row.title)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isCurrent ? 1 : 0.8))
                .lineLimit(1)
                .frame(height: L.headingHeight, alignment: .topLeading)
                .padding(.leading, L.margin)
                // As in the app (Steven): the focused title under the heading grows, the heading
                // steps up out of its way, quickly, and comes back once it is no longer focused.
                // Only when the focused title is the first on screen, right under the heading.
                .offset(y: isCurrent && lead == 0 ? -headingLift : 0)
                .animation(.easeOut(duration: 0.16), value: isCurrent && lead == 0)
            // As in Apple's app (Steven): the row scrolls only once the focus would leave the screen.
            OrbitNativeTileStrip(count: row.items.count, spacing: row.slot - (row.kind == .cards ? L.card.width : L.poster.width),
                                 height: row.cardHeight, lastWidth: row.kind == .cards ? L.card.width : L.poster.width,
                                 box: box, alignment: .top, keepsLeadAtMargin: false,
                                 onEnter: onEnter, onLeave: onLeave, onSelect: onSelect,
                                 onLeadChange: { _ in onLeadChange() },
                                 redrawKey: AnyHashable([AnyHashable(trailerURL), AnyHashable(newIDs)])) { index, lit in
                let item = row.items[index]
                Group {
                    switch row.kind {
                    case .cards:
                        OrbitAppleTVCard(item: item, meta: metaStore.meta(for: item), isNew: newIDs.contains(item.id),
                                         line: rankLine(item), focused: lit,
                                         trailerURL: index == lead ? trailerURL : nil,
                                         onTrailerFailure: onTrailerFailure, onTrailerEnded: onTrailerEnded)
                    case .top10:
                        // (Steven: his add-on's image and its own rank; focused, its kind and genre in
                        // the lengthened foot, as the other rows.)
                        OrbitAppleTVPoster(url: item.poster, fallback: item.rawPosterUrl, focused: lit, mark: false,
                                           caption: orbitAppleTVGenre(item, metaStore.meta(for: item), withKind: true))
                    case .posters:
                        let meta = metaStore.meta(for: item)
                        // Steven (2026-10-27): TMDB's poster, Orbit's own  tv mark on Apple's productions
                        // (TMDB's producers) — not the add-on's printed one.
                        // (Steven: Apple's posters print their  tv already — no Orbit mark on them.)
                        // (Steven, Apple's app: focused, "Série TV · Drame" under its title.)
                        OrbitAppleTVPoster(url: meta?.localPoster ?? meta?.titledPoster ?? item.poster, fallback: item.rawPosterUrl,
                                           focused: lit, mark: false,
                                           caption: orbitAppleTVGenre(item, meta, withKind: true))
                    }
                }
                .modifier(OrbitAppleTVZoomSource(id: "\(item.type):\(item.id)", space: zoomSpace))
            }
            .frame(width: OrbitHomeLayout.screenWidth, height: row.cardHeight, alignment: .topLeading)
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
    }
}

/// A tall rounded poster ( tv in its corner, as in the app); focused, lifted larger with a light
/// rim (tvOS's focus, no frame).
private struct OrbitAppleTVPoster: View {
    let url: String?
    let fallback: String?
    let focused: Bool
    /// Off (Steven: Apple's own posters already print their  tv, it showed twice).
    var mark = false
    /// The Top 10's rank, drawn top left (nil: none, or printed on the image).
    var rank: Int? = nil
    /// The line under the title ("Drame", "Série TV · Drame"): always (Top 10) or when focused.
    var caption: String? = nil
    var captionAlways = false

    var body: some View {
        let L = OrbitAppleTVLayout.self
        // Steven (Apple's app): focused, the card grows a dark band under its art, its kind and genre
        // in it; the Top 10 says its genre on the art itself, under the title.
        let hasFoot = !captionAlways && caption != nil
        let foot: CGFloat = hasFoot && focused ? L.captionFoot : 0
        let total = CGSize(width: L.poster.width, height: L.poster.height + foot)
        ZStack(alignment: .bottom) {
            Color.white.opacity(0.08)
            // The art at the poster's size, its foot going on below it (the image stretched to the
            // taller box would crop it): the bottom rows of the art drawn again, darkened.
            VStack(spacing: 0) {
                OrbitImage(url: url, fallback: fallback, mode: .fill, size: L.poster)
                // (Always there, its height opening with the focus: Steven — the foot and its words
                // popped in and out on each move.)
                if hasFoot {
                    OrbitImage(url: url, fallback: fallback, mode: .fill, size: L.poster)
                        .scaleEffect(x: 1, y: -1)
                        .frame(width: L.poster.width, height: L.captionFoot, alignment: .top)
                        .clipped()
                        .blur(radius: 6)
                        .frame(width: L.poster.width, height: foot, alignment: .top)
                        .clipped()
                }
            }
            .frame(width: total.width, height: total.height, alignment: .top)
            if hasFoot, let caption {
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(height: L.captionFoot + 40)
                    .opacity(focused ? 1 : 0)
                Text(caption)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    // In once the foot is open; out at once.
                    .opacity(focused ? 1 : 0)
                    .animation(focused ? .easeOut(duration: 0.15).delay(0.12) : nil, value: focused)
            }
            if let rank {
                Text(String(rank))
                    .font(.system(size: L.poster.height * 0.15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.55), radius: 6, y: 2)
                    .padding(.leading, 12)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if mark {
                Image("AppleTVMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.white)
                    .frame(width: 34)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: total.width, height: total.height)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .modifier(OrbitAppleTVFocus(focused: focused))
        // Laid out at the poster's size (the row has room under it for the foot).
        .frame(width: L.poster.width, height: L.poster.height, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: foot)
    }
}

/// "Drame", or "Série TV · Drame" (Apple's words under a poster's title).
func orbitAppleTVGenre(_ item: MetaPreview, _ meta: OrbitMeta?, withKind: Bool) -> String? {
    let genre: String? = meta?.genre ?? item.genres.first
    let kind = item.type == "movie" ? String(localized: "Film") : String(localized: "Série TV")
    guard withKind else { return genre }
    return genre.map { "\(kind) · \($0)" } ?? kind
}

/// A large card: the art without its title (TMDB's textless poster, else the backdrop), the
/// capsule, the logo, the line and its rank over it.
private struct OrbitAppleTVCard: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let isNew: Bool
    let line: String?
    let focused: Bool
    var trailerURL: String? = nil
    var onTrailerFailure: (TrailerFailureReport) -> Void = { _ in }
    var onTrailerEnded: () -> Void = {}

    var body: some View {
        let L = OrbitAppleTVLayout.self
        let size = L.card
        let info = OrbitInfo.make(item, meta: meta)
        ZStack(alignment: .bottomLeading) {
            Color.white.opacity(0.08)
            OrbitImage(url: meta?.cleanPoster ?? item.banner ?? meta?.backdrop, fallback: item.poster, mode: .fill, size: size)
            if let trailerURL {
                // Its trailer after a rest, filling the card (as in the app).
                TrailerHeroPlayer(urlString: trailerURL, onFailure: onTrailerFailure,
                                  zoomKey: TrailerResolutionCache.key(type: item.type, id: item.id),
                                  loops: false, onPlaybackEnded: onTrailerEnded, cornerRadius: L.radius + 6)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity.animation(.easeOut(duration: 0.6)))
            }
            LinearGradient(stops: [
                .init(color: .clear, location: 0.45),
                .init(color: .black.opacity(0.75), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                if isNew {
                    OrbitAppleTVCapsule(text: item.type == "movie" ? String(localized: "Nouveau film")
                                                                   : String(localized: "Nouvelle série"), size: 16)
                }
                OrbitTitleMark(name: item.name, logo: info.logo, maxSize: CGSize(width: 340, height: 110), textSize: 38,
                               fallbackLogo: info.logoFallback, hugsLogo: true)
                    .frame(width: 340, alignment: .leading)
                OrbitAppleTVLine(item: item, meta: meta, size: 18)
                if let line {
                    Text(line)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
            .padding(24)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: L.radius + 6, style: .continuous))
        .modifier(OrbitAppleTVFocus(focused: focused, scale: 1.06))
    }
}

/// tvOS's focus: larger, a deep shadow, a thin light rim.
private struct OrbitAppleTVFocus: ViewModifier {
    let focused: Bool
    var scale: CGFloat = OrbitAppleTVLayout.focusScale

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: OrbitAppleTVLayout.radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(focused ? 0.7 : 0), Color.white.opacity(focused ? 0.1 : 0)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 2)
            }
            .shadow(color: .black.opacity(focused ? 0.55 : 0.25), radius: focused ? 24 : 8, y: focused ? 16 : 4)
            .scaleEffect(focused ? scale : 1)
            // (Steven, device: the focused tile rose before the others — its focus follows the move's own curve.)
    }
}

/// A poster the detail page grows out of (tvOS's zoom), when the page has the namespace.
private struct OrbitAppleTVZoomSource: ViewModifier {
    let id: String
    let space: Namespace.ID?

    func body(content: Content) -> some View {
        if let space {
            content.matchedTransitionSource(id: id, in: space)
        } else {
            content
        }
    }
}


/// One page of the native Apple TV hero: the full-screen hero drawn from the screen's top (above
/// the section's own frame), lit as its button is; empty while far from the shown one.
private struct OrbitNativeAppleTVHeroPage<Content: View>: View {
    let live: Bool
    let line: CGFloat
    @ViewBuilder let content: (Bool) -> Content
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        ZStack(alignment: .top) {
            if live {
                content(isFocused)
                    .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
                    .offset(y: -line)
            } else {
                Color.clear
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitAppleTVLayout.rowsTopOnArrival - line, alignment: .top)
    }
}
