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
    @State private var leads: [String: Int] = [:]
    @State private var heroIndex = 0
    @FocusState private var canvasFocused: Bool
    @StateObject private var trailer = InlineTrailerCardModel()
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

    private var rows: [OrbitRow] {
        var out: [OrbitRow] = []
        var seen = Set<String>()
        let entries = model.continueWatching.filter { series ? $0.parentMetaType != "movie" : $0.parentMetaType == "movie" }
        if !entries.isEmpty {
            out.append(OrbitRow(id: "continue-watching", title: String(localized: "Reprendre"),
                                cards: Self.unique(entries.map(OrbitCard.continueWatching))))
            seen.insert("continue-watching")
        }
        for row in model.rows {
            guard case .catalog(let section) = row else { continue }
            let movie = section.target.contentType == "movie"
            guard series ? !movie : movie, !section.items.isEmpty, seen.insert(section.key).inserted else { continue }
            out.append(OrbitRow(id: section.key, title: section.title,
                                cards: Self.unique(section.items.map(OrbitCard.catalog)), sectionKey: section.key))
        }
        return out
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
            case .row: y += L.rowPitch
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
        let window = max(0, index - 1)...max(max(0, index - 1), min(sections.count - 1, index + 2))
        let heroItem = heroItems.isEmpty ? nil : heroItems[heroIndex % heroItems.count]

        ZStack(alignment: .topLeading) {
            OrbitAmbient(url: heroItem?.banner, visible: sections.first == .hero && index == 0)
                .ignoresSafeArea()

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
            trailer.restSource = .custom(motion)
            refreshAfterMove()
        }
        .onDisappear {
            trailer.reset(abortStages: true)
            OrbitBarLock.shared.set(false)
        }
        .onChange(of: canvasFocused) { _, _ in refreshAfterMove() }
        .onChange(of: sections.map(\.id)) { _, _ in
            if current >= sections.count { current = max(0, sections.count - 1) }
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
            OrbitHomeRowView(row: row, lead: lead, isCurrent: isCurrent, focused: focusedHere,
                             trailerURL: row.cards.indices.contains(lead) ? trailerURL(for: row.id, id: row.cards[lead].id) : nil,
                             onTrailerFailure: { trailer.playbackFailed($0) },
                             onTrailerEnded: { trailer.playbackFinished() })
        }
    }

    /// The current row's focused title's art (nil on the hero).
    private func rowsBackdropURL(sections: [Section], index: Int) -> String? {
        guard sections.indices.contains(index), case .row(let row) = sections[index] else { return nil }
        let lead = min(leads[row.id] ?? 0, max(0, row.cards.count - 1))
        guard row.cards.indices.contains(lead) else { return nil }
        let card = row.cards[lead]
        return OrbitMetaStore.shared.meta(for: card.preview)?.backdrop ?? card.landscape
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
        case .up:
            guard index > 0 else { return }   // the bar takes it (unlocked at the top)
            withAnimation(reduceMotion ? nil : OrbitHomeLayout.vertical) { current = index - 1 }
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

    private func goTop() {
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
private struct OrbitRowsBackdrop: View {
    let url: String?

    var body: some View {
        let L = OrbitHomeLayout.self
        let size = CGSize(width: 1400, height: 788)
        ZStack(alignment: .topTrailing) {
            L.background
            if let url {
                ZStack {
                    OrbitSwapImage(url: url, fallback: nil, size: size)
                    LinearGradient(stops: [
                        .init(color: L.background, location: 0),
                        .init(color: L.background.opacity(0.6), location: 0.28),
                        .init(color: .clear, location: 0.6),
                    ], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: L.background.opacity(0.7), location: 0.7),
                        .init(color: L.background, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .frame(width: size.width, height: size.height)
                .opacity(0.6)
            }
        }
        .frame(width: L.screenWidth, height: L.screenHeight, alignment: .topTrailing)
        .clipped()
        .allowsHitTesting(false)
    }
}
