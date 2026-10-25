import Combine
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
    @ViewBuilder let content: (Int, Bool) -> SectionContent

    @FocusState private var focus: Int?
    @State private var position: Int?

    var body: some View {
        let W = OrbitHomeLayout.screenWidth
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { s in
                    if customHero && s == 0 {
                        content(0, false)
                            .frame(width: W, height: height(0), alignment: .topLeading)
                            .focusSection()
                            .id(0)
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
                    .onMoveCommand { direction in
                        switch direction {
                        case .left, .right: onMove(direction)
                        case .up where s == 0: onUpFromTop?()
                        default: break
                        }
                    }
                    .id(s)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, OrbitHomeLayout.screenHeight)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position, anchor: .top)
        .contentMargins(.top, topLine, for: .scrollContent)
        .scrollClipDisabled()
        .onExitCommand(perform: onExit)
        .defaultFocus($focus, customHero && current == 0 ? nil : current, priority: .userInitiated)
        .onChange(of: focus) { old, s in
            if (old == nil) != (s == nil) { onFocusChange?(s != nil) }
            guard let s else { return }
            if s != current { onFocus(s) }
            if position != s { withAnimation(.easeInOut(duration: 0.34)) { position = s } }
        }
        // The page moved its section itself (Menu back to the top, a filter reset).
        .onChange(of: current) { _, c in
            if customHero && c == 0 {
                if focus != nil { focusHero?() }
            } else if focus != nil, focus != c { focus = c }
            if position != c { withAnimation(.easeInOut(duration: 0.34)) { position = c } }
        }
        .onAppear {
            position = current
            DispatchQueue.main.async {
                if customHero && current == 0 { focusHero?() } else if focus == nil { focus = current }
            }
        }
    }
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
