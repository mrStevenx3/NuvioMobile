import SharedCore
import SwiftUI

// Search & Discover batch 2026-10-06 (O3 Stage Discover, plan A4): the Discover tab's root, what
// `MainTabView` mounts in `Tab("Discover", systemImage: "safari", value: 6)` when the placement is
// Own Tab (the default):
//
//     Tab("Discover", systemImage: "safari", value: 6) {
//         DiscoverTabRoot()
//             .tabBarImmersiveHide()
//             .railTabRoot(6)
//     }
//
// It owns the tab's view models (cached for the tab's life, across pushes and tab switches)
// and its own `NavigationStack(path:)` with the four destinations Search registers (`SearchView`),
// so a poster, a See All tile, the Grid pill, a person or a studio/network chip push inside the
// Discover tab. The watchers run while the tab is on screen: `start()` on appear, `stop()` on
// disappear (a stop keeps the rows; the next start resumes any fetch it cancelled).

// FEAT-73 (Steven rc4, D11): the tab lands on the grid-first page (`DiscoverGridPage`); its
// Browse pill pushes the per-genre stage rows (`DiscoverRowsPage`, host `.pushed`: it starts and
// stops its own model and pops on Menu at its top) inside this stack, opened on the grid's catalog.

/// See the file header.
struct DiscoverTabRoot: View {
    @StateObject private var model = DiscoverGridViewModel()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            // Steven's fork (2026-10-23): Orbit Discover, drawn rather than scrolled.
            OrbitDiscoverPage(model: model, onOpen: { path.append(TitleRoute(preview: $0)) })
            .navigationDestination(for: TitleRoute.self) { route in
                DetailView(preview: route.preview)
            }
            .navigationDestination(for: CatalogRoute.self) { route in
                CatalogGridView(route: route)
            }
            .navigationDestination(for: PersonRoute.self) { route in
                PersonDetailView(personId: route.id, personName: route.name)
            }
            .navigationDestination(for: EntityRoute.self) { route in
                OrbitStudioPage(route: .entity(route))
            }
        }
        .environment(\.orbitPush, { path.append($0) })
        .orbitPopsToRootOnGoHome($path, tab: 6)
        .onAppear { model.start() }
        // Steven's fork (device pass): leaving Discover puts it back on Films, every genre, so a
        // return never opens on the last genre browsed.
        .onDisappear {
            model.resetToDefault()
            model.stop()
        }
    }
}
