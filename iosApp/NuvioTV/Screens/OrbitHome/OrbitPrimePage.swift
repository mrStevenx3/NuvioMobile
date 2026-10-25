import Combine
import SharedCore
import SwiftUI

// Orbit × Prime Video (Steven, 2026-10-25, after Prime Video's 2025 look): the Prime Video folder in
// Prime Video's style, Orbit's DNA kept (one focusable canvas; the collection bar top left with the
// house, Films / Séries as tabs switching on focus; the intro; trailers on a rest).
//
//  - Prime's dark blue-black. The hero: a carousel of the new titles, the art across the page (drifting
//    slowly, its trailer after a rest), the logo, a green line ("N° 2 des séries en France" for a
//    title of the Top 10), two lines of synopsis, the meta chips, the dots.
//  - The rows: 16:9 tiles (his add-on's landscape art, TMDB's backdrop and logo for the genres);
//    the focused one grows in place at the margin; under the current row, the title's name, its
//    chips and two lines of synopsis. Several rows show below.
//  - The Top 10: his images as they are (the card with its big grey-blue rank behind), larger.

enum OrbitPrimeLayout {
    static let background = Color(red: 0.06, green: 0.09, blue: 0.12)
    static let green = Color(red: 0.16, green: 0.80, blue: 0.45)
    static let margin: CGFloat = OrbitHomeLayout.margin
    static let heroHeight: CGFloat = 860
    static let infoTop: CGFloat = 230
    static let logoSize = CGSize(width: 620, height: 190)
    static let synopsisWidth: CGFloat = 860
    static let rowsTop: CGFloat = 820
    static let restTop: CGFloat = 150
    static let headingHeight: CGFloat = 52
    static let tile = CGSize(width: 384, height: 216)
    static let top10 = CGSize(width: 512, height: 288)
    static let gap: CGFloat = 22
    static let infoHeight: CGFloat = 170
    static let rowGap: CGFloat = 46
    static let radius: CGFloat = 10
    static let focusScale: CGFloat = 1.1
    static let horizontal = Animation.easeOut(duration: 0.24)
    static let vertical = Animation.easeInOut(duration: 0.38)
}

struct OrbitPrimeRow: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [MetaPreview]
    let top10: Bool
    let fresh: Bool

    static func == (a: OrbitPrimeRow, b: OrbitPrimeRow) -> Bool {
        a.id == b.id && a.top10 == b.top10 && a.items.map(\.id) == b.items.map(\.id)
    }

    var cardSize: CGSize { top10 ? OrbitPrimeLayout.top10 : OrbitPrimeLayout.tile }

    func height(current: Bool) -> CGFloat {
        let L = OrbitPrimeLayout.self
        return L.headingHeight + cardSize.height * (current ? L.focusScale : 1) + (current ? L.infoHeight : 0) + L.rowGap
    }
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
    /// 0: the hero; then the rows.
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

    /// His Nouveautés, his Top 10, then the genres (TMDB).
    private var rows: [OrbitPrimeRow] {
        let extraRows = series ? extras.seriesRows : extras.movieRows
        let catalogs: [OrbitPrimeRow] = CollectionTypeFilter.rows(model.stripRows, filter: typeFilter).compactMap { row in
            guard row.status == .loaded, let items = row.section?.items, !items.isEmpty else { return nil }
            guard extraRows.isEmpty || OrbitCatalogFilter.isKept(row.heading) else { return nil }
            var seen = Set<String>()
            let unique = items.filter { seen.insert("\($0.type):\($0.id)").inserted }
            let heading = row.heading.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let top10 = heading.contains("top 10") || heading.contains("top10")
            return OrbitPrimeRow(id: row.id,
                                 title: top10 ? (series ? String(localized: "Top 10 des séries en France")
                                                        : String(localized: "Top 10 des films en France"))
                                              : row.heading,
                                 items: top10 ? Array(unique.prefix(10)) : unique, top10: top10,
                                 fresh: heading.contains("nouveau") || heading.contains("nouvelle"))
        }
        let ordered = catalogs.filter(\.fresh) + catalogs.filter { !$0.fresh }
        var shown = Set(ordered.flatMap { $0.items.map(Self.identity) })
        var more: [OrbitPrimeRow] = []
        for extra in extraRows {
            let fresh = extra.items.filter { !shown.contains(Self.identity($0)) && $0.banner != nil }
            guard fresh.count >= 8 else { continue }
            let kept = Array(fresh.prefix(24))
            kept.forEach { shown.insert(Self.identity($0)) }
            more.append(OrbitPrimeRow(id: extra.id, title: extra.title, items: kept, top10: false, fresh: false))
        }
        return ordered + more
    }

    private static func identity(_ item: MetaPreview) -> String {
        let year: String = item.releaseInfo.map { String($0.prefix(4)) } ?? ""
        return item.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) + "|" + year
    }

    private var heroItems: [MetaPreview] {
        let rows = rows
        let source = rows.first(where: \.fresh) ?? rows.first
        return Array((source?.items ?? []).prefix(6))
    }

    private var heroItem: MetaPreview? {
        let items = heroItems
        return items.isEmpty ? nil : items[min(heroIndex, items.count - 1)]
    }

    /// The title's place in the Top 10, if it is in it.
    private func topRank(_ item: MetaPreview) -> Int? {
        guard let top = rows.first(where: \.top10) else { return nil }
        return top.items.firstIndex { Self.identity($0) == Self.identity(item) }.map { $0 + 1 }
    }

    private var sectionCount: Int { 1 + rows.count }

    private func rowTops(_ rows: [OrbitPrimeRow]) -> [CGFloat] {
        var y = OrbitPrimeLayout.rowsTop
        let currentRow = current - 1
        return rows.enumerated().map { i, row in defer { y += row.height(current: i == currentRow) }; return y }
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
                    OrbitPrimeHero(item: hero, meta: metaStore.meta(for: hero), rank: topRank(hero), series: series,
                                   count: heroItems.count, index: min(heroIndex, max(0, heroItems.count - 1)),
                                   trailerURL: current == 0 ? trailerURL(for: hero) : nil,
                                   onTrailerFailure: { trailer.playbackFailed($0) },
                                   onTrailerEnded: {
                                       trailer.playbackFinished()
                                       advanceHero()
                                   })
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
                               brand: Color(red: 0.0, green: 0.48, blue: 0.78))

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
        let high = min(rows.count - 1, max(currentRow, 0) + 3)
        ZStack(alignment: .topLeading) {
            if low <= high {
                ForEach(low...high, id: \.self) { i in
                    let row = rows[i]
                    let lead = lead(of: row)
                    let item: MetaPreview? = row.items.indices.contains(lead) ? row.items[lead] : nil
                    OrbitPrimeRowView(row: row, lead: lead, isCurrent: i == currentRow,
                                      focused: canvasFocused && i == currentRow, series: series,
                                      rank: item.flatMap { topRank($0) }, metaStore: metaStore)
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
                      motion.secondsSinceMotion > 12 else { continue }
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
        for i in r...max(r, min(rows.count - 1, r + 2)) where rows.indices.contains(i) {
            let row = rows[i]
            let lead = lead(of: row)
            metaItems += row.items.indices.filter { $0 >= lead - 1 && $0 <= lead + 6 }.map { row.items[$0] }
        }
        OrbitMetaStore.shared.request(metaItems)

        trailer.reset()
        trailerKey = nil
        guard trailersOn, canvasFocused, current == 0, search == nil, UIAccessibility.isVideoAutoplayEnabled,
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

/// "[16+]  NOUVEAUTÉ  2025 · Drame · 2 h 10".
private struct OrbitPrimeChips: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    var fresh = false

    var body: some View {
        let info = OrbitInfo.make(item, meta: meta)
        HStack(spacing: 12) {
            if fresh { chip(String(localized: "NOUVEAUTÉ")) }
            if let certification = meta?.certification {
                chip(certification == "TP" ? String(localized: "TOUS PUBLICS") : "\(certification)+")
            }
            Text(info.parts.joined(separator: "  ·  "))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.18)))
    }
}

/// Prime's green line: "N° 2 des séries en France", or "Nouveauté".
private struct OrbitPrimeLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                .font(.system(size: 24, weight: .semibold))
            Text(text)
                .font(.system(size: 22, weight: .bold))
        }
        .foregroundStyle(OrbitPrimeLayout.green)
    }
}

/// The hero: the art across the page (drifting, its trailer after a rest), the text on the left.
private struct OrbitPrimeHero: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let rank: Int?
    let series: Bool
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
                OrbitDriftImage(url: banner ?? meta?.backdrop, fallback: nil, size: size)
                    .id("\(item.type):\(item.id)")
                if let trailerURL {
                    TrailerHeroPlayer(urlString: trailerURL, onFailure: onTrailerFailure,
                                      zoomKey: TrailerResolutionCache.key(type: item.type, id: item.id),
                                      loops: false, onPlaybackEnded: onTrailerEnded, cornerRadius: 0)
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity.animation(.easeOut(duration: 0.6)))
                }
                LinearGradient(stops: [
                    .init(color: L.background.opacity(0.95), location: 0),
                    .init(color: L.background.opacity(0.55), location: 0.4),
                    .init(color: .clear, location: 0.68),
                ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.5),
                    .init(color: L.background.opacity(0.8), location: 0.8),
                    .init(color: L.background, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            VStack(alignment: .leading, spacing: 0) {
                OrbitTitleMark(name: item.name, logo: info.logo, maxSize: L.logoSize, textSize: 64,
                               fallbackLogo: info.logoFallback)
                    .frame(width: L.logoSize.width, height: L.logoSize.height, alignment: .bottomLeading)
                Group {
                    if let rank {
                        OrbitPrimeLine(text: series ? String(localized: "N° \(String(rank)) des séries en France")
                                                    : String(localized: "N° \(String(rank)) des films en France"))
                    } else {
                        OrbitPrimeLine(text: String(localized: "Nouveauté"))
                    }
                }
                .padding(.top, 24)
                Text(info.synopsis)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineSpacing(4)
                    .lineLimit(2)
                    .frame(width: L.synopsisWidth, alignment: .topLeading)
                    .padding(.top, 14)
                OrbitPrimeChips(item: item, meta: meta)
                    .padding(.top, 18)
                if count > 1 {
                    HStack(spacing: 10) {
                        ForEach(0..<count, id: \.self) { i in
                            Capsule()
                                .fill(Color.white.opacity(i == index ? 1 : 0.35))
                                .frame(width: i == index ? 26 : 10, height: 10)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: index)
                    .padding(.top, 28)
                }
            }
            .frame(width: L.synopsisWidth, alignment: .topLeading)
            .offset(x: L.margin, y: L.infoTop)
            .id("\(item.type):\(item.id)-info")
            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// A row: its heading, its tiles from the focused one (grown in place at the margin); under the
/// current row, the focused title's name, line, chips and synopsis.
private struct OrbitPrimeRowView: View {
    let row: OrbitPrimeRow
    let lead: Int
    let isCurrent: Bool
    let focused: Bool
    let series: Bool
    let rank: Int?
    @ObservedObject var metaStore: OrbitMetaStore

    var body: some View {
        let L = OrbitPrimeLayout.self
        let size = row.cardSize
        let grown = size.width * L.focusScale
        let low = max(0, lead - 1)
        let window = low...max(low, min(row.items.count - 1, lead + 7))
        VStack(alignment: .leading, spacing: 0) {
            Text(row.title)
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(Color.white.opacity(isCurrent ? 1 : 0.7))
                .lineLimit(1)
                .frame(height: L.headingHeight, alignment: .topLeading)
                .padding(.leading, L.margin)
            ZStack(alignment: .topLeading) {
                if !row.items.isEmpty {
                    ForEach(Array(zip(window, row.items[window])), id: \.1.id) { index, item in
                        let isLead = isCurrent && index == lead
                        // The grown tile pushes the next ones by its extra width.
                        let x: CGFloat = index <= lead
                            ? CGFloat(index - lead) * (size.width + L.gap)
                            : (isCurrent ? grown : size.width) + L.gap + CGFloat(index - lead - 1) * (size.width + L.gap)
                        OrbitPrimeTile(item: item, meta: metaStore.meta(for: item), size: size, top10: row.top10,
                                       grown: isLead, focused: focused && index == lead)
                            .offset(x: L.margin + x)
                            .opacity(index < lead ? 0 : 1)
                    }
                }
            }
            .frame(width: OrbitHomeLayout.screenWidth, height: size.height * (isCurrent ? L.focusScale : 1), alignment: .topLeading)
            if isCurrent, row.items.indices.contains(lead) {
                let item = row.items[lead]
                let meta = metaStore.meta(for: item)
                let info = OrbitInfo.make(item, meta: meta)
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.name)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    if let rank {
                        OrbitPrimeLine(text: series ? String(localized: "N° \(String(rank)) des séries en France")
                                                    : String(localized: "N° \(String(rank)) des films en France"))
                    }
                    OrbitPrimeChips(item: item, meta: meta, fresh: row.fresh)
                    Text(info.synopsis)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineSpacing(3)
                        .lineLimit(2)
                        .frame(width: 1000, alignment: .topLeading)
                }
                .padding(.leading, L.margin)
                .padding(.top, 16)
                .id("\(item.type):\(item.id)")
                .transition(.asymmetric(insertion: .opacity.animation(.easeInOut(duration: 0.2)), removal: .identity))
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// A 16:9 tile: his landscape art (or TMDB's backdrop with the logo); his Top 10 images as they
/// are (transparent, their rank behind the card). The focused one grows in place.
private struct OrbitPrimeTile: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let size: CGSize
    let top10: Bool
    let grown: Bool
    let focused: Bool

    var body: some View {
        let L = OrbitPrimeLayout.self
        let info = OrbitInfo.make(item, meta: meta)
        let landscape: String? = item.posterShape == .landscape ? (item.landscapePoster ?? item.poster) : nil
        Group {
            if top10 {
                OrbitImage(url: item.poster, fallback: item.rawPosterUrl, mode: .fit, size: size)
                    .frame(width: size.width, height: size.height)
                    .shadow(color: .white.opacity(focused ? 0.45 : 0), radius: focused ? 22 : 0)
                    .brightness(focused ? 0.05 : 0)
            } else {
                ZStack(alignment: .bottomLeading) {
                    Color(red: 0.10, green: 0.13, blue: 0.17)
                    if let landscape {
                        OrbitImage(url: landscape, fallback: item.rawPosterUrl, size: size)
                    } else {
                        OrbitImage(url: item.banner ?? meta?.backdrop, fallback: item.poster, size: size)
                        LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                        OrbitTitleMark(name: item.name, logo: info.logo,
                                       maxSize: CGSize(width: size.width * 0.6, height: size.height * 0.34), textSize: 24,
                                       fallbackLogo: info.logoFallback)
                            .padding(.leading, 14)
                            .padding(.bottom, 12)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: L.radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(focused ? 0.95 : 0), lineWidth: 3)
                }
                .shadow(color: .black.opacity(focused ? 0.5 : 0.2), radius: focused ? 18 : 6, y: focused ? 10 : 4)
            }
        }
        // Prime: the focused tile grows in place, from its top-left corner (the margin stays).
        .scaleEffect(grown ? L.focusScale : 1, anchor: .topLeading)
        .animation(.easeOut(duration: 0.2), value: grown)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}
