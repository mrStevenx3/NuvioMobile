import Combine
import SharedCore
import SwiftUI

// Orbit Home (Steven's fork, 2026-10-23): Home's Films and Séries pages rebuilt from scratch after
// Steven's reference video, independent of the Stage / Classic layouts.
//
// Fluidity is the brief, so nothing here is moved by the focus engine. The page is ONE focusable
// stop (an invisible button over the content) that takes the remote's presses itself:
//  - Up / Down change the current section (hero → genres → rows). The whole column moves as one
//    layer on one curve (`OrbitHomeLayout.vertical`), so the focused section lands on its fixed
//    line; the sections above fade out as they leave.
//  - Left / Right move the current section's lead: every card is drawn at a computed x and they all
//    glide together (`OrbitHomeLayout.horizontal`), under a fixed, opaque frame.
//  - Select opens the title (or resumes it, or opens the genre); Menu goes back to the top.
// Only the sections near the current one exist, and in a row only the cards near its lead.
// While the page is scrolled past its first section, the Orbit bar is out of the focus engine's
// reach (`OrbitBarLock`), so Up is the page's own; at the top, Up goes to the bar.

/// Settings ▸ Home Screen ▸ Orbit Home.
nonisolated enum OrbitHomeSetting {
    static let enabledKey = "orbit_home_enabled"
    static let trailersKey = "orbit_home_trailers"
    /// Steven (2026-10-25): the previews that start on their own play with their sound.
    static let trailerSoundKey = "orbit_trailer_sound"
}

extension Notification.Name {
    /// Asks the Orbit bar to take focus (its current page's item): Menu at the top of an Orbit page.
    /// The system's own Menu sent focus to the hidden tab bar, where the cursor vanished.
    static let orbitBarFocusRequest = Notification.Name("OrbitBarFocusRequest")
}

/// Keeps the Orbit bar out of the focus engine's reach while Orbit Home is scrolled down.
@MainActor
final class OrbitBarLock: ObservableObject {
    static let shared = OrbitBarLock()
    @Published private(set) var locked = false
    private init() {}
    func set(_ value: Bool) {
        if locked != value { locked = value }
    }
}

/// The trailer dwell's rest signal: the page is at rest once no press has come for a moment.
@MainActor
final class OrbitHomeMotion: RowRestSignal {
    private var last = ProcessInfo.processInfo.systemUptime
    func stamp() { last = ProcessInfo.processInfo.systemUptime }
    /// Home's last Up/Down (its rows' window settles once no other came after it).
    var verticalStamp: TimeInterval = 0
    var restPending: Bool { false }
    var secondsSinceMotion: TimeInterval { ProcessInfo.processInfo.systemUptime - last }
}

/// What Home's pages can ask Home's navigation to do.
struct StageHomeActions {
    /// Continue Watching: open the stream picker (`HomeView.resume`).
    let resume: (ResumeTarget) -> Void
    /// Push onto Home's stack (`HomeView.homePath`).
    let push: (TitleRoute) -> Void
}

/// What covers Home from `HomeView`'s own presentation machinery.
nonisolated struct StageCover: Equatable {
    /// Something is pushed over Home (`!homePath.isEmpty`).
    var pushed: Bool
    /// The Continue Watching stream picker is up.
    var resume: Bool
}

/// Films / Séries: Orbit Home. Plateformes / Studios: their Orbit pages.
struct OrbitHomeSwitch: View {
    @ObservedObject var model: HomeViewModel
    let actions: StageHomeActions
    let pushGenre: (OrbitGenre) -> Void
    let cover: StageCover
    @Binding var isScrolledDown: Bool

    @ObservedObject private var contentFilter = HomeContentFilterModel.shared

    var body: some View {
        let filter = contentFilter.filter
        ZStack {
            if filter == .services || filter == .studios {
                OrbitSpacesPage(model: model, studios: filter == .studios, cover: cover)
                    .id(filter)
                    .transition(.opacity)
                    .onAppear { OrbitBarLock.shared.set(false) }
            } else {
                OrbitHomeView(model: model, series: filter == .series, actions: actions, pushGenre: pushGenre,
                              isScrolledDown: $isScrolledDown)
                    .id(filter)
                    .transition(.opacity)
            }
        }
        // Steven (device: Films ↔ Séries arrived at once): the pages cross-fade.
        .animation(.easeInOut(duration: 0.35), value: filter)
    }
}

struct OrbitHomeView: View {
    @ObservedObject var model: HomeViewModel
    let series: Bool
    let actions: StageHomeActions
    let pushGenre: (OrbitGenre) -> Void
    @Binding var isScrolledDown: Bool

    @ObservedObject private var heroModel = StageTrendingHeroModel.shared
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var current = 0
    /// Steven (device, still a hitch on Up/Down): the rows mounted follow the row the page last
    /// settled on, not the one it is moving to — the row coming into the window is built once the
    /// move is over, not in the frame the move starts.
    @State private var settled = 0
    @State private var leads: [String: Int] = [:]
    @State private var heroIndex = 0
    @FocusState private var canvasFocused: Bool
    @StateObject private var trailer = InlineTrailerCardModel()
    /// The page's own rows (TMDB): the Top 10 across the platforms, each platform's new titles.
    @StateObject private var extras = OrbitHomeExtrasModel()
    @State private var motion = OrbitHomeMotion()
    /// "<section>|<card>" the trailer is armed for.
    @State private var trailerKey: String?

    private enum Section: Equatable {
        case hero
        case genres
        case row(OrbitRow)

        var id: String {
            switch self {
            case .hero: return "hero"
            case .genres: return "genres"
            case .row(let row): return row.id
            }
        }
    }

    // MARK: Data

    private var heroItems: [MetaPreview] { heroModel.items(series: series) }
    private var genres: [OrbitGenre] { series ? OrbitGenre.series : OrbitGenre.movies }

    /// Steven (pass 3: "trop pauvre", tiles of different kinds and sizes): Reprendre in landscape
    /// tiles; his catalogs alternating the classic frame, large cards and smaller posters (his Top
    /// 10 keep the classic frame); the Top 10 across the platforms after the first catalog; each
    /// platform's new titles in landscape tiles, one every two catalogs.
    /// Fluidity (Steven, 2026-10-25, before the IPA): the rows were rebuilt — every card of every
    /// row, through the Kotlin lists — several times per remote press. They are rebuilt only when
    /// what they are made of changed (a cheap signature of the catalogs, Reprendre and the extras).
    @State private var rowsCache = OrbitRowsCache()

    private var rows: [OrbitRow] {
        let key = rowsSignature()
        if rowsCache.key == key { return rowsCache.rows }
        let built = buildRows()
        rowsCache.key = key
        rowsCache.rows = built
        return built
    }

    private func rowsSignature() -> String {
        var k = series ? "s|" : "m|"
        for e in model.continueWatching { k += "\(e.videoId):\(e.lastUpdatedEpochMs)," }
        k += "|"
        let because = series ? extras.becauseSeries : extras.becauseMovie
        for extra in (series ? extras.seriesRows : extras.movieRows) + [because].compactMap({ $0 }) {
            k += "\(extra.id)#\(extra.items.count)#\(extra.items.first?.id ?? ""),"
        }
        k += "|"
        for row in model.rows {
            guard case .catalog(let section) = row else { continue }
            let items = section.items
            k += "\(section.key)#\(items.count)#\(items.first?.id ?? "")#\(items.last?.id ?? ""),"
        }
        return k
    }

    private func buildRows() -> [OrbitRow] {
        var out: [OrbitRow] = []
        var seen = Set<String>()
        let entries = model.continueWatching.filter { series ? $0.parentMetaType != "movie" : $0.parentMetaType == "movie" }
        if !entries.isEmpty {
            out.append(OrbitRow(id: "continue-watching", title: String(localized: "Reprendre"),
                                cards: Self.unique(entries.map(OrbitCard.continueWatching)), style: .landscape))
            seen.insert("continue-watching")
        }
        let because = series ? extras.becauseSeries : extras.becauseMovie
        let extraRows = ((series ? extras.seriesRows : extras.movieRows) + [because].compactMap { $0 }).map { extra in
            OrbitRow(id: extra.id, title: extra.title, cards: Self.unique(extra.items.map { Self.card(extra.id, $0) }),
                     style: extra.style)
        }
        var top = extraRows.filter { $0.style == .ranked }
        // Orbit's own rows, one after each of his catalogs from the second, in this order.
        let order = ["orbit-because", "orbit-new", "orbit-soon", "orbit-sagas", "orbit-best"]
        var platforms = extraRows.filter { $0.style != .ranked }
            .sorted { a, b in
                (order.firstIndex { a.id.hasPrefix($0) } ?? 9) < (order.firstIndex { b.id.hasPrefix($0) } ?? 9)
            }
        let cycle: [OrbitRowStyle] = [.cards, .classic, .posters]
        var catalogs = 0
        var styled = 0
        for row in model.rows {
            guard case .catalog(let section) = row else { continue }
            let movie = section.target.contentType == "movie"
            guard series ? !movie : movie, !section.items.isEmpty, seen.insert(section.key).inserted else { continue }
            let heading = section.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let isTop = heading.contains("top 10") || heading.contains("top10")
            // Steven: one Top 10 is enough — Orbit's own (across his platforms) replaces his add-on's
            // on Home once it has arrived (the platforms' pages keep theirs).
            if isTop, extraRows.contains(where: { $0.style == .ranked }) { continue }
            var style: OrbitRowStyle = .classic
            if !isTop {
                style = styled == 0 ? .classic : cycle[(styled - 1) % cycle.count]
                styled += 1
            }
            out.append(OrbitRow(id: section.key, title: section.title,
                                cards: Self.unique(section.items.map(OrbitCard.catalog)), sectionKey: section.key,
                                style: style))
            catalogs += 1
            // Steven: the Top 10 well forward, right after the first catalog.
            if catalogs == 1, !top.isEmpty { out.append(top.removeFirst()) }
            if catalogs >= 2, !platforms.isEmpty { out.append(platforms.removeFirst()) }
        }
        return out + top + platforms
    }

    /// An Orbit row's card: a saga keeps its own id (it opens its first film), Prochainement shows
    /// its date ("12 nov.") on the tile.
    private static func card(_ rowId: String, _ item: MetaPreview) -> OrbitCard {
        var card = OrbitCard.catalog(item)
        if rowId.hasPrefix("orbit-sagas") {
            card = OrbitCard(id: "saga:\(item.id)", preview: item, poster: item.poster, landscape: card.landscape)
        }
        if rowId.hasPrefix("orbit-soon"), let raw = item.rawReleaseDate, raw.count >= 10,
           let date = Self.isoDay.date(from: String(raw.prefix(10))) {
            card.badge = String(localized: "Le \(Self.shortDay.string(from: date))")
        }
        return card
    }

    // Made once (a DateFormatter is costly to create).
    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        return f
    }()

    /// "Parce que vous avez regardé": the last title watched of the page's kind — finished (his
    /// watched list) or in progress (Reprendre), the more recent of the two.
    private func becauseSeed(series: Bool) -> (id: String, name: String)? {
        let entry = model.continueWatching
            .filter { series ? $0.parentMetaType != "movie" : $0.parentMetaType == "movie" }
            .max { $0.lastUpdatedEpochMs < $1.lastUpdatedEpochMs }
        let watched = (WatchedRepository.shared.uiState.value_ as? WatchedUiState)?.items
            .filter { series ? $0.type != "movie" : $0.type == "movie" }
            .max { $0.markedAtEpochMs < $1.markedAtEpochMs }
        if let watched, watched.markedAtEpochMs > (entry?.lastUpdatedEpochMs ?? 0) {
            return (watched.id, watched.name)
        }
        if let entry { return (entry.parentMetaId, entry.title) }
        return nil
    }

    private static func unique(_ cards: [OrbitCard]) -> [OrbitCard] {
        var seen = Set<String>()
        return cards.filter { seen.insert($0.id).inserted }
    }

    private var sections: [Section] {
        var out: [Section] = []
        if !heroItems.isEmpty { out.append(.hero) }
        // Steven: no genre chips (Découvrir covers it).
        out.append(contentsOf: rows.map(Section.row))
        return out
    }

    // MARK: Geometry

    /// Each section's anchor in the column (hero top, chips top, row heading centre).
    private func anchors(_ sections: [Section]) -> [CGFloat] {
        let L = OrbitHomeLayout.self
        var y: CGFloat = 0
        var out: [CGFloat] = []
        for section in sections {
            out.append(y)
            switch section {
            case .hero: y += L.heroPitch
            case .genres: y += L.genresPitch
            case .row(let row): y += OrbitTileLayout.pitch(row.style)
            }
        }
        return out
    }

    private func screenLine(_ section: Section) -> CGFloat {
        switch section {
        case .hero: return OrbitHomeLayout.heroTop
        case .genres: return OrbitHomeLayout.chipsTop
        case .row: return OrbitHomeLayout.rowAnchor
        }
    }

    // MARK: Body

    var body: some View {
        let sections = sections
        let anchors = anchors(sections)
        let index = min(current, max(0, sections.count - 1))
        let scroll = sections.isEmpty ? 0 : screenLine(sections[index]) - anchors[index]
        let base = abs(settled - index) <= 1 ? settled : index
        let low = max(0, min(base - 1, index))
        let window = low...max(low, min(sections.count - 1, max(base + 2, index + 1)))
        let heroItem = heroItems.isEmpty ? nil : heroItems[heroIndex % heroItems.count]

        ZStack(alignment: .topLeading) {
            // (The blurred ambient behind the hero is gone: the full-screen hero covers it, it was
            // fetched and blurred for nothing on every title.)
            // Steven (2026-10-25, pass 2: the rows left the screen half black): the focused title's
            // art fills the top right behind the rows, fading to the left and down.
            OrbitRowsBackdrop(url: rowsBackdropURL(sections: sections, index: index))
                .opacity(index > 0 ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: index > 0)

            ZStack(alignment: .topLeading) {
                if !sections.isEmpty {
                    ForEach(Array(zip(window, sections[window])), id: \.1.id) { i, section in
                        sectionView(section, isCurrent: i == index, heroItem: heroItem)
                            .offset(y: anchors[i])
                            .opacity(i < index ? 0 : 1)
                            .transition(.identity)
                    }
                }
            }
            .offset(y: scroll)

            // The page's one focusable stop, under the bar's band.
            Button(action: select) {
                Color.clear
                    .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight - 110)
                    .contentShape(Rectangle())
            }
            .buttonStyle(OrbitCanvasButtonStyle())
            .focused($canvasFocused)
            .onMoveCommand(perform: move)
            .onExitCommand(perform: exitAction(index: index))
            .offset(y: 110)
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight, alignment: .topLeading)
        .background(OrbitHomeLayout.background)
        .ignoresSafeArea()
        .onAppear {
            heroModel.loadIfNeeded()
            extras.load()
            WatchedRepository.shared.ensureLoaded()
            extras.loadBecause(seed: becauseSeed(series: series), series: series)
            OrbitPlatformLogos.update()
            trailer.restSource = .custom(motion)
            refreshAfterMove()
        }
        .onDisappear {
            trailer.reset(abortStages: true)
            OrbitBarLock.shared.set(false)
        }
        .onChange(of: canvasFocused) { _, _ in refreshAfterMove() }
        .onChange(of: model.continueWatching.count) { _, _ in
            extras.loadBecause(seed: becauseSeed(series: series), series: series)
        }
        .onChange(of: sections.map(\.id)) { _, _ in
            if current >= sections.count { current = max(0, sections.count - 1) }
            if settled >= sections.count { settled = max(0, sections.count - 1) }
            refreshAfterMove()
        }
    }

    @ViewBuilder
    private func sectionView(_ section: Section, isCurrent: Bool, heroItem: MetaPreview?) -> some View {
        let focusedHere = isCurrent && canvasFocused
        switch section {
        case .hero:
            OrbitHomeHeroView(item: heroItem, focused: focusedHere,
                              count: heroItems.count, index: heroItems.isEmpty ? 0 : heroIndex % heroItems.count,
                              trailerURL: trailerURL(for: "hero", id: heroItem.map { "\($0.type):\($0.id)" }),
                              onTrailerFailure: { trailer.playbackFailed($0) },
                              onTrailerEnded: { trailer.playbackFinished() })
        case .genres:
            OrbitGenresView(genres: genres, lead: leads["genres"] ?? 0, focused: focusedHere)
        case .row(let row):
            let lead = min(leads[row.id] ?? 0, max(0, row.cards.count - 1))
            let rowTrailer = row.cards.indices.contains(lead) ? trailerURL(for: row.id, id: row.cards[lead].id) : nil
            if row.style == .classic {
                OrbitHomeRowView(row: row, lead: lead, isCurrent: isCurrent, focused: focusedHere,
                                 trailerURL: rowTrailer,
                                 onTrailerFailure: { trailer.playbackFailed($0) },
                                 onTrailerEnded: { trailer.playbackFinished() })
            } else {
                OrbitHomeTileRowView(row: row, lead: lead, isCurrent: isCurrent, focused: focusedHere,
                                     trailerURL: rowTrailer,
                                     onTrailerFailure: { trailer.playbackFailed($0) },
                                     onTrailerEnded: { trailer.playbackFinished() })
            }
        }
    }

    /// The current row's focused title's art (nil on the hero).
    private func rowsBackdropURL(sections: [Section], index: Int) -> String? {
        guard sections.indices.contains(index), case .row(let row) = sections[index] else { return nil }
        let lead = min(leads[row.id] ?? 0, max(0, row.cards.count - 1))
        guard row.cards.indices.contains(lead) else { return nil }
        let card = row.cards[lead]
        // The card's own art first (known at once: no swap when TMDB's arrives).
        return card.landscape ?? OrbitMetaStore.shared.meta(for: card.preview)?.backdrop
    }

    private func trailerURL(for section: String, id: String?) -> String? {
        guard let id, trailerKey == "\(section)|\(id)" else { return nil }
        return trailer.playingURL
    }

    // MARK: Input

    private func move(_ direction: MoveCommandDirection) {
        let sections = sections
        guard !sections.isEmpty else { return }
        let index = min(current, sections.count - 1)
        switch direction {
        case .down:
            guard index + 1 < sections.count else { return }
            withAnimation(reduceMotion ? nil : OrbitHomeLayout.vertical) { current = index + 1 }
            settleLater()
        case .up:
            guard index > 0 else { return }   // the bar takes it (unlocked at the top)
            withAnimation(reduceMotion ? nil : OrbitHomeLayout.vertical) { current = index - 1 }
            settleLater()
        case .left, .right:
            let delta = direction == .right ? 1 : -1
            switch sections[index] {
            case .hero:
                let count = heroItems.count
                guard count > 1 else { return }
                withAnimation(OrbitHomeLayout.horizontal) { heroIndex = (heroIndex + delta + count) % count }
            case .genres:
                let lead = (leads["genres"] ?? 0) + delta
                guard genres.indices.contains(lead) else { return }
                withAnimation(OrbitHomeLayout.horizontal) { leads["genres"] = lead }
            case .row(let row):
                let lead = min(leads[row.id] ?? 0, row.cards.count - 1) + delta
                guard row.cards.indices.contains(lead) else { return }
                // TMDB's results wait for the slide to end (a redraw of every row mid-slide).
                OrbitMetaStore.shared.holdPublishing(for: 0.3)
                withAnimation(OrbitHomeLayout.horizontal) { leads[row.id] = lead }
            }
        @unknown default:
            return
        }
        refreshAfterMove()
    }

    private func select() {
        let sections = sections
        guard !sections.isEmpty else { return }
        switch sections[min(current, sections.count - 1)] {
        case .hero:
            guard !heroItems.isEmpty else { return }
            actions.push(TitleRoute(preview: heroItems[heroIndex % heroItems.count]))
        case .genres:
            let lead = leads["genres"] ?? 0
            if genres.indices.contains(lead) { pushGenre(genres[lead]) }
        case .row(let row):
            let lead = min(leads[row.id] ?? 0, row.cards.count - 1)
            guard row.cards.indices.contains(lead) else { return }
            let card = row.cards[lead]
            if let entry = card.entry {
                actions.resume(ResumeTarget(entry: entry))
            } else {
                actions.push(TitleRoute(preview: card.preview))
            }
        }
    }

    /// Menu: back to the top from below it; at the top, the system's own (the bar, then out).
    private func exitAction(index: Int) -> (() -> Void)? {
        guard index > 0 else {
            return { NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil) }
        }
        return { goTop() }
    }

    /// Once no vertical move has come for the length of one: the window catches up (idle).
    private func settleLater() {
        // TMDB's results wait for the move to end (a redraw of every row mid-move is the hitch).
        OrbitMetaStore.shared.holdPublishing(for: 0.45)
        let stamp = ProcessInfo.processInfo.systemUptime
        motion.verticalStamp = stamp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard motion.verticalStamp == stamp, settled != current else { return }
            settled = current
        }
    }

    private func goTop() {
        settled = 0
        withAnimation(reduceMotion ? nil : OrbitHomeLayout.vertical) { current = 0 }
        refreshAfterMove()
    }

    /// After any move: the bar's lock, Home's scrolled flag, the trailer dwell, the look-ahead.
    private func refreshAfterMove() {
        let sections = sections
        let index = min(current, max(0, sections.count - 1))
        OrbitBarLock.shared.set(canvasFocused && index > 0)
        if isScrolledDown != (index > 0) { isScrolledDown = index > 0 }
        motion.stamp()

        // The look-ahead: TMDB meta and frame art for the titles around each nearby row's lead.
        var metaItems: [MetaPreview] = []
        if !heroItems.isEmpty {
            metaItems.append(contentsOf: (0..<min(3, heroItems.count)).map { heroItems[(heroIndex + $0) % heroItems.count] })
        }
        for i in max(0, index - 1)...max(0, min(sections.count - 1, index + 1)) where sections.indices.contains(i) {
            guard case .row(let row) = sections[i] else { continue }
            let lead = min(leads[row.id] ?? 0, max(0, row.cards.count - 1))
            let around = row.cards.indices.filter { $0 >= lead - 1 && $0 <= lead + 3 }
            metaItems.append(contentsOf: around.map { row.cards[$0].preview })
            let request = ArtworkDecodeRequest(size: .points(width: OrbitHomeLayout.frameWidth, height: OrbitHomeLayout.cardHeight),
                                               fill: true, scale: UIScreen.main.scale)
            ArtworkStore.prefetch(around.compactMap { j in
                row.cards[j].landscape.flatMap(URL.init(string:)).map { ArtworkPrefetchItem(url: $0, decode: request) }
            })
            if let key = row.sectionKey { model.rowAppeared(sectionKey: key) }
        }
        // Steven: the Top 10's details were late on each move — its ten titles are looked up all
        // at once, as soon as the page has them (after the nearby ones).
        for section in sections {
            guard case .row(let row) = section, row.style == .ranked else { continue }
            metaItems.append(contentsOf: row.cards.prefix(10).map(\.preview))
        }
        OrbitMetaStore.shared.request(metaItems)

        // The trailer: re-armed on the current title, or stopped.
        trailer.reset()
        trailerKey = nil
        guard trailersOn, canvasFocused, UIAccessibility.isVideoAutoplayEnabled,
              sections.indices.contains(index) else { return }
        trailer.prefersReducedMotion = reduceMotion
        trailer.restSource = .custom(motion)
        switch sections[index] {
        case .hero:
            guard !heroItems.isEmpty else { return }
            let item = heroItems[heroIndex % heroItems.count]
            trailerKey = "hero|\(item.type):\(item.id)"
            trailer.focusChanged(true, item: item)
        case .row(let row):
            // The trailer plays in the classic frame and in the large cards only.
            guard row.style == .classic || row.style == .cards else { return }
            let lead = min(leads[row.id] ?? 0, max(0, row.cards.count - 1))
            guard row.cards.indices.contains(lead) else { return }
            let card = row.cards[lead]
            trailerKey = "\(row.id)|\(card.id)"
            trailer.focusChanged(true, item: card.preview)
        case .genres:
            return
        }
    }
}

/// No system focus effect: the page draws its own.
private struct OrbitCanvasButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// The rows' backdrop: the focused title's art in the top right, fading into the page to the left
/// and down (as on Prime's and Paramount+'s pages), dimmed so the rows stay in front.
/// The colour of Home's wash (the focused title's), shared with the rows' headings.
@MainActor
final class OrbitHomeTone: ObservableObject {
    static let shared = OrbitHomeTone()
    @Published var color: Color?
}

/// A row's heading on Home. Steven (2026-10-25: the headings melted into the titles' text under
/// them): larger, heavier, a soft white gradient, and a short bar in the wash's colour before it.
struct OrbitRowHeading: View {
    let title: String
    let isCurrent: Bool
    /// The bar's colour where the page has its own (a platform's, a studio's); else Home's wash.
    var accent: Color? = nil
    var size: CGFloat = 34
    @ObservedObject private var tone = OrbitHomeTone.shared

    var body: some View {
        let colour = accent ?? tone.color
        HStack(spacing: size * 0.4) {
            Capsule()
                .fill(colour ?? Color.white.opacity(0.8))
                .frame(width: max(5, size * 0.18), height: size * 0.88)
                .shadow(color: (colour ?? .white).opacity(0.6), radius: 6)
            Text(title)
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.78)],
                                                startPoint: .top, endPoint: .bottom))
                .lineLimit(1)
        }
        // The whole heading dimmed (not its colour): an emoji in a catalogue's name dims with it.
        .opacity(isCurrent ? 1 : 0.55)
        .frame(height: size * 1.3, alignment: .center)
        .animation(.easeInOut(duration: 0.5), value: colour)
    }
}

/// The band behind a Top 10 (Steven: "une bande qui se fond"): a light frosted strip, solid in
/// the middle and melting away above and below, that holds the ranks and posters together.
struct OrbitTop10Band: View {
    let height: CGFloat

    var body: some View {
        LinearGradient(stops: [.init(color: .white.opacity(0), location: 0),
                               .init(color: .white.opacity(0.10), location: 0.2),
                               .init(color: .white.opacity(0.10), location: 0.8),
                               .init(color: .white.opacity(0), location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .overlay {
                // Two soft rims where the strip is solid.
                VStack {
                    Color.white.opacity(0.10).frame(height: 1).padding(.top, height * 0.2)
                    Spacer()
                    Color.white.opacity(0.10).frame(height: 1).padding(.bottom, height * 0.2)
                }
            }
            .frame(width: OrbitHomeLayout.screenWidth, height: height)
            .allowsHitTesting(false)
    }
}

struct OrbitRowsBackdrop: View {
    let url: String?
    /// The page's black under it (off where the page has its own ground).
    var opaque = true

    /// Steven (device: the art behind the rows looked overloaded): no image any more — a soft wash
    /// of the focused title's dominant colour from the top right, fading into the page (as the
    /// Top 10's ranks take their poster's colour).
    @State private var tone: Color?

    var body: some View {
        let L = OrbitHomeLayout.self
        ZStack {
            if opaque { L.background }
            if let tone {
                RadialGradient(colors: [tone.opacity(0.38), tone.opacity(0.14), .clear],
                               center: UnitPoint(x: 0.82, y: 0.08), startRadius: 0, endRadius: 1500)
                    .transition(.opacity)
            }
        }
        .frame(width: L.screenWidth, height: L.screenHeight)
        .animation(.easeInOut(duration: 0.5), value: tone)
        .task(id: url ?? "-") {
            guard let url else { return }
            // Steven (device: still a hitch Left / Right): the wash follows the title once the
            // remote rests — a full-screen colour change animating under every step was part of it.
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            if let color = await OrbitDominantColor.color(for: url), !Task.isCancelled {
                tone = color
                if opaque { OrbitHomeTone.shared.color = color }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Steven (2026-10-25, Search / Library / Discover in Orbit's language): the focused title's art
/// faded in top right behind a page, as on Home (its add-on art, else TMDB's backdrop).
struct OrbitFocusBackdrop: View {
    let item: MetaPreview?
    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        let banner: String? = item?.banner
        let url = (banner?.isEmpty == false ? banner : nil) ?? item.flatMap { metaStore.meta(for: $0)?.backdrop }
        OrbitRowsBackdrop(url: url, opaque: false)
            .task(id: item?.id ?? "-") { if let item { metaStore.request([item]) } }
    }
}

/// Orbit Home's last built rows and what they were built from (a reference: updating it never
/// re-renders the page).
final class OrbitRowsCache {
    var key: String?
    var rows: [OrbitRow] = []
}

/// Fluidity (Steven, 2026-10-25, before the IPA): what a platform page's rows are made of — his
/// catalogs (compared by their own equality key, no Kotlin list read), the page's filter, the TMDB
/// extras and any page switch. The rows are rebuilt only when it changes.
struct OrbitRowsKey: Equatable {
    var rows: [FolderStripRow]
    var filter: String?
    var extras: [OrbitPlatformExtrasModel.Extra] = []
    var variant: String = ""
    /// The rows' types (the Films / Séries filter reads them; not in a row's own equality key).
    private var types: [String?]

    init(rows: [FolderStripRow], filter: String?, extras: [OrbitPlatformExtrasModel.Extra] = [], variant: String = "") {
        self.rows = rows
        self.filter = filter
        self.extras = extras
        self.variant = variant
        types = rows.map(\.contentType)
    }
}

/// One page's last built value for an `OrbitRowsKey` (a reference: updating it never re-renders).
final class OrbitRowsMemo<Value> {
    private var key: OrbitRowsKey?
    private var value: Value?

    func get(_ key: OrbitRowsKey, _ make: () -> Value) -> Value {
        if let value, self.key == key { return value }
        let built = make()
        self.key = key
        value = built
        return built
    }
}
