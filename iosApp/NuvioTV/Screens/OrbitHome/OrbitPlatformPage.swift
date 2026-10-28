import Combine
import SharedCore
import SwiftUI

// Orbit Plateformes — inside a platform (Steven, 2026-10-24): the page a platform (or a studio)
// folder opens on, rebuilt from scratch in the Orbit style, laid out like the platforms' own apps:
//
//  - The focused title fills the screen (its backdrop, then its trailer after a rest), with its
//    logo, Orbit's meta line and three lines of synopsis at the top left.
//  - The rows at the bottom: the current one in full, the next one's heading peeking under it;
//    Down / Up go from row to row, Left / Right along it (the focused card stays at the margin).
//  - Cards keep the add-on's own art: its shape (Prime Video's and Paramount+'s landscape tiles
//    stay landscape) and, on the Top 10 rows, Steven's transparent images drawn as they are (no
//    background, no frame, no clipping: they carry their own big numbers).
//  - The intro: the platform's logo large on a screen tinted with its colour, gliding to the
//    top-right corner. Any press skips it. The page keeps the platform's colour.
//  - Top-left, the platform's own bar: Search (inside the platform only), Films, Séries.
//  - After the folder's catalogs: the platform's franchises (Disney+: Marvel, Star Wars, Pixar)
//    and its genres (TMDB, only what is on the platform in the viewer's region).
//
// The data is the folder's (`FolderDetailViewModel`, the collection's catalogs); everything drawn
// is new. One focusable canvas (Orbit Home's way): the page moves, the focus stays.

/// One row of the platform page.
struct OrbitPlatformRow: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [MetaPreview]
    /// The add-on's art shape for the row (its first title's).
    let shape: PosterShape
    /// Steven's Top 10 rows: transparent images drawn as they are.
    let transparent: Bool

    static func == (a: OrbitPlatformRow, b: OrbitPlatformRow) -> Bool {
        a.id == b.id && a.items.map(\.id) == b.items.map(\.id) && a.shape == b.shape && a.transparent == b.transparent
    }

    var cardSize: CGSize {
        let L = OrbitPlatformLayout.self
        // Steven (2026-10-25): his Top 10 images, much larger than the other rows, so they stand out.
        if transparent {
            let height = L.posterHeight * L.top10Scale
            return shape == .landscape ? CGSize(width: height * 16 / 9, height: height)
                                       : CGSize(width: height * 2 / 3, height: height)
        }
        switch shape {
        case .landscape: return CGSize(width: L.landscapeHeight * 16 / 9, height: L.landscapeHeight)
        case .square: return CGSize(width: L.squareSide, height: L.squareSide)
        default: return CGSize(width: L.posterHeight * 2 / 3, height: L.posterHeight)
        }
    }

    /// From the heading's centre to the next row's heading centre.
    var pitch: CGFloat { OrbitPlatformLayout.cardsTop + cardSize.height + OrbitPlatformLayout.rowGap }
}

enum OrbitPlatformLayout {
    static let margin: CGFloat = OrbitHomeLayout.margin
    /// The info block: logo top, its widths.
    static let infoTop: CGFloat = 150
    static let logoSize = CGSize(width: 640, height: 190)
    static let synopsisWidth: CGFloat = 900
    /// The current row's heading centre on screen.
    static let rowLine: CGFloat = 610
    /// From a heading's centre to its cards' top.
    static let cardsTop: CGFloat = 52
    static let rowGap: CGFloat = 70
    static let posterHeight: CGFloat = 330
    /// The Top 10 rows' size against the others.
    static let top10Scale: CGFloat = 1.22
    static let landscapeHeight: CGFloat = 225
    static let squareSide: CGFloat = 260
    static let gap: CGFloat = 26
    static let radius: CGFloat = 12
    static let horizontal = Animation.easeOut(duration: 0.24)
    static let vertical = Animation.easeInOut(duration: 0.36)
}

struct OrbitPlatformPage: View {
    let route: FolderRoute
    let push: (TitleRoute) -> Void

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

    @State private var typeFilter: String? = "movie"
    @State private var current = 0
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
    /// Steven: the first title's trailer never started (one YouTube extraction runs at a time
    /// app-wide, and a title that asks while another one runs is skipped, not queued). Asked
    /// again while the viewer stays on it.
    @State private var dwellRetry: Task<Void, Never>?

    init(route: FolderRoute, push: @escaping (TitleRoute) -> Void) {
        self.route = route
        self.push = push
        _model = StateObject(wrappedValue: FolderDetailViewModel(route: route))
    }

    // MARK: Data

    private var series: Bool { typeFilter == "series" }
    private var brand: Color { OrbitPlatformBrand.color(title: model.folderTitle) }

    /// The folder's catalogs of the current type (loaded ones), then the TMDB extras.
    /// Built once per change of what they are made of (fluidity: every press rebuilt them).
    @State private var rowsMemo = OrbitRowsMemo<[OrbitPlatformRow]>()

    private var rows: [OrbitPlatformRow] {
        rowsMemo.get(OrbitRowsKey(rows: model.stripRows, filter: typeFilter,
                                  extras: extras.movieRows + extras.seriesRows, variant: series ? "s" : "m")) { buildRows() }
    }

    private func buildRows() -> [OrbitPlatformRow] {
        let extraRows = series ? extras.seriesRows : extras.movieRows
        // Steven: where this page builds its own rows (a platform TMDB knows), his catalogs that
        // repeat them are not drawn — only his Nouveautés and Top 10 (the « Tous » catalogs stay,
        // unseen, for the search). Elsewhere every catalog shows.
        let ownRowsOnly = !extraRows.isEmpty
        let catalogs: [OrbitPlatformRow] = CollectionTypeFilter.rows(model.stripRows, filter: typeFilter).compactMap { row in
            guard row.status == .loaded, let items = row.section?.items, !items.isEmpty else { return nil }
            guard !ownRowsOnly || OrbitCatalogFilter.isKept(row.heading) else { return nil }
            var seen = Set<String>()
            let unique = items.filter { seen.insert("\($0.type):\($0.id)").inserted }
            let heading = row.heading.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let top10 = heading.contains("top 10") || heading.contains("top10")
            return OrbitPlatformRow(id: row.id, title: row.heading, items: unique,
                                    shape: unique.first?.posterShape ?? .poster, transparent: top10)
        }
        // Steven: a title already in a row above is left out of the rows this page adds (his own
        // rows are never touched); a row left with fewer than 8 titles is dropped.
        var shown = Set(catalogs.flatMap { $0.items.map { Self.identity($0) } })
        var more: [OrbitPlatformRow] = []
        for extra in extraRows {
            let fresh = extra.items.filter { !shown.contains(Self.identity($0)) }
            guard fresh.count >= 8 else { continue }
            let kept = Array(fresh.prefix(20))
            kept.forEach { shown.insert(Self.identity($0)) }
            more.append(OrbitPlatformRow(id: extra.id, title: extra.title, items: kept, shape: .poster, transparent: false))
        }
        return catalogs + more
    }

    /// The same title across sources (an add-on's "tt…" id, TMDB's "tmdb:…"): its name and year.
    private static func identity(_ item: MetaPreview) -> String {
        let year: String = item.releaseInfo.map { String($0.prefix(4)) } ?? ""
        return item.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) + "|" + year
    }

    private func lead(of row: OrbitPlatformRow) -> Int {
        min(leads[row.id] ?? 0, max(0, row.items.count - 1))
    }

    /// The title the page shows: the current row's focused card.
    private func focusedItem(_ rows: [OrbitPlatformRow]) -> MetaPreview? {
        guard rows.indices.contains(current) else { return rows.first?.items.first }
        let row = rows[current]
        return row.items.indices.contains(lead(of: row)) ? row.items[lead(of: row)] : nil
    }

    // MARK: Body

    var body: some View {
        let rows = rows
        let index = min(current, max(0, rows.count - 1))
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight

        ZStack(alignment: .topLeading) {
            // (Native: the stage follows the current row's own lead box — a press redraws only it.)
            OrbitLeadReader(box: leads.box(rows.indices.contains(index) ? rows[index].id : "-")) { _ in
            let item = focusedItem(rows)
            // The focused title, full screen.
            OrbitPlatformStage(item: item, meta: item.flatMap { metaStore.meta(for: $0) }, brand: brand,
                               trailerURL: trailerURL(for: item, rows: rows),
                               onTrailerFailure: { trailer.playbackFailed($0) },
                               onTrailerEnded: { trailer.playbackFinished() })

            // Its logo, meta line and synopsis.
            if let item {
                OrbitPlatformInfo(item: item, meta: metaStore.meta(for: item))
                    .offset(x: OrbitPlatformLayout.margin, y: OrbitPlatformLayout.infoTop)
            }

            }

            // The rows.
                            nativeSections(rows)
                    // Steven: Films / Séries came up on the Top 10 — each filter its own page, from its top.
                    .id(typeFilter ?? "all")
                    .disabled(search != nil)
            

            if rows.isEmpty, model.isLoading {
                ProgressView()
                    .frame(width: W, height: H)
            }

            // The page's one focusable stop, under the bar's band.

            // Search, Films, Séries — out of reach once the page has gone below its first row.
            CollectionFilterBar(filter: $typeFilter, onSearch: openSearch)
                .disabled(search != nil || (pageFocused && index > 0))
                .opacity(search != nil ? 0 : 1)

            OrbitPlatformIntro(title: model.folderTitle, logoUrl: model.titleLogoUrl, brand: brand)

            if let search {
                OrbitPlatformSearchLayer(model: search, platform: model.folderTitle,
                                         onOpen: { push(TitleRoute(preview: $0)) },
                                         onClose: closeSearch)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .background(OrbitHomeLayout.background)
        .ignoresSafeArea()
        .background { ViewerInputClockInstaller().frame(width: 0, height: 0) }
        .onAppear {
            covered = false
            tabBarVisibility.pushImmersive()
            OrbitHomeButtonHost.shared.enter(.ownBar)   // the house is in the page's own bar
            model.buildsStripState = true
            model.start()
            extras.load(title: model.folderTitle)
            trailer.restSource = .custom(motion)
            refreshAfterMove()
        }
        .onDisappear {
            covered = true
            tabBarVisibility.popImmersive()
            OrbitHomeButtonHost.shared.leave(.ownBar)
            trailer.reset(abortStages: true)
            // Keeps the folder's state (a pushed title only covers the page; `initialize` on the
            // way back finds the same rows).
            model.stop()
        }
        .onChange(of: model.folderTitle) { _, title in extras.load(title: title) }
        .onChange(of: canvasFocused) { _, _ in refreshAfterMove() }
        .onChange(of: rows.map(\.id)) { _, ids in
            if current >= ids.count { current = max(0, ids.count - 1) }
            refreshAfterMove()
        }
        .onChange(of: typeFilter) { _, _ in
            current = 0
            leads.reset()
            refreshAfterMove()
        }
        // A series-only folder does not open on an empty Films page.
        .onChange(of: model.stripRows.map(\.id), initial: true) { _, _ in
            let all = model.stripRows
            if typeFilter == "movie", !all.isEmpty, CollectionTypeFilter.rows(all, filter: "movie").isEmpty,
               !CollectionTypeFilter.rows(all, filter: "series").isEmpty {
                typeFilter = "series"
            }
        }
    }

    /// The native page: the sections (an invisible stop for the hero, whose art stays behind, then
    /// the rows drawn as before) as real buttons the system moves.
    private func nativeSections(_ rows: [OrbitPlatformRow]) -> some View {
        OrbitNativeSections(
            count: rows.count, hasHero: false,
            height: { s in rows.indices.contains(s) ? rows[s].pitch : 0 },
            topLine: OrbitPlatformLayout.rowLine, current: current, hidesAbove: true,
            onFocus: { s in
                withAnimation(.easeInOut(duration: 0.3)) { current = s }
                refreshAfterMove()
            },
            onMove: { move($0) }, onSelect: select, onExit: exitAction(index: min(current, max(0, rows.count - 1))),
            onFocusChange: { has in
                nativeHeroFocused = has
                if has { nativeEnter(0) } else { nativeLeave() }
            },
            rowsFocusable: true,
            focusRow: { s in if rows.indices.contains(s) { leads.box(rows[s].id).focusRequest &+= 1 } }
        ) { s, focused in
            if rows.indices.contains(s) {
                let row = rows[s]
                OrbitPlatformRowView(row: row, box: leads.box(row.id), isCurrent: s == current,
                                     focused: focused,
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

    private func trailerURL(for item: MetaPreview?, rows: [OrbitPlatformRow]) -> String? {
        guard let item, trailerKey == "\(item.type):\(item.id)" else { return nil }
        return trailer.playingURL
    }

    // MARK: Input

    private func move(_ direction: MoveCommandDirection) {
        let rows = rows
        guard !rows.isEmpty else { return }
        let index = min(current, rows.count - 1)
        switch direction {
        case .down:
            guard index + 1 < rows.count else { return }
            withAnimation(reduceMotion ? nil : OrbitPlatformLayout.vertical) { current = index + 1 }
        case .up:
            guard index > 0 else { return }   // the bar takes it at the top
            withAnimation(reduceMotion ? nil : OrbitPlatformLayout.vertical) { current = index - 1 }
        case .left, .right:
            let row = rows[index]
            let next = lead(of: row) + (direction == .right ? 1 : -1)
            guard row.items.indices.contains(next) else { return }
            withAnimation(OrbitPlatformLayout.horizontal) { leads[row.id] = next }
        @unknown default:
            return
        }
        refreshAfterMove()
    }

    private func select() {
        covered = true
        trailer.reset(abortStages: true)
        let rows = rows
        guard rows.indices.contains(current) else { return }
        let row = rows[current]
        guard row.items.indices.contains(lead(of: row)) else { return }
        push(TitleRoute(preview: row.items[lead(of: row)]))
    }

    /// Menu: back to the first row from below it; at the top, the system's own (the page closes).
    private func exitAction(index: Int) -> (() -> Void)? {
        guard index > 0 else { return nil }
        return {
            withAnimation(reduceMotion ? nil : OrbitPlatformLayout.vertical) { current = 0 }
            refreshAfterMove()
        }
    }

    private func openSearch() {
        trailer.reset()
        trailerKey = nil
        // Steven: Prime Video's and Paramount+'s art is landscape: so are their results.
        let shapes = rows.prefix(6).map(\.shape)
        let landscape = shapes.filter { $0 == .landscape }.count * 2 > max(1, shapes.count)
        withAnimation(.easeInOut(duration: 0.25)) {
            search = OrbitPlatformSearchModel(tabs: model.tabs, platformKey: "\(route.collectionId)|\(route.folderId)",
                                              landscape: landscape)
        }
    }

    private func closeSearch() {
        withAnimation(.easeInOut(duration: 0.25)) { search = nil }
        refreshAfterMove()
    }

    /// After any move: the look-ahead (TMDB meta, art) and the trailer of the focused title.
    private func refreshAfterMove() {
        let rows = rows
        let index = min(current, max(0, rows.count - 1))
        motion.stamp()

        var metaItems: [MetaPreview] = []
        for i in max(0, index - 1)...max(0, min(rows.count - 1, index + 1)) where rows.indices.contains(i) {
            let row = rows[i]
            let lead = lead(of: row)
            let around = row.items.indices.filter { $0 >= lead - 1 && $0 <= lead + 4 }
            metaItems.append(contentsOf: around.map { row.items[$0] })
            let request = ArtworkDecodeRequest(size: .points(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight),
                                               fill: true, scale: UIScreen.main.scale)
            ArtworkStore.prefetch(around.compactMap { j in
                let banner: String? = row.items[j].banner
                return banner.flatMap(URL.init(string:)).map { ArtworkPrefetchItem(url: $0, decode: request) }
            })
        }
        OrbitMetaStore.shared.request(metaItems)
        // Steven's video: moving along a row, the logo area went blank while the next logo
        // loaded. The logos of the titles around (their meta already known) load ahead, at the
        // info block's own size.
        let logoRequest = ArtworkDecodeRequest(size: .points(width: OrbitPlatformLayout.logoSize.width,
                                                             height: OrbitPlatformLayout.logoSize.height),
                                               fill: false, scale: UIScreen.main.scale)
        ArtworkStore.prefetch(metaItems.compactMap { item in
            let logo = OrbitInfo.make(item, meta: OrbitMetaStore.shared.meta(for: item)).logo
            return logo.flatMap(URL.init(string:)).map { ArtworkPrefetchItem(url: $0, decode: logoRequest) }
        })

        dwellRetry?.cancel()
        trailer.reset()
        trailerKey = nil
        guard trailersOn, !covered, pageFocused, search == nil, UIAccessibility.isVideoAutoplayEnabled,
              let item = focusedItem(rows) else { return }
        trailer.prefersReducedMotion = reduceMotion
        trailer.restSource = .custom(motion)
        let key = "\(item.type):\(item.id)"
        trailerKey = key
        trailer.focusChanged(true, item: item)
        dwellRetry = Task { @MainActor in
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled, trailerKey == key, trailer.playingURL == nil,
                      pageFocused, search == nil else { return }
                trailer.focusChanged(true, item: item)
            }
        }
    }
}

// MARK: - Stage, info, rows

/// The focused title full screen: its backdrop (kept until the next one is ready), its trailer
/// after a rest, the shades for the text and the rows, the platform's colour in the corner.
private struct OrbitPlatformStage: View {
    let item: MetaPreview?
    let meta: OrbitMeta?
    let brand: Color
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let size = CGSize(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
        let banner: String? = item?.banner
        ZStack {
            OrbitHomeLayout.background
            RadialGradient(colors: [brand.opacity(0.5), brand.opacity(0.15), .clear],
                           center: UnitPoint(x: 0.9, y: 0.05), startRadius: 0, endRadius: 1500)
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
            // The left shade for the logo and the synopsis, the bottom one for the rows.
            LinearGradient(stops: [
                .init(color: .black.opacity(0.82), location: 0),
                .init(color: .black.opacity(0.4), location: 0.45),
                .init(color: .clear, location: 0.72),
            ], startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [
                .init(color: .clear, location: 0.38),
                .init(color: .black.opacity(0.6), location: 0.62),
                .init(color: .black.opacity(0.92), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            // The platform's colour stays in the corner over the art.
            RadialGradient(colors: [brand.opacity(0.28), .clear],
                           center: UnitPoint(x: 0.95, y: 0), startRadius: 0, endRadius: 700)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.6), value: brand)
    }
}

/// The focused title's logo (or name), Orbit's meta line and three lines of synopsis.
private struct OrbitPlatformInfo: View {
    let item: MetaPreview
    let meta: OrbitMeta?

    var body: some View {
        let L = OrbitPlatformLayout.self
        let info = OrbitInfo.make(item, meta: meta)
        VStack(alignment: .leading, spacing: 0) {
            OrbitTitleMark(name: item.name, logo: info.logo, maxSize: L.logoSize, textSize: 64)
                .frame(width: L.logoSize.width, height: L.logoSize.height, alignment: .bottomLeading)
            OrbitMetaLine(info: info, size: 27)
                .frame(height: 36)
                .padding(.top, 26)
            Text(info.synopsis)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineSpacing(4)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(width: L.synopsisWidth, alignment: .topLeading)
                .padding(.top, 18)
        }
        .frame(width: L.synopsisWidth, alignment: .topLeading)
        .id("\(item.type):\(item.id)")
        .transition(.opacity.animation(.easeInOut(duration: 0.22)))
        .allowsHitTesting(false)
    }
}

/// One row: its heading, then its cards from the focused one (at the margin) onwards; the one
/// before it slides out to the left.
private struct OrbitPlatformRowView: View {
    let row: OrbitPlatformRow
    @ObservedObject var box: OrbitLeadBox
    let isCurrent: Bool
    let focused: Bool
    let onEnter: () -> Void
    let onLeave: () -> Void
    let onSelect: () -> Void
    let onLeadChange: () -> Void

    var body: some View {
        let L = OrbitPlatformLayout.self
        let size = row.cardSize
        ZStack(alignment: .topLeading) {
            Text(row.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.white)
                .opacity(isCurrent ? 1 : 0.55)
                .lineLimit(1)
                .frame(height: 40)
                .offset(x: L.margin + 4, y: -20)
            OrbitNativeTileStrip(count: row.items.count, spacing: L.gap, height: size.height,
                                 lastWidth: size.width, box: box, alignment: .top,
                                 onEnter: onEnter, onLeave: onLeave, onSelect: onSelect,
                                 onLeadChange: { _ in onLeadChange() }) { index, lit in
                OrbitPlatformCard(item: row.items[index], size: size, transparent: row.transparent, focused: lit)
            }
            .frame(width: OrbitHomeLayout.screenWidth, height: size.height, alignment: .topLeading)
            .offset(y: L.cardsTop)
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
    }
}

/// A card: the add-on's art in its own shape. Ordinary art is rounded, framed in white when
/// focused; Steven's Top 10 images (transparent, numbers included) are drawn as they are, lifted
/// when focused.
private struct OrbitPlatformCard: View {
    let item: MetaPreview
    let size: CGSize
    let transparent: Bool
    let focused: Bool

    var body: some View {
        let L = OrbitPlatformLayout.self
        let art: String? = item.shape == .landscape ? (item.landscapePoster ?? item.poster) : item.poster
        // Steven's video: the focused card rose before the others. Its focus animation (0.18 s)
        // also took over the row's vertical move (0.36 s). The focus look now animates on its own,
        // never the card's place.
        Group {
            if transparent {
                // Steven: no frame on these (transparent art), so the cursor is a white glow.
                OrbitImage(url: art, fallback: item.rawPosterUrl, mode: .fit, size: size)
                    .frame(width: size.width, height: size.height)
                    .animation(.easeOut(duration: 0.18)) { view in
                        view
                            .shadow(color: .white.opacity(focused ? 0.55 : 0), radius: focused ? 24 : 0)
                            .shadow(color: .black.opacity(focused ? 0.6 : 0.3), radius: focused ? 20 : 8, y: 8)
                            .brightness(focused ? 0.06 : 0)
                    }
            } else {
                OrbitImage(url: art, fallback: item.rawPosterUrl, mode: .fill, size: size)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
                    .animation(.easeOut(duration: 0.18)) { view in
                        view
                            .overlay {
                                RoundedRectangle(cornerRadius: L.radius, style: .continuous)
                                    .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 4)
                            }
                            .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 16, y: 10)
                    }
            }
        }
        // Grows from its left edge's middle: never over the heading above it.
        .animation(.easeOut(duration: 0.18)) { view in
            view.scaleEffect(focused ? 1.06 : 1, anchor: .leading)
        }
    }
}

private extension MetaPreview {
    var shape: PosterShape { posterShape }
}

// MARK: - Catalog filter

/// Steven: which of his catalogs show where Orbit builds its own rows (platforms, studios): his
/// Nouveautés and Top 10 only. The genre, popular, saga and « Tous » catalogs repeat Orbit's rows.
enum OrbitCatalogFilter {
    static func isKept(_ heading: String) -> Bool {
        let h = heading.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return h.contains("top 10") || h.contains("top10") || h.contains("nouveau") || h.contains("nouvelle")
    }
}

// MARK: - Brand

/// Each platform's colour (its brand's, darkened for a background), from the folder's title. A
/// folder not listed (a studio…) takes a neutral slate.
enum OrbitPlatformBrand {
    static func color(title raw: String) -> Color {
        known(title: raw) ?? Color(red: 0.30, green: 0.34, blue: 0.42)
    }

    /// No brand colour known for this title (the page samples one from the logo).
    static func isNeutral(title raw: String) -> Bool { known(title: raw) == nil }

    static func known(title raw: String) -> Color? {
        let t = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        if t.contains("netflix") { return Color(red: 0.78, green: 0.04, blue: 0.08) }
        if t.contains("disney") { return Color(red: 0.06, green: 0.22, blue: 0.62) }
        if t.contains("prime") || t.contains("amazon") { return Color(red: 0.0, green: 0.48, blue: 0.78) }
        if t.contains("hbo") || t == "max" || t.hasPrefix("max") { return Color(red: 0.16, green: 0.12, blue: 0.75) }
        if t.contains("paramount") { return Color(red: 0.0, green: 0.33, blue: 0.85) }
        if t.contains("appletv") || t.contains("apple") { return Color(white: 0.55) }
        if t.contains("canal") { return Color(white: 0.45) }
        if t.contains("crunchyroll") { return Color(red: 0.96, green: 0.46, blue: 0.08) }
        if t.contains("universal") { return Color(red: 0.12, green: 0.30, blue: 0.70) }
        if t.contains("pixar") { return Color(red: 0.10, green: 0.45, blue: 0.80) }
        if t.contains("marvel") { return Color(red: 0.75, green: 0.08, blue: 0.10) }
        if t.contains("dreamworks") { return Color(red: 0.10, green: 0.35, blue: 0.75) }
        return nil
    }
}

// MARK: - Intro

/// The platform's logo, large on a screen tinted with its colour, then gliding to the top-right
/// corner while the tint fades (an app opening on Apple TV). Once per visit; any press skips it;
/// Reduce Motion goes straight to the corner.
struct OrbitPlatformIntro: View {
    let title: String
    let logoUrl: String?
    let brand: Color
    /// Steven (Paramount+): the folder's logo drawn in white (its own blue sank into the dark page).
    var white = false
    /// Steven (Apple TV): a logo of the app's own instead of the folder's image.
    var assetLogo: String? = nil
    /// The asset keeps its own colours (Netflix's red N) instead of being drawn in white.
    var assetInColour = false
    /// Steven (Disney+): no corner logo — the logo goes out as it would glide there (the page
    /// shows it in its bar and its hero).
    var hidesCorner = false
    /// Steven (Disney+): where the logo glides instead of the corner (the page's own logo there,
    /// the opening's fades onto it), and its scale there.
    var settlesAt: CGPoint? = nil
    var settledScale: CGFloat = 0.3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .hidden
    @State private var glide: DispatchWorkItem?
    @State private var appearedAt = Date.distantFuture
    /// The logo's light: dim (1: off, 0: on) and its glow's flash.
    @State private var dim: Double = 1
    @State private var glow: Double = 0
    /// When the page last went away (a title opened just then: the way back keeps the corner logo).
    @State private var leftAt: TimeInterval = 0

    private static func returningFromTitle(leftAt: TimeInterval) -> Bool {
        leftAt > 0 && OrbitNavClock.titleOpenedAt >= leftAt - 2.0
    }

    private enum Phase { case hidden, splash, settled }

    static let logoSize = CGSize(width: 520, height: 200)
    static let splashScale: CGFloat = 1.4
    static let cornerScale: CGFloat = 0.36
    /// The corner: level with the bar's centre line, at the right margin.
    static let cornerCentreY: CGFloat = 59
    /// Steven: every page's logo in the TV's top right corner, the same distance from the top and
    /// from the right (on the corner's diagonal), at the same place on every page.
    static let cornerInset: CGFloat = 44
    /// The corner box's height (every logo fits it, its top and right edges on the inset).
    static let cornerHeight: CGFloat = 72
    /// Steven (device: not far enough right): level with the bar's right end.
    static let cornerTrailing: CGFloat = 50
    /// Steven (2026-10-28): the platform's Search, alone at the top right, just left of the corner logo.
    /// (The corner logo's drawn width: Netflix's N is far narrower than its box.)
    static let searchBesideLogo: CGFloat = -1
    /// Disney+ (its logo settles in the hero): Search in the corner itself, mirroring the house.
    static let searchInCorner: CGFloat = cornerInset - 6  // the bar pill's padding

    var body: some View {
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        let size = Self.logoSize
        let scale: CGFloat = switch phase {
        case .hidden: Self.splashScale * 0.85
        case .splash: Self.splashScale
        case .settled: settlesAt != nil ? settledScale : hidesCorner ? Self.splashScale * 1.08 : Self.cornerScale
        }
        let centre: CGPoint = phase == .settled && settlesAt != nil ? settlesAt!
            : phase == .settled && !hidesCorner
            ? CGPoint(x: W - Self.cornerInset - size.width * Self.cornerScale / 2,
                      // Steven (2026-10-28: Netflix's N sat lower than the bar's Search): the N, shorter
                      // than its box, centred on the bar's line (59 pt) — 10 pt up.
                      y: Self.cornerInset + size.height * Self.cornerScale / 2 - (assetInColour ? 10 : 0))
            : CGPoint(x: W / 2, y: H / 2)
        ZStack(alignment: .topLeading) {
            // Black tinted with the platform's colour.
            ZStack {
                Color.black
                RadialGradient(colors: [brand.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 900)
            }
            .frame(width: W, height: H)
            .opacity(phase == .settled ? 0 : 1)

            logo
                // Steven (2026-10-28: Search too far left of Netflix's N): the logo's own drawn width,
                // for the bar's Search to sit just left of it.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    if width > 1 { OrbitCornerLogo.shared.width = width * Self.cornerScale }
                }
                .frame(width: size.width, height: size.height, alignment: phase == .settled && settlesAt == nil ? .topTrailing : .center)
                // Steven: the logo switched on — it comes up dim, lights up, then takes the viewer in.
                .modifier(OrbitLightUp(dim: dim, glow: glow, tint: brand))
                .scaleEffect(scale, anchor: .center)
                .opacity(phase == .hidden || (hidesCorner && phase == .settled) ? 0 : 1)
                .offset(x: centre.x - size.width / 2, y: centre.y - size.height / 2)
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .allowsHitTesting(false)
        .onAppear {
            appearedAt = Date()
            // Pushed under the Plateformes page's curtain, which already shows this very opening:
            // the page starts at the same point (no fade), the curtain goes once the push is over,
            // then the logo glides to its corner.
            if OrbitPlatformCurtain.shared.down {
                glide?.cancel()
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { phase = reduceMotion ? .settled : .splash }
                let curtained = OrbitPlatformCurtain.shared.look != nil
                // The curtain plays the neon; the page waits under it, lit as it ends, and shows
                // once it is over (pushed ~0.25 s after the press).
                let lift = max(0.5, OrbitPlatformCurtain.litAfter - 0.25)
                DispatchQueue.main.asyncAfter(deadline: .now() + lift) { OrbitPlatformCurtain.shared.lift(instant: curtained) }
                if reduceMotion { dim = 0; glow = 0 } else {
                    withTransaction(still) { dim = 0; glow = curtained ? 0.35 : 0 }
                    if !curtained { lightUp(at: 0.5) }
                    let work = DispatchWorkItem {
                        withAnimation(.spring(response: 0.75, dampingFraction: 0.88)) { phase = .settled }
                        withAnimation(.easeOut(duration: 0.6)) { glow = 0 }
                    }
                    glide = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + lift + 0.2, execute: work)
                }
                return
            }
            // Steven (2026-10-26, still: the collection showed a moment, then the cover faded in over
            // it): a fresh entry (not the way back from a title opened here) starts black at once,
            // in this very frame and without animation, whatever the intro was left at.
            if phase != .hidden, OrbitNavClock.titlesShown == 0,
               OrbitNavClock.titleOpenedAt < ProcessInfo.processInfo.systemUptime - 3.0,
               !Self.returningFromTitle(leftAt: leftAt) {
                glide?.cancel()
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { phase = .hidden; dim = 1; glow = 0 }
            }
            // Steven (device: the collection showed before its logo): the screen stays black until
            // the logo is ready (a second at most), then the intro plays with it.
            if assetLogo != nil { play(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { play() }
            preload(logoUrl)
        }
        .onChange(of: logoUrl) { _, url in preload(url) }
        // Steven (device: entering a platform, its catalogue showed under the intro): the system
        // can show a closed page's view again for a moment on the next visit, intro already done.
        // Closed (no title opened over it), the intro goes back to its black start.
        .onDisappear {
            let left = ProcessInfo.processInfo.systemUptime
            leftAt = left
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // (A title opened from the page appears while the page is still leaving — the push
                // lasts: Steven, simulator, the opening replayed on the way back.)
                guard OrbitNavClock.titleOpenedAt < left - 2.0, OrbitNavClock.titlesShown == 0 else { return }
                glide?.cancel()
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { phase = .hidden; dim = 1; glow = 0 }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ViewerInputClock.didRecord)) { _ in
            // Steven: a press skips the intro (the page is used often) — not the press that opened
            // the page, which lands just after it appears (the catalogue showed before the intro).
            guard phase != .settled, Date().timeIntervalSince(appearedAt) > 0.8 else { return }
            glide?.cancel()
            withAnimation(.easeOut(duration: 0.3)) { phase = .settled; dim = 0; glow = 0 }
        }
    }

    private var logo: some View {
        OrbitPlatformIntroLogo(look: OrbitPlatformLook(title: title, logoUrl: logoUrl, brand: brand, white: white,
                                                       assetLogo: assetLogo, assetInColour: assetInColour))
    }


    /// The logo fetched at its splash size, then the intro.
    private func preload(_ url: String?) {
        guard phase == .hidden, let url, !url.isEmpty, let address = URL(string: url) else { return }
        let request = ArtworkDecodeRequest(size: .points(width: Self.logoSize.width * Self.splashScale,
                                                         height: Self.logoSize.height * Self.splashScale),
                                           fill: false, scale: UIScreen.main.scale)
        if ArtworkStore.cached(address, decode: request) != nil { play(); return }
        Task { @MainActor in
            _ = try? await ArtworkStore.fetch(address, decode: request)
            play()
        }
    }

    private func play() {
        guard phase == .hidden else { OrbitPlatformCurtain.shared.lift(); return }
        if reduceMotion {
            phase = .settled
            dim = 0; glow = 0
            OrbitPlatformCurtain.shared.lift()
            return
        }
        withAnimation(.easeOut(duration: 0.35)) { phase = .splash }
        lightUp(at: 0.3)
        // The curtain the page was pushed under goes once the logo shows on the page's own black.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { OrbitPlatformCurtain.shared.lift() }
        let work = DispatchWorkItem {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.88)) { phase = .settled }
            withAnimation(.easeOut(duration: 0.6)) { glow = 0 }
        }
        glide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: work)
    }

    /// The logo switched on as a neon sign: two quick flickers, then full light with its flash,
    /// then a soft glow left on it (Steven: "comme si on allumait le logo").
    private func lightUp(at delay: Double) {
        OrbitNeon.play(at: delay) { d, g, animation in
            guard phase == .splash else { return }
            withAnimation(animation) { dim = d; glow = g }
        }
    }
}

/// The neon's switching on: (dim, glow) steps, each with its animation.
enum OrbitNeon {
    static func play(at delay: Double, _ step: @escaping (Double, Double, Animation) -> Void) {
        // (Steven, 2026-10-27: one light-up, no flicker — it rises softly to very bright, peaks,
        // then keeps a glow as it leaves for its corner.)
        let steps: [(Double, Double, Double, Animation)] = [
            (0.00, 0.00, 0.75, .easeIn(duration: 0.5)),     // rising to bright
            (0.50, 0.00, 1.30, .easeOut(duration: 0.18)),   // its peak, very bright
            (0.72, 0.00, 0.45, .easeInOut(duration: 0.45)), // a glow left on it
        ]
        for (at, d, g, animation) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + at) { step(d, g, animation) }
        }
    }
}

/// A logo switched on: dim and greyed while off; lit, a white bloom and the brand's glow around it.
struct OrbitLightUp: ViewModifier {
    let dim: Double
    let glow: Double
    let tint: Color

    func body(content: Content) -> some View {
        content
            // (Steven: too dark while off — on its own colour it vanished; it is faint, only
            // asleep, and reads.)
            .opacity(1 - 0.55 * dim)
            .brightness(-0.08 * dim + 0.18 * glow)
            .saturation(1 - 0.3 * dim)
            .shadow(color: .white.opacity(min(1, 0.5 * glow)), radius: 18 * glow)
            .shadow(color: tint.opacity(min(1, 0.85 * glow)), radius: 55 * glow)
    }
}


/// How a platform opens: its name, logo and colour (the page's own opening and the curtain the
/// Plateformes page drops before pushing it draw the same thing).
struct OrbitPlatformLook {
    let title: String
    let logoUrl: String?
    let brand: Color
    var white = false
    var assetLogo: String? = nil
    var assetInColour = false
    /// A studio's opening (its logo as the studio page draws it).
    var studio = false

    /// The look of the page `route` opens (the same choice, in the same order, as Home's stack).
    @MainActor static func of(_ route: FolderRoute) -> OrbitPlatformLook {
        let t = route.folderTitle, logo = route.titleLogoUrl
        if OrbitDisneyPage.handles(route) { return .init(title: t, logoUrl: logo, brand: OrbitDisneyLayout.brandBlue) }
        if OrbitNetflixPage.handles(route) {
            return .init(title: t, logoUrl: logo, brand: OrbitNetflixLayout.red, assetLogo: "NetflixN", assetInColour: true)
        }
        if OrbitPrimePage.handles(route) { return .init(title: t, logoUrl: logo, brand: OrbitPrimeLayout.blue, white: true) }
        if OrbitHBOPage.handles(route) { return .init(title: t, logoUrl: logo, brand: OrbitHBOLayout.blue) }
        if OrbitParamountPage.handles(route) { return .init(title: t, logoUrl: logo, brand: OrbitParamountLayout.blue, white: true) }
        if OrbitAppleTVPage.handles(route) {
            return .init(title: t, logoUrl: logo, brand: Color(white: 0.6), white: true, assetLogo: "AppleTVMark")
        }
        return .init(title: t, logoUrl: logo, brand: OrbitPlatformBrand.color(title: t))
    }
}

/// The platform's logo as its opening draws it.
struct OrbitPlatformIntroLogo: View {
    let look: OrbitPlatformLook
    private var title: String { look.title }
    private var logoUrl: String? { look.logoUrl }
    private var white: Bool { look.white }
    private var assetLogo: String? { look.assetLogo }
    private var assetInColour: Bool { look.assetInColour }

    var body: some View { logo }

    @ViewBuilder
    private var logo: some View {
        if let assetLogo, assetInColour {
            Image(assetLogo)
                .resizable()
                .scaledToFit()
                // (Steven: Netflix's N touched the billboard under it — a little shorter, its top
                // still on the corner's line.)
                .padding(.bottom, OrbitPlatformIntro.logoSize.height * 0.3)
        } else if let assetLogo {
            Image(assetLogo)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.white)
                // (Its room below it: its top on the corner's line, as the other logos.)
                .padding(.bottom, OrbitPlatformIntro.logoSize.height * 0.36)
        } else if let logoUrl, !logoUrl.isEmpty {
            CachedAsyncImage(string: logoUrl, contentMode: .fit,
                             decodeSize: .points(width: OrbitPlatformIntro.logoSize.width * OrbitPlatformIntro.splashScale,
                                                 height: OrbitPlatformIntro.logoSize.height * OrbitPlatformIntro.splashScale),
                             loading: { Color.clear }, failure: { name })
                .brightness(white ? 1 : 0)
        } else {
            name
        }
    }

    private var name: some View {
        Text(title)
            .font(.system(size: 90, weight: .heavy))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
    }
}

// MARK: - Franchises and genres (TMDB)

/// The platform's own extra rows: Disney+'s franchises (Marvel, Star Wars, Pixar), then six genres
/// — TMDB's discover by watch provider in the viewer's region, the most popular first, so only
/// what is on the platform. Fetched once per page; a platform TMDB does not know has none.
@MainActor
final class OrbitPlatformExtrasModel: ObservableObject {
    struct Extra: Equatable {
        let id: String
        let title: String
        let items: [MetaPreview]
        static func == (a: Extra, b: Extra) -> Bool { a.id == b.id && a.items.map(\.id) == b.items.map(\.id) }
    }

    @Published private(set) var movieRows: [Extra] = []
    @Published private(set) var seriesRows: [Extra] = []
    private var loadedFor: Int?

    nonisolated private static let movieGenres: [(Int, String)] = [
        (28, "Action"), (35, "Comédie"), (53, "Thriller"), (27, "Horreur"), (878, "Science-Fiction"), (16, "Animation"),
    ]
    nonisolated private static let seriesGenres: [(Int, String)] = [
        (18, "Drame"), (35, "Comédie"), (80, "Crime"), (10765, "Science-Fiction & Fantastique"),
        (16, "Animation"), (99, "Documentaire"),
    ]
    /// Disney+: (company id, row title, movies, series).
    nonisolated private static let disneyFranchises: [(Int, String)] = [(420, "Marvel"), (1, "Star Wars"), (3, "Pixar")]

    func load(title: String) {
        guard let provider = OrbitPlatformTrendingModel.providerId(forTitle: title), provider != loadedFor else { return }
        loadedFor = provider
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        guard !key.isEmpty else { return }
        let language = TmdbSettingsRepository.shared.snapshot().language
        let disney = provider == 337
        Task { [weak self] in
            async let movies = Self.rows(media: "movie", provider: provider, disney: disney, apiKey: key, language: language)
            async let series = Self.rows(media: "tv", provider: provider, disney: disney, apiKey: key, language: language)
            let (m, s) = await (movies, series)
            guard let self, self.loadedFor == provider else { return }
            self.movieRows = m.map { Extra(id: $0.id, title: $0.title, items: $0.items) }
            self.seriesRows = s.map { Extra(id: $0.id, title: $0.title, items: $0.items) }
        }
    }

    nonisolated private static func rows(media: String, provider: Int, disney: Bool,
                                         apiKey: String, language: String) async -> [(id: String, title: String, items: [MetaPreview])] {
        let tv = media == "tv"
        var specs: [(id: String, title: String, query: String)] = []
        if disney {
            for (company, name) in disneyFranchises where !(tv && company == 3) {
                specs.append(("franchise-\(company)-\(media)", name, "&with_companies=\(company)"))
            }
        }
        for (genre, name) in tv ? seriesGenres : movieGenres {
            specs.append(("genre-\(genre)-\(media)", name, "&with_genres=\(genre)"))
        }
        let lang = language.isEmpty ? "fr-FR" : language
        let region = region(language: lang)
        let lists = await withTaskGroup(of: (Int, [MetaPreview]).self) { group in
            for (index, spec) in specs.enumerated() {
                group.addTask {
                    let address = "https://api.themoviedb.org/3/discover/\(media)?api_key=\(apiKey)&language=\(lang)"
                        + "&watch_region=\(region)&with_watch_providers=\(provider)"
                        + "&with_watch_monetization_types=flatrate&sort_by=popularity.desc" + spec.query
                    // Two pages: room for the titles the rows above already show to be left out.
                    async let first = fetch(address + "&page=1", tv: tv)
                    async let second = fetch(address + "&page=2", tv: tv)
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
            return (spec.id, spec.title, items)
        }
    }

    nonisolated static func region(language: String) -> String {
        let parts = language.split(whereSeparator: { $0 == "-" || $0 == "_" })
        if parts.count > 1 { return String(parts[1]).uppercased() }
        if let region = Locale.current.region?.identifier, region.count == 2 { return region }
        return "FR"
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
        }
        let results: [Result]?
    }

    /// One TMDB discover page as previews (the Disney+ page's Hulu rows use it too).
    nonisolated static func fetch(_ address: String, tv: Bool, requiresOverview: Bool = true) async -> [MetaPreview] {
        guard let url = URL(string: address),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return (decoded.results ?? []).compactMap { r -> MetaPreview? in
            // Steven: the rows this page adds keep only titles with a synopsis in his language.
            guard let name = r.title ?? r.name, !name.isEmpty, let poster = r.poster_path else { return nil }
            let overview = r.overview ?? ""
            if requiresOverview, overview.isEmpty { return nil }
            let date = r.release_date ?? r.first_air_date
            return MetaPreview(id: "tmdb:\(r.id)", type: tv ? "series" : "movie", name: name,
                               poster: "https://image.tmdb.org/t/p/w780\(poster)",
                               banner: r.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" },
                               logo: nil, posterShape: .poster,
                               description: overview, releaseInfo: date.map { String($0.prefix(4)) },
                               rawReleaseDate: date, popularity: nil, voteCount: nil,
                               imdbRating: r.vote_average.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil },
                               genres: [], rawPosterUrl: nil, landscapePoster: nil,
                               rawLandscapePosterUrl: nil, customPosterApplied: false)
        }
    }
}


/// The platform's corner logo as drawn (its width at the corner's scale), for the bar's Search.
@MainActor
final class OrbitCornerLogo: ObservableObject {
    static let shared = OrbitCornerLogo()
    @Published var width: CGFloat = OrbitPlatformIntro.logoSize.width * OrbitPlatformIntro.cornerScale
}
