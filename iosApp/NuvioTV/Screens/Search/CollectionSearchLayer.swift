import SwiftUI
import SharedCore

/// Steven's fork (collection bar): search inside one collection folder. The Orbit keyboard over a
/// Netflix-style result grid (`SearchGridResults`), matching the titles this folder's catalogs
/// have loaded (every source tab, under the page's Films / Séries filter). Menu closes it.
struct CollectionSearchLayer: View {
    let tabs: [FolderTab]
    let typeFilter: String?
    let onClose: () -> Void

    @StateObject private var queryBox = SearchQueryBox()

    var body: some View {
        let query = queryBox.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = Self.matches(query: query, tabs: tabs, typeFilter: typeFilter)
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.94).ignoresSafeArea()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    OrbitSearchKeyboard(queryBox: queryBox)
                    if query.isEmpty {
                        EmptyView()
                    } else if items.isEmpty {
                        Text("Aucun titre de cette collection ne correspond.")
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    } else {
                        SearchGridResults(entries: SearchGridResults.entries(suggestions: [""], items: items),
                                          items: items,
                                          onPick: { queryBox.text = $0 },
                                          onFocus: { _ in })
                    }
                }
                .padding(.top, 140)
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, Theme.Spacing.screen)
            }
            .scrollClipDisabled()
        }
        .ignoresSafeArea()
        .focusSection()
        .onExitCommand { onClose() }
    }

    /// Titles whose name contains every word of the query (case- and accent-insensitive), in the
    /// folder's tab order, without repeats.
    static func matches(query: String, tabs: [FolderTab], typeFilter: String?) -> [MetaPreview] {
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var out: [MetaPreview] = []
        var seen = Set<String>()
        for tab in tabs where !tab.isAllTab && CollectionTypeFilter.keeps(CollectionTypeFilter.effectiveType(declared: tab.type, name: tab.label),
                                                                        filter: typeFilter) {
            for item in tab.items {
                let name = item.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                guard words.allSatisfy({ name.contains($0) }), seen.insert(item.id).inserted else { continue }
                out.append(item)
            }
        }
        return out
    }
}
