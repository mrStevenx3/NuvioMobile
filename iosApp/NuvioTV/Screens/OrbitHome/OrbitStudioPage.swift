import Combine
import SharedCore
import SwiftUI

// Orbit Studio (Steven, 2026-10-24): a studio's page, rebuilt from scratch — a showcase of its
// films, with a rhythm (Steven: "des trucs en avant en grand, d'autres moins en avant en petit"):
//
//  - A wide banner first: the studio's featured films one at a time (Left / Right), their trailer
//    in large behind the logo, the meta line and the synopsis; the studio's logo and figures in
//    the banner's corner.
//  - "Les incontournables" in large landscape cards (the trailer plays in the focused one).
//  - "Les sagas" in medium landscape cards (the saga's name; it opens its first film).
//  - Every other row in small portrait posters, seven to eight a screen: the folder's Nouveautés
//    and Top 10 (Steven's transparent Top 10 images drawn as they are), "Les plus populaires",
//    "Prochainement", a row per decade. The focused film's meta line and synopsis under the row.
//  - Orbit's canvas: one focusable stop, the page moves (Down / Up section to section,
//    Left / Right along one).
//
// One page for both ways in: a studio of the Studios tab (its folder) and a studio or a channel
// from a film's "À propos" (TMDB's company / network id). The data is TMDB's (discover by company
// or network), plus the folder's catalogs.

/// What the page shows: a folder of the Studios tab, or TMDB's company / network.
struct OrbitStudioRoute: Hashable {
    let name: String
    /// TMDB ids ("3", "128064|9993"), nil to look them up by name.
    let companies: String?
    let isNetwork: Bool
    let logo: String?
    let collectionId: String?
    let folderId: String?

    static func folder(collectionId: String, folder: CollectionFolder) -> OrbitStudioRoute {
        let logo: String? = folder.titleLogoUrl
        return OrbitStudioRoute(name: folder.title,
                                companies: OrbitStudioFilmsModel.companies(forTitle: folder.title),
                                isNetwork: false,
                                logo: (logo ?? "").trimmingCharacters(in: .whitespaces).isEmpty ? nil : logo,
                                collectionId: collectionId, folderId: folder.id)
    }

    static func entity(_ route: EntityRoute) -> OrbitStudioRoute {
        OrbitStudioRoute(name: route.name, companies: String(route.id), isNetwork: route.isNetwork,
                         logo: nil, collectionId: nil, folderId: nil)
    }
}

/// How a row is drawn.
enum OrbitStudioRowKind: Equatable {
    /// Large landscape cards, the trailer in the focused one.
    case featured
    /// Medium landscape cards with the saga's name.
    case sagas
    /// Small portrait posters (transparent ones drawn as they are).
    case posters(transparent: Bool)
}

/// One row of the studio page.
struct OrbitStudioRow: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [MetaPreview]
    var kind: OrbitStudioRowKind = .posters(transparent: false)

    static func == (a: OrbitStudioRow, b: OrbitStudioRow) -> Bool {
        a.id == b.id && a.title == b.title && a.kind == b.kind && a.items.map(\.id) == b.items.map(\.id)
    }

    var cardSize: CGSize {
        switch kind {
        case .featured: return CGSize(width: 448, height: 252)
        case .sagas: return CGSize(width: 380, height: 214)
        case .posters: return CGSize(width: 196, height: 294)
        }
    }

    var gap: CGFloat {
        if case .posters = kind { return 22 }
        return 26
    }

    /// The focused film's info shows under the row (not for the sagas: their name is the card).
    var showsInfo: Bool { kind != .sagas }

    /// From this row's heading to the next one's.
    var pitch: CGFloat {
        OrbitStudioLayout.cardsTop + cardSize.height + (showsInfo ? 230 : 80)
    }
}

enum OrbitStudioLayout {
    static let margin: CGFloat = OrbitHomeLayout.margin
    static let radius: CGFloat = 14
    /// The banner.
    static let heroHeight: CGFloat = 700
    /// The first row's heading under the banner, and the current row's line once it has left.
    static let rowLine: CGFloat = 150
    static let cardsTop: CGFloat = 44
    static let horizontal = Animation.easeOut(duration: 0.24)
    static let vertical = Animation.easeInOut(duration: 0.36)
}

struct OrbitStudioPage: View {
    let route: OrbitStudioRoute

    @StateObject private var model: OrbitStudioModel
    @StateObject private var trailer = InlineTrailerCardModel()
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true

    /// 0: the banner; 1…: the rows.
    @State private var current = 0
    @State private var heroIndex = 0
    @State private var leads: [String: Int] = [:]
    @FocusState private var canvasFocused: Bool
    @State private var motion = OrbitHomeMotion()
    @State private var trailerKey: String?
    @State private var opening: TitleRoute?
    @State private var tint: Color?
    /// The opening is over: the page's own studio logo shows (the opening's lands on it).
    @State private var introDone = false

    init(route: OrbitStudioRoute) {
        self.route = route
        _model = StateObject(wrappedValue: OrbitStudioModel(route: route))
    }

    // MARK: Data

    private var rows: [OrbitStudioRow] { model.rows }
    private var heroItems: [MetaPreview] { model.heroItems }
    /// Sections: the banner (when it has films), then the rows.
    private var hasHero: Bool { !heroItems.isEmpty }
    private var sectionCount: Int { (hasHero ? 1 : 0) + rows.count }

    /// The row of section `s` (nil for the banner).
    private func row(at section: Int) -> OrbitStudioRow? {
        let i = section - (hasHero ? 1 : 0)
        return rows.indices.contains(i) ? rows[i] : nil
    }

    private func lead(of row: OrbitStudioRow) -> Int {
        min(leads[row.id] ?? 0, max(0, row.items.count - 1))
    }

    private var heroItem: MetaPreview? {
        heroItems.isEmpty ? nil : heroItems[heroIndex % heroItems.count]
    }

    private func focusedItem() -> MetaPreview? {
        let section = min(current, max(0, sectionCount - 1))
        if hasHero, section == 0 { return heroItem }
        guard let row = row(at: section), row.items.indices.contains(lead(of: row)) else { return nil }
        return row.items[lead(of: row)]
    }

    private var brand: Color {
        tint ?? OrbitPlatformBrand.color(title: model.name)
    }

    /// Each section's top in the page's column (banner at 0, each row's heading line after it).
    private func anchors() -> [CGFloat] {
        var out: [CGFloat] = []
        var y: CGFloat = 0
        if hasHero { out.append(0); y = OrbitStudioLayout.heroHeight }
        else { y = 360 }
        for row in rows { out.append(y); y += row.pitch }
        return out
    }

    // MARK: Body

    var body: some View {
        let L = OrbitStudioLayout.self
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        let count = sectionCount
        let index = min(current, max(0, count - 1))
        let anchors = anchors()
        let onHero = hasHero && index == 0
        // The banner stays at the top; a row brought up sits at the row line.
        let scroll: CGFloat = count == 0 || onHero || (!hasHero && index == 0) ? 0 : L.rowLine - anchors[index]

        ZStack(alignment: .topLeading) {
            OrbitStudioBackground(brand: brand)

            ZStack(alignment: .topLeading) {
                if hasHero {
                    OrbitStudioHero(item: heroItem, meta: heroItem.flatMap { metaStore.meta(for: $0) },
                                    studioName: model.name, studioLogo: model.logo ?? route.logo,
                                    showsStudioLogo: introDone,
                                    statsLine: model.statsLine, focused: onHero && canvasFocused,
                                    count: heroItems.count, index: heroIndex % max(1, heroItems.count),
                                    trailerURL: onHero ? trailerURL(for: heroItem) : nil,
                                    onTrailerFailure: { trailer.playbackFailed($0) },
                                    onTrailerEnded: { trailer.playbackFinished() })
                        .opacity(onHero ? 1 : 0)
                } else {
                    OrbitStudioHeader(name: model.name, logo: model.logo ?? route.logo, line: nil)
                        .offset(x: L.margin, y: 90)
                        .opacity(index == 0 ? 1 : 0)
                }
                if count > 0 {
                    let first = max(hasHero ? 1 : 0, index)
                    let last = min(count - 1, index + 2)
                    if first <= last {
                        ForEach(first...last, id: \.self) { s in
                            if let sectionRow = row(at: s) {
                                let row = sectionRow
                                OrbitStudioRowView(row: row, lead: lead(of: row), isCurrent: s == index,
                                                   focused: s == index && canvasFocused,
                                                   trailerURL: s == index && row.kind == .featured
                                                       ? trailerURL(for: row.items.indices.contains(lead(of: row)) ? row.items[lead(of: row)] : nil)
                                                       : nil,
                                                   onTrailerFailure: { trailer.playbackFailed($0) },
                                                   onTrailerEnded: { trailer.playbackFinished() })
                                    .offset(y: anchors[s])
                                    .id(row.id)
                                    .transition(.identity)
                            }
                        }
                    }
                }
            }
            .offset(y: scroll)

            if count == 0 {
                Group {
                    if model.loading {
                        ProgressView()
                    } else {
                        Text(String(localized: "Aucun film trouvé pour \(model.name)."))
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
                .frame(width: W, height: H)
            }

            // The page's one focusable stop.
            Button(action: select) {
                Color.clear
                    .frame(width: W, height: H)
                    .contentShape(Rectangle())
            }
            .buttonStyle(OrbitStudioCanvasStyle())
            .focused($canvasFocused)
            .onMoveCommand(perform: move)
            .onExitCommand(perform: exitAction(index: index))

            // The studio's opening, over everything from the first frame (the catalogue never
            // shows before it).
            if !introDone {
                OrbitStudioIntro(name: model.name, logoUrl: model.logo ?? route.logo,
                                 onDone: { introDone = true })
                    .zIndex(20)
            }
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .background(OrbitHomeLayout.background)
        .ignoresSafeArea()
        .defaultFocus($canvasFocused, true)
        .navigationDestination(item: $opening) { route in
            DetailView(preview: route.preview)
        }
        .onAppear {
            tabBarVisibility.pushImmersive()
            model.start()
            trailer.restSource = .custom(motion)
            DispatchQueue.main.async { canvasFocused = true }
            refreshAfterMove()
        }
        .onDisappear {
            tabBarVisibility.popImmersive()
            trailer.reset(abortStages: true)
        }
        .onChange(of: canvasFocused) { _, _ in refreshAfterMove() }
        .onChange(of: rows.map(\.id) + heroItems.map(\.id)) { _, _ in
            if current >= sectionCount { current = max(0, sectionCount - 1) }
            refreshAfterMove()
        }
        .onChange(of: model.logo ?? route.logo ?? "-", initial: true) { _, raw in sampleTint(raw) }
    }

    private func trailerURL(for item: MetaPreview?) -> String? {
        guard let item, trailerKey == "\(item.type):\(item.id)" else { return nil }
        return trailer.playingURL
    }

    /// The studio's colour from its logo when no brand colour is known.
    private func sampleTint(_ raw: String) {
        guard raw != "-", OrbitPlatformBrand.isNeutral(title: model.name) else { return }
        if let cached = ArtworkColorStore.shared.cachedColor(for: [raw], use: .wash) {
            tint = cached
            return
        }
        ArtworkColorStore.shared.color(for: [raw], use: .wash) { color in
            if let color { withAnimation(.easeInOut(duration: 0.5)) { tint = color } }
        }
    }

    // MARK: Input

    private func move(_ direction: MoveCommandDirection) {
        let count = sectionCount
        guard count > 0 else { return }
        let index = min(current, count - 1)
        switch direction {
        case .down:
            guard index + 1 < count else { return }
            withAnimation(reduceMotion ? nil : OrbitStudioLayout.vertical) { current = index + 1 }
        case .up:
            guard index > 0 else { return }
            withAnimation(reduceMotion ? nil : OrbitStudioLayout.vertical) { current = index - 1 }
        case .left, .right:
            let delta = direction == .right ? 1 : -1
            if hasHero, index == 0 {
                let n = heroItems.count
                guard n > 1 else { return }
                withAnimation(OrbitStudioLayout.horizontal) { heroIndex = (heroIndex + delta + n) % n }
            } else if let sectionRow = row(at: index) {
                let row = sectionRow
                let next = lead(of: row) + delta
                guard row.items.indices.contains(next) else { return }
                withAnimation(OrbitStudioLayout.horizontal) { leads[row.id] = next }
            }
        @unknown default:
            return
        }
        refreshAfterMove()
    }

    private func select() {
        guard let item = focusedItem() else { return }
        // A saga opens its first film, as that film (its own name and art, not the saga's).
        opening = TitleRoute(preview: model.sagaFilms[item.id] ?? item)
    }

    /// Menu: back to the top from below it; at the top, the page closes.
    private func exitAction(index: Int) -> (() -> Void)? {
        guard index > 0 else { return nil }
        return {
            withAnimation(reduceMotion ? nil : OrbitStudioLayout.vertical) { current = 0 }
            refreshAfterMove()
        }
    }

    /// After any move: the look-ahead (meta, art) and the trailer (the banner's or the featured
    /// row's focused film; the poster rows have none).
    private func refreshAfterMove() {
        let count = sectionCount
        let index = min(current, max(0, count - 1))
        motion.stamp()
        var metaItems: [MetaPreview] = []
        if !heroItems.isEmpty {
            metaItems.append(contentsOf: (0..<min(3, heroItems.count)).map { heroItems[(heroIndex + $0) % heroItems.count] })
        }
        for s in index...max(index, min(count - 1, index + 1)) {
            guard let sectionRow = row(at: s) else { continue }
            let at = lead(of: sectionRow)
            metaItems.append(contentsOf: sectionRow.items.indices.filter { $0 >= at - 1 && $0 <= at + 5 }.map { sectionRow.items[$0] })
        }
        OrbitMetaStore.shared.request(metaItems)

        trailer.reset()
        trailerKey = nil
        guard trailersOn, canvasFocused, UIAccessibility.isVideoAutoplayEnabled, let item = focusedItem() else { return }
        let playsHere = (hasHero && index == 0) || row(at: index)?.kind == .featured
        guard playsHere else { return }
        trailer.prefersReducedMotion = reduceMotion
        trailer.restSource = .custom(motion)
        trailerKey = "\(item.type):\(item.id)"
        trailer.focusChanged(true, item: item)
    }
}

private struct OrbitStudioCanvasStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - Opening

/// The studio's opening (Steven, 2026-10-24, "le générique de studio"): black, the studio's logo
/// fades in large in the middle, a light sweeps across it, then it glides to its place top right
/// while the page fades in. Once per visit (back from a film, nothing replays); any press skips
/// it; with Reduce Motion, nothing plays.
struct OrbitStudioIntro: View {
    let name: String
    let logoUrl: String?
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .black
    @State private var veil: Double = 1
    @State private var sweep: CGFloat = -1
    @State private var work: [DispatchWorkItem] = []

    private enum Phase { case black, splash, corner }

    /// The page's studio logo: its box and place (top right of the banner).
    static let cornerBox = CGSize(width: 300, height: 100)
    static let cornerTop: CGFloat = 56
    static let splashScale: CGFloat = 2.4

    var body: some View {
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        let box = Self.cornerBox
        let corner = CGPoint(x: W - OrbitHomeLayout.margin - box.width / 2, y: Self.cornerTop + box.height / 2)
        let centre = phase == .corner ? corner : CGPoint(x: W / 2, y: H / 2)
        ZStack(alignment: .topLeading) {
            Color.black
                .frame(width: W, height: H)
                .opacity(veil)

            logo
                // Centred in the middle; in the corner, right-aligned as the page's own logo.
                .frame(width: box.width, height: box.height, alignment: phase == .corner ? .topTrailing : .center)
                .overlay {
                    // The light sweeping across the logo, masked by it.
                    LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 90, height: box.height * 1.6)
                        .rotationEffect(.degrees(18))
                        .offset(x: sweep * (box.width / 2 + 90))
                        .blendMode(.plusLighter)
                        .mask(logo.frame(width: box.width, height: box.height))
                        .opacity(phase == .splash ? 1 : 0)
                }
                .scaleEffect(phase == .corner ? 1 : (phase == .black ? Self.splashScale * 0.92 : Self.splashScale))
                .opacity(phase == .black ? 0 : 1)
                .position(centre)
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear(perform: play)
        .onReceive(NotificationCenter.default.publisher(for: ViewerInputClock.didRecord)) { _ in
            // A press skips the opening.
            guard phase != .corner || veil > 0 else { return }
            work.forEach { $0.cancel() }
            withAnimation(.easeOut(duration: 0.3)) { phase = .corner; veil = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { onDone() }
        }
    }

    @ViewBuilder
    private var logo: some View {
        if let logoUrl, !logoUrl.isEmpty {
            OrbitBalancedLogo(url: logoUrl, area: 17_000, maxSize: Self.cornerBox,
                              whiten: OrbitBalancedLogo.isGrey(name), alignment: phase == .corner ? .topTrailing : .center)
        } else {
            Text(name)
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private func play() {
        guard phase == .black, veil == 1 else { return }
        if reduceMotion { onDone(); return }
        func at(_ delay: Double, _ body: @escaping () -> Void) {
            let item = DispatchWorkItem(block: body)
            work.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
        // 0 s: the logo fades in, large, in the middle.
        withAnimation(.easeOut(duration: 0.55)) { phase = .splash }
        // 0.6 s: the light sweeps across it.
        at(0.6) { withAnimation(.easeInOut(duration: 0.75)) { sweep = 1 } }
        // 1.5 s: it glides to its place, the page fades in under it.
        at(1.5) {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.9)) { phase = .corner }
            withAnimation(.easeInOut(duration: 0.8)) { veil = 0 }
        }
        // 2.4 s: the page's own logo takes over (same place, same size).
        at(2.4) { onDone() }
    }
}

// MARK: - Background, banner, header

/// A calm page: Orbit's black with the studio's colour rising from the top-left.
private struct OrbitStudioBackground: View {
    let brand: Color

    var body: some View {
        ZStack {
            OrbitHomeLayout.background
            RadialGradient(colors: [brand.opacity(0.42), brand.opacity(0.12), .clear],
                           center: UnitPoint(x: 0.12, y: 0.0), startRadius: 0, endRadius: 1400)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.5), value: brand)
    }
}

/// The banner: a featured film across the screen's width — its backdrop, then its trailer after
/// a rest; the studio's logo and figures in the corner; the film's logo, meta line and synopsis;
/// the dots of the featured films.
private struct OrbitStudioHero: View {
    let item: MetaPreview?
    let meta: OrbitMeta?
    let studioName: String
    let studioLogo: String?
    var showsStudioLogo = true
    let statsLine: String?
    let focused: Bool
    let count: Int
    let index: Int
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let L = OrbitStudioLayout.self
        let size = CGSize(width: OrbitHomeLayout.screenWidth, height: L.heroHeight)
        let banner: String? = item?.banner
        ZStack(alignment: .topLeading) {
            OrbitSwapImage(url: banner ?? meta?.backdrop, fallback: nil, size: size)
            if let trailerURL, let item {
                TrailerHeroPlayer(urlString: trailerURL,
                                  onFailure: onTrailerFailure,
                                  zoomKey: TrailerResolutionCache.key(type: item.type, id: item.id),
                                  loops: false,
                                  onPlaybackEnded: onTrailerEnded,
                                  cornerRadius: 0)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity.animation(.easeOut(duration: 0.6)))
            }
            LinearGradient(stops: [
                .init(color: .black.opacity(0.85), location: 0),
                .init(color: .black.opacity(0.4), location: 0.45),
                .init(color: .clear, location: 0.72),
            ], startPoint: .leading, endPoint: .trailing)
            // Melts into the page below.
            LinearGradient(stops: [
                .init(color: .clear, location: 0.55),
                .init(color: OrbitHomeLayout.background, location: 1),
            ], startPoint: .top, endPoint: .bottom)

            // The studio's logo, top right (Steven: no figures; the film's name has the left).
            Group {
                if let studioLogo, !studioLogo.isEmpty {
                    OrbitBalancedLogo(url: studioLogo, area: 17_000, maxSize: CGSize(width: 300, height: 100),
                                      whiten: OrbitBalancedLogo.isGrey(studioName), alignment: .topTrailing)
                } else {
                    studioText
                        .frame(width: 300, height: 100, alignment: .topTrailing)
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 12, y: 3)
            .opacity(showsStudioLogo ? 1 : 0)
            .offset(x: size.width - L.margin - 300, y: OrbitStudioIntro.cornerTop)

            if let item {
                let info = OrbitInfo.make(item, meta: meta)
                VStack(alignment: .leading, spacing: 0) {
                    OrbitTitleMark(name: item.name, logo: info.logo, maxSize: CGSize(width: 600, height: 180), textSize: 62)
                        .frame(width: 600, height: 180, alignment: .bottomLeading)
                    OrbitMetaLine(info: info, size: 27)
                        .frame(height: 36)
                        .padding(.top, 24)
                    Text(info.synopsis)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineSpacing(4)
                        .lineLimit(3)
                        .frame(width: 880, alignment: .leading)
                        .padding(.top, 18)
                    HStack(spacing: 18) {
                        Text("Voir la fiche")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(focused ? Color.black : Color.white)
                            .padding(.horizontal, 40)
                            .frame(height: 70)
                            .background(Capsule().fill(focused ? Color.white : Color.white.opacity(0.22)))
                        if count > 1 {
                            HStack(spacing: 10) {
                                ForEach(0..<count, id: \.self) { i in
                                    Capsule()
                                        .fill(Color.white.opacity(i == index ? 0.95 : 0.35))
                                        .frame(width: i == index ? 26 : 10, height: 10)
                                }
                            }
                        }
                    }
                    .padding(.top, 26)
                }
                .id("\(item.type):\(item.id)")
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                .offset(x: L.margin, y: 170)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }

    private var studioText: some View {
        Text(studioName)
            .font(.system(size: 40, weight: .heavy))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// The header when there is no banner (no featured film yet).
private struct OrbitStudioHeader: View {
    let name: String
    let logo: String?
    let line: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Group {
                if let logo, !logo.isEmpty {
                    CachedAsyncImage(string: logo, contentMode: .fit,
                                     decodeSize: .points(width: 520, height: 150),
                                     loading: { Color.clear }, failure: { nameText })
                } else {
                    nameText
                }
            }
            .frame(width: 520, height: 150, alignment: .bottomLeading)
            if let line, !line.isEmpty {
                Text(line)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
        .allowsHitTesting(false)
    }

    private var nameText: some View {
        Text(name)
            .font(.system(size: 72, weight: .heavy))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

// MARK: - Rows and cards

private struct OrbitStudioRowView: View {
    let row: OrbitStudioRow
    let lead: Int
    let isCurrent: Bool
    let focused: Bool
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        let L = OrbitStudioLayout.self
        let size = row.cardSize
        let window = max(0, lead - 1)...max(max(0, lead - 1), min(row.items.count - 1, lead + 9))
        ZStack(alignment: .topLeading) {
            Text(row.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.white.opacity(isCurrent ? 1 : 0.55))
                .lineLimit(1)
                .frame(height: 40)
                .offset(x: L.margin + 4, y: -20)

            ZStack(alignment: .topLeading) {
                if !row.items.isEmpty {
                    ForEach(Array(zip(window, row.items[window])), id: \.1.id) { index, item in
                        card(item, focused: focused && index == lead, trailer: index == lead ? trailerURL : nil, size: size)
                            .offset(x: L.margin + CGFloat(index - lead) * (size.width + row.gap))
                            .opacity(index < lead ? 0 : 1)
                            .transition(.identity)
                    }
                }
            }
            .offset(y: L.cardsTop)

            if isCurrent, row.showsInfo, row.items.indices.contains(lead) {
                let item = row.items[lead]
                let info = OrbitInfo.make(item, meta: metaStore.meta(for: item))
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    OrbitMetaLine(info: info, size: 25)
                        .frame(height: 32)
                    Text(info.synopsis)
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineSpacing(3)
                        .lineLimit(2)
                        .frame(width: 1100, alignment: .leading)
                }
                .id("\(item.type):\(item.id)")
                // Fades in; leaves at once (it hung over the next row while the page moved).
                .transition(.asymmetric(insertion: .opacity.animation(.easeInOut(duration: 0.2)), removal: .identity))
                .offset(x: L.margin + 4, y: L.cardsTop + size.height + (row.kind == .featured ? 30 : 46))
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func card(_ item: MetaPreview, focused: Bool, trailer: String?, size: CGSize) -> some View {
        switch row.kind {
        case .featured:
            OrbitStudioCard(item: item, meta: metaStore.meta(for: item), size: size, focused: focused,
                            trailerURL: trailer, onTrailerFailure: onTrailerFailure, onTrailerEnded: onTrailerEnded)
        case .sagas:
            OrbitStudioCard(item: item, meta: metaStore.meta(for: item), size: size, saga: true, focused: focused,
                            trailerURL: nil, onTrailerFailure: onTrailerFailure, onTrailerEnded: onTrailerEnded)
        case .posters(let transparent):
            OrbitStudioPoster(item: item, size: size, transparent: transparent, focused: focused)
        }
    }
}

/// A film (or a saga) in landscape: its art, its logo (a saga: its name) bottom-left; white frame
/// and a lift when focused; the trailer in place after a rest.
private struct OrbitStudioCard: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let size: CGSize
    var saga = false
    let focused: Bool
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let L = OrbitStudioLayout.self
        let banner: String? = item.banner
        let info = OrbitInfo.make(item, meta: meta)
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.1)
            OrbitImage(url: banner ?? meta?.backdrop, fallback: item.poster, size: size)
            if let trailerURL {
                TrailerHeroPlayer(urlString: trailerURL,
                                  onFailure: onTrailerFailure,
                                  zoomKey: TrailerResolutionCache.key(type: item.type, id: item.id),
                                  loops: false,
                                  onPlaybackEnded: onTrailerEnded,
                                  cornerRadius: L.radius)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity.animation(.easeOut(duration: 0.5)))
            }
            LinearGradient(colors: [.clear, .black.opacity(saga ? 0.75 : 0.6)], startPoint: .center, endPoint: .bottom)
            if saga {
                Text(item.name)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.6), radius: 6)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            } else {
                OrbitTitleMark(name: item.name, logo: info.logo, maxSize: CGSize(width: size.width * 0.6, height: 80), textSize: 30)
                    .padding(.leading, 20)
                    .padding(.bottom, 16)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        // The focus look animates on its own, never the card's place (the row moves it).
        .animation(.easeOut(duration: 0.18)) { view in
            view
                .overlay {
                    RoundedRectangle(cornerRadius: L.radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 4)
                }
                .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 18, y: 10)
                .scaleEffect(focused ? 1.05 : 1, anchor: .leading)
        }
    }
}

/// A small portrait poster; Steven's transparent Top 10 images drawn as they are.
private struct OrbitStudioPoster: View {
    let item: MetaPreview
    let size: CGSize
    let transparent: Bool
    let focused: Bool

    var body: some View {
        Group {
            if transparent {
                OrbitImage(url: item.poster, fallback: item.rawPosterUrl, mode: .fit, size: size)
                    .frame(width: size.width, height: size.height)
                    .animation(.easeOut(duration: 0.18)) { view in
                        view.shadow(color: .black.opacity(focused ? 0.6 : 0.3), radius: focused ? 20 : 8, y: 8)
                    }
            } else {
                OrbitImage(url: item.poster, fallback: item.rawPosterUrl, size: size)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .animation(.easeOut(duration: 0.18)) { view in
                        view
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 4)
                            }
                            .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 14, y: 8)
                    }
            }
        }
        .animation(.easeOut(duration: 0.18)) { view in
            view.scaleEffect(focused ? 1.07 : 1, anchor: .leading)
        }
    }
}

// MARK: - Data

/// The studio's TMDB data: its logo and figures, then the rows (the folder's catalogs first).
@MainActor
final class OrbitStudioModel: ObservableObject {
    @Published private(set) var rows: [OrbitStudioRow] = []
    /// A saga card's film (its first one), by the card's id.
    @Published private(set) var sagaFilms: [String: MetaPreview] = [:]
    /// The banner's featured films.
    @Published private(set) var heroItems: [MetaPreview] = []
    @Published private(set) var logo: String?
    @Published private(set) var statsLine: String?
    @Published private(set) var loading = true
    let name: String

    private let route: OrbitStudioRoute
    private var started = false
    private var folderModel: FolderDetailViewModel?
    private var folderRows: [OrbitStudioRow] = []
    private var tmdbRows: [OrbitStudioRow] = []
    private var cancellable: AnyCancellable?

    init(route: OrbitStudioRoute) {
        self.route = route
        name = route.name
    }

    func start() {
        guard !started else { return }
        started = true
        // The folder's own catalogs (Studios tab), drawn as the page's first rows.
        if let collectionId = route.collectionId, let folderId = route.folderId,
           let collection = CollectionRepository.shared.getCollection(id: collectionId),
           let folder = collection.folders.first(where: { $0.id == folderId }) {
            let folderModel = FolderDetailViewModel(route: FolderRoute(collectionId: collectionId, folder: folder))
            folderModel.buildsStripState = true
            self.folderModel = folderModel
            cancellable = folderModel.$stripRows.sink { [weak self] strip in
                Task { @MainActor in self?.applyFolder(strip) }
            }
            folderModel.start()
        }
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        guard !key.isEmpty else { loading = false; return }
        let language = TmdbSettingsRepository.shared.snapshot().language
        let route = route
        Task { [weak self] in
            let ids = await Self.resolveIds(route: route, apiKey: key)
            guard let ids, !ids.isEmpty else {
                self?.loading = false
                return
            }
            let found = await Self.load(ids: ids, network: route.isNetwork, apiKey: key, language: language)
            guard let self else { return }
            if self.logo == nil { self.logo = route.logo ?? found.logo }
            self.statsLine = Self.statsLine(network: route.isNetwork, count: found.count, since: found.since)
            self.sagaFilms = found.sagaFilms
            self.tmdbRows = found.rows.map { raw in
                let kind: OrbitStudioRowKind = raw.id == "best" ? .featured : raw.id == "sagas" ? .sagas
                    : .posters(transparent: false)
                return OrbitStudioRow(id: raw.id, title: raw.title, items: raw.items, kind: kind)
            }
            self.loading = false
            self.publish()
        }
    }

    private func applyFolder(_ strip: [FolderStripRow]) {
        folderRows = strip.compactMap { row in
            guard row.status == .loaded, let items = row.section?.items, !items.isEmpty else { return nil }
            let heading = row.heading.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let top10 = heading.contains("top 10") || heading.contains("top10")
            return OrbitStudioRow(id: "folder-\(row.id)", title: row.heading, items: items,
                                  kind: .posters(transparent: top10))
        }
        publish()
    }

    /// The order: his Nouveautés and Top 10, then "Les incontournables", "Les sagas", and the rest
    /// of the page's rows. Where the page has its own rows, his other catalogs are not drawn (they
    /// repeat them); without them (TMDB unknown), every catalog shows.
    private func publish() {
        let own = !tmdbRows.isEmpty
        let mine = own ? folderRows.filter { OrbitCatalogFilter.isKept($0.title) } : folderRows
        // "Les plus populaires" without the films of his Top 10 (it was the same row twice).
        let topNames = Set(mine.filter { row in
            if case .posters(transparent: true) = row.kind { return true }
            return false
        }.flatMap { $0.items.map { $0.name.lowercased() } })
        let shown = tmdbRows.compactMap { row -> OrbitStudioRow? in
            guard row.id == "popular", !topNames.isEmpty else { return row }
            let trimmed = OrbitStudioRow(id: row.id, title: row.title,
                                     items: row.items.filter { !topNames.contains($0.name.lowercased()) }, kind: row.kind)
            return trimmed.items.count >= 5 ? trimmed : nil
        }
        let next = mine + shown
        if next != rows { rows = next }
        // The banner: the newest films with art (his Nouveautés first), else the most popular.
        let source = (mine.first { !$0.title.lowercased().contains("top") }?.items ?? [])
            + (tmdbRows.first { $0.id == "popular" }?.items ?? [])
        var seen = Set<String>()
        let featured = source.filter { item in
            let banner: String? = item.banner
            return !(banner ?? "").isEmpty && seen.insert(item.name).inserted
        }
        let hero = Array(featured.prefix(5))
        if hero.map(\.id) != heroItems.map(\.id) { heroItems = hero }
    }

    private static func statsLine(network: Bool, count: Int, since: String?) -> String {
        var parts: [String] = [network ? String(localized: "Chaîne") : String(localized: "Studio")]
        if count > 0 {
            parts.append(network ? String(localized: "\(count) séries") : String(localized: "\(count) films"))
        }
        // No "depuis YYYY": TMDB's oldest dated film is often wrong (Disney showed 1983).
        return parts.joined(separator: " · ")
    }

    // MARK: TMDB

    nonisolated private struct SearchResponse: Decodable {
        nonisolated struct Hit: Decodable { let id: Int }
        let results: [Hit]?
    }

    nonisolated private struct CollectionResponse: Decodable {
        nonisolated struct Part: Decodable {
            let id: Int
            let title: String?
            let overview: String?
            let release_date: String?
            let poster_path: String?
            let backdrop_path: String?
            let vote_average: Double?
        }
        let parts: [Part]?
    }

    nonisolated private struct EntityResponse: Decodable {
        let logo_path: String?
    }

    nonisolated private struct DiscoverResponse: Decodable {
        nonisolated struct Result: Decodable {
            let id: Int
            let title: String?
            let name: String?
            let overview: String?
            let poster_path: String?
            let backdrop_path: String?
            let release_date: String?
            let first_air_date: String?
            let vote_average: Double?
        }
        let results: [Result]?
        let total_results: Int?
    }

    nonisolated private struct MovieResponse: Decodable {
        nonisolated struct Collection: Decodable {
            let id: Int
            let name: String?
            let backdrop_path: String?
            let poster_path: String?
        }
        let belongs_to_collection: Collection?
    }

    nonisolated private static func resolveIds(route: OrbitStudioRoute, apiKey: String) async -> String? {
        if let ids = route.companies, !ids.isEmpty { return ids }
        let query = route.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? route.name
        let kind = route.isNetwork ? "network" : "company"
        guard let url = URL(string: "https://api.themoviedb.org/3/search/\(kind)?api_key=\(apiKey)&query=\(query)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data),
              let first = decoded.results?.first else { return nil }
        return String(first.id)
    }

    nonisolated private static func load(ids: String, network: Bool, apiKey: String, language: String) async
        -> (logo: String?, count: Int, since: String?, rows: [(id: String, title: String, items: [MetaPreview])],
            sagaFilms: [String: MetaPreview]) {
        let lang = language.isEmpty ? "fr-FR" : language
        let media = network ? "tv" : "movie"
        let dateField = network ? "first_air_date" : "primary_release_date"
        let filter = network ? "&with_networks=\(ids)" : "&with_companies=\(ids)"
        let base = "https://api.themoviedb.org/3/discover/\(media)?api_key=\(apiKey)&language=\(lang)" + filter
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: Date())
        // "Prochainement": the films out within nine months. Further away, TMDB mostly has a
        // provisional poster (a logo on black: Frozen III, Tangled, Clay…) and no synopsis yet.
        let soon = formatter.string(from: Date().addingTimeInterval(270 * 86_400))

        // The logo (the first id's), the figures, the main rows, all at once.
        let firstId = ids.split(whereSeparator: { $0 == "|" || $0 == "," }).first.map(String.init) ?? ids
        async let entity: EntityResponse? = decode("https://api.themoviedb.org/3/\(network ? "network" : "company")/\(firstId)?api_key=\(apiKey)")
        async let oldest = discover(base + "&sort_by=\(dateField).asc&\(dateField).lte=\(today)&vote_count.gte=5", tv: network)
        async let best = discover(base + "&sort_by=vote_average.desc&vote_count.gte=300&with_runtime.gte=60", tv: network)
        async let popular = discover(base + "&sort_by=popularity.desc", tv: network)
        async let popular2 = discover(base + "&sort_by=popularity.desc&page=2", tv: network)
        async let upcoming = discover(base + "&sort_by=\(dateField).asc&\(dateField).gte=\(today)&\(dateField).lte=\(soon)", tv: network)

        let (entityValue, oldestValue, bestValue, popularValue, popular2Value, upcomingValue) =
            await (entity, oldest, best, popular, popular2, upcoming)

        var rows: [(id: String, title: String, items: [MetaPreview])] = []
        var sagaFilms: [String: MetaPreview] = [:]
        if bestValue.items.count >= 5 { rows.append(("best", String(localized: "Les incontournables"), bestValue.items)) }
        let popularItems = popularValue.items + popular2Value.items
        if popularItems.count >= 5 { rows.append(("popular", String(localized: "Les plus populaires"), popularItems)) }

        // The sagas: the collections the best-known films belong to (one card per saga, its art,
        // it opens the saga's first film met).
        if !network {
            var seen = Set<String>()
            let known = (popularItems + bestValue.items).filter { seen.insert($0.id).inserted }.prefix(30)
            let sagas = await withTaskGroup(of: (Int, MetaPreview?).self) { group in
                for (index, film) in known.enumerated() {
                    group.addTask {
                        let id = film.id.replacingOccurrences(of: "tmdb:", with: "")
                        let movie: MovieResponse? = await decode("https://api.themoviedb.org/3/movie/\(id)?api_key=\(apiKey)&language=\(lang)")
                        guard let saga = movie?.belongs_to_collection, let name = saga.name, !name.isEmpty else {
                            return (index, nil)
                        }
                        return (index, MetaPreview(id: film.id, type: "movie", name: name,
                                                   poster: saga.poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" } ?? film.poster,
                                                   banner: saga.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" } ?? film.banner,
                                                   logo: nil, posterShape: .landscape,
                                                   description: film.description_, releaseInfo: film.releaseInfo,
                                                   rawReleaseDate: nil, popularity: nil, voteCount: nil,
                                                   imdbRating: nil, genres: [], rawPosterUrl: "saga:\(saga.id)",
                                                   landscapePoster: nil, rawLandscapePosterUrl: nil,
                                                   customPosterApplied: false))
                    }
                }
                var out: [(Int, MetaPreview)] = []
                for await (index, item) in group { if let item { out.append((index, item)) } }
                return out.sorted { $0.0 < $1.0 }.map(\.1)
            }
            var sagaSeen = Set<String>()
            let unique = sagas.filter { sagaSeen.insert($0.rawPosterUrl ?? $0.name).inserted }
            // Each saga's first film (the earliest released part): the card opens it.
            let firsts = await withTaskGroup(of: (Int, MetaPreview?).self) { group in
                for (index, card) in unique.enumerated() {
                    group.addTask {
                        let sagaId = (card.rawPosterUrl ?? "").replacingOccurrences(of: "saga:", with: "")
                        guard let collection: CollectionResponse = await decode("https://api.themoviedb.org/3/collection/\(sagaId)?api_key=\(apiKey)&language=\(lang)") else {
                            return (index, nil)
                        }
                        let released = (collection.parts ?? []).filter { !($0.release_date ?? "").isEmpty && ($0.release_date ?? "") <= today }
                        guard let part = released.min(by: { ($0.release_date ?? "") < ($1.release_date ?? "") }),
                              let title = part.title, !title.isEmpty else { return (index, nil) }
                        let date = part.release_date
                        return (index, MetaPreview(id: "tmdb:\(part.id)", type: "movie", name: title,
                                                   poster: part.poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" },
                                                   banner: part.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" },
                                                   logo: nil, posterShape: .poster,
                                                   description: part.overview, releaseInfo: date.map { String($0.prefix(4)) },
                                                   rawReleaseDate: date, popularity: nil, voteCount: nil,
                                                   imdbRating: part.vote_average.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil },
                                                   genres: [], rawPosterUrl: nil, landscapePoster: nil,
                                                   rawLandscapePosterUrl: nil, customPosterApplied: false))
                    }
                }
                var out: [Int: MetaPreview] = [:]
                for await (index, film) in group { if let film { out[index] = film } }
                return out
            }
            var cards: [MetaPreview] = []
            for (index, card) in unique.enumerated() {
                guard let film = firsts[index] else { cards.append(card); continue }
                // The card takes the first film's id (its meta, its logo); the saga's name and art stay.
                cards.append(MetaPreview(id: film.id, type: "movie", name: card.name, poster: card.poster,
                                         banner: card.banner, logo: nil, posterShape: .landscape,
                                         description: film.description_, releaseInfo: film.releaseInfo,
                                         rawReleaseDate: nil, popularity: nil, voteCount: nil, imdbRating: nil,
                                         genres: [], rawPosterUrl: card.rawPosterUrl, landscapePoster: nil,
                                         rawLandscapePosterUrl: nil, customPosterApplied: false))
                sagaFilms[film.id] = film
            }
            if cards.count >= 2 { rows.append(("sagas", String(localized: "Les sagas"), cards)) }
        }

        // Only the films with a synopsis: the others have no real poster yet either.
        let upcomingItems = upcomingValue.items.filter { !($0.description_ ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        if upcomingItems.count >= 3 { rows.append(("upcoming", String(localized: "Prochainement"), upcomingItems)) }

        // A row per decade, from the newest.
        let year = Calendar.current.component(.year, from: Date())
        let firstDecade = (year / 10) * 10
        let decades = stride(from: firstDecade, through: 1950, by: -10).map { $0 }
        let decadeRows = await withTaskGroup(of: (Int, [MetaPreview]).self) { group in
            for decade in decades {
                group.addTask {
                    let range = "&\(dateField).gte=\(decade)-01-01&\(dateField).lte=\(decade + 9)-12-31"
                    return (decade, await discover(base + "&sort_by=popularity.desc&vote_count.gte=20" + range, tv: network).items)
                }
            }
            var out: [Int: [MetaPreview]] = [:]
            for await (decade, items) in group { out[decade] = items }
            return out
        }
        for decade in decades {
            let items = decadeRows[decade] ?? []
            guard items.count >= 6 else { continue }
            let label = decade >= 2000 ? String(localized: "Les années \(decade)")
                : String(localized: "Les années \(decade % 100)")
            rows.append(("decade-\(decade)", label, items))
        }

        let since = oldestValue.items.first?.rawReleaseDate.map { String($0.prefix(4)) }
        return (entityValue?.logo_path.map { "https://image.tmdb.org/t/p/w500\($0)" },
                popularValue.total, since, rows, sagaFilms)
    }

    nonisolated private static func decode<T: Decodable>(_ address: String) async -> T? {
        guard let url = URL(string: address),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    nonisolated private static func discover(_ address: String, tv: Bool) async -> (items: [MetaPreview], total: Int) {
        guard let decoded: DiscoverResponse = await decode(address) else { return ([], 0) }
        let items = (decoded.results ?? []).compactMap { r -> MetaPreview? in
            guard let name = r.title ?? r.name, !name.isEmpty, let poster = r.poster_path,
                  let backdrop = r.backdrop_path else { return nil }
            let date = r.release_date ?? r.first_air_date
            return MetaPreview(id: "tmdb:\(r.id)", type: tv ? "series" : "movie", name: name,
                               poster: "https://image.tmdb.org/t/p/w500\(poster)",
                               banner: "https://image.tmdb.org/t/p/w1280\(backdrop)",
                               logo: nil, posterShape: .landscape,
                               description: r.overview, releaseInfo: date.map { String($0.prefix(4)) },
                               rawReleaseDate: date, popularity: nil, voteCount: nil,
                               imdbRating: r.vote_average.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil },
                               genres: [], rawPosterUrl: nil, landscapePoster: nil,
                               rawLandscapePosterUrl: nil, customPosterApplied: false)
        }
        return (items, decoded.total_results ?? items.count)
    }
}
