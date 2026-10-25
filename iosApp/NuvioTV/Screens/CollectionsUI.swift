import Combine
import SwiftUI
import UIKit
import SharedCore
// Kotlin's `Collection` model collides with Swift's stdlib `Collection` protocol, and plain
// `SharedCore.Collection` doesn't work either (the framework also exports a *class* named
// `SharedCore`, which wins the qualification). A scoped import shadows the stdlib name in this
// file; the typealias gives the rest of the target an unambiguous name.
import class SharedCore.Collection

/// The shared Kotlin `Collection` model (a group of folders), aliased to dodge the name collision.
typealias NuvioCollection = Collection

// Collections (browse-only, Phase 5b): renders collections curated on mobile — the cloud sync
// already delivers them (SyncManager.pullAllForProfile → CollectionSyncService.pullFromServer).
// A collection appears on Home as a row of folder tiles; a folder opens a tabbed paginated grid
// backed entirely by the shared `FolderDetailRepository`. Structural editing stays on mobile; the
// one on-device edit is a tmdb source's Discover filters (`TmdbFilterEditorView`, from the
// folder grid's Edit Filters button).

/// Navigation value for a collection folder's detail grid. Hashes on the stable ids; carries the
/// titles for the destination's initial render (same wrapper approach as `TitleRoute`).
struct FolderRoute: Hashable {
    let collectionId: String
    let folderId: String
    let folderTitle: String
    /// BUG-38 (folder page): the folder's configured title logo, carried so the page's first
    /// frame already has it — the repository's `folder` lands a beat later. Identity (==/hash)
    /// stays collectionId + folderId; this is display-only. The backdrop is deliberately NOT
    /// drawn on this page (round three, reporter: "if we keep the background image inside, it
    /// makes the text unreadable depending on the image") — it belongs to the Home hero.
    let titleLogoUrl: String?
    /// Steven (device: entering a platform, its page showed — intro already done — before the
    /// intro): each opening is its own page (`.id(openedAt)` on the destination), never the last
    /// visit's view shown again. Not part of the identity (==/hash).
    let openedAt: TimeInterval

    init(collectionId: String, folder: CollectionFolder) {
        self.collectionId = collectionId
        self.folderId = folder.id
        self.folderTitle = folder.title
        self.titleLogoUrl = folder.titleLogoUrl.nonBlankTrimmed
        self.openedAt = ProcessInfo.processInfo.systemUptime
    }

    static func == (lhs: FolderRoute, rhs: FolderRoute) -> Bool {
        lhs.collectionId == rhs.collectionId && lhs.folderId == rhs.folderId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(collectionId)
        hasher.combine(folderId)
    }
}

/// Backs `FolderDetailView`. The shared `FolderDetailRepository` is a singleton keyed by
/// `initialize(collectionId:folderId:)` — one folder screen at a time, `clear()` on exit.
@MainActor
final class FolderDetailViewModel: ObservableObject {
    /// The selected tab's tmdb source when its Discover filters can be edited on-device
    /// (`TmdbFilterEditorView`). Identifiable so it can drive `.fullScreenCover(item:)`.
    struct EditableSource: Identifiable {
        let collectionId: String
        let folderId: String
        /// Index into `folder.resolvedSources` (what `TmdbSourceFilterEditor.begin` takes).
        let sourceIndex: Int
        let title: String
        var id: String { "\(collectionId)|\(folderId)|\(sourceIndex)" }
    }

    @Published private(set) var folderTitle: String
    /// BUG-38 (folder page): `CollectionFolder.titleLogoUrl` as the page title — the key the
    /// Home tile deliberately does NOT draw over a folder's own cover (BUG-52: the logo over a
    /// self-naming cover doubled every wordmark). Blank/whitespace counts as absent, the same
    /// trimming rule the tile applies to every payload URL. The folder's `heroBackdropUrl` is
    /// the HOME hero's business (round three), not this page's.
    @Published private(set) var titleLogoUrl: String?
    @Published private(set) var tabs: [FolderTab] = []
    @Published private(set) var selectedTabIndex = 0
    @Published private(set) var items: [MetaPreview] = []
    @Published private(set) var isLoading = true
    @Published private(set) var canLoadMore = false
    @Published private(set) var tabIsLoading = false
    /// Non-nil when the selected tab is a filter-consuming tmdb source (DISCOVER / COMPANY /
    /// NETWORK — LIST/COLLECTION/PERSON/DIRECTOR ignore Discover filters at resolve time).
    @Published private(set) var editableSource: EditableSource?

    /// Home Stage & Strip (P2 §2.2): the Rows page's strip, one row per source tab (no "All"), built
    /// from EVERY tab's state — `FolderDetailRepository.initialize` already loads each source's first
    /// page concurrently, so this is Swift only. Assigned only when it changes; a row whose equality
    /// key is unchanged keeps its previous instance and section (`FolderRowsPlan.reusing`).
    @Published private(set) var stripRows: [FolderStripRow] = []
    /// P2 §2.2: no source is still on its first load (`!FolderDetailUiState.isLoading`).
    @Published private(set) var allSettled = false
    /// P2 §2.6: one entry per filter-editable source tab (the Rows page's Edit menu); the Grid page
    /// keeps `editableSource`, the selected tab's.
    @Published private(set) var editableSources: [EditableSource] = []
    /// P2 §2.2: the folder's collection, for the Rows page's stage preview (`HomeRowPreviews.folder`).
    /// Read at init, refreshed when the repository's folder changes.
    @Published private(set) var collection: NuvioCollection? = nil

    /// Internal (P2 §2.2): the folder page builds its per-folder layout key from them.
    let collectionId: String
    let folderId: String
    private var watcher: FlowWatcher?
    /// The repository folder `collection` was last refreshed for.
    private var lastFolder: CollectionFolder?
    /// Review r1 (B P3-9): the strip state (rows, sources, settled, collection) is built only while
    /// something shows it: Stage (the Edit band) or a Rows page on either Home layout (Batch F), so
    /// Classic's grid does exactly the per-emission work it did before. `FolderDetailView` sets it
    /// from the live layouts; turning it on builds from the last emission at once.
    var buildsStripState = false {
        didSet {
            guard buildsStripState, !oldValue, let state = lastState else { return }
            applyStripState(state)
        }
    }
    private var lastState: FolderDetailUiState?

    /// The folder this page shows, from `collection` (the route carries only ids and titles).
    var folder: CollectionFolder? {
        collection?.folders.first { $0.id == folderId }
    }

    init(route: FolderRoute) {
        collectionId = route.collectionId
        folderId = route.folderId
        folderTitle = route.folderTitle
        titleLogoUrl = route.titleLogoUrl
        collection = CollectionRepository.shared.getCollection(id: route.collectionId)
    }

    func start() {
        guard watcher == nil else { return }
        watcher = FlowWatcherKt.watch(FolderDetailRepository.shared.uiState) { [weak self] emitted in
            guard let self, let state = emitted as? FolderDetailUiState else { return }
            if let folder = state.folder {
                self.folderTitle = folder.title
                self.titleLogoUrl = folder.titleLogoUrl.nonBlankTrimmed
            }
            self.tabs = state.tabs
            self.selectedTabIndex = Int(state.selectedTabIndex)
            self.items = state.selectedTab?.items ?? []
            self.isLoading = state.isLoading
            self.canLoadMore = state.selectedTabCanLoadMore
            self.tabIsLoading = state.selectedTab?.isLoading ?? false
            self.editableSource = Self.editableSource(
                forTabAt: Int(state.selectedTabIndex),
                in: state,
                collectionId: self.collectionId,
                folderId: self.folderId
            )
            self.lastState = state
            if self.buildsStripState { self.applyStripState(state) }
        }
        FolderDetailRepository.shared.initialize(collectionId: collectionId, folderId: folderId)
    }

    /// P2 §2.2: the Rows page's per-tab state, published only when it changes.
    private func applyStripState(_ state: FolderDetailUiState) {
        // The repository is a singleton: an emission still carrying another folder (before this
        // page's `initialize` replaced it) is never drawn as this folder's rows.
        if let folder = state.folder, folder.id != folderId { return }
        let snapshots = state.tabs.enumerated().map { index, tab in
            FolderTabSnapshot(tab: tab, tabIndex: index)
        }
        let rows = FolderRowsPlan.reusing(
            stripRows,
            for: FolderRowsPlan.rows(snapshots, collectionId: collectionId, folderId: folderId)
        )
        if rows != stripRows { stripRows = rows }
        let settled = !state.isLoading
        if settled != allSettled { allSettled = settled }
        let sources = state.tabs.indices.compactMap { index in
            Self.editableSource(forTabAt: index, in: state, collectionId: collectionId, folderId: folderId)
        }
        if sources.map(\.id) != editableSources.map(\.id) || sources.map(\.title) != editableSources.map(\.title) {
            editableSources = sources
        }
        if let folder = state.folder, folder != lastFolder {
            lastFolder = folder
            let fresh = CollectionRepository.shared.getCollection(id: collectionId)
            if fresh != collection { collection = fresh }
        }
    }

    /// P2 §2.3 (the Rows page's Try Again): clear, then load every source again. `reload()` is not
    /// enough here: `initialize` early-returns on unchanged inputs, so it never refetches a failed tab.
    func retry() {
        FolderDetailRepository.shared.clear()
        FolderDetailRepository.shared.initialize(collectionId: collectionId, folderId: folderId)
    }

    /// Re-runs `initialize` for the same folder after the filter editor saved: the repository's
    /// retained-inputs guard (UX-14) sees the changed `folder` and does a full refetch; when
    /// nothing changed (Cancel) it early-returns and keeps the grid as-is.
    func reload() {
        let previousTab = selectedTabIndex
        FolderDetailRepository.shared.initialize(collectionId: collectionId, folderId: folderId)
        // A full re-init rebuilds the tabs with index 0 selected; put the user back on the tab
        // whose filters they just edited (tabs are built synchronously inside initialize).
        let tabCount = (FolderDetailRepository.shared.uiState.value_ as? FolderDetailUiState)?.tabs.count ?? 0
        if previousTab > 0, previousTab < tabCount {
            FolderDetailRepository.shared.selectTab(index: Int32(previousTab))
        }
    }

    /// Maps tab `tabIndex` back to its `resolvedSources` index. FolderDetailRepository builds
    /// one tab per source, with an "All" tab first when `showAllTab` (`tabIndex = showAll ?
    /// sourceIndex + 1 : sourceIndex`, FolderDetailRepository.kt:278). Addon sources whose
    /// catalog can't be materialised are skipped while building tabs, which would shift the
    /// indices — so the offset result is verified against the folder's sources and corrected by
    /// identity when it doesn't line up. The Grid page asks for the selected tab; the Rows page's
    /// Edit menu (P2 §2.6) for every tab.
    private static func editableSource(
        forTabAt tabIndex: Int,
        in state: FolderDetailUiState,
        collectionId: String,
        folderId: String
    ) -> EditableSource? {
        let tabs = state.tabs
        guard tabs.indices.contains(tabIndex) else { return nil }
        let tab = tabs[tabIndex]
        guard !tab.isAllTab, let source = tab.source, source.isTmdb else { return nil }
        // Same fallback as the shared `CollectionSource.tmdbType()`: unknown/missing → DISCOVER.
        let rawType: String? = source.tmdbSourceType
        let type = (rawType ?? "DISCOVER").uppercased()
        if ["LIST", "COLLECTION", "PERSON", "DIRECTOR"].contains(type) { return nil }

        var sourceIndex = tabIndex - (state.showAllTab ? 1 : 0)
        if let resolved = state.folder?.resolvedSources {
            let aligned = resolved.indices.contains(sourceIndex) && resolved[sourceIndex] == source
            if !aligned, let match = resolved.firstIndex(where: { $0 == source }) {
                sourceIndex = match
            }
        }
        guard sourceIndex >= 0 else { return nil }
        return EditableSource(
            collectionId: collectionId,
            folderId: folderId,
            sourceIndex: sourceIndex,
            title: tab.label
        )
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        // UX-14: `onDisappear` also fires when a pushed title screen merely COVERS this grid —
        // `clear()` here meant popping back rebuilt the grid at the top. `detach()` cancels
        // in-flight loads but keeps the repository's state, so `initialize()`'s same-key
        // early-return preserves the items (and the lazy grid's scroll position) on pop-back.
        // Same UX-13 contract as CatalogGridViewModel.stop() → CatalogRepository.detach().
        FolderDetailRepository.shared.detach()
    }

    func selectTab(_ index: Int) {
        FolderDetailRepository.shared.selectTab(index: Int32(index))
    }

    /// Infinite scroll: page the selected tab when focus nears the end of the grid.
    func itemAppeared(at index: Int) {
        guard canLoadMore, index >= items.count - 8 else { return }
        FolderDetailRepository.shared.loadMoreSelectedTab()
    }
}

#if DEBUG
#endif

// BUG-38 (folder page hero): this screen's title-logo header used to live here as a private
// `FolderHeroTitle` — the folder's `titleLogoUrl` as the page title when it loads (the same
// ArtworkStore path `HeroLogo` in HomeView uses for the Home hero's logo), falling back to plain
// `screenTitle` text until then / when there is none. rc13 (FEAT-40) promoted it to
// `DesignSystem/TitleLogoHeader.swift` — generalized with `alignment`/`textFont`/`slotHeight`
// parameters so `FolderDetailView`'s header (centred, larger, pinned above the grid) and
// `StreamPickerView`'s header (FEAT-42, unchanged leading/screenTitle/pinned layout) share one
// implementation instead of two copies. See that file for the Codex round-1 fixes it carries
// forward; `FolderDetailView.logoSlot` above is the only call site left in this file.

private extension Optional where Wrapped == String {
    /// Blank/whitespace-only payload URLs count as absent — the rule every other cover/logo
    /// check in this file applies (the editor/import path can persist whitespace-only values).
    var nonBlankTrimmed: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

