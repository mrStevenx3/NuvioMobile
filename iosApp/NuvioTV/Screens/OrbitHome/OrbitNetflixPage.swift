import Combine
import CoreText
import SharedCore
import SwiftUI
import UIKit

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
    // Steven (2026-10-27, Netflix's own app on video: "un maximum proche de l'application
    // officielle"): every size below measured on it (1080p).
    static let billboardTop: CGFloat = 143
    static let billboardSize = CGSize(width: OrbitHomeLayout.screenWidth - 2 * OrbitHomeLayout.margin, height: 765)
    /// The first row's heading under the billboard (it peeks on the first screen).
    static let rowsTop: CGFloat = 946
    /// The current row's heading once the billboard has gone.
    static let restTop: CGFloat = 148
    static let headingHeight: CGFloat = 54
    static let tileHeight: CGFloat = 506
    static var openWidth: CGFloat { tileHeight * 16 / 9 }
    /// 2:3, the posters' own shape (Steven: narrower, their N, drawn in the art, was cut at the left).
    static let posterWidth: CGFloat = 337
    static let gap: CGFloat = 18
    /// The open tile's meta line and synopsis (three lines), then the gap to the next heading.
    static let infoHeight: CGFloat = 205
    static let rowGap: CGFloat = 33
    static let radius: CGFloat = 8
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

    /// Steven (as on Netflix): a row runs on in a loop — after its last title, its first again —
    /// so its end never leaves the screen empty. The Top 10 stops at its 10th.
    var loops: Bool { !top10 && items.count > 1 }
    /// The strip's slots (the titles repeated, for the loop).
    var slotCount: Int { loops ? items.count * 30 : items.count }
    /// The title in slot `slot`.
    func item(atSlot slot: Int) -> Int { items.isEmpty ? 0 : slot % items.count }

    private func rankWidth(_ index: Int) -> CGFloat {
        guard top10 else { return 0 }
        return OrbitNetflixRank.width(index + 1)
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
    @StateObject private var trailer = OrbitNativeTrailerHost()
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true
    /// A title was opened over the page: no trailer starts again behind it (Steven: Prime's kept
    /// playing, its sound under the title's page).
    @State private var covered = false

    /// nil: Accueil (films and series together, Steven 2026-10-25); "movie"; "series".
    @State private var typeFilter: String? = nil
    /// 0: the billboard; then the rows.
    @State private var current = 0
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

    init(route: FolderRoute, push: @escaping (TitleRoute) -> Void) {
        self.route = route
        self.push = push
        _model = StateObject(wrappedValue: FolderDetailViewModel(route: route))
    }

    // MARK: Data

    private var series: Bool { typeFilter == "series" }

    /// His Nouveautés, his Top 10, then the genres (TMDB).
    /// Built once per change of what they are made of (fluidity: every press rebuilt them).
    @State private var rowsMemo = OrbitRowsMemo<[OrbitNetflixRow]>()

    private var rows: [OrbitNetflixRow] {
        rowsMemo.get(OrbitRowsKey(rows: model.stripRows, filter: typeFilter,
                                  extras: extras.movieRows + extras.seriesRows)) { buildRows() }
    }

    private func buildRows() -> [OrbitNetflixRow] {
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

    /// The focused title of a row (its slot, in a looping row, brought back to the title).
    private func lead(of row: OrbitNetflixRow) -> Int {
        let slot = leads[row.id] ?? 0
        return row.loops ? row.item(atSlot: slot) : min(slot, max(0, row.items.count - 1))
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
            // Netflix's own app: around its billboard the page is a deep grey-violet, black under
            // the rows.
            LinearGradient(colors: [Color(red: 0.15, green: 0.14, blue: 0.2), .black],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.9))
                .opacity(offset > 0 ? 0 : 1)
                .animation(.easeInOut(duration: 0.35), value: offset > 0)
                .allowsHitTesting(false)

                            nativeSections(rows, billboard: billboard)
                    .disabled(search != nil)
            

            // Under the bar: black, so the row above never shows through.
            LinearGradient(colors: [.black, .black.opacity(0.9), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(width: W, height: 110)
                .opacity(offset > 0 ? 1 : 0)
                .allowsHitTesting(false)

            if rows.isEmpty, model.isLoading {
                ProgressView().frame(width: W, height: H)
            }


            CollectionFilterBar(filter: $typeFilter, onSearch: openSearch, showsAll: true)
                .disabled(search != nil || (pageFocused && current > 0))
                .opacity(search != nil ? 0 : 1)

            // Steven: only his N in the corner (larger), not the whole Netflix word.
            OrbitPlatformIntro(title: model.folderTitle, logoUrl: model.titleLogoUrl ?? route.titleLogoUrl,
                               brand: OrbitNetflixLayout.red, assetLogo: "NetflixN", assetInColour: true)

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
        .background(Color.black)
        .ignoresSafeArea()
        .background { ViewerInputClockInstaller().frame(width: 0, height: 0) }
        .onAppear {
            covered = false
            tabBarVisibility.pushImmersive()
            OrbitHomeButtonHost.shared.enter(.ownBar)
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
            leads.reset()
            refreshAfterMove()
        }
    }

    /// The native page: the billboard and the rows as sections the system moves.
    private func nativeSections(_ rows: [OrbitNetflixRow], billboard: MetaPreview?) -> some View {
        let L = OrbitNetflixLayout.self
        return OrbitNativeSections(
            count: 1 + rows.count, hasHero: true,
            height: { s in s == 0 ? L.rowsTop - L.restTop : (rows.indices.contains(s - 1) ? rows[s - 1].height : 0) },
            topLine: L.restTop, current: current,
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
            line: { s in s == 0 ? L.restTop : L.restTop }
        ) { s, focused in
            if s == 0 {
                if let billboard {
                    OrbitNetflixBillboard(item: billboard, meta: metaStore.meta(for: billboard),
                                          rank: topRank(billboard), series: billboard.type != "movie",
                                          focused: focused,
                                          trailerURL: current == 0 ? trailerURL(for: billboard) : nil,
                                          onTrailerFailure: { trailer.playbackFailed($0) },
                                          onTrailerEnded: { trailer.playbackFinished() })
                        .offset(x: L.margin, y: L.billboardTop - L.restTop)
                }
            } else if rows.indices.contains(s - 1) {
                let row = rows[s - 1]
                let lead = lead(of: row)
                let item: MetaPreview? = row.items.indices.contains(lead) ? row.items[lead] : nil
                OrbitNetflixRowView(row: row, box: leads.box(row.id), isCurrent: s == current, focused: focused,
                                    series: item.map { $0.type != "movie" } ?? series,
                                    rank: item.flatMap { topRank($0) },
                                    rankOf: { topRank($0) },
                                    trailerURL: s == current ? trailerURL(for: item) : nil,
                                    onTrailerFailure: { trailer.playbackFailed($0) },
                                    onTrailerEnded: { trailer.playbackFinished() },
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
            withAnimation(reduceMotion ? nil : OrbitNetflixLayout.vertical) { current += 1 }
        case .up:
            guard current > 0 else { return }
            withAnimation(reduceMotion ? nil : OrbitNetflixLayout.vertical) { current -= 1 }
        case .left, .right:
            let r = current - 1
            guard rows.indices.contains(r) else { return }
            let row = rows[r]
            let next = (leads[row.id] ?? 0) + (direction == .right ? 1 : -1)
            guard next >= 0, next < row.slotCount else { return }
            withAnimation(reduceMotion ? nil : OrbitNetflixLayout.horizontal) { leads[row.id] = next }
        @unknown default:
            return
        }
        refreshAfterMove()
    }

    /// The detail page's Netflix touch.
    private func detailPlatform(_ item: MetaPreview) -> OrbitDetailPlatform {
        OrbitDetailPlatform(theme: .netflix, own: isNetflixOwn(item, metaStore.meta(for: item)) ? .netflix : nil,
                            logoUrl: model.titleLogoUrl ?? route.titleLogoUrl)
    }

    private func select() {
        covered = true
        trailer.reset(abortStages: true)
        if let focusedItem { push(TitleRoute(preview: focusedItem, platform: detailPlatform(focusedItem))) }
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
        guard trailersOn, !covered, pageFocused, search == nil, UIAccessibility.isVideoAutoplayEnabled,
              let item = focusedItem else { return }
        trailer.prefersReducedMotion = reduceMotion
        trailer.restSource = .custom(motion)
        trailerKey = "\(item.type):\(item.id)"
        trailer.focusChanged(true, item: item)
    }
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
        // Steven (device: one image for a second, then another): the art stays until the next one
        // is ready, then cross-fades (never an empty or interim frame).
        OrbitSwapImage(url: url, fallback: fallback, size: CGSize(width: size.width * zoom, height: size.height * zoom))
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

/// One of Netflix's pills: its small icon, then its words.
struct OrbitNetflixPillInfo {
    enum Icon { case new, top10, liked }
    let icon: Icon?
    let text: String
}

/// Netflix's pill (its own app): a dark translucent box, a small coloured icon, white words.
private struct OrbitNetflixPill: View {
    let info: OrbitNetflixPillInfo
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: 8) {
            if let icon = info.icon { OrbitNetflixPillIcon(icon: icon, size: size) }
            Text(info.text)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.62)))
    }
}

/// The pills' icons: the TOP 10 square, the new one, the thumb.
private struct OrbitNetflixPillIcon: View {
    let icon: OrbitNetflixPillInfo.Icon
    let size: CGFloat

    var body: some View {
        switch icon {
        case .top10:
            VStack(spacing: -size * 0.12) {
                Text("TOP").font(.system(size: size * 0.32, weight: .heavy))
                Text("10").font(.system(size: size * 0.6, weight: .black))
            }
            .foregroundStyle(Color.white)
            .frame(width: size * 0.95, height: size * 1.05)
            .background(RoundedRectangle(cornerRadius: 2).fill(OrbitNetflixLayout.red))
        case .new:
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.8, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.25, blue: 0.45), OrbitNetflixLayout.red],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .liked:
            Image(systemName: "hand.thumbsup.fill")
                .font(.system(size: size * 0.8, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.95, green: 0.3, blue: 0.6), Color(red: 0.55, green: 0.3, blue: 0.95)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

/// "N° 3 des séries".
private func netflixRankLabel(_ rank: Int, series: Bool) -> String {
    series ? String(localized: "N° \(String(rank)) des séries") : String(localized: "N° \(String(rank)) des films")
}

/// Netflix's words for what is new.
private func netflixNewsLabel(_ news: OrbitTitleNews) -> String {
    switch news {
    case .newSeason: return String(localized: "Nouvelle saison")
    case .newEpisodes: return String(localized: "Nouveaux épisodes")
    case .soon: return String(localized: "Bientôt disponible")
    }
}

/// Netflix's label at the foot of a poster (its own app): white words over the poster's dark foot,
/// with the TOP 10 square before a rank.
private struct OrbitNetflixFootLabel: View {
    let info: OrbitNetflixPillInfo

    var body: some View {
        HStack(spacing: 6) {
            if let icon = info.icon { OrbitNetflixPillIcon(icon: icon, size: 16) }
            Text(info.text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .shadow(color: .black.opacity(0.8), radius: 4)
        .padding(.horizontal, 8)
        .padding(.top, 30)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
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
    return parts.joined(separator: "  •  ")
}

/// Netflix's own title: Steven's add-on marks it in its poster's address ("/n/v13/…" in the lists,
/// "/poster/v13/o3/…" in the Top 10 — the posters with its N), else TMDB lists Netflix as a producer.
private func isNetflixOwn(_ item: MetaPreview, _ meta: OrbitMeta?) -> Bool {
    // Steven: OFFICIER CID (1998) showed N SÉRIE — Netflix only carries it. Netflix's own titles
    // start in 2012 (Lilyhammer): anything older is never one of them.
    if let info = item.releaseInfo,
       let range = info.range(of: #"(19|20)\d{2}"#, options: .regularExpression),
       let year = Int(info[range]), year < 2012 { return false }
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
            // Netflix's own billboard (Steven's video): the logo, the meta line, three lines of
            // synopsis, then Lecture and Plus d'infos; a pill bottom right.
            VStack(alignment: .leading, spacing: 0) {
                if isNetflixOwn(item, meta) {
                    OrbitNetflixTag(series: item.type != "movie", size: 22)
                        .padding(.bottom, 12)
                }
                OrbitTitleMark(name: item.name, logo: info.logo, maxSize: CGSize(width: 560, height: 200), textSize: 72,
                               fallbackLogo: info.logoFallback, hugsLogo: true)
                    // Its own height (Steven: a wide logo left N FILM floating high above it).
                    .frame(width: 560, alignment: .leading)
                Text(netflixMeta(item, meta))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(1)
                    .padding(.top, 22)
                Text(info.synopsis)
                    .font(.system(size: 27, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineSpacing(4)
                    .lineLimit(3)
                    .frame(width: 640, alignment: .topLeading)
                    .padding(.top, 14)
                HStack(spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill").font(.system(size: 24, weight: .bold))
                        Text(String(localized: "Lecture")).font(.system(size: 28, weight: .semibold))
                    }
                    .foregroundStyle(focused ? Color.black : Color.white)
                    .padding(.horizontal, 34)
                    .frame(height: 76)
                    .background(Capsule().fill(focused ? Color.white : Color.white.opacity(0.22)))
                    Text(String(localized: "Plus d'infos"))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 34)
                        .frame(height: 76)
                        .background(Capsule().fill(Color.white.opacity(0.22)))
                }
                .padding(.top, 34)
            }
            .padding(.leading, 30)
            .padding(.bottom, 32)
            if let pill = billboardPill {
                OrbitNetflixPill(info: pill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(32)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // (Netflix: no frame around it — its Lecture button shows the focus.)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.5)
        }
        .animation(.easeOut(duration: 0.18), value: focused)
        .allowsHitTesting(false)
    }

    private var billboardPill: OrbitNetflixPillInfo? {
        if let rank { return .init(icon: .top10, text: netflixRankLabel(rank, series: series)) }
        if let news = OrbitTitleNews.of(item, meta) { return .init(icon: .new, text: netflixNewsLabel(news)) }
        return .init(icon: .liked, text: String(localized: "Vous devriez aimer"))
    }
}

/// A row: its heading; the focused title open at the margin, the next ones in portrait; under the
/// open tile, its meta line and synopsis.
private struct OrbitNetflixRowView: View {
    let row: OrbitNetflixRow

    /// The landscape art of the titles next to the open one, decoded at the open tile's size
    /// before the focus gets there (Steven: grey between each step).
    private func prefetchOpenArt(around index: Int) {
        let L = OrbitNetflixLayout.self
        let request = ArtworkDecodeRequest(size: .points(width: L.openWidth, height: L.tileHeight), fill: true,
                                           scale: UIScreen.main.scale).normalized
        for i in max(0, index - 1)...min(row.items.count - 1, index + 3) where i != index {
            let item = row.items[i]
            let banner: String? = item.banner
            guard let raw = (banner ?? metaStore.meta(for: item)?.backdrop).flatMap(URL.init(string:)) else { continue }
            // The address the open tile asks first (TMDB's original, as `OrbitSwapImage` does).
            let address = ArtworkURLUpgrade.upgraded(raw, role: .backdrop) ?? raw
            guard ArtworkStore.cached(address, decode: request) == nil else { continue }
            Task { _ = try? await ArtworkStore.fetch(address, decode: request) }
        }
    }

    @ObservedObject var box: OrbitLeadBox
    let isCurrent: Bool
    let focused: Bool
    let series: Bool
    let rank: Int?
    /// The title is in one of the page's Top 10s (Netflix's red TOP 10 mark on its poster).
    var rankOf: (MetaPreview) -> Int? = { _ in nil }
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void
    @ObservedObject var metaStore: OrbitMetaStore
    let onEnter: () -> Void
    let onLeave: () -> Void
    let onSelect: () -> Void
    let onLeadChange: () -> Void

    var body: some View {
        let L = OrbitNetflixLayout.self
        let leadSlot = min(box.lead, max(0, row.slotCount - 1))
        let lead = row.item(atSlot: leadSlot)
        VStack(alignment: .leading, spacing: 0) {
            Text(row.title)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isCurrent ? 1 : 0.55))
                .lineLimit(1)
                .frame(height: L.headingHeight, alignment: .topLeading)
                .padding(.leading, L.margin)
            // Real buttons the system slides (Steven: the touch surface, fluidity).
            // (The Top 10 ends at its edge: no room after its 10th — Steven: the screen went empty.)
            OrbitNativeTileStrip(count: row.slotCount, spacing: L.gap, height: L.tileHeight,
                                 lastWidth: row.top10 ? OrbitHomeLayout.screenWidth : L.openWidth, box: box,
                                 keepsLeadAtMargin: true,
                                 onEnter: onEnter, onLeave: onLeave, onSelect: onSelect,
                                 onLeadChange: { new in
                                     onLeadChange()
                                     prefetchOpenArt(around: row.item(atSlot: new))
                                 }) { slot, lit in
                let index = row.item(atSlot: slot)
                let item = row.items[index]
                let open = isCurrent && slot == leadSlot
                HStack(alignment: .bottom, spacing: 0) {
                    if row.top10 { OrbitNetflixRank(rank: index + 1) }
                    let meta = metaStore.meta(for: item)
                    OrbitNetflixTile(item: item, meta: meta, open: open, focused: lit,
                                     top10: row.top10,
                                     badges: open ? badges(rank: rank, fresh: row.fresh, news: OrbitTitleNews.of(item, meta)) : [],
                                     foot: footLabel(item, meta),
                                     trailerURL: open ? trailerURL : nil,
                                     onTrailerFailure: onTrailerFailure, onTrailerEnded: onTrailerEnded)
                }
            }
            .frame(width: OrbitHomeLayout.screenWidth, height: L.tileHeight, alignment: .topLeading)
            // Steven (device: the text ran over the posters while the page moved): the details of
            // the row the page arrives at wait for the move to end, then fade in; leaving, they go
            // at once.
            if row.items.indices.contains(lead) {
                let item = row.items[lead]
                let meta = metaStore.meta(for: item)
                let info = OrbitInfo.make(item, meta: meta)
                VStack(alignment: .leading, spacing: 12) {
                    Text(netflixMeta(item, meta))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(1)
                    Text(info.synopsis)
                        .font(.system(size: 27, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineSpacing(4)
                        .lineLimit(3)
                        .frame(width: 990, alignment: .topLeading)
                }
                .padding(.leading, L.margin + (row.top10 ? OrbitNetflixRank.width(lead + 1) : 0))
                // (Steven: further from the open tile, which grows when focused; the row's height
                // unchanged — taken from the gap under it.)
                .padding(.top, 26)
                .id("\(item.type):\(item.id)")
                // Steven (video: two synopses over each other, the one left over the next row's
                // title): the old text goes at once, the new one fades in; leaving the row, at once.
                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2)), removal: .identity))
                .opacity(isCurrent ? 1 : 0)
                .animation(isCurrent ? .easeOut(duration: 0.22).delay(0.08) : nil, value: isCurrent)
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
    }

    /// The open tile's pills, as Netflix shows them side by side: what is new, then its rank.
    private func badges(rank: Int?, fresh: Bool, news: OrbitTitleNews?) -> [OrbitNetflixPillInfo] {
        var out: [OrbitNetflixPillInfo] = []
        if let news { out.append(.init(icon: .new, text: netflixNewsLabel(news))) }
        else if fresh { out.append(.init(icon: .new, text: String(localized: "Récemment ajouté"))) }
        if let rank, !row.top10 { out.append(.init(icon: .top10, text: netflixRankLabel(rank, series: series))) }
        return out
    }

    /// The label at a poster's foot (Netflix: "Nouvelle saison", or its rank "N° 7 des séries").
    private func footLabel(_ item: MetaPreview, _ meta: OrbitMeta?) -> OrbitNetflixPillInfo? {
        if let news = OrbitTitleNews.of(item, meta) { return .init(icon: nil, text: netflixNewsLabel(news)) }
        if !row.top10, let rank = rankOf(item) {
            return .init(icon: .top10, text: netflixRankLabel(rank, series: item.type != "movie"))
        }
        return nil
    }
}

/// Netflix's rank (its own app, Steven's photos side by side): a wide figure drawn as a thin grey
/// line, black inside, its top level with the tile's, its right part tucked behind the tile.
private struct OrbitNetflixRank: View {
    let rank: Int

    /// The figure's height (Steven's photo of the real app: 43 % of the tile).
    static var figureHeight: CGFloat { OrbitNetflixLayout.tileHeight * 0.43 }
    /// How far the figure goes behind its tile.
    static let tuck: CGFloat = 26
    /// The gap between the previous tile and the figure.
    static let lead: CGFloat = 30

    static func figureWidth(_ rank: Int) -> CGFloat {
        figureHeight * OrbitGlyphShape.aspect("\(rank)", tracking: rank == 10 ? -0.02 : 0)
    }

    /// The room the figure takes before its tile.
    static func width(_ rank: Int) -> CGFloat { lead + figureWidth(rank) - tuck }

    var body: some View {
        let height = Self.figureHeight
        let width = Self.figureWidth(rank)
        let shape = OrbitGlyphShape(text: "\(rank)", tracking: rank == 10 ? -0.02 : 0)
        shape.fill(Color.black)
            .overlay {
                // Netflix: a light grey line, fading into the tile's shadow just before the tile.
                shape.stroke(LinearGradient(stops: [
                    .init(color: Color(white: 0.5), location: 0),
                    .init(color: Color(white: 0.46), location: 0.62),
                    .init(color: Color(white: 0.12), location: 0.9),
                ], startPoint: .leading, endPoint: .trailing),
                             style: StrokeStyle(lineWidth: 3.5, lineJoin: .round))
            }
            .frame(width: width, height: height)
            // Its right part behind the tile (drawn after it, over it).
            .padding(.leading, Self.lead)
            .frame(width: Self.width(rank), height: OrbitNetflixLayout.tileHeight, alignment: .topLeading)
            .padding(.top, 2)
    }
}

/// A text's glyphs as one shape, filling its frame (its drawn edges on the frame's).
struct OrbitGlyphShape: Shape {
    let text: String
    var tracking: CGFloat = 0

    private static var cache: [String: CGPath] = [:]

    /// The glyphs' outline at 200 pt, overlaps merged, its box at the origin.
    static func outline(_ text: String, tracking: CGFloat) -> CGPath {
        let key = "\(text)|\(tracking)"
        if let path = cache[key] { return path }
        let font = UIFont.systemFont(ofSize: 200, weight: .bold)
        let ctFont = font as CTFont
        let chars = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        CTFontGetGlyphsForCharacters(ctFont, chars, &glyphs, chars.count)
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, glyphs, &advances, glyphs.count)
        let combined = CGMutablePath()
        var x: CGFloat = 0
        for (i, glyph) in glyphs.enumerated() {
            if let g = CTFontCreatePathForGlyph(ctFont, glyph, nil) {
                // Flipped: CoreText draws upwards.
                combined.addPath(g, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x, ty: 0))
            }
            x += advances[i].width + tracking * 200
        }
        // (The system font's contours overlap — stroked, the overlaps showed inside the figure.)
        let whole = combined.normalized(using: .winding)
        let box = whole.boundingBoxOfPath
        var t = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        let path = whole.copy(using: &t) ?? whole
        cache[key] = path
        return path
    }

    /// Width over height of the drawn glyphs.
    static func aspect(_ text: String, tracking: CGFloat = 0) -> CGFloat {
        let box = outline(text, tracking: tracking).boundingBoxOfPath
        return box.height > 0 ? box.width / box.height : 0.6
    }

    func path(in rect: CGRect) -> Path {
        let path = Self.outline(text, tracking: tracking)
        let box = path.boundingBoxOfPath
        guard box.width > 0, box.height > 0 else { return Path() }
        var t = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / box.width, y: rect.height / box.height)
        return Path(path.copy(using: &t) ?? path)
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
    /// The open tile's pills (bottom right).
    var badges: [OrbitNetflixPillInfo] = []
    /// Netflix's label at the foot of the poster ("Nouvelle saison", "Nouveaux épisodes",
    /// "Bientôt disponible").
    /// The label at the poster's foot.
    var foot: OrbitNetflixPillInfo? = nil
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
        let closedSize = CGSize(width: L.posterWidth, height: L.tileHeight)
        let openSize = CGSize(width: L.openWidth, height: L.tileHeight)
        let shape = RoundedRectangle(cornerRadius: L.radius, style: .continuous)
        // Steven (2026-10-26: "exactement comme dans Nouveaux films de l'accueil"): the closed poster
        // is always there, drawn whole at its own size; the open frame is a view of its own at its
        // full size, fading in over it on the row's curve — no pane revealed from one side as the
        // tile widens, no grey: under the frame's art there is the poster, not an empty box.
        ZStack(alignment: .topLeading) {
            ZStack {
                Color(white: 0.09)
                // (Before TMDB answers for a Top 10 title, the catalog's poster rather than black.)
                OrbitImage(url: poster ?? item.poster, fallback: top10 ? nil : item.poster, mode: .fill, size: closedSize)
                if drawsN { OrbitNetflixPosterN(size: closedSize) }
                if let foot {
                    OrbitNetflixFootLabel(info: foot)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(width: closedSize.width, height: closedSize.height)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.white.opacity(focused && !open ? 0.95 : 0), lineWidth: 3) }
            if open {
                ZStack(alignment: .bottomLeading) {
                    // (Steven's video: the poster stretched under the art showed as a coloured smear
                    // while the row came in — the page's own dark until the art, fetched ahead, lands.)
                    Color(white: 0.09)
                    OrbitSwapImage(url: banner ?? meta?.backdrop, fallback: nil, size: openSize)
                    if let trailerURL {
                        TrailerHeroPlayer(urlString: trailerURL, onFailure: onTrailerFailure,
                                          zoomKey: TrailerResolutionCache.key(type: item.type, id: item.id),
                                          loops: false, onPlaybackEnded: onTrailerEnded, cornerRadius: L.radius)
                            .frame(width: openSize.width, height: openSize.height)
                            .transition(.opacity.animation(.easeOut(duration: 0.6)))
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 8) {
                        if isNetflixOwn(item, meta) { OrbitNetflixTag(series: item.type != "movie", size: 17) }
                        OrbitTitleMark(name: item.name, logo: info.logo, maxSize: CGSize(width: 330, height: 104), textSize: 36,
                                       fallbackLogo: info.logoFallback, hugsLogo: true)
                            .frame(width: 330, alignment: .leading)
                    }
                    .padding(.leading, 24)
                    .padding(.bottom, 22)
                    if !badges.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(badges.indices, id: \.self) { OrbitNetflixPill(info: badges[$0]) }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(20)
                    }
                }
                .frame(width: openSize.width, height: openSize.height)
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.white.opacity(focused ? 0.95 : 0), lineWidth: 3) }
                // (Steven: the open art came in dark, then lit up — a quicker fade.)
                .transition(.opacity.animation(.easeOut(duration: 0.14)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        // (Steven, device: the focused tile rose before the others — its focus follows the move's own curve.)
    }
}
