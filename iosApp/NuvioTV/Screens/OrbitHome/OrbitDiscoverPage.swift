import Combine
import SharedCore
import SwiftUI

// Orbit Discover (Steven's fork, 2026-10-23): the Discover tab's grid rebuilt on Orbit Home's
// principle. The focus engine scrolled the old grid in big jumps ("le défilement qui se fait en
// grand"); here nothing is scrolled by it. The header (title and the Type / Genre / Catalog pills)
// stays fixed under the bar; the grid is ONE focusable stop that takes the presses itself and is
// drawn rather than scrolled:
//  - Left / Right move the selection inside the line;
//  - Down / Up move one line, and the whole grid glides one line on one curve, the selected line
//    resting on the grid's second line (the first one stays in view above it, like the reference);
//  - Select opens the title; Up from the first line goes to the pills.
// Only the lines near the selection exist. The model (`DiscoverGridViewModel`) is unchanged.

enum OrbitDiscoverLayout {
    static let columns = 6
    static let gap: CGFloat = 24
    static let lineGap: CGFloat = 46
    static var tileWidth: CGFloat {
        floor((OrbitHomeLayout.screenWidth - 2 * OrbitHomeLayout.margin - CGFloat(columns - 1) * gap) / CGFloat(columns))
    }
    static var tileHeight: CGFloat { floor(tileWidth * 9 / 16) }
    static var pitch: CGFloat { tileHeight + lineGap }
    /// The header's top (under the bar) and the grid's first line.
    static let headerTop: CGFloat = 116
    static let gridTop: CGFloat = 236
}

struct OrbitDiscoverPage: View {
    @ObservedObject var model: DiscoverGridViewModel
    let onOpen: (MetaPreview) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var canvasFocused: Bool
    @State private var index = 0

    private var items: [MetaPreview] { model.items }
    private var line: Int { index / OrbitDiscoverLayout.columns }

    var body: some View {
        let D = OrbitDiscoverLayout.self
        let L = OrbitHomeLayout.self
        let line = self.line
        // The selected line rests on the second line once the grid has left its top.
        let restLine = min(line, 1)
        let scroll = CGFloat(restLine - line) * D.pitch
        let lines = items.isEmpty ? 0 : (items.count + D.columns - 1) / D.columns
        let window = max(0, line - 2)...max(max(0, line - 2), min(lines - 1, line + 5))

        ZStack(alignment: .topLeading) {
            L.background.ignoresSafeArea()
            // The selected title's art behind the page (Orbit's look, as on Home).
            if items.indices.contains(index) {
                OrbitFocusBackdrop(item: items[index])
                    .ignoresSafeArea()
            }

            // The grid: every line at its own place, all moving on the selection's curve.
            ZStack(alignment: .topLeading) {
                if lines > 0 {
                    ForEach(Array(window), id: \.self) { l in
                        lineView(l, selectedLine: line)
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
                    Color.clear.frame(height: D.gridTop - 40)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 40)
                    Color.black
                }
                .ignoresSafeArea()
            }

            if model.selectedType == nil || model.phase != .loaded {
                statusPanel
                    .padding(.leading, L.margin)
                    .padding(.top, D.gridTop)
            }

            // The page's one focusable stop for the grid, under the header.
            Button { if items.indices.contains(index) { onOpen(items[index]) } } label: {
                Color.clear
                    .frame(width: L.screenWidth, height: L.screenHeight - D.gridTop + 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(OrbitDiscoverCanvasStyle())
            .focused($canvasFocused)
            .disabled(items.isEmpty)
            .onMoveCommand(perform: move)
            // Steven: Menu sent the cursor to the hidden system tab bar (it vanished). Menu now goes
            // back to the first line, then to the bar.
            .onExitCommand {
                if line > 0 {
                    withAnimation(reduceMotion ? nil : OrbitHomeLayout.vertical) { index = index % D.columns }
                    syncLock()
                } else {
                    NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil)
                }
            }
            .offset(y: D.gridTop - 20)

            header
                .padding(.leading, L.margin)
                .padding(.top, D.headerTop)
                // Out of reach while the grid is scrolled (Up is the grid's own).
                .disabled(canvasFocused && line > 0)
        }
        .frame(width: L.screenWidth, height: L.screenHeight, alignment: .topLeading)
        .ignoresSafeArea()
        .onChange(of: model.gridKey) { _, _ in index = 0 }
        .onChange(of: canvasFocused) { _, _ in syncLock() }
        .onDisappear { OrbitBarLock.shared.set(false) }
    }

    private func lineView(_ l: Int, selectedLine: Int) -> some View {
        let D = OrbitDiscoverLayout.self
        let start = l * D.columns
        let end = min(items.count, start + D.columns)
        return ZStack(alignment: .topLeading) {
            if start < end {
                ForEach(start..<end, id: \.self) { i in
                    OrbitDiscoverTile(item: items[i], focused: canvasFocused && i == index)
                        .offset(x: CGFloat(i - start) * (D.tileWidth + D.gap))
                        .zIndex(i == index ? 1 : 0)
                        .onAppear { model.itemAppeared(at: i) }
                }
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: D.pitch, alignment: .topLeading)
    }

    // MARK: Input

    private func move(_ direction: MoveCommandDirection) {
        let D = OrbitDiscoverLayout.self
        guard !items.isEmpty else { return }
        var next = index
        switch direction {
        case .left:
            guard index % D.columns > 0 else { return }
            next = index - 1
        case .right:
            guard index % D.columns < D.columns - 1, index + 1 < items.count else { return }
            next = index + 1
        case .down:
            guard (line + 1) * D.columns < items.count else { return }
            next = min(items.count - 1, index + D.columns)
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
        model.itemAppeared(at: min(items.count - 1, next + D.columns * 3))
        syncLock()
    }

    private func syncLock() {
        OrbitBarLock.shared.set(canvasFocused && line > 0)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 18) {
            Text(headerTitle)
                .font(.system(size: 46, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, 12)
            if let type = model.selectedType {
                PillMenu(title: DiscoverRowsPlan.typeLabel(type),
                         systemImage: "film.stack",
                         selection: Binding(get: { type }, set: { model.select(type: $0) }),
                         options: model.typeOptions,
                         id: "discover.typePicker",
                         pickerTitle: String(localized: "Type"),
                         label: { DiscoverRowsPlan.typeLabel($0) })
            }
            if let option = model.selectedOption, let genres = DiscoverGridPlan.genreChoices(option) {
                let current = DiscoverGridPlan.pillValue(model.selectedGenre)
                let labels = DiscoverGridPlan.genreLabels(genres)
                PillMenu(title: labels[current] ?? DiscoverGridPlan.genreLabel(current),
                         systemImage: "theatermasks",
                         selection: Binding(get: { current }, set: { model.select(genrePill: $0) }),
                         options: genres,
                         id: "discover.genrePicker",
                         pickerTitle: String(localized: "Genre"),
                         label: { labels[$0] ?? DiscoverGridPlan.genreLabel($0) })
            }
            if let type = model.selectedType, let selected = model.selectedOption {
                let catalogs = model.catalogOptions(for: type)
                if catalogs.count > 1 {
                    PillMenu(title: DiscoverRowsPlan.catalogLabel(selected, among: catalogs),
                             systemImage: "square.stack",
                             selection: Binding(get: { selected.key }, set: { model.select(catalogKey: $0) }),
                             options: catalogs.map(\.key),
                             id: "discover.catalogPicker",
                             pickerTitle: String(localized: "Catalog"),
                             label: { key in
                                 catalogs.first { $0.key == key }
                                     .map { DiscoverRowsPlan.catalogLabel($0, among: catalogs) } ?? key
                             })
                }
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth - 2 * OrbitHomeLayout.margin, alignment: .leading)
        .focusSection()
    }

    private var headerTitle: String {
        if let option = model.selectedOption, let genres = DiscoverGridPlan.genreChoices(option), model.selectedGenre != nil {
            let current = DiscoverGridPlan.pillValue(model.selectedGenre)
            return DiscoverGridPlan.genreLabels(genres)[current] ?? DiscoverGridPlan.genreLabel(current)
        }
        return model.selectedType.map { DiscoverRowsPlan.typeLabel($0) } ?? String(localized: "Découvrir")
    }

    @ViewBuilder
    private var statusPanel: some View {
        switch model.phase {
        case .failed:
            HStack(spacing: 24) {
                Text("Impossible de charger Découvrir.")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                Button("Réessayer") { model.retry() }
            }
        case .empty:
            if !model.isLoadingMore {
                Text("Rien ici pour l'instant.")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        default:
            // Loading: the grid's skeleton, so the page never opens on an empty screen.
            OrbitDiscoverSkeleton()
        }
    }
}

/// While the first page loads: two lines of dim tiles in the grid's own places.
private struct OrbitDiscoverSkeleton: View {
    var body: some View {
        let D = OrbitDiscoverLayout.self
        VStack(alignment: .leading, spacing: D.lineGap) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: D.gap) {
                    ForEach(0..<D.columns, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: D.tileWidth, height: D.tileHeight)
                    }
                }
            }
        }
    }
}

/// One title: its landscape art with the logo (or name), the white frame when selected.
struct OrbitDiscoverTile: View {
    let item: MetaPreview
    let focused: Bool

    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        let D = OrbitDiscoverLayout.self
        let size = CGSize(width: D.tileWidth, height: D.tileHeight)
        let info = OrbitInfo.make(item, meta: metaStore.meta(for: item))
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.1)
            // The catalog's landscape art, else TMDB's backdrop, else the poster (a dead link no
            // longer leaves the tile with its title alone).
            let landscape = InlineTrailerCard.landscapeArtworkURL(item)
            let backdrop = metaStore.meta(for: item)?.backdrop
            OrbitImage(url: landscape ?? backdrop,
                       fallback: landscape != nil && backdrop != landscape ? backdrop : item.poster,
                       size: size, placeholder: item.poster, lastResort: item.poster)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            OrbitTitleMark(name: item.name, logo: info.logo,
                           maxSize: CGSize(width: size.width * 0.7, height: size.height * 0.32), textSize: 22,
                           fallbackLogo: info.logoFallback)
                .padding(.leading, 12)
                .padding(.bottom, 10)
            // Where it can be watched, as on Home.
            if let kind = OrbitPlatformBadgeKind.of(metaStore.meta(for: item)) {
                OrbitPlatformBadge(kind: kind, size: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 4)
        }
        .scaleEffect(focused ? 1.08 : 1)
        .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: 18, y: 10)
        // Steven: every tile shows its logo, not only the focused one (looked up once per title).
        .onAppear { metaStore.request([item]) }
    }
}

private struct OrbitDiscoverCanvasStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
