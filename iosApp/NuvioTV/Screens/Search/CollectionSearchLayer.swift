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
    /// Pass 2: the add-ons' own platform search, for this folder's catalogs that declare one
    /// (nil until a search has answered; then the results, possibly empty).
    @State private var remote: [MetaPreview]?
    @State private var searchingRemote = false

    var body: some View {
        let query = queryBox.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Pass 3 (Steven): films AND series whatever the Films / Séries tab, only from the
        // « Tous les films / Toutes les séries » catalogs (never Top 10 or Nouveautés), and the
        // add-on's platform-wide search when it has one; the loaded titles only for a folder
        // whose add-on cannot search.
        let canSearch = CollectionRemoteSearch.hasSearchableCatalogs(tabs)
        let items = canSearch ? (remote ?? []) : Self.matches(query: query, tabs: tabs, typeFilter: nil)
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.94).ignoresSafeArea()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    OrbitSearchKeyboard(queryBox: queryBox)
                    if query.isEmpty {
                        EmptyView()
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
                .padding(.top, 140)
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, Theme.Spacing.screen)
            }
            .scrollClipDisabled()
        }
        .ignoresSafeArea()
        .focusSection()
        .onExitCommand { onClose() }
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
                                    posterShape: .poster,
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
