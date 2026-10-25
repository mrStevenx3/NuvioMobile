import Combine
import SharedCore
import SwiftUI

// Orbit Home, native (Steven, 2026-10-25: "dans l'app Apple TV tout paraît ultra fluide"). The
// canvas Home draws the whole page and redraws it on every press; this one is built like Apple's
// own TV app: real rows of real buttons in scroll views, moved by the system's focus engine.
//
//  - Each row is a horizontal ScrollView of buttons: the system slides it (on the GPU), only the
//    two tiles whose focus changed redraw (`@Environment(\.isFocused)` in the tile).
//  - The page is a vertical ScrollView: the focused row is brought to its line under the bar.
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

    @State private var heroIndex = 0
    @FocusState private var heroFocused: Bool
    /// The page is on its hero (else on a row): the wash shows, the bar locks, Menu goes up.
    @State private var onHero = true
    /// Where the page is brought to (the hero, or a row's line).
    @State private var scrollTarget: String?

    private static let rowLine: CGFloat = 130

    var body: some View {
        let L = OrbitHomeLayout.self
        ZStack(alignment: .topLeading) {
            OrbitNativeBackdrop(visible: !onHero)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 56) {
                        if !heroItems.isEmpty {
                            hero
                                .id("hero")
                        }
                        ForEach(rows) { row in
                            OrbitNativeRow(row: row, actions: actions, onEnter: { enter(row.id) })
                                .overlay(alignment: .top) {
                                    // The row's line: its heading this far under the screen's top.
                                    Color.clear.frame(width: 1, height: 1)
                                        .alignmentGuide(.top) { $0[.top] + Self.rowLine }
                                        .id("line-\(row.id)")
                                }
                                .id(row.id)
                        }
                    }
                    .padding(.bottom, 240)
                }
                .scrollClipDisabled()
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.4)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
        }
        .frame(width: L.screenWidth, height: L.screenHeight, alignment: .topLeading)
        .onExitCommand(perform: exitAction)
        .onChange(of: heroFocused) { _, focused in
            guard focused else { return }
            setOnHero(true)
            scrollTarget = "hero"
        }
        .onAppear {
            OrbitBarLock.shared.set(!onHero)
            OrbitMetaStore.shared.request(Array(heroItems.prefix(3)))
        }
        .onDisappear { OrbitBarLock.shared.set(false) }
    }

    // MARK: Hero

    private var hero: some View {
        let L = OrbitHomeLayout.self
        let count = heroItems.count
        let item = heroItems[heroIndex % max(1, count)]
        return Button {
            actions.push(TitleRoute(preview: item))
        } label: {
            OrbitNativeHeroContent(item: item, count: count, index: heroIndex % max(1, count))
        }
        .buttonStyle(OrbitPlainStyle())
        .focused($heroFocused)
        .onMoveCommand { direction in
            guard count > 1 else { return }
            switch direction {
            case .left: withAnimation(L.horizontal) { heroIndex = (heroIndex - 1 + count) % count }
            case .right: withAnimation(L.horizontal) { heroIndex = (heroIndex + 1) % count }
            default: return
            }
            OrbitMetaStore.shared.request([heroItems[(heroIndex + 1) % count]])
        }
        // The hero is drawn full screen; the first row's heading peeks over its bottom.
        .frame(height: L.heroPitch - 56, alignment: .top)
    }

    // MARK: Moves

    /// Menu: back to the hero from a row; on the hero, to the bar.
    private var exitAction: () -> Void {
        if onHero {
            return { NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil) }
        }
        return { goTop() }
    }

    private func enter(_ rowID: String) {
        setOnHero(false)
        scrollTarget = "line-\(rowID)"
    }

    private func goTop() {
        heroFocused = true
    }

    private func setOnHero(_ value: Bool) {
        guard onHero != value else { return }
        onHero = value
        OrbitBarLock.shared.set(!value)
        if isScrolledDown != !value { isScrolledDown = !value }
    }
}

/// The hero's art and details, focused as the button it sits in is.
private struct OrbitNativeHeroContent: View {
    let item: MetaPreview
    let count: Int
    let index: Int
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        OrbitHomeHeroView(item: item, focused: isFocused, count: count, index: index,
                          trailerURL: nil, onTrailerFailure: { _ in }, onTrailerEnded: {})
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
    @ObservedObject private var metaStore = OrbitMetaStore.shared

    /// The classic row's open frame becomes 16:9 tiles here (the frame widened on every press).
    private var style: OrbitRowStyle { row.style == .classic ? .landscape : row.style }

    static let infoHeight: CGFloat = 112

    var body: some View {
        let L = OrbitHomeLayout.self
        let T = OrbitTileLayout.self
        let style = style
        let size = T.size(style)
        let focusedCard = row.cards.first { $0.id == focused }
        VStack(alignment: .leading, spacing: 14) {
            OrbitRowHeading(title: row.title, isCurrent: focused != nil)
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
                .padding(.horizontal, L.margin)
                .padding(.vertical, 34)
            }
            .scrollClipDisabled()
            .padding(.vertical, -34)
            .background {
                if style == .ranked {
                    OrbitTop10Band(height: size.height + 140)
                }
            }

            // The focused title's details under the row (large cards carry theirs).
            if style != .cards {
                details(focusedCard)
                    .frame(height: Self.infoHeight, alignment: .topLeading)
                    .padding(.leading, L.margin + 6)
            }
        }
        .focusSection()
        // Steven: coming into a row lands on its first title (the row back at its start).
        .defaultFocus($focused, row.cards.first?.id, priority: .userInitiated)
        .onChange(of: focused) { old, new in
            guard let new, let index = row.cards.firstIndex(where: { $0.id == new }) else { return }
            if old == nil { onEnter() }
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
