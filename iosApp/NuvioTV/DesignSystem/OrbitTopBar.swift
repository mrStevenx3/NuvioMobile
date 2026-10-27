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
    @Published var filter: HomeContentFilter = .movies

    func set(_ next: HomeContentFilter) {
        if filter != next { filter = next }
    }
}

// MARK: - Items

private enum OrbitBarItem: Hashable, CaseIterable {
    case search, films, series, library, discover, services, studios, settings, profile
    /// Collections' bar only: back to Home in one press (Steven, 2026-10-25).
    case home
    /// Collections' bar only (Prime Video): films and series together.
    case everything
    /// HBO Max's bar only: HBO's own programmes (filter "hbo").
    case hbo

    var title: String? {
        switch self {
        case .films: return String(localized: "Films")
        case .series: return String(localized: "Séries")
        case .everything: return String(localized: "Accueil")
        case .hbo: return "HBO"
        case .services: return String(localized: "Plateformes")
        case .studios: return String(localized: "Studios")
        default: return nil
        }
    }

    var systemImage: String? {
        switch self {
        case .search: return "magnifyingglass"
        case .home: return "house"
        case .library: return "books.vertical"
        case .discover: return "safari"
        case .settings: return "gearshape"
        default: return nil
        }
    }

    var accessibilityName: String {
        switch self {
        case .search: return String(localized: "Search")
        case .home: return String(localized: "Accueil")
        case .library: return String(localized: "Library")
        case .discover: return String(localized: "Discover")
        case .settings: return String(localized: "Settings")
        case .profile: return String(localized: "Profil")
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
    /// Steven (2026-10-24): the profile's avatar at the end of the bar opens its page.
    var activeProfile: NuvioProfile? = nil

    @ObservedObject private var homeFilter = HomeContentFilterModel.shared
    @ObservedObject private var barLock = OrbitBarLock.shared
    @FocusState private var focused: OrbitBarItem?
    @State private var immersive = false
    /// Pass 4: the launch focus (the engine's pick, the top-left Search glyph) is moved once onto
    /// the current page's item (Films at launch).
    @State private var placedLaunchFocus = false
    @State private var searchReady = false
    @State private var autoSelectGeneration = 0
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
            pill([[.settings, .profile]])
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
        .onReceive(NotificationCenter.default.publisher(for: .orbitBarFocusRequest)) { _ in
            OrbitBarLock.shared.set(false)
            DispatchQueue.main.async { focused = currentItem }
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
            // Steven (2026-10-23): Films, Séries, Plateformes and Studios open on focus, like the
            // Apple TV's own tab bar — after a short rest, so passing over one opens nothing.
            autoSelectGeneration &+= 1
            if let item, item.homeFilter != nil, placedLaunchFocus, !isSelected(item) {
                let generation = autoSelectGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    guard generation == autoSelectGeneration, focused == item, !isSelected(item) else { return }
                    select(item)
                }
            }
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
                    OrbitBarItemLabel(item: item, selected: isSelected(item), focused: focused == item,
                                      profile: activeProfile)
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
        case .profile: return selectedTab == 5
        default: return false
        }
    }

    private func select(_ item: OrbitBarItem) {
        // Pass 7/8: the portal plays entering Plateformes / Studios from any other page, and leaving
        // them for Search, Films, Séries, Library or Discover (not Settings, not between the two).
        let spaces: Set<HomeContentFilter> = [.services, .studios]
        let inSpace = selectedTab == 0 && spaces.contains(homeFilter.filter)
        let toSpace = item.homeFilter.map(spaces.contains) ?? false
        // Steven (2026-10-23): the portal is gone (it cost fluidity for nothing).
        _ = inSpace
        _ = toSpace
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
        case .profile: selectedTab = 5
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
    var profile: NuvioProfile? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if item == .profile {
            avatar
        } else {
            plain
        }
    }

    /// The profile: its avatar in a ring (white when focused, light when its page is open).
    private var avatar: some View {
        Group {
            if let profile {
                OrbitAvatar(profile: profile, size: OrbitBarMetrics.itemHeight - 10)
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: OrbitBarMetrics.glyphSize, weight: .medium))
                    .foregroundStyle(Color.white)
                    .frame(width: OrbitBarMetrics.itemHeight - 10, height: OrbitBarMetrics.itemHeight - 10)
            }
        }
        .padding(5)
        .overlay(Circle().strokeBorder(Color.white.opacity(focused ? 1 : (selected ? 0.5 : 0)), lineWidth: 3))
        .frame(width: OrbitBarMetrics.itemHeight, height: OrbitBarMetrics.itemHeight)
        .scaleEffect(focused && !reduceMotion ? OrbitBarMetrics.focusScale : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: focused)
    }

    private var plain: some View {
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
        if item == .hbo {
            // Steven: HBO Max's tab shows the real HBO mark, not a word (black when focused).
            Image("HBOMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: OrbitBarMetrics.fontSize * 0.9)
                .padding(.horizontal, OrbitBarMetrics.textPadding)
        } else if let title = item.title {
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

    // Steven (2026-10-23): the Plateformes page in Orbit's layout — a "Plateformes" heading under
    // the bar, then four large 16:9 tiles a line across the screen at Orbit's margin, the focus
    // drawn Orbit's way (white frame, slight lift), on black with a soft halo in the focused
    // platform's colour.
    // Steven (trending row): the platforms on ONE line (Down from a platform goes straight to its
    // trending row; on two lines Down from Netflix landed on HBO Max and the row switched to it).
    // Six fit across the screen; more scroll sideways.
    /// Steven: larger platforms (they melted into the rest) — four across, the others scroll.
    /// (Steven: larger than the Top 20's posters under them — three across.)
    static let columns = 3
    static let spacing: CGFloat = 28
    /// The tiles, under the bar (the page's title is gone).
    /// (Steven: the page balanced — the platforms a little lower, the larger Top 20 under them.)
    static let top: CGFloat = 165
    static var tileWidth: CGFloat {
        floor((OrbitHomeLayout.screenWidth - 2 * OrbitHomeLayout.margin - CGFloat(columns - 1) * spacing) / CGFloat(columns))
    }
    static var tileHeight: CGFloat { floor(tileWidth * 9 / 16) }

    /// The focused platform's colour (the halo), nil for a grey cover.
    @State private var haloColor: Color?
    /// The platform whose Top 20 is shown (marked while the focus is in its rows).
    @State private var selectedId: String?
    @Environment(\.orbitPushFolder) private var pushFolder
    /// The focus is down in the Top 20 (Steven: up on the bar, the platform stayed marked).
    @State private var inRows = false
    /// Where the page is brought to: the focused row's line, or its top on the platforms.
    @State private var scrollLine: String?

    var body: some View {
        let entries = entries
        ZStack(alignment: .topLeading) {
            OrbitHomeLayout.background.ignoresSafeArea()
            // (Steven, device: no title art behind the platforms — only their colour, the halo.)
            // The halo: the focused platform's colour, soft, from the top left.
            if let haloColor {
                RadialGradient(colors: [haloColor.opacity(0.55), haloColor.opacity(0.18), .clear],
                               center: UnitPoint(x: 0.22, y: 0.18), startRadius: 0, endRadius: 1250)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .id(haloColor.description)
                    .allowsHitTesting(false)
            }
            // Steven (2026-10-24): no "Plateformes" title — the bar already says it, and the
            // Studios page has none.
            ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Self.spacing) {
                    Color.clear.frame(height: 0).id("grid-top")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Self.spacing) {
                            ForEach(entries) { entry in
                                // Steven: the platform's opening before its page — black first, the
                                // page pushed under it (see `OrbitPlatformCurtain`).
                                Button {
                                    let route = FolderRoute(collectionId: entry.collection.id, folder: entry.folder)
                                    if let pushFolder {
                                        OrbitPlatformCurtain.shared.drop(look: OrbitPlatformLook.of(route)) { pushFolder(route) }
                                    }
                                } label: {
                                    OrbitPlatformTile(folder: entry.folder,
                                                      collectionBackdropUrl: entry.collection.backdropImageUrl,
                                                      focused: focused == entry.id,
                                                      // Steven: the platform whose Top 20 shows stays
                                                      // marked when the focus is down in it.
                                                      selected: inRows && selectedId == entry.id,
                                                      tint: haloColor,
                                                      size: CGSize(width: Self.tileWidth, height: Self.tileHeight))
                                }
                                .buttonStyle(OrbitPlatformTileStyle())
                                .focused($focused, equals: entry.id)
                                // Back from a platform, only its tile can take the focus a moment
                                // (Steven, simulator: it went to another platform first).
                                .disabled(restoreTarget != nil && restoreTarget != entry.id)
                                .id(entry.id)
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.trailing, OrbitHomeLayout.margin)
                    }
                    .scrollClipDisabled()
                    .padding(.vertical, -16)
                    .focusSection()
                    // Steven (on trial): what is popular on the focused platform.
                    // Steven (device: the page scrolled on its own, the Top 10 cut at the top): it
                    // moves a row at a time — the focused row at its line, the platforms at the top.
                    // Steven: everything on one screen — the page no longer moves row by row.
                    OrbitPlatformTrendingRow(onRowFocus: { inRows = $0 != nil }, accent: haloColor)
                        // (Back from a platform: the rows below cannot take the focus either — Steven,
                        // simulator: it landed in the Top 20, then went back to the platform.)
                        .disabled(restoreTarget != nil)
                        .padding(.top, 30)
                }
                .padding(.top, Self.top)
                .padding(.horizontal, OrbitHomeLayout.margin)
                .padding(.bottom, 80)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollClipDisabled()
            .scrollDisabled(true)
            .focusSection()
            .onChange(of: scrollLine) { _, line in
                guard let line else { return }
                withAnimation(.easeInOut(duration: 0.36)) { proxy.scrollTo(line, anchor: .top) }
            }
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: haloColor?.description)
        // The engine's own entry into the grid after the pop picks the tile too.
        .defaultFocus($focused, restoreTarget, priority: .userInitiated)
        .onChange(of: focused) { old, id in
            guard let id, let entry = entries.first(where: { $0.id == id }) else {
                Self.lostAt = ProcessInfo.processInfo.systemUptime
                return
            }
            // Back from a title of the rows below: the system's landing on a tile is passing (the
            // rows take the focus back) — the rows must not switch platform under it.
            if OrbitPlatformTrendingRow.restorePending { return }
            // Steven: coming down from the bar, the focus goes to the first platform (far left),
            // not the one under the bar's button. Not on a return from a folder, nor coming back
            // up from the trending row.
            if old == nil, restoreTarget == nil,
               ProcessInfo.processInfo.systemUptime - OrbitPlatformTrendingRow.lostAt > 0.6,
               let first = entries.first, id != first.id {
                focused = first.id
                return
            }
            Self.lastFocused = id
            selectedId = id
            scrollLine = "grid-top"
            onFolderFocus(entry.collection, entry.folder)
            updateHalo(entry)
            OrbitPlatformTrendingModel.shared.focus(title: entry.folder.title)
        }
        // Only a return from a folder (the grid had focus when it went away), never an arrival
        // from the bar, which keeps focus where the viewer is.
        .onAppear {
            if haloColor == nil, let first = entries.first(where: { $0.id == Self.lastFocused }) ?? entries.first {
                selectedId = first.id
                updateHalo(first)
                OrbitPlatformTrendingModel.shared.focus(title: first.folder.title)
            }
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
            // A title opened from the rows below: they give the focus back, not the platforms.
            OrbitPlatformTrendingRow.notePushIfFromRows()
            if OrbitPlatformTrendingRow.restorePending { Self.leftWithFocus = false; Self.pushedFrom = nil }
        }
    }

    /// Steven (device: every platform's background had gone black — their covers are animated GIFs
    /// the colour reader can't read): the known platforms' own colours, straight away.
    private static func brandColor(_ title: String) -> Color? {
        let t = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        if t.contains("netflix") { return Color(red: 0.85, green: 0.05, blue: 0.10) }
        if t.contains("disney") { return Color(red: 0.10, green: 0.30, blue: 0.95) }
        if t.contains("prime") || t.contains("amazon") { return Color(red: 0.0, green: 0.62, blue: 0.95) }
        if t.contains("hbo") || t == "max" { return Color(red: 0.45, green: 0.20, blue: 0.95) }
        if t.contains("paramount") { return Color(red: 0.05, green: 0.40, blue: 1.0) }
        if t.contains("apple") { return Color(white: 0.55) }
        if t.contains("canal") { return Color(white: 0.6) }
        return nil
    }

    private func updateHalo(_ entry: Entry) {
        if let brand = Self.brandColor(entry.folder.title) {
            // The full-screen colour follows once the remote rests (not on every step of a pass).
            let id = entry.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard focused == id || haloColor == nil else { return }
                haloColor = brand
            }
            return
        }
        let url = OrbitPlatformTile.coverURL(entry.folder, collectionBackdropUrl: entry.collection.backdropImageUrl)
        if let cached = ArtworkColorStore.shared.cachedColor(for: [url], use: .wash) {
            haloColor = cached
            return
        }
        let id = entry.id
        ArtworkColorStore.shared.color(for: [url], use: .wash) { color in
            guard focused == id || (focused == nil && Self.lastFocused == id) || haloColor == nil else { return }
            haloColor = color
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

/// One platform: its cover (the folder's own, else its backdrop, else the collection's), its
/// focus GIF while focused (revealed only once it shows something, see `StreamingGifView`), the
/// white frame and a slight lift when focused.
struct OrbitPlatformTile: View {
    let folder: CollectionFolder
    let collectionBackdropUrl: String?
    let focused: Bool
    /// The platform whose Top 20 shows, the focus elsewhere: a fine frame and its colour's glow.
    var selected = false
    var tint: Color? = nil
    let size: CGSize

    static func coverURL(_ folder: CollectionFolder, collectionBackdropUrl: String?) -> String? {
        for raw in [folder.coverImageUrl, folder.heroBackdropUrl, collectionBackdropUrl] {
            if let url = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty { return url }
        }
        return nil
    }

    var body: some View {
        let radius: CGFloat = 16
        let gif = folder.focusGifUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        ZStack {
            Color(white: 0.12)
            if let cover = Self.coverURL(folder, collectionBackdropUrl: collectionBackdropUrl) {
                CachedAsyncImage(string: cover, decodeSize: .points(width: size.width, height: size.height))
            } else {
                Text(folder.title)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .padding(20)
            }
            // (Steven: not Paramount+'s — its animation ends on a blurred reflection of its name;
            // its still cover instead.)
            if folder.focusGifEnabled, let gif, !gif.isEmpty,
               !folder.title.lowercased().contains("paramount") {
                // Fitted, not filled (Steven: Paramount+'s animation was cropped to a zoomed
                // mountain); its bars take the GIF's own edge colour.
                AnimatedGifImage(string: gif, fallback: nil, contentMode: .fit, isAnimating: focused, targetSize: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : (selected ? 0.8 : 0.08)),
                              lineWidth: focused ? 5 : (selected ? 4 : 1.5))
        }
        // (Steven: too light — a stronger glow in the platform's colour, as the Top 10's.)
        .shadow(color: (tint ?? .white).opacity(selected ? 0.9 : 0), radius: selected ? 34 : 0)
        .shadow(color: (tint ?? .white).opacity(selected ? 0.5 : 0), radius: selected ? 70 : 0)
        // Steven (device): no zoom on focus — it jumped before the GIF started. The frame says it.
        // Fluidity (Steven, device: the selection moved in jerks): only the focused tile casts a
        // shadow — six animated blurred shadows were redrawn on every step.
        .shadow(color: .black.opacity(focused ? 0.6 : 0), radius: focused ? 26 : 0, y: focused ? 14 : 0)
        .animation(.easeOut(duration: 0.16), value: focused)
        .animation(.easeOut(duration: 0.2), value: selected)
        .accessibilityLabel(folder.title)
    }
}

/// The tile draws its own focus; no system platter.
struct OrbitPlatformTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
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
    /// Films / Séries (Disney+ mixes them: none there).
    var showsTypes = true
    /// "Accueil" before Films / Séries (Prime Video): the filter nil.
    var showsAll = false
    /// "HBO" after Films / Séries (HBO Max's own tab): the filter "hbo".
    var showsHBO = false
    /// Steven (Disney+, 2026-10-25): a second pill at the screen's centre ("Disney+ · Hulu").
    var switchItems: [String] = []
    var switchSelection: Binding<Int>? = nil
    /// Steven (Disney+): each switch item drawn as its logo (`lit`: on the white focused pill).
    var switchLogo: ((_ index: Int, _ lit: Bool) -> AnyView)? = nil
    /// Steven (Disney+): Search and Accueil lead the centre pill (the house alone on the left).
    var centreLeads = false

    @FocusState private var focused: OrbitBarItem?
    @FocusState private var switchFocused: Int?
    @State private var placedEntryFocus = false
    @State private var searchReady = false
    @ObservedObject private var titleGate = OrbitTitleGate.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            leftPill
                .padding(.leading, OrbitBarMetrics.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !switchItems.isEmpty {
                centrePill
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        // Steven: back from a title, the system landed on the house before the page's restore.
        .disabled(titleGate.locked)
        // Pass 3 (Steven: Up never reached it): the focus section spans the screen's width in the
        // bar's band, so Up from any card of the top row finds the bar (the engine only searches
        // straight up, and the pill sits at the far right).
        .focusSection()
        .padding(.top, OrbitBarMetrics.top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }

    /// "Disney+ · Hulu": the selected one light, the focused one white.
    private var centrePill: some View {
        HStack(spacing: 4) {
            if centreLeads {
                barButtons(items.filter { $0 != .home })
            }
            ForEach(Array(switchItems.enumerated()), id: \.offset) { index, title in
                let selected = switchSelection?.wrappedValue == index
                let lit = switchFocused == index
                Button {
                    switchSelection?.wrappedValue = index
                } label: {
                    Group {
                        if let switchLogo {
                            switchLogo(index, lit)
                        } else {
                            Text(title)
                                .font(.system(size: OrbitBarMetrics.fontSize, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                        .padding(.horizontal, OrbitBarMetrics.textPadding + 6)
                        .foregroundStyle(lit ? Color.black : Color.white)
                        .frame(minHeight: OrbitBarMetrics.itemHeight)
                        .background {
                            Capsule(style: .continuous)
                                .fill(lit ? Color.white : Color.white.opacity(selected ? 0.24 : 0))
                        }
                        .scaleEffect(lit ? OrbitBarMetrics.focusScale : 1)
                        .animation(.easeOut(duration: 0.15), value: lit)
                }
                .buttonStyle(OrbitBarButtonStyle())
                .focused($switchFocused, equals: index)
                .accessibilityLabel(title)
            }
        }
        .padding(OrbitBarMetrics.pillPadding)
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.10)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
        // Steven: Disney+ / Hulu switch on focus, no press (after a short rest: passing over opens nothing).
        .onChange(of: switchFocused) { _, index in
            guard let index else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if switchFocused == index, switchSelection?.wrappedValue != index {
                    switchSelection?.wrappedValue = index
                }
            }
        }
    }

    /// Steven (2026-10-25): Orbit's house alone in its own pill, then the platform's own pill
    /// (Search · Accueil · Films · Séries), so the platform's "Accueil" never reads as Orbit's.
    private var leftPill: some View {
        HStack(spacing: 14) {
            pill(for: [.home])
            if !centreLeads { pill(for: items.filter { $0 != .home }) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onWidth($0) }
        // Steven: entering a collection puts the cursor on Films (Séries for a series-only one).
        // Once: a pop back from Detail keeps its own restore.
        // Steven: the engine's first pick (Search, top-left) flashed before Films.
        .defaultFocus($focused, entryItem, priority: .userInitiated)
        // Steven: Films / Séries switch on focus, no press (as Disney+ / Hulu), after a short rest.
        .onChange(of: focused) { _, item in
            guard let item, item == .everything || type(of: item) != nil else { return }
            let wanted = self.type(of: item)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if focused == item, filter != wanted { filter = wanted }
            }
        }
        .onAppear {
            guard !placedEntryFocus else { return }
            placedEntryFocus = true
            guard showsTypes else {
                // No Films / Séries: the entry lands on the centre pill's selected item.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { searchReady = true }
                // Nothing to land on without a centre pill (Apple TV): the page keeps its own focus.
                if !switchItems.isEmpty {
                    OrbitBarLaunchFocus.place { switchFocused = switchSelection?.wrappedValue ?? 0 }
                }
                return
            }
            focused = entryItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { searchReady = true }
            OrbitBarLaunchFocus.place {
                let target: OrbitBarItem = entryItem
                if focused != target { focused = target }
            }
        }
    }

    private func pill(for group: [OrbitBarItem]) -> some View {
        HStack(spacing: 4) { barButtons(group) }
        .padding(OrbitBarMetrics.pillPadding)
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.10)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
    }

    @ViewBuilder
    private func barButtons(_ group: [OrbitBarItem]) -> some View {
            ForEach(group, id: \.self) { item in
                Button { select(item) } label: {
                    OrbitBarItemLabel(item: item, selected: isSelected(item), focused: focused == item)
                }
                .buttonStyle(OrbitBarButtonStyle())
                .focused($focused, equals: item)
                // Steven: Search flashed before Films on entry; out of reach until Films has focus.
                .disabled((item == .search || item == .home) && !searchReady)
                .accessibilityLabel(item.accessibilityName)
            }
    }

    private var items: [OrbitBarItem] {
        // Steven (Disney+): "Accueil" as on Netflix, even without Films / Séries.
        guard showsTypes else { return showsAll ? [.home, .search, .everything] : [.home, .search] }
        let base: [OrbitBarItem] = showsAll ? [.home, .search, .everything, .films, .series] : [.home, .search, .films, .series]
        return showsHBO ? base + [.hbo] : base
    }

    /// Where the cursor lands on entry: the page's current tab.
    private var entryItem: OrbitBarItem {
        if showsAll, filter == nil { return .everything }
        if showsHBO, filter == "hbo" { return .hbo }
        return isSelected(.series) && !isSelected(.films) ? .series : .films
    }

    private func type(of item: OrbitBarItem) -> String? {
        switch item {
        case .films: return "movie"
        case .series: return "series"
        case .hbo: return "hbo"
        default: return nil
        }
    }

    private func isSelected(_ item: OrbitBarItem) -> Bool {
        // (Steven, Disney+: Accueil stayed lit beside the selected Disney+ / Hulu.)
        if item == .everything { return filter == nil && !centreLeads }
        guard let type = type(of: item) else { return false }
        return filter == type
    }

    private func select(_ item: OrbitBarItem) {
        if item == .home {
            NotificationCenter.default.post(name: .orbitGoHome, object: nil)
            return
        }
        if item == .everything {
            filter = nil
            return
        }
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
