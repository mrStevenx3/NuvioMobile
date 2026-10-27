import Combine
import SharedCore
import SwiftUI

// Orbit Discover (Steven's fork, 2026-10-23): the Discover tab's grid rebuilt on Orbit Home's
// principle. The focus engine scrolled the old grid in big jumps ("le défilement qui se fait en
// grand"); here nothing is scrolled by it. The header (title and the Type / Genre / Catalog pills)
// stays fixed under the bar; the grid is ONE focusable stop that takes the presses itself and is
// drawn rather than scrolled:
//  - Left / Right move the selection inside the line;
//  - Down / Up move one line, and the whole grid glides one line on one curve, the selected line
//    resting on the grid's second line (the first one stays in view above it, like the reference);
//  - Select opens the title; Up from the first line goes to the pills.
// Only the lines near the selection exist. The model (`DiscoverGridViewModel`) is unchanged.

enum OrbitDiscoverLayout {
    static let columns = 6
    static let gap: CGFloat = 24
    static let lineGap: CGFloat = 46
    static var tileWidth: CGFloat {
        floor((OrbitHomeLayout.screenWidth - 2 * OrbitHomeLayout.margin - CGFloat(columns - 1) * gap) / CGFloat(columns))
    }
    static var tileHeight: CGFloat { floor(tileWidth * 9 / 16) }
    static var pitch: CGFloat { tileHeight + lineGap }
    /// The header's top (under the bar) and the grid's first line.
    static let headerTop: CGFloat = 116
    static let gridTop: CGFloat = 236
}

struct OrbitDiscoverPage: View {
    @ObservedObject var model: DiscoverGridViewModel
    let onOpen: (MetaPreview) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var canvasFocused: Bool
    @State private var index = 0
    /// Native grid (Steven, 2026-10-26: as fluid as Home): real buttons in a grid the system
    /// scrolls (Settings ▸ Nouvel accueil off brings the drawn grid back).

    private var items: [MetaPreview] { model.items }
    private var line: Int { index / OrbitDiscoverLayout.columns }

    var body: some View {
                    OrbitNativeDiscover(model: model, onOpen: onOpen, header: { header })
        
    }

    // MARK: Input

    // MARK: Header

    var header: some View {
        HStack(spacing: 18) {
            Text(headerTitle)
                .font(.system(size: 46, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, 12)
            if let type = model.selectedType {
                PillMenu(title: DiscoverRowsPlan.typeLabel(type),
                         systemImage: "film.stack",
                         selection: Binding(get: { type }, set: { model.select(type: $0) }),
                         options: model.typeOptions,
                         id: "discover.typePicker",
                         pickerTitle: String(localized: "Type"),
                         label: { DiscoverRowsPlan.typeLabel($0) })
            }
            if let option = model.selectedOption, let genres = DiscoverGridPlan.genreChoices(option) {
                let current = DiscoverGridPlan.pillValue(model.selectedGenre)
                let labels = DiscoverGridPlan.genreLabels(genres)
                PillMenu(title: labels[current] ?? DiscoverGridPlan.genreLabel(current),
                         systemImage: "theatermasks",
                         selection: Binding(get: { current }, set: { model.select(genrePill: $0) }),
                         options: genres,
                         id: "discover.genrePicker",
                         pickerTitle: String(localized: "Genre"),
                         label: { labels[$0] ?? DiscoverGridPlan.genreLabel($0) })
            }
            if let type = model.selectedType, let selected = model.selectedOption {
                let catalogs = model.catalogOptions(for: type)
                if catalogs.count > 1 {
                    PillMenu(title: DiscoverRowsPlan.catalogLabel(selected, among: catalogs),
                             systemImage: "square.stack",
                             selection: Binding(get: { selected.key }, set: { model.select(catalogKey: $0) }),
                             options: catalogs.map(\.key),
                             id: "discover.catalogPicker",
                             pickerTitle: String(localized: "Catalog"),
                             label: { key in
                                 catalogs.first { $0.key == key }
                                     .map { DiscoverRowsPlan.catalogLabel($0, among: catalogs) } ?? key
                             })
                }
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth - 2 * OrbitHomeLayout.margin, alignment: .leading)
        .focusSection()
    }

    private var headerTitle: String {
        if let option = model.selectedOption, let genres = DiscoverGridPlan.genreChoices(option), model.selectedGenre != nil {
            let current = DiscoverGridPlan.pillValue(model.selectedGenre)
            return DiscoverGridPlan.genreLabels(genres)[current] ?? DiscoverGridPlan.genreLabel(current)
        }
        return model.selectedType.map { DiscoverRowsPlan.typeLabel($0) } ?? String(localized: "Découvrir")
    }

    @ViewBuilder
    private var statusPanel: some View {
        switch model.phase {
        case .failed:
            HStack(spacing: 24) {
                Text("Impossible de charger Découvrir.")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                Button("Réessayer") { model.retry() }
            }
        case .empty:
            if !model.isLoadingMore {
                Text("Rien ici pour l'instant.")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        default:
            // Loading: the grid's skeleton, so the page never opens on an empty screen.
            OrbitDiscoverSkeleton()
        }
    }
}

/// While the first page loads: two lines of dim tiles in the grid's own places.
private struct OrbitDiscoverSkeleton: View {
    var body: some View {
        let D = OrbitDiscoverLayout.self
        VStack(alignment: .leading, spacing: D.lineGap) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: D.gap) {
                    ForEach(0..<D.columns, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: D.tileWidth, height: D.tileHeight)
                    }
                }
            }
        }
    }
}

/// One title: its landscape art with the logo (or name), the white frame when selected.
struct OrbitDiscoverTile: View {
    let item: MetaPreview
    let focused: Bool

    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        let D = OrbitDiscoverLayout.self
        let size = CGSize(width: D.tileWidth, height: D.tileHeight)
        let info = OrbitInfo.make(item, meta: metaStore.meta(for: item))
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.1)
            // The catalog's landscape art, else TMDB's backdrop, else the poster (a dead link no
            // longer leaves the tile with its title alone).
            let landscape = InlineTrailerCard.landscapeArtworkURL(item)
            let backdrop = metaStore.meta(for: item)?.backdrop
            OrbitImage(url: landscape ?? backdrop,
                       fallback: landscape != nil && backdrop != landscape ? backdrop : item.poster,
                       size: size, placeholder: item.poster, lastResort: item.poster)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            OrbitTitleMark(name: item.name, logo: info.logo,
                           maxSize: CGSize(width: size.width * 0.7, height: size.height * 0.32), textSize: 22,
                           fallbackLogo: info.logoFallback)
                .padding(.leading, 12)
                .padding(.bottom, 10)
            // Where it can be watched, as on Home.
            if let kind = OrbitPlatformBadgeKind.of(metaStore.meta(for: item)) {
                OrbitPlatformBadge(kind: kind, size: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 4)
        }
        .scaleEffect(focused ? 1.08 : 1)
        .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: 18, y: 10)
        // Steven: every tile shows its logo, not only the focused one (looked up once per title).
        .onAppear { metaStore.request([item]) }
    }
}

/// Discover's grid, native: real buttons in a lazy grid the system scrolls, the selected title's
/// colour behind the page (only the two tiles whose focus changed redraw on a press).
private struct OrbitNativeDiscover<Header: View>: View {
    @ObservedObject var model: DiscoverGridViewModel
    let onOpen: (MetaPreview) -> Void
    @ViewBuilder let header: () -> Header

    @FocusState private var focused: Int?
    @State private var shown: Int?
    @State private var scrolled = false
    /// The tile a title was opened from: back from it, the focus goes there, and only there a
    /// moment (the system's own landing elsewhere is sent back — as on Home and the title page).
    @State private var restoringSince: TimeInterval = 0
    @State private var page = ScrollPosition(edge: .top)

    var body: some View {
        let D = OrbitDiscoverLayout.self
        let L = OrbitHomeLayout.self
        let items = model.items
        let columns = Array(repeating: GridItem(.fixed(D.tileWidth), spacing: D.gap, alignment: .top), count: D.columns)
        ZStack(alignment: .topLeading) {
            L.background.ignoresSafeArea()
            OrbitNativeDiscoverBackdrop(item: shown.flatMap { items.indices.contains($0) ? items[$0] : nil })

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 34) {
                        header()
                            .id("header")
                        if model.selectedType == nil || model.phase != .loaded {
                            status
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: D.lineGap) {
                            ForEach(items.indices, id: \.self) { i in
                                Button {
                                    OrbitDiscoverReturn.opened = i
                                    onOpen(items[i])
                                } label: {
                                    OrbitNativeDiscoverTile(item: items[i])
                                }
                                .buttonStyle(OrbitPlainStyle())
                                .focused($focused, equals: i)
                                // The focused tile above its neighbours (it grows over them).
                                .zIndex(focused == i ? 1 : 0)
                                .id(i)
                                .onAppear { model.itemAppeared(at: i) }
                            }
                        }
                        .focusSection()
                        .defaultFocus($focused, OrbitDiscoverReturn.opened, priority: .userInitiated)
                    }
                    .padding(.horizontal, L.margin)
                    .padding(.top, D.headerTop)
                    .padding(.bottom, 200)
                }
                .scrollClipDisabled()
                // Where the page is scrolled, kept, and put back on the way back from a title (the
                // system's own landing elsewhere scrolled it — Steven: the grid rose).
                .scrollPosition($page)
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, y in
                    if restoringSince == 0, OrbitDiscoverReturn.opened == nil { OrbitDiscoverReturn.offsetY = y }
                }
                .onChange(of: model.gridKey) { _, _ in
                    OrbitDiscoverReturn.opened = nil
                    focused = nil
                    shown = nil
                    proxy.scrollTo("header", anchor: .top)
                }
            }
        }
        .frame(width: L.screenWidth, height: L.screenHeight, alignment: .topLeading)
        .ignoresSafeArea()
        // Menu: from the grid, back to its top (the pills); there, to the bar.
        .onExitCommand(perform: focused == nil ? { NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil) }
                                                : { focused = nil; NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil) })
        .background { ViewerInputClockInstaller().frame(width: 0, height: 0) }
        .onAppear {
            guard let back = OrbitDiscoverReturn.opened, model.items.indices.contains(back) else { return }
            let start = ProcessInfo.processInfo.systemUptime
            restoringSince = start
            for delay in [0.0, 0.15, 0.35, 0.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard OrbitDiscoverReturn.opened == back, !ViewerInputClock.shared.hasInput(since: start + 0.3) else { return }
                    if focused != back { focused = back }
                    keepPage()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                restoringSince = 0
                if OrbitDiscoverReturn.opened == back { OrbitDiscoverReturn.opened = nil }
            }
        }
        .onChange(of: focused) { _, new in
            if let new, let back = OrbitDiscoverReturn.opened, restoringSince > 0,
               !ViewerInputClock.shared.hasInput(since: restoringSince + 0.3) {
                if new != back {
                    DispatchQueue.main.async { focused = back; keepPage() }
                    return
                }
                keepPage()
            }
            if let new {
                shown = new
                model.itemAppeared(at: min(model.items.count - 1, new + D.columns * 3))
            }
            let down = (new ?? 0) >= D.columns
            if scrolled != down {
                scrolled = down
                OrbitBarLock.shared.set(down)
            }
        }
        .onDisappear { OrbitBarLock.shared.set(false) }
    }

    /// The page exactly where it was when the title was opened.
    private func keepPage() {
        guard let y = OrbitDiscoverReturn.offsetY else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { page.scrollTo(y: y) }
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .failed:
            HStack(spacing: 24) {
                Text("Impossible de charger Découvrir.")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                Button("Réessayer") { model.retry() }
            }
        case .empty:
            if !model.isLoadingMore {
                Text("Rien ici pour l'instant.")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        default:
            OrbitDiscoverSkeleton()
        }
    }
}

/// The colour behind Discover (its own view: a new colour redraws only it).
private struct OrbitNativeDiscoverBackdrop: View {
    let item: MetaPreview?

    var body: some View {
        OrbitFocusBackdrop(item: item)
            .ignoresSafeArea()
    }
}

/// One Discover tile, focused as its button is.
private struct OrbitNativeDiscoverTile: View {
    let item: MetaPreview
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        OrbitDiscoverTile(item: item, focused: isFocused)
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}



/// Where the last title was opened from (a generic view cannot hold a static).
@MainActor
enum OrbitDiscoverReturn {
    static var opened: Int?
    static var offsetY: CGFloat?
}
