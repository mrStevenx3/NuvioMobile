import Combine
import SharedCore
import SwiftUI
import UIKit

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
    /// When the menu last closed: the Select that closed it must not open the title.
    @State private var menuClosedAt = Date.distantPast
    @FocusState private var menuFocus: Int?

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

                // The grid's one focusable stop (a Button: Select opens at once). A hold is caught
                // by `OrbitHoldCatcher` (a gesture on the Button never fired, and a focusable view
                // with a gesture delayed every Select by the hold's wait).
                Button {
                    guard menuIndex == nil, Date().timeIntervalSince(menuClosedAt) > 0.4,
                          entries.indices.contains(index) else { return }
                    onOpen(entries[index].item.toMetaPreview())
                } label: {
                    Color.clear
                        .frame(width: L.screenWidth, height: L.screenHeight - D.gridTop + 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(OrbitLibraryCanvasStyle())
                .focused($canvasFocused)
                .disabled(entries.isEmpty || menuIndex != nil)
                .background(OrbitHoldCatcher {
                    guard canvasFocused, menuIndex == nil, entries.indices.contains(index) else { return }
                    openMenu()
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
                holdMenu(entries[menuIndex])
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
        // The menu's first item takes the focus once it is on screen.
        DispatchQueue.main.async { menuFocus = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { if menuIndex != nil, menuFocus == nil { menuFocus = 0 } }
    }

    private func closeMenu() {
        menuClosedAt = Date()
        withAnimation(.easeOut(duration: 0.15)) { menuIndex = nil }
        menuFocus = nil
        DispatchQueue.main.async { canvasFocused = true }
    }

    /// The hold menu beside the poster: Mark as Watched / Unwatched and Remove. Up / Down inside,
    /// Menu closes it.
    private func holdMenu(_ entry: LibraryGridEntry) -> some View {
        let preview = entry.item.toMetaPreview()
        let isSeries = TitleHoldMenuPolicy.isSeries(type: preview.type)
        let isWatched = TitleHoldMenuItems.liveWatched(preview, isSeries: isSeries)
        return VStack(alignment: .leading, spacing: 6) {
            Text(entry.item.name)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 4)
            Button {
                TitleHoldMenuItems(preview: preview, revision: 0, includesLibraryAction: false, didAct: {})
                    .performWatchedAction(labelIsWatched: isWatched, isSeries: isSeries)
                closeMenu()
            } label: {
                Label(TitleHoldMenuPolicy.watchedLabel(isWatched: isWatched, isSeries: isSeries),
                      systemImage: TitleHoldMenuPolicy.watchedIcon(isWatched: isWatched))
            }
            .focused($menuFocus, equals: 0)
            if model.selectedSectionAllowsRemove {
                Button(role: .destructive) {
                    let listKey = model.selectedSectionKey
                    let listTitle = model.selectedSectionTitle
                    closeMenu()
                    model.requestRemove(entry, listKey: listKey, listTitle: listTitle)
                } label: {
                    Label(LibraryGridPolicy.removeLabel(listTitle: model.selectedSectionTitle), systemImage: "trash")
                }
                .focused($menuFocus, equals: 1)
            }
        }
        .buttonStyle(OrbitHoldMenuItemStyle())
        .padding(14)
        .frame(width: Self.menuWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(white: 0.1)))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        .focusSection()
        .onExitCommand(perform: closeMenu)
    }

    static var menuWidth: CGFloat { 470 }

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
        let width = Self.menuWidth
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

private struct OrbitLibraryCanvasStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// Catches a hold of Select (0.5 s) anywhere in the window while mounted: a gesture recognizer on
/// the window sees the presses of whatever is focused (the grid's Button), which SwiftUI's own
/// gestures on that Button never did. The page checks that the grid has the focus.
struct OrbitHoldCatcher: UIViewRepresentable {
    let onHold: () -> Void

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onHold = onHold
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) { view.onHold = onHold }

    final class CatcherView: UIView {
        var onHold: (() -> Void)?
        private var recognizer: UILongPressGestureRecognizer?
        private weak var attachedWindow: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let recognizer, let attachedWindow { attachedWindow.removeGestureRecognizer(recognizer) }
            recognizer = nil
            attachedWindow = nil
            guard let window else { return }
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
            hold.allowedTouchTypes = []
            hold.minimumPressDuration = 0.5
            hold.cancelsTouchesInView = false
            window.addGestureRecognizer(hold)
            recognizer = hold
            attachedWindow = window
        }

        @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
            if recognizer.state == .began { onHold?() }
        }
    }
}
