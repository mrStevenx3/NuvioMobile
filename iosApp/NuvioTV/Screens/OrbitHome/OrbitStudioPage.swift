import Combine
import SharedCore
import SwiftUI

// Orbit Studio (Steven, 2026-10-24): a studio's page, rebuilt from scratch — a showcase of its
// films rather than an app to open (the platforms are that):
//
//  - A header: the studio's logo on its colour, "Studio · 28 films · depuis 1986".
//  - Rows made for a filmography, in large landscape cards (each film's art and logo): the
//    folder's own catalogs when it comes from the Studios tab, then "Les incontournables" (best
//    rated), "Les plus populaires", "Les sagas" (one card per saga, it opens its first film),
//    "Prochainement", and a row per decade.
//  - Under the current row, the focused film's meta line and synopsis; its trailer plays in its
//    card after a rest.
//  - Orbit's canvas: one focusable stop, the page moves (Down / Up row to row, Left / Right along
//    one), the header leaves with the first row.
//
// One page for both ways in: a studio of the Studios tab (its folder) and a studio or a channel
// from a film's "À propos" (TMDB's company / network id). The data is TMDB's (discover by company
// or network), plus the folder's catalogs.

/// What the page shows: a folder of the Studios tab, or TMDB's company / network.
struct OrbitStudioRoute: Hashable {
    let name: String
    /// TMDB ids ("3", "128064|9993"), nil to look them up by name.
    let companies: String?
    let isNetwork: Bool
    let logo: String?
    let collectionId: String?
    let folderId: String?

    static func folder(collectionId: String, folder: CollectionFolder) -> OrbitStudioRoute {
        let logo: String? = folder.titleLogoUrl
        return OrbitStudioRoute(name: folder.title,
                                companies: OrbitStudioFilmsModel.companies(forTitle: folder.title),
                                isNetwork: false,
                                logo: (logo ?? "").trimmingCharacters(in: .whitespaces).isEmpty ? nil : logo,
                                collectionId: collectionId, folderId: folder.id)
    }

    static func entity(_ route: EntityRoute) -> OrbitStudioRoute {
        OrbitStudioRoute(name: route.name, companies: String(route.id), isNetwork: route.isNetwork,
                         logo: nil, collectionId: nil, folderId: nil)
    }
}

/// One row of the studio page.
struct OrbitStudioRow: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [MetaPreview]
    /// "Les sagas": each card is a saga (its name, not its first film's logo).
    var sagas: Bool { id == "sagas" }

    static func == (a: OrbitStudioRow, b: OrbitStudioRow) -> Bool {
        a.id == b.id && a.title == b.title && a.items.map(\.id) == b.items.map(\.id)
    }
}

enum OrbitStudioLayout {
    static let margin: CGFloat = OrbitHomeLayout.margin
    static let cardSize = CGSize(width: 448, height: 252)
    static let gap: CGFloat = 26
    static let radius: CGFloat = 14
    /// The header block's top, and the first row's heading line while the header shows.
    static let headerTop: CGFloat = 90
    static let firstRowLine: CGFloat = 400
    /// The current row's heading line once the header has left.
    static let rowLine: CGFloat = 150
    static let cardsTop: CGFloat = 44
    /// From a heading to the next one: cards, the info (meta line + 2 lines), the gap.
    /// Steven: the next heading sat right under the synopsis; room for the info and air after.
    static let pitch: CGFloat = cardsTop + cardSize.height + 250
    static let horizontal = Animation.easeOut(duration: 0.24)
    static let vertical = Animation.easeInOut(duration: 0.36)
}

struct OrbitStudioPage: View {
    let route: OrbitStudioRoute

    @StateObject private var model: OrbitStudioModel
    @StateObject private var trailer = InlineTrailerCardModel()
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true

    @State private var current = 0
    @State private var leads: [String: Int] = [:]
    @FocusState private var canvasFocused: Bool
    @State private var motion = OrbitHomeMotion()
    @State private var trailerKey: String?
    @State private var opening: TitleRoute?
    @State private var tint: Color?

    init(route: OrbitStudioRoute) {
        self.route = route
        _model = StateObject(wrappedValue: OrbitStudioModel(route: route))
    }

    // MARK: Data

    private var rows: [OrbitStudioRow] { model.rows }

    private func lead(of row: OrbitStudioRow) -> Int {
        min(leads[row.id] ?? 0, max(0, row.items.count - 1))
    }

    private func focusedItem(_ rows: [OrbitStudioRow]) -> MetaPreview? {
        guard rows.indices.contains(current) else { return nil }
        let row = rows[current]
        return row.items.indices.contains(lead(of: row)) ? row.items[lead(of: row)] : nil
    }

    private var brand: Color {
        tint ?? OrbitPlatformBrand.color(title: model.name)
    }

    // MARK: Body

    var body: some View {
        let rows = rows
        let index = min(current, max(0, rows.count - 1))
        let L = OrbitStudioLayout.self
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        // The header shows over the first row only; below, the current row sits higher.
        let line = index == 0 ? L.firstRowLine : L.rowLine

        ZStack(alignment: .topLeading) {
            OrbitStudioBackground(brand: brand)

            OrbitStudioHeader(name: model.name, logo: model.logo ?? route.logo, line: model.statsLine)
                .offset(x: L.margin, y: L.headerTop)
                .opacity(index == 0 ? 1 : 0)
                .offset(y: index == 0 ? 0 : -80)

            ZStack(alignment: .topLeading) {
                if !rows.isEmpty {
                    let window = index...max(index, min(rows.count - 1, index + 2))
                    ForEach(Array(zip(window, rows[window])), id: \.1.id) { i, row in
                        OrbitStudioRowView(row: row, lead: lead(of: row), isCurrent: i == index,
                                           focused: i == index && canvasFocused,
                                           trailerURL: i == index ? trailerURL(for: row) : nil,
                                           onTrailerFailure: { trailer.playbackFailed($0) },
                                           onTrailerEnded: { trailer.playbackFinished() })
                            .offset(y: line + CGFloat(i - index) * L.pitch)
                            .transition(.identity)
                    }
                }
            }

            if rows.isEmpty {
                Group {
                    if model.loading {
                        ProgressView()
                    } else {
                        Text(String(localized: "Aucun film trouvé pour \(model.name)."))
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
                .frame(width: W, height: H)
            }

            // The page's one focusable stop.
            Button(action: select) {
                Color.clear
                    .frame(width: W, height: H)
                    .contentShape(Rectangle())
            }
            .buttonStyle(OrbitStudioCanvasStyle())
            .focused($canvasFocused)
            .onMoveCommand(perform: move)
            .onExitCommand(perform: exitAction(index: index))
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .background(OrbitHomeLayout.background)
        .ignoresSafeArea()
        .defaultFocus($canvasFocused, true)
        .navigationDestination(item: $opening) { route in
            DetailView(preview: route.preview)
        }
        .onAppear {
            tabBarVisibility.pushImmersive()
            model.start()
            trailer.restSource = .custom(motion)
            DispatchQueue.main.async { canvasFocused = true }
            refreshAfterMove()
        }
        .onDisappear {
            tabBarVisibility.popImmersive()
            trailer.reset(abortStages: true)
        }
        .onChange(of: canvasFocused) { _, _ in refreshAfterMove() }
        .onChange(of: rows.map(\.id)) { _, ids in
            if current >= ids.count { current = max(0, ids.count - 1) }
            refreshAfterMove()
        }
        .onChange(of: model.logo ?? route.logo ?? "-", initial: true) { _, raw in sampleTint(raw) }
    }

    private func trailerURL(for row: OrbitStudioRow) -> String? {
        guard row.items.indices.contains(lead(of: row)) else { return nil }
        let item = row.items[lead(of: row)]
        guard trailerKey == "\(item.type):\(item.id)" else { return nil }
        return trailer.playingURL
    }

    /// The studio's colour from its logo when no brand colour is known.
    private func sampleTint(_ raw: String) {
        guard raw != "-", OrbitPlatformBrand.isNeutral(title: model.name) else { return }
        if let cached = ArtworkColorStore.shared.cachedColor(for: [raw], use: .wash) {
            tint = cached
            return
        }
        ArtworkColorStore.shared.color(for: [raw], use: .wash) { color in
            if let color { withAnimation(.easeInOut(duration: 0.5)) { tint = color } }
        }
    }

    // MARK: Input

    private func move(_ direction: MoveCommandDirection) {
        let rows = rows
        guard !rows.isEmpty else { return }
        let index = min(current, rows.count - 1)
        switch direction {
        case .down:
            guard index + 1 < rows.count else { return }
            withAnimation(reduceMotion ? nil : OrbitStudioLayout.vertical) { current = index + 1 }
        case .up:
            guard index > 0 else { return }
            withAnimation(reduceMotion ? nil : OrbitStudioLayout.vertical) { current = index - 1 }
        case .left, .right:
            let row = rows[index]
            let next = lead(of: row) + (direction == .right ? 1 : -1)
            guard row.items.indices.contains(next) else { return }
            withAnimation(OrbitStudioLayout.horizontal) { leads[row.id] = next }
        @unknown default:
            return
        }
        refreshAfterMove()
    }

    private func select() {
        guard let item = focusedItem(rows) else { return }
        opening = TitleRoute(preview: item)
    }

    /// Menu: back to the first row from below it; at the top, the page closes.
    private func exitAction(index: Int) -> (() -> Void)? {
        guard index > 0 else { return nil }
        return {
            withAnimation(reduceMotion ? nil : OrbitStudioLayout.vertical) { current = 0 }
            refreshAfterMove()
        }
    }

    /// After any move: the look-ahead (meta, art) and the focused film's trailer.
    private func refreshAfterMove() {
        let rows = rows
        let index = min(current, max(0, rows.count - 1))
        motion.stamp()
        var metaItems: [MetaPreview] = []
        let request = ArtworkDecodeRequest(size: .points(width: OrbitStudioLayout.cardSize.width,
                                                         height: OrbitStudioLayout.cardSize.height),
                                           fill: true, scale: UIScreen.main.scale)
        for i in index...max(index, min(rows.count - 1, index + 1)) where rows.indices.contains(i) {
            let row = rows[i]
            let lead = lead(of: row)
            let around = row.items.indices.filter { $0 >= lead - 1 && $0 <= lead + 4 }
            metaItems.append(contentsOf: around.map { row.items[$0] })
            ArtworkStore.prefetch(around.compactMap { j in
                let banner: String? = row.items[j].banner
                return banner.flatMap(URL.init(string:)).map { ArtworkPrefetchItem(url: $0, decode: request) }
            })
        }
        OrbitMetaStore.shared.request(metaItems)

        trailer.reset()
        trailerKey = nil
        guard trailersOn, canvasFocused, UIAccessibility.isVideoAutoplayEnabled,
              let item = focusedItem(rows) else { return }
        trailer.prefersReducedMotion = reduceMotion
        trailer.restSource = .custom(motion)
        trailerKey = "\(item.type):\(item.id)"
        trailer.focusChanged(true, item: item)
    }
}

private struct OrbitStudioCanvasStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - Background, header

/// A calm page: Orbit's black with the studio's colour rising from the top-left, where its logo is.
private struct OrbitStudioBackground: View {
    let brand: Color

    var body: some View {
        ZStack {
            OrbitHomeLayout.background
            RadialGradient(colors: [brand.opacity(0.42), brand.opacity(0.12), .clear],
                           center: UnitPoint(x: 0.12, y: 0.0), startRadius: 0, endRadius: 1400)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.5), value: brand)
    }
}

private struct OrbitStudioHeader: View {
    let name: String
    let logo: String?
    let line: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Group {
                if let logo, !logo.isEmpty {
                    CachedAsyncImage(string: logo, contentMode: .fit,
                                     decodeSize: .points(width: 520, height: 150),
                                     loading: { Color.clear }, failure: { nameText })
                } else {
                    nameText
                }
            }
            .frame(width: 520, height: 150, alignment: .bottomLeading)
            .shadow(color: .black.opacity(0.4), radius: 10, y: 3)
            if let line, !line.isEmpty {
                Text(line)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
        .allowsHitTesting(false)
    }

    private var nameText: some View {
        Text(name)
            .font(.system(size: 72, weight: .heavy))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

// MARK: - Rows and cards

private struct OrbitStudioRowView: View {
    let row: OrbitStudioRow
    let lead: Int
    let isCurrent: Bool
    let focused: Bool
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        let L = OrbitStudioLayout.self
        let size = L.cardSize
        let window = max(0, lead - 1)...max(max(0, lead - 1), min(row.items.count - 1, lead + 5))
        ZStack(alignment: .topLeading) {
            Text(row.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.white.opacity(isCurrent ? 1 : 0.55))
                .lineLimit(1)
                .frame(height: 40)
                .offset(x: L.margin + 4, y: -20)

            ZStack(alignment: .topLeading) {
                if !row.items.isEmpty {
                    ForEach(Array(zip(window, row.items[window])), id: \.1.id) { index, item in
                        OrbitStudioCard(item: item, meta: metaStore.meta(for: item), saga: row.sagas,
                                        focused: focused && index == lead,
                                        trailerURL: index == lead ? trailerURL : nil,
                                        onTrailerFailure: onTrailerFailure, onTrailerEnded: onTrailerEnded)
                            .offset(x: L.margin + CGFloat(index - lead) * (size.width + L.gap))
                            .opacity(index < lead ? 0 : 1)
                            .transition(.identity)
                    }
                }
            }
            .offset(y: L.cardsTop)

            // The focused film's meta line and two lines of synopsis, under the row.
            if isCurrent, row.items.indices.contains(lead) {
                let item = row.items[lead]
                let info = OrbitInfo.make(item, meta: metaStore.meta(for: item))
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    OrbitMetaLine(info: info, size: 25)
                        .frame(height: 32)
                    Text(info.synopsis)
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineSpacing(3)
                        .lineLimit(2)
                        .frame(width: 1100, alignment: .leading)
                }
                .id("\(item.type):\(item.id)")
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                .offset(x: L.margin + 4, y: L.cardsTop + size.height + 26)
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// A film in large landscape: its art, its logo bottom-left; white frame and a lift when focused;
/// its trailer in place after a rest.
private struct OrbitStudioCard: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    var saga = false
    let focused: Bool
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let L = OrbitStudioLayout.self
        let size = L.cardSize
        let banner: String? = item.banner
        let info = OrbitInfo.make(item, meta: meta)
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.1)
            OrbitImage(url: banner ?? meta?.backdrop, fallback: item.poster, size: size)
            if let trailerURL {
                TrailerHeroPlayer(urlString: trailerURL,
                                  onFailure: onTrailerFailure,
                                  zoomKey: TrailerResolutionCache.key(type: item.type, id: item.id),
                                  loops: false,
                                  onPlaybackEnded: onTrailerEnded,
                                  cornerRadius: L.radius)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity.animation(.easeOut(duration: 0.5)))
            }
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            OrbitTitleMark(name: item.name, logo: saga ? nil : info.logo,
                           maxSize: CGSize(width: 260, height: 80), textSize: 30)
                .padding(.leading, 20)
                .padding(.bottom, 16)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        // The focus look animates on its own, never the card's place (the row moves it).
        .animation(.easeOut(duration: 0.18)) { view in
            view
                .overlay {
                    RoundedRectangle(cornerRadius: L.radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 4)
                }
                .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 18, y: 10)
                .scaleEffect(focused ? 1.05 : 1, anchor: .leading)
        }
    }
}

// MARK: - Data

/// The studio's TMDB data: its logo and figures, then the rows (the folder's catalogs first).
@MainActor
final class OrbitStudioModel: ObservableObject {
    @Published private(set) var rows: [OrbitStudioRow] = []
    @Published private(set) var logo: String?
    @Published private(set) var statsLine: String?
    @Published private(set) var loading = true
    let name: String

    private let route: OrbitStudioRoute
    private var started = false
    private var folderModel: FolderDetailViewModel?
    private var folderRows: [OrbitStudioRow] = []
    private var tmdbRows: [OrbitStudioRow] = []
    private var cancellable: AnyCancellable?

    init(route: OrbitStudioRoute) {
        self.route = route
        name = route.name
    }

    func start() {
        guard !started else { return }
        started = true
        // The folder's own catalogs (Studios tab), drawn as the page's first rows.
        if let collectionId = route.collectionId, let folderId = route.folderId,
           let collection = CollectionRepository.shared.getCollection(id: collectionId),
           let folder = collection.folders.first(where: { $0.id == folderId }) {
            let folderModel = FolderDetailViewModel(route: FolderRoute(collectionId: collectionId, folder: folder))
            folderModel.buildsStripState = true
            self.folderModel = folderModel
            cancellable = folderModel.$stripRows.sink { [weak self] strip in
                Task { @MainActor in self?.applyFolder(strip) }
            }
            folderModel.start()
        }
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        guard !key.isEmpty else { loading = false; return }
        let language = TmdbSettingsRepository.shared.snapshot().language
        let route = route
        Task { [weak self] in
            let ids = await Self.resolveIds(route: route, apiKey: key)
            guard let ids, !ids.isEmpty else {
                self?.loading = false
                return
            }
            let found = await Self.load(ids: ids, network: route.isNetwork, apiKey: key, language: language)
            guard let self else { return }
            if self.logo == nil { self.logo = route.logo ?? found.logo }
            self.statsLine = Self.statsLine(network: route.isNetwork, count: found.count, since: found.since)
            self.tmdbRows = found.rows.map { OrbitStudioRow(id: $0.id, title: $0.title, items: $0.items) }
            self.loading = false
            self.publish()
        }
    }

    private func applyFolder(_ strip: [FolderStripRow]) {
        folderRows = strip.compactMap { row in
            guard row.status == .loaded, let items = row.section?.items, !items.isEmpty else { return nil }
            return OrbitStudioRow(id: "folder-\(row.id)", title: row.heading, items: items)
        }
        publish()
    }

    private func publish() {
        let next = folderRows + tmdbRows
        if next != rows { rows = next }
    }

    private static func statsLine(network: Bool, count: Int, since: String?) -> String {
        var parts: [String] = [network ? String(localized: "Chaîne") : String(localized: "Studio")]
        if count > 0 {
            parts.append(network ? String(localized: "\(count) séries") : String(localized: "\(count) films"))
        }
        if let since { parts.append(String(localized: "depuis \(since)")) }
        return parts.joined(separator: " · ")
    }

    // MARK: TMDB

    nonisolated private struct SearchResponse: Decodable {
        nonisolated struct Hit: Decodable { let id: Int }
        let results: [Hit]?
    }

    nonisolated private struct EntityResponse: Decodable {
        let logo_path: String?
    }

    nonisolated private struct DiscoverResponse: Decodable {
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
        let total_results: Int?
    }

    nonisolated private struct MovieResponse: Decodable {
        nonisolated struct Collection: Decodable {
            let id: Int
            let name: String?
            let backdrop_path: String?
            let poster_path: String?
        }
        let belongs_to_collection: Collection?
    }

    nonisolated private static func resolveIds(route: OrbitStudioRoute, apiKey: String) async -> String? {
        if let ids = route.companies, !ids.isEmpty { return ids }
        let query = route.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? route.name
        let kind = route.isNetwork ? "network" : "company"
        guard let url = URL(string: "https://api.themoviedb.org/3/search/\(kind)?api_key=\(apiKey)&query=\(query)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data),
              let first = decoded.results?.first else { return nil }
        return String(first.id)
    }

    nonisolated private static func load(ids: String, network: Bool, apiKey: String, language: String) async
        -> (logo: String?, count: Int, since: String?, rows: [(id: String, title: String, items: [MetaPreview])]) {
        let lang = language.isEmpty ? "fr-FR" : language
        let media = network ? "tv" : "movie"
        let dateField = network ? "first_air_date" : "primary_release_date"
        let filter = network ? "&with_networks=\(ids)" : "&with_companies=\(ids)"
        let base = "https://api.themoviedb.org/3/discover/\(media)?api_key=\(apiKey)&language=\(lang)" + filter
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: Date())

        // The logo (the first id's), the figures, the main rows, all at once.
        let firstId = ids.split(whereSeparator: { $0 == "|" || $0 == "," }).first.map(String.init) ?? ids
        async let entity: EntityResponse? = decode("https://api.themoviedb.org/3/\(network ? "network" : "company")/\(firstId)?api_key=\(apiKey)")
        async let oldest = discover(base + "&sort_by=\(dateField).asc&\(dateField).lte=\(today)&vote_count.gte=5", tv: network)
        async let best = discover(base + "&sort_by=vote_average.desc&vote_count.gte=300", tv: network)
        async let popular = discover(base + "&sort_by=popularity.desc", tv: network)
        async let popular2 = discover(base + "&sort_by=popularity.desc&page=2", tv: network)
        async let upcoming = discover(base + "&sort_by=\(dateField).asc&\(dateField).gte=\(today)", tv: network)

        let (entityValue, oldestValue, bestValue, popularValue, popular2Value, upcomingValue) =
            await (entity, oldest, best, popular, popular2, upcoming)

        var rows: [(id: String, title: String, items: [MetaPreview])] = []
        if bestValue.items.count >= 5 { rows.append(("best", String(localized: "Les incontournables"), bestValue.items)) }
        let popularItems = popularValue.items + popular2Value.items
        if popularItems.count >= 5 { rows.append(("popular", String(localized: "Les plus populaires"), popularItems)) }

        // The sagas: the collections the best-known films belong to (one card per saga, its art,
        // it opens the saga's first film met).
        if !network {
            var seen = Set<String>()
            let known = (popularItems + bestValue.items).filter { seen.insert($0.id).inserted }.prefix(30)
            let sagas = await withTaskGroup(of: (Int, MetaPreview?).self) { group in
                for (index, film) in known.enumerated() {
                    group.addTask {
                        let id = film.id.replacingOccurrences(of: "tmdb:", with: "")
                        let movie: MovieResponse? = await decode("https://api.themoviedb.org/3/movie/\(id)?api_key=\(apiKey)&language=\(lang)")
                        guard let saga = movie?.belongs_to_collection, let name = saga.name, !name.isEmpty else {
                            return (index, nil)
                        }
                        return (index, MetaPreview(id: film.id, type: "movie", name: name,
                                                   poster: saga.poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" } ?? film.poster,
                                                   banner: saga.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" } ?? film.banner,
                                                   logo: nil, posterShape: .landscape,
                                                   description: film.description_, releaseInfo: film.releaseInfo,
                                                   rawReleaseDate: nil, popularity: nil, voteCount: nil,
                                                   imdbRating: nil, genres: [], rawPosterUrl: "saga:\(saga.id)",
                                                   landscapePoster: nil, rawLandscapePosterUrl: nil,
                                                   customPosterApplied: false))
                    }
                }
                var out: [(Int, MetaPreview)] = []
                for await (index, item) in group { if let item { out.append((index, item)) } }
                return out.sorted { $0.0 < $1.0 }.map(\.1)
            }
            var sagaSeen = Set<String>()
            let unique = sagas.filter { sagaSeen.insert($0.rawPosterUrl ?? $0.name).inserted }
            if unique.count >= 2 { rows.append(("sagas", String(localized: "Les sagas"), unique)) }
        }

        if upcomingValue.items.count >= 3 { rows.append(("upcoming", String(localized: "Prochainement"), upcomingValue.items)) }

        // A row per decade, from the newest.
        let year = Calendar.current.component(.year, from: Date())
        let firstDecade = (year / 10) * 10
        let decades = stride(from: firstDecade, through: 1950, by: -10).map { $0 }
        let decadeRows = await withTaskGroup(of: (Int, [MetaPreview]).self) { group in
            for decade in decades {
                group.addTask {
                    let range = "&\(dateField).gte=\(decade)-01-01&\(dateField).lte=\(decade + 9)-12-31"
                    return (decade, await discover(base + "&sort_by=popularity.desc&vote_count.gte=20" + range, tv: network).items)
                }
            }
            var out: [Int: [MetaPreview]] = [:]
            for await (decade, items) in group { out[decade] = items }
            return out
        }
        for decade in decades {
            let items = decadeRows[decade] ?? []
            guard items.count >= 6 else { continue }
            let label = decade >= 2000 ? String(localized: "Les années \(decade)")
                : String(localized: "Les années \(decade % 100)")
            rows.append(("decade-\(decade)", label, items))
        }

        let since = oldestValue.items.first?.rawReleaseDate.map { String($0.prefix(4)) }
        return (entityValue?.logo_path.map { "https://image.tmdb.org/t/p/w500\($0)" },
                popularValue.total, since, rows)
    }

    nonisolated private static func decode<T: Decodable>(_ address: String) async -> T? {
        guard let url = URL(string: address),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    nonisolated private static func discover(_ address: String, tv: Bool) async -> (items: [MetaPreview], total: Int) {
        guard let decoded: DiscoverResponse = await decode(address) else { return ([], 0) }
        let items = (decoded.results ?? []).compactMap { r -> MetaPreview? in
            guard let name = r.title ?? r.name, !name.isEmpty, let poster = r.poster_path,
                  let backdrop = r.backdrop_path else { return nil }
            let date = r.release_date ?? r.first_air_date
            return MetaPreview(id: "tmdb:\(r.id)", type: tv ? "series" : "movie", name: name,
                               poster: "https://image.tmdb.org/t/p/w500\(poster)",
                               banner: "https://image.tmdb.org/t/p/w1280\(backdrop)",
                               logo: nil, posterShape: .landscape,
                               description: r.overview, releaseInfo: date.map { String($0.prefix(4)) },
                               rawReleaseDate: date, popularity: nil, voteCount: nil,
                               imdbRating: r.vote_average.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil },
                               genres: [], rawPosterUrl: nil, landscapePoster: nil,
                               rawLandscapePosterUrl: nil, customPosterApplied: false)
        }
        return (items, decoded.total_results ?? items.count)
    }
}
