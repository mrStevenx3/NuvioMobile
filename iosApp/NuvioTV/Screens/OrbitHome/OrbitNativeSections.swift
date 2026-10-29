import Combine
import SharedCore
import SwiftUI

// The platform pages, native (Steven, 2026-10-26: "fais-les toutes en même temps"). Each page
// keeps its own look — its hero, its rows drawn as before — but the way they move changes, as on
// Home:
//  - Up / Down: every section (the hero, each row) is a real button in a vertical scroll view;
//    the system moves the focus between them and slides the page (on the GPU) to the section,
//    instead of the page offsetting a whole drawn layer on every press.
//  - Left / Right: a row's lead lives in its own little box (`OrbitLeadBox`), so a press redraws
//    that row alone, not the whole page.
//  - Rows far from the focus are not drawn at all.
// (Native only: the old drawn pages and their switch are gone.)

/// A page's vertical scroll, observed by the one view that follows it.
@MainActor
final class OrbitScrollTracker: ObservableObject {
    @Published var y: CGFloat = 0
}

/// Its content fades out over the scroll's first `distance` points.
struct OrbitScrollFaded<Content: View>: View {
    @ObservedObject var tracker: OrbitScrollTracker
    let distance: CGFloat
    /// Built by the page, kept as is while only the scroll moves.
    let content: Content

    init(tracker: OrbitScrollTracker, distance: CGFloat, @ViewBuilder content: () -> Content) {
        self.tracker = tracker
        self.distance = distance
        self.content = content()
    }

    var body: some View {
        content.opacity(Double(1 - min(1, max(0, tracker.y / distance))))
    }
}

/// One row's focused title, observed by that row alone.
@MainActor
final class OrbitLeadBox: ObservableObject {
    @Published var lead = 0
    /// Bumped to give the row the focus (on its lead): Menu back, the page's own moves.
    @Published var focusRequest = 0
    /// Bumped to put a pinned row's lead back at the margin at once (Disney+: the row opening as the
    /// focus arrives — its tile grown in place, the row scrolled for the closed one).
    @Published var realign = 0
    /// The title opened from this row: the focus comes back on it on the way back.
    var reopen: Int?
    /// Where the row is scrolled (where it comes back to when rebuilt or back from a title).
    var offsetX: CGFloat?
    /// From the opening of a title until just after the way back (kept by the box: the row may be
    /// rebuilt meanwhile): only the reopened tile can take the focus.
    @Published var restoreLock = false
}

/// The rows' leads, read by the page (never observed by it: a lead change redraws only its row).
@MainActor
final class OrbitLeadStore {
    private var boxes: [String: OrbitLeadBox] = [:]

    func box(_ id: String) -> OrbitLeadBox {
        if let box = boxes[id] { return box }
        let box = OrbitLeadBox()
        boxes[id] = box
        return box
    }

    subscript(id: String) -> Int? {
        get { boxes[id]?.lead }
        set { box(id).lead = newValue ?? 0 }
    }

    func reset() {
        for box in boxes.values {
            if box.lead != 0 { box.lead = 0 }
            box.offsetX = nil
        }
    }
}

/// Shows `value` once it has stayed the same `delay` seconds (a new key while it waits restarts the
/// wait); at once when `delay` is 0.
struct OrbitAfterRest<Value, Content: View>: View {
    let key: String
    let value: Value
    let delay: Double
    @ViewBuilder let content: (Value) -> Content

    @State private var shown: Value?
    @State private var shownKey: String?
    @State private var work: DispatchWorkItem?

    var body: some View {
        content(shownKey == nil ? value : (shown ?? value))
            .onChange(of: key, initial: true) { _, new in
                work?.cancel()
                let latest = value
                if delay <= 0 || shownKey == nil {
                    shown = latest
                    shownKey = new
                    return
                }
                let item = DispatchWorkItem { shown = latest; shownKey = new }
                work = item
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            }
    }
}

/// Redraws its content when its box's lead changes (and only it).
struct OrbitLeadReader<Content: View>: View {
    @ObservedObject var box: OrbitLeadBox
    @ViewBuilder let content: (Int) -> Content

    var body: some View { content(box.lead) }
}

/// The page's sections as real buttons in a vertical scroll view the system moves.
struct OrbitNativeSections<SectionContent: View>: View {
    /// Sections: the hero (when `hasHero`), then the rows.
    let count: Int
    let hasHero: Bool
    /// Each section's height in the column (the rows drawn as before, at their pitch).
    let height: (Int) -> CGFloat
    /// The line under the screen's top a focused section's top rests on.
    let topLine: CGFloat
    /// The page's current section (the hero: 0).
    let current: Int
    /// The rows above the current one hide (the page's own top shows there).
    var hidesAbove = true
    let onFocus: (Int) -> Void
    /// Left / Right on the focused section (the page's own move: its hero, or the row's lead).
    let onMove: (MoveCommandDirection) -> Void
    let onSelect: () -> Void
    var onExit: (() -> Void)? = nil
    /// Up from the hero (nil: the system's own — the bar above).
    var onUpFromTop: (() -> Void)? = nil
    /// The page holds the focus (or lost it: the bar, the search).
    var onFocusChange: ((Bool) -> Void)? = nil
    /// The hero is the page's own view (a carousel of its own buttons), not a button of ours:
    /// `focusHero` gives it the focus (Menu back to the top, the arrival).
    var customHero = false
    var focusHero: (() -> Void)? = nil
    /// The rows hold their own buttons (`OrbitNativeTileStrip`): they report their focus through
    /// `onFocus`, and `focusRow` gives a row the focus.
    var rowsFocusable = false
    /// Told the page's scroll on every frame (a hero that fades as the page moves).
    var tracker: OrbitScrollTracker? = nil
    var focusRow: ((Int) -> Void)? = nil
    /// Each section's own line (nil: `topLine` for all).
    var line: ((Int) -> CGFloat)? = nil
    @ViewBuilder let content: (Int, Bool) -> SectionContent

    @FocusState private var focus: Int?

    private var heroCount: Int { hasHero ? 1 : 0 }

    private func lineOf(_ s: Int) -> CGFloat { line?(s) ?? topLine }

    /// The section the page is aligned on.
    @State private var position: Int?
    /// Steven (2026-10-29: "partout pareil"): Home's vertical move on every platform page — every
    /// move asked for on Apple's curve (full speed at the press, easing to rest in 0.4 s), no scroll
    /// binding the system rewrites at each step of its own move.
    @State private var scroll = ScrollPosition(idType: Int.self)
    @State private var lastGo: TimeInterval = 0
    @State private var systemScrollOff = false

    private func go(to s: Int, animated: Bool = true) {
        if position == s, ProcessInfo.processInfo.systemUptime - lastGo < 0.2 { return }
        lastGo = ProcessInfo.processInfo.systemUptime
        position = s
        // (As Home: one mover — past the first row the system's own scroll is off, no nudge after
        // the page rests; nothing redrawn mid-move by details arriving.)
        systemScrollOff = s >= heroCount + 1
        OrbitMetaStore.shared.holdPublishing(for: 0.6)
        if animated && !UIAccessibility.isReduceMotionEnabled {
            withAnimation(.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.4)) { scroll.scrollTo(id: s, anchor: .top) }
        } else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { scroll.scrollTo(id: s, anchor: .top) }
        }
    }
    @State private var heroLocked = false
    @State private var builtAll = false
    /// The section last asked to take the focus (read live by the retries below).
    @State private var wanted: Int?

    var body: some View {
        let W = OrbitHomeLayout.screenWidth
        // Steven (device, 2026-10-26: "le défilement dans le studio fonctionne parfaitement, il faut
        // mettre ce défilement partout"): the studio page's scroll — a vertical scroll view aligned on
        // its sections, the page bringing the focused one to its line on one curve (the line is the
        // top margin, so each section keeps its own). Touch and Up to the bar are the system's again.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { s in
                    Group {
                    if customHero && s == 0 {
                        content(0, false)
                            .frame(width: W, height: height(0), alignment: .topLeading)
                            .focusSection()
                            .disabled(heroLocked)
                    } else if rowsFocusable && s >= heroCount {
                        // Every row built once, as Home's (Steven, 2026-10-29: the vertical moves
                        // shook — a row coming within reach was built during the page's slide).
                        Group {
                            // Every row built once settled in (as Home's: none built during a slide);
                            // at the opening, only those near the focus (Steven: the platform's opening
                            // hitched while every row was built under it).
                            if builtAll || abs(s - current) <= 3 { content(s, false) } else { Color.clear }
                        }
                        .frame(width: W, height: height(s), alignment: .topLeading)
                        // Back from a title, only the row it was opened from can take the focus a
                        // moment (Steven's video, Disney+: it landed in the row above, then came back).
                        .disabled(heroLocked && s != current)
                        .transformEnvironment(\.orbitFocusHidden) { $0 = $0 || (heroLocked && s != current) }
                        .focusSection()
                        // Steven (simulator: Up in the platforms went astray): the row above is hidden
                        // (transparent: the system cannot focus it) — Up goes to it explicitly.
                        .onMoveCommand { direction in
                            // (From the row the press came from: the system may already have jumped
                            // to the hero — Steven, Hulu: the Top 10 above was skipped.)
                            if direction == .up, hidesAbove, s > 0, current != s - 1 { onFocus(s - 1) }
                        }
                    } else {
                    Button(action: onSelect) {
                        OrbitNativeSectionLabel(live: abs(s - current) <= 3) { focused in
                            content(s, focused)
                        }
                        .frame(width: W, height: height(s), alignment: .topLeading)
                        .opacity(hidesAbove && s < current ? 0 : 1)
                        .animation(.easeOut(duration: 0.14), value: s < current)
                    }
                    .buttonStyle(OrbitPlainStyle())
                    .focused($focus, equals: s)
                    .disabled(heroLocked && s < heroCount)
                    .onMoveCommand { direction in
                        switch direction {
                        case .left, .right: onMove(direction)
                        case .up where s == 0: onUpFromTop?()
                        default: break
                        }
                    }
                    }
                    }
                    .id(s)
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, OrbitHomeLayout.screenHeight)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition($scroll)
        .scrollDisabled(systemScrollOff)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, y in
            if let tracker, abs(tracker.y - y) > 0.5 { tracker.y = y }
        }
        // The line follows the page's section only (Steven's videos, Prime Video / Paramount+: the
        // rows jumped — the line also followed the section the scroll wrote back mid-move).
        .contentMargins(.top, lineOf(current), for: .scrollContent)
        .scrollClipDisabled()
        // The rows above the current one slide away under the page's top, as on Home (Steven's
        // video, Prime Video: a row vanished on the spot when the focus left it, before the page
        // had moved). A soft edge just above the line, not a switch on each row.
        .mask {
            if hidesAbove, current >= heroCount {
                VStack(spacing: 0) {
                    // (Steven, 2026-10-29, Prime: bits of the row above showed through the soft edge —
                    // the edge closer to the line, shorter.)
                    Color.clear.frame(height: max(0, lineOf(current) - 28))
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 22)
                    Color.black
                }
                .frame(width: W, height: OrbitHomeLayout.screenHeight, alignment: .top)
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .onExitCommand(perform: onExit)
        // Only the hero is a button of ours: on the way back to a row, nothing pulls the focus up to
        // it (Steven, simulator: back from a title the page came back on its hero).
        .defaultFocus($focus, !customHero && current == 0 ? 0 : nil, priority: .userInitiated)
        .onChange(of: focus) { old, s in
            OrbitTrace.log("sections focus \(String(describing: old)) -> \(String(describing: s)) current=\(current)")
            // (With rows of their own buttons, this focus is the hero's alone: Steven, simulator —
            // DÉTAILS no longer lit when the hero took the focus.)
            if (old == nil) != (s == nil) { onFocusChange?(s != nil) }
            guard let s else { return }
            if s != current { onFocus(s) }
        }
        // The section changed (the focus moved, Menu back to the top, a filter reset): the page
        // slides to it, and a section the focus is not in yet takes it.
        .onChange(of: current) { _, c in
            go(to: c)
            take(c)
        }
        .onAppear {
            go(to: current, animated: false)
            if !builtAll { DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { builtAll = true } }
            // Back to a row (from a title): the hero out of the focus's reach a moment.
            if current >= heroCount, heroCount > 0 {
                heroLocked = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { heroLocked = false }
            }
            // (Rebuilt by a filter chosen in the bar: the focus stays in the bar.)
            DispatchQueue.main.async { if !OrbitCollectionBarFocus.held { take(current) } }
        }
    }

    /// Section `c` takes the focus (if it does not hold it already).
    private func take(_ c: Int) {
        wanted = c
        OrbitTrace.log("sections take \(c) focus=\(String(describing: focus))")
        if customHero && c == 0 {
            focusHero?()
        } else if rowsFocusable && c >= heroCount {
            focusRow?(c)
        } else if focus != c {
            focus = c
            // Steven (Disney+ / Hulu: Up from the first row, the page went up but the focus stayed
            // in the row — the next Down went further down): the hero was still fading in (hidden,
            // not focusable) at the ask. Asked again until it holds.
            let asked = ProcessInfo.processInfo.systemUptime
            for delay in [0.06, 0.18, 0.35, 0.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard wanted == c, focus != c, !ViewerInputClock.shared.hasInput(since: asked) else { return }
                    OrbitTrace.log("sections retake \(c) after \(delay)")
                    focus = c
                }
            }
        }
    }
}

/// A platform row's titles as real buttons in a horizontal scroll view (Steven: the remote's touch
/// surface slides them as on Home; the system slides the row on the GPU). The focused title stays
/// at the margin (the row slides under it); its row's box follows it.
struct OrbitNativeTileStrip<Tile: View>: View {
    let count: Int
    let spacing: CGFloat
    let height: CGFloat
    /// The last title's width (room after it, so it reaches the margin too).
    let lastWidth: CGFloat
    @ObservedObject var box: OrbitLeadBox
    var margin: CGFloat = OrbitHomeLayout.margin
    var alignment: VerticalAlignment = .bottom
    /// The focused title comes to the margin — only where its synopsis sits under the row (Netflix).
    /// Elsewhere the row scrolls as Apple's app does: the focus runs over the titles on screen and
    /// the row moves only when it reaches the edge (Steven).
    var keepsLeadAtMargin = false
    /// The row took the focus (from outside it) / let it go.
    let onEnter: () -> Void
    var onLeave: () -> Void = {}
    let onSelect: () -> Void
    /// The focus moved to another title of the row (the page's look-ahead, its trailer).
    var onLeadChange: (Int) -> Void = { _ in }
    /// A pinned row's Left: the closed width (with its gap) of the title the focus goes to. The row
    /// is put at once where it ends and slid there from where it was (Steven: Right slid, Left
    /// jumped — the title growing before the scroll's aim, the system dropped the slide).
    var leftSlide: ((Int) -> CGFloat)? = nil
    /// Each title's width when the page knows it (a title wider when open: Netflix's lead). Else
    /// the tiles are measured once.
    var width: ((Int) -> CGFloat)? = nil
    /// What the page's tiles depend on besides the row's lead and the titles' details (nil: the
    /// tiles redrawn at every update).
    var redrawKey: AnyHashable? = nil
    @ViewBuilder let tile: (_ index: Int, _ focused: Bool) -> Tile

    @FocusState private var focus: Int?
    @State private var anchor: Int?
    @State private var scroll = ScrollPosition(idType: Int.self)
    @State private var holds = false
    @State private var slideX: CGFloat = 0

    @State private var rowProxy: ScrollViewProxy?
    @State private var leadWork: DispatchWorkItem?
    /// When the way back from a title began (0: not coming back).
    @State private var restoringSince: TimeInterval = 0
    @State private var disappeared = false

    /// The row put back where it is shown: a pinned row on its title at the margin (exact), the
    /// others at their kept scroll.
    private func settle(on index: Int?) {
        var still = Transaction()
        still.disablesAnimations = true
        if keepsLeadAtMargin, let index {
            withTransaction(still) { scroll.scrollTo(id: index, anchor: .leading) }
        }
        // A row scrolled freely is never moved by us (Steven's video, Disney+ Top 10: at the
        // press the row slid right — the kept scroll put back — then again on the way back). The
        // system keeps it where it is; only the title's tile can take the focus meanwhile.
    }

    private func lockForReturn(_ index: Int) {
        // Nothing touches the row at the press (Steven's video: the poster slid right before the
        // title's page came — the lock and the scroll's aim moved it): both wait for the page to
        // have gone (`onDisappear`), the row no longer on screen.
    }

    /// The UIKit strip (the way back, the page's focus requests go through it).
    @State private var strip = OrbitStripRef()

    /// Steven (2026-10-29: "applique-le de PARTOUT"): the row is a UIKit collection view the focus
    /// engine scrolls, as Home's rows and Apple's TV app (`OrbitStripView`); the page's tiles in it.
    var body: some View {
        OrbitStripView(count: count, spacing: spacing, height: height, margin: margin, alignment: alignment,
                       pinned: keepsLeadAtMargin, lead: min(box.lead, max(0, count - 1)),
                       // (Without the page's widths: every title as wide as the last — the rows' own rule.)
                       width: width ?? { _ in lastWidth },
                       redrawKey: redrawKey.map { AnyHashable([AnyHashable(box.lead), AnyHashable(OrbitMetaStore.shared.revision), $0]) },
                       ref: strip,
                       tile: { i, focused in AnyView(tile(i, focused)) },
                       onFocus: { stripFocus($0) },
                       onSelect: { i in
                           box.reopen = i
                           onSelect()
                       })
            .frame(height: height)
            .onChange(of: box.focusRequest) { _, _ in
                strip.controller?.takeFocus(on: min(box.lead, max(0, count - 1)))
            }
            .onChange(of: box.realign) { _, _ in
                guard keepsLeadAtMargin else { return }
                strip.controller?.place(min(box.lead, max(0, count - 1)), animated: false)
            }
            .onDisappear { disappeared = true }
            .onAppear {
                disappeared = false
                // Back from a title opened here: its tile takes the focus again.
                if let back = box.reopen {
                    DispatchQueue.main.async { strip.controller?.restore(index: back) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { if box.reopen == back { box.reopen = nil } }
                } else if keepsLeadAtMargin {
                    DispatchQueue.main.async { strip.controller?.place(min(box.lead, max(0, count - 1)), animated: false) }
                }
            }
    }

    private func stripFocus(_ new: Int?) {
        guard let new else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                if strip.controller?.focusedIndex == nil, holds { holds = false; onLeave() }
            }
            return
        }
        if !holds {
            holds = true
            onEnter()
        }
        if box.lead != new {
            // Steven (2026-10-29: Nouveaux films' scroll "exactement le même de partout"): the lead set
            // plainly, as Home's new films — the strip slides on its own curve, the frame fades;
            // nothing else of the page is animated with it.
            box.lead = new
            // Steven (2026-10-29: the platforms' rows not fluid): the page's own work for the new title
            // (its trailer, its look-ahead) redrew the whole page under every step of the slide — it
            // waits for the remote to rest, as Home's colour does.
            leadWork?.cancel()
            let work = DispatchWorkItem { onLeadChange(new) }
            leadWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private var legacyBody: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: alignment, spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    Button {
                        box.reopen = i
                        lockForReturn(i)
                        onSelect()
                    } label: {
                        OrbitNativeStripLabel { focused in tile(i, focused) }
                    }
                    .buttonStyle(OrbitPlainStyle())
                    .focused($focus, equals: i)
                    // The focused tile above its neighbours (Steven, Paramount+: it went behind the
                    // poster on its right).
                    .zIndex(focus == i ? 1 : 0)
                    // Back from a title, only its tile can take the focus a moment.
                    .disabled(box.restoreLock && box.reopen != nil && box.reopen != i)
                    .transformEnvironment(\.orbitFocusHidden) {
                        $0 = $0 || ((box.restoreLock || restoringSince > 0) && box.reopen != nil && box.reopen != i)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 40)
            .offset(x: slideX)
        }
        .scrollTargetBehavior(OrbitRowScrollBehavior(aligned: !keepsLeadAtMargin))
        // (Only a pinned row is driven by its anchor; an unpinned one is not bound: the written-back
        // first title, half off screen, was brought in on the way back — Steven.)
        .scrollPosition($scroll)
        // Where the row is scrolled, kept in its box (not while it comes back from a title): the way
        // back puts it exactly there again (Steven, simulator: every return moved it right).
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, x in
            if restoringSince == 0, !disappeared, !box.restoreLock { box.offsetX = x }
        }
        .contentMargins(.leading, margin, for: .scrollContent)
        .contentMargins(.trailing, keepsLeadAtMargin ? max(margin, OrbitHomeLayout.screenWidth - margin - lastWidth) : margin,
                        for: .scrollContent)
        .scrollClipDisabled()
        .onAppear { rowProxy = proxy }
        }
        .padding(.vertical, -40)
        .frame(height: height)
        .defaultFocus($focus, min(box.lead, max(0, count - 1)), priority: .userInitiated)
        .onChange(of: focus) { _, new in
            guard let new else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    if focus == nil, holds { holds = false; onLeave() }
                }
                return
            }
            // Back from a title: a landing on another title is the system's, not the viewer's —
            // sent straight back, the row unchanged (Steven: it went to a neighbour, then came back).
            if let back = box.reopen, new != back, restoringSince > 0,
               !ViewerInputClock.shared.hasInput(since: restoringSince) {
                DispatchQueue.main.async { focus = back }
                return
            }
            let moving = holds
            if !holds {
                holds = true
                onEnter()
            }
            if box.lead != new {
                // Steven: Netflix's rows move as Home's first row does — the same curve for the tile
                // opening and the row sliding.
                withAnimation(OrbitHomeLayout.horizontal) { box.lead = new }
                onLeadChange(new)
            }
            if keepsLeadAtMargin, anchor != new {
                let old = anchor
                anchor = new
                if let leftSlide, let old, new < old, old - new <= 3 {
                    var still = Transaction()
                    still.disablesAnimations = true
                    let distance = (new..<old).reduce(CGFloat(0)) { $0 + leftSlide($1) }
                    withTransaction(still) {
                        slideX = -distance
                        scroll.scrollTo(id: new, anchor: .leading)
                    }
                    withAnimation(OrbitHomeLayout.horizontal) { slideX = 0 }
                } else {
                    withAnimation(OrbitHomeLayout.horizontal) { scroll.scrollTo(id: new, anchor: .leading) }
                }
            }
            // The open tile grows while the scroll is aimed: once open, the title back exactly at
            // the margin (Steven, simulator: it drifted right).
            if keepsLeadAtMargin, moving {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard focus == new else { return }
                    withAnimation(.easeOut(duration: 0.16)) { scroll.scrollTo(id: new, anchor: .leading) }
                }
            }
        }
        // An unpinned row remembers where it was scrolled (its first title on screen): rebuilt —
        // back from a title, far from the page's section — it comes back there (Steven: it moved).
        .onChange(of: box.realign) { _, _ in
            guard keepsLeadAtMargin else { return }
            let target = min(box.lead, max(0, count - 1))
            anchor = target
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { scroll.scrollTo(id: target, anchor: .leading) }
        }
        .onChange(of: box.focusRequest) { _, _ in
            let target = min(box.lead, max(0, count - 1))
            if focus != target { focus = target }
        }
        // The page gone over a title opened here: the scroll's aim set to where the row is, and only
        // the title's tile able to take the focus until the way back is over.
        .onDisappear {
            disappeared = true
            if let back = box.reopen {
                settle(on: back)
                box.restoreLock = true
            }
        }
        .onAppear {
            let lead = min(box.lead, max(0, count - 1))
            // Pinned rows keep it at the margin; the others are brought back to it only when the
            // row is rebuilt deep inside (its title must exist to take the focus back).
            // (Steven, simulator: back from a title an unpinned row jumped to its title, then slid
            // back to where it was: only a pinned row is brought to it.)
            // (An unpinned row is left where it is: re-anchored on its first title it moved — Steven.)
            disappeared = false
            // The row exactly where it was (rebuilt, or back from a title).
            if keepsLeadAtMargin { anchor = lead }
            settle(on: box.reopen ?? lead)
            // Back from a title opened here: its card takes the focus again (asked a few times,
            // the system's own landing comes late).
            if let back = box.reopen {
                let appeared = ProcessInfo.processInfo.systemUptime
                restoringSince = appeared
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { restoringSince = 0; box.restoreLock = false }
                for delay in [0.0, 0.15, 0.35, 0.6, 0.9] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        guard box.reopen == back, !ViewerInputClock.shared.hasInput(since: appeared) else { return }
                        if focus != back { focus = back }
                        settle(on: back)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if box.reopen == back { box.reopen = nil } }
            }
        }
    }
}

private struct OrbitNativeStripLabel<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @Environment(\.isFocused) private var systemFocused
    /// Back from a title, a tile the system lands on a moment is not drawn focused (Steven: the
    /// focus seen going left, then coming back).
    @Environment(\.orbitFocusHidden) private var focusHidden
    private var isFocused: Bool { systemFocused && !focusHidden }

    var body: some View { content(isFocused) }
}

/// A section's content, drawn focused as its button is; empty while far from the focus.
private struct OrbitNativeSectionLabel<Content: View>: View {
    let live: Bool
    @ViewBuilder let content: (Bool) -> Content
    @Environment(\.isFocused) private var systemFocused
    /// Back from a title, a tile the system lands on a moment is not drawn focused (Steven: the
    /// focus seen going left, then coming back).
    @Environment(\.orbitFocusHidden) private var focusHidden
    private var isFocused: Bool { systemFocused && !focusHidden }

    var body: some View {
        if live {
            content(isFocused)
        } else {
            Color.clear
        }
    }
}

// MARK: - Trailers on native pages

/// Orbit's one trailer object (Steven, 2026-10-26: back on Home and the studios, then "un truc
/// unifié": every page uses it). Kept out of the
/// pages' own state: arming it, or the trailer starting, redraws only the few views that play it
/// (`OrbitNativeTrailerReader`), never a whole page.
@MainActor
final class OrbitNativeTrailerHost: ObservableObject {
    let model = InlineTrailerCardModel()
    let motion = OrbitHomeMotion()
    @Published private(set) var key: String?
    private var relay: AnyCancellable?

    init() {
        model.restSource = .custom(motion)
        relay = model.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// The focus stopped on a title that plays its trailer here (after the usual rest).
    /// The page is covered by a title (or gone): nothing starts behind it (Steven: a thumbnail's
    /// trailer kept playing, its sound under the title's page).
    var suspended = false

    func arm(_ key: String, item: MetaPreview, reduceMotion: Bool = false) {
        motion.stamp()
        guard !suspended else { return }
        guard self.key != key else { return }
        model.reset()
        self.key = nil
        guard UserDefaults.standard.object(forKey: OrbitHomeSetting.trailersKey) as? Bool ?? true,
              UIAccessibility.isVideoAutoplayEnabled else { return }
        model.prefersReducedMotion = reduceMotion
        model.restSource = .custom(motion)
        self.key = key
        model.focusChanged(true, item: item)
    }

    /// The focus left for a title without one, or the page went away.
    func stop(abort: Bool = false) {
        motion.stamp()
        guard key != nil || abort else { return }
        model.reset(abortStages: abort)
        key = nil
    }

    func url(for key: String) -> String? {
        self.key == key ? model.playingURL : nil
    }

    // Steven (2026-10-26: "un truc unifié"): every Orbit page plays its trailers through this one
    // object — the drawn pages too, with the same calls they made on the bare model.

    var playingURL: String? { model.playingURL }
    var prefersReducedMotion: Bool {
        get { model.prefersReducedMotion }
        set { model.prefersReducedMotion = newValue }
    }
    var restSource: RowRestSource {
        get { model.restSource }
        set { model.restSource = newValue }
    }

    func focusChanged(_ focused: Bool, item: MetaPreview) {
        if focused {
            key = "\(item.type):\(item.id)"
            model.focusChanged(true, item: item)
        } else {
            reset()
        }
    }

    func reset(abortStages: Bool = false) {
        model.reset(abortStages: abortStages)
        key = nil
    }

    func playbackFailed(_ report: TrailerFailureReport) { model.playbackFailed(report) }
    func playbackFinished() { model.playbackFinished() }
}

/// Hands its content the trailer playing for `key` (nil: none), redrawn alone as it changes.
struct OrbitNativeTrailerReader<Content: View>: View {
    @ObservedObject var host: OrbitNativeTrailerHost
    let key: String
    @ViewBuilder let content: (String?) -> Content

    var body: some View { content(host.url(for: key)) }
}


private struct OrbitFocusHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

private struct OrbitRankGlowHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The Top 10's rank glow off while its row slides (Steven: the glow travelling with the figure
    /// looked poor) — it comes back once the row rests.
    var orbitRankGlowHidden: Bool {
        get { self[OrbitRankGlowHiddenKey.self] }
        set { self[OrbitRankGlowHiddenKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// A tile drawn unfocused even while the system holds the focus on it (the moment of a return
    /// from a title, when the system's own landing is sent back to the title's tile).
    var orbitFocusHidden: Bool {
        get { self[OrbitFocusHiddenKey.self] }
        set { self[OrbitFocusHiddenKey.self] = newValue }
    }
}
