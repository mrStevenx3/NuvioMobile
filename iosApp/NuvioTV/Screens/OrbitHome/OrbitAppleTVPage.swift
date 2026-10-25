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
    static let poster = CGSize(width: 232, height: 348)
    static let card = CGSize(width: 520, height: 620)
    static let gap: CGFloat = 28
    static let cardGap: CGFloat = 34
    static let rowGap: CGFloat = 46
    static let radius: CGFloat = 20
    static let focusScale: CGFloat = 1.1
    static let horizontal = Animation.easeOut(duration: 0.24)
    static let vertical = Animation.easeInOut(duration: 0.4)
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
    var height: CGFloat { OrbitAppleTVLayout.headingHeight + cardHeight + OrbitAppleTVLayout.rowGap }
    var slot: CGFloat {
        kind == .cards ? OrbitAppleTVLayout.card.width + OrbitAppleTVLayout.cardGap
                       : OrbitAppleTVLayout.poster.width + OrbitAppleTVLayout.gap
    }
}

struct OrbitAppleTVPage: View {
    let route: FolderRoute
    let push: (TitleRoute) -> Void

    static func handles(_ route: FolderRoute) -> Bool {
        let t = route.folderTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        return t.contains("appletv")
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

    private static func alternate<T>(_ a: [T], _ b: [T]) -> [T] {
        var out: [T] = []
        for i in 0..<max(a.count, b.count) {
            if i < a.count { out.append(a[i]) }
            if i < b.count { out.append(b[i]) }
        }
        return out
    }

    /// As in the app: the Top 10 first, then the new titles, one row of large cards, the genres (TMDB).
    private var rows: [OrbitAppleTVRow] {
        let extraRows: [OrbitPlatformExtrasModel.Extra] = switch typeFilter {
        case "movie"?: extras.movieRows
        case "series"?: extras.seriesRows
        default: Self.alternate(extras.seriesRows, extras.movieRows)
        }
        let all = catalogs
        var out: [OrbitAppleTVRow] = []
        // Series' Top 10 before the films' (the app's order).
        let tops = all.filter(\.top10).sorted { a, _ in Self.isSeries(a) }
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

    private var freshIdentities: Set<String> {
        Set(catalogs.filter(\.fresh).flatMap { $0.items.map(Self.identity) })
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
    private func rankLine(_ item: MetaPreview) -> String? {
        for top in catalogs where top.top10 {
            if let i = top.items.prefix(10).firstIndex(where: { Self.identity($0) == Self.identity(item) }) {
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
        let offset = scroll(rows)
        let onArrival = current == 0
        let ambient = focusedItem ?? heroItem

        ZStack(alignment: .topLeading) {
            OrbitAppleTVAmbient(item: ambient, meta: ambient.flatMap { metaStore.meta(for: $0) })

            if let hero = heroItem {
                OrbitAppleTVHero(item: hero, meta: metaStore.meta(for: hero), isNew: isNew(hero), line: rankLine(hero),
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

            if rows.isEmpty, model.isLoading {
                ProgressView().frame(width: W, height: H)
            }

            Button(action: select) {
                Color.clear
                    .frame(width: W, height: H - 110)
                    .contentShape(Rectangle())
            }
            .buttonStyle(OrbitAppleTVCanvasStyle())
            .focused($canvasFocused)
            .onMoveCommand(perform: move)
            .onExitCommand(perform: exitAction())
            .offset(y: 110)
            .disabled(search != nil)

            CollectionFilterBar(filter: $typeFilter, onSearch: openSearch, showsAll: true)
                .disabled(search != nil || (canvasFocused && current > 0))
                .opacity(search != nil ? 0 : 1)

            OrbitPlatformIntro(title: model.folderTitle, logoUrl: model.titleLogoUrl ?? route.titleLogoUrl,
                               brand: Color(white: 0.6), white: true, assetLogo: "AppleTVMark")

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
        .animation(reduceMotion ? nil : OrbitAppleTVLayout.vertical, value: offset)
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
    private func rowsLayer(_ rows: [OrbitAppleTVRow]) -> some View {
        let tops = rowTops(rows)
        let currentRow = rowIndex(of: current) ?? -1
        let low = max(0, currentRow - 1)
        let high = min(rows.count - 1, max(currentRow, 0) + 3)
        ZStack(alignment: .topLeading) {
            if low <= high {
                ForEach(low...high, id: \.self) { i in
                    let row = rows[i]
                    OrbitAppleTVRowView(row: row, lead: lead(of: row), isCurrent: i == currentRow,
                                        focused: canvasFocused && i == currentRow,
                                        newIDs: Set(row.items.filter(isNew).map(\.id)),
                                        rankLine: { rankLine($0) },
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
                withAnimation(reduceMotion ? nil : OrbitAppleTVLayout.horizontal) { leads[row.id] = next }
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
        guard trailersOn, search == nil, current == 0, UIAccessibility.isVideoAutoplayEnabled,
              let item = heroItem else { return }
        trailer.prefersReducedMotion = reduceMotion
        trailer.restSource = .custom(motion)
        trailerKey = "\(item.type):\(item.id)"
        trailer.focusChanged(true, item: item)
    }
}

private struct OrbitAppleTVCanvasStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

// MARK: - Pieces

/// tvOS 26's background: the shown title's art, blurred and dimmed, all over the page.
private struct OrbitAppleTVAmbient: View {
    let item: MetaPreview?
    let meta: OrbitMeta?

    var body: some View {
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        ZStack {
            Color(white: 0.06)
            if let item {
                OrbitImage(url: item.banner ?? meta?.backdrop, fallback: item.poster,
                           size: CGSize(width: W / 4, height: H / 4))
                    .frame(width: W / 4, height: H / 4)
                    .scaleEffect(4.4)
                    .blur(radius: 18)
                    .saturation(1.25)
                    .opacity(0.8)
                    .id("\(item.type):\(item.id)")
                    .transition(.opacity.animation(.easeInOut(duration: 0.6)))
            }
            LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        }
        .frame(width: W, height: H)
        .clipped()
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
                if isNew {
                    OrbitAppleTVCapsule(text: item.type == "movie" ? String(localized: "Nouveau film")
                                                                   : String(localized: "Nouvelle série"))
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
    let lead: Int
    let isCurrent: Bool
    let focused: Bool
    let newIDs: Set<String>
    let rankLine: (MetaPreview) -> String?
    @ObservedObject var metaStore: OrbitMetaStore

    var body: some View {
        let L = OrbitAppleTVLayout.self
        let low = max(0, lead - 1)
        let window = low...max(low, min(row.items.count - 1, lead + (row.kind == .cards ? 4 : 8)))
        VStack(alignment: .leading, spacing: 0) {
            Text(row.title)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isCurrent ? 1 : 0.8))
                .lineLimit(1)
                .frame(height: L.headingHeight, alignment: .topLeading)
                .padding(.leading, L.margin)
            ZStack(alignment: .topLeading) {
                if !row.items.isEmpty {
                    ForEach(Array(zip(window, row.items[window])), id: \.1.id) { index, item in
                        let lit = focused && index == lead
                        Group {
                            switch row.kind {
                            case .cards:
                                OrbitAppleTVCard(item: item, meta: metaStore.meta(for: item), isNew: newIDs.contains(item.id),
                                                 line: rankLine(item), focused: lit)
                            case .top10:
                                OrbitAppleTVPoster(url: item.poster, fallback: item.rawPosterUrl, focused: lit, mark: false)
                            case .posters:
                                let meta = metaStore.meta(for: item)
                                OrbitAppleTVPoster(url: meta?.localPoster ?? item.poster, fallback: item.rawPosterUrl, focused: lit)
                            }
                        }
                        .offset(x: L.margin + CGFloat(index - lead) * row.slot)
                        .opacity(index < lead ? 0 : 1)
                        .zIndex(lit ? 1 : 0)
                    }
                }
            }
            .frame(width: OrbitHomeLayout.screenWidth, height: row.cardHeight, alignment: .topLeading)
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// A tall rounded poster ( tv in its corner, as in the app); focused, lifted larger with a light
/// rim (tvOS's focus, no frame).
private struct OrbitAppleTVPoster: View {
    let url: String?
    let fallback: String?
    let focused: Bool
    var mark = true

    var body: some View {
        let L = OrbitAppleTVLayout.self
        ZStack(alignment: .topTrailing) {
            Color.white.opacity(0.08)
            OrbitImage(url: url, fallback: fallback, mode: .fill, size: L.poster)
            if mark {
                Image("AppleTVMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.white)
                    .frame(width: 34)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                    .padding(12)
            }
        }
        .frame(width: L.poster.width, height: L.poster.height)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .modifier(OrbitAppleTVFocus(focused: focused))
    }
}

/// A large card: the art without its title (TMDB's textless poster, else the backdrop), the
/// capsule, the logo, the line and its rank over it.
private struct OrbitAppleTVCard: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let isNew: Bool
    let line: String?
    let focused: Bool

    var body: some View {
        let L = OrbitAppleTVLayout.self
        let size = L.card
        let info = OrbitInfo.make(item, meta: meta)
        ZStack(alignment: .bottomLeading) {
            Color.white.opacity(0.08)
            OrbitImage(url: meta?.cleanPoster ?? item.banner ?? meta?.backdrop, fallback: item.poster, mode: .fill, size: size)
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
            .animation(.easeOut(duration: 0.2), value: focused)
    }
}
