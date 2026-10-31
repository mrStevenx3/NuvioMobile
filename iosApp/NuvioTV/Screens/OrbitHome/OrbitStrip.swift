import SwiftUI
import UIKit

// Steven (2026-10-29, after Home's rows went UIKit: "c'est le jour et la nuit… applique-le de
// PARTOUT"): any page's row of titles as a UIKit collection view the focus engine scrolls (Apple's
// own curve: full speed at the press, an even slow-down), its tiles still the page's SwiftUI ones.
//  - Free rows scroll as Apple's: the focus runs over the titles on screen, the row moves at its edge.
//  - Pinned rows (`pinned`) keep the focused title at the margin (Netflix's), on the same curve.
//  - A tile may be wider focused (an opening frame): the row makes room on the focus's own move.

/// The strip's controller, for its page (the way back, the page's own focus requests).
@MainActor
/// Steven (2026-10-29, Prime's Originals, slow-motion video): in a row whose open title is held at
/// the margin, the title just left slid out on the left of the frame — a "ghost" going the wrong way
/// while the next one came from the right under the frame. Nothing shows left of the margin.
struct OrbitClipBeforeMargin: ViewModifier {
    let active: Bool
    let margin: CGFloat
    let height: CGFloat

    func body(content: Content) -> some View {
        if active {
            content.mask(alignment: .topLeading) {
                Rectangle()
                    .frame(width: OrbitHomeLayout.screenWidth * 2, height: height + 400)
                    .offset(x: margin - 6, y: -200)
            }
        } else {
            content
        }
    }
}

/// Steven (2026-10-29: "l'image à gauche doit être un peu assombrie"): in a row whose open title is
/// held at the margin, the bit of the title before it, left of the margin, is shaded.
/// Steven (2026-10-30, photo: a dark rectangle left of the posters — the shade was a band over the
/// row's whole height, on the lighter ground): the strip dims the titles themselves, each by how much
/// of it lies before the margin — nothing drawn where there is no poster.
struct OrbitShadeBeforeMargin: ViewModifier {
    let active: Bool
    let margin: CGFloat

    func body(content: Content) -> some View {
        content.environment(\.orbitShadesBeforeMargin, active)
    }
}

private struct OrbitShadesBeforeMarginKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var orbitShadesBeforeMargin: Bool {
        get { self[OrbitShadesBeforeMarginKey.self] }
        set { self[OrbitShadesBeforeMarginKey.self] = newValue }
    }
}

/// Steven (2026-10-30: "les affiches à gauche et à droite disparaissent d'un coup sec"): a row slid in
/// one animation is at its end at once for the collection view, which takes away at the start the
/// titles that will be off screen. Their pictures stand in for them, sliding out with the row, and go
/// when the row comes to rest.
@MainActor
final class OrbitLeavingTiles {
    private var views: [UIView] = []
    private var generation = 0

    /// Before sliding `collectionView` to `x`: the titles on screen that will be off it.
    func keep(_ collectionView: UICollectionView, goingTo x: CGFloat) -> Int {
        let now = collectionView.bounds
        let then = CGRect(x: x, y: now.minY, width: now.width, height: now.height)
        for cell in collectionView.visibleCells where cell.frame.intersects(now) && !cell.frame.intersects(then) {
            guard let picture = cell.snapshotView(afterScreenUpdates: false) else { continue }
            picture.frame = cell.frame
            picture.isUserInteractionEnabled = false
            collectionView.addSubview(picture)
            views.append(picture)
        }
        generation &+= 1
        return generation
    }

    /// The slide `generation` ended: the pictures go if no newer slide began.
    func done(_ generation: Int) {
        guard generation == self.generation else { return }
        views.forEach { $0.removeFromSuperview() }
        views.removeAll()
    }
}

final class OrbitStripRef {
    weak var controller: OrbitStripController?
}

struct OrbitStripView: UIViewControllerRepresentable {
    let count: Int
    /// What the tiles show (a change re-measures and redraws them).
    var identity: String = ""
    let spacing: CGFloat
    let height: CGFloat
    var margin: CGFloat = OrbitHomeLayout.margin
    var alignment: VerticalAlignment = .bottom
    var pinned = false
    /// Where the focus lands when the row is entered (pinned rows: their lead).
    var lead: Int = 0
    /// Entering the row lands on `lead` (pinned rows always; others when asked: a series' seasons).
    var entersOnLead: Bool? = nil
    /// Each tile's width when the page knows it (a tile wider when open, from the page's own state:
    /// Netflix's lead). Else the tiles are measured.
    var width: ((Int) -> CGFloat)? = nil
    /// What the tiles show, when the page knows it: the visible tiles are redrawn only when it
    /// changes (nil: at every update, as before). Steven (2026-10-29, platforms jerky up and down):
    /// each move redrew every tile on screen of the rows it touched; Home's rows redraw only on change.
    var redrawKey: AnyHashable? = nil
    /// A pinned row whose focused title opens wider (Netflix's, Home's new films): the extra room,
    /// added by the strip itself to the title it holds at the margin — on the very move of the focus.
    /// `width` then gives the closed widths. Steven (2026-10-29, Netflix's Top 10: a ghost going left
    /// and right): the room grew one beat after the focus moved, the row aimed at the old layout first,
    /// then at the new one — two slides.
    var openDelta: CGFloat? = nil
    let ref: OrbitStripRef
    let tile: (Int, Bool) -> AnyView
    var onFocus: (Int?) -> Void = { _ in }
    var onSelect: (Int) -> Void = { _ in }
    var menu: ((Int) -> UIMenu?)? = nil

    @Environment(\.orbitFocusHidden) private var focusHidden
    @Environment(\.isEnabled) private var enabled
    @Environment(\.orbitShadesBeforeMargin) private var shadesBeforeMargin

    func makeUIViewController(context: Context) -> OrbitStripController {
        let controller = OrbitStripController()
        ref.controller = controller
        update(controller)
        return controller
    }

    func updateUIViewController(_ controller: OrbitStripController, context: Context) {
        ref.controller = controller
        update(controller)
    }

    private func update(_ c: OrbitStripController) {
        c.tile = tile
        c.onFocus = onFocus
        c.onSelect = onSelect
        c.menu = menu
        c.lead = lead
        c.entersOnLead = entersOnLead ?? pinned
        c.widthOf = width
        c.redrawKey = redrawKey
        c.setOpenDelta(openDelta)
        c.shadesBeforeMargin = shadesBeforeMargin
        c.show(count: count, identity: identity, spacing: spacing, height: height, margin: margin,
               alignment: alignment, pinned: pinned, focusHidden: focusHidden, enabled: enabled)
    }
}

@MainActor
final class OrbitStripController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var tile: (Int, Bool) -> AnyView = { _, _ in AnyView(EmptyView()) }
    var onFocus: (Int?) -> Void = { _ in }
    var onSelect: (Int) -> Void = { _ in }
    var menu: ((Int) -> UIMenu?)?
    var lead = 0
    var entersOnLead = false
    var widthOf: ((Int) -> CGFloat)?
    /// The page's widths last laid out.
    private var widths: [CGFloat] = []

    private var collectionView: UICollectionView!
    private var count = 0
    private var identity = "\u{1}"
    private var spacing: CGFloat = 0
    private var height: CGFloat = 0
    private var margin: CGFloat = OrbitHomeLayout.margin
    private var alignment: VerticalAlignment = .bottom
    private(set) var pinned = false
    private var focusHidden = false
    private var enabled = true

    private(set) var focusedIndex: Int?
    /// Steven (2026-10-31, Paramount+, video: "le bord droit de la vignette vient d'abord se mettre
    /// derrière, et après le reste"): a title grown from its left edge reaches over the next one. On
    /// a move to the right, the title left behind shrinks back over the new one — kept above it
    /// until it has (else its overhang went under at once, the rest shrinking after).
    private var shrinkingOnTop: Int?
    /// The focused title sits at the row's left margin (first on screen, under the row's heading),
    /// where the row will rest after this move. Told before `onFocus`.
    private(set) var focusAtMargin = true
    /// When the focus last moved from one title of the row to another (only such a move slides a
    /// room open: arriving on the row or leaving it, the rooms are at once what they will be —
    /// Steven's video, Disney+: a room growing under a frame already open while the page moved).
    private var movedWithinAt: TimeInterval = 0
    /// The focus the row had at its last update (nil: it was not in the row).
    private var lastShowFocus: Int?
    private let entryGuide = UIFocusGuide()
    var redrawKey: AnyHashable?
    private var drawnKey: AnyHashable?
    /// The open title's extra room (nil: no title opens) and the place it is given to.
    private var openDelta: CGFloat?
    private var roomLead = 0

    func setOpenDelta(_ delta: CGFloat?) {
        guard delta != openDelta else { return }
        let opening = openDelta == nil && delta != nil
        openDelta = delta
        // (Steven, 2026-10-30, photo: the first time a Disney+ row was arrived on, its open frame
        // covered the next poster — the focus was already in the row, the room went to the title
        // it had been on before.) Opening, the room is the focused title's.
        if opening || focusedIndex == nil || delta == nil { roomLead = focusedIndex ?? lead }
        guard collectionView != nil else { return }
        // Opening / closing as the row is arrived on or left: at once.
        UIView.performWithoutAnimation {
            collectionView?.collectionViewLayout.invalidateLayout()
            collectionView?.layoutIfNeeded()
            if pinned, delta != nil { offsetToMargin(roomLead) }
        }
        // Only the open title's own tile changes (its room shown or its poster back): the others are
        // not redrawn as the row is arrived on or left (Steven: the page stopped a frame each move).
        collectionView.cellForItem(at: IndexPath(item: roomLead, section: 0))?.setNeedsUpdateConfiguration()
    }
    private var lastFocusedIndex: Int?
    private var onlyIndex: Int?
    private var onlyUntil: TimeInterval = 0
    private var preferredIndex: Int?
    /// Measured tile sizes (closed, focused), by place.
    private var closedSizes: [Int: CGSize] = [:]
    private var focusedSizes: [Int: CGSize] = [:]
    private lazy var sizer: UIHostingController<AnyView> = {
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.safeAreaRegions = []
        return host
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = false
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.insetsLayoutMarginsFromSafeArea = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.remembersLastFocusedIndexPath = false
        collectionView.register(OrbitRowStripCell.self, forCellWithReuseIdentifier: "tile")
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        // Steven (2026-10-29: season → episode → up → down again went to the row under the episodes):
        // coming into a row entered on its lead, the focus is caught over the whole row and handed
        // to its lead — wherever it comes from, even far from the lead.
        entryGuide.preferredFocusEnvironments = [collectionView]
        view.addLayoutGuide(entryGuide)
        NSLayoutConstraint.activate([
            entryGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            entryGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            entryGuide.topAnchor.constraint(equalTo: view.topAnchor),
            entryGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        entryGuide.isEnabled = false
        NotificationCenter.default.addObserver(forName: ViewerInputClock.didRecord, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.onlyIndex != nil else { return }
                switch ViewerInputClock.shared.lastKind {
                case .left?, .right?, .up?, .down?, .swipe?:
                    self.onlyIndex = nil
                    self.preferredIndex = nil
                default: break
                }
            }
        }
    }

    func show(count: Int, identity: String, spacing: CGFloat, height: CGFloat, margin: CGFloat,
              alignment: VerticalAlignment, pinned: Bool, focusHidden: Bool, enabled: Bool) {
        loadViewIfNeeded()
        let relayout = spacing != self.spacing || height != self.height || margin != self.margin
        self.spacing = spacing
        self.height = height
        self.margin = margin
        self.alignment = alignment
        self.pinned = pinned
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.minimumLineSpacing = spacing
            layout.minimumInteritemSpacing = spacing
            layout.sectionInset = UIEdgeInsets(top: 0, left: margin, bottom: 0,
                                               right: pinned ? max(margin, OrbitHomeLayout.screenWidth - margin - 300) : margin)
        }
        let stateChanged = focusHidden != self.focusHidden || enabled != self.enabled
        self.focusHidden = focusHidden
        self.enabled = enabled
        let keyChanged = redrawKey == nil || redrawKey != drawnKey || stateChanged
        drawnKey = redrawKey
        let newWidths: [CGFloat] = widthOf.map { w in (0..<count).map { w($0) } } ?? []
        if count != self.count || identity != self.identity {
            self.count = count
            self.identity = identity
            closedSizes = [:]
            focusedSizes = [:]
            widths = newWidths
            collectionView.reloadData()
            // A pinned row shows its lead at the margin from the start (a looping row: its middle copy).
            if pinned, focusedIndex == nil {
                let lead = self.lead
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.focusedIndex == nil, lead >= 0, lead < self.count else { return }
                    self.place(lead, animated: false)
                }
            }
        } else {
            if relayout { closedSizes = [:]; focusedSizes = [:]; collectionView.collectionViewLayout.invalidateLayout() }
            let widthsChanged = newWidths != widths
            if widthsChanged {
                let old = widths
                widths = newWidths
                // Moving inside the row (or a title rested on opening): the room changes on the row's
                // own curve; arriving on the row or leaving it, at once.
                if focusedIndex != nil, lastShowFocus != nil {
                    UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
                        self.collectionView.collectionViewLayout.invalidateLayout()
                        self.collectionView.layoutIfNeeded()
                        if self.pinned, let f = self.focusedIndex { self.offsetToMargin(f) }
                    } completion: { _ in
                        // Steven (2026-10-29, a studio's Top 10: the trailer's frame at the screen's
                        // edge stayed cut): a title grown open is brought wholly on screen, as Home's.
                        guard !self.pinned, let f = self.focusedIndex,
                              let frame = self.collectionView.layoutAttributesForItem(at: IndexPath(item: f, section: 0))?.frame
                        else { return }
                        let right = frame.maxX - self.collectionView.contentOffset.x
                        let limit = self.collectionView.bounds.width - OrbitHomeLayout.margin
                        if right > limit {
                            var offset = self.collectionView.contentOffset
                            offset.x += right - limit
                            self.collectionView.setContentOffset(offset, animated: true)
                        }
                    }
                    // A tile changing size is not stretched by the row's animation (Steven: the Top 10's
                    // poster jumped right, then came back left): it takes its room at once, its own
                    // view widening from its left; only the titles after it slide.
                    // (A row held at its margin moves its rooms with it: left to the animation.)
                    for i in newWidths.indices where !pinned && (!old.indices.contains(i) || old[i] != newWidths[i]) {
                        (collectionView.cellForItem(at: IndexPath(item: i, section: 0)) as? OrbitRowStripCell)?.settleFrame()
                    }
                } else {
                    UIView.performWithoutAnimation {
                        self.collectionView.collectionViewLayout.invalidateLayout()
                        self.collectionView.layoutIfNeeded()
                        if self.pinned, let f = self.focusedIndex { self.offsetToMargin(f) }
                    }
                }
            }
            if keyChanged || widthsChanged { redrawVisible() }
        }
        if focusedIndex == nil, openDelta != nil, roomLead != lead, lead >= 0, lead < count {
            roomLead = lead
            UIView.performWithoutAnimation {
                collectionView.collectionViewLayout.invalidateLayout()
                collectionView.layoutIfNeeded()
            }
        }
        lastShowFocus = focusedIndex
        entryGuide.isEnabled = entersOnLead && focusedIndex == nil && enabled
        // A pinned row the focus is not in: its lead kept at the margin (it changes before the row is
        // ever entered — a looping row moved to its middle copy).
        if pinned, focusedIndex == nil, lead != placedLead, lead >= 0, lead < count {
            placedLead = lead
            let target = lead
            DispatchQueue.main.async { [weak self] in
                guard let self, self.focusedIndex == nil, self.lead == target else { return }
                self.place(target, animated: false)
            }
        }
    }
    private var placedLead: Int?

    private func redrawVisible() {
        for path in collectionView.indexPathsForVisibleItems {
            collectionView.cellForItem(at: path)?.setNeedsUpdateConfiguration()
        }
    }

    // MARK: Sizes

    private func measure(_ index: Int, focused: Bool) -> CGSize {
        // (A width of 0 from the page: measured.)
        if widths.indices.contains(index), widths[index] > 0 { return CGSize(width: widths[index], height: height) }
        if focused, let known = focusedSizes[index] { return known }
        if !focused, let known = closedSizes[index] { return known }
        sizer.rootView = tile(index, focused)
        var size = sizer.sizeThatFits(in: CGSize(width: OrbitHomeLayout.screenWidth * 2, height: height))
        // A tile that takes whatever it is given (no width of its own): a poster's.
        if !size.width.isFinite || size.width <= 1 || size.width >= OrbitHomeLayout.screenWidth * 1.5 {
            size.width = (height * 2 / 3).rounded()
        }
        size.height = height
        if focused { focusedSizes[index] = size } else { closedSizes[index] = size }
        return size
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        var size = measure(indexPath.item, focused: indexPath.item == focusedIndex && !focusHidden)
        if let openDelta, indexPath.item == roomLead { size.width += openDelta }
        return size
    }

    // MARK: The page's requests

    /// The row takes the focus (on `index`, else its lead).
    func takeFocus(on index: Int? = nil) {
        preferredIndex = index ?? lead
        requestFocus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.preferredIndex = nil }
    }

    /// Back from a title opened here: its tile takes the focus back, the others locked a moment.
    func restore(index: Int) {
        guard index >= 0, index < count else { return }
        let start = ProcessInfo.processInfo.systemUptime
        preferredIndex = index
        onlyIndex = index
        onlyUntil = start + 1.2
        if pinned { place(index, animated: false) }
        for delay in [0.0, 0.15, 0.35, 0.6, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !ViewerInputClock.shared.hasInput(since: start), self.focusedIndex != index else { return }
                self.requestFocus()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            guard let self else { return }
            if self.preferredIndex == index { self.preferredIndex = nil }
            if self.onlyIndex == index { self.onlyIndex = nil }
        }
    }

    // MARK: Shade before the margin

    /// The titles left of the margin dimmed (each by the share of it there), on the row's own moves.
    var shadesBeforeMargin = false {
        didSet { if oldValue != shadesBeforeMargin, isViewLoaded { shadeVisible() } }
    }

    private func shade(_ cell: UICollectionViewCell) {
        guard shadesBeforeMargin else {
            if cell.contentView.alpha != 1 { cell.contentView.alpha = 1 }
            return
        }
        let left = cell.frame.minX - collectionView.bounds.minX
        let before = min(1, max(0, (margin - left) / max(1, cell.frame.width)))
        let alpha = 1 - 0.5 * before
        if abs(cell.contentView.alpha - alpha) > 0.001 { cell.contentView.alpha = alpha }
    }

    private func shadeVisible() {
        for cell in collectionView.visibleCells { shade(cell) }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        shadeVisible()
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        shade(cell)
    }

    /// The offset that puts `index` at the margin (set at once, inside an animation block).
    private func offsetToMargin(_ index: Int) {
        guard let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return }
        collectionView.contentOffset = CGPoint(x: max(0, frame.minX - margin), y: 0)
        shadeVisible()
    }

    /// A pinned row: `index` at the margin.
    func place(_ index: Int, animated: Bool) {
        guard index >= 0, index < count else { return }
        collectionView.layoutIfNeeded()
        guard let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return }
        let x = max(0, frame.minX - margin)
        if animated {
            // (Steven, 2026-10-30: "applique ce fonctionnement de PARTOUT" — the titles leaving slide out.)
            let generation = leaving.keep(collectionView, goingTo: x)
            UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
                self.collectionView.contentOffset = CGPoint(x: x, y: 0)
                self.shadeVisible()
            } completion: { [weak self] _ in
                self?.leaving.done(generation)
            }
        } else {
            collectionView.contentOffset = CGPoint(x: x, y: 0)
            shadeVisible()
        }
    }

    private func requestFocus() {
        view.window?.windowScene?.focusSystem?.requestFocusUpdate(to: collectionView)
        collectionView.setNeedsFocusUpdate()
        collectionView.updateFocusIfNeeded()
    }

    // MARK: Data

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "tile", for: indexPath)
        let index = indexPath.item
        cell.configurationUpdateHandler = { [weak self] cell, state in
            guard let self, let cell = cell as? OrbitRowStripCell, index < self.count else { return }
            let focused = state.isFocused && !self.focusHidden
            cell.layer.zPosition = state.isFocused ? 1 : (index == self.shrinkingOnTop ? 2 : 0)
            let alignment: Alignment = self.alignment == .top ? .topLeading
                : (self.alignment == .center ? .leading : .bottomLeading)
            // (A reused cell must not keep the state of the title it showed before.)
            cell.show(AnyView(self.tile(index, focused)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .id("\(self.identity)|\(index)")))
        }
        cell.setNeedsUpdateConfiguration()
        return cell
    }

    // MARK: Focus

    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        guard enabled else { return false }
        if let only = onlyIndex, ProcessInfo.processInfo.systemUptime < onlyUntil { return indexPath.item == only }
        // Steven (2026-10-29: from a season to the episodes, the focus landed a second on the episode
        // under it, then went to the first): a row entered on its lead lets only its lead take the
        // focus coming in — the system lands there directly, nothing to send it on afterwards.
        if entersOnLead, focusedIndex == nil, preferredIndex == nil, lead >= 0, lead < count {
            return indexPath.item == lead
        }
        return true
    }

    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        let target = preferredIndex ?? (entersOnLead && focusedIndex == nil ? lead : nil)
        guard let index = target, index >= 0, index < count else { return nil }
        return IndexPath(item: index, section: 0)
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                        with coordinator: UIFocusAnimationCoordinator) {
        let previous = context.previouslyFocusedIndexPath?.item
        // (The row slides: the titles' details arriving wait for it to rest — no redraw mid-slide.)
        OrbitMetaStore.shared.holdPublishing(for: 0.5)
        let next = context.nextFocusedIndexPath?.item
        focusedIndex = next
        if let previous, let next, previous < next {
            shrinkingOnTop = previous
            collectionView.cellForItem(at: IndexPath(item: previous, section: 0))?.layer.zPosition = 2
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.shrinkingOnTop == previous else { return }
                self.shrinkingOnTop = nil
                if self.focusedIndex != previous {
                    self.collectionView.cellForItem(at: IndexPath(item: previous, section: 0))?.layer.zPosition = 0
                }
            }
        } else if next != nil, shrinkingOnTop != nil {
            let old = shrinkingOnTop
            shrinkingOnTop = nil
            if let old, old != next { collectionView.cellForItem(at: IndexPath(item: old, section: 0))?.layer.zPosition = 0 }
        }
        entryGuide.isEnabled = entersOnLead && next == nil
        if previous != nil, next != nil { movedWithinAt = ProcessInfo.processInfo.systemUptime }
        // A tile wider when focused: the row makes room on the focus's own move.
        let grows = [previous, next].compactMap { $0 }.contains { measure($0, focused: true).width != measure($0, focused: false).width }
        if grows {
            coordinator.addCoordinatedAnimations {
                collectionView.collectionViewLayout.invalidateLayout()
                collectionView.layoutIfNeeded()
            }
        }
        guard let next else {
            onFocus(nil)
            return
        }
        if onlyIndex != nil, onlyIndex != next { onlyIndex = nil }
        // A pinned row entered from outside lands on its lead (at the margin).
        // (Not when the page itself asked for a title: the way back, its own requests.)
        if entersOnLead, preferredIndex == nil, previous == nil, next != lead, lead >= 0, lead < count {
            preferredIndex = lead
            // Steven (2026-10-29: the first Down from the hero sent the focus back up to the bar): the
            // lead far off screen (a looping row never placed yet) could not take it — the row is put
            // on its lead first, its cell there to take the focus.
            if pinned { place(lead, animated: false) }
            DispatchQueue.main.async { [weak self] in
                self?.requestFocus()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.preferredIndex = nil }
            }
            return
        }
        lastFocusedIndex = next
        if pinned, openDelta != nil {
            // The room goes with the focus, in the same move as the row's slide (one layout, one aim).
            roomLead = next
            // (The titles leaving slide out with the row: their pictures kept until it rests.)
            collectionView.collectionViewLayout.invalidateLayout()
            let aim = collectionView.layoutAttributesForItem(at: IndexPath(item: next, section: 0)).map { max(0, $0.frame.minX - margin) }
            let generation = aim.map { leaving.keep(collectionView, goingTo: $0) }
            UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
                self.collectionView.collectionViewLayout.invalidateLayout()
                self.collectionView.layoutIfNeeded()
                self.offsetToMargin(next)
            } completion: { [weak self] _ in
                if let generation { self?.leaving.done(generation) }
            }
            focusAtMargin = true
            onFocus(next)
            return
        }
        if pinned {
            focusAtMargin = true
        } else if let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: next, section: 0))?.frame {
            let rest = revealOffset(for: next) ?? (aimedOffset ?? collectionView.contentOffset.x)
            focusAtMargin = frame.minX - rest <= margin + 2
        }
        onFocus(next)
        if pinned {
            place(next, animated: true)
        } else if previous != nil, let target = revealOffset(for: next) {
            // Steven (2026-10-30: Home's free rows smooth at last once they slid themselves — Apple
            // TV's rows still stuttering across): the system's slide fell to a third of its speed a
            // tenth of a second in; the row slides itself, frame by frame, on one curve.
            aimedOffset = target
            slide(to: target)
        }
    }

    /// A free row: where it slides to show `index` whole within the margins (nil: shown already).
    private var aimedOffset: CGFloat?

    private func revealOffset(for index: Int) -> CGFloat? {
        guard let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return nil }
        // (Its width once focused: a tile that grows takes its room in the same move.)
        let width = max(frame.width, measure(index, focused: !focusHidden).width)
        let bounds = collectionView.bounds.width
        let current = aimedOffset ?? collectionView.contentOffset.x
        var x = current
        if frame.minX + width > current + bounds - margin { x = frame.minX + width - (bounds - margin) }
        if frame.minX < current + margin { x = frame.minX - margin }
        x = min(max(0, x), max(0, collectionView.contentSize.width - bounds))
        return abs(x - current) < 0.5 ? nil : x
    }


    /// (Steven, 2026-10-30: frame by frame it stuttered again — one animation, as when it was smooth;
    /// the titles leaving are kept by the layout, which lays out a screen's width either side.)
    private let leaving = OrbitLeavingTiles()

    private func slide(to x: CGFloat) {
        let generation = leaving.keep(collectionView, goingTo: x)
        UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                       animations: { self.collectionView.contentOffset = CGPoint(x: x, y: 0) },
                       completion: { [weak self] _ in
                           self?.leaving.done(generation)
                           if self?.aimedOffset == x { self?.aimedOffset = nil }
                       })
    }

    /// The system's own scroll to the focus: a pinned row aims at its title at the margin.
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        // Steven (2026-10-30, Plateformes and Studios: "pas naturel", the first or last tile not staying
        // at its end but going towards the middle, presses that seemed to skip): with nothing to reveal
        // (the focused tile already whole on screen), the system went on with its own aim — the focused
        // tile towards the middle. A free row now never moves further than needed to show it whole.
        if !pinned {
            if let aimedOffset {
                targetContentOffset.pointee.x = aimedOffset
            } else if let index = focusedIndex {
                targetContentOffset.pointee.x = revealOffset(for: index) ?? scrollView.contentOffset.x
            }
            return
        }
        guard pinned, let index = focusedIndex,
              let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return }
        targetContentOffset.pointee.x = max(0, frame.minX - margin)
    }

    // MARK: Select, hold

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect(indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let path = indexPaths.first, let menu = menu?(path.item) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }
    }
}
