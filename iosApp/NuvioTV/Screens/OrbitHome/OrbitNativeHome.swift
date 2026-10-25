import Combine
import SharedCore
import SwiftUI

// Orbit Home, native (Steven, 2026-10-25: "dans l'app Apple TV tout paraît ultra fluide"). The
// canvas Home draws the whole page and redraws it on every press; this one is built like Apple's
// own TV app: real rows of real buttons in scroll views, moved by the system's focus engine.
//
//  - Each row is a horizontal ScrollView of buttons: the system slides it (on the GPU), only the
//    two tiles whose focus changed redraw (`@Environment(\.isFocused)` in the tile).
//  - The page is a vertical ScrollView aligned on its rows (`.viewAligned`): the system brings the
//    focused row to the line under the bar itself — no scroll of our own fighting its own.
//  - The hero is a carousel of buttons the system slides too (Left / Right).
//  - The page's own view never redraws on a press — each row keeps its own focus; the colour wash
//    behind the rows follows a small shared object.
//  - Entering a row lands on its first title (Steven's rule), the row back at its start.
//
// Same rows, tiles, Top 10, headings and wash as the canvas Home (`OrbitHomeView` hands them
// over). First version: no trailers in the rows or the hero yet.

/// What the native Home shares between its rows and its wash, outside its page's own state.
@MainActor
final class OrbitNativeHomeState: ObservableObject {
    static let shared = OrbitNativeHomeState()
    /// The focused title's art (the wash's colour comes from it).
    @Published var art: String?
}

struct OrbitNativeHome: View {
    let heroItems: [MetaPreview]
    let rows: [OrbitRow]
    let actions: StageHomeActions
    @Binding var isScrolledDown: Bool

    @FocusState private var heroFocus: Int?
    /// The hero page last focused (Menu comes back to it).
    @State private var heroPage = 0
    /// The page is on its hero (else on a row): the wash shows, the bar locks, Menu goes up.
    @State private var onHero = true

    /// The line under the bar the page aligns its sections on (the bar's band is above it).
    static let topLine: CGFloat = 120
    /// The hero's own height in the column: the first row's heading peeks at the screen's bottom.
    static var heroHeight: CGFloat { OrbitHomeLayout.heroPitch - topLine - sectionGap }
    static let sectionGap: CGFloat = 56

    var body: some View {
        let L = OrbitHomeLayout.self
        ZStack(alignment: .topLeading) {
            OrbitNativeBackdrop(visible: !onHero)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Self.sectionGap) {
                    if !heroItems.isEmpty {
                        hero
                    }
                    ForEach(rows) { row in
                        OrbitNativeRow(row: row, actions: actions, onEnter: { setOnHero(false) })
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, 300)
            }
            // Steven (device: the rows jumped on a quick Up / Down, as if the cursor didn't know
            // where to stop): the system aligns the focused section on the line itself.
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.top, Self.topLine, for: .scrollContent)
            .scrollClipDisabled()

            // Steven's video: the row above showed sliced under the bar. Once off the hero, the
            // band under the bar is the page's dark, melting down to the focused row's line.
            LinearGradient(stops: [.init(color: OrbitHomeLayout.background, location: 0),
                                   .init(color: OrbitHomeLayout.background, location: 0.55),
                                   .init(color: OrbitHomeLayout.background.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: L.screenWidth, height: Self.topLine + 10)
                .opacity(onHero ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: onHero)
                .allowsHitTesting(false)
        }
        .frame(width: L.screenWidth, height: L.screenHeight, alignment: .topLeading)
        .onExitCommand(perform: exitAction)
        .onChange(of: heroFocus) { _, page in
            guard let page else { return }
            heroPage = page
            setOnHero(true)
            if heroItems.indices.contains(page + 1) { OrbitMetaStore.shared.request([heroItems[page + 1]]) }
        }
        .onAppear {
            OrbitBarLock.shared.set(!onHero)
            OrbitMetaStore.shared.request(Array(heroItems.prefix(3)))
        }
        .onDisappear { OrbitBarLock.shared.set(false) }
    }

    // MARK: Hero

    /// Steven (device: the hero no longer changed title): a carousel of buttons, slid by the system.
    /// Its buttons start under the bar (the bar stays reachable above them: Up from the hero).
    private var hero: some View {
        let count = heroItems.count
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(Array(heroItems.enumerated()), id: \.offset) { index, item in
                    Button {
                        actions.push(TitleRoute(preview: item))
                    } label: {
                        OrbitNativeHeroPage(item: item, count: count, index: index)
                    }
                    .buttonStyle(OrbitPlainStyle())
                    .focused($heroFocus, equals: index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .frame(width: OrbitHomeLayout.screenWidth, height: Self.heroHeight)
        .focusSection()
        .defaultFocus($heroFocus, heroPage, priority: .userInitiated)
    }

    // MARK: Moves

    /// Menu: back to the hero from a row; on the hero, to the bar.
    private var exitAction: () -> Void {
        if onHero {
            return { NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil) }
        }
        return { heroFocus = heroPage }
    }

    private func setOnHero(_ value: Bool) {
        guard onHero != value else { return }
        onHero = value
        OrbitBarLock.shared.set(!value)
        if isScrolledDown != !value { isScrolledDown = !value }
    }
}

/// One hero page: the full-screen art and details (drawn from the screen's top, above the button's
/// own frame), focused as its button is.
private struct OrbitNativeHeroPage: View {
    let item: MetaPreview
    let count: Int
    let index: Int
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        OrbitHomeHeroView(item: item, focused: isFocused, count: count, index: index,
                          trailerURL: nil, onTrailerFailure: { _ in }, onTrailerEnded: {})
            .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
            .offset(y: -OrbitNativeHome.topLine)
            .frame(width: OrbitHomeLayout.screenWidth, height: OrbitNativeHome.heroHeight, alignment: .top)
    }
}

/// The colour wash behind the rows (its own view: a new colour redraws only it).
private struct OrbitNativeBackdrop: View {
    let visible: Bool
    @ObservedObject private var state = OrbitNativeHomeState.shared

    var body: some View {
        OrbitRowsBackdrop(url: state.art)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.35), value: visible)
            .ignoresSafeArea()
    }
}

// MARK: - A row

struct OrbitNativeRow: View {
    let row: OrbitRow
    let actions: StageHomeActions
    /// The focus came into this row (from outside it).
    let onEnter: () -> Void

    @FocusState private var focused: String?
    /// The row holds the focus. Steven (device: the headings blinked on every Left / Right): the
    /// focus passes through "none" between two titles of a row — the row lets go only if it stays
    /// gone a moment.
    @State private var holds = false
    /// The last title focused here (its details stay through the passage).
    @State private var shown: String?
    @ObservedObject private var metaStore = OrbitMetaStore.shared

    /// The classic row's open frame becomes 16:9 tiles here (the frame widened on every press).
    private var style: OrbitRowStyle { row.style == .classic ? .landscape : row.style }

    static let infoHeight: CGFloat = 112

    var body: some View {
        let L = OrbitHomeLayout.self
        let T = OrbitTileLayout.self
        let style = style
        let size = T.size(style)
        let shownCard = row.cards.first { $0.id == shown }
        VStack(alignment: .leading, spacing: 14) {
            OrbitRowHeading(title: row.title, isCurrent: holds)
                .padding(.leading, L.margin + 4)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: T.gap(style)) {
                    ForEach(Array(row.cards.enumerated()), id: \.element.id) { index, card in
                        Button {
                            open(card)
                        } label: {
                            OrbitNativeTile(card: card, meta: metaStore.meta(for: card.preview), style: style, rank: index + 1)
                        }
                        .buttonStyle(OrbitPlainStyle())
                        .focused($focused, equals: card.id)
                        .onAppear { OrbitMetaStore.shared.request([card.preview]) }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 34)
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, L.margin, for: .scrollContent)
            .scrollClipDisabled()
            .padding(.vertical, -34)
            .background {
                if style == .ranked {
                    OrbitTop10Band(height: size.height + 140)
                }
            }

            // The focused title's details under the row (large cards carry theirs).
            if style != .cards {
                details(holds ? shownCard : nil)
                    .frame(height: Self.infoHeight, alignment: .topLeading)
                    .padding(.leading, L.margin + 6)
            }
        }
        .focusSection()
        // Steven: coming into a row lands on its first title (the row back at its start).
        .defaultFocus($focused, row.cards.first?.id, priority: .userInitiated)
        .onChange(of: focused) { _, new in
            guard let new else {
                // Gone for good, or only passing between two titles?
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    if focused == nil, holds { holds = false }
                }
                return
            }
            if !holds {
                holds = true
                onEnter()
            }
            shown = new
            guard let index = row.cards.firstIndex(where: { $0.id == new }) else { return }
            let card = row.cards[index]
            OrbitNativeHomeState.shared.art = card.landscape ?? metaStore.meta(for: card.preview)?.backdrop
            let ahead = row.cards[index..<min(row.cards.count, index + 6)].map(\.preview)
            OrbitMetaStore.shared.request(Array(ahead))
        }
    }

    @ViewBuilder
    private func details(_ card: OrbitCard?) -> some View {
        if let card {
            let saga = card.id.hasPrefix("saga:")
            let info = OrbitInfo.make(card.preview, meta: saga ? nil : metaStore.meta(for: card.preview))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Text(card.preview.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    if saga {
                        Text(card.preview.releaseInfo ?? "")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                    } else {
                        OrbitMetaLine(info: info, size: 24)
                    }
                }
                .frame(height: 34)
                Text(saga ? (card.preview.description_ ?? "") : info.synopsis)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineSpacing(3)
                    .lineLimit(2)
                    .frame(width: 1100, alignment: .topLeading)
            }
            .id(card.id)
            .transition(.opacity.animation(.easeInOut(duration: 0.18)))
        }
    }

    private func open(_ card: OrbitCard) {
        if let entry = card.entry {
            actions.resume(ResumeTarget(entry: entry))
        } else {
            actions.push(TitleRoute(preview: card.preview))
        }
    }
}

/// One tile, drawn focused as its button is (only the tiles whose focus changed redraw).
private struct OrbitNativeTile: View {
    let card: OrbitCard
    let meta: OrbitMeta?
    let style: OrbitRowStyle
    let rank: Int
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Group {
            switch style {
            case .landscape, .classic:
                OrbitLandscapeTile(card: card, meta: meta, focused: isFocused)
            case .cards:
                OrbitBigCard(card: card, meta: meta, focused: isFocused,
                             trailerURL: nil, onTrailerFailure: { _ in }, onTrailerEnded: {})
            case .ranked:
                OrbitRankedTile(card: card, meta: meta, rank: rank, focused: isFocused)
            case .posters:
                OrbitSmallPoster(card: card, meta: meta, focused: isFocused)
            case .sagas:
                OrbitSmallPoster(card: card, meta: meta, focused: isFocused, size: OrbitTileLayout.sagaPoster)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}
