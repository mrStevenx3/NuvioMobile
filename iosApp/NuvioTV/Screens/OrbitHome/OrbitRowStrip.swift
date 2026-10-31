import SwiftUI
import UIKit

// Steven (2026-10-29: "fais exactement comme l'application Apple TV"): his slow-motion videos of
// Apple's TV app showed its rows starting at full speed on the press and slowing evenly to rest;
// Orbit's SwiftUI rows took three or four frames to get going. Apple's rows are UIKit collection
// views scrolled by the focus engine — Home's poster rows are now the same (as Discover, Search
// and the sources already are). The tiles are still Orbit's SwiftUI tiles, one per cell.

/// The row's controller, for the page (the way back, the page's own focus requests).
@MainActor
final class OrbitRowStripRef {
    weak var controller: OrbitRowStripController?
}

struct OrbitRowStrip: UIViewControllerRepresentable {
    let rowID: String
    let cards: [OrbitCard]
    let style: OrbitRowStyle
    let loopStart: String?
    let trailers: OrbitNativeTrailerHost
    let ref: OrbitRowStripRef
    let onSelect: (OrbitCard) -> Void
    /// The focused title (nil: the focus left the row).
    let onFocus: (OrbitCard?) -> Void
    let menu: (OrbitCard) -> UIMenu?

    @Environment(\.orbitFocusHidden) private var focusHidden
    @Environment(\.isEnabled) private var enabled

    func makeUIViewController(context: Context) -> OrbitRowStripController {
        let controller = OrbitRowStripController()
        ref.controller = controller
        update(controller)
        return controller
    }

    func updateUIViewController(_ controller: OrbitRowStripController, context: Context) {
        ref.controller = controller
        update(controller)
    }

    private func update(_ controller: OrbitRowStripController) {
        controller.onSelect = onSelect
        controller.onFocus = onFocus
        controller.menu = menu
        controller.trailers = trailers
        controller.show(rowID: rowID, cards: cards, style: style, loopStart: loopStart,
                        focusHidden: focusHidden, enabled: enabled)
    }
}

/// One cell's tile: Orbit's own, drawn focused as its cell is (and the Top 10's frame when open).
private struct OrbitRowStripTile: View {
    let card: OrbitCard
    let style: OrbitRowStyle
    let rank: Int
    let trailers: OrbitNativeTrailerHost
    let trailerKey: String
    let focused: Bool
    let open: Bool
    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        OrbitNativeTile(card: card, meta: metaStore.meta(for: card.preview), style: style, rank: rank,
                        trailers: trailers, trailerKey: trailerKey,
                        focusedFromCell: focused, openFromCell: open)
            // (Opening on the row's own curve, closing on its quicker one — the titles after it slide on
            // the same curves.)
            .animation(.easeInOut(duration: open ? 0.4 : 0.28), value: open)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            // Steven (2026-10-29, device: the Top 10's frame showed another film, and jumped open): a
            // reused cell kept the state of the title it showed before (its "stable" art held until
            // the new one came). Each title its own view.
            .id(card.id)
    }
}

/// A cell holding a SwiftUI tile, out of the TV's safe area (as Discover's).
final class OrbitRowStripCell: UICollectionViewCell {
    private var host: UIHostingController<AnyView>?

    func show(_ view: AnyView) {
        if let host {
            host.rootView = view
            return
        }
        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.frame = contentView.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.insetsLayoutMarginsFromSafeArea = false
        host.view.clipsToBounds = false
        contentView.addSubview(host.view)
        self.host = host
    }

    /// The cell put at once at its new size (its tile widens or narrows on its own, from its left).
    func settleFrame() {
        for layer in [layer, contentView.layer, host?.view.layer].compactMap({ $0 }) {
            layer.removeAllAnimations()
        }
    }
}

@MainActor
final class OrbitRowStripController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onSelect: (OrbitCard) -> Void = { _ in }
    var onFocus: (OrbitCard?) -> Void = { _ in }
    var menu: (OrbitCard) -> UIMenu? = { _ in nil }
    var trailers: OrbitNativeTrailerHost?

    private var collectionView: UICollectionView!
    private var rowID = ""
    private var cards: [OrbitCard] = []
    private var style: OrbitRowStyle = .posters
    private var loopStart: String?
    private var placedLoop = false
    private var focusHidden = false
    private var enabled = true

    /// The focused title's place (nil: the focus is elsewhere).
    private(set) var focusedIndex: Int?
    private var lastFocusedIndex: Int?
    /// The Top 10's title widened into its 16:9 frame.
    private var openIndex: Int?
    private var dwell: DispatchWorkItem?
    /// The way back from a title: only its card can take the focus a moment.
    private var onlyIndex: Int?
    private var onlyUntil: TimeInterval = 0
    /// Where the focus goes when the row is asked for it.
    private var preferredIndex: Int?

    static let dwellTime: TimeInterval = 1.5

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
        // Coming into the row from above or below lands on the title under the focus (Steven:
        // "le défilement naturel de l'Apple TV"), not on the one last left.
        collectionView.remembersLastFocusedIndexPath = false
        collectionView.register(OrbitRowStripCell.self, forCellWithReuseIdentifier: "tile")
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        applyLayout()
        // A press ends the way back's lock as it begins (the input clock hears it before the focus
        // engine moves), so the move finds every card.
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

    private func applyLayout() {
        guard let layout = collectionView?.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let gap = OrbitTileLayout.gap(style)
        layout.minimumLineSpacing = gap
        layout.minimumInteritemSpacing = gap
        layout.sectionInset = UIEdgeInsets(top: 0, left: OrbitHomeLayout.margin, bottom: 0, right: OrbitHomeLayout.margin)
    }

    func show(rowID: String, cards new: [OrbitCard], style: OrbitRowStyle, loopStart: String?,
              focusHidden: Bool, enabled: Bool) {
        loadViewIfNeeded()
        self.rowID = rowID
        self.loopStart = loopStart
        if style != self.style {
            self.style = style
            applyLayout()
            collectionView.collectionViewLayout.invalidateLayout()
        }
        var redraw = false
        if new.map(\.id) != cards.map(\.id) {
            let removed = Set(cards.map(\.id)).subtracting(new.map(\.id))
            cards = new
            openIndex = nil
            // Steven (2026-10-29: a title taken out of Continue Watching left an empty, see-through
            // place beside it): the row rebuilt whole and put back on its start, a card focused there.
            if !removed.isEmpty {
                placedLoop = false
                UIView.performWithoutAnimation {
                    collectionView.reloadData()
                    collectionView.layoutIfNeeded()
                }
                placeLoopIfNeeded()
                if focusedIndex != nil {
                    DispatchQueue.main.async { [weak self] in self?.takeFocusOnStart() }
                }
                return
            }
            collectionView.reloadData()
            placeLoopIfNeeded()
        } else if new != cards {
            cards = new
            redraw = true
        }
        if focusHidden != self.focusHidden || enabled != self.enabled {
            self.focusHidden = focusHidden
            self.enabled = enabled
            redraw = true
        }
        if redraw { redrawVisible() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        placeLoopIfNeeded()
    }

    /// A looping row starts on its middle copy (once).
    private func placeLoopIfNeeded() {
        guard !placedLoop, let loopStart, collectionView.bounds.width > 0,
              let index = cards.firstIndex(where: { $0.id == loopStart }) else { return }
        collectionView.layoutIfNeeded()
        guard let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return }
        placedLoop = true
        collectionView.setContentOffset(CGPoint(x: frame.minX - OrbitHomeLayout.margin, y: 0), animated: false)
    }

    private func redrawVisible() {
        for path in collectionView.indexPathsForVisibleItems {
            collectionView.cellForItem(at: path)?.setNeedsUpdateConfiguration()
        }
    }

    // MARK: The page's requests

    /// The page sends the focus here (Up / Down it could not reach, a way back cut short).
    func takeFocus() {
        preferredIndex = lastFocusedIndex ?? cards.indices.first
        requestFocus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.preferredIndex = nil }
    }

    /// After a title left the row: the focus on its start (the card at the margin).
    private func takeFocusOnStart() {
        let start = loopStart.flatMap { id in cards.firstIndex { $0.id == id } } ?? cards.indices.first
        preferredIndex = start
        requestFocus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.preferredIndex = nil }
    }

    /// Back from a title opened here: its card takes the focus back (asked a few times — the
    /// system's own landing comes late), the others locked a moment.
    func restore(cardID: String) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        let start = ProcessInfo.processInfo.systemUptime
        preferredIndex = index
        onlyIndex = index
        onlyUntil = start + 1.2
        lastFocusedIndex = index
        // (Steven, 2026-10-31: the system's landing can come as late as 2 s — asked until then.)
        for delay in [0.0, 0.15, 0.35, 0.6, 0.9, 1.3, 1.8, 2.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !ViewerInputClock.shared.hasInput(since: start), self.focusedIndex != index else { return }
                self.requestFocus()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            if self.preferredIndex == index { self.preferredIndex = nil }
            if self.onlyIndex == index { self.onlyIndex = nil }
        }
    }

    private func requestFocus() {
        if let index = preferredIndex, cards.indices.contains(index),
           collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) != nil {
            collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: [], animated: false)
        }
        view.window?.windowScene?.focusSystem?.requestFocusUpdate(to: collectionView)
        collectionView.setNeedsFocusUpdate()
        collectionView.updateFocusIfNeeded()
    }

    // MARK: Data

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { cards.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "tile", for: indexPath)
        let index = indexPath.item
        cell.configurationUpdateHandler = { [weak self] cell, state in
            self?.configure(cell, index: index, focused: state.isFocused)
        }
        cell.setNeedsUpdateConfiguration()
        return cell
    }

    private func configure(_ cell: UICollectionViewCell, index: Int, focused: Bool) {
        guard let cell = cell as? OrbitRowStripCell, cards.indices.contains(index), let trailers else { return }
        let card = cards[index]
        cell.layer.zPosition = focused ? 1 : 0
        cell.show(AnyView(OrbitRowStripTile(card: card, style: style, rank: index + 1, trailers: trailers,
                                            trailerKey: "\(rowID)|\(card.id)",
                                            focused: focused && !focusHidden,
                                            open: openIndex == index && focused)))
    }

    // MARK: Layout

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let size = OrbitTileLayout.size(style)
        guard style == .ranked else { return size }
        let rank = indexPath.item + 1
        if openIndex == indexPath.item {
            return CGSize(width: OrbitRankedTile.rankRoom(rank) + OrbitNativeRankedOpenTile.frame(scale: 1).width,
                          height: size.height)
        }
        return CGSize(width: OrbitRankedTile.closedWidth(rank), height: size.height)
    }

    // MARK: Focus

    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        guard enabled else { return false }
        if let only = onlyIndex, ProcessInfo.processInfo.systemUptime < onlyUntil { return indexPath.item == only }
        return true
    }

    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        guard let index = preferredIndex, cards.indices.contains(index) else { return nil }
        return IndexPath(item: index, section: 0)
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                        with coordinator: UIFocusAnimationCoordinator) {
        let next = context.nextFocusedIndexPath?.item
        focusedIndex = next
        // (The row slides: the titles' details arriving wait for it to rest — no redraw mid-slide.)
        OrbitMetaStore.shared.holdPublishing(for: 0.5)
        dwell?.cancel()
        if let open = openIndex, open != next { setOpen(nil) }
        guard let next, cards.indices.contains(next) else {
            onFocus(nil)
            return
        }
        lastFocusedIndex = next
        // A press of his ends the way back's lock.
        if onlyIndex != nil, onlyIndex != next { onlyIndex = nil }
        // Steven (2026-10-30, slow-motion video: a stutter at each step of "Nouveau sur vos
        // plateformes"): the system's own slide sped up, then fell back to a third of its speed a
        // tenth of a second in and crept to the end — every press. The row now slides itself, in one
        // curve (as the rows held at their margin, smooth on his TV), the system aimed at the same place.
        if context.previouslyFocusedIndexPath != nil, let target = revealOffset(for: next) {
            aimedOffset = target
            slide(to: target)
        } else {
            aimedOffset = nil
        }
        onFocus(cards[next])
        // The Top 10: rested on, the poster widens into its frame (its trailer in it).
        if style == .ranked {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.focusedIndex == next, self.cards.indices.contains(next) else { return }
                let card = self.cards[next]
                self.trailers?.arm("\(self.rowID)|\(card.id)", item: card.preview)
                self.setOpen(next)
            }
            dwell = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwellTime, execute: work)
        }
    }

    /// Where the row slides to show `index` whole within the margins (nil: already shown).
    private var aimedOffset: CGFloat?

    private func revealOffset(for index: Int) -> CGFloat? {
        guard let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return nil }
        let margin = OrbitHomeLayout.margin
        let width = collectionView.bounds.width
        let current = aimedOffset ?? collectionView.contentOffset.x
        var x = current
        if frame.maxX > current + width - margin { x = frame.maxX - (width - margin) }
        if frame.minX < current + margin { x = frame.minX - margin }
        let maxX = max(0, collectionView.contentSize.width - width)
        x = min(max(0, x), maxX)
        return abs(x - current) < 0.5 ? nil : x
    }

    /// Steven (2026-10-30: "les affiches à gauche et à droite disparaissent d'un coup sec"): slid as
    /// one animation, the row jumped to its end at once for the collection view — the titles leaving
    /// were taken away at the start. It now moves frame by frame on the same curve (0.4 s, easing
    /// out): each title leaves as it crosses the screen's edge.

    /// (Steven, 2026-10-30: frame by frame it stuttered again — one animation, as when it was smooth;
    /// the titles leaving are kept by the layout, which lays out a screen's width either side.)
    private let leaving = OrbitLeavingTiles()

    private func slide(to x: CGFloat) {
        let generation = leaving.keep(collectionView, goingTo: x)
        UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
            self.collectionView.contentOffset = CGPoint(x: x, y: 0)
        } completion: { [weak self] _ in
            self?.leaving.done(generation)
            if self?.aimedOffset == x { self?.aimedOffset = nil }
        }
    }

    /// The system's own scroll to the focus aims where the row slides itself (no second aim).
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        if let aimedOffset { targetContentOffset.pointee.x = aimedOffset }
    }

    /// The Top 10's frame open on `index` (nil: closed), the titles after it making room.
    private func setOpen(_ index: Int?) {
        let old = openIndex
        openIndex = index
        let changed = [old, index].compactMap({ $0 }).map({ IndexPath(item: $0, section: 0) })
        // The tile told first, out of the row's animation: it widens (or narrows) on its own curve.
        for path in changed {
            guard let cell = collectionView.cellForItem(at: path) else { continue }
            configure(cell, index: path.item, focused: cell.isFocused)
        }
        UIView.animate(withDuration: index == nil ? 0.28 : 0.4, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
        } completion: { _ in
            // The open frame wholly on the screen.
            guard let index, self.openIndex == index,
                  let frame = self.collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return }
            let right = frame.maxX - self.collectionView.contentOffset.x
            let limit = self.collectionView.bounds.width - OrbitHomeLayout.margin
            if right > limit {
                var offset = self.collectionView.contentOffset
                offset.x += right - limit
                self.collectionView.setContentOffset(offset, animated: true)
            }
        }
        // Steven (2026-10-29, video: the poster jumped right, then the frame came back left): the
        // opening cell is not stretched by the row's animation (its tile was drawn at its new size
        // and slid back) — it takes its new room at once, its tile widening from its left edge on
        // its own; only the titles after it slide.
        for path in changed {
            (collectionView.cellForItem(at: path) as? OrbitRowStripCell)?.settleFrame()
        }
    }

    // MARK: Select, hold

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard cards.indices.contains(indexPath.item) else { return }
        onSelect(cards[indexPath.item])
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let path = indexPaths.first, cards.indices.contains(path.item), let menu = menu(cards[path.item]) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }
    }
}
