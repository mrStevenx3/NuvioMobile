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

@MainActor
final class OrbitSearchResultsController: UIViewController, UICollectionViewDelegate {
    private let model: SearchViewModel
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

    static let columns = 7
    static let margin: CGFloat = OrbitHomeLayout.margin
    static let spacing: CGFloat = 30

    init(model: SearchViewModel, onPick: @escaping (String) -> Void, onOpen: @escaping (MetaPreview) -> Void) {
        self.model = model
        self.onPick = onPick
        self.onOpen = onOpen
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: Self.layout())
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
        Publishers.MergeMany(
            model.$rows.map { _ in () }.eraseToAnyPublisher(),
            model.$topResult.map { _ in () }.eraseToAnyPublisher(),
            model.$suggestions.map { _ in () }.eraseToAnyPublisher(),
            model.$history.map { _ in () }.eraseToAnyPublisher(),
            model.$queryIsEmpty.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(60), scheduler: DispatchQueue.main)
        .sink { [weak self] in MainActor.assumeIsolated { self?.apply() } }
        .store(in: &cancellables)
        apply()
    }

    /// Steven: titles whose poster does not load drew grey squares. A title shows once its poster
    /// is loaded (at the cell's own decode size), never if it fails.
    private var posterLoaded: [String: Bool] = [:]
    private var reapplyScheduled = false

    private var posterRequest: ArtworkDecodeRequest {
        let width = (view.bounds.width > 0 ? view.bounds.width : OrbitHomeLayout.screenWidth) - 2 * Self.margin
        let posterWidth = floor((width - CGFloat(Self.columns - 1) * Self.spacing) / CGFloat(Self.columns))
        return ArtworkDecodeRequest(size: .points(width: posterWidth, height: floor(posterWidth * 1.5)),
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
        let all = SearchGridResults.items(top: model.topResult, rows: model.rows)
        let found = all.filter { posterReady($0) }
        titles = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = model.queryIsEmpty ? model.history
            : SearchGridResults.entries(suggestions: model.suggestions, items: all, limit: 10)
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.suggestions, .titles])
        var seen = Set<String>()
        snapshot.appendItems(entries.filter { seen.insert($0).inserted }.map(Item.suggestion), toSection: .suggestions)
        snapshot.appendItems(model.queryIsEmpty ? [] : found.map { Item.title($0.id) }, toSection: .titles)
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
        return (false, path.item / Self.columns, path.item % Self.columns)
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

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .suggestion(let text): onPick(text)
        case .title(let id): if let preview = titles[id] { onOpen(preview) }
        }
    }

    private static func layout() -> UICollectionViewCompositionalLayout {
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
            let width = environment.container.effectiveContentSize.width - 2 * margin
            let posterWidth = floor((width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(posterWidth),
                                                                heightDimension: .absolute(floor(posterWidth * 1.5))))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                             heightDimension: .absolute(floor(posterWidth * 1.5))),
                                                           repeatingSubitem: item, count: columns)
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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(white: 0.1)
                OrbitImage(url: item.poster, fallback: item.rawPosterUrl, size: geo.size)
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
    }
}
