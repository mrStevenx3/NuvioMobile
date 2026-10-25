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
    @StateObject private var trailer = InlineTrailerCardModel()
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true

    @State private var typeFilter: String? = "movie"
    @State private var current = 0
    @State private var leads: [String: Int] = [:]
    @FocusState private var canvasFocused: Bool
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
    private var rows: [OrbitPlatformRow] {
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
        let item = focusedItem(rows)
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight

        ZStack(alignment: .topLeading) {
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

            // The rows.
            rowsLayer(rows, index: index)

            if rows.isEmpty, model.isLoading {
                ProgressView()
                    .frame(width: W, height: H)
            }

            // The page's one focusable stop, under the bar's band.
            Button(action: select) {
                Color.clear
                    .frame(width: W, height: H - 110)
                    .contentShape(Rectangle())
            }
            .buttonStyle(OrbitPlatformCanvasStyle())
            .focused($canvasFocused)
            .onMoveCommand(perform: move)
            .onExitCommand(perform: exitAction(index: index))
            .offset(y: 110)
            .disabled(search != nil)

            // Search, Films, Séries — out of reach once the page has gone below its first row.
            CollectionFilterBar(filter: $typeFilter, onSearch: openSearch)
                .disabled(search != nil || (canvasFocused && index > 0))
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
            tabBarVisibility.pushImmersive()
            OrbitHomeButtonHost.shared.enter(.ownBar)   // the house is in the page's own bar
            model.buildsStripState = true
            model.start()
            extras.load(title: model.folderTitle)
            trailer.restSource = .custom(motion)
            refreshAfterMove()
        }
        .onDisappear {
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
            leads = [:]
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

    /// The current row at its line, the rows after it below (the next one's heading peeks), the
    /// ones above faded out as they leave.
    @ViewBuilder
    private func rowsLayer(_ rows: [OrbitPlatformRow], index: Int) -> some View {
        let L = OrbitPlatformLayout.self
        // Each row's heading centre, relative to the current row's.
        let offsets: [CGFloat] = {
            var out = Array(repeating: CGFloat(0), count: rows.count)
            guard rows.indices.contains(index) else { return out }
            var y: CGFloat = 0
            for i in index..<rows.count { out[i] = y; y += rows[i].pitch }
            y = 0
            for i in stride(from: index - 1, through: 0, by: -1) { y -= rows[i].pitch; out[i] = y }
            return out
        }()
        // Steven's video: the row leaving upwards faded across the next one (a ghost of the Top 10
        // over the posters). The rows above the current one are not drawn at all: one leaving
        // goes at once, one coming back down appears in place.
        let window = index...max(index, min(rows.count - 1, index + 2))
        ZStack(alignment: .topLeading) {
            if !rows.isEmpty {
                ForEach(Array(zip(window, rows[window])), id: \.1.id) { i, row in
                    OrbitPlatformRowView(row: row, lead: lead(of: row), isCurrent: i == index,
                                         focused: i == index && canvasFocused)
                        .offset(y: L.rowLine + offsets[i])
                        .transition(.identity)
                }
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight, alignment: .topLeading)
        // Steven's video: the row leaving upwards crossed the synopsis as a ghost. Nothing of the
        // rows shows above the current row's heading.
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: (L.rowLine - 60) / OrbitHomeLayout.screenHeight),
                .init(color: .black, location: (L.rowLine - 30) / OrbitHomeLayout.screenHeight),
                .init(color: .black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
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
        guard trailersOn, canvasFocused, search == nil, UIAccessibility.isVideoAutoplayEnabled,
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
                      canvasFocused, search == nil else { return }
                trailer.focusChanged(true, item: item)
            }
        }
    }
}

/// No system focus effect: the page draws its own.
private struct OrbitPlatformCanvasStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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
    let lead: Int
    let isCurrent: Bool
    let focused: Bool

    var body: some View {
        let L = OrbitPlatformLayout.self
        let size = row.cardSize
        let window = max(0, lead - 1)...max(max(0, lead - 1), min(row.items.count - 1, lead + 9))
        ZStack(alignment: .topLeading) {
            Text(row.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.white)
                .opacity(isCurrent ? 1 : 0.55)
                .lineLimit(1)
                .frame(height: 40)
                .offset(x: L.margin + 4, y: -20)
            ZStack(alignment: .topLeading) {
                if !row.items.isEmpty {
                    ForEach(Array(zip(window, row.items[window])), id: \.1.id) { index, item in
                        OrbitPlatformCard(item: item, size: size, transparent: row.transparent,
                                          focused: focused && index == lead)
                            .offset(x: L.margin + CGFloat(index - lead) * (size.width + L.gap))
                            .opacity(index < lead ? 0 : 1)
                            .transition(.identity)
                    }
                }
            }
            .offset(y: L.cardsTop)
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
        .allowsHitTesting(false)
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
private struct OrbitPlatformIntro: View {
    let title: String
    let logoUrl: String?
    let brand: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .hidden
    @State private var glide: DispatchWorkItem?
    @State private var appearedAt = Date.distantFuture

    private enum Phase { case hidden, splash, settled }

    static let logoSize = CGSize(width: 520, height: 200)
    static let splashScale: CGFloat = 1.4
    static let cornerScale: CGFloat = 0.36
    /// The corner: level with the bar's centre line, at the right margin.
    static let cornerCentreY: CGFloat = 59
    static let cornerTrailing: CGFloat = 72

    var body: some View {
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        let size = Self.logoSize
        let scale: CGFloat = switch phase {
        case .hidden: Self.splashScale * 0.85
        case .splash: Self.splashScale
        case .settled: Self.cornerScale
        }
        let centre: CGPoint = phase == .settled
            ? CGPoint(x: W - Self.cornerTrailing - size.width * Self.cornerScale / 2, y: Self.cornerCentreY)
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
                .frame(width: size.width, height: size.height, alignment: phase == .settled ? .trailing : .center)
                .scaleEffect(scale, anchor: .center)
                .opacity(phase == .hidden ? 0 : 1)
                .offset(x: centre.x - size.width / 2, y: centre.y - size.height / 2)
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .allowsHitTesting(false)
        .onAppear {
            appearedAt = Date()
            play()
        }
        .onReceive(NotificationCenter.default.publisher(for: ViewerInputClock.didRecord)) { _ in
            // Steven: a press skips the intro (the page is used often) — not the press that opened
            // the page, which lands just after it appears (the catalogue showed before the intro).
            guard phase != .settled, Date().timeIntervalSince(appearedAt) > 0.8 else { return }
            glide?.cancel()
            withAnimation(.easeOut(duration: 0.3)) { phase = .settled }
        }
    }

    @ViewBuilder
    private var logo: some View {
        if let logoUrl, !logoUrl.isEmpty {
            CachedAsyncImage(string: logoUrl, contentMode: .fit,
                             decodeSize: .points(width: Self.logoSize.width * Self.splashScale,
                                                 height: Self.logoSize.height * Self.splashScale),
                             loading: { Color.clear }, failure: { name })
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

    private func play() {
        guard phase == .hidden else { return }
        if reduceMotion {
            phase = .settled
            return
        }
        withAnimation(.easeOut(duration: 0.35)) { phase = .splash }
        let work = DispatchWorkItem {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.88)) { phase = .settled }
        }
        glide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95, execute: work)
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

    nonisolated private static func region(language: String) -> String {
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

    nonisolated private static func fetch(_ address: String, tv: Bool) async -> [MetaPreview] {
        guard let url = URL(string: address),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return (decoded.results ?? []).compactMap { r -> MetaPreview? in
            // Steven: the rows this page adds keep only titles with a synopsis in his language.
            guard let name = r.title ?? r.name, !name.isEmpty, let poster = r.poster_path,
                  let overview = r.overview, !overview.isEmpty else { return nil }
            let date = r.release_date ?? r.first_air_date
            return MetaPreview(id: "tmdb:\(r.id)", type: tv ? "series" : "movie", name: name,
                               poster: "https://image.tmdb.org/t/p/w500\(poster)",
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
