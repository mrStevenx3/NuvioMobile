import SharedCore
import SwiftUI

// Orbit Plateformes / Studios (Steven's fork, 2026-10-24): the two "spaces" pages of the Orbit bar,
// hosted directly (Chris's Stage strip used to carry them). Plateformes: the folder grid
// (`OrbitCollectionGrid`). Studios: the Orbit Studios page (`OrbitStudiosPage`).

struct OrbitSpacesPage: View {
    @ObservedObject var model: HomeViewModel
    let studios: Bool
    let cover: StageCover

    /// Bumped when a folder pushed from the Plateformes grid pops (the grid's own tile restore).
    @State private var gridRestoreGeneration = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            if studios {
                Color(red: 31 / 255, green: 38 / 255, blue: 48 / 255).ignoresSafeArea()
                if let collection = collections.first {
                    OrbitStudiosPage(collection: collection)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            } else {
                OrbitHomeLayout.background.ignoresSafeArea()
                OrbitCollectionGrid(collections: collections, onFolderFocus: { _, _ in },
                                    restoreGeneration: gridRestoreGeneration)
            }
        }
        .ignoresSafeArea()
        .onChange(of: cover) { old, new in
            guard !studios else { return }
            if new.pushed, !old.pushed { OrbitCollectionGrid.notePush() }
            if !new.pushed, old.pushed { gridRestoreGeneration &+= 1 }
        }
    }

    /// The page's collections, in Home's order; all of them when none matches the page.
    private var collections: [NuvioCollection] {
        let all: [NuvioCollection] = model.rows.compactMap { row in
            if case .collection(let collection) = row { return collection }
            return nil
        }
        let matching = all.filter { collection in
            studios ? HomeContentFilter.isStudiosCollection(title: collection.title)
                    : HomeContentFilter.isServicesCollection(title: collection.title)
        }
        return matching.isEmpty ? all : matching
    }
}
