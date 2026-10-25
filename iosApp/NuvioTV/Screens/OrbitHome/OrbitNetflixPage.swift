import Combine
import SharedCore
import SwiftUI

// Orbit × Netflix (Steven, 2026-10-25, after Netflix's 2025 TV app): the Netflix folder in
// Netflix's look, Orbit's DNA kept (one focusable canvas — the page moves, the focus stays; the
// collection bar top left with the house, Films / Séries as Netflix's own tabs; the intro; trailers
// on a rest).
//
//  - Pure black. At the top, the billboard: a large rounded card (the newest title's art, its logo
//    with "N FILM" / "N SÉRIE" above when it is Netflix's own, "Comédie · 1996 · 1 h 31 · 13+", a red
//    "N° 6 des films" when it is in the Top 10).
//  - The rows, one at a time under the bar: the focused title opens into a large 16:9 tile (its
//    art, its logo, its red badges, its trailer after a rest) at the margin, the next ones in tall
//    portrait posters; under the open tile, its meta line and three lines of synopsis. The next
//    row's heading peeks at the bottom.
//  - The Top 10: Netflix's huge outlined ranks, each beside its title.

enum OrbitNetflixLayout {
    static let background = Color.black
    static let red = Color(red: 0.90, green: 0.04, blue: 0.08)
    static let margin: CGFloat = OrbitHomeLayout.margin
    /// The billboard.
    static let billboardTop: CGFloat = 112
    static let billboardSize = CGSize(width: OrbitHomeLayout.screenWidth - 2 * OrbitHomeLayout.margin, height: 640)
    /// The first row's heading under the billboard (it peeks on the first screen).
    static let rowsTop: CGFloat = 800
    /// The current row's heading once the billboard has gone.
    static let restTop: CGFloat = 118
    static let headingHeight: CGFloat = 50
    static let tileHeight: CGFloat = 500
    static var openWidth: CGFloat { tileHeight * 16 / 9 }
    /// 2:3, the posters' own shape (narrower, their sides were cut: Friends' F).
    static let posterWidth: CGFloat = 333
    static let gap: CGFloat = 16
    /// The open tile's meta line and synopsis.
    static let infoHeight: CGFloat = 170
    static let rowGap: CGFloat = 40
    static let radius: CGFloat = 8
    static let rankWidth: CGFloat = 170
    static let rankWidthTen: CGFloat = 360
    static let horizontal = Animation.easeOut(duration: 0.26)
    static let vertical = Animation.easeInOut(duration: 0.38)
}

struct OrbitNetflixRow: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [MetaPreview]
    let top10: Bool
    /// His Nouveautés rows ("Récemment ajouté" on the open tile).
    let fresh: Bool

    static func == (a: OrbitNetflixRow, b: OrbitNetflixRow) -> Bool {
        a.id == b.id && a.top10 == b.top10 && a.items.map(\.id) == b.items.map(\.id)
    }

    var height: CGFloat {
        let L = OrbitNetflixLayout.self
        return L.headingHeight + L.tileHeight + L.infoHeight + L.rowGap
    }

    private func rankWidth(_ index: Int) -> CGFloat {
        guard top10 else { return 0 }
        return index == 9 ? OrbitNetflixLayout.rankWidthTen : OrbitNetflixLayout.rankWidth
    }

    /// A title's slot (its rank on the Top 10, then its tile: open when focused on the current row).
    func slotWidth(_ index: Int, lead: Int, opens: Bool) -> CGFloat {
        let L = OrbitNetflixLayout.self
        return rankWidth(index) + (opens && index == lead ? L.openWidth : L.posterWidth)
    }

    /// A slot's left edge from the margin: the focused one at the margin, the others after it.
    /// Steven's video: only the current row has an open tile; the others are all portrait.
    func x(of index: Int, lead: Int, opens: Bool) -> CGFloat {
        let L = OrbitNetflixLayout.self
        guard index > lead else { return index == lead ? 0 : -(L.posterWidth + L.gap) }
        var x: CGFloat = 0
        for i in lead..<index { x += slotWidth(i, lead: lead, opens: opens) + L.gap }
        return x
    }
}

struct OrbitNetflixPage: View {
    let route: FolderRoute
    let push: (TitleRoute) -> Void

    static func handles(_ route: FolderRoute) -> Bool {
        let t = route.folderTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return t.contains("netflix")
    }

    @StateObject private var model: FolderDetailViewModel
    @StateObject private var extras = OrbitPlatformExtrasModel()
    @StateObject private var trailer = InlineTrailerCardModel()
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true

    /// nil: Accueil (films and series together, Steven 2026-10-25); "movie"; "series".
    @State private var typeFilter: String? = nil
    /// 0: the billboard; then the rows.
    @State private var current = 0
    @State private var leads: [String: Int] = [:]
    @FocusState private var canvasFocused: Bool
    @State private var motion = OrbitHomeMotion()
    @State private var trailerKey: String?
    @State private var search: OrbitPlatformSearchModel?

    init(route: FolderRoute, push: @escaping (TitleRoute) -> Void) {
        self.route = route
        self.push = push
        _model = StateObject(wrappedValue: FolderDetailViewModel(route: route))
    }

    // MARK: Data

    private var series: Bool { typeFilter == "series" }

    /// His Nouveautés, his Top 10, then the genres (TMDB).
    private var rows: [OrbitNetflixRow] {
        let extraRows: [OrbitPlatformExtrasModel.Extra] = switch typeFilter {
        case "movie"?: extras.movieRows
        case "series"?: extras.seriesRows
        default: Self.alternate(extras.movieRows, extras.seriesRows)
        }
        let catalogs: [OrbitNetflixRow] = CollectionTypeFilter.rows(model.stripRows, filter: typeFilter).compactMap { row in
            guard row.status == .loaded, let items = row.section?.items, !items.isEmpty else { return nil }
            guard extraRows.isEmpty || OrbitCatalogFilter.isKept(row.heading) else { return nil }
            var seen = Set<String>()
            let unique = items.filter { seen.insert("\($0.type):\($0.id)").inserted }
            let heading = row.heading.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let top10 = heading.contains("top 10") || heading.contains("top10")
            let seriesRow = heading.contains("serie") || unique.first.map { $0.type != "movie" } == true
            return OrbitNetflixRow(id: row.id,
                                   title: top10 ? (seriesRow ? String(localized: "Top 10 des séries en France aujourd'hui")
                                                          : String(localized: "Top 10 des films en France aujourd'hui"))
                                                : row.heading,
                                   items: top10 ? Array(unique.prefix(10)) : unique, top10: top10,
                                   fresh: heading.contains("nouveau") || heading.contains("nouvelle"))
        }
        let ordered = catalogs.filter(\.fresh) + catalogs.filter { !$0.fresh }
        var shown = Set(ordered.flatMap { $0.items.map(Self.identity) })
        var more: [OrbitNetflixRow] = []
        var merged: [String: Int] = [:]
        for extra in extraRows {
            let fresh = extra.items.filter { !shown.contains(Self.identity($0)) }
            guard fresh.count >= 8 else { continue }
            let kept = Array(fresh.prefix(24))
            kept.forEach { shown.insert(Self.identity($0)) }
            if let i = merged[extra.title] {
                // Accueil: one row per genre, its films and series in turn.
                let row = more[i]
                more[i] = OrbitNetflixRow(id: row.id, title: row.title, items: Self.alternate(row.items, kept),
                                          top10: false, fresh: false)
            } else {
                merged[extra.title] = more.count
                more.append(OrbitNetflixRow(id: extra.id, title: extra.title, items: kept, top10: false, fresh: false))
            }
        }
        return ordered + more
    }

    private static func alternate<T>(_ a: [T], _ b: [T]) -> [T] {
        var out: [T] = []
        for i in 0..<max(a.count, b.count) {
            if i < a.count { out.append(a[i]) }
            if i < b.count { out.append(b[i]) }
        }
        return out
    }

    private static func identity(_ item: MetaPreview) -> String {
        let year: String = item.releaseInfo.map { String($0.prefix(4)) } ?? ""
        return item.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) + "|" + year
    }

    /// The billboard's title: the newest with art.
    private var billboardItem: MetaPreview? {
        let rows = rows
        let source = rows.first(where: \.fresh) ?? rows.first
        return source?.items.first { $0.banner != nil } ?? source?.items.first
    }

    /// "N° 3 des films" for a title of the Top 10.
    private func topRank(_ item: MetaPreview) -> Int? {
        // Accueil has both Top 10s: the title's rank on whichever lists it.
        for top in rows where top.top10 {
            if let i = top.items.firstIndex(where: { Self.identity($0) == Self.identity(item) }) { return i + 1 }
        }
        return nil
    }

    private var sectionCount: Int { 1 + rows.count }

    private func rowTops(_ rows: [OrbitNetflixRow]) -> [CGFloat] {
        var y = OrbitNetflixLayout.rowsTop
        return rows.map { row in defer { y += row.height }; return y }
    }

    private func scroll(_ rows: [OrbitNetflixRow]) -> CGFloat {
        let r = current - 1
        guard r >= 0, rows.indices.contains(r) else { return 0 }
        return rowTops(rows)[r] - OrbitNetflixLayout.restTop
    }

    private func lead(of row: OrbitNetflixRow) -> Int {
        min(leads[row.id] ?? 0, max(0, row.items.count - 1))
    }

    private var focusedItem: MetaPreview? {
        if current == 0 { return billboardItem }
        let rows = rows
        let r = current - 1
        guard rows.indices.contains(r) else { return nil }
        let row = rows[r]
        return row.items.indices.contains(lead(of: row)) ? row.items[lead(of: row)] : nil
    }

    // MARK: Body

    var body: some View {
        let rows = rows
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        let offset = scroll(rows)
        let billboard = billboardItem

        ZStack(alignment: .topLeading) {
            OrbitNetflixLayout.background

            ZStack(alignment: .topLeading) {
                if let billboard {
                    OrbitNetflixBillboard(item: billboard, meta: metaStore.meta(for: billboard),
                                          rank: topRank(billboard), series: billboard.type != "movie",
                                          focused: canvasFocused && current == 0,
                                          trailerURL: current == 0 ? trailerURL(for: billboard) : nil,
                                          onTrailerFailure: { trailer.playbackFailed($0) },
                                          onTrailerEnded: { trailer.playbackFinished() })
                        .offset(x: OrbitNetflixLayout.margin, y: OrbitNetflixLayout.billboardTop)
                        .opacity(current <= 1 ? 1 : 0)
                }
                rowsLayer(rows)
            }
            .offset(y: -offset)
            .animation(reduceMotion ? nil : OrbitNetflixLayout.vertical, value: offset)

            // Under the bar: black, so the row above never shows through.
            LinearGradient(colors: [.black, .black.opacity(0.9), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(width: W, height: 110)
                .opacity(offset > 0 ? 1 : 0)
                .allowsHitTesting(false)

            if rows.isEmpty, model.isLoading {
                ProgressView().frame(width: W, height: H)
            }

            Button(action: select) {
                Color.clear
                    .frame(width: W, height: H - 110)
                    .contentShape(Rectangle())
            }
            .buttonStyle(OrbitNetflixCanvasStyle())
            .focused($canvasFocused)
            .onMoveCommand(perform: move)
            .onExitCommand(perform: exitAction())
            .offset(y: 110)
            .disabled(search != nil)

            CollectionFilterBar(filter: $typeFilter, onSearch: openSearch, showsAll: true)
                .disabled(search != nil || (canvasFocused && current > 0))
                .opacity(search != nil ? 0 : 1)

            OrbitPlatformIntro(title: model.folderTitle, logoUrl: model.titleLogoUrl ?? route.titleLogoUrl,
                               brand: OrbitNetflixLayout.red)

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
        .background(Color.black)
        .ignoresSafeArea()
        .background { ViewerInputClockInstaller().frame(width: 0, height: 0) }
        .onAppear {
            tabBarVisibility.pushImmersive()
            OrbitHomeButtonHost.shared.enter(.ownBar)
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
            model.stop()
        }
        .onChange(of: model.folderTitle) { _, title in extras.load(title: title) }
        .onChange(of: canvasFocused) { _, _ in refreshAfterMove() }
        .onChange(of: rows.map(\.id)) { _, _ in
            if current >= sectionCount { current = max(0, sectionCount - 1) }
            refreshAfterMove()
        }
        .onChange(of: typeFilter) { _, _ in
            current = 0
            leads = [:]
            refreshAfterMove()
        }
    }

    @ViewBuilder
    private func rowsLayer(_ rows: [OrbitNetflixRow]) -> some View {
        let tops = rowTops(rows)
        let currentRow = current - 1
        let low = max(0, currentRow)
        let high = min(rows.count - 1, max(currentRow, 0) + 2)
        ZStack(alignment: .topLeading) {
            if low <= high {
                ForEach(low...high, id: \.self) { i in
                    let row = rows[i]
                    let lead = lead(of: row)
                    let item: MetaPreview? = row.items.indices.contains(lead) ? row.items[lead] : nil
                    OrbitNetflixRowView(row: row, lead: lead, isCurrent: i == currentRow,
                                        focused: canvasFocused && i == currentRow,
                                        series: item.map { $0.type != "movie" } ?? series,
                                        rank: item.flatMap { topRank($0) },
                                        trailerURL: i == currentRow ? trailerURL(for: item) : nil,
                                        onTrailerFailure: { trailer.playbackFailed($0) },
                                        onTrailerEnded: { trailer.playbackFinished() },
                                        metaStore: metaStore)
                        .offset(y: tops[i])
                        // Steven's video: the row leaving upwards overlapped the new one while the
                        // page moved. It goes at once, the others keep their place.
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
            withAnimation(reduceMotion ? nil : OrbitNetflixLayout.vertical) { current += 1 }
        case .up:
            guard current > 0 else { return }
            withAnimation(reduceMotion ? nil : OrbitNetflixLayout.vertical) { current -= 1 }
        case .left, .right:
            let r = current - 1
            guard rows.indices.contains(r) else { return }
            let row = rows[r]
            let next = lead(of: row) + (direction == .right ? 1 : -1)
            guard row.items.indices.contains(next) else { return }
            withAnimation(reduceMotion ? nil : OrbitNetflixLayout.horizontal) { leads[row.id] = next }
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
            withAnimation(reduceMotion ? nil : OrbitNetflixLayout.vertical) { current = 0 }
            refreshAfterMove()
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

    /// After any move: the look-ahead (TMDB: logos, titled posters, ratings, producers) and the trailer.
    private func refreshAfterMove() {
        let rows = rows
        motion.stamp()
        var metaItems: [MetaPreview] = []
        if let billboardItem { metaItems.append(billboardItem) }
        let r = max(0, current - 1)
        for i in r...max(r, min(rows.count - 1, r + 1)) where rows.indices.contains(i) {
            let row = rows[i]
            let lead = lead(of: row)
            metaItems += row.items.indices.filter { $0 >= lead - 1 && $0 <= lead + 6 }.map { row.items[$0] }
        }
        // The Top 10 tiles draw TMDB's posters (his images carry their own numbers): all ten at once.
        metaItems += rows.filter(\.top10).flatMap(\.items)
        OrbitMetaStore.shared.request(metaItems)

        trailer.reset()
        trailerKey = nil
        guard trailersOn, canvasFocused, search == nil, UIAccessibility.isVideoAutoplayEnabled,
              let item = focusedItem else { return }
        trailer.prefersReducedMotion = reduceMotion
        trailer.restSource = .custom(motion)
        trailerKey = "\(item.type):\(item.id)"
        trailer.focusChanged(true, item: item)
    }
}

private struct OrbitNetflixCanvasStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

// MARK: - Pieces

/// "N SÉRIE" / "N FILM" above a Netflix title's logo.
private struct OrbitNetflixTag: View {
    let series: Bool
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: 6) {
            // Steven's own N (his add-on's image), not a letter.
            Image("NetflixN")
                .resizable()
                .scaledToFit()
                .frame(height: size * 1.2)
            Text(series ? String(localized: "SÉRIE") : String(localized: "FILM"))
                .font(.system(size: size * 0.8, weight: .bold))
                .kerning(size * 0.2)
                .foregroundStyle(Color.white.opacity(0.85))
        }
    }
}

/// The open tile's still, a little larger than the tile, gliding slowly to the left (Netflix's own
/// focus effect before its preview).
struct OrbitDriftImage: View {
    let url: String?
    let fallback: String?
    let size: CGSize

    @State private var drifting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let zoom: CGFloat = 1.1
        let travel = size.width * (zoom - 1) / 2
        OrbitImage(url: url, fallback: fallback, size: CGSize(width: size.width * zoom, height: size.height * zoom))
            .offset(x: drifting ? -travel : travel)
            .frame(width: size.width, height: size.height)
            .clipped()
            // Steven: it never moved — an animation started in the first appearance is dropped; a beat
            // later it runs. It goes on whether or not the billboard has the focus (back and forth).
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) { drifting = true }
            }
    }
}

/// His add-on's N on a poster: the same image, place and size (8 % of the height, 4.5 % / 3 % from
/// the corner), over the same light veil at the top.
private struct OrbitNetflixPosterN: View {
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(stops: [
                .init(color: .black.opacity(0.4), location: 0),
                .init(color: .clear, location: 0.16),
            ], startPoint: .top, endPoint: .bottom)
            Image("NetflixN")
                .resizable()
                .scaledToFit()
                .frame(height: size.height * 0.08)
                .padding(.leading, size.width * 0.045)
                .padding(.top, size.height * 0.03)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// Netflix's small red pill ("Récemment ajouté", "N° 3 des séries").
private struct OrbitNetflixBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 4).fill(OrbitNetflixLayout.red))
    }
}

/// "Drame · 2025 · 3 saisons · 16+".
private func netflixMeta(_ item: MetaPreview, _ meta: OrbitMeta?) -> String {
    var parts: [String] = []
    if let genre = meta?.genre ?? item.genres.first { parts.append(genre) }
    if let year = meta?.year ?? item.releaseInfo.map({ String($0.prefix(4)) }) { parts.append(year) }
    if let seasons = meta?.seasons, item.type != "movie" {
        parts.append(seasons == 1 ? String(localized: "1 saison") : String(localized: "\(String(seasons)) saisons"))
    } else if let runtime = meta?.runtime {
        parts.append(runtime)
    }
    if let certification = meta?.certification {
        parts.append(certification == "TP" ? String(localized: "Tous publics") : "\(certification)+")
    }
    return parts.joined(separator: "  ·  ")
}

/// Netflix's own title: Steven's add-on marks it in its poster's address ("/n/v13/…" in the lists,
/// "/poster/v13/o3/…" in the Top 10 — the posters with its N), else TMDB lists Netflix as a producer.
private func isNetflixOwn(_ item: MetaPreview, _ meta: OrbitMeta?) -> Bool {
    let poster: String = item.poster ?? ""
    if poster.contains("/n/v") || poster.range(of: #"/poster/v\d+/o"#, options: .regularExpression) != nil { return true }
    return meta?.producers.contains { $0.lowercased().contains("netflix") } ?? false
}

/// The billboard: a large rounded card at the top.
private struct OrbitNetflixBillboard: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let rank: Int?
    let series: Bool
    let focused: Bool
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let L = OrbitNetflixLayout.self
        let size = L.billboardSize
        let info = OrbitInfo.make(item, meta: meta)
        let banner: String? = item.banner
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.08)
            // Netflix (Steven's video): the billboard's still drifts slowly to the left until its trailer.
            OrbitDriftImage(url: banner ?? meta?.backdrop, fallback: nil, size: size)
                .id("\(item.type):\(item.id)")
            if let trailerURL {
                TrailerHeroPlayer(urlString: trailerURL, onFailure: onTrailerFailure,
                                  zoomKey: TrailerResolutionCache.key(type: item.type, id: item.id),
                                  loops: false, onPlaybackEnded: onTrailerEnded, cornerRadius: 20)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity.animation(.easeOut(duration: 0.6)))
            }
            LinearGradient(stops: [
                .init(color: .black.opacity(0.75), location: 0),
                .init(color: .black.opacity(0.2), location: 0.5),
                .init(color: .clear, location: 0.8),
            ], startPoint: .bottomLeading, endPoint: .topTrailing)
            VStack(alignment: .leading, spacing: 14) {
                if isNetflixOwn(item, meta) { OrbitNetflixTag(series: item.type != "movie", size: 22) }
                OrbitTitleMark(name: item.name, logo: info.logo, maxSize: CGSize(width: 600, height: 190), textSize: 64,
                               fallbackLogo: info.logoFallback, hugsLogo: true)
                    // Its own height (Steven: a wide logo left N FILM floating high above it).
                    .frame(width: 600, alignment: .leading)
                Text(netflixMeta(item, meta))
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(.leading, 48)
            .padding(.bottom, 44)
            if let rank {
                OrbitNetflixBadge(text: series ? String(localized: "N° \(String(rank)) des séries")
                                               : String(localized: "N° \(String(rank)) des films"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(32)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 0.95 : 0), lineWidth: 4)
        }
        .animation(.easeOut(duration: 0.18), value: focused)
        .allowsHitTesting(false)
    }
}

/// A row: its heading; the focused title open at the margin, the next ones in portrait; under the
/// open tile, its meta line and synopsis.
private struct OrbitNetflixRowView: View {
    let row: OrbitNetflixRow
    let lead: Int
    let isCurrent: Bool
    let focused: Bool
    let series: Bool
    let rank: Int?
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void
    @ObservedObject var metaStore: OrbitMetaStore

    var body: some View {
        let L = OrbitNetflixLayout.self
        let low = max(0, lead - 1)
        let window = low...max(low, min(row.items.count - 1, lead + 6))
        VStack(alignment: .leading, spacing: 0) {
            Text(row.title)
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(Color.white.opacity(isCurrent ? 1 : 0.55))
                .lineLimit(1)
                .frame(height: L.headingHeight, alignment: .topLeading)
                .padding(.leading, L.margin)
            ZStack(alignment: .topLeading) {
                if !row.items.isEmpty {
                    ForEach(Array(zip(window, row.items[window])), id: \.1.id) { index, item in
                        let open = isCurrent && index == lead
                        let meta = metaStore.meta(for: item)
                        HStack(alignment: .bottom, spacing: 0) {
                            if row.top10 { OrbitNetflixRank(rank: index + 1) }
                            OrbitNetflixTile(item: item, meta: meta, open: open, focused: focused && open,
                                             top10: row.top10,
                                             badge: open ? badge(rank: rank, fresh: row.fresh) : nil,
                                             trailerURL: open ? trailerURL : nil,
                                             onTrailerFailure: onTrailerFailure, onTrailerEnded: onTrailerEnded)
                        }
                        .offset(x: L.margin + row.x(of: index, lead: lead, opens: isCurrent))
                        .opacity(index < lead ? 0 : 1)
                    }
                }
            }
            .frame(width: OrbitHomeLayout.screenWidth, height: L.tileHeight, alignment: .topLeading)
            if isCurrent, row.items.indices.contains(lead) {
                let item = row.items[lead]
                let meta = metaStore.meta(for: item)
                let info = OrbitInfo.make(item, meta: meta)
                VStack(alignment: .leading, spacing: 10) {
                    Text(netflixMeta(item, meta))
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                    Text(info.synopsis)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineSpacing(3)
                        .lineLimit(3)
                        .frame(width: 1000, alignment: .topLeading)
                }
                .padding(.leading, L.margin + (row.top10 ? (lead == 9 ? L.rankWidthTen : L.rankWidth) : 0))
                .padding(.top, 18)
                .id("\(item.type):\(item.id)")
                .transition(.asymmetric(insertion: .opacity.animation(.easeInOut(duration: 0.2)), removal: .identity))
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func badge(rank: Int?, fresh: Bool) -> String? {
        if let rank, !row.top10 {
            return series ? String(localized: "N° \(String(rank)) des séries") : String(localized: "N° \(String(rank)) des films")
        }
        return fresh ? String(localized: "Récemment ajouté") : nil
    }
}

/// Netflix's rank: huge, outlined in grey, black inside.
private struct OrbitNetflixRank: View {
    let rank: Int

    var body: some View {
        let L = OrbitNetflixLayout.self
        // Steven: "10" showed as "…" (too wide for its room, the text truncated): never truncated,
        // and "10" drawn a bit narrower (tighter, slightly smaller) in a wider room.
        let text = Text("\(rank)")
            .font(.system(size: L.tileHeight * (rank == 10 ? 0.56 : 0.62), weight: .black))
            .kerning(rank == 10 ? -22 : -10)
        ZStack {
            // The outline: the number drawn around itself in grey, then black inside.
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * .pi / 4
                text.foregroundStyle(Color(white: 0.55))
                    .fixedSize()
                    .offset(x: cos(angle) * 3, y: sin(angle) * 3)
            }
            text.foregroundStyle(Color.black)
                .fixedSize()
        }
        .frame(width: rank == 10 ? L.rankWidthTen : L.rankWidth, height: L.tileHeight, alignment: .bottomTrailing)
        .offset(x: 24, y: 34)
    }
}

/// A title's tile: a tall portrait poster, or open (focused) as a large 16:9 tile with its logo, its
/// badge and its trailer.
private struct OrbitNetflixTile: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let open: Bool
    let focused: Bool
    let top10: Bool
    let badge: String?
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let L = OrbitNetflixLayout.self
        let size = CGSize(width: open ? L.openWidth : L.posterWidth, height: L.tileHeight)
        let info = OrbitInfo.make(item, meta: meta)
        let banner: String? = item.banner
        // The portrait art: TMDB's French poster when there is one (Steven: his posters were often
        // English), else his poster (his N already on it). His Top 10 images carry their numbers:
        // TMDB's poster there.
        let french: String? = meta?.localPoster
        let poster: String? = french ?? (top10 ? meta?.titledPoster : item.poster)
        // TMDB's art has no N: his N, drawn as his add-on draws it.
        let drawsN = (french != nil || top10) && isNetflixOwn(item, meta)
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.09)
            if open {
                OrbitImage(url: banner ?? meta?.backdrop, fallback: poster, size: size)
                if let trailerURL {
                    TrailerHeroPlayer(urlString: trailerURL, onFailure: onTrailerFailure,
                                      zoomKey: TrailerResolutionCache.key(type: item.type, id: item.id),
                                      loops: false, onPlaybackEnded: onTrailerEnded, cornerRadius: L.radius)
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity.animation(.easeOut(duration: 0.6)))
                }
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 8) {
                    if isNetflixOwn(item, meta) { OrbitNetflixTag(series: item.type != "movie", size: 17) }
                    OrbitTitleMark(name: item.name, logo: info.logo, maxSize: CGSize(width: 380, height: 120), textSize: 40,
                                   fallbackLogo: info.logoFallback, hugsLogo: true)
                        .frame(width: 380, alignment: .leading)
                }
                .padding(.leading, 24)
                .padding(.bottom, 22)
                if let badge {
                    OrbitNetflixBadge(text: badge)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(22)
                }
            } else {
                OrbitImage(url: poster, fallback: top10 ? nil : item.poster, mode: .fill, size: size)
                if drawsN { OrbitNetflixPosterN(size: size) }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: L.radius, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 0.95 : 0), lineWidth: 3)
        }
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}
