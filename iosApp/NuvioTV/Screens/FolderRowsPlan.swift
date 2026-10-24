import Foundation
import SharedCore

/// FEAT-71 (Steven, beta.19-rc4 verdict 2026-10-16: the Rows / Grid option "shouldn't remain visible
/// on the first row of the Home screen"): the Layout choice lives in Settings › Home Screen ›
/// Collections Layout. The rc3/rc4 per-folder store (`folder_layout_grid`, written by the band's
/// picker) is gone with the picker; a stale value under that key is ignored (review r1 P2-1). The
/// synced `Collection.viewMode` stays ignored on TV: its default is `TABBED_GRID`, so it cannot
/// tell "chose grid" from "never touched".
nonisolated enum FolderLayoutDefault: String, CaseIterable, Sendable {
    case rows
    case grid

    /// The `UserDefaults` key (device-local `@AppStorage`, not synced), like `home_layout`.
    static let defaultsKey = "folder_layout_default"
    /// Rows, the Stage folder page as it shipped.
    static let defaultValue: FolderLayoutDefault = .rows
    /// Batch F (Steven rc6 17:30Z: Rows or Grid on Classic too): Classic's own default, stored
    /// apart so Classic keeps today's grid until the viewer chooses Rows there.
    static let classicDefaultsKey = "folder_layout_default_classic"
    static let classicDefaultValue: FolderLayoutDefault = .grid

    static func defaultsKey(for layout: HomeLayout) -> String {
        layout == .classic ? classicDefaultsKey : defaultsKey
    }

    static func defaultValue(for layout: HomeLayout) -> FolderLayoutDefault {
        layout == .classic ? classicDefaultValue : defaultValue
    }

    /// The stored default for `layout`; unset or unknown reads as that layout's default.
    static func current(for layout: HomeLayout, defaults: UserDefaults = .standard) -> FolderLayoutDefault {
        guard let raw = defaults.string(forKey: defaultsKey(for: layout)) else { return defaultValue(for: layout) }
        return FolderLayoutDefault(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            ?? defaultValue(for: layout)
    }

    /// nil, blank or unknown resolves to `defaultValue`. The views store the enum itself through
    /// `@AppStorage` (a `String` raw value), so this is for raw readers such as tests and tooling.
    static func resolve(_ raw: String?) -> FolderLayoutDefault {
        guard let raw else { return defaultValue }
        return FolderLayoutDefault(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            ?? defaultValue
    }

    var isGrid: Bool { self == .grid }

    /// The Settings picker label ("Rows" and "Grid" already exist in the string catalog).
    var label: String {
        switch self {
        case .rows: String(localized: "Rows")
        case .grid: String(localized: "Grid")
        }
    }
}

// MARK: - Per-tab snapshot (§2.3)

/// One `FolderTab` as the Rows page reads it. The view model builds it from the repository state
/// (`init(tab:tabIndex:)`); the tests build it directly.
nonisolated struct FolderTabSnapshot {
    /// Where the row's See All goes: `getCatalogSectionsForRows`'s two target kinds
    /// (`FolderDetailRepository.kt:556–576`).
    nonisolated enum Target: Equatable {
        /// TMDB and Trakt tabs: the folder source itself.
        case collectionSource(sourceKey: String, contentType: String, supportsPagination: Bool)
        /// Add-on tabs whose add-on is installed.
        case addon(manifestUrl: String, contentType: String, catalogId: String, genre: String?,
                   supportsPagination: Bool)
    }

    /// The tab's index in `FolderDetailUiState.tabs` ("All" included when the folder shows it).
    let tabIndex: Int
    let label: String
    let typeLabel: String
    let isAllTab: Bool
    let isLoading: Bool
    let items: [MetaPreview]
    let error: String?
    let canLoadMore: Bool
    /// nil when no target can be built (an add-on tab whose add-on is missing, a direct source
    /// with no route key); such a tab never shows posters.
    let target: Target?
}

extension FolderTabSnapshot {
    /// Steven's fork (genre rows): a source filtered to a genre is titled by the genre alone
    /// ("Action", not "Tous les films · Action").
    var displayLabel: String {
        if case .addon(_, _, _, let genre?, _)? = target, !genre.isEmpty { return genre }
        // Pass 2 (Steven): no "(Movies)" / "(Series)" suffix — the collection bar already says
        // which kind is shown. The shared label is "<name> (<typeLabel>)<genre suffix>".
        let suffix = " (\(typeLabel))"
        if !typeLabel.isEmpty, let range = label.range(of: suffix) {
            return label.replacingCharacters(in: range, with: "")
        }
        return label
    }

    /// Steven's fork (collection bar): the tab's catalog type, from its target.
    var contentType: String? {
        switch target {
        case .collectionSource(_, let contentType, _)?: return contentType
        case .addon(_, let contentType, _, _, _)?: return contentType
        case nil: return nil
        }
    }

    /// The view model's mapping, exactly `getCatalogSectionsForRows`'s target rule: TMDB and Trakt
    /// tabs need their `sourceKey`, add-on tabs their `manifestUrl`.
    init(tab: FolderTab, tabIndex: Int) {
        let direct = tab.source.map { $0.isTmdb || $0.isTrakt } ?? false
        var target: Target?
        if direct {
            if let sourceKey = tab.sourceKey {
                target = .collectionSource(sourceKey: sourceKey,
                                           contentType: tab.type,
                                           supportsPagination: tab.supportsPagination)
            }
        } else if let manifestUrl = tab.manifestUrl {
            target = .addon(manifestUrl: manifestUrl,
                            contentType: tab.type,
                            catalogId: tab.catalogId,
                            genre: tab.genre,
                            supportsPagination: tab.supportsPagination)
        }
        self.init(tabIndex: tabIndex,
                  label: tab.label,
                  typeLabel: tab.typeLabel,
                  isAllTab: tab.isAllTab,
                  isLoading: tab.isLoading,
                  items: tab.items,
                  error: tab.error,
                  canLoadMore: tab.canLoadMore,
                  target: target)
    }
}

// MARK: - Row model (§2.3)

// The row model, the visibility rule, the initial focus wait and the page states live in
// `StripRowsPlan.swift` (shared with other strip pages). The folder page keeps its old names.
typealias FolderRowStatus = StripRowStatus
/// One strip row: one source tab of the folder (`order` is the tab index). See `StripRow`.
typealias FolderStripRow = StripRow

nonisolated enum FolderRowsPlan {
    static var previewLimit: Int { StripRowsPlan.previewLimit }
    static var skeletonCount: Int { StripRowsPlan.skeletonCount }
    typealias PageState = StripRowsPlan.PageState

    /// The strip key of tab `tabIndex`, which is also its section key (see `FolderStripRow`). The
    /// tab INDEX, not the label (`getCatalogSectionsForRows` keys on the label), so two sources with
    /// the same label never collide.
    static func rowKey(folderId: String, tabIndex: Int) -> String {
        "folder_\(folderId)_\(tabIndex)"
    }

    static func itemKey(_ item: MetaPreview) -> String { StripRowsPlan.itemKey(item) }

    static func status(_ t: FolderTabSnapshot) -> FolderRowStatus {
        if !t.items.isEmpty, t.target != nil { return .loaded }
        if t.isLoading { return .loading }
        if t.error != nil { return .failed }
        return .empty
    }

    /// The row's section, mirroring `getCatalogSectionsForRows` with two differences: the key is the
    /// tab index, and the items are trimmed to `previewLimit` (`availableItemCount` keeps the full
    /// count, so See All still shows). nil unless the tab has items and a target. Every Kotlin
    /// argument is passed: Kotlin defaults do not reach Swift.
    static func section(_ t: FolderTabSnapshot, collectionId: String, folderId: String) -> HomeCatalogSection? {
        guard !t.items.isEmpty, let target = t.target else { return nil }
        let catalogTarget: any CatalogTarget
        switch target {
        case .collectionSource(let sourceKey, let contentType, let supportsPagination):
            catalogTarget = CatalogTargetCollectionSource(collectionId: collectionId,
                                                          folderId: folderId,
                                                          sourceKey: sourceKey,
                                                          contentType: contentType,
                                                          supportsPagination: supportsPagination)
        case .addon(let manifestUrl, let contentType, let catalogId, let genre, let supportsPagination):
            catalogTarget = CatalogTargetAddon(manifestUrl: manifestUrl,
                                               contentType: contentType,
                                               catalogId: catalogId,
                                               genre: genre,
                                               search: nil,
                                               supportsPagination: supportsPagination)
        }
        return HomeCatalogSection(key: rowKey(folderId: folderId, tabIndex: t.tabIndex),
                                  title: t.displayLabel,
                                  subtitle: t.typeLabel,
                                  // Empty, so the Stage heading's "· add-on" suffix (W2-A) never
                                  // shows on a folder row.
                                  addonName: "",
                                  target: catalogTarget,
                                  items: Array(t.items.prefix(previewLimit)),
                                  availableItemCount: Int32(t.items.count),
                                  hasMore: t.canLoadMore)
    }

    /// One row per source tab, in tab order. The "All" tab is omitted (Rows mode has no merged row).
    static func rows(_ tabs: [FolderTabSnapshot], collectionId: String, folderId: String) -> [FolderStripRow] {
        tabs.filter { !$0.isAllTab }.map { t in
            let rowStatus = status(t)
            let rowSection = rowStatus == .loaded ? section(t, collectionId: collectionId, folderId: folderId) : nil
            return FolderStripRow(id: rowKey(folderId: folderId, tabIndex: t.tabIndex),
                                  order: t.tabIndex,
                                  heading: t.displayLabel,
                                  status: rowStatus,
                                  section: rowSection,
                                  itemKeys: rowStatus == .loaded ? t.items.prefix(previewLimit).map(itemKey) : [],
                                  itemCount: t.items.count,
                                  hasMore: t.canLoadMore,
                                  contentType: t.contentType)
        }
    }

    // Forwarders to `StripRowsPlan` (the folder page's names, unchanged behaviour).

    static func reusing(_ previous: [FolderStripRow], for next: [FolderStripRow]) -> [FolderStripRow] {
        StripRowsPlan.reusing(previous, for: next)
    }

    /// The focused TAB's index is the row `order` on the folder page.
    static func visible(_ rows: [FolderStripRow], focusedTabIndex: Int?) -> [FolderStripRow] {
        StripRowsPlan.visible(rows, focusedOrder: focusedTabIndex)
    }

    static func firstFocusable(_ rows: [FolderStripRow]) -> FolderStripRow? {
        StripRowsPlan.firstFocusable(rows)
    }

    static var initialFocusWaitLimit: TimeInterval { StripRowsPlan.initialFocusWaitLimit }

    static func initialFocusTarget(_ rows: [FolderStripRow], waitOver: Bool) -> FolderStripRow? {
        StripRowsPlan.initialFocusTarget(rows, waitOver: waitOver)
    }

    static func focusablePosition(of rowId: String, in rows: [FolderStripRow]) -> Int? {
        StripRowsPlan.focusablePosition(of: rowId, in: rows)
    }

    static func pageState(_ rows: [FolderStripRow], allSettled: Bool) -> PageState {
        StripRowsPlan.pageState(rows, allSettled: allSettled)
    }

    static func nonBlank(_ value: String?) -> String? { StripRowsPlan.nonBlank(value) }

    /// §2.4: the stage preview of a folder with neither a backdrop nor a logo, for which
    /// `HomeRowPreviews.folder` returns nil (Home keeps the previous title for such a folder, but the
    /// folder's own page must still open on the folder). The same id and type as the Home preview
    /// (`nuvio-folder://…`, `nuvio.folder`, so `isCollectionHero` gates trailers and enrichment), the
    /// folder title as its name, the collection title as the meta line, `folderHeroDescription` as
    /// the synopsis when `showsDetails` (B1, Show Catalog Details in Headings; nil when off, the
    /// default), and no artwork at all.
    @MainActor
    static func plainFolderPreview(collection: NuvioCollection, folder: CollectionFolder, showsDetails: Bool) -> MetaPreview {
        MetaPreview(
            id: "\(collectionHeroIdScheme)\(collection.id)/\(folder.id)",
            type: collectionHeroType,
            name: folder.title.trimmingCharacters(in: .whitespacesAndNewlines),
            poster: nil,
            banner: nil,
            logo: nil,
            posterShape: .poster,
            description: showsDetails ? HomeView.folderHeroDescription(collection: collection, folder: folder) : nil,
            releaseInfo: collection.title.trimmingCharacters(in: .whitespacesAndNewlines),
            rawReleaseDate: nil,
            popularity: nil,
            voteCount: nil,
            imdbRating: nil,
            genres: [],
            rawPosterUrl: nil,
            landscapePoster: nil,
            rawLandscapePosterUrl: nil,
            customPosterApplied: false
        )
    }
}

