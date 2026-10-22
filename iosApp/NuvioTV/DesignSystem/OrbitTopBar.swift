import Combine
import SwiftUI
import SharedCore

// Steven's fork (Orbit top bar): the navigation chrome that replaces the system tab bar and the
// rail when Settings › Appearance › Navigation is "Orbit Bar" (the default in this fork). A row of
// glass pills pinned to the screen's top-left corner, in three groups split by thin vertical rules:
//
//     [ 🔍  Films  Séries  📚  🧭 ]  |  [ Services  Studios ]  |  [ ⚙︎ ]
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
    static let top: CGFloat = 38
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
    @FocusState private var focused: OrbitBarItem?
    @State private var immersive = false
    /// Pass 4: the launch focus (the engine's pick, the top-left Search glyph) is moved once onto
    /// the current page's item (Films at launch).
    @State private var placedLaunchFocus = false
    /// Pass 7: the Plateformes / Studios entry transition (`OrbitSpaceTransition`), one per entry.
    @State private var transition: (id: Int, style: OrbitSpaceTransition.Style, origin: CGPoint)?
    @State private var itemCentres: [OrbitBarItem: CGPoint] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: OrbitBarMetrics.groupGap) {
            pill([.search, .films, .series, .library, .discover])
            rule
            pill([.services, .studios])
            rule
            pill([.settings])
        }
        // The focus section hugs the bar itself (device pass 1: drawn over the whole screen, it
        // kept Down from reaching Settings' list).
        .focusSection()
        // Pass 3: Up into the bar lands on the current page's item (Discover from Discover…).
        .defaultFocus($focused, currentItem, priority: .userInitiated)
        .padding(.top, OrbitBarMetrics.top)
        .padding(.leading, OrbitBarMetrics.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .overlay {
            if let transition {
                OrbitSpaceTransition(style: transition.style, origin: transition.origin) {
                    if self.transition?.id == transition.id { self.transition = nil }
                }
                .id(transition.id)
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
            HiddenTabBarFocusBlocker(onFocusLandedInHiddenBar: {
                DispatchQueue.main.async { focused = currentItem }
            })
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        .onChange(of: focused) { _, item in
            guard !placedLaunchFocus, let item else { return }
            placedLaunchFocus = true
            if item != currentItem {
                DispatchQueue.main.async { focused = currentItem }
            }
        }
    }

    private func pill(_ items: [OrbitBarItem]) -> some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                Button { select(item) } label: {
                    OrbitBarItemLabel(item: item, selected: isSelected(item), focused: focused == item)
                }
                .buttonStyle(OrbitBarButtonStyle())
                .focused($focused, equals: item)
                .onGeometryChange(for: CGPoint.self) { proxy in
                    let frame = proxy.frame(in: .global)
                    return CGPoint(x: frame.midX, y: frame.midY)
                } action: { centre in
                    itemCentres[item] = centre
                }
                .accessibilityLabel(item.accessibilityName)
                .accessibilityIdentifier("orbit_bar_\(item)")
            }
        }
        .padding(OrbitBarMetrics.pillPadding)
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
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
        let spaces: Set<HomeContentFilter> = [.services, .studios]
        if let filter = item.homeFilter, spaces.contains(filter),
           !(selectedTab == 0 && spaces.contains(homeFilter.filter)) {
            let style = OrbitSpaceTransition.currentStyle
            if style != .off, !reduceMotion {
                transition = ((transition?.id ?? 0) + 1, style, itemCentres[item] ?? CGPoint(x: 400, y: 80))
            }
        }
        if let filter = item.homeFilter {
            homeFilter.set(filter)
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
                .font(.system(size: OrbitBarMetrics.fontSize, weight: selected || focused ? .semibold : .medium))
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

    private struct Entry: Identifiable {
        let collection: NuvioCollection
        let folder: CollectionFolder
        var id: String { "\(collection.id)/\(folder.id)" }
    }

    @FocusState private var focused: String?

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
        .onChange(of: focused) { _, id in
            guard let id, let entry = entries.first(where: { $0.id == id }) else { return }
            onFolderFocus(entry.collection, entry.folder)
        }
    }
}
