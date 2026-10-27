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
        .orbitHouseFollows(path.count)
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
            // The whole screen (Steven: the search screen's own shaded ground stopped in a hard
            // line under the bar); its contents start under the bar's band.
            container.view.topAnchor.constraint(equalTo: host.view.topAnchor),
            container.view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            container.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            container.view.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
        ])
        container.additionalSafeAreaInsets.top = 100
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
private final class OrbitSearchHostController: UIViewController {
    weak var searchBar: UISearchBar?
    weak var results: OrbitSearchResultsController?
    private var focusTarget: UIFocusEnvironment?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let menu = UITapGestureRecognizer(target: self, action: #selector(menuPressed))
        menu.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(menu)
        // Steven (device, twice: Up from the keyboard's lower lines went to the bar): the keyboard is
        // one focus item for the whole grid, so a press can't tell "moved a line up" from "nothing
        // above". The bar is asked only when the focus really left for the hidden system tab bar.
        NotificationCenter.default.addObserver(self, selector: #selector(focusMoved(_:)),
                                               name: UIFocusSystem.didUpdateNotification, object: nil)
    }

    /// Back from a title: the results are the page's preferred focus from the start of the way
    /// back (Steven's video: the keyboard had it first, then the poster) — the system's own
    /// restoration lands on the poster.
    private var returning = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if results?.hasRestore == true, let target = results?.prepareRestore() {
            returning = true
            focusTarget = target
            // Steven's video (still): the keyboard took the focus first on the way back — it is
            // out of the focus's reach until the poster has it.
            searchBar?.isUserInteractionEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.searchBar?.isUserInteractionEnabled = true
            }
            setNeedsFocusUpdate()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        OrbitTrace.log("search didAppear restore=\(results?.hasRestore == true) focused=\(Self.describe(view.window?.windowScene?.focusSystem?.focusedItem))")
        if results?.hasRestore == true {
            restoreOpenedTitle(attempt: 0)
        } else {
            focusKeyboard(attempt: 0)
        }
    }

    /// Steven: coming back to Search, the focus went to the recent searches — the keyboard has it
    /// (asked a few times: the system's own landing can come after).
    private func focusKeyboard(attempt: Int) {
        guard let searchBar else { return }
        let focused = view.window?.windowScene?.focusSystem?.focusedItem as? UIView
        if let focused, focused.isDescendant(of: view), !(results.map { focused.isDescendant(of: $0.view) } ?? false) { return }
        if focused != nil, !(focused?.isDescendant(of: view) ?? false) { return }   // the bar or elsewhere: left alone
        move(to: searchBar)
        guard attempt < 3 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.focusKeyboard(attempt: attempt + 1) }
    }

    /// Back from a title: the poster it was opened from, asked again a few times (the system's own
    /// restoration to the keyboard can land after the first ask).
    private func restoreOpenedTitle(attempt: Int) {
        guard let results, let target = results.prepareRestore() else { return }
        let focused = view.window?.windowScene?.focusSystem?.focusedItem as? UIView
        OrbitTrace.log("search restore \(attempt) focused=\(Self.describe(focused))")
        if let cell = results.restoredCell, let focused, focused.isDescendant(of: cell) {
            results.restoreDone()
            searchBar?.isUserInteractionEnabled = true
            returning = false
            focusTarget = nil
            return
        }
        // (Kept as the preferred focus while the way back lasts: cleared, the system's own update
        // went to the keyboard.)
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

    /// Up from the keyboard's first line: the system sends the focus to its hidden tab bar (no way
    /// back down from there) — it goes to the Orbit bar instead.
    private static func describe(_ item: UIFocusItem?) -> String {
        guard let item else { return "nil" }
        var v: UIView? = item as? UIView
        var path: [String] = []
        while let c = v, path.count < 4 { path.append(String(describing: type(of: c))); v = c.superview }
        return path.joined(separator: "<")
    }

    @objc private func focusMoved(_ note: Notification) {
        if let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext {
            OrbitTrace.log("search focus \(Self.describe(context.previouslyFocusedItem)) -> \(Self.describe(context.nextFocusedItem))")
        }
        guard let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext,
              let previous = context.previouslyFocusedItem as? UIView, previous.isDescendant(of: view),
              let next = context.nextFocusedItem as? UIView, !next.isDescendant(of: view) else { return }
        var ancestor: UIView? = next
        // (tvOS 26's floating tab bar is its own private class: matched by name too.)
        while let current = ancestor, !(current is UITabBar),
              !String(describing: type(of: current)).contains("TabBar") { ancestor = current.superview }
        guard ancestor != nil else { return }
        NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil)
    }

    private func move(to target: UIFocusEnvironment) {
        focusTarget = target
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        focusTarget = nil
    }
}

