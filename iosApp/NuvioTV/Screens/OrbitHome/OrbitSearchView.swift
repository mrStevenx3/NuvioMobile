import Combine
import SharedCore
import SwiftUI
import UIKit

// Orbit Search (Steven's fork, 2026-10-23): the Search tab rebuilt from scratch. SwiftUI's
// `.searchable` mounts tvOS's field about a second after the tab appears, so the page came in two
// steps (a look-alike field, then the real one and its keyboard jumping into place). This page is
// UIKit's own search screen (`UISearchContainerViewController`): the field and Apple's keyboard
// (Siri dictation on the remote's microphone, typing from an iPhone) are there at once, the results
// under them, as in Apple's own apps. Results: the suggestions on the left, every title found as
// a poster grid on the right; the data is the existing `SearchViewModel`.

struct OrbitSearchView: View {
    @StateObject private var model = SearchViewModel()
    @StateObject private var queryBox = SearchQueryBox()
    @State private var path = NavigationPath()
    @State private var bridge = OrbitSearchBridge()

    var body: some View {
        NavigationStack(path: $path) {
            OrbitSearchContainer(model: model, queryBox: queryBox, bridge: bridge, onOpen: { item in
                let query = queryBox.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty { model.recordSearch(query) }
                path.append(TitleRoute(preview: item))
            })
            .ignoresSafeArea()
            .background(OrbitHomeLayout.background.ignoresSafeArea())
            .navigationDestination(for: TitleRoute.self) { route in
                DetailView(preview: route.preview)
            }
            .navigationDestination(for: PersonRoute.self) { route in
                PersonDetailView(personId: route.id, personName: route.name)
            }
            .navigationDestination(for: EntityRoute.self) { route in
                OrbitStudioPage(route: .entity(route))
            }
        }
        .environment(\.orbitPush, { path.append($0) })
        .orbitPopsToRootOnGoHome($path, tab: 1)
        .onAppear { model.start() }
        .onDisappear {
            model.stop()
            // Leaving Search clears it; a return opens on an empty field.
            if path.isEmpty, !queryBox.text.isEmpty { bridge.setQuery?("") }
        }
    }
}

/// UIKit's search screen, hosted under the Orbit bar.
private struct OrbitSearchContainer: UIViewControllerRepresentable {
    let model: SearchViewModel
    let queryBox: SearchQueryBox
    let bridge: OrbitSearchBridge
    let onOpen: (MetaPreview) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(model: model, queryBox: queryBox) }

    func makeUIViewController(context: Context) -> UIViewController {
        let coordinator = context.coordinator
        // Device pass 2: the results are a UIKit collection view the search container tracks.
        let results = OrbitSearchResultsController(model: model,
                                                   onPick: { coordinator.setQuery($0) },
                                                   onOpen: onOpen)
        let search = UISearchController(searchResultsController: results)
        search.searchResultsUpdater = coordinator
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Films, séries…")
        coordinator.search = search
        bridge.setQuery = { [weak coordinator] in coordinator?.setQuery($0) }

        let container = UISearchContainerViewController(searchController: search)
        let host = OrbitSearchHostController()
        host.searchBar = search.searchBar
        host.results = results
        host.addChild(container)
        container.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(container.view)
        NSLayoutConstraint.activate([
            // Under the Orbit bar's band.
            container.view.topAnchor.constraint(equalTo: host.view.topAnchor, constant: 100),
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
        let model: SearchViewModel
        let queryBox: SearchQueryBox
        weak var search: UISearchController?

        init(model: SearchViewModel, queryBox: SearchQueryBox) {
            self.model = model
            self.queryBox = queryBox
        }

        func updateSearchResults(for searchController: UISearchController) {
            let text = searchController.searchBar.text ?? ""
            guard text != queryBox.text else { return }
            queryBox.text = text
            model.queryChanged(text)
        }

        /// A suggestion or a recent search picked from the list.
        func setQuery(_ text: String) {
            search?.searchBar.text = text
            queryBox.text = text
            model.queryChanged(text)
        }
    }
}

/// Lets the page reach the search field (clearing it when Search is left).
@MainActor
final class OrbitSearchBridge {
    var setQuery: ((String) -> Void)?
}

/// Steven (device pass): Menu sent the cursor to the hidden system tab bar (it vanished, and the
/// next Down misbehaved). Menu is the page's own here: from the results it goes back up to the
/// keyboard (results scrolled to their top); from the keyboard it goes to the Orbit bar.
private final class OrbitSearchHostController: UIViewController, UIGestureRecognizerDelegate {
    private weak var upRecognizer: UIGestureRecognizer?
    weak var searchBar: UISearchBar?
    weak var results: OrbitSearchResultsController?
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

    /// Back from a title: the poster it was opened from, asked again a few times (the system's own
    /// restoration to the keyboard can land after the first ask).
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

    /// Steven: Menu in the results goes to their first line (same column); from the first line or
    /// the suggestions, to the keyboard; from the keyboard, to the Orbit bar.
    @objc private func menuPressed() {
        let focused = view.window?.windowScene?.focusSystem?.focusedItem as? UIView
        if let results, let focused, let place = results.focusedPlace(focused) {
            if !place.suggestions, place.line > 0, let target = results.prepareFirstLine(column: place.column) {
                move(to: target)
            } else if let searchBar {
                move(to: searchBar)
            }
        } else {
            NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil)
        }
    }

    /// Up from the keyboard: the Orbit bar (the system sent it to the hidden tab bar: no way up).
    @objc private func upPressed() {
        NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil)
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

