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
        let results = UIHostingController(rootView: OrbitSearchResults(model: model,
                                                                       onPick: { coordinator.setQuery($0) },
                                                                       onOpen: onOpen))
        results.view.backgroundColor = .clear
        let search = UISearchController(searchResultsController: results)
        search.searchResultsUpdater = coordinator
        search.obscuresBackgroundDuringPresentation = false
        search.showsSearchResultsController = true
        search.searchBar.placeholder = String(localized: "Films, séries…")
        coordinator.search = search
        bridge.setQuery = { [weak coordinator] in coordinator?.setQuery($0) }

        let container = UISearchContainerViewController(searchController: search)
        let host = OrbitSearchHostController()
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

private final class OrbitSearchHostController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
}

/// Under the keyboard: the recent searches while the field is empty, else the suggestions and
/// the titles found.
private struct OrbitSearchResults: View {
    @ObservedObject var model: SearchViewModel
    let onPick: (String) -> Void
    let onOpen: (MetaPreview) -> Void

    private static let listWidth: CGFloat = 420
    private static let columns = 5
    private static let spacing: CGFloat = 32

    var body: some View {
        let gridWidth = OrbitHomeLayout.screenWidth - 2 * OrbitHomeLayout.margin - Self.listWidth - 56
        let posterWidth = floor((gridWidth - CGFloat(Self.columns - 1) * Self.spacing) / CGFloat(Self.columns))
        let items = SearchGridResults.items(top: model.topResult, rows: model.rows)
        let entries = model.queryIsEmpty ? model.history
            : SearchGridResults.entries(suggestions: model.suggestions, items: items)
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 56) {
                VStack(alignment: .leading, spacing: 6) {
                    if model.queryIsEmpty, !entries.isEmpty {
                        Text("Recherches récentes")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .padding(.leading, 18)
                            .padding(.bottom, 8)
                    }
                    ForEach(entries, id: \.self) { entry in
                        Button { onPick(entry) } label: {
                            OrbitSearchEntry(text: entry)
                        }
                        .buttonStyle(OrbitSearchEntryStyle())
                    }
                }
                .frame(width: Self.listWidth, alignment: .leading)
                .focusSection()

                VStack(alignment: .leading, spacing: 24) {
                    if !model.queryIsEmpty {
                        if items.isEmpty, model.isLoading {
                            ProgressView()
                        } else if items.isEmpty {
                            Text("Aucun résultat.")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(posterWidth), spacing: Self.spacing, alignment: .top),
                                             count: Self.columns),
                              alignment: .leading, spacing: Self.spacing) {
                        ForEach(items, id: \.id) { item in
                            Button { onOpen(item) } label: {
                                PosterCard(title: item.name, imageURL: item.poster, fallbackImageURL: item.rawPosterUrl,
                                           width: posterWidth, height: floor(posterWidth * 1.5), showTitle: false)
                            }
                            .cardFocusButtonStyle()
                            .posterButtonShape()
                        }
                    }
                }
                .frame(width: gridWidth, alignment: .topLeading)
                .focusSection()
            }
            .padding(.horizontal, OrbitHomeLayout.margin)
            .padding(.top, 30)
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
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
            .frame(width: 420, alignment: .leading)
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
