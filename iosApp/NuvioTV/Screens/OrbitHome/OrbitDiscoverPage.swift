import Combine
import SharedCore
import SwiftUI
import UIKit

// Orbit Discover (Steven's fork): the Discover tab's grid of landscape tiles, six to a line, under
// its title and the Type / Genre / Catalog pills. Since 2026-10-28 the grid is a UIKit collection
// view scrolled by the focus engine, as Search's results. The model (`DiscoverGridViewModel`) is
// unchanged.

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
    /// scrolls.

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
            if let kind = OrbitPlatformBadgeKind.original(metaStore.meta(for: item)) {
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

/// Discover's grid, native. Steven (2026-10-28: "le défilement vertical est bizarre, mets le même
/// que dans Rechercher"): the grid is a UIKit collection view, as Search's results — the focus
/// engine scrolls it the way Apple's own apps do. The header (title and pills) is SwiftUI, drawn
/// over the grid's top and carried up with its scroll.
private struct OrbitNativeDiscover<Header: View>: View {
    @ObservedObject var model: DiscoverGridViewModel
    let onOpen: (MetaPreview) -> Void
    @ViewBuilder let header: () -> Header

    @StateObject private var scroll = OrbitDiscoverScroll()
    @State private var shown: Int?
    @State private var scrolled = false
    @State private var headerHeight: CGFloat = 70

    var body: some View {
        let D = OrbitDiscoverLayout.self
        let L = OrbitHomeLayout.self
        let items = model.items
        ZStack(alignment: .topLeading) {
            L.background.ignoresSafeArea()
            OrbitNativeDiscoverBackdrop(item: shown.flatMap { items.indices.contains($0) ? items[$0] : nil })

            OrbitDiscoverGrid(items: items, gridKey: model.gridKey,
                              topInset: D.headerTop + headerHeight + 34,
                              scroll: scroll,
                              onOpen: { i in
                                  guard items.indices.contains(i) else { return }
                                  OrbitDiscoverReturn.opened = i
                                  onOpen(items[i])
                              },
                              onFocus: { i in focusChanged(i) },
                              onAppear: { i in model.itemAppeared(at: i) })
                .ignoresSafeArea()

            OrbitDiscoverHeaderLayer(scroll: scroll) {
                VStack(alignment: .leading, spacing: 34) {
                    header()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                            if abs(h - headerHeight) > 0.5 { headerHeight = h }
                        }
                    if model.selectedType == nil || model.phase != .loaded {
                        status
                    }
                }
            }
            .padding(.horizontal, L.margin)
            .padding(.top, D.headerTop)
        }
        .frame(width: L.screenWidth, height: L.screenHeight, alignment: .topLeading)
        .ignoresSafeArea()
        // Menu: from the grid, back to the bar.
        .onExitCommand { NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil) }
        .onChange(of: model.gridKey) { _, _ in
            OrbitDiscoverReturn.opened = nil
            shown = nil
        }
        .onDisappear { OrbitBarLock.shared.set(false) }
    }

    private func focusChanged(_ new: Int?) {
        let D = OrbitDiscoverLayout.self
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

/// A Discover tile's cell: its SwiftUI tile in a hosting controller that ignores the TV's safe
/// area. Steven (device, twice): tiles near the screen's edges (the top lines, the last column,
/// then the bottom lines) were pushed in by it and overlapped — a hosting configuration keeps it.
final class OrbitDiscoverCell: UICollectionViewCell {
    private var host: UIHostingController<AnyView>?

    func show(_ view: AnyView) {
        if let host {
            host.rootView = view
            return
        }
        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.frame = contentView.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.insetsLayoutMarginsFromSafeArea = false
        contentView.addSubview(host.view)
        self.host = host
    }
}

/// How far the grid is scrolled (the header follows it; only the header redraws).
@MainActor
final class OrbitDiscoverScroll: ObservableObject {
    @Published var y: CGFloat = 0
}

private struct OrbitDiscoverHeaderLayer<Content: View>: View {
    @ObservedObject var scroll: OrbitDiscoverScroll
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .offset(y: -scroll.y)
            // Gone once scrolled well past it (no focus target far above the screen).
            .opacity(scroll.y > 400 ? 0 : 1)
    }
}

/// The grid itself: a collection view, as Search's results.
private struct OrbitDiscoverGrid: UIViewControllerRepresentable {
    let items: [MetaPreview]
    let gridKey: String
    let topInset: CGFloat
    let scroll: OrbitDiscoverScroll
    let onOpen: (Int) -> Void
    let onFocus: (Int?) -> Void
    let onAppear: (Int) -> Void

    func makeUIViewController(context: Context) -> OrbitDiscoverGridController {
        let controller = OrbitDiscoverGridController(scroll: scroll)
        update(controller)
        return controller
    }

    func updateUIViewController(_ controller: OrbitDiscoverGridController, context: Context) {
        update(controller)
    }

    private func update(_ controller: OrbitDiscoverGridController) {
        controller.onOpen = onOpen
        controller.onFocus = onFocus
        controller.onAppear = onAppear
        controller.show(items: items, gridKey: gridKey, topInset: topInset)
    }
}

@MainActor
final class OrbitDiscoverGridController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    var onOpen: (Int) -> Void = { _ in }
    var onFocus: (Int?) -> Void = { _ in }
    var onAppear: (Int) -> Void = { _ in }

    private let scroll: OrbitDiscoverScroll
    private var collectionView: UICollectionView!
    private var items: [MetaPreview] = []
    private var gridKey: String?
    private var topInset: CGFloat = 0
    private var cell: UICollectionView.CellRegistration<OrbitDiscoverCell, MetaPreview>!

    init(scroll: OrbitDiscoverScroll) {
        self.scroll = scroll
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: Self.layout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.insetsLayoutMarginsFromSafeArea = false
        collectionView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: 200, right: 0)
        collectionView.showsVerticalScrollIndicator = false
        // Back from a title (or down from the pills), the focus goes to the tile it left.
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        cell = UICollectionView.CellRegistration<OrbitDiscoverCell, MetaPreview> { cell, _, item in
            cell.configurationUpdateHandler = { cell, state in
                (cell as? OrbitDiscoverCell)?.show(
                    AnyView(OrbitDiscoverTile(item: item, focused: state.isFocused)
                        .animation(.easeOut(duration: 0.16), value: state.isFocused))
                )
            }
        }
        collectionView.setContentOffset(CGPoint(x: 0, y: -topInset), animated: false)
    }

    func show(items new: [MetaPreview], gridKey key: String, topInset inset: CGFloat) {
        loadViewIfNeeded()
        if abs(inset - topInset) > 0.5 {
            let atTop = collectionView.contentOffset.y <= -topInset + 1
            topInset = inset
            collectionView.contentInset.top = inset
            if atTop { collectionView.setContentOffset(CGPoint(x: 0, y: -inset), animated: false) }
        }
        if key != gridKey {
            // Another catalog or genre: a new grid, from its top.
            gridKey = key
            items = new
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            collectionView.setContentOffset(CGPoint(x: 0, y: -topInset), animated: false)
            return
        }
        guard new.count != items.count || zip(new, items).contains(where: { $0.id != $1.id }) else { return }
        let old = items
        items = new
        // The next page arrived: added at the end, the focus and the scroll untouched.
        if new.count > old.count, zip(new, old).allSatisfy({ $0.id == $1.id }) {
            let added = (old.count..<new.count).map { IndexPath(item: $0, section: 0) }
            UIView.performWithoutAnimation { collectionView.insertItems(at: added) }
        } else {
            collectionView.reloadData()
        }
    }

    // MARK: Data

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: items[indexPath.item])
    }

    // MARK: Delegate

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        onAppear(indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onOpen(indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                        with coordinator: UIFocusAnimationCoordinator) {
        // The focused tile grows over its neighbours.
        if let path = context.previouslyFocusedIndexPath { collectionView.cellForItem(at: path)?.layer.zPosition = 0 }
        if let path = context.nextFocusedIndexPath { collectionView.cellForItem(at: path)?.layer.zPosition = 1 }
        // On the first line, the grid back at its top: the title and the pills in view above it
        // (Up goes to them, then to the bar).
        if let path = context.nextFocusedIndexPath, path.item < OrbitDiscoverLayout.columns {
            let top = CGPoint(x: 0, y: -topInset)
            // (Steven: up into the first line the page jumped — now slid, as every other line.)
            DispatchQueue.main.async {
                if abs(collectionView.contentOffset.y - top.y) > 0.5 { collectionView.setContentOffset(top, animated: true) }
            }
        }
        onFocus(context.nextFocusedIndexPath?.item)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { followHeader() }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        followHeader()
    }

    /// The header rides on the grid's first line (34 pt above it), wherever the grid is.
    private func followHeader() {
        guard let collectionView else { return }
        var y: CGFloat = 0
        if items.count > 0, let first = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)) {
            let lineTop = first.frame.minY - collectionView.contentOffset.y
            y = max(0, topInset - lineTop)
        }
        if abs(scroll.y - y) > 0.5 { scroll.y = y }
    }

    private static func layout() -> UICollectionViewCompositionalLayout {
        let D = OrbitDiscoverLayout.self
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(D.tileWidth),
                                                            heightDimension: .absolute(D.tileHeight)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                         heightDimension: .absolute(D.tileHeight)),
                                                       repeatingSubitem: item, count: D.columns)
        group.interItemSpacing = .fixed(D.gap)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = D.lineGap
        section.contentInsets = .init(top: 0, leading: OrbitHomeLayout.margin, bottom: 0, trailing: OrbitHomeLayout.margin)
        // The screen's whole width (not the TV's safe area): six tiles fit exactly.
        section.contentInsetsReference = .none
        return UICollectionViewCompositionalLayout(section: section)
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

/// Where the last title was opened from (a generic view cannot hold a static).
@MainActor
enum OrbitDiscoverReturn {
    static var opened: Int?
}
