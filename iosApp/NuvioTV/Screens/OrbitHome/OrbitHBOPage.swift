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

    static func == (a: OrbitHBORow, b: OrbitHBORow) -> Bool {
        a.id == b.id && a.top10 == b.top10 && a.wide == b.wide && a.items.map(\.id) == b.items.map(\.id)
    }

    var cardHeight: CGFloat { wide ? OrbitHBOLayout.tile.height : OrbitHBOLayout.poster.height }
    var headingHeight: CGFloat { top10 ? OrbitHBOLayout.top10HeadingHeight : OrbitHBOLayout.headingHeight }
    var height: CGFloat { headingHeight + cardHeight + OrbitHBOLayout.rowGap }

    private func rankWidth(_ index: Int) -> CGFloat {
        guard top10 else { return 0 }
        return (index == 9 ? OrbitHBOLayout.rankWidthTen : OrbitHBOLayout.rankWidth) - OrbitHBOLayout.rankUnderPoster
    }

    func slot(_ index: Int) -> CGFloat {
        let L = OrbitHBOLayout.self
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
    @StateObject private var trailer = InlineTrailerCardModel()
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true

    /// nil: Accueil; "movie"; "series".
    @State private var typeFilter: String? = nil
    /// 0: the carousel; then the rows.
    @State private var current = 0
    @State private var heroIndex = 0
    @State private var leads: [String: Int] = [:]
    @FocusState private var canvasFocused: Bool
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

    private var catalogs: [Catalog] {
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
        let fresh = catalogs.filter(\.fresh).map(\.items)
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
                             buttonLit: canvasFocused && onArrival,
                             count: heroItems.count, index: min(heroIndex, max(0, heroItems.count - 1)),
                             trailerURL: onArrival ? trailerURL(for: hero) : nil,
                             onTrailerFailure: { trailer.playbackFailed($0) },
                             onTrailerEnded: {
                                 trailer.playbackFinished()
                                 advanceHero()
                             })
                    .offset(y: -offset)
                    .opacity(onArrival ? 1 : 0)
            }

            rowsLayer(rows)
                .offset(y: -offset)

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

            Button(action: select) {
                Color.clear
                    .frame(width: W, height: H - 110)
                    .contentShape(Rectangle())
            }
            .buttonStyle(OrbitHBOCanvasStyle())
            .focused($canvasFocused)
            .onMoveCommand(perform: move)
            .onExitCommand(perform: exitAction())
            .offset(y: 110)
            .disabled(search != nil)

            CollectionFilterBar(filter: $typeFilter, onSearch: openSearch, showsAll: true, showsHBO: true)
                .disabled(search != nil || (canvasFocused && current > 0))
                .opacity(search != nil ? 0 : 1)

            OrbitPlatformIntro(title: model.folderTitle, logoUrl: model.titleLogoUrl ?? route.titleLogoUrl,
                               brand: OrbitHBOLayout.blue)

            if let search {
                OrbitPlatformSearchLayer(model: search, platform: model.folderTitle,
                                         onOpen: { push(TitleRoute(preview: $0)) },
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
        .animation(.easeInOut(duration: 0.3), value: onArrival)
        .onAppear {
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
            leads = [:]
            refreshAfterMove()
        }
    }

    @ViewBuilder
    private func rowsLayer(_ rows: [OrbitHBORow]) -> some View {
        let tops = rowTops(rows)
        let currentRow = rowIndex(of: current) ?? -1
        // The row above stays in view over the current one.
        let low = max(0, currentRow - 1)
        let high = min(rows.count - 1, max(currentRow, 0) + 3)
        ZStack(alignment: .topLeading) {
            if low <= high {
                ForEach(low...high, id: \.self) { i in
                    let row = rows[i]
                    OrbitHBORowView(row: row, lead: lead(of: row), isCurrent: i == currentRow,
                                    focused: canvasFocused && i == currentRow,
                                    // Not on the Nouveautés rows themselves (every poster said it).
                                    news: freshRowIDs.contains(row.id) ? [] : Set(row.items.filter(isNew).map(\.id)),
                                    metaStore: metaStore)
                        .offset(y: tops[i])
                        .id(row.id)
                        .transition(.identity)
                }
            }
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

    private func select() {
        if let focusedItem { push(TitleRoute(preview: focusedItem)) }
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
        guard trailersOn, search == nil, current == 0, UIAccessibility.isVideoAutoplayEnabled,
              let item = heroItem else { return }
        trailer.prefersReducedMotion = reduceMotion
        trailer.restSource = .custom(motion)
        trailerKey = "\(item.type):\(item.id)"
        trailer.focusChanged(true, item: item)
    }
}

private struct OrbitHBOCanvasStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

// MARK: - Pieces

/// "HBO ORIGINAL" / "HBO MAX ORIGINAL" above a title's logo.
private struct OrbitHBOMark: View {
    let own: OrbitHBOOwn
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: size * 0.4) {
            Text(own == .hbo ? "HBO" : "HBO max")
                .font(.system(size: size * 1.15, weight: .black))
            Text(String(localized: "ORIGINAL"))
                .font(.system(size: size * 0.8, weight: .semibold))
                .kerning(size * 0.3)
        }
        .foregroundStyle(Color.white)
        .shadow(color: .black.opacity(0.5), radius: 4)
    }
}

/// The blue "NOUVEAU" tag.
private struct OrbitHBONewTag: View {
    var size: CGFloat = 15

    var body: some View {
        Text(String(localized: "NOUVEAU"))
            .font(.system(size: size, weight: .heavy))
            .kerning(size * 0.06)
            .foregroundStyle(Color.white)
            .padding(.horizontal, size * 0.45)
            .padding(.vertical, size * 0.18)
            .background(RoundedRectangle(cornerRadius: 3).fill(OrbitHBOLayout.blue))
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
        let own = OrbitHBOOwn.of(item)
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
                    if isNew { OrbitHBONewTag() }
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
                Text(item.type == "movie" ? String(localized: "Voir le film") : String(localized: "Voir la série"))
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
    let lead: Int
    let isCurrent: Bool
    let focused: Bool
    let news: Set<String>
    @ObservedObject var metaStore: OrbitMetaStore

    var body: some View {
        let L = OrbitHBOLayout.self
        let low = max(0, lead - 1)
        let window = low...max(low, min(row.items.count - 1, lead + 8))
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
            ZStack(alignment: .topLeading) {
                if !row.items.isEmpty {
                    ForEach(Array(zip(window, row.items[window])), id: \.1.id) { index, item in
                        let lit = focused && index == lead
                        Group {
                            if row.top10 {
                                OrbitHBOTop10Card(item: item, meta: metaStore.meta(for: item), rank: index + 1, focused: lit)
                            } else if row.wide {
                                OrbitHBOTile(item: item, meta: metaStore.meta(for: item),
                                             isNew: news.contains(item.id), focused: lit)
                            } else {
                                OrbitHBOPoster(item: item, meta: metaStore.meta(for: item),
                                               isNew: news.contains(item.id), focused: lit)
                            }
                        }
                        .offset(x: L.margin + row.x(of: index, lead: lead))
                        .opacity(index < lead ? 0 : 1)
                        .zIndex(lit ? 1 : 0)
                    }
                }
            }
            .frame(width: OrbitHomeLayout.screenWidth, height: row.cardHeight, alignment: .topLeading)
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
        .opacity(isCurrent || focused ? 1 : 0.85)
        .allowsHitTesting(false)
    }
}

/// HBO Max's Top 10 heading (2026, Steven's screenshot): "TOP 10" in dark glass with a silver rim,
/// "DES SÉRIES" / "DU JOUR" beside it.
private struct OrbitHBOTop10Heading: View {
    let series: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            OrbitHBOGlassText(text: "TOP 10", size: 80, filled: false)
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

    var body: some View {
        let font = Font.system(size: size, weight: .medium)
        let w = max(1.5, size * 0.022)
        let offsets: [CGSize] = (0..<16).map { i in
            let a = Double(i) / 16 * 2 * .pi
            return CGSize(width: cos(a) * w, height: sin(a) * w)
        }
        let rim = LinearGradient(colors: [Color(white: 0.97), Color(white: 0.55), Color(white: 0.3), Color(white: 0.85)],
                                 startPoint: .bottomLeading, endPoint: .topTrailing)
        let glass = LinearGradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.06), Color(red: 0.15, green: 0.17, blue: 0.24)],
                                   startPoint: .top, endPoint: .bottom)
        let lit = LinearGradient(colors: [Color.white, Color(white: 0.78)], startPoint: .top, endPoint: .bottom)
        ZStack {
            ForEach(offsets.indices, id: \.self) { i in
                Text(text).font(font).foregroundStyle(rim).offset(offsets[i])
            }
            Text(text).font(font).foregroundStyle(filled ? AnyShapeStyle(lit) : AnyShapeStyle(glass))
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
        .fixedSize()
        .animation(.easeOut(duration: 0.2), value: filled)
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
                .offset(y: L.poster.height * 0.1)
            ZStack {
                Color(red: 0.08, green: 0.10, blue: 0.20)
                if let poster {
                    OrbitImage(url: poster, fallback: nil, mode: .fill, size: L.poster)
                }
            }
            .frame(width: L.poster.width, height: L.poster.height)
            .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
            .modifier(OrbitHBOFocus(focused: focused))
            .offset(x: rankW - L.rankUnderPoster)
        }
        .frame(width: rankW - L.rankUnderPoster + L.poster.width, height: L.poster.height, alignment: .bottomLeading)
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
            OrbitImage(url: item.banner ?? meta?.backdrop, fallback: nil, size: size)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            OrbitTitleMark(name: item.name, logo: info.logo,
                           maxSize: CGSize(width: size.width * 0.55, height: size.height * 0.4), textSize: 26,
                           fallbackLogo: info.logoFallback)
                .padding(.leading, 16)
                .padding(.bottom, 14)
            if isNew {
                OrbitHBONewTag(size: 13)
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
        let url: String? = ranked ? (meta?.titledPoster ?? meta?.localPoster)
            : OrbitHBOOwn.of(item) != nil && !OrbitHBOOwn.isPlain(item) ? item.poster : (meta?.localPoster ?? item.poster)
        ZStack(alignment: .topLeading) {
            Color(red: 0.08, green: 0.10, blue: 0.20)
            if let url { OrbitImage(url: url, fallback: ranked ? nil : item.rawPosterUrl, mode: .fill, size: size) }
            if isNew {
                OrbitHBONewTag(size: 13)
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
            .animation(.easeOut(duration: 0.18), value: focused)
    }
}
