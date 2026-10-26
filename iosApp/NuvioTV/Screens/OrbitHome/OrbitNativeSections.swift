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
// Settings ▸ Nouvel accueil off brings the drawn pages back.

/// One row's focused title, observed by that row alone.
@MainActor
final class OrbitLeadBox: ObservableObject {
    @Published var lead = 0
    /// Bumped to give the row the focus (on its lead): Menu back, the page's own moves.
    @Published var focusRequest = 0
    /// The title opened from this row: the focus comes back on it on the way back.
    var reopen: Int?
    /// An unpinned row's first title on screen (where it comes back to when rebuilt).
    var firstVisible: Int?
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
        for box in boxes.values where box.lead != 0 { box.lead = 0 }
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
    var focusRow: ((Int) -> Void)? = nil
    /// Each section's own line (nil: `topLine` for all).
    var line: ((Int) -> CGFloat)? = nil
    @ViewBuilder let content: (Int, Bool) -> SectionContent

    @FocusState private var focus: Int?

    private var heroCount: Int { hasHero ? 1 : 0 }

    private func lineOf(_ s: Int) -> CGFloat { line?(s) ?? topLine }

    /// The section the page is aligned on.
    @State private var position: Int?
    @State private var heroLocked = false

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
                        Group {
                            if abs(s - current) <= 3 { content(s, false) } else { Color.clear }
                        }
                        .frame(width: W, height: height(s), alignment: .topLeading)
                        .opacity(hidesAbove && s < current ? 0 : 1)
                        .animation(.easeOut(duration: 0.14), value: s < current)
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
        .scrollPosition(id: $position, anchor: .top)
        .contentMargins(.top, lineOf(position ?? current), for: .scrollContent)
        .scrollClipDisabled()
        .onExitCommand(perform: onExit)
        // Only the hero is a button of ours: on the way back to a row, nothing pulls the focus up to
        // it (Steven, simulator: back from a title the page came back on its hero).
        .defaultFocus($focus, !customHero && current == 0 ? 0 : nil, priority: .userInitiated)
        .onChange(of: focus) { old, s in
            // (With rows of their own buttons, this focus is the hero's alone: Steven, simulator —
            // DÉTAILS no longer lit when the hero took the focus.)
            if (old == nil) != (s == nil) { onFocusChange?(s != nil) }
            guard let s else { return }
            if s != current { onFocus(s) }
        }
        // The section changed (the focus moved, Menu back to the top, a filter reset): the page
        // slides to it, and a section the focus is not in yet takes it.
        .onChange(of: current) { _, c in
            if position != c { withAnimation(.easeInOut(duration: 0.32)) { position = c } }
            take(c)
        }
        .onAppear {
            position = current
            // Back to a row (from a title): the hero out of the focus's reach a moment.
            if current >= heroCount, heroCount > 0 {
                heroLocked = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { heroLocked = false }
            }
            DispatchQueue.main.async { take(current) }
        }
    }

    /// Section `c` takes the focus (if it does not hold it already).
    private func take(_ c: Int) {
        if customHero && c == 0 {
            focusHero?()
        } else if rowsFocusable && c >= heroCount {
            focusRow?(c)
        } else if focus != c {
            focus = c
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
    @ViewBuilder let tile: (_ index: Int, _ focused: Bool) -> Tile

    @FocusState private var focus: Int?
    @State private var anchor: Int?
    @State private var holds = false

    @State private var rowProxy: ScrollViewProxy?
    /// When the way back from a title began (0: not coming back).
    @State private var restoringSince: TimeInterval = 0
    /// From the opening of a title until just after the way back: only its tile can take the focus.
    @State private var restoreLock = false
    @State private var disappeared = false

    private func lockForReturn() {
        restoreLock = true
        disappeared = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { if !disappeared { restoreLock = false } }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: alignment, spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    Button {
                        box.reopen = i
                        lockForReturn()
                        onSelect()
                    } label: {
                        OrbitNativeStripLabel { focused in tile(i, focused) }
                    }
                    .buttonStyle(OrbitPlainStyle())
                    .focused($focus, equals: i)
                    // Back from a title, only its tile can take the focus a moment.
                    .disabled(restoreLock && box.reopen != nil && box.reopen != i)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 40)
        }
        .scrollTargetBehavior(OrbitRowScrollBehavior(aligned: !keepsLeadAtMargin))
        // (Only a pinned row is driven by its anchor; an unpinned one is not bound: the written-back
        // first title, half off screen, was brought in on the way back — Steven.)
        .scrollPosition(id: keepsLeadAtMargin ? $anchor : .constant(nil), anchor: .leading)
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
            if keepsLeadAtMargin, anchor != new { withAnimation(OrbitHomeLayout.horizontal) { anchor = new } }
            // The open tile grows while the scroll is aimed: once open, the title back exactly at
            // the margin (Steven, simulator: it drifted right).
            if keepsLeadAtMargin, moving {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard focus == new else { return }
                    anchor = nil
                    DispatchQueue.main.async {
                        guard focus == new else { return }
                        withAnimation(.easeOut(duration: 0.16)) { anchor = new }
                    }
                }
            }
        }
        // An unpinned row remembers where it was scrolled (its first title on screen): rebuilt —
        // back from a title, far from the page's section — it comes back there (Steven: it moved).
        .onChange(of: anchor) { _, first in
            if !keepsLeadAtMargin, let first { box.firstVisible = first }
        }
        .onChange(of: box.focusRequest) { _, _ in
            let target = min(box.lead, max(0, count - 1))
            if focus != target { focus = target }
        }
        .onDisappear { disappeared = true }
        .onAppear {
            let lead = min(box.lead, max(0, count - 1))
            // Pinned rows keep it at the margin; the others are brought back to it only when the
            // row is rebuilt deep inside (its title must exist to take the focus back).
            // (Steven, simulator: back from a title an unpinned row jumped to its title, then slid
            // back to where it was: only a pinned row is brought to it.)
            // (An unpinned row is left where it is: re-anchored on its first title it moved — Steven.)
            if keepsLeadAtMargin { anchor = lead }
            // Back from a title opened here: its card takes the focus again (asked a few times,
            // the system's own landing comes late).
            if let back = box.reopen {
                let appeared = ProcessInfo.processInfo.systemUptime
                restoringSince = appeared
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { restoringSince = 0; restoreLock = false }
                for delay in [0.0, 0.15, 0.35, 0.6, 0.9] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        guard box.reopen == back, !ViewerInputClock.shared.hasInput(since: appeared) else { return }
                        if focus != back { focus = back }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if box.reopen == back { box.reopen = nil } }
            }
        }
    }
}

private struct OrbitNativeStripLabel<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @Environment(\.isFocused) private var isFocused

    var body: some View { content(isFocused) }
}

/// A section's content, drawn focused as its button is; empty while far from the focus.
private struct OrbitNativeSectionLabel<Content: View>: View {
    let live: Bool
    @ViewBuilder let content: (Bool) -> Content
    @Environment(\.isFocused) private var isFocused

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
