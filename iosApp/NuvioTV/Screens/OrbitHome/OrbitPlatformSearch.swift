import Combine
import SharedCore
import SwiftUI
import UIKit

// Orbit Plateformes — search (Steven, 2026-10-24): searching inside a platform (only what is on
// Netflix, Disney+…), rebuilt on the general Orbit Search's ground: UIKit's own search screen
// (Apple's field and keyboard at once, Siri dictation, typing from an iPhone), the results as the
// same poster grid (`OrbitSearchResultsController`: a title shows once its poster has loaded, no
// grey squares), and the same remote: Menu in the results goes to their first line, then to the
// keyboard; Menu from the keyboard closes the search; back from a title, the poster it was
// opened from takes the focus again.
//
// What is searched is unchanged: the platform add-on's « Tous les films / Toutes les séries »
// catalogs answer `search=` with titles on the platform only (`CollectionRemoteSearch`); a folder
// without them is searched in the titles already loaded.

@MainActor
final class OrbitPlatformSearchModel: ObservableObject {
    /// The focused result, for the art behind the whole page (Steven, 2026-10-31: drawn behind the
    /// results only, it left a black band at the top of the screen).
    let spotlight = OrbitSearchSpotlight()
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
            // The focused result's colour over the whole screen, from its very top.
            OrbitSearchBackdrop(spotlight: model.spotlight)
                .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            OrbitPlatformSearchContainer(model: model, placeholder: String(localized: "Rechercher sur \(platform)"),
                                         onOpen: { item in
                                             model.recordSearch()
                                             onOpen(item)
                                         },
                                         onClose: onClose)
                .ignoresSafeArea()
            Color.clear.frame(width: 0, height: 0)
                .onAppear { NotificationCenter.default.post(name: .orbitPlatformSearchAppeared, object: model) }
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
        let host = OrbitPlatformSearchHost()
        let results = OrbitSearchResultsController(feed: model.feed, landscape: model.landscape,
                                                   spotlight: model.spotlight,
                                                   onPick: { coordinator.setQuery($0) },
                                                   onOpen: { [weak host] item in
                                                       host?.titleOpened()
                                                       onOpen(item)
                                                   })
        let search = UISearchController(searchResultsController: results)
        coordinator.search = search
        search.searchResultsUpdater = context.coordinator
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = placeholder

        let container = UISearchContainerViewController(searchController: search)
        host.searchBar = search.searchBar
        host.model = model
        host.results = results
        host.onClose = onClose
        host.addChild(container)
        container.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(container.view)
        NSLayoutConstraint.activate([
            container.view.topAnchor.constraint(equalTo: host.view.topAnchor),
            container.view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            container.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            container.view.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
        ])
        // (As the general Search: the whole screen, its contents a little lower.)
        container.additionalSafeAreaInsets.top = 40
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

/// Steven (2026-10-31: "le focus va sur le a et revient… applique les mêmes réglages que la
/// recherche d'Orbit, elle fonctionne bien"): the general Search's own host, line for line — the
/// system's grey grounds hidden, the keyboard taking the focus as it opens, the way back from a
/// title kept on its poster (the keyboard out of reach meanwhile), Menu from the results to their
/// first line then the keyboard, Menu from the keyboard closing the search. Up is the keyboard's
/// own; the focus leaving the search (Up from its top, to the page behind) closes it.
private final class OrbitPlatformSearchHost: UIViewController {
    weak var searchBar: UISearchBar?
    weak var results: OrbitSearchResultsController?
    var onClose: (() -> Void)?
    private var focusTarget: UIFocusEnvironment?
    private var returning = false
    private var closed = false
    /// A title was opened from the results (the focus going to its page is not a leaving).
    var openedAt: TimeInterval = 0
    /// The page's search model: its layer says when it is on screen again (`orbitPlatformSearchAppeared`).
    weak var model: OrbitPlatformSearchModel?

    /// Steven (2026-10-31, again: "il repasse par le a quand je sors d'une affiche"): the search is a
    /// layer of the platform's page, not a page of its own — on the way back from a title the
    /// system's views never told this host they appeared again, so nothing kept the keyboard away:
    /// the system's landing went to it first. The keyboard is now put out of reach as the title
    /// opens, and given back once its poster has the focus again.
    func titleOpened() {
        openedAt = ProcessInfo.processInfo.systemUptime
        searchBar?.isUserInteractionEnabled = false
    }

    /// The layer is on screen again: back from a title, its poster gets the focus.
    @objc private func layerAppeared(_ note: Notification) {
        guard note.object as AnyObject? === model else { return }
        guard results?.hasRestore == true, let target = results?.prepareRestore() else {
            searchBar?.isUserInteractionEnabled = true
            return
        }
        returning = true
        focusTarget = target
        setNeedsFocusUpdate()
        restoreOpenedTitle(attempt: 0)
        // (Never left out of reach: the keyboard comes back whatever happened.)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.searchBar?.isUserInteractionEnabled = true
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let menu = UITapGestureRecognizer(target: self, action: #selector(menuPressed))
        menu.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(menu)
        NotificationCenter.default.addObserver(self, selector: #selector(focusMoved(_:)),
                                               name: UIFocusSystem.didUpdateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(layerAppeared(_:)),
                                               name: .orbitPlatformSearchAppeared, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        hideFullScreenFrost(in: view)
    }

    /// (As the general Search: the system's frosted and grey full-screen grounds hidden — the page's
    /// own ground and the result's colour show.)
    private func hideFullScreenFrost(in root: UIView) {
        let screen = view.bounds.size
        for sub in root.subviews {
            let large = sub.bounds.width >= screen.width * 0.9 && sub.bounds.height >= screen.height * 0.5
            if large, let frost = sub as? UIVisualEffectView {
                if !frost.isHidden { frost.isHidden = true }
                continue
            }
            if large, let ground = sub.backgroundColor, ground != .clear,
               !(sub is UICollectionView), sub !== view {
                sub.backgroundColor = .clear
            }
            hideFullScreenFrost(in: sub)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        closed = false
        if results?.hasRestore == true, let target = results?.prepareRestore() {
            returning = true
            focusTarget = target
            // (The keyboard took the focus first on the way back: out of reach until the poster has it.)
            searchBar?.isUserInteractionEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.searchBar?.isUserInteractionEnabled = true
            }
            setNeedsFocusUpdate()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if results?.hasRestore == true {
            restoreOpenedTitle(attempt: 0)
        } else {
            focusKeyboard(attempt: 0)
        }
    }

    /// The keyboard has the focus as the search opens (asked a few times: the system's own landing
    /// can come after).
    private func focusKeyboard(attempt: Int) {
        guard let searchBar else { return }
        let focused = view.window?.windowScene?.focusSystem?.focusedItem as? UIView
        if let focused, focused.isDescendant(of: view), !(results.map { focused.isDescendant(of: $0.view) } ?? false) { return }
        move(to: searchBar)
        guard attempt < 3 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.focusKeyboard(attempt: attempt + 1) }
    }

    /// Back from a title: the poster it was opened from, asked again a few times.
    private func restoreOpenedTitle(attempt: Int) {
        guard let results, let target = results.prepareRestore() else { return }
        let focused = view.window?.windowScene?.focusSystem?.focusedItem as? UIView
        if let cell = results.restoredCell, let focused, focused.isDescendant(of: cell) {
            results.restoreDone()
            searchBar?.isUserInteractionEnabled = true
            returning = false
            focusTarget = nil
            return
        }
        returning = true
        focusTarget = target
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        guard attempt < 6 else {
            results.restoreDone()
            returning = false
            focusTarget = nil
            searchBar?.isUserInteractionEnabled = true
            return
        }
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
            close()
        }
    }

    /// The focus left the search for something behind it (Up from the keyboard's top): closed.
    @objc private func focusMoved(_ note: Notification) {
        guard !returning, view.window != nil, ProcessInfo.processInfo.systemUptime - openedAt > 2,
              let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext,
              let previous = context.previouslyFocusedItem as? UIView, previous.isDescendant(of: view),
              let next = context.nextFocusedItem as? UIView, !next.isDescendant(of: view) else { return }
        // (A title opened from the results is a push, not a leaving.)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.view.window != nil, !self.returning,
                  ProcessInfo.processInfo.systemUptime - self.openedAt > 2 else { return }
            let now = self.view.window?.windowScene?.focusSystem?.focusedItem as? UIView
            if let now, now.isDescendant(of: self.view) { return }
            self.close()
        }
    }

    private func close() {
        guard !closed else { return }
        closed = true
        onClose?()
    }

    private func move(to target: UIFocusEnvironment) {
        focusTarget = target
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        focusTarget = nil
    }
}


extension Notification.Name {
    /// A platform's search layer is on screen (again, back from a title).
    static let orbitPlatformSearchAppeared = Notification.Name("orbitPlatformSearchAppeared")
}
