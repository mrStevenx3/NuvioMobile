import SwiftUI
import SharedCore

/// Steven's fork (collection bar): search inside one collection folder, on tvOS's own system
/// search field and keyboard (Siri dictation from the remote's microphone, typing from an iPhone),
/// over a Netflix-style result grid (`SearchGridResults`). Menu closes it.
///
/// Built like `SearchView` (see its header): `.searchable` sits on the results `ScrollView` inside
/// Home's own `NavigationStack` (no nested stack), the typed text lives in `SearchQueryBox`, and
/// the view that carries `.searchable` observes only that box, so a results update never
/// re-applies the field's binding (the iPhone-keyboard flicker).
struct CollectionSearchLayer: View {
    let tabs: [FolderTab]
    let typeFilter: String?
    let onClose: () -> Void

    /// Held, never observed here (an `@State` box does not subscribe this view).
    @State private var queryBox = SearchQueryBox()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.94).ignoresSafeArea()
            CollectionSearchField(queryBox: queryBox) {
                CollectionSearchResults(queryBox: queryBox, tabs: tabs)
            }
        }
        .focusSection()
        .onExitCommand { onClose() }
    }

    static func merged(_ first: [MetaPreview], _ second: [MetaPreview]) -> [MetaPreview] {
        var seen = Set<String>()
        return (first + second).filter { seen.insert($0.id).inserted }
    }

    /// Titles whose name contains every word of the query (case- and accent-insensitive), in the
    /// folder's tab order, without repeats.
    static func matches(query: String, tabs: [FolderTab], typeFilter: String?) -> [MetaPreview] {
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var out: [MetaPreview] = []
        var seen = Set<String>()
        let everything = tabs.filter { CollectionRemoteSearch.isEverythingCatalog($0.catalogId) }
        for tab in (everything.isEmpty ? tabs : everything) where !tab.isAllTab
            && CollectionTypeFilter.keeps(CollectionTypeFilter.effectiveType(declared: tab.type, name: tab.label),
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


/// Steven's fork (collection search, pass 2): asks the folder's add-on catalogs that declare a
/// `search` extra in their manifest (Steven's platform add-ons, v1.1: « Tous les films / Toutes les
/// séries », which keep only titles on the platform) — `…/catalog/<type>/<id>/search=<q>.json`.
enum CollectionRemoteSearch {
    private struct Response: Decodable {
        struct Meta: Decodable {
            let id: String
            let type: String?
            let name: String?
            let poster: String?
            let background: String?
            let description: String?
            let releaseInfo: String?
            let imdbRating: String?
            /// Steven's landscape platforms (Prime Video, Paramount+) declare "landscape".
            let posterShape: String?
        }
        let metas: [Meta]?
    }

    /// Steven's platform add-ons' « Tous les films / Toutes les séries » (`<prefix>-all-movies` /
    /// `<prefix>-all-series`), the catalogs that carry the platform-wide search (add-on v1.1).
    static func isEverythingCatalog(_ id: String) -> Bool {
        id.hasSuffix("-all-movies") || id.hasSuffix("-all-series")
    }

    static func hasSearchableCatalogs(_ tabs: [FolderTab]) -> Bool {
        tabs.contains { !$0.isAllTab && isEverythingCatalog($0.catalogId) && !($0.manifestUrl ?? "").isEmpty }
    }

    @MainActor
    static func search(query: String, tabs: [FolderTab]) async -> [MetaPreview] {
        var targets: [(base: String, type: String, catalogId: String)] = []
        var seen = Set<String>()
        for tab in tabs where !tab.isAllTab && isEverythingCatalog(tab.catalogId) {
            guard let manifestUrl = tab.manifestUrl, !manifestUrl.isEmpty else { continue }
            let base = manifestUrl.components(separatedBy: "/manifest.json").first ?? manifestUrl
            if seen.insert("\(base)|\(tab.type)|\(tab.catalogId)").inserted {
                targets.append((base, tab.type, tab.catalogId))
            }
        }
        guard !targets.isEmpty else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/&=?"))) ?? query
        let lists = await withTaskGroup(of: [MetaPreview].self) { group in
            for target in targets {
                group.addTask {
                    guard let url = URL(string: "\(target.base)/catalog/\(target.type)/\(target.catalogId)/search=\(encoded).json"),
                          let response = try? await URLSession.shared.data(from: url),
                          let decoded = try? JSONDecoder().decode(Response.self, from: response.0) else {
                        NSLog("[CollectionSearch] failed %@/%@", target.type, target.catalogId)
                        return []
                    }
                    return (decoded.metas ?? []).map { meta in
                        MetaPreview(id: meta.id, type: meta.type ?? target.type, name: meta.name ?? "",
                                    poster: meta.poster, banner: meta.background, logo: nil,
                                    posterShape: meta.posterShape?.lowercased() == "landscape" ? .landscape
                                        : (meta.posterShape?.lowercased() == "square" ? .square : .poster),
                                    description: meta.description, releaseInfo: meta.releaseInfo, rawReleaseDate: nil,
                                    popularity: nil, voteCount: nil, imdbRating: meta.imdbRating,
                                    genres: [],
                                    rawPosterUrl: nil,
                                    landscapePoster: nil,
                                    rawLandscapePosterUrl: nil,
                                    customPosterApplied: false)
                    }
                }
            }
            var all: [[MetaPreview]] = []
            for await list in group { all.append(list) }
            return all
        }
        // An add-on that predates v1.1 ignores `search=` and answers its plain list: keep only titles
        // whose name holds a word of the query, so such a catalog adds nothing instead of noise.
        let words = fold(query).split(separator: " ").map(String.init).filter { $0.count >= 2 }
        let found = CollectionSearchLayer.merged(lists.flatMap { $0 }, []).filter { item in
            words.isEmpty || words.contains { fold(item.name).contains($0) }
        }
        NSLog("[CollectionSearch] q=%@ catalogs=%d results=%d", query, targets.count, found.count)
        return found
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

}


/// The system search field: observes only the query box.
private struct CollectionSearchField<Content: View>: View {
    @ObservedObject var queryBox: SearchQueryBox
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical) {
            content()
                .padding(.top, 30)
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, Theme.Spacing.screen)
        }
        .scrollClipDisabled()
        .searchable(text: $queryBox.text, prompt: Text("Rechercher dans la collection"))
    }
}

/// The results under the field: films and series of the folder's « Tous » catalogs, through the
/// add-on's platform-wide search when it has one, else the titles already loaded.
private struct CollectionSearchResults: View {
    @ObservedObject var queryBox: SearchQueryBox
    let tabs: [FolderTab]

    @State private var remote: [MetaPreview]?
    @State private var searchingRemote = false

    var body: some View {
        let query = queryBox.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSearch = CollectionRemoteSearch.hasSearchableCatalogs(tabs)
        let items = canSearch ? (remote ?? []) : CollectionSearchLayer.matches(query: query, tabs: tabs, typeFilter: nil)
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            if query.isEmpty {
                Color.clear.frame(height: 1)
            } else if items.isEmpty, searchingRemote || (canSearch && remote == nil) {
                ProgressView()
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: query) {
            remote = nil
            guard query.count >= 2 else { searchingRemote = false; return }
            searchingRemote = true
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            let found = await CollectionRemoteSearch.search(query: query, tabs: tabs)
            if Task.isCancelled { return }
            remote = found
            searchingRemote = false
        }
    }
}
