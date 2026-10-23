import Combine
import SwiftUI
import SharedCore

// Steven's fork (Orbit top bar): the navigation chrome that replaces the system tab bar and the
// rail when Settings › Appearance › Navigation is "Orbit Bar" (the default in this fork). A row of
// glass pills pinned to the screen's top-left corner, in three groups split by thin vertical rules:
//
//                        …          [ 🔍  Films  Séries  📚  🧭  |  Plateformes  Studios ]  [ ⚙︎ ]
//
// Films, Séries, Services and Studios are four views of the Home tab (`HomeContentFilter`); the
// glyphs open Search, Library, Discover and Settings. Mounted once, in `MainTabView`'s overlay,
// outside every `Tab` closure (the rail's T3 rule), and hidden while a page is pushed over a tab
// root (`TabBarVisibility.immersiveHidden`, the same signal the system bar used).

// MARK: - Home content filter

/// Which slice of Home the Stage strip shows (`StageStripHome.rowKeys`). `.all` outside the Orbit bar.
enum HomeContentFilter: String, Equatable, Sendable {
    case all
    case movies
    case series
    case services
    case studios

    /// Collection rows that belong on the Services page (by their title, the collection's own name).
    static func isServicesCollection(title: String) -> Bool {
        let t = title.lowercased()
        return t.contains("service") || t.contains("plateforme") || t.contains("platform") || t.contains("streaming")
    }

    /// Collection rows that belong on the Studios page.
    static func isStudiosCollection(title: String) -> Bool {
        title.lowercased().contains("studio")
    }
}

/// The current Home slice, shared by the bar (writes) and Stage Home (reads). A singleton because the
/// bar lives in the shell's overlay and Home deep inside a `Tab`; both observe this one object.
@MainActor
final class HomeContentFilterModel: ObservableObject {
    static let shared = HomeContentFilterModel()

    /// Films is the landing page with the Orbit bar; every other chrome shows all of Home.
    @Published var filter: HomeContentFilter = NavigationChrome.isOrbitBar() ? .movies : .all

    func set(_ next: HomeContentFilter) {
        if filter != next { filter = next }
    }
}

// MARK: - Items

private enum OrbitBarItem: Hashable, CaseIterable {
    case search, films, series, library, discover, services, studios, settings

    var title: String? {
        switch self {
        case .films: return String(localized: "Films")
        case .series: return String(localized: "Séries")
        case .services: return String(localized: "Plateformes")
        case .studios: return String(localized: "Studios")
        default: return nil
        }
    }

    var systemImage: String? {
        switch self {
        case .search: return "magnifyingglass"
        case .library: return "books.vertical"
        case .discover: return "safari"
        case .settings: return "gearshape"
        default: return nil
        }
    }

    var accessibilityName: String {
        switch self {
        case .search: return String(localized: "Search")
        case .library: return String(localized: "Library")
        case .discover: return String(localized: "Discover")
        case .settings: return String(localized: "Settings")
        default: return title ?? ""
        }
    }

    /// The Home slice a text item selects (nil for the glyphs, which open other tabs).
    var homeFilter: HomeContentFilter? {
        switch self {
        case .films: return .movies
        case .series: return .series
        case .services: return .services
        case .studios: return .studios
        default: return nil
        }
    }
}

private enum OrbitBarMetrics {
    /// The top-left corner: the tvOS safe-area line, like the rail's Corner position.
    static let leading: CGFloat = 60
    /// Steven (2026-10-23): a little higher, off Orbit Home's hero (was 38).
    static let top: CGFloat = 22
    static let pillPadding: CGFloat = 6
    static let itemHeight: CGFloat = 62
    static let textPadding: CGFloat = 24
    static let groupGap: CGFloat = 18
    static let ruleHeight: CGFloat = 40
    static let fontSize: CGFloat = 27
    static let glyphSize: CGFloat = 28
    static let focusScale: CGFloat = 1.08
}

// MARK: - The bar

struct OrbitTopBar: View {
    @Binding var selectedTab: Int
    /// Passed in, never read from the environment (the rail's rc2 rule: the shell's overlay sits
    /// outside the environment modifiers that carry it).
    let tabBarVisibility: TabBarVisibility
    /// Discover on its own tab (selection 6); otherwise the compass opens Search, which hosts it.
    let showsDiscover: Bool

    @ObservedObject private var homeFilter = HomeContentFilterModel.shared
    @ObservedObject private var barLock = OrbitBarLock.shared
    @FocusState private var focused: OrbitBarItem?
    @State private var immersive = false
    /// Pass 4: the launch focus (the engine's pick, the top-left Search glyph) is moved once onto
    /// the current page's item (Films at launch).
    @State private var placedLaunchFocus = false
    @State private var searchReady = false
    /// Pass 7: the Plateformes / Studios portal (`OrbitSpaceTransition`), one id per run.
    @State private var transitionId: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: OrbitBarMetrics.groupGap) {
            // Steven (2026-10-23, like his reference): the bar on the right — one block with the
            // pages, Plateformes / Studios split off by a rule inside it, and Settings in a block
            // of its own at the far right.
            Spacer(minLength: 0)
            pill([[.search, .films, .series, .library, .discover], [.services, .studios]])
            pill([[.settings]])
        }
        .padding(.trailing, OrbitBarMetrics.leading)
        // Orbit Home: out of reach while the page is scrolled down (Up is the page's own).
        .disabled(barLock.locked)
        // The focus section hugs the bar's band (device pass 1: drawn over the whole screen, it
        // kept Down from reaching Settings' list); it spans the width so Right reaches Settings.
        .focusSection()
        // Pass 3: Up into the bar lands on the current page's item (Discover from Discover…).
        .defaultFocus($focused, currentItem, priority: .userInitiated)
        .padding(.top, OrbitBarMetrics.top)
        .padding(.leading, OrbitBarMetrics.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .overlay {
            if let id = transitionId {
                OrbitSpaceTransition {
                    if transitionId == id { transitionId = nil }
                }
                .id(id)
            }
        }
        .opacity(immersive ? 0 : 1)
        .allowsHitTesting(!immersive)
        .disabled(immersive)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: immersive)
        .onReceive(tabBarVisibility.$immersiveHidden) { immersive = $0 }
        // Pass 6: the hidden system tab bar is still focusable (Search's system field sends focus
        // into it, and every remote press then went nowhere). The rail's blocker, mounted here
        // too, takes it out of the focus engine; a landing there anyway comes back to the bar.
        .background(alignment: .topLeading) {
            // No redirect (device pass: with the system search keyboard it pulled focus off the
            // keys onto the results); the blocker alone keeps the hidden bar unfocusable.
            HiddenTabBarFocusBlocker()
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        // Steven: at launch the cursor sits on Films (the hero / first row took it late).
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { searchReady = true }
            OrbitBarLaunchFocus.place {
                guard selectedTab == 0 else { return }
                if focused != currentItem { focused = currentItem }
            }
        }
        .onChange(of: focused) { _, item in
            if item != nil, !searchReady {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { searchReady = true }
            }
            guard !placedLaunchFocus, let item else { return }
            placedLaunchFocus = true
            if item != currentItem {
                DispatchQueue.main.async { focused = currentItem }
            }
        }
    }

    private func pill(_ groups: [[OrbitBarItem]]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, items in
                if index > 0 {
                    rule.padding(.horizontal, 10)
                }
                ForEach(items, id: \.self) { item in
                Button { select(item) } label: {
                    OrbitBarItemLabel(item: item, selected: isSelected(item), focused: focused == item)
                }
                .buttonStyle(OrbitBarButtonStyle())
                .focused($focused, equals: item)
                // Steven: the engine's first pick was Search (top-left), flashing before Films.
                // Search is out of reach until the first focus has landed.
                .disabled(item == .search && !searchReady)
                .accessibilityLabel(item.accessibilityName)
                .accessibilityIdentifier("orbit_bar_\(item)")
                }
            }
        }
        .padding(OrbitBarMetrics.pillPadding)
        // Steven: slightly lighter (a white veil over the glass).
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.10)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.white.opacity(0.35))
            .frame(width: 1.5, height: OrbitBarMetrics.ruleHeight)
    }

    /// The item of the page on screen.
    private var currentItem: OrbitBarItem {
        OrbitBarItem.allCases.first(where: isSelected) ?? .films
    }

    private func isSelected(_ item: OrbitBarItem) -> Bool {
        if let filter = item.homeFilter { return selectedTab == 0 && homeFilter.filter == filter }
        switch item {
        case .search: return selectedTab == 1
        case .library: return selectedTab == 2
        case .discover: return selectedTab == 6
        case .settings: return selectedTab == 4
        default: return false
        }
    }

    private func select(_ item: OrbitBarItem) {
        // Pass 7/8: the portal plays entering Plateformes / Studios from any other page, and leaving
        // them for Search, Films, Séries, Library or Discover (not Settings, not between the two).
        let spaces: Set<HomeContentFilter> = [.services, .studios]
        let inSpace = selectedTab == 0 && spaces.contains(homeFilter.filter)
        let toSpace = item.homeFilter.map(spaces.contains) ?? false
        if !reduceMotion, inSpace != toSpace, item != .settings {
            transitionId = (transitionId ?? 0) + 1
        }
        if let filter = item.homeFilter {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { homeFilter.set(filter) }
            selectedTab = 0
            return
        }
        switch item {
        case .search: selectedTab = 1
        case .library: selectedTab = 2
        case .discover: selectedTab = showsDiscover ? 6 : 1
        case .settings: selectedTab = 4
        default: break
        }
    }
}

/// One item's look. `focused` comes from the bar's own `@FocusState` (never `@Environment(\.isFocused)`,
/// device-unreliable, BUG-65): a white capsule with dark ink, slightly enlarged. The selected item
/// keeps a light capsule while focus is elsewhere.
private struct OrbitBarItemLabel: View {
    let item: OrbitBarItem
    let selected: Bool
    let focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .foregroundStyle(focused ? Color.black : Color.white)
            .frame(minWidth: OrbitBarMetrics.itemHeight, minHeight: OrbitBarMetrics.itemHeight)
            .background {
                Capsule(style: .continuous)
                    .fill(focused ? Color.white : Color.white.opacity(selected ? 0.24 : 0))
            }
            .scaleEffect(focused && !reduceMotion ? OrbitBarMetrics.focusScale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: focused)
    }

    @ViewBuilder
    private var content: some View {
        if let title = item.title {
            Text(title)
                // One weight in every state (pass 9, Steven: the bar shifted while moving in it —
                // a bolder focused or selected label is wider and pushed its neighbours).
                .font(.system(size: OrbitBarMetrics.fontSize, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, OrbitBarMetrics.textPadding)
        } else if let image = item.systemImage {
            Image(systemName: image)
                .font(.system(size: OrbitBarMetrics.glyphSize, weight: .medium))
        }
    }
}

/// No system focus treatment (the label draws its own), a small press dip.
private struct OrbitBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}


// MARK: - Services / Studios grid

/// Steven's fork (Orbit bar): the Services and Studios pages lay their collections' folders out on
/// a grid, like the tvOS home screen's apps, under the bar and over the stage art (which follows
/// the focused folder). Each tile opens the folder page, exactly as from a collection row.
struct OrbitCollectionGrid: View {
    let collections: [NuvioCollection]
    /// The focused folder (nil when focus leaves the grid), for the stage.
    let onFolderFocus: (NuvioCollection, CollectionFolder?) -> Void
    /// Bumped by Home on the pop of a folder pushed from the grid (`StageCover.pushed` going false),
    /// in case the grid stayed mounted under the push and never re-appeared.
    var restoreGeneration = 0

    private struct Entry: Identifiable {
        let collection: NuvioCollection
        let folder: CollectionFolder
        var id: String { "\(collection.id)/\(folder.id)" }
    }

    @FocusState private var focused: String?
    @State private var restoreTarget: String?
    /// Device pass (Steven): back from a folder, focus returns to the tile it was opened from
    /// (it reset to the first one). Static, so it survives the grid being rebuilt on the pop.
    @MainActor private static var lastFocused: String?
    @MainActor private static var leftWithFocus = false
    @MainActor private static var lostAt: TimeInterval = 0
    @MainActor private static var appearedAt: TimeInterval = 0
    /// Pass 4 (Steven: always back on Netflix): the tile the folder was opened from, kept at the
    /// push. `lastFocused` itself is overwritten by the engine's own landing on the first tile,
    /// which happens BEFORE the grid's `onAppear` on the pop.
    @MainActor private static var pushedFrom: String?

    /// Home, on the push edge while the grid is shown.
    static func notePush() {
        if let lastFocused { pushedFrom = lastFocused }
    }

    private var entries: [Entry] {
        var seen = Set<String>()
        var out: [Entry] = []
        for collection in collections {
            for folder in collection.folders {
                let entry = Entry(collection: collection, folder: folder)
                if seen.insert(entry.id).inserted { out.append(entry) }
            }
        }
        return out
    }

    static let columnMinimum: CGFloat = 400
    static let spacing: CGFloat = 40
    static let top: CGFloat = 170

    var body: some View {
        let entries = entries
        ScrollView(.vertical) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.columnMinimum), spacing: Self.spacing, alignment: .top)],
                      alignment: .leading, spacing: Self.spacing + 12) {
                ForEach(entries) { entry in
                    NavigationLink(value: FolderRoute(collectionId: entry.collection.id, folder: entry.folder)) {
                        FolderTile(folder: entry.folder,
                                   collectionBackdropUrl: entry.collection.backdropImageUrl,
                                   collectionId: entry.collection.id,
                                   stillFocused: focused == entry.id)
                    }
                    .cardFocusButtonStyle()
                    .posterButtonShape()
                    .focused($focused, equals: entry.id)
                    .id(entry.id)
                }
            }
            .padding(.top, Self.top)
            .padding(.horizontal, StripGeometry.edgeMargin)
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .focusSection()
        // Steven: the Poster Size setting does not apply here — the platform tiles keep the size
        // they were laid out for (the default style), whatever Small / Large says.
        .environment(\.posterStyle, .default)
        // The engine's own entry into the grid after the pop picks the tile too.
        .defaultFocus($focused, restoreTarget, priority: .userInitiated)
        .onChange(of: focused) { _, id in
            guard let id, let entry = entries.first(where: { $0.id == id }) else {
                Self.lostAt = ProcessInfo.processInfo.systemUptime
                return
            }
            Self.lastFocused = id
            onFolderFocus(entry.collection, entry.folder)
        }
        // Only a return from a folder (the grid had focus when it went away), never an arrival
        // from the bar, which keeps focus where the viewer is.
        .onAppear {
            guard Self.leftWithFocus else { return }
            Self.leftWithFocus = false
            restoreFocus()
        }
        .onChange(of: restoreGeneration) { _, _ in restoreFocus() }
        // Device pass (still back on the first tile): the push takes focus off the tile before the
        // grid disappears, so `focused` was already nil here. A loss just before counts.
        .onDisappear {
            let now = ProcessInfo.processInfo.systemUptime
            Self.leftWithFocus = focused != nil || now - Self.lostAt < 1.0
            if Self.leftWithFocus { Self.notePush() }
        }
    }

    private func restoreFocus() {
        guard let last = Self.pushedFrom ?? Self.lastFocused,
              entries.contains(where: { $0.id == last }) else { return }
        do {
            let appeared = ProcessInfo.processInfo.systemUptime
            Self.appearedAt = appeared
            restoreTarget = last
            // Pass 3 (Steven's video: still the first tile): the engine's own restoration lands
            // late, after the first asks. Ask again over the first second and a half, until the
            // viewer presses anything.
            for delay in [0.0, 0.15, 0.35, 0.6, 0.9, 1.3] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard !ViewerInputClock.shared.hasInput(since: appeared), focused != last else { return }
                    focused = last
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                restoreTarget = nil
                Self.pushedFrom = nil
            }
        }
    }
}

// MARK: - Collection bar

/// Steven's fork (collection bar): the folder page's own bar, in the Orbit bar's style and place —
/// Search, Films, Séries. Films / Séries keep only that type's rows (selecting the lit one again
/// shows every row); Search opens `CollectionSearchLayer` over the page.
struct CollectionFilterBar: View {
    @Binding var filter: String?
    /// Pass 2 (Steven): top-right, just left of the folder logo; `trailing` is its gap to the
    /// screen's right edge (the logo's corner margin plus the logo's own room).
    var trailing: CGFloat = 0
    /// The pill's width, for the logo to make room for it.
    var onWidth: (CGFloat) -> Void = { _ in }
    let onSearch: () -> Void

    @FocusState private var focused: OrbitBarItem?
    @State private var placedEntryFocus = false
    @State private var searchReady = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach([OrbitBarItem.search, .films, .series], id: \.self) { item in
                Button { select(item) } label: {
                    OrbitBarItemLabel(item: item, selected: isSelected(item), focused: focused == item)
                }
                .buttonStyle(OrbitBarButtonStyle())
                .focused($focused, equals: item)
                // Steven: Search flashed before Films on entry; out of reach until Films has focus.
                .disabled(item == .search && !searchReady)
                .accessibilityLabel(item.accessibilityName)
            }
        }
        .padding(OrbitBarMetrics.pillPadding)
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.10)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onWidth($0) }
        // Steven: entering a collection puts the cursor on Films (Séries for a series-only one).
        // Once: a pop back from Detail keeps its own restore.
        // Steven: the engine's first pick (Search, top-left) flashed before Films.
        .defaultFocus($focused, isSelected(.series) && !isSelected(.films) ? .series : .films, priority: .userInitiated)
        .onAppear {
            guard !placedEntryFocus else { return }
            placedEntryFocus = true
            focused = isSelected(.series) && !isSelected(.films) ? .series : .films
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { searchReady = true }
            OrbitBarLaunchFocus.place {
                let target: OrbitBarItem = isSelected(.series) && !isSelected(.films) ? .series : .films
                if focused != target { focused = target }
            }
        }
        // Pass 3 (Steven: Up never reached it): the focus section spans the screen's width in the
        // bar's band, so Up from any card of the top row finds the bar (the engine only searches
        // straight up, and the pill sits at the far right).
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .padding(.top, OrbitBarMetrics.top)
        // Pass 5 (Steven, device): back at the top-left, like Home's bar.
        .padding(.leading, OrbitBarMetrics.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }

    private func type(of item: OrbitBarItem) -> String? {
        switch item {
        case .films: return "movie"
        case .series: return "series"
        default: return nil
        }
    }

    private func isSelected(_ item: OrbitBarItem) -> Bool {
        guard let type = type(of: item) else { return false }
        return filter == type
    }

    private func select(_ item: OrbitBarItem) {
        guard let type = type(of: item) else { onSearch(); return }
        filter = type
    }
}

/// Steven's fork (collection bar): which folder rows a type filter keeps. "series" also keeps any
/// non-movie type (tv, anime…), like Home's Séries.
enum CollectionTypeFilter {
    static func keeps(_ contentType: String?, filter: String?) -> Bool {
        guard let filter else { return true }
        guard let contentType else { return false }
        return filter == "movie" ? contentType == "movie" : contentType != "movie"
    }

    /// Pass 2 (Steven: a series catalog showed under Films): the catalog's own name wins over its
    /// declared type ("Nouvelles séries" is a series row even when its add-on declares "movie").
    static func effectiveType(declared: String?, name: String) -> String? {
        let n = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if n.contains("serie") || n.contains("show") || n.contains("anime") { return "series" }
        if n.contains("film") || n.contains("movie") { return "movie" }
        return declared
    }

    static func rows(_ rows: [FolderStripRow], filter: String?) -> [FolderStripRow] {
        guard filter != nil else { return rows }
        return rows.filter { keeps(effectiveType(declared: $0.contentType, name: $0.heading), filter: filter) }
    }
}

/// Steven: the cursor starts on the page's Films (or Séries) item of a bar, not on the first card.
/// Asked several times over the first seconds (the strip's own first focus lands late), until the
/// viewer presses anything.
@MainActor
enum OrbitBarLaunchFocus {
    static func place(_ apply: @escaping () -> Void) {
        let start = ProcessInfo.processInfo.systemUptime
        for delay in [0.05, 0.3, 0.7, 1.2, 2.0, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !ViewerInputClock.shared.hasInput(since: start) else { return }
                apply()
            }
        }
    }
}
