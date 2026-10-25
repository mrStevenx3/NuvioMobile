import Combine
import SharedCore
import SwiftUI

// Orbit × Prime Video (Steven, 2026-10-25, pass 2, after his photos of Prime Video's 2025 look): the
// Prime Video folder in Prime's style, Orbit's DNA kept (one focusable canvas; the collection bar top
// left with the house, Films / Séries as tabs switching on focus; the intro).
//
//  - Prime's blue-black. The hero: the new titles in turn, the art across the page (still — Prime
//    plays the trailer, no drift), "prime" above the logo for Amazon's own titles, the green "Série
//    n° 2 en France" line for a title of the Top 10, two lines of synopsis, the age box, the dots;
//    the trailer starts on a rest whether or not the hero has the focus.
//  - "Amazon Original et exclusivités": tall portrait posters; the focused one opens into a large
//    16:9 card (logo, Plus d'informations, the green line, the chips).
//  - The other rows: 16:9 tiles (TMDB's backdrop, the title's French logo, "prime" on Amazon's own,
//    a white badge top right on the new ones); the focused one grows into a card with its summary.
//  - The Top 10: Prime's big solid grey ranks, partly behind each 16:9 tile.

enum OrbitPrimeLayout {
    static let background = Color(red: 0.03, green: 0.05, blue: 0.09)
    static let green = Color(red: 0.16, green: 0.84, blue: 0.55)
    static let blue = Color(red: 0.10, green: 0.55, blue: 0.95)
    static let margin: CGFloat = OrbitHomeLayout.margin
    static let heroHeight: CGFloat = 860
    static let infoTop: CGFloat = 250
    static let logoSize = CGSize(width: 560, height: 210)
    static let synopsisWidth: CGFloat = 820
    static let rowsTop: CGFloat = 840
    static let restTop: CGFloat = 150
    static let headingHeight: CGFloat = 54
    // Measured on Steven's photos (a 2000-pixel-wide page), at 1920.
    static let tile = CGSize(width: 290, height: 163)
    static let gap: CGFloat = 20
    static let grownScale: CGFloat = 1.6
    static let panelHeight: CGFloat = 210
    static let poster = CGSize(width: 292, height: 438)
    static var openWidth: CGFloat { poster.height * 16 / 9 }
    static let top10Tile = CGSize(width: 288, height: 162)
    static let rankWidth: CGFloat = 84
    /// How far the rank runs under its tile.
    static let rankTuck: CGFloat = 40
    static let rowGap: CGFloat = 44
    static let radius: CGFloat = 10
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
        case .top10: return OrbitPrimeLayout.top10Tile.height
        }
    }

    var height: CGFloat { OrbitPrimeLayout.headingHeight + cardHeight + OrbitPrimeLayout.rowGap }

    /// A title's slot width (the focused one open on the originals row).
    func slot(_ index: Int, lead: Int, current: Bool) -> CGFloat {
        let L = OrbitPrimeLayout.self
        switch kind {
        case .tiles: return L.tile.width
        case .originals: return current && index == lead ? L.openWidth : L.poster.width
        case .top10: return L.rankWidth + L.top10Tile.width
        }
    }

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
    @StateObject private var trailer = InlineTrailerCardModel()
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true

    @State private var typeFilter: String? = "movie"
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

    private var series: Bool { typeFilter == "series" }

    private struct Catalog {
        let id: String
        let heading: String
        let items: [MetaPreview]
        let top10: Bool
        let fresh: Bool
    }

    private var catalogs: [Catalog] {
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

    /// His Nouveautés, Amazon's own titles (portrait), his Top 10, then the genres (TMDB).
    private var rows: [OrbitPrimeRow] {
        let extraRows = series ? extras.seriesRows : extras.movieRows
        let all = catalogs
        var out: [OrbitPrimeRow] = []
        for c in all where c.fresh {
            out.append(OrbitPrimeRow(id: c.id, title: c.heading, items: c.items, kind: .tiles))
        }
        var seen = Set<String>()
        let own = all.flatMap(\.items)
            .filter { orbitPrimeIsOwn($0) && seen.insert(Self.identity($0)).inserted }
        if own.count >= 4 {
            out.append(OrbitPrimeRow(id: "prime-originals-\(series)",
                                     title: series ? String(localized: "Programmes Amazon Original et exclusivités")
                                                   : String(localized: "Films Amazon Original et exclusivités"),
                                     items: Array(own.prefix(20)), kind: .originals))
        }
        for c in all where c.top10 {
            out.append(OrbitPrimeRow(id: c.id,
                                     title: series ? String(localized: "Top 10 des séries en France")
                                                   : String(localized: "Top 10 des films en France"),
                                     items: Array(c.items.prefix(10)), kind: .top10))
        }
        if extraRows.isEmpty {
            for c in all where !c.fresh && !c.top10 {
                out.append(OrbitPrimeRow(id: c.id, title: c.heading, items: c.items, kind: .tiles))
            }
        }
        var shown = Set(out.flatMap { $0.items.map(Self.identity) })
        for extra in extraRows {
            let fresh = extra.items.filter { !shown.contains(Self.identity($0)) && $0.banner != nil }
            guard fresh.count >= 8 else { continue }
            let kept = Array(fresh.prefix(24))
            kept.forEach { shown.insert(Self.identity($0)) }
            out.append(OrbitPrimeRow(id: extra.id,
                                     title: "\(extra.title) – \(series ? String(localized: "Séries") : String(localized: "Films"))",
                                     items: kept, kind: .tiles))
        }
        return out
    }

    private static func identity(_ item: MetaPreview) -> String {
        let year: String = item.releaseInfo.map { String($0.prefix(4)) } ?? ""
        return item.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) + "|" + year
    }

    /// The new titles (the white badge).
    private var freshIdentities: Set<String> {
        Set(catalogs.filter(\.fresh).flatMap { $0.items.map(Self.identity) })
    }

    private var heroItems: [MetaPreview] {
        let source = catalogs.first(where: \.fresh) ?? catalogs.first
        return Array((source?.items ?? []).prefix(6))
    }

    private var heroItem: MetaPreview? {
        let items = heroItems
        return items.isEmpty ? nil : items[min(heroIndex, items.count - 1)]
    }

    private func topRank(_ item: MetaPreview) -> Int? {
        guard let top = catalogs.first(where: \.top10) else { return nil }
        return top.items.prefix(10).firstIndex { Self.identity($0) == Self.identity(item) }.map { $0 + 1 }
    }

    /// "Série n° 2 en France".
    private func rankLine(_ item: MetaPreview) -> String? {
        topRank(item).map { rank in
            item.type == "movie" ? String(localized: "Film n° \(String(rank)) en France")
                                 : String(localized: "Série n° \(String(rank)) en France")
        }
    }

    private func badge(_ item: MetaPreview) -> String? {
        guard freshIdentities.contains(Self.identity(item)) else { return nil }
        return item.type == "movie" ? String(localized: "NOUVEAU FILM") : String(localized: "NOUVELLE SÉRIE")
    }

    private var sectionCount: Int { 1 + rows.count }

    private func rowTops(_ rows: [OrbitPrimeRow]) -> [CGFloat] {
        var y = OrbitPrimeLayout.rowsTop
        return rows.map { row in defer { y += row.height }; return y }
    }

    private func scroll(_ rows: [OrbitPrimeRow]) -> CGFloat {
        let r = current - 1
        guard r >= 0, rows.indices.contains(r) else { return 0 }
        return rowTops(rows)[r] - OrbitPrimeLayout.restTop
    }

    private func lead(of row: OrbitPrimeRow) -> Int {
        min(leads[row.id] ?? 0, max(0, row.items.count - 1))
    }

    private var focusedItem: MetaPreview? {
        if current == 0 { return heroItem }
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
        let hero = heroItem

        ZStack(alignment: .topLeading) {
            OrbitPrimeLayout.background

            ZStack(alignment: .topLeading) {
                if let hero {
                    OrbitPrimeHero(item: hero, meta: metaStore.meta(for: hero), line: rankLine(hero),
                                   count: heroItems.count, index: min(heroIndex, max(0, heroItems.count - 1)),
                                   trailerURL: current == 0 ? trailerURL(for: hero) : nil,
                                   onTrailerFailure: { trailer.playbackFailed($0) },
                                   onTrailerEnded: {
                                       trailer.playbackFinished()
                                       advanceHero()
                                   })
                        .opacity(current <= 1 ? 1 : 0)
                }
                rowsLayer(rows)
            }
            .offset(y: -offset)
            .animation(reduceMotion ? nil : OrbitPrimeLayout.vertical, value: offset)

            LinearGradient(colors: [OrbitPrimeLayout.background, OrbitPrimeLayout.background.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: W, height: 130)
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
            .buttonStyle(OrbitPrimeCanvasStyle())
            .focused($canvasFocused)
            .onMoveCommand(perform: move)
            .onExitCommand(perform: exitAction())
            .offset(y: 110)
            .disabled(search != nil)

            CollectionFilterBar(filter: $typeFilter, onSearch: openSearch)
                .disabled(search != nil || (canvasFocused && current > 0))
                .opacity(search != nil ? 0 : 1)

            OrbitPlatformIntro(title: model.folderTitle, logoUrl: model.titleLogoUrl ?? route.titleLogoUrl,
                               brand: OrbitPrimeLayout.blue)

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
        .background(OrbitPrimeLayout.background)
        .ignoresSafeArea()
        .background { ViewerInputClockInstaller().frame(width: 0, height: 0) }
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
        .onChange(of: model.stripRows.map(\.id), initial: true) { _, _ in
            let all = model.stripRows
            if typeFilter == "movie", !all.isEmpty, CollectionTypeFilter.rows(all, filter: "movie").isEmpty,
               !CollectionTypeFilter.rows(all, filter: "series").isEmpty {
                typeFilter = "series"
            }
        }
    }

    @ViewBuilder
    private func rowsLayer(_ rows: [OrbitPrimeRow]) -> some View {
        let tops = rowTops(rows)
        let currentRow = current - 1
        let low = max(0, currentRow)
        let high = min(rows.count - 1, max(currentRow, 0) + 4)
        ZStack(alignment: .topLeading) {
            if low <= high {
                ForEach(low...high, id: \.self) { i in
                    let row = rows[i]
                    let lead = lead(of: row)
                    let item: MetaPreview? = row.items.indices.contains(lead) ? row.items[lead] : nil
                    OrbitPrimeRowView(row: row, lead: lead, isCurrent: i == currentRow,
                                      focused: canvasFocused && i == currentRow,
                                      line: item.flatMap { rankLine($0) },
                                      badges: Dictionary(row.items.map { ($0.id, badge($0) ?? "") },
                                                         uniquingKeysWith: { a, _ in a }),
                                      metaStore: metaStore)
                        .offset(y: tops[i])
                        // The current row's grown card spills over the rows below: drawn above them.
                        .zIndex(i == currentRow ? 1 : 0)
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
            withAnimation(reduceMotion ? nil : OrbitPrimeLayout.vertical) { current += 1 }
        case .up:
            guard current > 0 else { return }
            withAnimation(reduceMotion ? nil : OrbitPrimeLayout.vertical) { current -= 1 }
        case .left, .right:
            let step = direction == .right ? 1 : -1
            if current == 0 {
                let n = heroItems.count
                guard n > 1 else { return }
                withAnimation(.easeInOut(duration: 0.3)) { heroIndex = (heroIndex + step + n) % n }
            } else {
                let r = current - 1
                guard rows.indices.contains(r) else { return }
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

    private func select() {
        if let focusedItem { push(TitleRoute(preview: focusedItem)) }
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
        guard n > 1 else { return }
        withAnimation(.easeInOut(duration: 0.5)) { heroIndex = (heroIndex + 1) % n }
        motion.stamp()
        refreshAfterMove()
    }

    /// The carousel moves on by itself after a long rest with no trailer playing.
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
        var metaItems: [MetaPreview] = heroItems
        let r = max(0, current - 1)
        for i in r...max(r, min(rows.count - 1, r + 3)) where rows.indices.contains(i) {
            let row = rows[i]
            let lead = lead(of: row)
            metaItems += row.items.indices.filter { $0 >= lead - 1 && $0 <= lead + 8 }.map { row.items[$0] }
        }
        OrbitMetaStore.shared.request(metaItems)

        trailer.reset()
        trailerKey = nil
        // Prime: the hero's trailer plays whether or not the hero has the focus (the bar can).
        guard trailersOn, current == 0, search == nil, UIAccessibility.isVideoAutoplayEnabled,
              let item = heroItem else { return }
        trailer.prefersReducedMotion = reduceMotion
        trailer.restSource = .custom(motion)
        trailerKey = "\(item.type):\(item.id)"
        trailer.focusChanged(true, item: item)
    }
}

private struct OrbitPrimeCanvasStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

// MARK: - Pieces

/// "prime" with Amazon's smile, as on Prime's tiles.
private struct OrbitPrimeMark: View {
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

private struct OrbitPrimeSmile: Shape {
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

/// The white badge top right ("NOUVEAU FILM").
private struct OrbitPrimeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Rectangle().fill(Color.white))
    }
}

/// "[NOUVEAU FILM] [16+] Drame  1 h 51".
private struct OrbitPrimeChips: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let badge: String?

    var body: some View {
        let info = OrbitInfo.make(item, meta: meta)
        HStack(spacing: 10) {
            if let badge, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white))
            }
            if let certification = meta?.certification {
                Text(certification == "TP" ? String(localized: "TOUS PUBLICS") : "\(certification)+")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.25)))
            }
            Text(info.parts.joined(separator: "  "))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1)
        }
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

/// The hero: the still art across the page, its trailer on a rest; the text on the left.
private struct OrbitPrimeHero: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let line: String?
    let count: Int
    let index: Int
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let L = OrbitPrimeLayout.self
        let size = CGSize(width: OrbitHomeLayout.screenWidth, height: L.heroHeight)
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
                    .init(color: L.background.opacity(0.95), location: 0),
                    .init(color: L.background.opacity(0.5), location: 0.38),
                    .init(color: .clear, location: 0.62),
                ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.55),
                    .init(color: L.background.opacity(0.85), location: 0.85),
                    .init(color: L.background, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            VStack(alignment: .leading, spacing: 0) {
                if orbitPrimeIsOwn(item) {
                    OrbitPrimeMark(size: 30, color: L.blue)
                        .padding(.bottom, 10)
                }
                OrbitTitleMark(name: item.name, logo: info.logo, maxSize: L.logoSize, textSize: 64,
                               fallbackLogo: info.logoFallback, hugsLogo: true)
                    .frame(width: L.logoSize.width, alignment: .leading)
                if let line {
                    OrbitPrimeLine(text: line)
                        .padding(.top, 22)
                }
                Text(info.synopsis)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineSpacing(4)
                    .lineLimit(2)
                    .frame(width: L.synopsisWidth, alignment: .topLeading)
                    .padding(.top, 14)
            }
            .frame(width: L.synopsisWidth, alignment: .topLeading)
            .offset(x: L.margin, y: L.infoTop)
            .id("\(item.type):\(item.id)-info")
            .transition(.opacity.animation(.easeInOut(duration: 0.3)))

            if count > 1 {
                HStack(spacing: 10) {
                    ForEach(0..<count, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(i == index ? 1 : 0.35))
                            .frame(width: i == index ? 11 : 8, height: i == index ? 11 : 8)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: index)
                .frame(width: size.width)
                .offset(y: L.heroHeight - 110)
            }
            if let certification = meta?.certification {
                Text(certification == "TP" ? String(localized: "TP") : "\(certification)+")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.22)))
                    .frame(width: size.width - L.margin, alignment: .trailing)
                    .offset(y: L.heroHeight - 120)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// A row: its heading, then its titles from the focused one (at the margin).
private struct OrbitPrimeRowView: View {
    let row: OrbitPrimeRow
    let lead: Int
    let isCurrent: Bool
    let focused: Bool
    let line: String?
    let badges: [String: String]
    @ObservedObject var metaStore: OrbitMetaStore

    var body: some View {
        let L = OrbitPrimeLayout.self
        let low = max(0, lead - 1)
        let window = low...max(low, min(row.items.count - 1, lead + 8))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(row.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.white.opacity(isCurrent ? 1 : 0.85))
                if row.kind == .top10 {
                    Image(systemName: "chart.line.uptrend.xyaxis.circle")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
            }
            .lineLimit(1)
            .frame(height: L.headingHeight, alignment: .topLeading)
            .padding(.leading, L.margin)
            ZStack(alignment: .topLeading) {
                if !row.items.isEmpty {
                    // The focused title last: its grown card above its neighbours.
                    ForEach(Array(zip(window, row.items[window])), id: \.1.id) { index, item in
                        let isLead = isCurrent && index == lead
                        let meta = metaStore.meta(for: item)
                        let badge = badges[item.id].flatMap { $0.isEmpty ? nil : $0 }
                        Group {
                            switch row.kind {
                            case .tiles:
                                OrbitPrimeTile(item: item, meta: meta, badge: badge, grown: isLead, focused: focused && isLead)
                            case .originals:
                                OrbitPrimeOriginal(item: item, meta: meta, badge: badge, open: isLead,
                                                   focused: focused && isLead, line: isLead ? line : nil)
                            case .top10:
                                HStack(alignment: .bottom, spacing: 0) {
                                    OrbitPrimeRank(rank: index + 1)
                                    OrbitPrimeTile(item: item, meta: meta, badge: badge, grown: isLead,
                                                   focused: focused && isLead, size: L.top10Tile)
                                        .padding(.leading, -L.rankTuck)
                                }
                            }
                        }
                        .offset(x: L.margin + row.x(of: index, lead: lead, current: isCurrent))
                        .opacity(index < lead ? 0 : 1)
                        .zIndex(isLead ? 1 : 0)
                    }
                }
            }
            .frame(width: OrbitHomeLayout.screenWidth, height: row.cardHeight, alignment: .topLeading)
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// Prime's Top 10 rank: big, solid grey, its right part behind the tile.
private struct OrbitPrimeRank: View {
    let rank: Int

    var body: some View {
        let L = OrbitPrimeLayout.self
        // Steven's photo: Prime's ranks are a very wide, very heavy face, flat grey, about a third of
        // the tile's height, a little above its middle, their right part under the tile.
        Text("\(rank)")
            .font(.system(size: L.top10Tile.height * 0.5, weight: .black).width(.expanded))
            .kerning(rank == 10 ? -4 : 0)
            .foregroundStyle(Color(white: 0.55))
            .fixedSize()
            .frame(width: L.rankWidth + L.rankTuck, height: L.top10Tile.height, alignment: .trailing)
            .offset(y: -L.top10Tile.height * 0.1)
    }
}

/// A 16:9 tile: TMDB's backdrop, the title's logo, "prime" on Amazon's own, the badge; focused, it
/// grows (from its top-left corner) into a card with its summary under the art.
private struct OrbitPrimeTile: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let badge: String?
    let grown: Bool
    let focused: Bool
    var size: CGSize = OrbitPrimeLayout.tile

    var body: some View {
        let L = OrbitPrimeLayout.self
        let scale = grown ? L.grownScale : 1
        let art = CGSize(width: size.width * scale, height: size.height * scale)
        let info = OrbitInfo.make(item, meta: meta)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color(red: 0.10, green: 0.13, blue: 0.18)
                OrbitImage(url: item.banner ?? meta?.backdrop, fallback: item.poster, size: art)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                OrbitTitleMark(name: item.name, logo: info.logo,
                               maxSize: CGSize(width: art.width * 0.55, height: art.height * 0.42), textSize: 22 * scale,
                               fallbackLogo: info.logoFallback)
                    .padding(.leading, 14 * scale)
                    .padding(.bottom, 14 * scale)
                if orbitPrimeIsOwn(item) {
                    OrbitPrimeMark(size: 17 * scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(12 * scale)
                }
                if let badge {
                    OrbitPrimeBadge(text: badge)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(5)
                }
            }
            .frame(width: art.width, height: art.height)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: L.radius, bottomLeadingRadius: grown ? 0 : L.radius,
                                              bottomTrailingRadius: grown ? 0 : L.radius, topTrailingRadius: L.radius,
                                              style: .continuous))
            if grown {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    OrbitPrimeChips(item: item, meta: meta, badge: badge)
                    Text(info.synopsis)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineSpacing(2)
                        .lineLimit(3)
                }
                .padding(18)
                .frame(width: art.width, height: L.panelHeight, alignment: .topLeading)
                .background(UnevenRoundedRectangle(bottomLeadingRadius: L.radius, bottomTrailingRadius: L.radius,
                                                   style: .continuous).fill(Color.black))
                .transition(.opacity)
            }
        }
        .shadow(color: .black.opacity(grown ? 0.7 : 0.25), radius: grown ? 26 : 6, y: grown ? 14 : 4)
        .animation(.easeOut(duration: 0.22), value: grown)
    }
}

/// A portrait poster of Amazon's own titles; focused, it opens into a large 16:9 card.
private struct OrbitPrimeOriginal: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let badge: String?
    let open: Bool
    let focused: Bool
    let line: String?

    var body: some View {
        let L = OrbitPrimeLayout.self
        let size = CGSize(width: open ? L.openWidth : L.poster.width, height: L.poster.height)
        let info = OrbitInfo.make(item, meta: meta)
        let poster: String? = meta?.localPoster ?? meta?.titledPoster
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.10, green: 0.13, blue: 0.18)
            if open {
                OrbitImage(url: item.banner ?? meta?.backdrop, fallback: poster, size: size)
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: UnitPoint(x: 0.5, y: 0.35), endPoint: .bottom)
                VStack(alignment: .leading, spacing: 14) {
                    OrbitTitleMark(name: item.name, logo: info.logo, maxSize: CGSize(width: 420, height: 130), textSize: 44,
                                   fallbackLogo: info.logoFallback, hugsLogo: true)
                        .frame(width: 420, alignment: .leading)
                    HStack(spacing: 14) {
                        Text(String(localized: "Plus d'informations"))
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(focused ? Color.black : Color.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 6).fill(focused ? Color.white : Color.white.opacity(0.22)))
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(Color.white.opacity(0.22)))
                    }
                    if let line { OrbitPrimeLine(text: line, size: 18) }
                    OrbitPrimeChips(item: item, meta: meta, badge: badge)
                }
                .padding(.leading, 24)
                .padding(.bottom, 24)
                OrbitPrimeMark(size: 26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(26)
            } else {
                OrbitImage(url: poster ?? item.poster, fallback: item.poster, mode: .fill, size: size)
                OrbitPrimeMark(size: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(14)
                if let badge {
                    OrbitPrimeBadge(text: badge)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(5)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: L.radius, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 0.9 : 0), lineWidth: 3)
        }
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}
