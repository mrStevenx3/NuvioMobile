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
        let local = Self.matches(query: query, tabs: tabs, typeFilter: typeFilter)
        // The add-on search knows the whole platform; the loaded titles fill in for catalogs
        // without one (and while it answers).
        let items = Self.merged(remote ?? [], local)
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.94).ignoresSafeArea()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    OrbitSearchKeyboard(queryBox: queryBox)
                    if query.isEmpty {
                        EmptyView()
                    } else if items.isEmpty, searchingRemote {
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
            let found = await CollectionRemoteSearch.search(query: query, tabs: tabs, typeFilter: typeFilter)
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


/// Steven's fork (collection search, pass 2): asks the folder's add-on catalogs that declare a
/// `search` extra in their manifest (Steven's platform add-ons, v1.1: « Tous les films / Toutes les
/// séries », which keep only titles on the platform) — `…/catalog/<type>/<id>/search=<q>.json`.
enum CollectionRemoteSearch {
    private struct Manifest: Decodable {
        struct Catalog: Decodable {
            struct Extra: Decodable { let name: String }
            let type: String
            let id: String
            let extra: [Extra]?
        }
        let catalogs: [Catalog]?
    }

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

    @MainActor private static var manifests: [String: Manifest] = [:]

    @MainActor
    static func search(query: String, tabs: [FolderTab], typeFilter: String?) async -> [MetaPreview] {
        var targets: [(base: String, type: String, catalogId: String)] = []
        var seen = Set<String>()
        for tab in tabs where !tab.isAllTab {
            guard let manifestUrl = tab.manifestUrl, !manifestUrl.isEmpty,
                  CollectionTypeFilter.keeps(CollectionTypeFilter.effectiveType(declared: tab.type, name: tab.label),
                                             filter: typeFilter) else { continue }
            guard let manifest = await manifest(manifestUrl),
                  manifest.catalogs?.contains(where: { $0.id == tab.catalogId && $0.type == tab.type
                      && ($0.extra ?? []).contains { $0.name == "search" } }) == true else { continue }
            let base = manifestUrl.replacingOccurrences(of: "/manifest.json", with: "")
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
                          let decoded = try? JSONDecoder().decode(Response.self, from: response.0) else { return [] }
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
        return CollectionSearchLayer.merged(lists.flatMap { $0 }, [])
    }

    @MainActor
    private static func manifest(_ urlString: String) async -> Manifest? {
        if let cached = manifests[urlString] { return cached }
        guard let url = URL(string: urlString),
              let response = try? await URLSession.shared.data(from: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: response.0) else { return nil }
        manifests[urlString] = manifest
        return manifest
    }
}
