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
    /// Each tile's width when the page knows it (a tile wider when open, from the page's own state:
    /// Netflix's lead). Else the tiles are measured.
    var width: ((Int) -> CGFloat)? = nil
    let ref: OrbitStripRef
    let tile: (Int, Bool) -> AnyView
    var onFocus: (Int?) -> Void = { _ in }
    var onSelect: (Int) -> Void = { _ in }
    var menu: ((Int) -> UIMenu?)? = nil

    @Environment(\.orbitFocusHidden) private var focusHidden
    @Environment(\.isEnabled) private var enabled

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
        c.widthOf = width
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
        self.focusHidden = focusHidden
        self.enabled = enabled
        let newWidths: [CGFloat] = widthOf.map { w in (0..<count).map { w($0) } } ?? []
        if count != self.count || identity != self.identity {
            self.count = count
            self.identity = identity
            closedSizes = [:]
            focusedSizes = [:]
            widths = newWidths
            collectionView.reloadData()
        } else {
            if relayout { closedSizes = [:]; focusedSizes = [:]; collectionView.collectionViewLayout.invalidateLayout() }
            if newWidths != widths {
                widths = newWidths
                // Moving inside the row: the room changes on the row's own curve; arriving, at once.
                if focusedIndex != nil {
                    UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
                        self.collectionView.collectionViewLayout.invalidateLayout()
                        self.collectionView.layoutIfNeeded()
                        if self.pinned, let f = self.focusedIndex { self.offsetToMargin(f) }
                    }
                } else {
                    UIView.performWithoutAnimation {
                        self.collectionView.collectionViewLayout.invalidateLayout()
                        self.collectionView.layoutIfNeeded()
                    }
                }
            }
            redrawVisible()
        }
    }

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
        measure(indexPath.item, focused: indexPath.item == focusedIndex && !focusHidden)
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

    /// The offset that puts `index` at the margin (set at once, inside an animation block).
    private func offsetToMargin(_ index: Int) {
        guard let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return }
        collectionView.contentOffset = CGPoint(x: max(0, frame.minX - margin), y: 0)
    }

    /// A pinned row: `index` at the margin.
    func place(_ index: Int, animated: Bool) {
        guard index >= 0, index < count else { return }
        collectionView.layoutIfNeeded()
        guard let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return }
        let x = max(0, frame.minX - margin)
        if animated {
            UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
                self.collectionView.contentOffset = CGPoint(x: x, y: 0)
            }
        } else {
            collectionView.contentOffset = CGPoint(x: x, y: 0)
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
            cell.layer.zPosition = state.isFocused ? 1 : 0
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
        return true
    }

    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        guard let index = preferredIndex, index >= 0, index < count else { return nil }
        return IndexPath(item: index, section: 0)
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                        with coordinator: UIFocusAnimationCoordinator) {
        let previous = context.previouslyFocusedIndexPath?.item
        let next = context.nextFocusedIndexPath?.item
        focusedIndex = next
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
        if pinned, previous == nil, next != lead, lead >= 0, lead < count {
            preferredIndex = lead
            DispatchQueue.main.async { [weak self] in
                self?.requestFocus()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.preferredIndex = nil }
            }
            return
        }
        lastFocusedIndex = next
        onFocus(next)
        if pinned { place(next, animated: true) }
    }

    /// The system's own scroll to the focus: a pinned row aims at its title at the margin.
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
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
