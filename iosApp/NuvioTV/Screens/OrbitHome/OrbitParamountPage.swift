import Combine
import SharedCore
import SwiftUI

// Orbit × Paramount+ (Steven, 2026-10-25: a video of the 2026 TV app). Orbit's DNA kept (one
// focusable canvas; the house and the platform's pill top left; the intro; trailers on a rest).
//
//  - Paramount+'s near black. The top of the screen always shows a title: the new titles in turn on
//    arrival (its trailer on a rest), then the focused one once in the rows — its art on the right
//    fading to the left and down, "Paramount+ ORIGINAL" above the logo on its own, the small capitals
//    line (genre · seasons · year · age), the green line ("NOUVEAUTÉ", "N° 3 DU TOP 10"), three lines
//    of synopsis; on arrival, the blue "▶ REGARDER" button.
//  - The rows: tall posters packed close, the focused one larger (no frame, as on the app); his Top
//    10 images (the big white rank above the poster's corner).

enum OrbitParamountLayout {
    static let background = Color(red: 0.055, green: 0.06, blue: 0.07)
    static let blue = Color(red: 0.0, green: 0.39, blue: 1.0)
    static let green = Color(red: 0.30, green: 0.84, blue: 0.45)
    static let margin: CGFloat = OrbitHomeLayout.margin
    static let artHeight: CGFloat = 820
    static let infoTop: CGFloat = 150
    static let logoSize = CGSize(width: 560, height: 180)
    static let synopsisWidth: CGFloat = 780
    /// The first row on arrival.
    static let rowsTopOnArrival: CGFloat = 700
    /// Once in the rows: the current row's top (the title's details stay above it).
    static let rowLine: CGFloat = 540
    static let headingHeight: CGFloat = 50
    static let poster = CGSize(width: 214, height: 321)
    /// His Top 10 images: 640 × 920, the poster 500 × 750 in their bottom right, the rank above its corner.
    static var top10Image: CGSize { CGSize(width: poster.height / 750 * 640, height: poster.height / 750 * 920) }
    static var top10Above: CGFloat { top10Image.height - poster.height }
    static let gap: CGFloat = 12
    static let rowGap: CGFloat = 44
    static let radius: CGFloat = 8
    static let focusScale: CGFloat = 1.12
    static let horizontal = Animation.easeOut(duration: 0.22)
    static let vertical = Animation.easeInOut(duration: 0.38)
}

struct OrbitParamountRow: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [MetaPreview]
    let top10: Bool

    static func == (a: OrbitParamountRow, b: OrbitParamountRow) -> Bool {
        a.id == b.id && a.top10 == b.top10 && a.items.map(\.id) == b.items.map(\.id)
    }

    var cardHeight: CGFloat { top10 ? OrbitParamountLayout.top10Image.height : OrbitParamountLayout.poster.height }
    /// Steven: the ranks ran over the heading; the Top 10 keeps room between them (its focused
    /// title grows upwards too).
    var headingHeight: CGFloat { OrbitParamountLayout.headingHeight + (top10 ? 46 : 0) }
    var height: CGFloat { headingHeight + cardHeight + OrbitParamountLayout.rowGap }
    var slot: CGFloat {
        (top10 ? OrbitParamountLayout.top10Image.width : OrbitParamountLayout.poster.width) + OrbitParamountLayout.gap
    }
}

/// Paramount+'s own title: Steven's add-on marks it in its image address ("/img/v…/tv/123/o0/…").
func orbitParamountIsOwn(_ item: MetaPreview) -> Bool {
    let poster: String = item.poster ?? ""
    return poster.range(of: #"/img/v\d+/(movie|tv)/\d+/o"#, options: .regularExpression) != nil
}

struct OrbitParamountPage: View {
    let route: FolderRoute
    let push: (TitleRoute) -> Void

    static func handles(_ route: FolderRoute) -> Bool {
        let t = route.folderTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        return t.contains("paramount")
    }

    @StateObject private var model: FolderDetailViewModel
    @StateObject private var extras = OrbitPlatformExtrasModel()
    @StateObject private var trailer = OrbitNativeTrailerHost()
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true

    /// nil: Accueil; "movie"; "series".
    @State private var typeFilter: String? = nil
    /// 0: the arrival (the new titles in turn); then the rows.
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

    /// His Nouveautés, Paramount+'s own, his Top 10, then the genres (TMDB).
    private var rows: [OrbitParamountRow] {
        let extraRows: [OrbitPlatformExtrasModel.Extra] = switch typeFilter {
        case "movie"?: extras.movieRows
        case "series"?: extras.seriesRows
        default: Self.alternate(extras.movieRows, extras.seriesRows)
        }
        let all = catalogs
        var out: [OrbitParamountRow] = []
        for c in all where c.fresh {
            out.append(OrbitParamountRow(id: c.id, title: c.heading, items: c.items, top10: false))
        }
        var seen = Set(out.flatMap { $0.items.map(Self.identity) })
        let own = all.filter { !$0.top10 }.flatMap(\.items)
            .filter { orbitParamountIsOwn($0) && seen.insert(Self.identity($0)).inserted }
        if own.count >= 4 {
            out.append(OrbitParamountRow(id: "pplus-originals-\(typeFilter ?? "all")",
                                         title: String(localized: "Paramount+ Originals"), items: Array(own.prefix(20)), top10: false))
        }
        for c in all where c.top10 {
            let isSeries = c.heading.lowercased().contains("série") || c.items.first.map { $0.type != "movie" } == true
            out.append(OrbitParamountRow(id: c.id,
                                         title: isSeries ? String(localized: "Top 10 des séries") : String(localized: "Top 10 des films"),
                                         items: Array(c.items.prefix(10)), top10: true))
        }
        if extraRows.isEmpty {
            for c in all where !c.fresh && !c.top10 {
                out.append(OrbitParamountRow(id: c.id, title: c.heading, items: c.items, top10: false))
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
                out[i] = OrbitParamountRow(id: row.id, title: row.title, items: Self.alternate(row.items, kept), top10: false)
            } else {
                merged[extra.title] = out.count
                out.append(OrbitParamountRow(id: extra.id, title: extra.title, items: kept, top10: false))
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
        // Fiction first, documentaries after (as on HBO Max).
        let withArt = items.filter { $0.banner != nil }
        let isDoc: (MetaPreview) -> Bool = { item in item.genres.contains { $0.hasPrefix("Documentaire") } }
        return Array((withArt.filter { !isDoc($0) } + withArt.filter(isDoc)).prefix(6))
    }

    private var heroItem: MetaPreview? {
        let items = heroItems
        return items.isEmpty ? nil : items[min(heroIndex, items.count - 1)]
    }

    private func topRank(_ item: MetaPreview) -> Int? {
        for top in catalogs where top.top10 {
            if let i = top.items.prefix(10).firstIndex(where: { Self.identity($0) == Self.identity(item) }) { return i + 1 }
        }
        return nil
    }

    /// The green line: its Top 10 rank, else "NOUVEAUTÉ" for a new title.
    private func greenLine(_ item: MetaPreview) -> String? {
        if let rank = topRank(item) {
            return item.type == "movie" ? String(localized: "N° \(String(rank)) DU TOP 10 DES FILMS")
                                        : String(localized: "N° \(String(rank)) DU TOP 10 DES SÉRIES")
        }
        guard isNew(item) else { return nil }
        return item.type == "movie" ? String(localized: "NOUVEAU FILM") : String(localized: "NOUVELLE SÉRIE")
    }

    private var sectionCount: Int { 1 + rows.count }

    private func rowIndex(of section: Int) -> Int? { section >= 1 ? section - 1 : nil }

    private func rowTops(_ rows: [OrbitParamountRow]) -> [CGFloat] {
        var y = OrbitParamountLayout.rowsTopOnArrival
        return rows.map { row in defer { y += row.height }; return y }
    }

    /// None on arrival, else the current row at its line (a Top 10's ranks above its line).
    private func scroll(_ rows: [OrbitParamountRow]) -> CGFloat {
        guard let r = rowIndex(of: current), rows.indices.contains(r) else { return 0 }
        let line = OrbitParamountLayout.rowLine - (rows[r].top10 ? OrbitParamountLayout.top10Above * 0.6 : 0)
        return rowTops(rows)[r] - line
    }

    private func lead(of row: OrbitParamountRow) -> Int {
        min(leads[row.id] ?? 0, max(0, row.items.count - 1))
    }

    /// The title the top of the screen shows: the arrival's on arrival, else the focused one.
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

        ZStack(alignment: .topLeading) {
            OrbitParamountLayout.background

            // (Native: the top follows the current row's own lead box — a press in a row redraws it.)
            OrbitLeadReader(box: leads.box(rowIndex(of: current).flatMap { rows.indices.contains($0) ? rows[$0].id : nil } ?? "-")) { _ in
            if let shown = shownItem {
                OrbitParamountTop(item: shown, meta: metaStore.meta(for: shown), line: greenLine(shown),
                                  onArrival: onArrival, buttonLit: pageFocused && onArrival,
                                  count: heroItems.count, index: min(heroIndex, max(0, heroItems.count - 1)),
                                  trailerURL: onArrival ? trailerURL(for: shown) : nil,
                                  onTrailerFailure: { trailer.playbackFailed($0) },
                                  onTrailerEnded: {
                                      trailer.playbackFinished()
                                      advanceHero()
                                  })
            }
            }

                            nativeSections(rows)
                    .disabled(search != nil)
            

            if rows.isEmpty, model.isLoading {
                ProgressView().frame(width: W, height: H)
            }


            CollectionFilterBar(filter: $typeFilter, onSearch: openSearch, showsAll: true)
                .disabled(search != nil || (pageFocused && current > 0))
                .opacity(search != nil ? 0 : 1)

            OrbitPlatformIntro(title: model.folderTitle, logoUrl: model.titleLogoUrl ?? route.titleLogoUrl,
                               brand: OrbitParamountLayout.blue, white: true)

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
        .background(OrbitParamountLayout.background)
        .ignoresSafeArea()
        .background { ViewerInputClockInstaller().frame(width: 0, height: 0) }
        .animation(.easeInOut(duration: 0.25), value: onArrival)
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
            leads.reset()
            refreshAfterMove()
        }
    }

    /// The native page: the sections (an invisible stop for the hero, whose art stays behind, then
    /// the rows drawn as before) as real buttons the system moves.
    private func nativeSections(_ rows: [OrbitParamountRow]) -> some View {
        OrbitNativeSections(
            count: 1 + rows.count, hasHero: true,
            height: { s in s == 0 ? OrbitParamountLayout.rowsTopOnArrival - OrbitParamountLayout.rowLine : (rows.indices.contains(s - 1) ? rows[s - 1].height : 0) },
            topLine: OrbitParamountLayout.rowLine, current: current, hidesAbove: true,
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
            line: { s in
                guard s >= 1, rows.indices.contains(s - 1) else { return OrbitParamountLayout.rowLine }
                return OrbitParamountLayout.rowLine - (rows[s - 1].top10 ? OrbitParamountLayout.top10Above * 0.6 : 0)
            }
        ) { s, focused in
            if s == 0 {
                Color.clear
            } else if rows.indices.contains(s - 1) {
                let row = rows[s - 1]
                OrbitParamountRowView(row: row, box: leads.box(row.id), isCurrent: s == current,
                                      focused: focused,
                                      news: freshRowIDs.contains(row.id) ? [] : Set(row.items.filter(isNew).map(\.id)),
                                      metaStore: metaStore,
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
            withAnimation(reduceMotion ? nil : OrbitParamountLayout.vertical) { current += 1 }
        case .up:
            guard current > 0 else { return }
            withAnimation(reduceMotion ? nil : OrbitParamountLayout.vertical) { current -= 1 }
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
                withAnimation(reduceMotion ? nil : OrbitParamountLayout.horizontal) { leads[row.id] = next }
            }
        @unknown default:
            return
        }
        refreshAfterMove()
    }

    /// The detail page's Paramount+ touch.
    private func detailPlatform(_ item: MetaPreview) -> OrbitDetailPlatform {
        OrbitDetailPlatform(theme: .paramount, own: orbitParamountIsOwn(item) ? .paramount : nil,
                            logoUrl: model.titleLogoUrl ?? route.titleLogoUrl)
    }

    private func select() {
        if let shownItem { push(TitleRoute(preview: shownItem, platform: detailPlatform(shownItem))) }
    }

    private func exitAction() -> (() -> Void)? {
        guard current > 0 else { return nil }
        return {
            withAnimation(reduceMotion ? nil : OrbitParamountLayout.vertical) { current = 0 }
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
        for i in r...max(r, min(rows.count - 1, r + 2)) where rows.indices.contains(i) {
            let row = rows[i]
            let lead = lead(of: row)
            metaItems += row.items.indices.filter { $0 >= lead - 1 && $0 <= lead + 9 }.map { row.items[$0] }
        }
        OrbitMetaStore.shared.request(metaItems)

        trailer.reset()
        trailerKey = nil
        // The arrival's trailer plays whether or not it has the focus (the bar can).
        guard trailersOn, search == nil, current == 0, UIAccessibility.isVideoAutoplayEnabled,
              let item = heroItem else { return }
        trailer.prefersReducedMotion = reduceMotion
        trailer.restSource = .custom(motion)
        trailerKey = "\(item.type):\(item.id)"
        trailer.focusChanged(true, item: item)
    }
}

// MARK: - Pieces

/// The top of the screen: a title's art on the right (its trailer on a rest), its details on the
/// left; on arrival, the blue button and the dots.
private struct OrbitParamountTop: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let line: String?
    let onArrival: Bool
    let buttonLit: Bool
    let count: Int
    let index: Int
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    /// "DRAME · 4 SAISONS · 2022 · 16+": the app's small capitals line.
    private var capitals: String {
        var parts: [String] = []
        if let genre = meta?.genre ?? item.genres.first { parts.append(genre) }
        if let seasons = meta?.seasons, item.type != "movie" {
            parts.append(seasons > 1 ? String(localized: "\(seasons) SAISONS") : String(localized: "1 SAISON"))
        } else if let runtime = meta?.runtime {
            parts.append(runtime)
        }
        if let year = meta?.year ?? item.releaseInfo.flatMap({ $0.isEmpty ? nil : String($0.prefix(4)) }) { parts.append(year) }
        if let certification = meta?.certification {
            parts.append(certification == "TP" ? String(localized: "TOUS PUBLICS") : "\(certification)+")
        }
        return parts.joined(separator: "   ").uppercased()
    }

    var body: some View {
        let L = OrbitParamountLayout.self
        let size = CGSize(width: OrbitHomeLayout.screenWidth, height: L.artHeight)
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
                    .init(color: L.background, location: 0),
                    .init(color: L.background.opacity(0.75), location: 0.3),
                    .init(color: .clear, location: 0.6),
                ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: L.background.opacity(0.85), location: 0.72),
                    .init(color: L.background, location: 0.86),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            VStack(alignment: .leading, spacing: 0) {
                if orbitParamountIsOwn(item) {
                    Image("ParamountOriginal")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 46)
                        .foregroundStyle(Color.white)
                        .padding(.bottom, 14)
                }
                OrbitTitleMark(name: item.name, logo: info.logo, maxSize: onArrival ? L.logoSize : CGSize(width: 440, height: 130),
                               textSize: onArrival ? 64 : 48, fallbackLogo: info.logoFallback, hugsLogo: true)
                    .frame(width: L.logoSize.width, alignment: .leading)
                Text(capitals)
                    .font(.system(size: 17, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .padding(.top, 22)
                if let line {
                    Text(line)
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(L.green)
                        .padding(.top, 10)
                }
                Text(info.synopsis)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineSpacing(4)
                    .lineLimit(3)
                    .frame(width: L.synopsisWidth, alignment: .topLeading)
                    .padding(.top, 10)
                if onArrival {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill").font(.system(size: 20, weight: .bold))
                        Text(String(localized: "REGARDER")).font(.system(size: 21, weight: .heavy))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 26)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(L.blue))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(buttonLit ? 0.9 : 0), lineWidth: 3))
                    .scaleEffect(buttonLit ? 1.06 : 1, anchor: .leading)
                    .animation(.easeOut(duration: 0.18), value: buttonLit)
                    .padding(.top, 24)
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
                        Capsule()
                            .fill(Color.white.opacity(i == index ? 1 : 0.35))
                            .frame(width: i == index ? 22 : 8, height: 8)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: index)
                .frame(width: size.width)
                .offset(y: L.rowsTopOnArrival - 44)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// A row: its heading, then its titles from the focused one (at the margin).
private struct OrbitParamountRowView: View {
    let row: OrbitParamountRow
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
        let L = OrbitParamountLayout.self
        VStack(alignment: .leading, spacing: 0) {
            Text(row.title)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(Color.white.opacity(isCurrent ? 1 : 0.8))
                .lineLimit(1)
                .frame(height: row.headingHeight, alignment: .topLeading)
                .padding(.leading, L.margin)
            OrbitNativeTileStrip(count: row.items.count, spacing: L.gap, height: row.cardHeight,
                                 lastWidth: row.slot - L.gap, box: box, alignment: .top,
                                 onEnter: onEnter, onLeave: onLeave, onSelect: onSelect,
                                 onLeadChange: { _ in onLeadChange() }) { index, lit in
                let item = row.items[index]
                if row.top10 {
                    OrbitParamountTop10Image(item: item, focused: lit)
                } else {
                    OrbitParamountPoster(item: item, meta: metaStore.meta(for: item),
                                         isNew: news.contains(item.id), focused: lit)
                }
            }
            .frame(width: OrbitHomeLayout.screenWidth, height: row.cardHeight, alignment: .topLeading)
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
    }
}

/// The small blue tag top left ("NOUVEAU").
private struct OrbitParamountNewTag: View {
    var body: some View {
        Text(String(localized: "NOUVEAU"))
            .font(.system(size: 12, weight: .heavy))
            .kerning(0.5)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(OrbitParamountLayout.blue))
    }
}

/// A tall poster: Paramount+'s own keep his add-on's poster (its "Paramount+ ORIGINAL" mark), the
/// others TMDB's French one when it has one; focused, larger (the app has no frame).
private struct OrbitParamountPoster: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let isNew: Bool
    let focused: Bool

    var body: some View {
        let L = OrbitParamountLayout.self
        let size = L.poster
        // His add-on no longer adds a mark: the French poster for all when TMDB has one.
        let url: String? = meta?.localPoster ?? item.poster
        ZStack(alignment: .topLeading) {
            Color(white: 0.12)
            OrbitImage(url: url, fallback: item.rawPosterUrl, mode: .fill, size: size)
            if isNew {
                OrbitParamountNewTag().padding(7)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: L.radius, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 0.35 : 0), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(focused ? 0.7 : 0.3), radius: focused ? 20 : 6, y: focused ? 10 : 3)
        .scaleEffect(focused ? L.focusScale : 1, anchor: .leading)
        // (Steven, device: the focused tile rose before the others — its focus follows the move's own curve.)
    }
}

/// His Top 10 image as it is (the big white rank above the poster's corner); focused, larger.
private struct OrbitParamountTop10Image: View {
    let item: MetaPreview
    let focused: Bool

    var body: some View {
        let L = OrbitParamountLayout.self
        let k = L.top10Image.width / 640
        OrbitImage(url: item.poster, fallback: item.rawPosterUrl, mode: .fit, size: L.top10Image)
            .frame(width: L.top10Image.width, height: L.top10Image.height)
            // Steven (the focused title hardly stood out): a white frame around its poster only.
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14 * k, style: .continuous)
                    .strokeBorder(Color.white.opacity(focused ? 0.95 : 0), lineWidth: 3)
                    .frame(width: 500 * k, height: 750 * k)
                    .offset(x: 140 * k, y: 170 * k)
            }
            .shadow(color: .black.opacity(focused ? 0.7 : 0.3), radius: focused ? 20 : 6, y: focused ? 10 : 3)
            // No growth (Steven: the focused rank rose above the others): the frame shows it.
            // (Steven, device: the focused tile rose before the others — its focus follows the move's own curve.)
    }
}
