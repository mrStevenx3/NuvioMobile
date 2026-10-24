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

    private let tabs: [FolderTab]
    private var task: Task<Void, Never>?

    init(tabs: [FolderTab]) {
        self.tabs = tabs
    }

    func queryChanged(_ raw: String) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
            changes: Publishers.Merge(
                $titles.map { _ in () }.eraseToAnyPublisher(),
                $queryIsEmpty.map { _ in () }.eraseToAnyPublisher()
            ).eraseToAnyPublisher(),
            read: { [weak self] in
                OrbitSearchFeed.Snapshot(queryIsEmpty: self?.queryIsEmpty ?? true, chips: [],
                                         titles: self?.titles ?? [])
            }
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
                                         onOpen: onOpen, onClose: onClose)
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
        let results = OrbitSearchResultsController(feed: model.feed, onPick: { _ in }, onOpen: onOpen)
        let search = UISearchController(searchResultsController: results)
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
        private var last = ""

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

    @objc private func upPressed() {
        onClose?()
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
