import Combine
import SharedCore
import SwiftUI
import UIKit

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
    /// The hero's art cut to its frame (rows focused). Steven (2026-10-29, device: Down from the
    /// hero, a black band at the top): the cut came at once, before the page had slid — the art
    /// above the hero's frame vanished, the band under the bar empty until its wash came. Now the
    /// cut waits for the slide (the band's wash is up by then).
    @State private var heroCut = false
    @State private var heroCutGeneration = 0
    /// The hero's art below its frame (the screen's last points), shown only while it rests there.
    @State private var heroFootShown = true
    /// The section the page is aligned on (the system scrolls to it, on its own curve).
    @State private var position: String = "hero"
    /// The page's scroll. Steven (2026-10-28, device: after a while Up / Down moved the page at once,
    /// no slide): the id binding was written back by the scroll itself, the page then thought it
    /// was there already and asked nothing — the system's own jump showed. `position` is ours alone
    /// and every move is asked for, on the curve.
    @State private var page = ScrollPosition(idType: String.self)
    @State private var lastGo: TimeInterval = 0
    /// The page is shown (not under a title's page, the sources, the player).
    @State private var onScreen = false
    /// The hero's default focus is the page's first (not on a way back to a row).
    @State private var heroDefaultStrong = true

    private func go(to id: String, animated: Bool = true) {
        // Steven (2026-10-29, device: now and then a vertical move snapped, no slide): the page could
        // be elsewhere than `position` says (the system's own scroll moved it), and the move was then
        // skipped — the system's jump showed. Every move is asked for, on the curve; the same place
        // twice in a row only once.
        if position == id, ProcessInfo.processInfo.systemUptime - lastGo < 0.2 { return }
        lastGo = ProcessInfo.processInfo.systemUptime
        position = id
        if animated && !reduceMotion {
            // Steven (2026-10-29, videos: every vertical move started with a jerk): the system's own
            // scroll starts fast, ours (ease-in-out) took over from rest — the page slowed after its
            // first frame. Ours now starts fast too and settles slowly, as the system's does.
            // (Steven's slow-motion video of Apple's TV app: its page starts at full speed on the
            // press and slows evenly to rest in about 0.4 s — an ease-out, measured frame by frame.)
            withAnimation(.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.4)) { page.scrollTo(id: id, anchor: .top) }
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
    /// Steven (2026-10-29: "un petit peu d'espace entre chaque ligne comme dans l'application Apple
    /// TV"): 44 → 72, about Apple's own gap between a row's posters and the next heading.
    static let sectionGap: CGFloat = 72

    var body: some View {
        let L = OrbitHomeLayout.self
        ZStack(alignment: .topLeading) {
            OrbitNativeBackdrop(visible: !onHero)
            // The clickpad's swipes, for the open row holding the focus (`OrbitSwipeHub`).
            OrbitSwipeCatcher(active: true) { step in OrbitSwipeHub.shared.onStep?(step) }
                .frame(width: 0, height: 0)

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
                            // Steven (2026-10-29, device): the top waits for the slide (no black band
                            // under the bar), the bottom is cut at once (its dark foot no longer
                            // drawn over the first row as the page slides — the band at the bottom)
                            // and comes back once the page rests on the hero.
                            .mask(alignment: .top) {
                                let H = OrbitHomeLayout.screenHeight
                                let up: CGFloat = heroCut ? 0 : H
                                let down: CGFloat = heroFootShown ? H : 0
                                Rectangle()
                                    .frame(width: OrbitHomeLayout.screenWidth, height: Self.heroHeight + up + down)
                                    .offset(y: -up)
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
                                    .equatable()
                            } else {
                                OrbitNativeRow(row: row.looped(), isCurrent: currentRow == row.id, actions: actions,
                                               trailers: trailers, onEnter: { enter(row.id) })
                                    .equatable()
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
            // (Tried, 2026-10-28: the system's own scroll off — jerkier on the device, and Down from the
            // hero took two presses. Back to the page's scroll alongside the system's.)
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
                heroDefaultStrong = false
                heroLocked = true
                returnRow = back.row
                returnTarget = back.row
                returnSince = ProcessInfo.processInfo.systemUptime
                go(to: back.row, animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { heroLocked = false; returnRow = nil }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) { returnTarget = nil }
            } else {
                OrbitNativeRow.reopen = nil
                heroDefaultStrong = true
            }
            // Never kept beyond this return — unless the page has gone again meanwhile (Steven,
            // 2026-10-29: Continue Watching's menu closing showed Home a moment, the card was
            // forgotten while the title's page was up, and the way back came to the hero).
            onScreen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) { if onScreen { OrbitNativeRow.reopen = nil } }
            trailers.suspended = !active
            if active { OrbitBarLock.shared.set(!onHero) }
            OrbitMetaStore.shared.request(Array(heroItems.prefix(3)))
        }
        .onDisappear {
            onScreen = false
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
                      // (Steven, 2026-10-29: back from Continue Watching, the focus went up to the
                      // hero unseen — the priority flipped as the remembered card was forgotten,
                      // and the system put the focus back on its default. Set once per appearance.)
                      priority: heroDefaultStrong ? .userInitiated : .automatic)
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
        heroCutGeneration &+= 1
        let generation = heroCutGeneration
        if value {
            heroCut = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                if generation == heroCutGeneration, onHero { heroFootShown = true }
            }
        } else {
            heroFootShown = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if generation == heroCutGeneration, !onHero { heroCut = true }
            }
        }
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
        OrbitMirroredWash(mirror: OrbitWashMirror.home)
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
        OrbitRowsBackdrop(url: state.art, mirror: OrbitWashMirror.home)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.35), value: visible)
            .ignoresSafeArea()
    }
}

// MARK: - A row

/// Steven (2026-10-29, videos: a frame missed at the start of every move): any change on the page
/// (the row holding the focus, the hero's state…) redrew every row — their closures made them all
/// "new". A row now redraws only when its titles or its being current change (its own state and
/// the page's environment still reach it).
extension OrbitNativeRow: Equatable {
    static func == (a: OrbitNativeRow, b: OrbitNativeRow) -> Bool {
        a.row == b.row && a.isCurrent == b.isCurrent
    }
}

extension OrbitNativeOpenRow: Equatable {
    static func == (a: OrbitNativeOpenRow, b: OrbitNativeOpenRow) -> Bool {
        a.row == b.row && a.isCurrent == b.isCurrent
    }
}

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
    @State private var placedLoop = false
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
    /// (Steven, 2026-10-29, device: the Top 10 opening in place slid at every title, the old frame
    /// mixed into the new — his choice: posters and big ranks, as Netflix's Top 10.)
    static let rankedOpens = false
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

    /// The row's UIKit strip (the way back, the page's focus requests go through it).
    @State private var strip = OrbitRowStripRef()

    /// Steven (2026-10-29: "fais exactement comme l'application Apple TV"): the row is a UIKit
    /// collection view scrolled by the focus engine, as Apple's own rows (`OrbitRowStrip`).
    var body: some View {
        let L = OrbitHomeLayout.self
        VStack(alignment: .leading, spacing: 14) {
            OrbitRowHeading(title: row.title, isCurrent: isCurrent)
                .padding(.leading, L.margin + 4)
            OrbitRowStrip(rowID: row.id, cards: row.cards, style: style, loopStart: row.loopStart,
                          trailers: trailers, ref: strip,
                          onSelect: { open($0) },
                          onFocus: { focusChanged($0) },
                          menu: { holdMenu($0) })
                .frame(height: OrbitTileLayout.size(style).height)
        }
        .focusSection()
        .onAppear {
            disappeared = false
            // Back from a title opened here: its card takes the focus back.
            if let back = Self.reopen, back.row == row.id {
                let appeared = ProcessInfo.processInfo.systemUptime
                restoringSince = appeared
                DispatchQueue.main.async { strip.controller?.restore(cardID: back.card) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                    if restoringSince == appeared { restoringSince = 0 }
                    if !disappeared, Self.reopen?.card == back.card { Self.reopen = nil }
                }
            }
        }
        .onDisappear { disappeared = true }
        .onReceive(NotificationCenter.default.publisher(for: .orbitHomeRowFocus)) { note in
            guard note.object as? String == row.id else { return }
            strip.controller?.takeFocus()
        }
    }

    /// The focus moved in the strip (nil: it left the row).
    private func focusChanged(_ card: OrbitCard?) {
        guard let card else {
            // Gone for good, or only passing between two titles?
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                if strip.controller?.focusedIndex == nil, holds { holds = false }
            }
            return
        }
        if !holds {
            holds = true
            onEnter()
        }
        shown = card.id
        trailers.stop()
        OrbitNativeHomeState.shared.art = card.landscape ?? metaStore.meta(for: card.preview)?.backdrop
        if let index = row.cards.firstIndex(where: { $0.id == card.id }) {
            let ahead = row.cards[index..<min(row.cards.count, index + 6)].map(\.preview)
            OrbitMetaStore.shared.request(Array(ahead))
        }
    }

    /// Continue Watching, held: its options (the old Home's menu).
    private func holdMenu(_ card: OrbitCard) -> UIMenu? {
        guard let entry = card.entry else { return nil }
        let isEpisode = TitleHoldMenuPolicy.isEpisode(season: entry.seasonNumber?.intValue,
                                                      episode: entry.episodeNumber?.intValue)
        let items: [UIMenuElement] = TitleHoldMenuPolicy.continueWatchingActions(isEpisode: isEpisode).map { action in
            UIAction(title: action.title, image: UIImage(systemName: action.systemImage),
                     attributes: action.isDestructive ? .destructive : []) { _ in
                OrbitContinueWatchingMenu.perform(action, entry, preview: card.preview, actions: actions,
                                                  onLeave: { markOpening(card) })
            }
        }
        return UIMenu(title: "", children: items)
    }

    @ViewBuilder
    private var legacyBody: some View {
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
                // Steven (2026-10-29, videos: frames missed during each slide): a short row (the Top
                // 10…) is built whole once — a lazy one built the tile coming in mid-slide.
                OrbitRowStack(lazy: row.cards.count > 14, spacing: T.gap(style)) {
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
                        .modifier(OrbitContinueWatchingMenu(entry: card.entry, preview: card.preview, actions: actions,
                                                            onLeave: { markOpening(card) }))
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
            // Steven (2026-10-29, videos: a shake at the end of every slide, a frame missed then a
            // little jump): the system wrote the row's first visible title back into the binding as
            // the slide ended, and the row was re-placed on it. A row the focus scrolls freely is no
            // longer bound at all — only a row placed by its anchor.
            .modifier(OrbitRowBinding(bound: pinned, scroll: $scroll))
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
        .onAppear {
            disappeared = false
            // (Steven, 2026-10-29: back from a film started in Continue Watching the row no longer
            // moved — its other cards stayed locked when the way back was not this row's.)
            if Self.reopen?.row != row.id { restoreLock = false }
            // A looping row starts in its middle copy (once: it keeps where it was after).
            if let start = row.loopStart, !placedLoop {
                placedLoop = true
                var still = Transaction()
                still.disablesAnimations = true
                if pinned {
                    withTransaction(still) { scroll.scrollTo(id: start, anchor: .leading) }
                } else {
                    // (Unbound: placed through the reader, once it is there.)
                    DispatchQueue.main.async {
                        withTransaction(still) { rowProxy?.scrollTo(start, anchor: .leading) }
                    }
                }
            }
            restoreIfReturning()
        }
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
            if !disappeared, Self.reopen?.card == target.card { Self.reopen = nil }
        }
    }

    /// Leaving for a title from this card (opened, or from its hold menu): the way back comes to it.
    private func markOpening(_ card: OrbitCard) {
        Self.reopen = (row.id, card.id)
        Self.reopenedAt = ProcessInfo.processInfo.systemUptime
        // Continue Watching plays without a title page (the sources, the player): the way back
        // counts it as a title opened (else the page came back on the hero).
        if card.entry != nil { OrbitNavClock.titleOpenedAt = Self.reopenedAt }
        lockForReturn(card.id)
        trailers.stop(abort: true)
        trailers.suspended = true
    }

    private func open(_ card: OrbitCard) {
        markOpening(card)
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
struct OrbitNativeTile: View {
    let card: OrbitCard
    let meta: OrbitMeta?
    let style: OrbitRowStyle
    let rank: Int
    let trailers: OrbitNativeTrailerHost
    let trailerKey: String
    /// In a UIKit row (`OrbitRowStrip`) the cell says whether it is focused, and opens the Top 10.
    var focusedFromCell: Bool? = nil
    var openFromCell: Bool? = nil
    @Environment(\.isFocused) private var systemFocused
    /// Back from a title, a tile the system lands on a moment is not drawn focused (Steven: the
    /// focus seen going left, then coming back).
    @Environment(\.orbitFocusHidden) private var focusHidden
    private var isFocused: Bool { (focusedFromCell ?? systemFocused) && !focusHidden }
    /// Steven (2026-10-29): the Top 10's poster, rested on, widens into a 16:9 frame with its
    /// trailer, over its own rank (hidden behind it); the row does not move. Any move: a poster again.
    @State private var landscape = false
    static let dwellTime: Duration = .milliseconds(1500)

    private func dwell() async {
        guard isFocused else {
            if landscape { withAnimation(.easeInOut(duration: 0.28)) { landscape = false } }
            return
        }
        do { try await Task.sleep(for: Self.dwellTime) } catch { return }
        guard isFocused, !Task.isCancelled else { return }
        trailers.arm(trailerKey, item: card.preview)
        withAnimation(.easeInOut(duration: 0.4)) { landscape = true }
    }

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
                // Steven (2026-10-29, device: the frame drawn over the neighbours "ça va pas du
                // tout"): the poster itself widens into the 16:9 frame in its own place, its rank
                // staying on its left (a little behind it), the titles after it making room.
                let open = (openFromCell ?? landscape) && isFocused
                let frame = OrbitNativeRankedOpenTile.frame(scale: 1)
                OrbitRankedTile(card: card, meta: meta, rank: rank, focused: isFocused,
                                openWidth: open ? frame.width : nil,
                                openFrame: open ? {
                                    AnyView(OrbitRankedOpenFrame(card: card, meta: meta, focused: false,
                                                                 trailers: trailers, trailerKey: trailerKey, size: frame))
                                } : nil,
                                opens: true)
                    .task(id: isFocused) { if openFromCell == nil { await dwell() } }
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
/// A row's tiles: lazy for the long rows, built whole for the short ones.
private struct OrbitRowStack<Content: View>: View {
    let lazy: Bool
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if lazy {
            LazyHStack(alignment: .bottom, spacing: spacing, content: content).scrollTargetLayout()
        } else {
            HStack(alignment: .bottom, spacing: spacing, content: content).scrollTargetLayout()
        }
    }
}

/// A row's scroll bound to its position only where the row is placed by its anchor.
private struct OrbitRowBinding: ViewModifier {
    let bound: Bool
    @Binding var scroll: ScrollPosition

    func body(content: Content) -> some View {
        if bound { content.scrollPosition($scroll) } else { content }
    }
}

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
struct OrbitContinueWatchingMenu: ViewModifier {
    let entry: WatchProgressEntry?
    let preview: MetaPreview
    let actions: StageHomeActions
    /// Steven (2026-10-29, device: back from a title opened from Continue Watching's menu, the page
    /// came back on the hero): the menu's ways to a title mark the card for the way back too.
    var onLeave: () -> Void = {}

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
        Self.perform(action, entry, preview: preview, actions: actions, onLeave: onLeave)
    }

    static func perform(_ action: TitleHoldMenuPolicy.CWAction, _ entry: WatchProgressEntry, preview: MetaPreview,
                        actions: StageHomeActions, onLeave: @escaping () -> Void) {
        // Steven (2026-10-29, device: the card's lifted image stayed over the title's page a moment):
        // the page opens once the menu has closed.
        let later: (@escaping () -> Void) -> Void = { go in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: go)
        }
        switch action {
        case .playManually:
            onLeave()
            later { actions.resume(ResumeTarget(entry: entry, forceManual: true)) }
        case .goToDetails:
            onLeave()
            later { actions.push(TitleRoute(preview: preview)) }
        case .markEpisodeWatched:
            WatchedRepository.shared.markWatched(
                item: WatchingActionsKt.watchedItemFromProgress(
                    entry: entry,
                    markedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000)
                )
            )
            WatchProgressRepository.shared.clearProgress(videoId: entry.videoId, parentMetaId: entry.parentMetaId)
        case .startOver:
            onLeave()
            later { actions.resume(ResumeTarget(entry: entry, startFromBeginning: true)) }
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
    /// The open title, as a place in the strip. Nouveaux films loops (Steven, 2026-10-28: "les
    /// lignes doivent être en boucle"): the place runs on past the end, its title taken round.
    @State private var lead = 0
    /// The Top 10 (Steven's choice A): its first place on screen. The row stays put while the open
    /// title is on screen — it opens in its own place — and slides only at the screen's edge.
    @State private var first = 0
    /// The row is sliding (the rank's glow waits for it to rest).
    @State private var sliding = false
    @State private var slideGeneration = 0
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.orbitFocusHidden) private var focusHidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ranked: Bool { row.style == .ranked }
    private var count: Int { row.cards.count }
    private var loops: Bool { !ranked && count >= 3 }
    private var gap: CGFloat { OrbitTileLayout.gap(row.style) }
    private var height: CGFloat { OrbitTileLayout.size(row.style).height }

    /// The title at place `v` (taken round in a looping row).
    private func index(_ v: Int) -> Int { count == 0 ? 0 : ((v % count) + count) % count }
    private func card(_ v: Int) -> OrbitCard { row.cards[index(v)] }

    /// A tile's room before its poster (the Top 10's rank).
    private func room(_ v: Int) -> CGFloat { ranked ? OrbitRankedTile.rankRoom(index(v) + 1) : 0 }
    private func width(_ v: Int, open: Bool) -> CGFloat {
        if ranked {
            return room(v) + (open ? OrbitNativeRankedOpenTile.frame(scale: 1).width : OrbitTileLayout.rankedPoster.width)
        }
        return open ? OrbitHomeLayout.frameWidth : OrbitHomeLayout.posterWidth
    }

    /// Place `v`'s left edge: the anchor (the open title, or the Top 10's first on screen) at the
    /// margin, the others beside it.
    private func x(_ v: Int, lead: Int, first: Int) -> CGFloat {
        let margin = OrbitHomeLayout.margin
        let anchor = ranked ? first : lead
        if v >= anchor {
            return margin + (anchor..<v).reduce(CGFloat(0)) { $0 + width($1, open: $1 == lead) + gap }
        }
        return margin - (v..<anchor).reduce(CGFloat(0)) { $0 + width($1, open: $1 == lead) + gap }
    }

    private var places: [Int] {
        guard count > 0 else { return [] }
        return ranked ? Array(0..<count) : Array((lead - 2)...(lead + 7))
    }

    /// The UIKit strip (Steven, 2026-10-29: "applique les réglages… même Nouveaux films").
    @State private var strip = OrbitStripRef()
    /// The strip holds the focus (the open frame drawn lit).
    @State private var stripHasFocus = false
    @State private var placedLoop = false
    /// The places of the strip: the titles repeated (the row loops), the lead starting in the middle.
    private var copies: Int { loops ? 7 : 1 }
    private var stripPlaces: Int { count * copies }

    var body: some View {
        if ranked {
            legacyBody
        } else {
            stripBody
        }
    }

    private var stripBody: some View {
        let L = OrbitHomeLayout.self
        let lit = stripHasFocus && !focusHidden
        return VStack(alignment: .leading, spacing: 14) {
            OrbitRowHeading(title: row.title, isCurrent: isCurrent)
                .padding(.leading, L.margin + 4)
            OrbitStripView(count: stripPlaces, identity: row.cards.map(\.id).joined(separator: ","), spacing: gap, height: height,
                           margin: L.margin, alignment: .bottom, pinned: true, lead: lead,
                           width: { v in v == lead ? L.frameWidth : L.posterWidth }, ref: strip,
                           tile: { v, _ in
                               v == lead
                                   ? AnyView(Color.clear.frame(width: L.frameWidth, height: height))
                                   : AnyView(OrbitPosterCard(card: card(v))
                                       .frame(width: L.posterWidth, height: height, alignment: .bottomLeading))
                           },
                           onFocus: { v in
                               guard let v else {
                                   DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                       if strip.controller?.focusedIndex == nil { stripHasFocus = false }
                                   }
                                   return
                               }
                               if !stripHasFocus {
                                   stripHasFocus = true
                                   onEnter()
                               }
                               if v != lead {
                                   lead = v
                                   leadChanged()
                               }
                           },
                           onSelect: { _ in if count > 0 { open(card(lead)) } })
                .frame(height: height)
                // The open frame, at the margin; the next title fades in inside it.
                .overlay(alignment: .bottomLeading) {
                    if count > 0 {
                        openFrame(card(lead), lit: lit)
                            .id(lead)
                            .transition(.opacity.animation(.easeInOut(duration: 0.22)))
                            .offset(x: L.margin)
                            .allowsHitTesting(false)
                    }
                }
            if row.style == .classic {
                ZStack(alignment: .topLeading) {
                    Color.clear
                    if isCurrent, count > 0 { details(card(lead)) }
                }
                .frame(width: 1200, height: OrbitNativeRow.infoHeight, alignment: .topLeading)
                .clipped()
                .padding(.top, 20)
                .padding(.bottom, -8)
                .padding(.leading, L.margin + 6)
            }
        }
        .onAppear {
            // A looping row starts in its middle copy (once).
            if loops, !placedLoop, count > 0 {
                placedLoop = true
                lead = count * 3 + index(lead)
            }
            // Back from a title opened here: its place takes the focus back.
            if let target = OrbitNativeRow.reopen, target.row == row.id,
               let i = row.cards.firstIndex(where: { $0.id == target.card }) {
                if i != index(lead) { lead = lead - index(lead) + i }
                let place = lead
                DispatchQueue.main.async { strip.controller?.restore(index: place) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .orbitHomeRowFocus)) { note in
            guard note.object as? String == row.id else { return }
            strip.controller?.takeFocus(on: lead)
        }
    }

    @ViewBuilder
    private var legacyBody: some View {
        let L = OrbitHomeLayout.self
        VStack(alignment: .leading, spacing: 14) {
            OrbitRowHeading(title: row.title, isCurrent: isCurrent)
                .padding(.leading, L.margin + 4)

            Button {
                if count > 0 { open(card(lead)) }
            } label: {
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                    ForEach(places, id: \.self) { v in
                        tile(v, open: v == lead)
                            .environment(\.orbitFocusHidden, focusHidden || v != lead)
                            .environment(\.orbitRankGlowHidden, sliding)
                            .offset(x: x(v, lead: lead, first: first))
                            .zIndex(v == lead ? 1 : 0)
                            .transition(.identity)
                    }
                }
                .frame(width: L.screenWidth, height: height, alignment: .bottomLeading)
                // Steven (2026-10-28: "image fantôme"): the open frame is drawn apart and the next
                // title fades in inside it — at the margin for Nouveaux films, in its own place
                // for the Top 10.
                .overlay(alignment: .bottomLeading) {
                    if count > 0 {
                        openFrame(card(lead))
                            .id(lead)
                            .transition(.opacity.animation(.easeInOut(duration: 0.22)))
                            .offset(x: x(lead, lead: lead, first: first) + room(lead))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(OrbitPlainStyle())
            .focused($rowFocused)
            .onMoveCommand { direction in
                // A swipe's steps come from the catcher alone (the system's move for it would
                // count it twice).
                if OrbitSwipeHub.shared.swiping, OrbitSwipeHub.shared.owner == row.id { return }
                switch direction {
                case .left: move(-1)
                case .right: move(1)
                default: break
                }
            }
            .frame(height: height)
            // Steven (2026-10-28: the touch surface no longer moved these rows): a swipe across the
            // clickpad moves the lead, one title per stretch of the swipe.
            .onChange(of: rowFocused, initial: true) { _, focused in
                if focused {
                    OrbitSwipeHub.shared.owner = row.id
                    OrbitSwipeHub.shared.onStep = { step in move(step) }
                } else if OrbitSwipeHub.shared.owner == row.id {
                    OrbitSwipeHub.shared.owner = nil
                    OrbitSwipeHub.shared.onStep = nil
                }
            }

            if row.style == .classic {
                ZStack(alignment: .topLeading) {
                    Color.clear
                    if isCurrent, count > 0 { details(card(lead)) }
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

    /// A title of the strip. The open one keeps only its room (and its rank): its frame is drawn
    /// apart (`openFrame`).
    @ViewBuilder
    private func tile(_ v: Int, open: Bool) -> some View {
        let card = card(v)
        let meta = metaStore.meta(for: card.preview)
        if ranked {
            OrbitRankedTile(card: card, meta: meta, rank: index(v) + 1, focused: open && rowFocused && !focusHidden,
                            openWidth: open ? OrbitNativeRankedOpenTile.frame(scale: 1).width : nil,
                            openFrame: open ? { AnyView(Color.clear) } : nil)
        } else if open {
            Color.clear.frame(width: width(v, open: true), height: height)
        } else {
            OrbitPosterCard(card: card)
                .frame(width: width(v, open: false), height: height, alignment: .bottomLeading)
        }
    }

    /// The open title's frame (its trailer in it).
    @ViewBuilder
    private func openFrame(_ card: OrbitCard, lit litOverride: Bool? = nil) -> some View {
        let meta = metaStore.meta(for: card.preview)
        let key = "\(row.id)|\(card.id)"
        let lit = litOverride ?? (rowFocused && !focusHidden)
        if ranked {
            OrbitRankedOpenFrame(card: card, meta: meta, focused: lit, trailers: trailers, trailerKey: key,
                                 size: OrbitNativeRankedOpenTile.frame(scale: 1))
        } else {
            OrbitNativeTrailerReader(host: trailers, key: key) { url in
                OrbitLeadFrame(card: card, meta: meta, focused: lit, trailerURL: url,
                               onTrailerFailure: { trailers.model.playbackFailed($0) },
                               onTrailerEnded: { trailers.model.playbackFinished() })
            }
            .shadow(color: .black.opacity(lit ? 0.55 : 0), radius: lit ? 18 : 0, y: lit ? 10 : 0)
            .animation(.easeOut(duration: 0.18), value: lit)
            .allowsHitTesting(false)
        }
    }

    private func move(_ step: Int) {
        let next = lead + step
        guard loops || row.cards.indices.contains(next) else { return }
        let nextFirst = ranked ? firstForMove(next) : first
        withAnimation(reduceMotion ? nil : OrbitHomeLayout.horizontal) {
            lead = next
            first = nextFirst
        }
        sliding = true
        slideGeneration &+= 1
        let generation = slideGeneration
        // (Steven: the glow came back late — now as the slide ends.)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            if generation == slideGeneration { sliding = false }
        }
        leadChanged()
    }

    private func firstForMove(_ next: Int) -> Int {
        var f = min(first, next)
        let limit = OrbitHomeLayout.screenWidth - OrbitHomeLayout.margin
        while f < next, x(next, lead: next, first: f) + width(next, open: true) > limit { f += 1 }
        return f
    }

    /// The lead's trailer, wash and the titles ahead.
    private func leadChanged() {
        guard count > 0 else { return }
        let card = card(lead)
        trailers.arm("\(row.id)|\(card.id)", item: card.preview)
        OrbitNativeHomeState.shared.art = card.landscape ?? metaStore.meta(for: card.preview)?.backdrop
        let around = ranked ? Array(max(0, lead - 2)..<min(count, lead + 8)) : Array((lead - 2)..<(lead + 8))
        OrbitMetaStore.shared.request(around.map { self.card($0).preview })
        // Steven (2026-10-28: the frame came up empty a moment, on the last titles above all): the
        // art of the titles around is fetched ahead at the frame's own size, so each new title's
        // image is already there when it fades in.
        let size = ranked ? OrbitNativeRankedOpenTile.frame(scale: 1)
                          : CGSize(width: OrbitHomeLayout.frameWidth, height: OrbitHomeLayout.cardHeight)
        let request = ArtworkDecodeRequest(size: .points(width: size.width, height: size.height), fill: true,
                                           scale: UIScreen.main.scale)
        let near = ranked ? Array(max(0, lead - 2)..<min(count, lead + 4)) : Array((lead - 2)..<(lead + 4))
        for v in near {
            let neighbour = self.card(v)
            let raw: String? = neighbour.landscape ?? metaStore.meta(for: neighbour.preview)?.backdrop
            guard let raw, let url = URL(string: raw) else { continue }
            let best = ArtworkURLUpgrade.upgraded(url, role: .backdrop) ?? url
            if ArtworkStore.cached(best, decode: request) == nil {
                Task { _ = try? await ArtworkStore.fetch(best, decode: request) }
            }
        }
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
        .id(lead)
        // Steven (2026-10-28): the synopsis fades in with the title in the frame; the old one goes
        // at once (two texts over each other were unreadable).
        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.05)), removal: .identity))
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
        if let i = row.cards.firstIndex(where: { $0.id == target.card }), i != index(lead) {
            var still = Transaction()
            still.disablesAnimations = true
            let place = loops ? lead - index(lead) + i : i
            withTransaction(still) {
                lead = place
                if ranked { first = firstForMove(place) }
            }
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


/// The open row holding the focus: where the clickpad's swipes go (one catcher for the page —
/// Steven: with one per row, Nouveaux films never moved).
@MainActor
final class OrbitSwipeHub {
    static let shared = OrbitSwipeHub()
    var owner: String?
    var onStep: ((Int) -> Void)?
    /// When the finger last travelled across the clickpad. Steven (2026-10-29, device: the Top 10
    /// went 2 → 4 on one swipe): the system turned the same swipe into a move too — while a swipe
    /// is under way, the open rows take their steps from the catcher alone.
    var lastTravel: TimeInterval = 0
    var swiping: Bool { ProcessInfo.processInfo.systemUptime - lastTravel < 0.35 }
}

/// Swipes across the remote's clickpad while `active`: one step per stretch of travel (left -1,
/// right +1). Installed on the window, alongside the focus engine (it never takes the touches).
struct OrbitSwipeCatcher: UIViewRepresentable {
    let active: Bool
    let onStep: (Int) -> Void

    final class Catcher: UIView, UIGestureRecognizerDelegate {
        var active = false
        var onStep: (Int) -> Void = { _ in }
        private var pan: UIPanGestureRecognizer?
        private var lastX: CGFloat = 0
        private var stepsThisSwipe = 0
        /// Points of travel for one title (the clickpad's whole width is about 1 900). Steven
        /// (2026-10-29, device: Nouveaux films needed two or three swipes): a shorter stretch, and a
        /// quick flick shorter than it still counts as one title when the finger lifts.
        private let stretch: CGFloat = 150
        private let flick: CGFloat = 45

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let pan { pan.view?.removeGestureRecognizer(pan); self.pan = nil }
            guard let window else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            pan.cancelsTouchesInView = false
            pan.delegate = self
            window.addGestureRecognizer(pan)
            self.pan = pan
        }

        @objc private func panned(_ pan: UIPanGestureRecognizer) {
            let t = pan.translation(in: pan.view)
            switch pan.state {
            case .began:
                lastX = t.x
                stepsThisSwipe = 0
            case .changed:
                guard active, abs(t.x) > abs(t.y) else { return }
                let travel = t.x - lastX
                if abs(t.x) > 20 { OrbitSwipeHub.shared.lastTravel = ProcessInfo.processInfo.systemUptime }
                if abs(travel) >= stretch {
                    lastX = t.x
                    stepsThisSwipe += 1
                    onStep(travel > 0 ? 1 : -1)
                }
            case .ended:
                let travel = t.x - lastX
                if active, stepsThisSwipe == 0, abs(t.x) > abs(t.y), abs(travel) >= flick {
                    OrbitSwipeHub.shared.lastTravel = ProcessInfo.processInfo.systemUptime
                    onStep(travel > 0 ? 1 : -1)
                }
                lastX = 0
                stepsThisSwipe = 0
            default:
                lastX = 0
                stepsThisSwipe = 0
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }

    func makeUIView(context: Context) -> Catcher {
        let view = Catcher()
        view.isUserInteractionEnabled = false
        view.active = active
        view.onStep = onStep
        return view
    }

    func updateUIView(_ view: Catcher, context: Context) {
        view.active = active
        view.onStep = onStep
    }
}
