import Combine
import SharedCore
import SwiftUI
import UIKit

// Orbit Search (Steven's fork, device pass 2): the results under Apple's search keyboard as a UIKit
// collection view, the way Apple's own apps build them. A SwiftUI scroll view hosted there is not
// tracked by the search container: the keyboard and the results moved apart and the focus jumped
// (Down to the bottom, Right back up). The collection view is handed to the container as its
// content scroll view, so the keyboard folds away and comes back with the results' own scroll.
//
//     section 0   suggestions (or recent searches while the field is empty), one scrolling line
//     section 1   every title found, posters seven to a line

/// What the results show, from any search: the general Search (`SearchViewModel`) or a platform's
/// own (`OrbitPlatformSearchModel`). `read` is asked after each `changes` signal.
@MainActor
struct OrbitSearchFeed {
    /// Chips (recent searches while the field is empty, suggestions else) and the titles found.
    struct Snapshot {
        var queryIsEmpty: Bool
        var chips: [String]
        var titles: [MetaPreview]
    }

    let changes: AnyPublisher<Void, Never>
    let read: () -> Snapshot
    /// Steven: a recent search can be removed (long press on it), or all of them.
    var removeRecent: ((String) -> Void)? = nil
    var clearRecent: (() -> Void)? = nil

    /// The general Search.
    static func search(_ model: SearchViewModel) -> OrbitSearchFeed {
        OrbitSearchFeed(
            changes: Publishers.MergeMany(
                model.$rows.map { _ in () }.eraseToAnyPublisher(),
                model.$topResult.map { _ in () }.eraseToAnyPublisher(),
                model.$suggestions.map { _ in () }.eraseToAnyPublisher(),
                model.$history.map { _ in () }.eraseToAnyPublisher(),
                model.$queryIsEmpty.map { _ in () }.eraseToAnyPublisher()
            ).eraseToAnyPublisher(),
            read: { [weak model] in
                guard let model else { return Snapshot(queryIsEmpty: true, chips: [], titles: []) }
                let all = SearchGridResults.items(top: model.topResult, rows: model.rows)
                let chips = model.queryIsEmpty ? model.history
                    : SearchGridResults.entries(suggestions: model.suggestions, items: all, limit: 10)
                return Snapshot(queryIsEmpty: model.queryIsEmpty, chips: chips, titles: all)
            },
            removeRecent: { [weak model] in model?.removeHistory($0) },
            clearRecent: { [weak model] in
                guard let model else { return }
                model.history.forEach { model.removeHistory($0) }
            }
        )
    }
}

@MainActor
final class OrbitSearchResultsController: UIViewController, UICollectionViewDelegate {
    private let feed: OrbitSearchFeed
    /// Orbit Plateformes: a platform whose art is landscape (Prime Video, Paramount+ in Steven's
    /// add-ons) shows its results as landscape tiles, four to a line.
    private let landscape: Bool
    private let onPick: (String) -> Void
    private let onOpen: (MetaPreview) -> Void

    nonisolated private enum Section: Int, Sendable { case suggestions, titles }
    nonisolated private enum Item: Hashable, Sendable {
        case suggestion(String)
        case title(String)
    }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var titles: [String: MetaPreview] = [:]
    private var cancellables = Set<AnyCancellable>()
    /// Steven (2026-10-25): the focused result's art behind the results, as on Home.
    private let spotlight = OrbitSearchSpotlight()

    static let columns = 7
    static let landscapeColumns = 4
    static let margin: CGFloat = OrbitHomeLayout.margin
    static let spacing: CGFloat = 30

    convenience init(model: SearchViewModel, onPick: @escaping (String) -> Void, onOpen: @escaping (MetaPreview) -> Void) {
        self.init(feed: .search(model), onPick: onPick, onOpen: onOpen)
    }

    init(feed: OrbitSearchFeed, landscape: Bool = false,
         onPick: @escaping (String) -> Void, onOpen: @escaping (MetaPreview) -> Void) {
        self.feed = feed
        self.landscape = landscape
        self.onPick = onPick
        self.onOpen = onOpen
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let backdrop = UIHostingController(rootView: OrbitSearchBackdrop(spotlight: spotlight))
        backdrop.view.backgroundColor = .clear
        backdrop.view.frame = view.bounds
        backdrop.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backdrop.view.isUserInteractionEnabled = false
        addChild(backdrop)
        view.addSubview(backdrop.view)
        backdrop.didMove(toParent: self)
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: Self.layout(landscape: landscape))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        // The page picks the focused cell itself on Menu (`focusFirstLine`).
        collectionView.remembersLastFocusedIndexPath = false
        collectionView.delegate = self
        collectionView.contentInset = UIEdgeInsets(top: 30, left: 0, bottom: 80, right: 0)
        view.addSubview(collectionView)
        setContentScrollView(collectionView)

        let suggestionCell = UICollectionView.CellRegistration<UICollectionViewCell, String> { cell, _, text in
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    OrbitSearchChip(text: text, focused: state.isFocused)
                }
                .margins(.all, 0)
            }
        }
        let titleCell = UICollectionView.CellRegistration<UICollectionViewCell, MetaPreview> { cell, _, item in
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    OrbitSearchPoster(item: item, focused: state.isFocused)
                }
                .margins(.all, 0)
            }
        }
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { [weak self] view, path, item in
            switch item {
            case .suggestion(let text):
                return view.dequeueConfiguredReusableCell(using: suggestionCell, for: path, item: text)
            case .title(let id):
                let preview = self?.titles[id]
                return view.dequeueConfiguredReusableCell(using: titleCell, for: path, item: preview ?? Self.placeholder)
            }
        }

        // One snapshot per change of what the page shows (the model publishes on willSet: read
        // the values on the next turn).
        feed.changes
        .debounce(for: .milliseconds(60), scheduler: DispatchQueue.main)
        .sink { [weak self] in MainActor.assumeIsolated { self?.apply() } }
        .store(in: &cancellables)
        apply()
    }

    /// Steven: titles whose poster does not load drew grey squares. A title shows once its poster
    /// is loaded (at the cell's own decode size), never if it fails.
    private var posterLoaded: [String: Bool] = [:]
    private var reapplyScheduled = false

    private var columns: Int { landscape ? Self.landscapeColumns : Self.columns }

    private var posterRequest: ArtworkDecodeRequest {
        let width = (view.bounds.width > 0 ? view.bounds.width : OrbitHomeLayout.screenWidth) - 2 * Self.margin
        let posterWidth = floor((width - CGFloat(columns - 1) * Self.spacing) / CGFloat(columns))
        let ratio: CGFloat = landscape ? 9.0 / 16.0 : 1.5
        return ArtworkDecodeRequest(size: .points(width: posterWidth, height: floor(posterWidth * ratio)),
                                    fill: true, scale: traitCollection.displayScale)
    }

    private func posterReady(_ item: MetaPreview) -> Bool {
        let key = item.id
        if let known = posterLoaded[key] { return known }
        let poster: String? = item.poster
        guard let url = poster.flatMap(URL.init(string:)) else { posterLoaded[key] = false; return false }
        let request = posterRequest
        if ArtworkStore.cached(url, decode: request) != nil { posterLoaded[key] = true; return true }
        posterLoaded[key] = false
        Task { [weak self] in
            let ok = (try? await ArtworkStore.fetch(url, decode: request)) != nil
            guard let self, ok else { return }
            self.posterLoaded[key] = true
            self.scheduleApply()
        }
        return false
    }

    private func scheduleApply() {
        guard !reapplyScheduled else { return }
        reapplyScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.reapplyScheduled = false
            self.apply()
        }
    }

    private func apply() {
        let shot = feed.read()
        if shot.queryIsEmpty, spotlight.item != nil { spotlight.item = nil }
        let found = shot.titles.filter { posterReady($0) }
        titles = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = shot.chips
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.suggestions, .titles])
        var seen = Set<String>()
        snapshot.appendItems(entries.filter { seen.insert($0).inserted }.map(Item.suggestion), toSection: .suggestions)
        snapshot.appendItems(shot.queryIsEmpty ? [] : found.map { Item.title($0.id) }, toSection: .titles)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// Menu: the first line of posters, same column (nil when already there or nothing to show).
    private var preferredPath: IndexPath?

    /// The focused cell's place: nil outside the grid, else (in the suggestions line?, column).
    func focusedPlace(_ focused: UIView) -> (suggestions: Bool, line: Int, column: Int)? {
        guard focused.isDescendant(of: collectionView) else { return nil }
        var view: UIView? = focused
        while let v = view, !(v is UICollectionViewCell) { view = v.superview }
        guard let cell = view as? UICollectionViewCell, let path = collectionView.indexPath(for: cell) else { return nil }
        if path.section == Section.suggestions.rawValue { return (true, 0, 0) }
        return (false, path.item / columns, path.item % columns)
    }

    /// Scrolls back to the top and names the first line's cell in `column` as the focus target.
    func prepareFirstLine(column: Int) -> UIFocusEnvironment? {
        let count = collectionView.numberOfItems(inSection: Section.titles.rawValue)
        guard count > 0 else { return nil }
        preferredPath = IndexPath(item: min(column, count - 1), section: Section.titles.rawValue)
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false)
        collectionView.layoutIfNeeded()
        return collectionView
    }

    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        defer { preferredPath = nil }
        return preferredPath
    }

    /// Long press on a recent search (the field empty): remove it, or every recent search.
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let path = indexPaths.first, case .suggestion(let text)? = dataSource.itemIdentifier(for: path),
              feed.read().queryIsEmpty, let remove = feed.removeRecent else { return nil }
        let clear = feed.clearRecent
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            var actions: [UIMenuElement] = [
                UIAction(title: String(localized: "Supprimer « \(text) »"), image: UIImage(systemName: "xmark"),
                         attributes: .destructive) { _ in remove(text) },
            ]
            if let clear {
                actions.append(UIAction(title: String(localized: "Effacer toutes les recherches récentes"),
                                        image: UIImage(systemName: "trash"), attributes: .destructive) { _ in clear() })
            }
            return UIMenu(children: actions)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                        with coordinator: UIFocusAnimationCoordinator) {
        guard let path = context.nextFocusedIndexPath, case .title(let id)? = dataSource.itemIdentifier(for: path),
              let item = titles[id] else { return }
        if spotlight.item?.id != item.id { spotlight.item = item }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .suggestion(let text): onPick(text)
        case .title(let id):
            if let preview = titles[id] {
                lastOpened = indexPath
                onOpen(preview)
            }
        }
    }

    /// Steven: back from a title, the cursor went back up to the keyboard. The poster it was
    /// opened from takes focus again.
    private var lastOpened: IndexPath?

    func prepareRestore() -> UIFocusEnvironment? {
        guard let path = lastOpened, path.section < collectionView.numberOfSections,
              path.item < collectionView.numberOfItems(inSection: path.section) else { return nil }
        preferredPath = path
        // Steven (device: a bounce on the way back): the results stay where they were when the
        // poster is still on screen; only an off-screen one is brought back.
        if !collectionView.indexPathsForVisibleItems.contains(path) {
            collectionView.scrollToItem(at: path, at: .centeredVertically, animated: false)
            collectionView.layoutIfNeeded()
        }
        return collectionView
    }

    func restoreDone() { lastOpened = nil }

    var restoredCell: UIView? { lastOpened.flatMap { collectionView.cellForItem(at: $0) } }

    private static func layout(landscape: Bool) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { index, environment in
            if index == Section.suggestions.rawValue {
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .estimated(220), heightDimension: .absolute(64)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .estimated(220),
                                                                                 heightDimension: .absolute(64)),
                                                               subitems: [item])
                let section = NSCollectionLayoutSection(group: group)
                section.orthogonalScrollingBehavior = .continuous
                section.interGroupSpacing = 14
                section.contentInsets = .init(top: 0, leading: margin, bottom: 34, trailing: margin)
                return section
            }
            let count = landscape ? landscapeColumns : columns
            let width = environment.container.effectiveContentSize.width - 2 * margin
            let posterWidth = floor((width - CGFloat(count - 1) * spacing) / CGFloat(count))
            let height = floor(posterWidth * (landscape ? 9.0 / 16.0 : 1.5))
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(posterWidth),
                                                                heightDimension: .absolute(height)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                             heightDimension: .absolute(height)),
                                                           repeatingSubitem: item, count: count)
            group.interItemSpacing = .fixed(spacing)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = spacing + 12
            section.contentInsets = .init(top: 0, leading: margin, bottom: 0, trailing: margin)
            return section
        }
    }

    private static let placeholder = MetaPreview(
        id: "-", type: "movie", name: "", poster: nil, banner: nil, logo: nil,
        posterShape: .poster, description: nil, releaseInfo: nil, rawReleaseDate: nil,
        popularity: nil, voteCount: nil, imdbRating: nil, genres: [], rawPosterUrl: nil,
        landscapePoster: nil, rawLandscapePosterUrl: nil, customPosterApplied: false)
}

/// A suggestion or a recent search.
private struct OrbitSearchChip: View {
    let text: String
    let focused: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 26, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(focused ? Color.black : Color.white)
            .padding(.horizontal, 24)
            .frame(height: 60)
            .background(Capsule().fill(focused ? Color.white : Color.white.opacity(0.14)))
            .scaleEffect(focused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// A title found: its poster, the white frame and a small lift when focused.
private struct OrbitSearchPoster: View {
    let item: MetaPreview
    let focused: Bool
    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(white: 0.1)
                // Steven (Charmed: a plain catalog poster, no title): TMDB's poster in his language,
                // with its title, as on Home; the catalog's while TMDB has none.
                // (TMDB's own poster when it has none in his language: Charmed has none in French.)
                let meta = metaStore.meta(for: item)
                let local = meta?.localPoster ?? meta?.titledPoster
                OrbitImage(url: local ?? item.poster, fallback: local != nil ? item.poster : item.rawPosterUrl,
                           size: geo.size, placeholder: local != nil ? item.poster : nil)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 4)
            }
            .scaleEffect(focused ? 1.08 : 1)
            .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 16, y: 10)
            .animation(.easeOut(duration: 0.18), value: focused)
        }
        .onAppear { metaStore.request([item]) }
    }
}

/// The focused result (the backdrop follows it; it stays when the focus goes back to the keyboard).
@MainActor
final class OrbitSearchSpotlight: ObservableObject {
    @Published var item: MetaPreview?
}

private struct OrbitSearchBackdrop: View {
    @ObservedObject var spotlight: OrbitSearchSpotlight

    var body: some View {
        OrbitFocusBackdrop(item: spotlight.item)
            .animation(.easeInOut(duration: 0.35), value: spotlight.item?.id)
            .ignoresSafeArea()
    }
}
