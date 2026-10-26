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
    /// On screen (the other Home stays built, hidden: no trailer, no bar lock).
    var active: Bool = true

    @FocusState private var heroFocus: Int?
    /// The trailer (hero, classic frame, large cards) — a reference, never observed by the page.
    @State private var trailers = OrbitNativeTrailerHost()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The hero page last focused (Menu comes back to it).
    @State private var heroPage = 0
    /// The page is on its hero (else on a row): the wash shows, the bar locks, Menu goes up.
    @State private var onHero = true
    /// The section the page is aligned on (the system scrolls to it, on its own curve).
    @State private var position: String? = "hero"
    /// The row holding the focus (its heading lit, its details shown) — set by the page, so a
    /// row's own focus passing through "none" between two titles never dims it.
    @State private var currentRow: String?

    /// The line under the bar the page aligns its sections on (the bar's band is above it).
    static let topLine: CGFloat = 120
    /// The hero's own height in the column. Steven: the hero takes the whole screen (no sliver of
    /// the first row under it).
    /// (Steven: then Down no longer left the hero — the lazy column never built a first row wholly
    /// off screen, so the focus had nowhere to go. Its top edge stays on the screen's last points,
    /// where nothing of it shows.)
    static var heroHeight: CGFloat { OrbitHomeLayout.screenHeight - topLine - sectionGap - 2 }
    /// (Steven: 12 points taken from here went above the details, so the rows stay in place.)
    static let sectionGap: CGFloat = 44

    var body: some View {
        let L = OrbitHomeLayout.self
        ZStack(alignment: .topLeading) {
            OrbitNativeBackdrop(visible: !onHero)

            // Steven (device, 2026-10-26: "le défilement dans le studio fonctionne parfaitement, il
            // faut mettre ce défilement partout"): the studio page's scroll — a vertical scroll view
            // aligned on its rows, the page bringing the focused row to the line on one curve. Touch
            // and Up to the bar are the system's again.
            ScrollView(.vertical, showsIndicators: false) {
                // Steven (device: now and then Up jumped in one go): a lazy column guesses the height
                // of the rows it hasn't built yet and corrects it as one is built on the way up — the
                // jump. A dozen rows are built once, at their real heights (each row stays lazy along).
                VStack(alignment: .leading, spacing: Self.sectionGap) {
                    if !heroItems.isEmpty {
                        hero
                            // Steven (a strip of the hero under the bar once in the rows): its art runs
                            // past its frame — cut to its frame while the rows hold the focus (a mask,
                            // not a fade: Up must still reach it).
                            .mask {
                                Rectangle()
                                    .frame(width: OrbitHomeLayout.screenWidth,
                                           height: onHero ? OrbitHomeLayout.screenHeight * 3 : Self.heroHeight)
                            }
                            .id("hero")
                    }
                    ForEach(rows) { row in
                        OrbitNativeRow(row: row, isCurrent: currentRow == row.id, actions: actions, trailers: trailers,
                                       onEnter: { enter(row.id) })
                            .id(row.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, 300)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .top)
            .contentMargins(.top, Self.topLine, for: .scrollContent)
            .scrollClipDisabled()

            // Off the hero, the band under the bar is the page's own ground and wash (the rows above
            // slide under it; Steven: no dark band, the wash reaches the top, no hero left showing).
            OrbitNativeTopCover()
                .opacity(onHero ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: onHero)
        }
        .frame(width: L.screenWidth, height: L.screenHeight, alignment: .topLeading)
        .onExitCommand(perform: exitAction)
        .onChange(of: heroFocus) { _, page in
            guard let page else {
                // Gone up to the bar (not down to a row): the hero's trailer stops.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if heroFocus == nil, currentRow == nil { trailers.stop() }
                }
                return
            }
            if heroItems.indices.contains(page) {
                let item = heroItems[page]
                trailers.arm("hero|\(item.type):\(item.id)", item: item, reduceMotion: reduceMotion)
            }
            heroPage = page
            currentRow = nil
            setOnHero(true)
            if position != "hero" { withAnimation(.easeInOut(duration: 0.32)) { position = "hero" } }
            if heroItems.indices.contains(page + 1) { OrbitMetaStore.shared.request([heroItems[page + 1]]) }
        }
        .onChange(of: active) { _, now in
            if now {
                trailers.suspended = false
                OrbitBarLock.shared.set(!onHero)
                if isScrolledDown != !onHero { isScrolledDown = !onHero }
            } else {
                trailers.stop(abort: true)
                trailers.suspended = true
            }
        }
        .onAppear {
            trailers.suspended = !active
            if active { OrbitBarLock.shared.set(!onHero) }
            OrbitMetaStore.shared.request(Array(heroItems.prefix(3)))
        }
        .onDisappear {
            OrbitBarLock.shared.set(false)
            trailers.stop(abort: true)
            trailers.suspended = true
        }
    }

    // MARK: Hero

    /// Steven (device: the hero no longer changed title): a carousel of buttons, slid by the system.
    /// Its buttons start under the bar (the bar stays reachable above them: Up from the hero).
    private var hero: some View {
        let count = heroItems.count
        return ScrollView(.horizontal, showsIndicators: false) {
            // Steven (device: still no Left / Right on the hero): a lazy stack never built the next
            // page (wholly off screen), so the focus engine had nowhere to go. Every page is a real
            // button; only the pages next to the shown one draw their art.
            HStack(spacing: 0) {
                ForEach(Array(heroItems.enumerated()), id: \.offset) { index, item in
                    Button {
                        actions.push(TitleRoute(preview: item))
                    } label: {
                        OrbitNativeHeroPage(item: item, count: count, index: index,
                                            live: abs(index - heroPage) <= 1, trailers: trailers)
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
        .defaultFocus($heroFocus, heroPage,
                      // Back from a title opened in a row: the hero must not take the focus first
                      // (Steven: it went elsewhere, then came back to the title).
                      priority: OrbitNativeRow.reopen == nil ? .userInitiated : .automatic)
    }

    // MARK: Moves

    /// Menu: back to the hero from a row; on the hero, to the bar.
    private var exitAction: () -> Void {
        if onHero {
            return { NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil) }
        }
        return {
            withAnimation(.easeInOut(duration: 0.32)) { position = "hero" }
            heroFocus = heroPage
        }
    }

    private func enter(_ rowID: String) {
        currentRow = rowID
        setOnHero(false)
        if position != rowID { withAnimation(.easeInOut(duration: 0.32)) { position = rowID } }
    }

    private func setOnHero(_ value: Bool) {
        guard onHero != value else { return }
        onHero = value
        guard active else { return }
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
    /// Next to the shown page: drawn (the others are empty frames until they come close).
    let live: Bool
    let trailers: OrbitNativeTrailerHost
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        ZStack(alignment: .top) {
            if live {
                OrbitNativeTrailerReader(host: trailers, key: "hero|\(item.type):\(item.id)") { url in
                    OrbitHomeHeroView(item: item, focused: isFocused, count: count, index: index,
                                      trailerURL: url,
                                      onTrailerFailure: { trailers.model.playbackFailed($0) },
                                      onTrailerEnded: { trailers.model.playbackFinished() })
                }
                    .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
                    .offset(y: -OrbitNativeHome.topLine)
            } else {
                Color.clear
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitNativeHome.heroHeight, alignment: .top)
    }
}

/// The band under the bar off the hero: the page's ground and wash again, fading out down to the
/// rows' line (the rows above slide under it).
private struct OrbitNativeTopCover: View {
    @ObservedObject private var state = OrbitNativeHomeState.shared

    var body: some View {
        OrbitRowsBackdrop(url: state.art)
            .mask(alignment: .top) {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.7),
                                       .init(color: .black.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: OrbitNativeHome.topLine)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
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
    /// Steven (device: the headings still blinked): lit by the page, not by the row's own focus.
    let isCurrent: Bool
    let actions: StageHomeActions
    let trailers: OrbitNativeTrailerHost
    /// The focus came into this row (from outside it).
    let onEnter: () -> Void

    @FocusState private var focused: String?
    /// The row holds the focus. Steven (device: the headings blinked on every Left / Right): the
    /// focus passes through "none" between two titles of a row — the row lets go only if it stays
    /// gone a moment.
    @State private var holds = false
    /// The last title focused here (its details stay through the passage).
    @State private var shown: String?
    /// The classic row: the title it is scrolled to (its frame at the margin).
    @State private var anchor: String?
    /// The row's own scroll (a last correction once the frame has opened).
    @State private var rowProxy: ScrollViewProxy?
    @ObservedObject private var metaStore = OrbitMetaStore.shared

    private var style: OrbitRowStyle { row.style }
    /// Steven: the first row as before — the focused title open in a large 16:9 frame at the left
    /// margin, the others as posters after it, the row sliding under it (Netflix).
    private var classic: Bool { row.style == .classic }

    static let infoHeight: CGFloat = 112

    /// The focused title stays at the margin only where its details sit under the row.
    private var pinned: Bool { showsDetails }
    /// The focused title's details under the row — not under the large cards (they carry theirs)
    /// nor under the great sagas (Steven).
    private var showsDetails: Bool { row.style != .cards && row.style != .sagas }

    var body: some View {
        let L = OrbitHomeLayout.self
        let T = OrbitTileLayout.self
        let style = style
        let size = T.size(style)
        let shownCard = row.cards.first { $0.id == shown }
        VStack(alignment: .leading, spacing: 14) {
            OrbitRowHeading(title: row.title, isCurrent: isCurrent)
                .padding(.leading, L.margin + 4)

            let lead = shown ?? row.cards.first?.id
            ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: T.gap(style)) {
                    ForEach(Array(row.cards.enumerated()), id: \.element.id) { index, card in
                        Button {
                            open(card)
                        } label: {
                            if classic {
                                OrbitNativeClassicTile(card: card, meta: metaStore.meta(for: card.preview),
                                                       trailers: trailers, trailerKey: "\(row.id)|\(card.id)",
                                                       open: card.id == lead)
                            } else {
                                OrbitNativeTile(card: card, meta: metaStore.meta(for: card.preview), style: style, rank: index + 1,
                                                trailers: trailers, trailerKey: "\(row.id)|\(card.id)")
                            }
                        }
                        .buttonStyle(OrbitPlainStyle())
                        .focused($focused, equals: card.id)
                        .onAppear { OrbitMetaStore.shared.request([card.preview]) }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 34)
                // The frame opening on the new title and closing on the old one, on the row's curve.
                .animation(classic ? OrbitHomeLayout.horizontal : nil, value: lead)
            }
            // Steven (simulator: always a whole poster left of the focused title): the alignment on
            // the tiles snapped the pinned row back while its frame was opening — a pinned row is
            // placed by its anchor alone.
            .scrollTargetBehavior(OrbitRowScrollBehavior(aligned: !pinned))
            .scrollPosition(id: $anchor, anchor: .leading)
            // Room after the last title (Steven: at a row's end the focus stopped at the margin and
            // ran on to the right): the last one can come to the margin too.
            .contentMargins(.leading, L.margin, for: .scrollContent)
            // Steven (2026-10-26: at a row's end the frame stayed mid-screen): the room is counted
            // from a closed POSTER, not the open frame. The scroll is asked for while the frame is
            // still opening on the new title (its old place a poster), so with room for the frame
            // only, the row's end was clamped short and the title stopped in the middle. A
            // poster's width is the narrowest it can be: the clamp never bites; the surplus is
            // blank space after the last title.
            .contentMargins(.trailing, pinned ? L.screenWidth - L.margin - size.width : L.margin,
                            for: .scrollContent)
            .scrollClipDisabled()
            .onAppear { rowProxy = proxy }
            }
            .padding(.vertical, -34)
            // Steven's video (the row below bounced on Left / Right): every part of a row has a
            // fixed height — nothing in it can change the rows' places.
            .frame(height: size.height)

            // The focused title's details under the row (large cards carry theirs).
            if showsDetails {
                ZStack(alignment: .topLeading) {
                    Color.clear
                    details(isCurrent ? shownCard : nil)
                }
                .frame(width: 1200, height: Self.infoHeight, alignment: .topLeading)
                .clipped()
                // Steven: the text was too close under the posters (the focused one, larger,
                // nearly touched it).
                .padding(.top, 12)
                .padding(.leading, L.margin + 6)
            }
        }
        .focusSection()
        .onAppear { restoreIfReturning() }
        .onReceive(NotificationCenter.default.publisher(for: .orbitHomeRowFocus)) { note in
            guard note.object as? String == row.id else { return }
            focused = shown ?? row.cards.first?.id
        }
        // Steven: coming into a row lands on its first title (the row back at its start).
        // (Steven: no return to the row's start — the row keeps where it was, as in Apple's app.)
        .defaultFocus($focused, shown ?? row.cards.first?.id, priority: .userInitiated)
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
            // Every row keeps its focused title at the margin, the row sliding under it (Steven: the
            // synopsis stayed on the left while the focus ran off to the right). The classic row's
            // frame stays there too.
            // Rows without details under them scroll as Apple's app does (Steven): the focus runs
            // over the titles on screen, the row moves only at its edge.
            if pinned, anchor != new { withAnimation(OrbitHomeLayout.horizontal) { anchor = new } }
            // Steven (simulator: moving right, the frame drifted off the margin, a poster left of
            // it): the scroll is aimed while the frame is still opening — once it has opened, the
            // title is brought back exactly to the margin.
            if pinned {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                    guard shown == new, focused == new else { return }
                    // Re-aimed through the anchor (it keeps the margin): cleared, then set again.
                    anchor = nil
                    DispatchQueue.main.async {
                        guard shown == new else { return }
                        withAnimation(.easeOut(duration: 0.16)) { anchor = new }
                    }
                }
            }
            guard let index = row.cards.firstIndex(where: { $0.id == new }) else { return }
            let card = row.cards[index]
            // The trailer plays in the classic frame and in the large cards only.
            if row.style == .classic || row.style == .cards {
                trailers.arm("\(row.id)|\(card.id)", item: card.preview)
            } else {
                trailers.stop()
            }
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

    /// The title opened from Home (row, card): the focus is put back on it on the way back
    /// (Steven: it came back on the card to its left).
    @MainActor static var reopen: (row: String, card: String)?

    /// Back from a title: its card, asked a few times (the system's own landing comes late).
    private func restoreIfReturning() {
        guard let target = Self.reopen, target.row == row.id else { return }
        let appeared = ProcessInfo.processInfo.systemUptime
        shown = target.card
        anchor = target.card
        for delay in [0.0, 0.15, 0.35, 0.6, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard Self.reopen?.card == target.card, !ViewerInputClock.shared.hasInput(since: appeared) else { return }
                if focused != target.card { focused = target.card }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if Self.reopen?.card == target.card { Self.reopen = nil }
        }
    }

    private func open(_ card: OrbitCard) {
        Self.reopen = (row.id, card.id)
        trailers.stop(abort: true)
        trailers.suspended = true
        if let entry = card.entry {
            actions.resume(ResumeTarget(entry: entry))
        } else {
            actions.push(TitleRoute(preview: card.preview))
        }
    }
}

/// The classic row's tile: the open 16:9 frame (art, logo, badge) for its title, else a poster.
private struct OrbitNativeClassicTile: View {
    let card: OrbitCard
    let meta: OrbitMeta?
    let trailers: OrbitNativeTrailerHost
    let trailerKey: String
    let open: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        if open {
            OrbitNativeTrailerReader(host: trailers, key: trailerKey) { url in
                OrbitLeadFrame(card: card, meta: meta, focused: isFocused, trailerURL: url,
                               onTrailerFailure: { trailers.model.playbackFailed($0) },
                               onTrailerEnded: { trailers.model.playbackFinished() })
            }
                .shadow(color: .black.opacity(isFocused ? 0.55 : 0), radius: isFocused ? 18 : 0, y: isFocused ? 10 : 0)
                .animation(.easeOut(duration: 0.18), value: isFocused)
                .transition(.opacity)
        } else {
            OrbitPosterCard(card: card)
                .transition(.opacity)
        }
    }
}

/// One tile, drawn focused as its button is (only the tiles whose focus changed redraw).
private struct OrbitNativeTile: View {
    let card: OrbitCard
    let meta: OrbitMeta?
    let style: OrbitRowStyle
    let rank: Int
    let trailers: OrbitNativeTrailerHost
    let trailerKey: String
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Group {
            switch style {
            case .landscape, .classic:
                OrbitLandscapeTile(card: card, meta: meta, focused: isFocused)
            case .cards:
                OrbitNativeTrailerReader(host: trailers, key: trailerKey) { url in
                    OrbitBigCard(card: card, meta: meta, focused: isFocused,
                                 trailerURL: url,
                                 onTrailerFailure: { trailers.model.playbackFailed($0) },
                                 onTrailerEnded: { trailers.model.playbackFinished() })
                }
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


extension Notification.Name {
    /// A Home row takes the focus (the page's own Up / Down, when the system could not reach it).
    static let orbitHomeRowFocus = Notification.Name("orbitHomeRowFocus")
}


/// A row's scroll: aligned on its tiles (Apple's own rows), or free for a row whose focused title is
/// pinned at the margin by the page (the alignment snapped it back while its frame was opening).
struct OrbitRowScrollBehavior: ScrollTargetBehavior {
    let aligned: Bool

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard aligned else { return }
        ViewAlignedScrollTargetBehavior().updateTarget(&target, context: context)
    }
}
