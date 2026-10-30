import Combine
import SharedCore
import SwiftUI
import UIKit

// Orbit Studio (Steven, 2026-10-24): a studio's page, rebuilt from scratch — a showcase of its
// films, with a rhythm (Steven: "des trucs en avant en grand, d'autres moins en avant en petit"):
//
//  - A wide banner first: the studio's featured films one at a time (Left / Right), their trailer
//    in large behind the logo, the meta line and the synopsis; the studio's logo and figures in
//    the banner's corner.
//  - "Les incontournables" in large landscape cards (the trailer plays in the focused one).
//  - A shelf per saga (Disney+ style): its logo, "La saga · N films" and TOUT VOIR on its backdrop,
//    then its films' posters in order.
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
    /// Each opening is its own page (see `FolderRoute.openedAt`); not part of the identity.
    var openedAt: TimeInterval = ProcessInfo.processInfo.systemUptime

    static func == (a: OrbitStudioRoute, b: OrbitStudioRoute) -> Bool {
        a.name == b.name && a.companies == b.companies && a.isNetwork == b.isNetwork && a.logo == b.logo
            && a.collectionId == b.collectionId && a.folderId == b.folderId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name); hasher.combine(companies); hasher.combine(isNetwork)
        hasher.combine(collectionId); hasher.combine(folderId)
    }

    static func folder(collectionId: String, folder: CollectionFolder) -> OrbitStudioRoute {
        let logo: String? = OrbitStudioLogos.url(forTitle: folder.title) ?? folder.titleLogoUrl
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
    /// One saga's shelf: its logo and TOUT VOIR first (`items[0]`), then its films' posters.
    case saga
    /// Small portrait posters (transparent ones drawn as they are).
    case posters(transparent: Bool)
    /// Steven (2026-10-25): Orbit's own Top 10 (TMDB), drawn as Home's — the rank beside the
    /// poster, in the poster's colour (his add-on's images are no longer used).
    case ranked
    /// Steven (2026-10-27): the studio's new films as Home's first row — the focused one open in
    /// a 16:9 frame at the margin, its details under the row, the others as posters after it.
    case classic
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
        case .saga: return CGSize(width: 220, height: 330)
        // Steven (2026-10-25): his Top 10 images much larger than the other posters.
        case .posters(let transparent):
            // (Steven, 2026-10-27: Home's poster size — the same grid on both pages.)
            return transparent ? CGSize(width: 274, height: 412) : OrbitTileLayout.poster
        // Steven (2026-10-25): 15 % larger beside the saga's big band.
        case .ranked: return CGSize(width: OrbitTileLayout.rankedPoster.width * Self.rankedScale,
                                    height: OrbitTileLayout.rankedPoster.height * Self.rankedScale)
        case .classic: return CGSize(width: OrbitHomeLayout.posterWidth, height: OrbitHomeLayout.cardHeight)
        }
    }

    var gap: CGFloat {
        // Steven (2026-10-29): the same gaps as Home (posters 32, 16:9 cards 36, sagas 32).
        if case .posters = kind { return 32 }
        if kind == .classic { return OrbitHomeLayout.gap }
        // (Steven, 2026-10-27: the 16:9 cards a little apart, as on Home.)
        if kind == .featured { return 36 }
        if kind == .ranked { return 18 }
        return 32
    }

    /// The focused film's info shows under the row (not for a saga's shelf: its band is the info).
    /// (Steven, 2026-10-27, as on Home: the title's details only under the 16:9 cards — Les
    /// incontournables; the posters' rows are cleaner without, and scroll as Apple's app does.)
    /// (Steven, 2026-10-27: under the new films' open frame only — Les incontournables carry their
    /// title on their art.)
    var showsInfo: Bool { kind == .classic }
    /// The focused title kept at the margin, the row sliding under it: the new films, and the Top 10
    /// when it opens as Home's (Steven: the same in the studios).
    var pinned: Bool { showsInfo || opensRanked }
    var opensRanked: Bool { kind == .ranked && OrbitNativeRow.rankedOpens }

    /// (Steven, 2026-10-27: Home's size — the same Top 10 on both pages.)
    static let rankedScale: CGFloat = 1.0

    /// A saga shelf's first place (its logo and TOUT VOIR).
    /// (Steven: the posters sat too far right of the left-aligned logo and text: narrower.)
    static let sagaPanelWidth: CGFloat = 430

    /// A card's place along the row from the margin. Ordinary rows: from the focused card (it stays
    /// at the margin). A saga's shelf (Steven): the logo stays put and the cursor moves along the
    /// films; they slide only once the cursor would leave the screen.
    func x(of index: Int, lead: Int) -> CGFloat {
        if kind == .ranked { return CGFloat(index - lead) * (OrbitTileLayout.rankWidth * Self.rankedScale + cardSize.width + gap) }
        guard kind == .saga else { return CGFloat(index - lead) * (cardSize.width + gap) }
        if index == 0 { return 0 }
        return Self.sagaPanelWidth + gap + CGFloat(index - 1 - sagaScroll(lead: lead)) * (cardSize.width + gap)
    }

    /// The films slid out on the left of a saga's shelf.
    func sagaScroll(lead: Int) -> Int {
        let room = OrbitHomeLayout.screenWidth - 2 * OrbitStudioLayout.margin - Self.sagaPanelWidth - gap
        let fits = max(1, Int((room + gap) / (cardSize.width + gap)))
        return max(0, (lead - 1) - (fits - 1))
    }

    /// Drawn: a saga's films before its scroll are hidden; elsewhere the cards before the focused one.
    func isHidden(_ index: Int, lead: Int) -> Bool {
        guard kind == .saga else { return index < lead }
        return index > 0 && index - 1 < sagaScroll(lead: lead)
    }

    /// From this row's heading to the next one's.
    var pitch: CGFloat {
        OrbitStudioLayout.cardsTop + cardSize.height + (showsInfo ? 230 : kind == .saga ? 110 : 80)
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
    @StateObject private var trailer = OrbitNativeTrailerHost()
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
    @Environment(\.orbitPush) private var orbitPush
    @State private var tint: Color?
    /// The opening is over: the page's own studio logo shows (the opening's lands on it).
    @State private var introDone = false
    /// When a title was last opened from a studio page (its disappearance then is a push, not a close).
    @MainActor private static var pushedAt: TimeInterval = 0

    // Native page (Steven, 2026-10-25: as fluid as Home): real rows of real buttons, moved by the
    // system.
    @FocusState private var nativeHeroFocus: Int?
    @State private var nativeHeroPage = 0
    @State private var nativeOnHero = true
    @State private var nativePosition: String? = "hero"
    /// Steven (2026-10-29, device: "le défilement vertical est très saccadé"): Home's vertical move —
    /// the page brought to the row on Apple's curve (full speed at the press, easing to rest in
    /// 0.4 s), asked for every move.
    @State private var nativeScroll = ScrollPosition(idType: String.self)
    @State private var nativeLastGo: TimeInterval = 0
    @State private var nativeSystemScrollOff = false

    private func nativeGo(to id: String, animated: Bool = true) {
        if nativePosition == id, ProcessInfo.processInfo.systemUptime - nativeLastGo < 0.2 { return }
        nativeLastGo = ProcessInfo.processInfo.systemUptime
        nativePosition = id
        // (As Home: one mover — past the first row the system's own scroll is off, no nudge after
        // the page rests; nothing redrawn mid-move by details arriving.)
        nativeSystemScrollOff = id != "hero" && id != "header" && (rows.firstIndex { $0.id == id } ?? 0) >= 1
        OrbitMetaStore.shared.holdPublishing(for: 0.6)
        if animated && !reduceMotion {
            withAnimation(.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.4)) { nativeScroll.scrollTo(id: id, anchor: .top) }
        } else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { nativeScroll.scrollTo(id: id, anchor: .top) }
        }
    }
    @State private var studioHeroLocked = false
    /// Back from a title: the row it was opened from (the only one the focus can land in a moment).
    @State private var returnRow: String?
    @State private var nativeRow: String?
    /// The native page's trailer (banner, featured cards) — a reference, never observed by the page.
    @State private var nativeTrailers = OrbitNativeTrailerHost()
    /// (Steven: the house sat right on the row's heading — the rows' line lower, room under it.)
    static let nativeTop: CGFloat = 165

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

    /// The title focused in the rows (Home's wash and the headings' bar follow it) — held apart, so
    /// a new title redraws only the wash.
    @State private var rowSpot = OrbitStudioSpot()

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
            // Steven (2026-10-29: "intérieur studio comme accueil"): in the rows, the focused title's
            // colour washes the page as on Home (same wash, same 250 ms rest and 0.45 s fade); the
            // banner keeps the studio's own colour.
            // (Steven, 2026-10-29, after trying it: a studio keeps its own colour — no title wash.)

                            nativeContent
            

            // The studio's opening, over everything from the first frame (the catalogue never
            // shows before it).
            if !introDone {
                OrbitStudioIntro(name: model.name, logoUrl: model.logo ?? route.logo, tint: brand,
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
            OrbitHomeButtonHost.shared.enter(.onRequest)
            model.start()
            trailer.restSource = .custom(motion)
            nativeTrailers.suspended = false
            if let back = OrbitNativeStudioRow.reopen {
                studioHeroLocked = true
                returnRow = back.row
                nativeGo(to: back.row, animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { studioHeroLocked = false; returnRow = nil }
            }
            DispatchQueue.main.async {
                 if hasHero, nativeHeroFocus == nil, OrbitNativeStudioRow.reopen == nil { nativeHeroFocus = 0 } 
            }
            refreshAfterMove()
        }
        .onDisappear {
            tabBarVisibility.popImmersive()
            OrbitHomeButtonHost.shared.leave(.onRequest)
            trailer.reset(abortStages: true)
            nativeTrailers.stop(abort: true)
            nativeTrailers.suspended = true
            // Steven (device: entering a studio, its page showed — with its logo — before the
            // opening): the system can show a closed page's view again for a moment on the next
            // visit. Closed (not covered by a title), it goes back to its black opening.
            // (Steven, simulator: back from a title the opening played again — the page went away
            // late: it is closed only when no title page covers it, a moment later.)
            let left = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard OrbitNavClock.titlesShown == 0, left - Self.pushedAt > 1.5,
                      OrbitNavClock.titleOpenedAt < left - 2.0 else { return }
                introDone = false
                current = 0
            }
        }
        // Down from the house: back on the page.
        .onReceive(NotificationCenter.default.publisher(for: .orbitHomeButtonLeave)) { _ in
            canvasFocused = true
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

    // MARK: Native page

    @ViewBuilder
    private var nativeContent: some View {
        let L = OrbitStudioLayout.self
        ZStack(alignment: .topLeading) {
            ScrollView(.vertical, showsIndicators: false) {
                // Home's gap between rows (Steven, 2026-10-29: "partout pareil").
                VStack(alignment: .leading, spacing: OrbitNativeHome.sectionGap) {
                    if hasHero {
                        nativeHero
                            // Back from a title of a row: the banner out of the focus's reach a moment.
                            .disabled(studioHeroLocked)
                            .id("hero")
                    } else {
                        OrbitStudioHeader(name: model.name, logo: model.logo ?? route.logo, line: nil)
                            .padding(.leading, L.margin)
                            .frame(height: 360 - Self.nativeTop, alignment: .topLeading)
                            .id("header")
                    }
                    ForEach(rows) { row in
                        OrbitNativeStudioRow(row: row, isCurrent: nativeRow == row.id,
                                             accent: brand, trailers: nativeTrailers,
                                             onEnter: { nativeEnter(row.id) }, onOpen: { nativeOpen($0) },
                                             onItem: { rowSpot.item = $0 })
                            // (As Home's rows: a row is redrawn only when it changes — the page's
                            // moves no longer redraw every row.)
                            .equatable()
                            .id(row.id)
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
            .scrollPosition($nativeScroll)
            .scrollDisabled(nativeSystemScrollOff)
            .contentMargins(.top, Self.nativeTop, for: .scrollContent)
            .scrollClipDisabled()

            // Off the banner, the band under the top is the page's own ground (as Home's: Steven,
            // 2026-10-29 — "toujours très d'ombre en haut"), the rows sliding away under it.
            OrbitStudioBackground(brand: brand)
                .mask(alignment: .top) {
                    // (Steven: bits of the posters above showed — whole down to just above the rows'
                    // line, then a short edge.)
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: (Self.nativeTop - 26) / Self.nativeTop),
                                           .init(color: .black.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(width: OrbitHomeLayout.screenWidth, height: Self.nativeTop)
                }
                .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight, alignment: .top)
                // Steven (2026-10-30, photo: "ça ne va pas jusqu'en haut de l'écran"): no band — the
                // rows above show up to the top, as on Disney+; the banner's art (its bits showed
                // above the rows) goes as the rows take the focus.
                .opacity(0)
                .allowsHitTesting(false)

            // The studio's logo stays top right while the page moves (Steven).
            Group {
                if OrbitStudioIntroLogo.isNatGeo(model.name) {
                    // (Steven: its black name vanished on the dark page — his own file.)
                    OrbitStudioIntroLogo(name: model.name, logoUrl: nil, corner: true)
                } else if let logo = model.logo ?? route.logo, !logo.isEmpty {
                    OrbitBalancedLogo(url: logo, area: 13_000, maxSize: OrbitStudioIntro.cornerBox,
                                      whiten: OrbitBalancedLogo.isGrey(model.name), alignment: .topTrailing)
                } else {
                    Text(model.name)
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(width: OrbitStudioIntro.cornerBox.width, height: OrbitStudioIntro.cornerBox.height,
                               alignment: .topTrailing)
                }
            }
            .frame(width: OrbitStudioIntro.cornerBox.width, height: OrbitStudioIntro.cornerBox.height, alignment: .topTrailing)
            .shadow(color: .black.opacity(0.45), radius: 12, y: 3)
            .opacity(introDone && (hasHero || !nativeOnHero) ? 1 : 0)
            .offset(x: OrbitHomeLayout.screenWidth - OrbitStudioIntro.cornerTrailing - OrbitStudioIntro.cornerBox.width,
                    y: OrbitStudioIntro.cornerTop)
            .allowsHitTesting(false)

            if sectionCount == 0 {
                Group {
                    if model.loading {
                        ProgressView()
                    } else {
                        Text(String(localized: "Aucun film trouvé pour \(model.name)."))
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
                .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
            }
        }
        .onExitCommand(perform: nativeExit)
        .onChange(of: nativeHeroFocus) { _, focus in
            guard focus != nil else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if nativeHeroFocus == nil, nativeRow == nil { nativeTrailers.stop() }
                }
                return
            }
            armHero(nativeHeroPage)
            nativeRow = nil
            nativeOnHero = true
            nativeGo(to: "hero")
        }
        // Left / Right on the banner: the next film fades in (Steven: no slide).
        .onChange(of: nativeHeroPage) { _, page in
            if nativeHeroFocus != nil { armHero(page) }
        }
    }

    private func armHero(_ page: Int) {
        guard heroItems.indices.contains(page) else { return }
        let item = heroItems[page]
        nativeTrailers.arm("hero|\(item.type):\(item.id)", item: item, reduceMotion: reduceMotion)
        if heroItems.indices.contains(page + 1) { OrbitMetaStore.shared.request([heroItems[page + 1]]) }
    }

    /// The banner: one button showing the film of the page; Left / Right change it with a plain
    /// cross-fade (Steven: he did not like the slide); Up goes to the house.
    private var nativeHero: some View {
        let count = heroItems.count
        let page = min(nativeHeroPage, max(0, count - 1))
        return Button {
            if heroItems.indices.contains(page) { nativeOpen(heroItems[page]) }
        } label: {
            ZStack(alignment: .topLeading) {
                if heroItems.indices.contains(page) {
                    let item = heroItems[page]
                    OrbitNativeStudioHeroPage(item: item, meta: metaStore.meta(for: item), trailers: nativeTrailers,
                                              studioName: model.name, studioLogo: model.logo ?? route.logo,
                                              showsStudioLogo: false, statsLine: model.statsLine,
                                              count: count, index: page, live: true)
                        .id(page)
                        // The fade alone carries the animation (Steven: it also zoomed — the whole
                        // page animated, the new film's logo and art growing into their places).
                        .transition(.opacity.animation(.easeInOut(duration: 0.45)))
                }
            }
            .frame(width: OrbitHomeLayout.screenWidth, height: OrbitStudioLayout.heroHeight - Self.nativeTop,
                   alignment: .topLeading)
            // (Off the banner its art fades — only what it draws: the button itself stays, focusable;
            // Steven: hidden whole, Up could no longer reach it, nor the bar.)
            .opacity(nativeOnHero ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: nativeOnHero)
        }
        .buttonStyle(OrbitPlainStyle())
        .focused($nativeHeroFocus, equals: 0)
        .onMoveCommand { direction in
            switch direction {
            case .up: NotificationCenter.default.post(name: .orbitHomeButtonFocus, object: nil)
            case .left: if nativeHeroPage > 0 { nativeHeroPage -= 1 }
            case .right: if nativeHeroPage < count - 1 { nativeHeroPage += 1 }
            default: break
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitStudioLayout.heroHeight - Self.nativeTop)
        .focusSection()
        .defaultFocus($nativeHeroFocus, 0,
                      // (Back from a title of a row: its card takes the focus, not the banner first.)
                      priority: OrbitNativeStudioRow.reopen == nil ? .userInitiated : .automatic)
    }

    /// Menu: from a row, back to the banner; on the banner (or with none), the page closes.
    private var nativeExit: (() -> Void)? {
        guard hasHero, !nativeOnHero else { return nil }
        return { nativeHeroFocus = 0 }
    }

    private func nativeEnter(_ rowID: String) {
        nativeRow = rowID
        nativeOnHero = false
        nativeGo(to: rowID)
    }

    private func nativeOpen(_ item: MetaPreview) {
        // A saga opens its first film, as that film (its own name and art, not the saga's).
        let route = TitleRoute(preview: model.sagaFilms[item.id] ?? item)
        Self.pushedAt = ProcessInfo.processInfo.systemUptime
        if let orbitPush { orbitPush(route) } else { opening = route }
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
            guard index > 0 else {
                // At the top: the house (top left).
                NotificationCenter.default.post(name: .orbitHomeButtonFocus, object: nil)
                return
            }
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
        let route = TitleRoute(preview: model.sagaFilms[item.id] ?? item)
        Self.pushedAt = ProcessInfo.processInfo.systemUptime
        if let orbitPush { orbitPush(route) } else { opening = route }
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

// MARK: - Opening

/// The studio's opening (Steven, 2026-10-24, "le générique de studio"): black, the studio's logo
/// fades in large in the middle, lights up, then it glides to its place top right
/// while the page fades in. Once per visit (back from a film, nothing replays); any press skips
/// it; with Reduce Motion, nothing plays.
struct OrbitStudioIntro: View {
    let name: String
    let logoUrl: String?
    /// Steven: the opening's black tinted with the studio's colour, as the platforms' are.
    var tint: Color? = nil
    let onDone: () -> Void
    /// The tint drawn (the curtain's own when the page was pushed under it: the same colour).
    @State private var shownTint: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .black
    @State private var veil: Double = 1
    @State private var dim: Double = 1
    @State private var glow: Double = 0
    @State private var work: [DispatchWorkItem] = []
    @State private var started = false
    @State private var appearedAt = Date.distantFuture

    private enum Phase { case black, splash, corner }

    /// The next opening skipped (Disney+'s brands open their studio at once).
    static var skipNext = false

    /// The page's studio logo: its box and place (top right of the banner).
    /// Steven: level with the Orbit bar (its centre line), at its right end.
    static let cornerBox = CGSize(width: 300, height: OrbitPlatformIntro.cornerHeight)
    /// (Steven: in the TV's corner, at the same place as the platforms' logos.)
    static let cornerTop: CGFloat = OrbitPlatformIntro.cornerInset
    static let cornerTrailing: CGFloat = OrbitPlatformIntro.cornerInset
    static let splashScale: CGFloat = 2.9  // Steven (2026-10-29): larger on his large screen (was 2.4)

    var body: some View {
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        let box = Self.cornerBox
        let corner = CGPoint(x: W - Self.cornerTrailing - box.width / 2, y: Self.cornerTop + box.height / 2)
        let centre = phase == .corner ? corner : CGPoint(x: W / 2, y: H / 2)
        ZStack(alignment: .topLeading) {
            ZStack {
                Color.black
                if let tint = shownTint ?? tint {
                    RadialGradient(colors: [tint.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 900)
                }
            }
            .frame(width: W, height: H)
            .opacity(veil)

            logo
                // Centred in the middle; in the corner, right-aligned as the page's own logo.
                .frame(width: box.width, height: box.height, alignment: phase == .corner ? .topTrailing : .center)
                // Steven: the logo switched on — it comes up dim, lights up, then takes the viewer in.
                .modifier(OrbitLightUp(dim: dim, glow: glow, tint: shownTint ?? tint ?? Color(white: 0.8)))
                .scaleEffect(phase == .corner ? 1 : (phase == .black ? Self.splashScale * 0.92 : Self.splashScale))
                .opacity(phase == .black ? 0 : 1)
                .position(centre)
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            appearedAt = Date()
            // Opened from Disney+'s brands (Steven): no opening, the page at once.
            if Self.skipNext {
                Self.skipNext = false
                started = true
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { phase = .corner; veil = 0; dim = 0; glow = 0 }
                onDone()
                return
            }
            // Pushed under the Studios page's curtain, which already shows this very opening: the
            // page starts at the same point, the curtain goes once the push is over.
            if OrbitPlatformCurtain.shared.down {
                let look = OrbitPlatformCurtain.shared.look
                if let look, look.studio {
                    shownTint = look.brand
                    var still = Transaction()
                    still.disablesAnimations = true
                    withTransaction(still) { phase = .splash; dim = 0; glow = 0.35 }
                    // Steven (2026-10-30: the studio's page showed a second during the opening, then
                    // went — as the platforms' did): the curtain went 0.3 s after the push began, the
                    // push still sliding the page in. As the platforms' now: it goes at 0.75 s, as the
                    // logo leaves for its corner, the page fading in under it.
                    let lift = 0.75
                    DispatchQueue.main.asyncAfter(deadline: .now() + lift) { OrbitPlatformCurtain.shared.lift(instant: true) }
                    play(fromSplash: true, after: lift - 0.4)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { OrbitPlatformCurtain.shared.lift() }
            }
            // Steven (opened from a film's page): the logo is not known yet — the screen stays
            // black until it is (its name only if it never comes).
            if let logoUrl, !logoUrl.isEmpty {
                play()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { play() }
            }
        }
        .onChange(of: logoUrl) { _, url in
            if let url, !url.isEmpty { play() }
        }
        .onReceive(NotificationCenter.default.publisher(for: ViewerInputClock.didRecord)) { _ in
            // A press skips the opening — not the press that opened the page (it lands just after).
            guard phase != .corner || veil > 0, Date().timeIntervalSince(appearedAt) > 0.8 else { return }
            work.forEach { $0.cancel() }
            withAnimation(.easeOut(duration: 0.3)) { phase = .corner; veil = 0; dim = 0; glow = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { onDone() }
        }
    }

    private var logo: some View {
        OrbitStudioIntroLogo(name: name, logoUrl: logoUrl, corner: phase == .corner)
    }

    /// `after`: under the curtain, the time it still shows (its neon) — the glide comes after it.
    private func play(fromSplash: Bool = false, after: Double = 0) {
        guard !started, fromSplash || phase == .black, veil == 1 else { return }
        started = true
        if reduceMotion { dim = 0; onDone(); return }
        func at(_ delay: Double, _ body: @escaping () -> Void) {
            let item = DispatchWorkItem(block: body)
            work.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
        // 0 s: the logo fades in, large, in the middle (already there under the curtain).
        if !fromSplash { withAnimation(.easeOut(duration: 0.55)) { phase = .splash } }
        // Then it lights up as a neon sign: two flickers, its flash, a soft glow left on it.
        if !fromSplash {
            OrbitNeon.play(at: 0.35) { d, g, animation in
                guard phase == .splash else { return }
                withAnimation(animation) { dim = d; glow = g }
            }
        }
        // 1.5 s: it glides to its place, the page fades in under it.
        at(fromSplash ? after + 0.4 : 1.5) {  // (Steven: a hitch as it left the centre — a moment more for the page to settle.)
            withAnimation(.spring(response: 0.8, dampingFraction: 0.9)) { phase = .corner }
            withAnimation(.easeInOut(duration: 0.8)) { veil = 0; glow = 0 }
        }
        // 2.4 s: the page's own logo takes over (same place, same size).
        at(fromSplash ? after + 1.3 : 2.4) { onDone() }
    }
}

// MARK: - Native page's parts

/// One banner page of the native studio page, focused as its button is (drawn from the top).
private struct OrbitNativeStudioHeroPage: View {
    let item: MetaPreview
    let meta: OrbitMeta?
    let trailers: OrbitNativeTrailerHost
    let studioName: String
    let studioLogo: String?
    let showsStudioLogo: Bool
    let statsLine: String?
    let count: Int
    let index: Int
    let live: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        // (The page's own line: Steven — a black band at the top once the line went lower.)
        let top: CGFloat = OrbitStudioPage.nativeTop
        ZStack(alignment: .top) {
            if live {
                OrbitNativeTrailerReader(host: trailers, key: "hero|\(item.type):\(item.id)") { url in
                    OrbitStudioHero(item: item, meta: meta, studioName: studioName, studioLogo: studioLogo,
                                    showsStudioLogo: showsStudioLogo, statsLine: statsLine, focused: isFocused,
                                    count: count, index: index, trailerURL: url,
                                    onTrailerFailure: { trailers.model.playbackFailed($0) },
                                    onTrailerEnded: { trailers.model.playbackFinished() })
                }
                    .frame(width: OrbitHomeLayout.screenWidth, height: OrbitStudioLayout.heroHeight, alignment: .top)
                    .offset(y: -top)
            } else {
                Color.clear
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitStudioLayout.heroHeight - top, alignment: .top)
    }
}

/// A row of the native studio page: real buttons the system slides, the focused one at the margin.
/// The title focused in a studio's rows.
@MainActor
final class OrbitStudioSpot: ObservableObject {
    @Published var item: MetaPreview?
}

/// A studio's wash: Home's (the focused title's colour, its rest and fade) while the rows hold the
/// focus; the headings' bar follows it (`OrbitHomeTone.studio`). On the banner, the studio's own.
private struct OrbitStudioWash: View {
    @ObservedObject var spot: OrbitStudioSpot
    let inRows: Bool
    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        OrbitFocusBackdrop(item: inRows ? spot.item : nil)
            .opacity(inRows ? 1 : 0)
            .animation(.easeInOut(duration: OrbitRowsBackdrop.fade), value: inRows)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .task(id: (inRows ? spot.item.map { "\($0.type):\($0.id)" } : nil) ?? "-") { await follow() }
            .onChange(of: inRows) { _, rows in
                if !rows { withAnimation(.easeInOut(duration: OrbitRowsBackdrop.fade)) { OrbitHomeTone.studio.color = nil } }
            }
            .onDisappear { OrbitHomeTone.studio.color = nil }
    }

    private func follow() async {
        guard inRows, let item = spot.item else { return }
        do { try await Task.sleep(for: .milliseconds(OrbitRowsBackdrop.wait)) } catch { return }
        let raw = metaStore.meta(for: item)?.backdrop ?? item.banner ?? item.poster
        guard let raw, let color = await OrbitDominantColor.color(for: raw), !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: OrbitRowsBackdrop.fade)) { OrbitHomeTone.studio.color = color }
    }
}

extension OrbitNativeStudioRow: Equatable {
    static func == (a: OrbitNativeStudioRow, b: OrbitNativeStudioRow) -> Bool {
        a.row == b.row && a.isCurrent == b.isCurrent && a.accent == b.accent
    }
}

private struct OrbitNativeStudioRow: View {
    let row: OrbitStudioRow
    let isCurrent: Bool
    let accent: Color?
    let trailers: OrbitNativeTrailerHost
    let onEnter: () -> Void
    let onOpen: (MetaPreview) -> Void
    /// The title focused in this row (the page's wash follows it).
    var onItem: (MetaPreview) -> Void = { _ in }

    @FocusState private var focused: Int?
    @State private var holds = false
    @State private var shown: Int?
    @State private var anchor: Int?
    @State private var scroll = ScrollPosition(idType: Int.self)
    /// Each row's scroll (where it comes back to on the way back from a title).
    @MainActor static var offsets: [String: CGFloat] = [:]
    @ObservedObject private var metaStore = OrbitMetaStore.shared

    /// The title opened from a studio page (row, place): the focus goes back to it.
    @MainActor static var reopen: (row: String, index: Int)?
    @State private var restoringSince: TimeInterval = 0
    @State private var restoreLock = false
    @State private var disappeared = false
    /// The Top 10's Left: the row put at once where it ends, slid there (Netflix's).
    @State private var slideX: CGFloat = 0
    /// Where the Top 10's open title is in the row: the frame follows it (Netflix's).
    @State private var openX: CGFloat?

    /// The row put back where it is shown: a row with details on its title at the margin (exact),
    /// the others at their kept scroll.
    private func settle(on index: Int?) {
        var still = Transaction()
        still.disablesAnimations = true
        if row.pinned, let index {
            withTransaction(still) { scroll.scrollTo(id: index, anchor: .leading) }
        }
        // A row scrolled freely is never moved by us (Steven's video, Disney+ Top 10: at the
        // press the row slid right — the kept scroll put back — then again on the way back). The
        // system keeps it where it is; only the title's tile can take the focus meanwhile.
    }

    private func lockForReturn(_ index: Int) {
        // Nothing touches the row at the press (Steven: it slid right now and then): the aim and
        // the lock wait for the page to have gone (`onDisappear`).
    }

    @State private var strip = OrbitStripRef()
    @Environment(\.orbitFocusHidden) private var rowFocusHidden

    /// Steven (2026-10-29: "le défilement de Nouveaux films… exactement le même de partout"): the
    /// new films' row of a studio as Home's — the open title's room left empty in the strip, its
    /// frame drawn by the row at the margin, the next title fading in inside it.
    @ViewBuilder
    private func classicFrame(lit: Bool) -> some View {
        if let i = shown ?? (row.items.isEmpty ? nil : 0), row.items.indices.contains(i) {
            let item = row.items[i]
            let key = "\(row.id)|\(item.type):\(item.id)"
            OrbitNativeTrailerReader(host: trailers, key: key) { url in
                OrbitLeadFrame(card: OrbitCard.catalog(item), meta: metaStore.meta(for: item), focused: lit, trailerURL: url,
                               onTrailerFailure: { trailers.model.playbackFailed($0) },
                               onTrailerEnded: { trailers.model.playbackFinished() })
            }
            .shadow(color: .black.opacity(lit ? 0.55 : 0), radius: lit ? 18 : 0, y: lit ? 10 : 0)
            .animation(.easeOut(duration: 0.18), value: lit)
            .id(i)
            .transition(.opacity.animation(.easeInOut(duration: 0.22)))
            .offset(x: OrbitStudioLayout.margin)
            .allowsHitTesting(false)
        }
    }

    // Steven (2026-10-29: "dans le studio t'as pas mis le défilement infini"): the new films loop as
    // Home's — the titles repeated in the strip, the lead starting in the middle copy.
    private var loops: Bool { row.kind == .classic && row.items.count >= 3 }
    private var places: Int { row.items.count * (loops ? 7 : 1) }
    /// The lead's place in the strip (a looping row: past the end, its title taken round).
    @State private var place: Int?
    private func itemIndex(_ v: Int) -> Int {
        let n = row.items.count
        return n == 0 ? 0 : ((v % n) + n) % n
    }
    private var leadPlace: Int { place ?? ((loops ? row.items.count * 3 : 0) + (shown ?? 0)) }
    /// The Top 10 as Home's: the poster rested on (1.5 s) widens into its 16:9 frame with its trailer.
    @State private var rankedOpen: Int?
    @State private var dwell: DispatchWorkItem?

    /// Each title's room in the strip.
    private func stripWidth(_ v: Int) -> CGFloat {
        let size = row.cardSize
        switch row.kind {
        case .saga: return v == 0 ? OrbitStudioRow.sagaPanelWidth : size.width
        case .ranked:
            if v == rankedOpen {
                return OrbitRankedTile.rankRoom(v + 1, scale: OrbitStudioRow.rankedScale)
                    + OrbitNativeRankedOpenTile.frame(scale: OrbitStudioRow.rankedScale).width
            }
            return OrbitRankedTile.closedWidth(v + 1, scale: OrbitStudioRow.rankedScale)
        case .classic: return size.width  // (its open room: `openDelta`, moved by the strip with the focus)
        default: return size.width
        }
    }

    /// The focus moved in the strip (nil: it left the row).
    private func stripFocus(_ newPlace: Int?) {
        dwell?.cancel()
        if rankedOpen != nil { rankedOpen = nil }
        guard let newPlace else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                if strip.controller?.focusedIndex == nil, holds { holds = false }
            }
            return
        }
        if !holds {
            holds = true
            onEnter()
        }
        let new = itemIndex(newPlace)
        // (As Home's new films: the lead set plainly — the strip slides, the frame fades.)
        if loops { place = newPlace }
        shown = new
        if row.kind == .ranked, row.items.indices.contains(new) {
            let item = row.items[new]
            let work = DispatchWorkItem {
                guard shown == new, holds else { return }
                trailers.arm("\(row.id)|\(item.type):\(item.id)", item: item)
                rankedOpen = newPlace
            }
            dwell = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
        if row.items.indices.contains(new) { onItem(row.items[new]) }
        if row.kind == .featured || row.kind == .classic || row.opensRanked, row.items.indices.contains(new) {
            let item = row.items[new]
            trailers.arm("\(row.id)|\(item.type):\(item.id)", item: item)
        } else {
            trailers.stop()
        }
        guard row.items.indices.contains(new) else { return }
        let ahead = row.items[new..<min(row.items.count, new + 6)]
        OrbitMetaStore.shared.request(Array(ahead))
    }

    var body: some View {
        let L = OrbitStudioLayout.self
        let size = row.cardSize
        let saga = row.kind == .saga
        let lastWidth = row.kind == .ranked ? size.width + OrbitTileLayout.rankWidth * OrbitStudioRow.rankedScale : size.width
        VStack(alignment: .leading, spacing: 14) {
            if !saga {
                OrbitRowHeading(title: row.title, isCurrent: isCurrent, accent: accent)
                    .padding(.leading, L.margin + 4)
            }
            // Steven (2026-10-29: "applique-le de PARTOUT"): a UIKit strip the focus engine
            // scrolls, as Home's rows and Apple's TV app (`OrbitStripView`).
            OrbitStripView(count: places, identity: row.id + (loops ? "|loop" : ""), spacing: row.gap, height: size.height,
                           margin: L.margin, alignment: .bottom, pinned: row.pinned, lead: leadPlace,
                           width: { v in stripWidth(v) },
                           openDelta: row.kind == .classic ? OrbitHomeLayout.frameWidth - size.width : nil, ref: strip,
                           tile: { v, focused in
                               row.kind == .classic && v == leadPlace
                                   ? AnyView(Color.clear.frame(width: OrbitHomeLayout.frameWidth, height: size.height))
                                   : AnyView(OrbitStudioStripTile(row: row, index: itemIndex(v), trailers: trailers, focused: focused,
                                                                  open: row.kind == .ranked && v == rankedOpen && focused))
                           },
                           onFocus: { stripFocus($0) },
                           onSelect: { v in
                               let i = itemIndex(v)
                               guard row.items.indices.contains(i) else { return }
                               Self.reopen = (row.id, i)
                               onOpen(row.items[i])
                           })
                .frame(height: size.height)
                .modifier(OrbitShadeBeforeMargin(active: row.kind == .classic, margin: L.margin))
                .overlay(alignment: .bottomLeading) {
                    if row.kind == .classic { classicFrame(lit: holds && !rowFocusHidden) }
                }

            if row.showsInfo {
                ZStack(alignment: .topLeading) {
                    Color.clear
                    details(isCurrent ? shown.flatMap { row.items.indices.contains($0) ? row.items[$0] : nil } : nil)
                }
                .frame(width: 1200, height: 112, alignment: .topLeading)
                .clipped()
                // Steven: the text was too close under the posters (the focused one, larger,
                // nearly touched it). Lower again (2026-10-26), the row's height unchanged: the
                // 16 points come out of the gap under the row.
                .padding(.top, 20)
                .padding(.bottom, -8)
                .padding(.leading, L.margin + 6)
            }
        }
        // Steven (device: the next row's title sat on the saga's band): the band is exactly the
        // shelf's own height, with room above and below its posters.
        .padding(.vertical, saga ? 30 : 0)
        .background(alignment: .topLeading) {
            if saga {
                OrbitSagaBand(backdrop: row.items.first?.banner, height: size.height + 60)
            }
        }
        .focusSection()
        .defaultFocus($focused, shown ?? 0, priority: .userInitiated)
        // (Every appearance: a row scrolled off the page and back stopped keeping where it was —
        // Steven: back from a title the row came back far from where he left it.)
        .onAppear { disappeared = false; restoreIfReturning() }
        .onDisappear {
            disappeared = true
            if let back = Self.reopen, back.row == row.id {
                settle(on: back.index)
                restoreLock = true
            }
        }
        .onChange(of: focused) { _, new in
            guard let new else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    if focused == nil, holds { holds = false }
                }
                return
            }
            // Back from a title: a landing on another title is the system's — sent straight back.
            if let back = Self.reopen, back.row == row.id, new != back.index, restoringSince > 0,
               !ViewerInputClock.shared.hasInput(since: restoringSince) {
                DispatchQueue.main.async { focused = back.index }
                return
            }
            let moving = holds
            if !holds {
                holds = true
                onEnter()
            }
            shown = new
            // The trailer plays in the featured cards and the new films' open frame.
            if row.kind == .featured || row.kind == .classic || row.opensRanked, row.items.indices.contains(new) {
                let item = row.items[new]
                trailers.arm("\(row.id)|\(item.type):\(item.id)", item: item)
            } else {
                trailers.stop()
            }
            // Only a row with the title's details under it keeps it at the margin; the others scroll as
            // Apple's app does (Steven), the row moving only when the focus reaches its edge.
            if row.pinned, anchor != new {
                let old = anchor
                anchor = new
                // (Steven: Left as Right — the same slide.)
                if false, row.opensRanked, let old, new < old, old - new <= 3 {
                    // (Steven: Left as Netflix's — at once where it ends, slid there.)
                    let scale = OrbitStudioRow.rankedScale
                    let distance = (new..<old).reduce(CGFloat(0)) {
                        $0 + OrbitRankedTile.closedWidth($1 + 1, scale: scale) + row.gap
                    }
                    var still = Transaction()
                    still.disablesAnimations = true
                    withTransaction(still) {
                        slideX = -distance
                        scroll.scrollTo(id: new, anchor: .leading)
                    }
                    withAnimation(OrbitStudioLayout.horizontal) { slideX = 0 }
                } else {
                    withAnimation(OrbitStudioLayout.horizontal) { scroll.scrollTo(id: new, anchor: .leading) }
                }
            }
            // As on Home: once the focus has settled, the title brought back exactly to the margin
            // (Steven's video: the focused title stopped a poster right of it).
            if row.pinned, moving {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                    guard shown == new, focused == new else { return }
                    withAnimation(.easeOut(duration: 0.16)) { scroll.scrollTo(id: new, anchor: .leading) }
                }
            }
            let ahead = row.items[new..<min(row.items.count, new + 6)]
            OrbitMetaStore.shared.request(Array(ahead))
        }
    }

    private func restoreIfReturning() {
        guard let target = Self.reopen, target.row == row.id else { return }
        let appeared = ProcessInfo.processInfo.systemUptime
        restoringSince = appeared
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { restoringSince = 0; restoreLock = false }
        shown = target.index
        disappeared = false
        let back = (loops ? row.items.count * 3 : 0) + target.index
        if loops { place = back }
        DispatchQueue.main.async { strip.controller?.restore(index: back) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if Self.reopen?.index == target.index { Self.reopen = nil }
        }
    }

    @ViewBuilder
    private func details(_ item: MetaPreview?) -> some View {
        if let item {
            let info = OrbitInfo.make(item, meta: metaStore.meta(for: item))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Text(item.name)
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
            .id(item.id)
            // (As Home's new films: the synopsis fades in with the title in the frame; the old one
            // goes at once.)
            .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.05)), removal: .identity))
        }
    }
}

/// One tile of a native studio row, focused as its button is.
/// A studio row's tile in its UIKit strip (the meta observed here, per cell).
private struct OrbitStudioStripTile: View {
    let row: OrbitStudioRow
    let index: Int
    let trailers: OrbitNativeTrailerHost
    let focused: Bool
    let open: Bool
    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        if row.items.indices.contains(index) {
            let item = row.items[index]
            OrbitNativeStudioTile(row: row, item: item, index: index, meta: metaStore.meta(for: item),
                                  trailers: trailers, open: open, focusedFromCell: focused)
                .animation(.easeInOut(duration: open ? 0.4 : 0.28), value: open)
        }
    }
}

private struct OrbitNativeStudioTile: View {
    let row: OrbitStudioRow
    let item: MetaPreview
    let index: Int
    let meta: OrbitMeta?
    let trailers: OrbitNativeTrailerHost
    /// The new films' row: this title is the open one.
    var open = false
    /// In a UIKit strip the cell says whether it is focused.
    var focusedFromCell: Bool? = nil
    @Environment(\.isFocused) private var systemFocused
    /// Back from a title, a tile the system lands on a moment is not drawn focused (Steven: the
    /// focus seen going left, then coming back).
    @Environment(\.orbitFocusHidden) private var focusHidden
    private var isFocused: Bool { (focusedFromCell ?? systemFocused) && !focusHidden }

    var body: some View {
        let size = row.cardSize
        Group {
            switch row.kind {
            case .saga where index == 0:
                OrbitSagaPanel(saga: item, meta: meta,
                               size: CGSize(width: OrbitStudioRow.sagaPanelWidth, height: size.height), focused: isFocused)
            case .saga:
                OrbitStudioPoster(item: item, size: size, transparent: false, focused: isFocused)
            case .featured:
                OrbitNativeTrailerReader(host: trailers, key: "\(row.id)|\(item.type):\(item.id)") { url in
                    OrbitStudioCard(item: item, meta: meta, size: size, focused: isFocused,
                                    trailerURL: url,
                                    onTrailerFailure: { trailers.model.playbackFailed($0) },
                                    onTrailerEnded: { trailers.model.playbackFinished() })
                }
            case .posters(let transparent):
                OrbitStudioPoster(item: item, size: size, transparent: transparent, focused: isFocused)
            case .ranked where row.opensRanked:
                OrbitNativeRankedOpenTile(card: OrbitCard(id: item.id, preview: item, poster: item.poster, landscape: item.banner),
                                          meta: meta, rank: index + 1, trailers: trailers,
                                          trailerKey: "\(row.id)|\(item.type):\(item.id)", open: open,
                                          scale: OrbitStudioRow.rankedScale, showsBadge: false)
            case .ranked:
                // (Home's Top 10 tile: rested on, it widens into its frame with the trailer.)
                OrbitNativeTile(card: OrbitCard(id: item.id, preview: item, poster: item.poster, landscape: item.banner),
                                meta: meta, style: .ranked, rank: index + 1, trailers: trailers,
                                trailerKey: "\(row.id)|\(item.type):\(item.id)",
                                focusedFromCell: isFocused, openFromCell: open)
            case .classic:
                OrbitNativeClassicTile(card: OrbitCard.catalog(item), meta: meta, trailers: trailers,
                                       trailerKey: "\(row.id)|\(item.type):\(item.id)", open: open)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

// MARK: - Background, banner, header

/// A calm page: Orbit's black with the studio's colour rising from the top-left.
private struct OrbitStudioBackground: View {
    let brand: Color

    var body: some View {
        ZStack {
            OrbitHomeLayout.background
            // Steven (2026-10-29: "le même dégradé que l'accueil"): Home's shape — the studio's colour
            // from the top's middle across the whole screen, darker towards the bottom.
            RadialGradient(colors: [brand.opacity(0.42), brand.opacity(0.24), brand.opacity(0.08)],
                           center: UnitPoint(x: 0.5, y: 0.0), startRadius: 0, endRadius: 1900)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: UnitPoint(x: 0.5, y: 0.4), endPoint: .bottom)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let L = OrbitStudioLayout.self
        // Steven (2026-10-30, photo: "on ne peut pas garder cette ligne de brouillard dessous"): the
        // art reaches down to the first row's posters (under its heading), fading out just there —
        // no band of the page's colour between them.
        let size = CGSize(width: OrbitHomeLayout.screenWidth, height: L.heroHeight + 150)
        let banner: String? = item?.banner
        ZStack(alignment: .topLeading) {
            // Steven (device: a sharp line between the banner and the rows): the art itself fades
            // out at the bottom, into the page's own colour, whatever it is.
            ZStack(alignment: .topLeading) {
                // Steven (2026-10-30: "l'image du hero qui défile, je t'ai jamais demandé ça"): the art
                // still, as before (a trailer covers it when it plays).
                OrbitSwapImage(url: banner ?? meta?.backdrop, fallback: nil, size: size)
                    .frame(width: size.width, height: size.height)
                    .clipped()
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
                // Steven (2026-10-30: "un brouillard de la couleur du fond du studio sur la gauche et le
                // bas"): the art no longer turns see-through over the studio's colour — it is shaded
                // as Home's hero is, into the page's own dark, on the left and at the bottom.
                // (Steven, 2026-10-30: "pareil que le hero de l'accueil" — Home's shades exactly.)
                LinearGradient(stops: [
                    .init(color: OrbitHomeLayout.background.opacity(0.6), location: 0),
                    .init(color: OrbitHomeLayout.background.opacity(0.3), location: 0.38),
                    .init(color: .clear, location: 0.64),
                ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .clear, location: 0.16),
                    .init(color: .clear, location: 0.6),
                    .init(color: OrbitHomeLayout.background, location: 0.97),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)

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
                        .modifier(OrbitHeroTextShade())
                        .frame(height: 36)
                        .padding(.top, 24)
                    Text(info.synopsis)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineSpacing(4)
                        .lineLimit(2)
                        .frame(width: 880, alignment: .leading)
                        .modifier(OrbitHeroTextShade())
                        .padding(.top, 18)
                    HStack(spacing: 18) {
                        Text("Voir la fiche")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(focused ? Color.black : Color.white)
                            .padding(.horizontal, 40)
                            .frame(height: 70)
                            .background(Capsule().fill(focused ? Color.white : OrbitGlass.tint))
                            .overlay(Capsule().strokeBorder(OrbitGlass.rim.opacity(focused ? 0 : 1), lineWidth: 1.5))
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
                // Steven (device: "Nouveaux films" ran over the banner's text): higher up.
                // (Steven, 2026-10-30: "il flotte au milieu à gauche" — lower, still a row's gap
                // above the first row's heading.)
                // (2026-10-31: "tu ne l'as pas baissé" — 60 points was not enough to see: down to just
                // above the first row, about 45 points over its heading.)
                .offset(x: L.margin, y: 235)
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

/// A saga shelf's band across the page (Steven: Disney+'s brand shelves): a smooth gradient of the
/// saga's own two colours (its backdrop's left and right halves, sampled once), darker on the left
/// under the logo.
private struct OrbitSagaBand: View {
    let backdrop: String?
    let height: CGFloat

    @State private var colors: OrbitSagaPalette.Pair?

    var body: some View {
        let W = OrbitHomeLayout.screenWidth
        let pair = colors ?? OrbitSagaPalette.cached(backdrop)
        // Steven (2026-10-26: "une bande qui se fond vers le noir"): the saga's colours, strongest
        // under its logo on the left, melting into the page's dark to the right.
        ZStack {
            if let pair {
                // (Steven: the melt starts after the second poster, ~40 %, and ends at the edge.)
                LinearGradient(stops: [.init(color: pair.left, location: 0),
                                       .init(color: pair.right, location: 0.4),
                                       .init(color: pair.right.opacity(0.45), location: 0.72),
                                       .init(color: pair.right.opacity(0), location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .transition(.opacity)
            }
        }
        // (Steven: the top and bottom edges stay sharp; only the right end melts away.)
        .frame(width: W, height: height)
        .animation(.easeInOut(duration: 0.4), value: pair?.left)
        .task(id: backdrop) {
            if colors == nil { colors = await OrbitSagaPalette.colors(for: backdrop) }
        }
    }
}

/// Each saga's two colours, sampled from a small copy of its backdrop and kept for the session.
@MainActor
enum OrbitSagaPalette {
    struct Pair: Equatable {
        let left: Color
        let right: Color
    }

    private static var cache: [String: Pair] = [:]

    static func cached(_ url: String?) -> Pair? { url.flatMap { cache[$0] } }

    static func colors(for url: String?) async -> Pair? {
        guard let url else { return nil }
        if let known = cache[url] { return known }
        guard let small = URL(string: url.replacingOccurrences(of: "/w1280/", with: "/w300/")),
              let result = try? await URLSession.shared.data(from: small) else { return nil }
        let data = result.0
        let sampled = await Task.detached(priority: .utility) { () -> (Color?, Color?) in
            guard let image = UIImage(data: data)?.cgImage else { return (nil, nil) }
            let w = image.width, h = image.height
            let left = image.cropping(to: CGRect(x: 0, y: 0, width: w / 2, height: h))
            let right = image.cropping(to: CGRect(x: w / 2, y: 0, width: w - w / 2, height: h))
            return (left.flatMap { ArtworkColorStore.color(from: ArtworkColorStore.meanChroma(of: $0), use: .wash) },
                    right.flatMap { ArtworkColorStore.color(from: ArtworkColorStore.meanChroma(of: $0), use: .wash) })
        }.value
        guard let first = sampled.0 ?? sampled.1 else { return nil }
        let pair = Pair(left: first, right: sampled.1 ?? first)
        cache[url] = pair
        return pair
    }
}

/// A saga shelf's first place: the saga's logo (its first film's: "Toy Story" for Toy Story 1, 2,
/// 3…), "La saga · 4 films" and TOUT VOIR (it opens the first film).
private struct OrbitSagaPanel: View {
    let saga: MetaPreview
    let meta: OrbitMeta?
    let size: CGSize
    let focused: Bool

    var body: some View {
        let info = OrbitInfo.make(saga, meta: meta)
        let count: String? = saga.releaseInfo
        // Steven: the logo, the count and TOUT VOIR on one line, the page's left margin.
        VStack(alignment: .leading, spacing: 22) {
            OrbitTitleMark(name: saga.name, logo: info.logo, maxSize: CGSize(width: size.width * 0.8, height: 140),
                           textSize: 44, fallbackLogo: info.logoFallback)
                .frame(width: size.width * 0.8, height: 140, alignment: .bottomLeading)
                .clipped()
            Text(String(localized: "La saga · \(count ?? "") films"))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .frame(height: 32)
            Text(String(localized: "TOUT VOIR"))
                .font(.system(size: 22, weight: .bold))
                .kerning(2)
                .foregroundStyle(focused ? Color.black : Color.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 8).fill(focused ? Color.white : OrbitGlass.tint))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(OrbitGlass.rim.opacity(focused ? 0 : 1), lineWidth: 1.5))
                .scaleEffect(focused ? 1.06 : 1, anchor: .leading)
                .animation(.easeOut(duration: 0.18), value: focused)
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
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
                        view
                            .shadow(color: .white.opacity(focused ? 0.55 : 0), radius: focused ? 24 : 0)
                            .shadow(color: .black.opacity(focused ? 0.6 : 0.3), radius: focused ? 20 : 8, y: 8)
                            .brightness(focused ? 0.06 : 0)
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
    /// Short films found in his catalogues (Steven: DC's "Nouveaux films" was full of Krypto
    /// shorts), and the films already checked.
    private var shorts = Set<String>()
    private var runtimeChecked = Set<String>()
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
            // The logo first, on its own (the opening waits for it; the rows take longer).
            if route.logo == nil, self?.logo == nil {
                let firstId = ids.split(whereSeparator: { $0 == "|" || $0 == "," }).first.map(String.init) ?? ids
                let entity: EntityResponse? = await Self.decode(
                    "https://api.themoviedb.org/3/\(route.isNetwork ? "network" : "company")/\(firstId)?api_key=\(key)")
                if let path = entity?.logo_path, self?.logo == nil {
                    self?.logo = "https://image.tmdb.org/t/p/w500\(OrbitMetaStore.decodable(path))"
                }
            }
            let found = await Self.load(ids: ids, network: route.isNetwork, apiKey: key, language: language)
            guard let self else { return }
            if self.logo == nil { self.logo = route.logo ?? found.logo }
            self.statsLine = Self.statsLine(network: route.isNetwork, count: found.count, since: found.since)
            self.sagaFilms = found.sagaFilms
            self.tmdbRows = found.rows.map { raw in
                let kind: OrbitStudioRowKind = raw.id == "best" ? .featured : raw.id.hasPrefix("saga-") ? .saga
                    : raw.id == "top10" ? .ranked : .posters(transparent: false)
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
            // His Top 10 add-on is replaced by Orbit's own (TMDB, `ranked`).
            if heading.contains("top 10") || heading.contains("top10") { return nil }
            return OrbitStudioRow(id: "folder-\(row.id)", title: row.heading, items: items,
                                  kind: .posters(transparent: false))
        }
        // The first row of new films drawn as Home's first row (Steven).
        if let i = folderRows.firstIndex(where: {
            $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains("nouveau")
        }) {
            let r = folderRows[i]
            folderRows[i] = OrbitStudioRow(id: r.id, title: r.title, items: r.items, kind: .classic)
        }
        checkRuntimes()
        publish()
    }

    /// Asks TMDB the length of the films in his catalogues (the first forty of each row) and
    /// leaves out those under an hour; a film whose length is unknown stays.
    private func checkRuntimes() {
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        guard !key.isEmpty else { return }
        let candidates = folderRows.flatMap { $0.items.prefix(40) }
            .filter { $0.type == "movie" && !runtimeChecked.contains($0.id) }
        guard !candidates.isEmpty else { return }
        candidates.forEach { runtimeChecked.insert($0.id) }
        let ids = candidates.map(\.id)
        Task { [weak self] in
            let found = await withTaskGroup(of: String?.self) { group in
                for id in ids {
                    group.addTask {
                        let tmdb = id.hasPrefix("tmdb:") ? String(id.dropFirst(5)) : id
                        guard tmdb.hasPrefix("tt") || Int(tmdb) != nil else { return nil }
                        let movie: RuntimeResponse? = await Self.decode("https://api.themoviedb.org/3/movie/\(tmdb)?api_key=\(key)")
                        guard let minutes = movie?.runtime, minutes > 0, minutes < 60 else { return nil }
                        return id
                    }
                }
                var out: [String] = []
                for await id in group { if let id { out.append(id) } }
                return out
            }
            guard let self, !found.isEmpty else { return }
            self.shorts.formUnion(found)
            self.publish()
        }
    }

    nonisolated private struct RuntimeResponse: Decodable {
        let runtime: Int?
    }

    /// The order: his Nouveautés and Top 10, then "Les incontournables", "Les sagas", and the rest
    /// of the page's rows. Where the page has its own rows, his other catalogs are not drawn (they
    /// repeat them); without them (TMDB unknown), every catalog shows.
    private func publish() {
        let own = !tmdbRows.isEmpty
        let kept = own ? folderRows.filter { OrbitCatalogFilter.isKept($0.title) } : folderRows
        // No short films in his catalogues.
        let mine = kept.compactMap { row -> OrbitStudioRow? in
            let items = row.items.filter { !shorts.contains($0.id) }
            guard !items.isEmpty else { return nil }
            return items.count == row.items.count ? row
                : OrbitStudioRow(id: row.id, title: row.title, items: items, kind: row.kind)
        }
        // "Les plus populaires" without the films of his Top 10 (it was the same row twice).
        let topNames = Set(tmdbRows.filter { $0.kind == .ranked }.flatMap { $0.items.map { $0.name.lowercased() } })
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
        // Orbit's Top 10: the most popular of the moment among what is out (an hour or more).
        async let top10 = discover(base + "&sort_by=popularity.desc&\(dateField).lte=\(today)&vote_count.gte=20"
                                   + (network ? "" : "&with_runtime.gte=60"), tv: network)
        async let upcoming = discover(base + "&sort_by=\(dateField).asc&\(dateField).gte=\(today)&\(dateField).lte=\(soon)", tv: network)

        let (entityValue, oldestValue, bestValue, popularValue, popular2Value, upcomingValue, top10Value) =
            await (entity, oldest, best, popular, popular2, upcoming, top10)

        var rows: [(id: String, title: String, items: [MetaPreview])] = []
        /// Steven: the sagas spread through the page (one after each row), not one after another.
        var sagaRows: [(id: String, title: String, items: [MetaPreview])] = []
        var sagaFilms: [String: MetaPreview] = [:]
        if top10Value.items.count >= 10 {
            rows.append(("top10", network ? String(localized: "Top 10 des séries") : String(localized: "Top 10 des films"),
                         Array(top10Value.items.prefix(10))))
        }
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
                                                   poster: saga.poster_path.map { "https://image.tmdb.org/t/p/w780\($0)" } ?? film.poster,
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
            // Each saga's released films, oldest first (Steven, 2026-10-25: a shelf per saga, Disney+'s
            // brand shelf — the saga's logo and TOUT VOIR on the left, its films' posters on the right).
            let parts = await withTaskGroup(of: (Int, [MetaPreview]).self) { group in
                for (index, card) in unique.enumerated() {
                    group.addTask {
                        let sagaId = (card.rawPosterUrl ?? "").replacingOccurrences(of: "saga:", with: "")
                        guard let collection: CollectionResponse = await decode("https://api.themoviedb.org/3/collection/\(sagaId)?api_key=\(apiKey)&language=\(lang)") else {
                            return (index, [])
                        }
                        let released = (collection.parts ?? [])
                            .filter { !($0.release_date ?? "").isEmpty && ($0.release_date ?? "") <= today && $0.poster_path != nil }
                            .sorted { ($0.release_date ?? "") < ($1.release_date ?? "") }
                        return (index, released.compactMap { part -> MetaPreview? in
                        guard let title = part.title, !title.isEmpty else { return nil }
                        let date = part.release_date
                        return MetaPreview(id: "tmdb:\(part.id)", type: "movie", name: title,
                                                   poster: part.poster_path.map { "https://image.tmdb.org/t/p/w780\($0)" },
                                                   banner: part.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" },
                                                   logo: nil, posterShape: .poster,
                                                   description: part.overview, releaseInfo: date.map { String($0.prefix(4)) },
                                                   rawReleaseDate: date, popularity: nil, voteCount: nil,
                                                   imdbRating: part.vote_average.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil },
                                                   genres: [], rawPosterUrl: nil, landscapePoster: nil,
                                                   rawLandscapePosterUrl: nil, customPosterApplied: false)
                        })
                    }
                }
                var out: [Int: [MetaPreview]] = [:]
                for await (index, films) in group { out[index] = films }
                return out
            }
            var shelves = 0
            for (index, card) in unique.enumerated() where shelves < 6 {
                let films = parts[index] ?? []
                guard let first = films.first, films.count >= 2 else { continue }
                shelves += 1
                // The shelf's first place: the saga itself (the first film's id, for its logo and
                // TOUT VOIR, which opens it; the saga's name, its backdrop, its number of films).
                let panel = MetaPreview(id: first.id, type: "movie", name: card.name, poster: card.poster,
                                        banner: card.banner, logo: nil, posterShape: .landscape,
                                        description: first.description_, releaseInfo: "\(films.count)",
                                        rawReleaseDate: nil, popularity: nil, voteCount: nil, imdbRating: nil,
                                        genres: [], rawPosterUrl: card.rawPosterUrl, landscapePoster: nil,
                                        rawLandscapePosterUrl: nil, customPosterApplied: false)
                sagaFilms[first.id] = first
                sagaRows.append(("saga-\(card.rawPosterUrl ?? card.name)", card.name, [panel] + films))
            }
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
            // A plain string: an interpolated Int is formatted with the French thousands space ("2 010").
            let label = decade >= 2000 ? String(localized: "Les années \(String(decade))")
                : String(localized: "Les années \(String(decade % 100))")
            rows.append(("decade-\(decade)", label, items))
        }

        var mixed: [(id: String, title: String, items: [MetaPreview])] = []
        for row in rows {
            mixed.append(row)
            if !sagaRows.isEmpty { mixed.append(sagaRows.removeFirst()) }
        }
        rows = mixed + sagaRows

        let since = oldestValue.items.first?.rawReleaseDate.map { String($0.prefix(4)) }
        return (entityValue?.logo_path.map { "https://image.tmdb.org/t/p/w500\(OrbitMetaStore.decodable($0))" },
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
                               poster: "https://image.tmdb.org/t/p/w780\(poster)",
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


/// A studio's logo as its opening draws it.
struct OrbitStudioIntroLogo: View {
    let name: String
    let logoUrl: String?
    let corner: Bool

    static func isNatGeo(_ name: String) -> Bool {
        let n = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return n.contains("national geographic") || n.contains("nat geo")
    }

    private var isNatGeo: Bool { Self.isNatGeo(name) }

    var body: some View {
        if isNatGeo {
            // (Steven: its name, black, sank into the dark page — his own file, white name and
            // yellow frame.)
            Image("NatGeoLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: OrbitStudioIntro.cornerBox.width, maxHeight: OrbitStudioIntro.cornerBox.height * 0.8)
                .frame(width: OrbitStudioIntro.cornerBox.width, height: OrbitStudioIntro.cornerBox.height,
                       alignment: corner ? .topTrailing : .center)
        } else if let logoUrl, !logoUrl.isEmpty {
            OrbitBalancedLogo(url: logoUrl, area: 13_000, maxSize: OrbitStudioIntro.cornerBox,
                              whiten: OrbitBalancedLogo.isGrey(name), alignment: corner ? .topTrailing : .center)
        } else {
            Text(name)
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}


/// Its content drifting very slowly — a gentle push in and across, there and back — animated by
/// Core Animation (no work for the app on each frame). Stops (eased back to rest) when not
/// `active`; starts again from rest for a new `key`.
/// Steven (2026-10-30: "ça bouge pas", no trailer there): the animation was put on before the view was
/// on screen, and the system drops a view's animations when it is put on (or taken off) the screen —
/// the view now starts it itself once it is on screen, and again whenever it was lost.
struct OrbitSlowDrift<Content: View>: UIViewRepresentable {
    let active: Bool
    let key: String
    /// Where it goes from and to (a push in and across by default), and in how long each way.
    var from: CATransform3D = CATransform3DIdentity
    var to: CATransform3D = CATransform3DTranslate(CATransform3DMakeScale(1.12, 1.12, 1), -40, -10, 0)
    var duration: Double = 16
    var timing: CAMediaTimingFunctionName = .linear
    @ViewBuilder let content: () -> Content

    final class DriftView: UIView {
        let host: UIHostingController<AnyView>
        var active = false
        var key = ""
        var from = CATransform3DIdentity
        var to = CATransform3DIdentity
        var duration: Double = 16
        var timing: CAMediaTimingFunctionName = .linear
        private var driftKey = ""

        init(host: UIHostingController<AnyView>) {
            self.host = host
            super.init(frame: .zero)
            backgroundColor = .clear
            isUserInteractionEnabled = false
            clipsToBounds = true
            host.view.backgroundColor = .clear
            host.view.frame = bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(host.view)
            NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                                   name: UIApplication.didBecomeActiveNotification, object: nil)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            refresh()
        }

        @objc func refresh() {
            let layer = host.view.layer
            guard window != nil else { return }
            if active {
                if layer.animation(forKey: "drift") == nil || driftKey != key {
                    layer.removeAnimation(forKey: "settle")
                    layer.removeAnimation(forKey: "drift")
                    let drift = CABasicAnimation(keyPath: "transform")
                    drift.fromValue = from
                    drift.toValue = to
                    drift.duration = duration
                    drift.autoreverses = true
                    drift.repeatCount = .infinity
                    drift.timingFunction = CAMediaTimingFunction(name: timing)
                    // Its resting place is where it starts (no jump when it settles or starts).
                    layer.transform = from
                    drift.isRemovedOnCompletion = false
                    layer.add(drift, forKey: "drift")
                    driftKey = key
                }
            } else if layer.animation(forKey: "drift") != nil {
                // Back to rest, gently, from wherever it is.
                let now = layer.presentation()?.transform ?? CATransform3DIdentity
                layer.removeAnimation(forKey: "drift")
                let settle = CABasicAnimation(keyPath: "transform")
                settle.fromValue = now
                settle.toValue = from
                settle.duration = 0.6
                settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(settle, forKey: "settle")
                driftKey = ""
            }
        }
    }

    func makeUIView(context: Context) -> DriftView {
        let host = UIHostingController(rootView: AnyView(content()))
        host.safeAreaRegions = []
        return DriftView(host: host)
    }

    func updateUIView(_ view: DriftView, context: Context) {
        view.host.rootView = AnyView(content())
        view.active = active
        view.key = key
        view.from = from
        view.to = to
        view.duration = duration
        view.timing = timing
        view.refresh()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: DriftView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}
