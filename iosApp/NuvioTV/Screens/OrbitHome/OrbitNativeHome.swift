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
    @State private var position: String = "hero"
    /// The page's scroll. Steven (2026-10-28, device: after a while Up / Down moved the page at once,
    /// no slide): the id binding was written back by the scroll itself, the page then thought it
    /// was there already and asked nothing — the system's own jump showed. `position` is ours alone
    /// and every move is asked for, on the curve.
    @State private var page = ScrollPosition(idType: String.self)

    private func go(to id: String, animated: Bool = true) {
        guard position != id else { return }
        position = id
        if animated && !reduceMotion {
            withAnimation(.easeInOut(duration: 0.32)) { page.scrollTo(id: id, anchor: .top) }
        } else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { page.scrollTo(id: id, anchor: .top) }
        }
    }
    /// The row holding the focus (its heading lit, its details shown) — set by the page, so a
    /// row's own focus passing through "none" between two titles never dims it.
    @State private var currentRow: String?
    /// The hero out of the focus's reach while a row takes back the title opened from it.
    @State private var heroLocked = false
    /// Back from a title: the row it was opened from (the only one the focus can land in a moment).
    @State private var returnRow: String?
    /// Steven (2026-10-28, device: back from a title the focus ended in the row above, or on the
    /// neighbour): the system's own landing comes late on the TV. Until the viewer presses anything
    /// (2.6 s at most), a landing anywhere else is sent back to the title's row.
    @State private var returnTarget: String?
    @State private var returnSince: TimeInterval = 0

    private var returning: Bool {
        guard let returnTarget, rows.contains(where: { $0.id == returnTarget }) else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        return now - returnSince < 2.6 && !ViewerInputClock.shared.hasInput(since: returnSince)
    }

    private func sendBack() {
        guard let returnTarget else { return }
        NotificationCenter.default.post(name: .orbitHomeRowFocus, object: returnTarget)
    }

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
                            // Back from a title opened in a row: the hero cannot take the focus for
                            // a moment (Steven, simulator: the focus went up to it).
                            .disabled(heroLocked)
                            .id("hero")
                    }
                    ForEach(rows) { row in
                        Group {
                            // Steven (2026-10-28, device: Left poor, quick presses left the row blank):
                            // the rows that open their title are moved by the page itself.
                            if row.style == .classic || (row.style == .ranked && OrbitNativeRow.rankedOpens) {
                                OrbitNativeOpenRow(row: row, isCurrent: currentRow == row.id, actions: actions,
                                                   trailers: trailers, onEnter: { enter(row.id) })
                            } else {
                                OrbitNativeRow(row: row, isCurrent: currentRow == row.id, actions: actions, trailers: trailers,
                                               onEnter: { enter(row.id) })
                            }
                        }
                            .id(row.id)
                            // (Steven's videos: back from a title the focus landed a moment in the
                            // row above, then came back.)
                            .disabled(returnRow != nil && returnRow != row.id)
                            .environment(\.orbitFocusHidden, returnRow != nil && returnRow != row.id)
                    }
                }
                .scrollTargetLayout()
                // Room under the last rows, so each can come up to the line (Steven, Séries: the last
                // rows were short since their synopsis went — the page stopped at its end, and
                // Up into Prochainement left it cut under the bar).
                .padding(.bottom, OrbitHomeLayout.screenHeight)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition($page)
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
            if page != nil, returning { sendBack(); return }
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
            go(to: "hero")
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
            // Only the way back from a title opened here: a remembered title from long ago (Steven:
            // after a platform, Home came back on its last row every time) is forgotten.
            if let back = OrbitNativeRow.reopen, rows.contains(where: { $0.id == back.row }),
               ProcessInfo.processInfo.systemUptime - OrbitNativeRow.reopenedAt < 600,
               OrbitNavClock.titleOpenedAt >= OrbitNativeRow.reopenedAt - 1 {
                heroLocked = true
                returnRow = back.row
                returnTarget = back.row
                returnSince = ProcessInfo.processInfo.systemUptime
                go(to: back.row, animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { heroLocked = false; returnRow = nil }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) { returnTarget = nil }
            } else {
                OrbitNativeRow.reopen = nil
            }
            // Never kept beyond this return.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) { OrbitNativeRow.reopen = nil }
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
                        // Steven (2026-10-28: the hero's trailer still heard on the title's page).
                        trailers.stop(abort: true)
                        trailers.suspended = true
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
            go(to: "hero")
            heroFocus = heroPage
        }
    }

    private func enter(_ rowID: String) {
        if returning, rowID != returnTarget { sendBack(); return }
        currentRow = rowID
        setOnHero(false)
        go(to: rowID)
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
    @State private var scroll = ScrollPosition(idType: String.self)
    /// The row's own scroll (a last correction once the frame has opened).
    @State private var rowProxy: ScrollViewProxy?
    /// When the way back from a title began (0: not coming back).
    @State private var restoringSince: TimeInterval = 0
    /// From the opening of a title until just after the way back: only its card can take the focus.
    @State private var restoreLock = false
    @State private var disappeared = false
    /// The Top 10's Left: the row put at once where it ends, slid there (as Netflix's).
    @State private var slideX: CGFloat = 0
    /// Where the Top 10's open title is in the row (its tile's left): the frame follows it on the
    /// row's slide (Netflix's).
    @State private var openX: CGFloat?
    /// The last move was Left (the classic frame then changes room at once: the row is slid).
    @State private var movingLeft = false

    /// The row put back where it is shown: a pinned row on its title at the margin (exact, whatever
    /// was recorded), the others at their kept scroll.
    private func settle(on card: String?) {
        var still = Transaction()
        still.disablesAnimations = true
        if pinned, let card {
            withTransaction(still) { scroll.scrollTo(id: card, anchor: .leading) }
        }
        // A row scrolled freely is never moved by us (Steven's video: at the end of "Films
        // recommandés pour vous" it came back shifted right) — as on the platforms and studios.
    }

    private func lockForReturn(_ card: String) {
        // Nothing touches the row at the press (Steven: "Films recommandés pour vous" slid right
        // as he pressed): the aim and the lock wait for the page to have gone (`onDisappear`).
    }
    @ObservedObject private var metaStore = OrbitMetaStore.shared

    private var style: OrbitRowStyle { row.style }
    /// Steven: the first row as before — the focused title open in a large 16:9 frame at the left
    /// margin, the others as posters after it, the row sliding under it (Netflix).
    private var classic: Bool { row.style == .classic }
    /// Steven (2026-10-27, to try): the Top 10 moves as Nouveaux films — its focused title open in a
    /// 16:9 frame (its trailer there), at the margin, the row sliding under it; same height.
    /// `false` puts back his Top 10 as it was (posters, the row scrolled freely).
    static let rankedOpens = true
    private var rankedOpen: Bool { row.style == .ranked && Self.rankedOpens }
    /// The opening rows (the frame on the new title, on the row's curve).
    private var opens: Bool { classic || rankedOpen }

    static let infoHeight: CGFloat = 112

    /// The focused title stays at the margin only where its details sit under the row.
    private var pinned: Bool { showsDetails || rankedOpen }
    /// The focused title's details under the row — not under the large cards (they carry theirs)
    /// nor under the great sagas (Steven).
    /// (Steven, 2026-10-27: only under the first row's open 16:9 frame — the posters' rows are
    /// cleaner without, and scroll as Apple's app does.)
    private var showsDetails: Bool { row.style == .classic }

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
                            } else if rankedOpen {
                                OrbitNativeRankedOpenTile(card: card, meta: metaStore.meta(for: card.preview), rank: index + 1,
                                                          trailers: trailers, trailerKey: "\(row.id)|\(card.id)",
                                                          open: card.id == lead)

                            } else {
                                OrbitNativeTile(card: card, meta: metaStore.meta(for: card.preview), style: style, rank: index + 1,
                                                trailers: trailers, trailerKey: "\(row.id)|\(card.id)")
                            }
                        }
                        .buttonStyle(OrbitPlainStyle())
                        // Steven (2026-10-28): Continue Watching, held — its options again.
                        .modifier(OrbitContinueWatchingMenu(entry: card.entry, preview: card.preview, actions: actions))
                        .focused($focused, equals: card.id)
                        // The focused tile above its neighbours (Steven, Prochainement: the next
                        // tile covered the grown one's edge).
                        .zIndex(focused == card.id ? 1 : 0)
                        // Back from a title, only its card can take the focus a moment: a landing on
                        // a neighbour scrolled the row to it (Steven, simulator: the row moved).
                        .disabled(restoreLock && Self.reopen?.row == row.id && Self.reopen?.card != card.id)
                        .transformEnvironment(\.orbitFocusHidden) {
                            $0 = $0 || ((restoreLock || restoringSince > 0) && Self.reopen?.row == row.id && Self.reopen?.card != card.id)
                        }
                        .onAppear { OrbitMetaStore.shared.request([card.preview]) }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 34)
                .offset(x: slideX)
                // The frame opening on the new title and closing on the old one, on the row's curve.
                // (The Top 10: its room changes at once, only the row slides — Netflix's.)
                .animation(classic && !movingLeft ? OrbitHomeLayout.horizontal : nil, value: lead)
            }
            // Steven (simulator: always a whole poster left of the focused title): the alignment on
            // the tiles snapped the pinned row back while its frame was opening — a pinned row is
            // placed by its anchor alone.
            .scrollTargetBehavior(OrbitRowScrollBehavior(aligned: !pinned))
            // Only a pinned row is driven by its anchor. An unpinned one is not bound at all: the
            // binding kept the first title the system wrote back (one half off screen) and brought it
            // in on the way back from a title — the row moved by one (Steven, simulator).
            .scrollPosition($scroll)
            // Where the row is scrolled, kept (not while it comes back from a title): the way back
            // puts it exactly there again (Steven, simulator: every return moved it right).
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, x in
                if restoringSince == 0, !disappeared, !restoreLock { Self.offsets[row.id] = x }
            }
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
            .coordinateSpace(.named("rankedRow"))

            // The focused title's details under the row (large cards carry theirs).
            if showsDetails {
                ZStack(alignment: .topLeading) {
                    Color.clear
                    details(isCurrent ? shownCard : nil)
                }
                .frame(width: 1200, height: Self.infoHeight, alignment: .topLeading)
                .clipped()
                // Steven: the text was too close under the posters (the focused one, larger,
                // nearly touched it). Lower again (2026-10-26), the row's height unchanged: the
                // 16 points come out of the gap under the row.
                .padding(.top, 20)
                .padding(.bottom, -8)
                .padding(.leading, L.margin + 6)
            }
        }
        .focusSection()
        // (Every appearance: a row scrolled off the page and back stopped keeping where it was —
        // Steven: back from a title the row came back far from where he left it.)
        .onAppear { disappeared = false; restoreIfReturning() }
        .onDisappear {
            disappeared = true
            if let back = Self.reopen, back.row == row.id {
                settle(on: back.card)
                restoreLock = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .orbitHomeRowFocus)) { note in
            guard note.object as? String == row.id else { return }
            focused = shown ?? row.cards.first?.id
        }
        // Steven: coming into a row lands on its first title (the row back at its start).
        // (Steven: no return to the row's start — the row keeps where it was, as in Apple's app.)
        // Steven (2026-10-28: "on s'était dit le défilement naturel de l'Apple TV partout" — coming
        // into a row of posters always landed on its far-left title): only the rows whose title
        // sits at the margin (Nouveaux films, the Top 10) take it there; the others are the
        // system's own landing, the title under the focus.
        .modifier(OrbitRowEntry(focused: $focused, target: pinned ? (shown ?? row.cards.first?.id) : nil))
        .onChange(of: focused) { _, new in
            guard let new else {
                // Gone for good, or only passing between two titles?
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    if focused == nil, holds { holds = false }
                }
                return
            }
            // Back from a title: a landing on another title is the system's — sent straight back,
            // the row unchanged (Steven, simulator: Split showed a moment, then Logan).
            if let back = Self.reopen, back.row == row.id, new != back.card, restoringSince > 0,
               !ViewerInputClock.shared.hasInput(since: restoringSince) {
                DispatchQueue.main.async { focused = back.card }
                return
            }
            // A move inside the row (not the focus coming back into it, nor a return from a title).
            let moving = holds
            if !holds {
                holds = true
                onEnter()
            }
            if pinned, let oldIndex = anchor.flatMap({ id in row.cards.firstIndex(where: { $0.id == id }) }),
               let newIndex = row.cards.firstIndex(where: { $0.id == new }) {
                movingLeft = newIndex < oldIndex
            } else {
                movingLeft = false
            }
            shown = new
            // Every row keeps its focused title at the margin, the row sliding under it (Steven: the
            // synopsis stayed on the left while the focus ran off to the right). The classic row's
            // frame stays there too.
            // Rows without details under them scroll as Apple's app does (Steven): the focus runs
            // over the titles on screen, the row moves only at its edge.
            if pinned, anchor != new {
                let old = anchor.flatMap { id in row.cards.firstIndex(where: { $0.id == id }) }
                let now = row.cards.firstIndex(where: { $0.id == new })
                anchor = new
                // Steven (2026-10-28, device: Right fine, Left poor): Left as Netflix's page (validated
                // there) — the row put at once where it ends and slid there, so Left looks as Right.
                if opens, let old, let now, now < old, old - now <= 3 {
                    let distance = (now..<old).reduce(CGFloat(0)) {
                        $0 + (rankedOpen ? OrbitRankedTile.closedWidth($1 + 1) : size.width) + T.gap(style)
                    }
                    var still = Transaction()
                    still.disablesAnimations = true
                    withTransaction(still) {
                        slideX = -distance
                        scroll.scrollTo(id: new, anchor: .leading)
                    }
                    withAnimation(OrbitHomeLayout.horizontal) { slideX = 0 }
                } else {
                    withAnimation(OrbitHomeLayout.horizontal) { scroll.scrollTo(id: new, anchor: .leading) }
                }
            }
            // Steven (simulator: moving right, the frame drifted off the margin, a poster left of
            // it): the scroll is aimed while the frame is still opening — once it has opened, the
            // title is brought back exactly to the margin.
            // (Only on a move inside the row: on a return the re-aim moved the row — Steven.)
            if pinned, moving {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                    guard shown == new, focused == new else { return }
                    withAnimation(.easeOut(duration: 0.16)) { scroll.scrollTo(id: new, anchor: .leading) }
                }
            }
            guard let index = row.cards.firstIndex(where: { $0.id == new }) else { return }
            let card = row.cards[index]
            // The trailer plays in the open frames only (Steven, 2026-10-28: none in the large cards of
            // "Films recommandés pour vous").
            if row.style == .classic || rankedOpen {
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
                // (Steven: no synopsis under Prochainement — its title and date line only.)
                Text(row.id.hasPrefix("orbit-soon") ? "" : (saga ? (card.preview.description_ ?? "") : info.synopsis))
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
    @MainActor static var reopenedAt: TimeInterval = 0
    /// Each row's scroll (where it comes back to on the way back from a title).
    @MainActor static var offsets: [String: CGFloat] = [:]

    /// Back from a title: its card, asked a few times (the system's own landing comes late).
    private func restoreIfReturning() {
        guard let target = Self.reopen, target.row == row.id else { return }
        let appeared = ProcessInfo.processInfo.systemUptime
        restoringSince = appeared
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { restoreLock = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { if restoringSince == appeared { restoringSince = 0 } }
        shown = target.card
        // Steven (simulator: back from a title the row jumped, then slid back): only a pinned row is
        // brought to its title; the others are where they were left.
        disappeared = false
        for delay in [0.0, 0.15, 0.35, 0.6, 0.9, 1.3, 1.8, 2.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard Self.reopen?.card == target.card, !ViewerInputClock.shared.hasInput(since: appeared) else { return }
                if focused != target.card { focused = target.card }
                // The row exactly where it was left, whatever the focus's own scroll did.
                settle(on: target.card)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if Self.reopen?.card == target.card { Self.reopen = nil }
        }
    }

    private func open(_ card: OrbitCard) {
        Self.reopen = (row.id, card.id)
        Self.reopenedAt = ProcessInfo.processInfo.systemUptime
        lockForReturn(card.id)
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
struct OrbitNativeClassicTile: View {
    let card: OrbitCard
    let meta: OrbitMeta?
    let trailers: OrbitNativeTrailerHost
    let trailerKey: String
    let open: Bool
    @Environment(\.isFocused) private var systemFocused
    /// Back from a title, a tile the system lands on a moment is not drawn focused (Steven: the
    /// focus seen going left, then coming back).
    @Environment(\.orbitFocusHidden) private var focusHidden
    private var isFocused: Bool { systemFocused && !focusHidden }

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

/// The Top 10 opening as Nouveaux films (`OrbitNativeRow.rankedOpens`): its rank, then the focused
/// title's 16:9 frame of the poster's height (its trailer), the others as his ranked posters.
struct OrbitNativeRankedOpenTile: View {
    let card: OrbitCard
    let meta: OrbitMeta?
    let rank: Int
    let trailers: OrbitNativeTrailerHost
    let trailerKey: String
    let open: Bool
    /// A studio's page: its larger Top 10, no platform badge.
    var scale: CGFloat = 1
    var showsBadge = true
    @Environment(\.isFocused) private var systemFocused
    @Environment(\.orbitFocusHidden) private var focusHidden
    private var isFocused: Bool { systemFocused && !focusHidden }

    private var frame: CGSize { Self.frame(scale: scale) }

    /// The frame size of the open title (16:9, the poster's height).
    static func frame(scale: CGFloat) -> CGSize {
        let height = OrbitTileLayout.rankedPoster.height * scale
        return CGSize(width: (height * 16 / 9).rounded(), height: height)
    }

    var body: some View {
        // The open title's frame is its tile's own, beside its rank: the figure and the frame move
        // with the row as one (Steven) — the frame no longer drawn apart by the row.
        // (Steven: the figure lit again when its title has the focus.)
        let frame = frame
        let focused = isFocused
        OrbitRankedTile(card: card, meta: meta, rank: rank, focused: isFocused, showsBadge: showsBadge, scale: scale,
                        openWidth: open ? frame.width : nil,
                        openFrame: open ? {
                            AnyView(OrbitRankedOpenFrame(card: card, meta: meta, focused: focused,
                                                         trailers: trailers, trailerKey: trailerKey, size: frame))
                        } : nil)
            // The room changes at once (Steven: Left left a hole — the room shrank on the focus's
            // own little curve while the row was put where it ends).
            .transaction(value: open) { $0.animation = nil }
    }
}

/// The open title's frame, drawn once by its row at the margin (Netflix's Top 10): the art and the
/// trailer change inside it as the focus moves.
struct OrbitRankedOpenFrame: View {
    let card: OrbitCard
    let meta: OrbitMeta?
    let focused: Bool
    let trailers: OrbitNativeTrailerHost
    let trailerKey: String
    let size: CGSize

    var body: some View {
        OrbitNativeTrailerReader(host: trailers, key: trailerKey) { url in
            OrbitLeadFrame(card: card, meta: meta, focused: focused, trailerURL: url,
                           onTrailerFailure: { trailers.model.playbackFailed($0) },
                           onTrailerEnded: { trailers.model.playbackFinished() },
                           frameSize: size)
        }
        .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: focused ? 18 : 0, y: focused ? 10 : 0)
        .animation(.easeOut(duration: 0.18), value: focused)
        .allowsHitTesting(false)
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
    @Environment(\.isFocused) private var systemFocused
    /// Back from a title, a tile the system lands on a moment is not drawn focused (Steven: the
    /// focus seen going left, then coming back).
    @Environment(\.orbitFocusHidden) private var focusHidden
    private var isFocused: Bool { systemFocused && !focusHidden }

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
        // Steven (simulator, every return from a title: the row moved right): a row the focus
        // scrolled freely rests between two tiles; the next scroll — the focus put back on the
        // way back — was snapped to a tile, a tile to the right. No row is aligned any more: the
        // focus scrolls them as Apple's app does, and a pinned row is placed by its anchor.
        _ = aligned
    }
}


/// Continue Watching, held (the old Home's menu): choose the source, the title's page, the episode
/// marked watched, from the start, out of the row.
private struct OrbitContinueWatchingMenu: ViewModifier {
    let entry: WatchProgressEntry?
    let preview: MetaPreview
    let actions: StageHomeActions

    func body(content: Content) -> some View {
        if let entry {
            content.contextMenu {
                let isEpisode = TitleHoldMenuPolicy.isEpisode(season: entry.seasonNumber?.intValue,
                                                              episode: entry.episodeNumber?.intValue)
                ForEach(TitleHoldMenuPolicy.continueWatchingActions(isEpisode: isEpisode), id: \.self) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        perform(action, entry)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            }
        } else {
            content
        }
    }

    private func perform(_ action: TitleHoldMenuPolicy.CWAction, _ entry: WatchProgressEntry) {
        switch action {
        case .playManually:
            actions.resume(ResumeTarget(entry: entry, forceManual: true))
        case .goToDetails:
            actions.push(TitleRoute(preview: preview))
        case .markEpisodeWatched:
            WatchedRepository.shared.markWatched(
                item: WatchingActionsKt.watchedItemFromProgress(
                    entry: entry,
                    markedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000)
                )
            )
            WatchProgressRepository.shared.clearProgress(videoId: entry.videoId, parentMetaId: entry.parentMetaId)
        case .startOver:
            actions.resume(ResumeTarget(entry: entry, startFromBeginning: true))
        case .remove:
            WatchProgressRepository.shared.clearProgress(videoId: entry.videoId, parentMetaId: entry.parentMetaId)
        }
    }
}


/// A pinned row's entry on its title at the margin; any other row: the system's own landing.
private struct OrbitRowEntry: ViewModifier {
    var focused: FocusState<String?>.Binding
    let target: String?

    func body(content: Content) -> some View {
        if let target {
            content.defaultFocus(focused, target, priority: .userInitiated)
        } else {
            content
        }
    }
}


// MARK: - The rows that open their title (Nouveaux films, the Top 10)

/// Steven (2026-10-28, device videos: Right fine slowly, Left poor, quick presses left the row
/// half blank — a lazy row slid past what it had built): the row is ONE focusable stop. Left /
/// Right move its lead; every tile is placed from the lead on one curve — the old title closing,
/// the new one opening, the row sliding — the same both ways, retargeted smoothly on quick presses.
/// Up / Down are the system's (nothing else in the row to go to).
struct OrbitNativeOpenRow: View {
    let row: OrbitRow
    let isCurrent: Bool
    let actions: StageHomeActions
    let trailers: OrbitNativeTrailerHost
    let onEnter: () -> Void

    @FocusState private var rowFocused: Bool
    @State private var lead = 0
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.orbitFocusHidden) private var focusHidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ranked: Bool { row.style == .ranked }
    private var gap: CGFloat { OrbitTileLayout.gap(row.style) }
    private var height: CGFloat { OrbitTileLayout.size(row.style).height }

    /// A tile's room before its poster (the Top 10's rank).
    private func room(_ i: Int) -> CGFloat { ranked ? OrbitRankedTile.rankRoom(i + 1) : 0 }
    private func width(_ i: Int, open: Bool) -> CGFloat {
        if ranked {
            return room(i) + (open ? OrbitNativeRankedOpenTile.frame(scale: 1).width : OrbitTileLayout.rankedPoster.width)
        }
        return open ? OrbitHomeLayout.frameWidth : OrbitHomeLayout.posterWidth
    }

    /// Tile `i`'s left edge, the lead's at the margin.
    private func x(_ i: Int) -> CGFloat {
        let margin = OrbitHomeLayout.margin
        if i == lead { return margin }
        if i > lead {
            return margin + (lead..<i).reduce(CGFloat(0)) { $0 + width($1, open: $1 == lead) + gap }
        }
        return margin - (i..<lead).reduce(CGFloat(0)) { $0 + width($1, open: false) + gap }
    }

    var body: some View {
        let L = OrbitHomeLayout.self
        let cards = row.cards
        let leadIndex = min(lead, max(0, cards.count - 1))
        VStack(alignment: .leading, spacing: 14) {
            OrbitRowHeading(title: row.title, isCurrent: isCurrent)
                .padding(.leading, L.margin + 4)

            Button {
                if cards.indices.contains(leadIndex) { open(cards[leadIndex]) }
            } label: {
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                    ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                        if i >= leadIndex - 2, i <= leadIndex + 7 {
                            tile(card, index: i, open: i == leadIndex)
                                .environment(\.orbitFocusHidden, focusHidden || i != leadIndex)
                                .offset(x: x(i))
                                .zIndex(i == leadIndex ? 1 : 0)
                                .transition(.identity)
                        }
                    }
                }
                .frame(width: L.screenWidth, height: height, alignment: .bottomLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(OrbitPlainStyle())
            .focused($rowFocused)
            .onMoveCommand { direction in
                switch direction {
                case .left: move(-1)
                case .right: move(1)
                default: break
                }
            }
            .frame(height: height)

            if row.style == .classic {
                ZStack(alignment: .topLeading) {
                    Color.clear
                    if isCurrent, cards.indices.contains(leadIndex) { details(cards[leadIndex]) }
                }
                .frame(width: 1200, height: OrbitNativeRow.infoHeight, alignment: .topLeading)
                .clipped()
                .padding(.top, 20)
                .padding(.bottom, -8)
                .padding(.leading, L.margin + 6)
            }
        }
        .onChange(of: rowFocused) { _, focused in
            if focused {
                onEnter()
                leadChanged()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .orbitHomeRowFocus)) { note in
            guard note.object as? String == row.id else { return }
            rowFocused = true
        }
        .onAppear(perform: restoreIfReturning)
    }

    @ViewBuilder
    private func tile(_ card: OrbitCard, index: Int, open: Bool) -> some View {
        let meta = metaStore.meta(for: card.preview)
        let key = "\(row.id)|\(card.id)"
        if ranked {
            OrbitNativeRankedOpenTile(card: card, meta: meta, rank: index + 1, trailers: trailers, trailerKey: key, open: open)
        } else {
            OrbitNativeClassicTile(card: card, meta: meta, trailers: trailers, trailerKey: key, open: open)
                .frame(width: width(index, open: open), height: height, alignment: .bottomLeading)
        }
    }

    private func move(_ step: Int) {
        let next = lead + step
        guard row.cards.indices.contains(next) else { return }
        withAnimation(reduceMotion ? nil : OrbitHomeLayout.horizontal) { lead = next }
        leadChanged()
    }

    /// The lead's trailer, wash and the titles ahead.
    private func leadChanged() {
        let cards = row.cards
        guard cards.indices.contains(lead) else { return }
        let card = cards[lead]
        trailers.arm("\(row.id)|\(card.id)", item: card.preview)
        OrbitNativeHomeState.shared.art = card.landscape ?? metaStore.meta(for: card.preview)?.backdrop
        let ahead = cards[max(0, lead - 2)..<min(cards.count, lead + 8)].map(\.preview)
        OrbitMetaStore.shared.request(Array(ahead))
    }

    @ViewBuilder
    private func details(_ card: OrbitCard) -> some View {
        let info = OrbitInfo.make(card.preview, meta: metaStore.meta(for: card.preview))
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text(card.preview.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                OrbitMetaLine(info: info, size: 24)
            }
            .frame(height: 34)
            Text(info.synopsis)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineSpacing(3)
                .lineLimit(2)
                .frame(width: 1100, alignment: .topLeading)
        }
        .id(card.id)
        .transition(.opacity.animation(.easeInOut(duration: 0.18)))
    }

    private func open(_ card: OrbitCard) {
        OrbitNativeRow.reopen = (row.id, card.id)
        OrbitNativeRow.reopenedAt = ProcessInfo.processInfo.systemUptime
        trailers.stop(abort: true)
        trailers.suspended = true
        if let entry = card.entry {
            actions.resume(ResumeTarget(entry: entry))
        } else {
            actions.push(TitleRoute(preview: card.preview))
        }
    }

    /// Back from a title opened here: the row takes the focus back (on its lead, unchanged).
    private func restoreIfReturning() {
        guard let target = OrbitNativeRow.reopen, target.row == row.id else { return }
        if let i = row.cards.firstIndex(where: { $0.id == target.card }), i != lead {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { lead = i }
        }
        let appeared = ProcessInfo.processInfo.systemUptime
        for delay in [0.0, 0.15, 0.35, 0.6, 0.9, 1.3, 1.8, 2.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard OrbitNativeRow.reopen?.card == target.card,
                      !ViewerInputClock.shared.hasInput(since: appeared) else { return }
                if !rowFocused { rowFocused = true }
            }
        }
    }
}
