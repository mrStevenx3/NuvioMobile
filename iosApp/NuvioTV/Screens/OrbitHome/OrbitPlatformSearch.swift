import Combine
import SharedCore
import SwiftUI
import UIKit

// Orbit Plateformes — search (Steven, 2026-10-24): searching inside a platform (only what is on
// Netflix, Disney+…), rebuilt on the general Orbit Search's ground: UIKit's own search screen
// (Apple's field and keyboard at once, Siri dictation, typing from an iPhone), the results as the
// same poster grid (`OrbitSearchResultsController`: a title shows once its poster has loaded, no
// grey squares), and the same remote: Menu in the results goes to their first line, then to the
// keyboard; Menu or Up from the keyboard closes the search; back from a title, the poster it was
// opened from takes the focus again.
//
// What is searched is unchanged: the platform add-on's « Tous les films / Toutes les séries »
// catalogs answer `search=` with titles on the platform only (`CollectionRemoteSearch`); a folder
// without them is searched in the titles already loaded.

@MainActor
final class OrbitPlatformSearchModel: ObservableObject {
    @Published private(set) var titles: [MetaPreview] = []
    @Published private(set) var queryIsEmpty = true
    @Published private(set) var searching = false
    /// Recent searches on this platform (shown while the field is empty, like the general Search).
    @Published private(set) var history: [String] = []
    /// The platform's art is landscape: the results are landscape tiles.
    let landscape: Bool

    private let tabs: [FolderTab]
    private let historyKey: String
    private var task: Task<Void, Never>?
    private(set) var query = ""

    init(tabs: [FolderTab], platformKey: String, landscape: Bool) {
        self.tabs = tabs
        self.landscape = landscape
        historyKey = "orbit_platform_search_history.\(platformKey)"
        history = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    func removeRecent(_ text: String) {
        history = history.filter { $0 != text }
        UserDefaults.standard.set(history, forKey: historyKey)
    }

    func clearRecent() {
        history = []
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    /// A title opened from the results: its search goes to the top of the recent ones.
    func recordSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return }
        var list = history.filter { $0.lowercased() != text.lowercased() }
        list.insert(text, at: 0)
        history = Array(list.prefix(10))
        UserDefaults.standard.set(history, forKey: historyKey)
    }

    func queryChanged(_ raw: String) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        self.query = query
        task?.cancel()
        queryIsEmpty = query.isEmpty
        guard query.count >= 2 else {
            titles = []
            searching = false
            return
        }
        searching = true
        let tabs = tabs
        task = Task { [weak self] in
            // A pause in the typing first: one request per word, not per letter.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let found: [MetaPreview]
            if CollectionRemoteSearch.hasSearchableCatalogs(tabs) {
                found = await CollectionRemoteSearch.search(query: query, tabs: tabs)
            } else {
                found = CollectionSearchLayer.matches(query: query, tabs: tabs, typeFilter: nil)
            }
            guard !Task.isCancelled, let self else { return }
            self.titles = found
            self.searching = false
        }
    }

    var feed: OrbitSearchFeed {
        OrbitSearchFeed(
            changes: Publishers.Merge3(
                $titles.map { _ in () }.eraseToAnyPublisher(),
                $queryIsEmpty.map { _ in () }.eraseToAnyPublisher(),
                $history.map { _ in () }.eraseToAnyPublisher()
            ).eraseToAnyPublisher(),
            read: { [weak self] in
                guard let self else { return OrbitSearchFeed.Snapshot(queryIsEmpty: true, chips: [], titles: []) }
                // As on the general Search: the recent searches while the field is empty, else
                // the names of what was found.
                let chips = self.queryIsEmpty ? self.history
                    : SearchGridResults.entries(suggestions: [], items: self.titles, limit: 10)
                return OrbitSearchFeed.Snapshot(queryIsEmpty: self.queryIsEmpty, chips: chips, titles: self.titles)
            },
            removeRecent: { [weak self] in self?.removeRecent($0) },
            clearRecent: { [weak self] in self?.clearRecent() }
        )
    }
}

/// The search layer over the platform page.
struct OrbitPlatformSearchLayer: View {
    @ObservedObject var model: OrbitPlatformSearchModel
    let platform: String
    let onOpen: (MetaPreview) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.94).ignoresSafeArea()
            OrbitPlatformSearchContainer(model: model, placeholder: String(localized: "Rechercher sur \(platform)"),
                                         onOpen: { item in
                                             model.recordSearch()
                                             onOpen(item)
                                         },
                                         onClose: onClose)
                .ignoresSafeArea()
            if !model.queryIsEmpty, !model.searching, model.titles.isEmpty {
                Text(String(localized: "Aucun titre sur \(platform) ne correspond."))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 560)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct OrbitPlatformSearchContainer: UIViewControllerRepresentable {
    let model: OrbitPlatformSearchModel
    let placeholder: String
    let onOpen: (MetaPreview) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIViewController(context: Context) -> UIViewController {
        let coordinator = context.coordinator
        let results = OrbitSearchResultsController(feed: model.feed, landscape: model.landscape,
                                                   onPick: { coordinator.setQuery($0) }, onOpen: onOpen)
        let search = UISearchController(searchResultsController: results)
        coordinator.search = search
        search.searchResultsUpdater = context.coordinator
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = placeholder

        let container = UISearchContainerViewController(searchController: search)
        let host = OrbitPlatformSearchHost()
        host.searchBar = search.searchBar
        host.results = results
        host.onClose = onClose
        host.addChild(container)
        container.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(container.view)
        NSLayoutConstraint.activate([
            container.view.topAnchor.constraint(equalTo: host.view.topAnchor, constant: 40),
            container.view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            container.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            container.view.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
        ])
        container.didMove(toParent: host)
        return host
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UISearchResultsUpdating {
        let model: OrbitPlatformSearchModel
        weak var search: UISearchController?
        private var last = ""

        /// A suggestion or a recent search picked from the line.
        func setQuery(_ text: String) {
            search?.searchBar.text = text
            last = text
            model.queryChanged(text)
        }

        init(model: OrbitPlatformSearchModel) {
            self.model = model
        }

        func updateSearchResults(for searchController: UISearchController) {
            let text = searchController.searchBar.text ?? ""
            guard text != last else { return }
            last = text
            model.queryChanged(text)
        }
    }
}

/// The remote, as on the general Search: Menu in the results goes to their first line (same
/// column), then to the keyboard; Menu or Up from the keyboard closes the search. Back from a
/// title, the poster it was opened from.
private final class OrbitPlatformSearchHost: UIViewController, UIGestureRecognizerDelegate {
    private weak var upRecognizer: UIGestureRecognizer?
    weak var searchBar: UISearchBar?
    weak var results: OrbitSearchResultsController?
    var onClose: (() -> Void)?
    private var focusTarget: UIFocusEnvironment?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let menu = UITapGestureRecognizer(target: self, action: #selector(menuPressed))
        menu.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(menu)
        let up = UITapGestureRecognizer(target: self, action: #selector(upPressed))
        up.allowedPressTypes = [NSNumber(value: UIPress.PressType.upArrow.rawValue)]
        up.delegate = self
        // (The focus engine still gets the press: Up moves within the keyboard as usual.)
        up.cancelsTouchesInView = false
        view.addGestureRecognizer(up)
        upRecognizer = up
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restoreOpenedTitle(attempt: 0)
    }

    private func restoreOpenedTitle(attempt: Int) {
        guard let results, let target = results.prepareRestore() else { return }
        let focused = view.window?.windowScene?.focusSystem?.focusedItem as? UIView
        if let cell = results.restoredCell, let focused, focused.isDescendant(of: cell) {
            results.restoreDone()
            return
        }
        move(to: target)
        guard attempt < 4 else { results.restoreDone(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.restoreOpenedTitle(attempt: attempt + 1)
        }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let focusTarget { return [focusTarget] }
        return super.preferredFocusEnvironments
    }

    @objc private func menuPressed() {
        let focused = view.window?.windowScene?.focusSystem?.focusedItem as? UIView
        if let results, let focused, let place = results.focusedPlace(focused) {
            if !place.suggestions, place.line > 0, let target = results.prepareFirstLine(column: place.column) {
                move(to: target)
            } else if let searchBar {
                move(to: searchBar)
            }
        } else {
            onClose?()
        }
    }

    /// Steven (2026-10-31: "la fenêtre de recherche se ferme toute seule quand je tape du texte"):
    /// every Up outside the results closed the search — Up from the keyboard's lower lines too, while
    /// typing. Now Up closes it only when it moves nothing: from the keyboard's (or the field's) top.
    @objc private func upPressed() {
        let before = view.window?.windowScene?.focusSystem?.focusedItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let now = self.view.window?.windowScene?.focusSystem?.focusedItem
            // (Up that took the focus out of the search, behind it: closed too.)
            if let moved = now as? UIView, !moved.isDescendant(of: self.view) { self.onClose?(); return }
            guard let before, let now, before === now else { return }
            if let results = self.results, let focused = now as? UIView, focused.isDescendant(of: results.view) { return }
            self.onClose?()
        }
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        recognizer === upRecognizer
    }

    private func move(to target: UIFocusEnvironment) {
        focusTarget = target
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        focusTarget = nil
    }

    // Up is taken only while the focus is NOT in the results (the keyboard or the field).
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
        guard recognizer === upRecognizer else { return true }
        let focused = view.window?.windowScene?.focusSystem?.focusedItem as? UIView
        guard let focused, let results else { return true }
        return !focused.isDescendant(of: results.view)
    }
}
