import Combine
import SharedCore
import SwiftUI

// Orbit Library (Steven's fork, 2026-10-23): the Library tab rebuilt on Orbit Discover's principle.
// The old page was a stock `ScrollView` + adaptive `LazyVGrid` the focus engine scrolled in jumps,
// laid out at Nuvio's margins. Here:
//  - the header (title, count line, then the List / Type / Sort / filter pills) stays fixed under
//    the Orbit bar, at Orbit's margin;
//  - the grid is ONE focusable stop that takes the presses itself (7 posters a line): Left / Right
//    inside the line, Down / Up one line with the whole grid gliding on one curve, the selected
//    line resting on the grid's second line; Up from the first line goes to the pills;
//  - Menu goes back to the first line, then to the Orbit bar;
//  - a hold opens the selected poster's menu (Mark as Watched / Unwatched, Remove);
//  - back from a title, the selection is the poster it was opened from.
// Data, filters, sort, provider lists and the hold actions are the existing `LibraryViewModel`'s.

enum OrbitLibraryLayout {
    static let columns = 7
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var canvasFocused: Bool
    @State private var index = 0
    /// The poster whose hold menu is open (its index), nil when closed.
    @State private var menuIndex: Int?

    private var entries: [LibraryGridEntry] { model.entries }
    private var line: Int { index / OrbitLibraryLayout.columns }
    private var showsGrid: Bool { !(showingCloud && cloudConnected) && model.content == .grid }

    var body: some View {
        let D = OrbitLibraryLayout.self
        let L = OrbitHomeLayout.self
        let line = self.line
        let restLine = min(line, 1)
        let scroll = CGFloat(restLine - line) * D.pitch
        let lines = entries.isEmpty ? 0 : (entries.count + D.columns - 1) / D.columns
        let window = max(0, line - 2)...max(max(0, line - 2), min(lines - 1, line + 4))

        ZStack(alignment: .topLeading) {
            L.background.ignoresSafeArea()

            if showsGrid {
                ZStack(alignment: .topLeading) {
                    if lines > 0 {
                        ForEach(Array(window), id: \.self) { l in
                            lineView(l)
                                .offset(x: L.margin, y: D.gridTop + scroll + CGFloat(l) * D.pitch)
                                .opacity(l < line - 1 ? 0 : 1)
                                .transition(.identity)
                        }
                    }
                }
                .frame(width: L.screenWidth, height: L.screenHeight, alignment: .topLeading)
                // The lines leaving upward fade out under the header.
                .mask {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: D.gridTop - 44)
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 44)
                        Color.black
                    }
                    .ignoresSafeArea()
                }

                // The grid's one focusable stop. Not a Button: a Button takes the press, so a hold
                // never reached a gesture (and the system context menu opened in the middle of the
                // screen, for the wrong poster). A hold opens the Orbit menu beside the poster.
                Color.clear
                    .frame(width: L.screenWidth, height: L.screenHeight - D.gridTop + 20)
                    .contentShape(Rectangle())
                    .focusable(!entries.isEmpty && menuIndex == nil)
                    .focusEffectDisabled()
                    .focused($canvasFocused)
                    .gesture(ExclusiveGesture(LongPressGesture(minimumDuration: 0.5), TapGesture())
                        .onEnded { value in
                            guard entries.indices.contains(index) else { return }
                            switch value {
                            case .first: openMenu()
                            case .second: onOpen(entries[index].item.toMetaPreview())
                            }
                        })
                .onMoveCommand(perform: move)
                .onExitCommand {
                    if line > 0 {
                        withAnimation(reduceMotion ? nil : OrbitHomeLayout.vertical) { index = index % D.columns }
                        syncLock()
                    } else {
                        NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil)
                    }
                }
                .offset(y: D.gridTop - 20)
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
                .disabled((canvasFocused && line > 0) || menuIndex != nil)

            if let menuIndex, showsGrid, entries.indices.contains(menuIndex) {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                // The held poster stays bright above the dim.
                OrbitLibraryTile(entry: entries[menuIndex], focused: true)
                    .offset(posterOrigin(menuIndex))
                    .allowsHitTesting(false)
                    .transition(.opacity)
                OrbitLibraryHoldMenu(entry: entries[menuIndex],
                                     allowsRemove: model.selectedSectionAllowsRemove,
                                     removeLabel: LibraryGridPolicy.removeLabel(listTitle: model.selectedSectionTitle),
                                     onRemove: {
                                         let entry = entries[menuIndex]
                                         let listKey = model.selectedSectionKey
                                         let listTitle = model.selectedSectionTitle
                                         closeMenu()
                                         model.requestRemove(entry, listKey: listKey, listTitle: listTitle)
                                     },
                                     onClose: closeMenu)
                    .offset(menuOrigin(menuIndex))
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
            }
        }
        .frame(width: L.screenWidth, height: L.screenHeight, alignment: .topLeading)
        .ignoresSafeArea()
        .onChange(of: model.selectedSectionKey) { _, _ in index = 0 }
        .onChange(of: model.selectedType) { _, _ in index = 0 }
        .onChange(of: model.activeSmartFilters) { _, _ in index = 0 }
        .onChange(of: model.effectiveSortOption) { _, _ in index = 0 }
        .onChange(of: entries.count) { _, count in if index >= count { index = max(0, count - 1) } }
        .onChange(of: canvasFocused) { _, _ in syncLock() }
        .onDisappear { OrbitBarLock.shared.set(false) }
    }

    // MARK: Hold menu

    private func openMenu() {
        withAnimation(.easeOut(duration: 0.18)) { menuIndex = index }
    }

    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.15)) { menuIndex = nil }
        DispatchQueue.main.async { canvasFocused = true }
    }

    /// Where poster `i` is drawn on screen (its line's place after the grid's glide).
    private func posterOrigin(_ i: Int) -> CGSize {
        let D = OrbitLibraryLayout.self
        let l = i / D.columns
        let scroll = CGFloat(min(line, 1) - line) * D.pitch
        return CGSize(width: OrbitHomeLayout.margin + CGFloat(i % D.columns) * (D.tileWidth + D.gap),
                      height: D.gridTop + scroll + CGFloat(l) * D.pitch)
    }

    /// The menu beside the poster: on its right, or on its left near the screen's right edge.
    private func menuOrigin(_ i: Int) -> CGSize {
        let D = OrbitLibraryLayout.self
        let poster = posterOrigin(i)
        let width = OrbitLibraryHoldMenu.width
        var x = poster.width + D.tileWidth + 30
        if x + width > OrbitHomeLayout.screenWidth - OrbitHomeLayout.margin {
            x = poster.width - 30 - width
        }
        return CGSize(width: x, height: poster.height + 20)
    }

    private func lineView(_ l: Int) -> some View {
        let D = OrbitLibraryLayout.self
        let start = l * D.columns
        let end = min(entries.count, start + D.columns)
        return ZStack(alignment: .topLeading) {
            if start < end {
                ForEach(start..<end, id: \.self) { i in
                    OrbitLibraryTile(entry: entries[i], focused: canvasFocused && i == index)
                        .offset(x: CGFloat(i - start) * (D.tileWidth + D.gap))
                        .zIndex(i == index ? 1 : 0)
                }
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: D.pitch, alignment: .topLeading)
    }

    // MARK: Input

    private func move(_ direction: MoveCommandDirection) {
        let D = OrbitLibraryLayout.self
        guard !entries.isEmpty else { return }
        var next = index
        switch direction {
        case .left:
            guard index % D.columns > 0 else { return }
            next = index - 1
        case .right:
            guard index % D.columns < D.columns - 1, index + 1 < entries.count else { return }
            next = index + 1
        case .down:
            guard (line + 1) * D.columns < entries.count else { return }
            next = min(entries.count - 1, index + D.columns)
        case .up:
            guard line > 0 else { return }   // the pills take it (unlocked on the first line)
            next = index - D.columns
        @unknown default:
            return
        }
        let vertical = direction == .up || direction == .down
        withAnimation(reduceMotion ? nil : (vertical ? OrbitHomeLayout.vertical : .easeOut(duration: 0.16))) {
            index = next
        }
        syncLock()
    }

    private func syncLock() {
        OrbitBarLock.shared.set(canvasFocused && line > 0)
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
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 4)
        }
        .scaleEffect(focused ? 1.08 : 1)
        .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: 18, y: 10)
    }
}

/// The hold menu: Mark as Watched / Unwatched and Remove, beside the held poster. Menu closes it.
private struct OrbitLibraryHoldMenu: View {
    let entry: LibraryGridEntry
    let allowsRemove: Bool
    let removeLabel: String
    let onRemove: () -> Void
    let onClose: () -> Void

    static let width: CGFloat = 470

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.item.name)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 4)
            TitleHoldMenuItems(preview: entry.item.toMetaPreview(), revision: 0,
                               includesLibraryAction: false, didAct: onClose)
            if allowsRemove {
                Button(role: .destructive, action: onRemove) {
                    Label(removeLabel, systemImage: "trash")
                }
            }
        }
        .buttonStyle(OrbitHoldMenuItemStyle())
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(white: 0.1)))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        .focusSection()
        .onExitCommand(perform: onClose)
    }
}

private struct OrbitHoldMenuItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OrbitHoldMenuItem(configuration: configuration)
    }
}

private struct OrbitHoldMenuItem: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var focused

    var body: some View {
        let destructive = configuration.role == .destructive
        configuration.label
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(focused ? (destructive ? Color.red : Color.black)
                                     : (destructive ? Color(red: 1, green: 0.35, blue: 0.35) : Color.white))
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(Capsule().fill(focused ? Color.white : Color.clear))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}
