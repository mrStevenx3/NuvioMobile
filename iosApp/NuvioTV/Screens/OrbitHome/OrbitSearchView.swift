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
                EntityBrowseView(route: route)
            }
        }
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

    /// Steven: Down from the Orbit bar into the keyboard (field empty) lands on "a", not on
    /// whichever key sat under the bar's item.
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard let next = context.nextFocusedItem, contains(next), !contains(context.previouslyFocusedItem),
              (searchBar?.text ?? "").isEmpty else { return }
        if let results, let view = next as? UIView, view.isDescendant(of: results.view) { return }
        landOnA(near: next, attempt: 0)
    }

    /// The first time the keyboard is reached its keys can still be settling (the move was
    /// ignored and the focus stayed on "m"): asked again a few times until "a" holds it.
    private func landOnA(near key: UIFocusItem, attempt: Int) {
        let delay = attempt == 0 ? 0 : 0.12
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let focused = self.view.window?.windowScene?.focusSystem?.focusedItem
            let current = focused ?? key
            // Only while the focus still sits on the key it first landed on (it got there, or
            // Steven has moved on).
            if attempt > 0, current !== key { return }
            guard self.contains(current), let a = self.letterA(near: current) else {
                if attempt < 5 { self.landOnA(near: key, attempt: attempt + 1) }
                return
            }
            if a === current { return }
            self.move(to: a)
            if attempt < 5 { self.landOnA(near: key, attempt: attempt + 1) }
        }
    }

    private func contains(_ item: UIFocusEnvironment?) -> Bool {
        var env = item
        while let current = env {
            if current === self { return true }
            env = current.parentFocusEnvironment
        }
        return false
    }

    /// The keyboard's "a": by its name, else the third key of the focused key's row (after
    /// "123" and the space bar).
    private func letterA(near key: UIFocusItem) -> UIFocusItem? {
        guard let container = key.parentFocusEnvironment?.focusItemContainer else { return nil }
        let everything = CGRect(x: -20_000, y: -20_000, width: 40_000, height: 40_000)
        let items = container.focusItems(in: everything).filter { $0.canBecomeFocused }
        if let named = items.first(where: {
            (($0 as? NSObject)?.accessibilityLabel ?? "").lowercased() == "a"
        }) { return named }
        let keyFrame = key.frame
        let row = items
            .filter { abs($0.frame.midY - keyFrame.midY) < 24 }
            .sorted { $0.frame.minX < $1.frame.minX }
        return row.count > 2 ? row[2] : nil
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

/// Under the keyboard: the recent searches while the field is empty, else every title found as
/// ONE poster grid across the screen (Steven, device pass: with a suggestions column beside the
/// grid, Down jumped to the bottom and Right back up, the focus engine hopping between two columns
/// of different heights). Titles without a poster are left out (they drew empty tiles).
private struct OrbitSearchResults: View {
    @ObservedObject var model: SearchViewModel
    let onPick: (String) -> Void
    let onOpen: (MetaPreview) -> Void

    private static let columns = 7
    private static let spacing: CGFloat = 30

    var body: some View {
        let gridWidth = OrbitHomeLayout.screenWidth - 2 * OrbitHomeLayout.margin
        let posterWidth = floor((gridWidth - CGFloat(Self.columns - 1) * Self.spacing) / CGFloat(Self.columns))
        let items = SearchGridResults.items(top: model.topResult, rows: model.rows).filter { item in
            let poster: String? = item.poster
            return !(poster?.isEmpty ?? true)
        }
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 28) {
                if model.queryIsEmpty {
                    if !model.history.isEmpty {
                        Text("Recherches récentes")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.55))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(model.history, id: \.self) { entry in
                                    Button { onPick(entry) } label: {
                                        OrbitSearchEntry(text: entry)
                                    }
                                    .buttonStyle(OrbitSearchEntryStyle())
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .scrollClipDisabled()
                        .focusSection()
                    }
                } else if items.isEmpty {
                    if model.isLoading {
                        ProgressView()
                    } else {
                        Text("Aucun résultat.")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(posterWidth), spacing: Self.spacing, alignment: .top),
                                             count: Self.columns),
                              alignment: .leading, spacing: Self.spacing + 10) {
                        ForEach(items, id: \.id) { item in
                            Button { onOpen(item) } label: {
                                PosterCard(title: item.name, imageURL: item.poster, fallbackImageURL: item.rawPosterUrl,
                                           width: posterWidth, height: floor(posterWidth * 1.5), showTitle: false)
                            }
                            .cardFocusButtonStyle()
                            .posterButtonShape()
                        }
                    }
                    .focusSection()
                }
            }
            .frame(width: gridWidth, alignment: .topLeading)
            .padding(.horizontal, OrbitHomeLayout.margin)
            // Room for the focused poster's lift: the page is clipped at its top now, so the posters
            // no longer slide up under the Orbit bar.
            .padding(.top, 40)
            .padding(.bottom, 80)
        }
    }
}

private struct OrbitSearchEntry: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .fixedSize()
    }
}

/// White highlight on focus, no system lift.
private struct OrbitSearchEntryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OrbitSearchEntryBody(configuration: configuration)
    }
}

private struct OrbitSearchEntryBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .foregroundStyle(focused ? Color.black : Color.white)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(focused ? Color.white : Color.clear)
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}
