import Combine
import SharedCore
import SwiftUI

// Orbit Library (Steven's fork, 2026-10-23): the Library tab rebuilt for Orbit. The old page was a
// stock `ScrollView` + adaptive `LazyVGrid` the focus engine scrolled in jumps, laid out at Nuvio's
// margins. Here:
//  - the header (title, count line, then the List / Type / Sort / filter pills) stays fixed under
//    the Orbit bar, at Orbit's margin;
//  - every poster is its own Button, so focus moves at the system's own speed and a hold opens
//    the system menu beside the poster (Mark as Watched / Unwatched, Remove), as on every other
//    card. (2026-10-27: the grid is a real scroll view the system moves — Apple's glide, the
//    remote's touch surface — as Discover's.)
//  - Menu goes back to the first line, then to the Orbit bar;
//  - back from a title, the focus is the poster it was opened from.
// Data, filters, sort, provider lists and the hold actions are the existing `LibraryViewModel`'s.
// (A single focusable canvas, as on Discover, made the hold impossible to catch reliably and
// delayed the focus; given up for this page.)

enum OrbitLibraryLayout {
    /// Steven (2026-10-25): larger posters (seven looked lost on the page).
    static let columns = 6
    static let gap: CGFloat = 28
    static let lineGap: CGFloat = 40
    static var tileWidth: CGFloat {
        floor((OrbitHomeLayout.screenWidth - 2 * OrbitHomeLayout.margin - CGFloat(columns - 1) * gap) / CGFloat(columns))
    }
    static var tileHeight: CGFloat { floor(tileWidth * 1.5) }
    static var pitch: CGFloat { tileHeight + lineGap }
    static let headerTop: CGFloat = 112
    static let pillsTop: CGFloat = 186
    static let gridTop: CGFloat = 292
}

struct OrbitLibraryPage<Cloud: View>: View {
    @ObservedObject var model: LibraryViewModel
    let cloudConnected: Bool
    @Binding var showingCloud: Bool
    let onOpen: (MetaPreview) -> Void
    @ViewBuilder let cloudContent: () -> Cloud

    /// The focused poster (nil when the focus is elsewhere).
    @FocusState private var focusedIndex: Int?
    /// The poster the grid is placed for (the focused one, kept when the focus leaves).
    @State private var index = 0

    private var entries: [LibraryGridEntry] { model.entries }
    private var line: Int { index / OrbitLibraryLayout.columns }
    private var showsGrid: Bool { !(showingCloud && cloudConnected) && model.content == .grid }

    /// The poster a title was opened from (back from it, the focus goes there — and only there,
    /// a moment: the system's own landing elsewhere is sent back, as on Home).
    @State private var restoringSince: TimeInterval = 0
    @State private var page = ScrollPosition(edge: .top)

    var body: some View {
        let D = OrbitLibraryLayout.self
        let L = OrbitHomeLayout.self
        let columns = Array(repeating: GridItem(.fixed(D.tileWidth), spacing: D.gap, alignment: .top), count: D.columns)

        ZStack(alignment: .topLeading) {
            L.background.ignoresSafeArea()
            // The focused title's art behind the page (Orbit's look, as on Home).
            if showsGrid, entries.indices.contains(index) {
                OrbitFocusBackdrop(item: entries[index].item.toMetaPreview())
                    .ignoresSafeArea()
            }

            if showsGrid {
                // Steven (2026-10-27: "le nouveau système fluide partout"): real buttons in a grid
                // the system scrolls (touch surface, Apple's own glide), as Discover's.
                ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: D.lineGap) {
                        ForEach(entries.indices, id: \.self) { i in
                            posterButton(i)
                                .zIndex(i == focusedIndex ? 1 : 0)
                                .id(i)
                        }
                    }
                    .padding(.horizontal, L.margin)
                    .padding(.top, 24)
                    .padding(.bottom, 240)
                }
                .scrollClipDisabled()
                .scrollPosition($page)
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, y in
                    if restoringSince == 0, OrbitLibraryReturn.opened == nil { OrbitLibraryReturn.offsetY = y }
                }
                .padding(.top, D.gridTop - 24)
                .onChange(of: model.selectedSectionKey) { _, _ in proxy.scrollTo(0, anchor: .top) }
                .onChange(of: model.selectedType) { _, _ in proxy.scrollTo(0, anchor: .top) }
                }
                // The lines leaving upward fade out under the header.
                .mask {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: D.gridTop - 44)
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 44)
                        Color.black
                    }
                    .ignoresSafeArea()
                }
                .focusSection()
                .defaultFocus($focusedIndex, OrbitLibraryReturn.opened ?? index, priority: .userInitiated)
                .onExitCommand {
                    if index >= D.columns {
                        focusedIndex = index % D.columns
                    } else {
                        NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil)
                    }
                }
            } else if showingCloud && cloudConnected {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 28) { cloudContent() }
                        .frame(width: L.screenWidth - 2 * L.margin, alignment: .topLeading)
                        .padding(.horizontal, L.margin)
                        .padding(.top, 20)
                        .padding(.bottom, 80)
                }
                .scrollClipDisabled()
                .padding(.top, D.gridTop - 20)
                .onExitCommand { NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil) }
            } else {
                statusPanel
                    .padding(.leading, L.margin)
                    .padding(.top, D.gridTop)
            }

            header
                // Out of reach while the grid is scrolled (Up from a lower line stays in the grid).
                .disabled(focusedIndex != nil && line > 0)
        }
        .frame(width: L.screenWidth, height: L.screenHeight, alignment: .topLeading)
        .ignoresSafeArea()
        .background { ViewerInputClockInstaller().frame(width: 0, height: 0) }
        .onChange(of: focusedIndex) { _, new in
            guard let new else { syncLock(); return }
            // Back from a title: the system's landing elsewhere is sent back to its poster.
            if let back = OrbitLibraryReturn.opened, restoringSince > 0,
               !ViewerInputClock.shared.hasInput(since: restoringSince + 0.3) {
                if new != back {
                    DispatchQueue.main.async { focusedIndex = back; keepPage() }
                    return
                }
                keepPage()
            }
            index = new
            syncLock()
        }
        .onAppear {
            guard let back = OrbitLibraryReturn.opened, entries.indices.contains(back) else { return }
            let start = ProcessInfo.processInfo.systemUptime
            restoringSince = start
            index = back
            for delay in [0.0, 0.15, 0.35, 0.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard OrbitLibraryReturn.opened == back, !ViewerInputClock.shared.hasInput(since: start + 0.3) else { return }
                    if focusedIndex != back { focusedIndex = back }
                    keepPage()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                restoringSince = 0
                if OrbitLibraryReturn.opened == back { OrbitLibraryReturn.opened = nil }
            }
        }
        .onChange(of: model.selectedSectionKey) { _, _ in index = 0 }
        .onChange(of: model.selectedType) { _, _ in index = 0 }
        .onChange(of: model.activeSmartFilters) { _, _ in index = 0 }
        .onChange(of: model.effectiveSortOption) { _, _ in index = 0 }
        .onChange(of: entries.count) { _, count in if index >= count { index = max(0, count - 1) } }
        .onDisappear { OrbitBarLock.shared.set(false) }
    }

    private func posterButton(_ i: Int) -> some View {
        let entry = entries[i]
        let preview = entry.item.toMetaPreview()
        return Button {
            OrbitLibraryReturn.opened = i
            onOpen(preview)
        } label: {
            // (Back from a title, only its poster is drawn focused a moment.)
            OrbitLibraryTile(entry: entry, focused: focusedIndex == i
                             && !(restoringSince > 0 && OrbitLibraryReturn.opened != nil && OrbitLibraryReturn.opened != i))
        }
        .buttonStyle(OrbitLibraryPosterStyle())
        .focused($focusedIndex, equals: i)
        // The system hold menu, as on every card (the list-aware Remove after the watched toggle).
        .libraryHoldMenu(preview: preview) {
            let listKey = model.selectedSectionKey
            let listTitle = model.selectedSectionTitle
            if model.selectedSectionAllowsRemove {
                Button(role: .destructive) {
                    model.requestRemove(entry, listKey: listKey, listTitle: listTitle)
                } label: {
                    Label(LibraryGridPolicy.removeLabel(listTitle: listTitle), systemImage: "trash")
                }
            }
        }
    }

    /// The grid exactly where it was when the title was opened.
    private func keepPage() {
        guard let y = OrbitLibraryReturn.offsetY else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { page.scrollTo(y: y) }
    }

    private func syncLock() {
        OrbitBarLock.shared.set(focusedIndex != nil && line > 0)
    }

    // MARK: Header

    private var header: some View {
        let D = OrbitLibraryLayout.self
        let L = OrbitHomeLayout.self
        return ZStack(alignment: .topLeading) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text(String(localized: "Library"))
                    .font(.system(size: 46, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .fixedSize()
                if !(showingCloud && cloudConnected), model.content == .grid, !model.countLine.isEmpty {
                    Text(model.countLine)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
                if let badge = LibraryGridPolicy.sourceBadge(sourceModeName: model.sourceModeName),
                   !(showingCloud && cloudConnected) {
                    Text(badge)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5))
                }
            }
            .padding(.top, D.headerTop)

            pills
                .padding(.top, D.pillsTop)
        }
        .padding(.leading, L.margin)
        .frame(width: L.screenWidth, alignment: .topLeading)
    }

    private var pills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                if cloudConnected {
                    FilterChip(title: String(localized: "Saved"), isActive: !showingCloud) { showingCloud = false }
                    FilterChip(title: String(localized: "Debrid Cloud"), isActive: showingCloud) { showingCloud = true }
                }
                if !(showingCloud && cloudConnected), model.content == .grid || model.content == .noMatches {
                    if model.sections.count > 1 {
                        PillMenu(title: model.selectedSectionTitle ?? String(localized: "List"),
                                 systemImage: "list.bullet",
                                 selection: Binding(get: { model.selectedSectionKey ?? "" },
                                                    set: { model.selectSection($0) }),
                                 options: model.sections.map(\.type),
                                 id: "library.listPicker",
                                 pickerTitle: String(localized: "List"),
                                 label: { key in model.sections.first { $0.type == key }?.displayTitle ?? key })
                    }
                    if model.types.count > 1 {
                        PillMenu(title: model.selectedType.map { LibraryGridPolicy.typeLabel($0) } ?? String(localized: "All"),
                                 systemImage: "film.stack",
                                 selection: Binding(get: { model.selectedType ?? "" },
                                                    set: { model.selectType($0.isEmpty ? nil : $0) }),
                                 options: [""] + model.types,
                                 id: "library.typePicker",
                                 pickerTitle: String(localized: "Type"),
                                 label: { $0.isEmpty ? String(localized: "All") : LibraryGridPolicy.typeLabel($0) })
                    }
                    if !model.availableSortOptions.isEmpty {
                        PillMenu(title: model.sortLabel(model.effectiveSortOption),
                                 systemImage: "arrow.up.arrow.down",
                                 selection: Binding(get: { model.effectiveSortOption }, set: { model.setSort($0) }),
                                 options: model.availableSortOptions,
                                 id: "library.sortPicker",
                                 pickerTitle: String(localized: "Sort"),
                                 label: { model.sortLabel($0) })
                    }
                    ForEach(model.visibleSmartFilters, id: \.self) { filter in
                        FilterChip(title: filter.title, isActive: model.activeSmartFilters.contains(filter)) {
                            model.toggleSmartFilter(filter)
                        }
                    }
                    if model.showsProviderControls {
                        PillButton(title: String(localized: "Refresh"), systemImage: "arrow.clockwise",
                                   id: "library.refresh") { model.refresh() }
                        if model.isLoading { ProgressView() }
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, OrbitHomeLayout.margin)
        }
        .scrollClipDisabled()
        .frame(width: OrbitHomeLayout.screenWidth - OrbitHomeLayout.margin, alignment: .leading)
        .focusSection()
    }

    // MARK: States

    @ViewBuilder
    private var statusPanel: some View {
        switch model.content {
        case .loading:
            OrbitLibrarySkeleton()
        case .failed(let message):
            VStack(alignment: .leading, spacing: 18) {
                Text(LibraryGridPolicy.failedTitle(providerName: model.providerName))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.white)
                Text(message)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .frame(maxWidth: 1100, alignment: .leading)
                PillButton(title: String(localized: "Retry"), systemImage: "arrow.clockwise", id: "library.retry") {
                    model.retry()
                }
            }
            .focusSection()
        case .empty:
            VStack(alignment: .leading, spacing: 14) {
                Text(LibraryGridPolicy.emptyTitle(providerName: model.providerName))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.white)
                Text(LibraryGridPolicy.emptyMessage(providerName: model.providerName))
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        case .noMatches:
            VStack(alignment: .leading, spacing: 18) {
                Text(LibraryGridPolicy.noMatchesTitle)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.white)
                PillButton(title: String(localized: "Clear Filters"), systemImage: "xmark.circle", id: "library.clear") {
                    model.clearSmartFilters()
                }
            }
            .focusSection()
        case .grid:
            EmptyView()
        }
    }
}

/// While the library loads: two lines of dim posters in the grid's own places.
private struct OrbitLibrarySkeleton: View {
    var body: some View {
        let D = OrbitLibraryLayout.self
        VStack(alignment: .leading, spacing: D.lineGap) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: D.gap) {
                    ForEach(0..<D.columns, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: OrbitHomeLayout.posterRadius, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: D.tileWidth, height: D.tileHeight)
                    }
                }
            }
        }
    }
}

/// One saved title: its poster, the watched tick or the progress bar, the white frame when selected.
private struct OrbitLibraryTile: View {
    let entry: LibraryGridEntry
    let focused: Bool
    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        let D = OrbitLibraryLayout.self
        let size = CGSize(width: D.tileWidth, height: D.tileHeight)
        let radius = OrbitHomeLayout.posterRadius
        ZStack {
            Color(white: 0.1)
            OrbitImage(url: entry.item.poster, fallback: entry.item.rawPosterUrl, size: size)
            if (entry.item.poster ?? "").isEmpty, (entry.item.rawPosterUrl ?? "").isEmpty {
                Text(entry.item.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(14)
            }
            PosterWatchBadgeView(badge: PosterWatchBadge(isWatched: entry.state.isWatched,
                                                         progress: entry.state.progress))
            // Where it can be watched, as on Home.
            if let kind = OrbitPlatformBadgeKind.of(metaStore.meta(for: entry.item.toMetaPreview())) {
                OrbitPlatformBadge(kind: kind, size: 15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 14)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 4)
        }
        .scaleEffect(focused ? 1.08 : 1)
        .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: 18, y: 10)
        .animation(.easeOut(duration: 0.14), value: focused)
        .onAppear { metaStore.request([entry.item.toMetaPreview()]) }
    }
}

/// The poster draws its own focus (the white frame and the lift); no system platter.
private struct OrbitLibraryPosterStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}


/// Where the last title was opened from (a generic view cannot hold a static).
@MainActor
enum OrbitLibraryReturn {
    static var opened: Int?
    static var offsetY: CGFloat?
}
