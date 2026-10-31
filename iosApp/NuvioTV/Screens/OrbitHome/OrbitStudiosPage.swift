import Combine
import SharedCore
import SwiftUI
import UIKit

// Orbit Studios (Steven, 2026-10-24, third version): the Studios page in Orbit's own language —
//  - the page on the focused studio's colour; its backdrop whole in a large frame top right
//    (rounded, a shadow, as on the platforms); on the left its logo, "Studio · 432 films" and its
//    latest films;
//  - the studios as landscape tiles, each its logo in white on its own colour;
//  - one row of the studio's films in portrait posters: "Les incontournables" (Steven, 2026-10-25:
//    on every studio; "Les plus populaires" when TMDB has too few).
// Down from the bar lands on the first studio (far left); entering a row lands where the system puts it;
// up from the films, back on the studio whose films they are; back from a studio, the focus is
// the studio it was opened from.

struct OrbitStudiosPage: View {
    let collection: NuvioCollection

    @FocusState private var focused: String?
    /// The tile drawn as focused: `focused`, followed in an explicit animation.
    @State private var lit: String?
    @Environment(\.displayScale) private var displayScale
    /// The studio the page shows (backdrop, logo, films): the focused one, kept when the focus
    /// goes down to the films.
    @State private var shownId: String?
    /// The studio whose colour the page is on: Home's timing (it follows once the remote rests,
    /// `OrbitRowsBackdrop.wait`, on Home's fade).
    @State private var groundId: String?
    @ObservedObject private var films = OrbitStudioFilmsModel.shared
    @ObservedObject private var banners = OrbitStudioBanners.shared
    /// Each studio's colour, sampled from its backdrop (a known brand colour first).
    @State private var tints: [String: Color] = [:]
    /// The way the focus went along the tiles (right: true): the studio's name slides that way.
    @State private var forward = true
    /// The tile a studio was opened from, while the page comes back.
    @State private var restoreTarget: String?
    @State private var tilesStrip = OrbitStripRef()
    /// The strip holds the focus (its tiles' focus, as `focused` was).
    @State private var tilesHaveFocus = false

    @MainActor private static var lastFocused: String?
    @MainActor private static var leftWithFocus = false
    @MainActor private static var lostTilesAt: TimeInterval = 0

    static let tileSize = CGSize(width: 236, height: 133)
    static let tileSpacing: CGFloat = 36  // Home's 16:9 gap (Steven, 2026-10-29)
    static let heroTop: CGFloat = 112
    /// (Steven, 2026-10-30: larger, now the image spans the screen — was 460 × 130.)
    static let logoSize = CGSize(width: 640, height: 180)
    /// The framed backdrop, top right.
    /// Steven (2026-10-26): the large image takes the top of the screen, the studios under it at
    /// the bottom (their size unchanged).
    static let frameSize = CGSize(width: 1760, height: 690)

    private var folders: [CollectionFolder] {
        var seen = Set<String>()
        return collection.folders.filter { seen.insert($0.id).inserted }
    }

    private var shownFolder: CollectionFolder? {
        folders.first { $0.id == shownId } ?? folders.first
    }

    private func tint(_ folder: CollectionFolder) -> Color {
        OrbitPlatformBrand.known(title: folder.title) ?? tints[folder.id] ?? OrbitPlatformBrand.color(title: folder.title)
    }

    @Environment(\.orbitPushStudio) private var pushStudio

    var body: some View {
        let L = OrbitHomeLayout.self
        let folders = folders
        let shown = shownFolder
        let selectedId = shownId ?? folders.first?.id
        ZStack(alignment: .topLeading) {
            // Steven (2026-10-24): the page on the studio's colour; its backdrop in a large frame
            // top right (whole, no blur, a shadow as on the platforms) — the image no longer runs
            // under the tiles and the posters.
            let ground = (folders.first { $0.id == groundId } ?? shown).map(tint) ?? OrbitPlatformBrand.color(title: "")
            ZStack {
                OrbitHomeLayout.background
                // Steven (2026-10-29: "le même dégradé que l'accueil"): the studio's colour from the
                // top's middle across the whole screen, darker towards the bottom.
                RadialGradient(colors: [ground.opacity(0.6), ground.opacity(0.34), ground.opacity(0.12)],
                               center: UnitPoint(x: 0.5, y: 0.0), startRadius: 0, endRadius: 1900)
                // (Steven, 2026-10-30, DC Studios: a dark band too strong at the bottom — lighter, lower.)
                LinearGradient(colors: [.clear, .black.opacity(0.28 * OrbitHomeLayout.footShade / 0.55)], startPoint: UnitPoint(x: 0.5, y: 0.6), endPoint: .bottom)
                // Steven (2026-10-30: "en bas ce soit la couleur de l'affiche et pas d'un studio, avec
                // un dégradé flou"; then "le flou d'en bas ne défile pas avec l'image", "pas naturel"):
                // the banner and its blurred continuation are one picture now — the same image, at the
                // same place, sharp above and blurred below, gliding together.
                OrbitStudiosBackdrop(url: bannerURL(shown), lift: OrbitStudioFrame.lift(title: shown?.title ?? ""))
                // (Darker towards the bottom, for the tiles.)
                LinearGradient(colors: [.clear, .black.opacity(0.32 * OrbitHomeLayout.footShade / 0.55)],
                               startPoint: UnitPoint(x: 0.5, y: 0.6), endPoint: .bottom)
                OrbitGrain()
                // (The trial's even ground, as Home's: see `OrbitHomeLayout.footShade`.)
                Color.white.opacity(OrbitHomeLayout.floorLift)
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: OrbitRowsBackdrop.fade), value: groundId)

            // Steven (2026-10-24): a panoramic frame across the page, centred; the studio's name
            // on it, bottom left (a soft shade in that corner only).
            OrbitStudioFrame(url: bannerURL(shown), forward: forward,
                             lift: OrbitStudioFrame.lift(title: shown?.title ?? ""),
                             shade: OrbitStudioFrame.shade(title: shown?.title ?? ""))
                .overlay(alignment: .bottomLeading) {
                    hero(shown)
                        .padding(.leading, L.margin + 36)
                        .padding(.bottom, 26)
                }

            // Everything on one screen (no page scroll: it slid the studio's name under the bar).
            VStack(alignment: .leading, spacing: 0) {
                    // The frame's place (it is drawn above).
                    Color.clear
                        .frame(width: 1, height: Self.heroTop + Self.frameSize.height)
                        .allowsHitTesting(false)

                    // Steven (device: from DC to Lucasfilm and on, the row jumped — the system's own
                    // scroll): the row glides on one curve, the focused studio kept at the centre
                    // once past the first ones, at every move alike.
                    // Steven (2026-10-29: "applique-le de PARTOUT"): a UIKit strip the focus engine
                    // scrolls, as Apple's TV app.
                    OrbitStripView(count: folders.count, identity: folders.map(\.id).joined(separator: ","),
                                   spacing: Self.tileSpacing, height: Self.tileSize.height, margin: L.margin,
                                   alignment: .center, width: { _ in Self.tileSize.width },
                                   // (Its tiles redrawn only when what they show changes — every press
                                   // redrew them all, the page being drawn again for it.)
                                   redrawKey: AnyHashable([AnyHashable(tilesHaveFocus ? "" : (selectedId ?? "")),
                                                           AnyHashable(tints.count)]),
                                   ref: tilesStrip,
                                   tile: { i, lit in
                                       let folder = folders[i]
                                       return AnyView(OrbitStudioTile(folder: folder, focused: lit,
                                                                      selected: !tilesHaveFocus && folder.id == selectedId,
                                                                      tint: tint(folder)))
                                   },
                                   onFocus: { i in tileFocus(i.map { folders[$0].id }) },
                                   onSelect: { i in
                                       let folder = folders[i]
                                       let route = OrbitStudioRoute.folder(collectionId: collection.id, folder: folder)
                                       if let pushStudio {
                                           let look = OrbitPlatformLook(title: folder.title, logoUrl: route.logo,
                                                                        brand: tint(folder), studio: true)
                                           OrbitPlatformCurtain.shared.drop(look: look) { pushStudio(route) }
                                       }
                                   })
                    .frame(height: Self.tileSize.height)
                    .padding(.top, 40)
                    .focusSection()

                    // (Steven, 2026-10-26: the row of the studio's films is gone — the studios
                    // alone.)
            }
            .frame(width: L.screenWidth, alignment: .leading)
        }
        .frame(width: L.screenWidth, height: L.screenHeight, alignment: .topLeading)
        .ignoresSafeArea()
        // Menu goes to the Orbit bar (not the hidden system tab bar).
        .onExitCommand { NotificationCenter.default.post(name: .orbitBarFocusRequest, object: nil) }
        .animation(.easeInOut(duration: 0.3), value: shownId)
        .onChange(of: shownId, initial: true) { _, id in
            guard groundId != nil else { groundId = id; return }
            // (The row's rest is already waited for before the studio is shown.)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if shownId == id { groundId = id }
            }
        }
        .onChange(of: focused) { old, id in
            guard let id else {
                if old != nil { Self.lostTilesAt = ProcessInfo.processInfo.systemUptime }
                withAnimation(.easeInOut(duration: 0.3)) { lit = nil }
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            // Up from the films: back on the studio whose films they are.
            let fromFilms = OrbitStudioFilmsRow.hasFocus || now - OrbitStudioFilmsRow.lostAt < 0.6
            if old == nil, fromFilms, let selected = shownId ?? folders.first?.id, id != selected {
                focused = selected
                return
            }
            // Steven (2026-10-28): Down from the bar lands where the system takes it (no jump to the first).
            withAnimation(.easeOut(duration: 0.2)) { lit = id }
            Self.lastFocused = id
            if let from = folders.firstIndex(where: { $0.id == shownId }),
               let to = folders.firstIndex(where: { $0.id == id }), from != to {
                forward = to > from
            }
            shownId = id
            if let folder = folders.first(where: { $0.id == id }) {
                films.focus(title: folder.title)
            }
        }
        // Back from a studio, the system lands on its tile straight away (Steven, simulator: it
        // went to another studio first, then came back).
        .defaultFocus($focused, restoreTarget, priority: .userInitiated)
        .onAppear {
            if Self.leftWithFocus, let last = Self.lastFocused, folders.contains(where: { $0.id == last }) {
                Self.leftWithFocus = false
                shownId = last
                restoreTarget = last
                restore(last)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { restoreTarget = nil }
            } else {
                shownId = folders.first?.id
            }
            if let folder = shownFolder { films.focus(title: folder.title) }
            // (After the tabs' cross-fade, as the banners: not decoded while it plays.)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { prefetchBackdrops() }
        }
        // (Once the chosen films are known, and whenever they change.)
        .task(id: folders.map { bannerURL($0) ?? "-" }.joined(separator: "|")) { prefetchBanners() }
        .onDisappear {
            let now = ProcessInfo.processInfo.systemUptime
            Self.leftWithFocus = tilesHaveFocus || focused != nil || now - Self.lostTilesAt < 1.0
        }
    }

    /// The banner: the studio's chosen film's backdrop (TMDB), else its own configured image.
    private func bannerURL(_ folder: CollectionFolder?) -> String? {
        folder.flatMap { banners.url(forTitle: $0.title) } ?? Self.backdropURL(folder)
    }

    /// The banners' images (the studios' chosen films), fetched ahead at the banner's size and
    /// blurred ahead, so a change of studio shows at once.
    private func prefetchBanners() {
        let request = ArtworkDecodeRequest(size: .points(width: OrbitHomeLayout.screenWidth,
                                                         height: OrbitHomeLayout.screenWidth * 9 / 16),
                                           fill: true, scale: displayScale)
        let raws = folders.compactMap { bannerURL($0) }
        let lifts = folders.compactMap { folder in bannerURL(folder).map { ($0, OrbitStudioFrame.lift(title: folder.title)) } }
        let scale = displayScale
        Task(priority: .utility) {
            // Steven (2026-10-31, slow motion of the tabs: the cross-fade to Studios jerky all along):
            // a dozen large pictures were decoded and blurred at the very moment the page came in.
            // They now wait for the cross-fade to be over (the banner shown loads its own at once).
            try? await Task.sleep(for: .seconds(1.2))
            for raw in raws {
                guard let url = URL(string: raw) else { continue }
                // (Steven, 2026-10-30: still slow, two fades — the banner draws TMDB's original
                // image, which was not fetched ahead: the smaller copy showed, then the original
                // came over it from the network. The original itself fetched ahead now.)
                let best = ArtworkURLUpgrade.upgraded(url, role: .backdrop) ?? url
                if ArtworkStore.cached(best, decode: request) == nil {
                    _ = try? await ArtworkStore.fetch(best, decode: request)
                }
                await OrbitPreBlurred.prepare(raw, radius: 16)
            }
            // Each studio's banner pictures made ahead too (a change only fades two pictures).
            for (raw, lift) in lifts {
                await OrbitStudioBake.make(raw, lift: lift, scale: scale)
                await OrbitThickBlur.prepare(raw)
            }
        }
    }

    /// Every studio's backdrop fetched as the page opens (a change is instant), then its colour.
    private func prefetchBackdrops() {
        banners.load(titles: folders.map(\.title))
        let request = ArtworkDecodeRequest(size: .points(width: OrbitHomeLayout.screenWidth,
                                                         height: OrbitHomeLayout.screenWidth * 9 / 16),
                                           fill: true, scale: displayScale)
        let jobs: [(id: String, raw: String, url: URL)] = folders.compactMap { folder in
            guard let raw = Self.backdropURL(folder), let url = URL(string: raw) else { return nil }
            return (folder.id, raw, url)
        }
        Task(priority: .utility) {
            for job in jobs {
                if ArtworkStore.cached(job.url, decode: request) == nil {
                    _ = try? await ArtworkStore.fetch(job.url, decode: request)
                }
                await MainActor.run { sampleTint(id: job.id, raw: job.raw) }
            }
        }
    }

    private func sampleTint(id: String, raw: String) {
        guard tints[id] == nil else { return }
        if let cached = ArtworkColorStore.shared.cachedColor(for: [raw], use: .wash) {
            tints[id] = cached
            return
        }
        ArtworkColorStore.shared.color(for: [raw], use: .wash) { color in
            if let color { tints[id] = color }
        }
    }

    /// Back from a studio: the tile it was opened from (asked a few times: the engine's own
    /// restoration lands late), until the viewer presses anything.
    private func restore(_ id: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        DispatchQueue.main.async { tilesStrip.controller?.restore(index: index) }
    }

    /// The focus moved in the studios' strip (as `focused` used to change).
    private func tileFocus(_ id: String?) {
        guard let id else {
            tilesHaveFocus = false
            Self.lostTilesAt = ProcessInfo.processInfo.systemUptime
            withAnimation(.easeInOut(duration: 0.3)) { lit = nil }
            return
        }
        tilesHaveFocus = true
        withAnimation(.easeOut(duration: 0.2)) { lit = id }
        Self.lastFocused = id
        // Steven (2026-10-30: the studios' row not smooth when pressed quickly, fine slowly): each
        // press switched the page to the studio at once — its films' row swapped and the whole page
        // animated for it — while the row was still sliding. That waits for the row to rest (as on
        // Plateformes and Home).
        shownWork?.cancel()
        let work = DispatchWorkItem {
            guard Self.lastFocused == id, tilesHaveFocus else { return }
            if let from = folders.firstIndex(where: { $0.id == shownId }),
               let to = folders.firstIndex(where: { $0.id == id }), from != to {
                forward = to > from
            }
            shownId = id
            if let folder = folders.first(where: { $0.id == id }) {
                films.focus(title: folder.title)
            }
        }
        shownWork = work
        // (Steven, 2026-10-31, video: the picture changed ~0.42 s after the press, then its 0.2 s
        // fade — the wait was most of it. The pictures and blurs are ready ahead now: a shorter wait.)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// The studio's page switch, once the row rests.
    @State private var shownWork: DispatchWorkItem?

    static func backdropURL(_ folder: CollectionFolder?) -> String? {
        let url = folder?.heroBackdropUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (url?.isEmpty ?? true) ? nil : url
    }

    static func logoURL(_ folder: CollectionFolder?) -> String? {
        if let own = OrbitStudioLogos.url(forTitle: folder?.title) { return own }
        let url = folder?.titleLogoUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (url?.isEmpty ?? true) ? nil : url
    }

    /// The hero: the studio's logo, then its figures.
    /// Steven (2026-10-24): the name follows the focus — right on the tiles, it leaves to the right
    /// and the next one comes in from the left.
    /// Steven (2026-10-26): the logo in a plain fade, nothing else (no glide).
    /// (Steven, 2026-10-31, slow motion: the old studio's logo and the new one were seen over each
    /// other a moment, the new picture already there — the old one now goes at once, the new one
    /// comes as it has gone, with the picture.)
    /// (Steven, 2026-10-31: then "le logo se charge plus vite que l'image de fond" — the picture now
    /// starts its fade a few frames late, once drawn: the logos follow its time — the old one goes as
    /// the new picture starts, the new one comes as it is half in.)
    private var slide: AnyTransition {
        .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.18)),
                    removal: .opacity.animation(.easeIn(duration: 0.1).delay(0.07)))
    }

    /// Fixed places (Steven: from Disney to Pixar the logo moved, the block was centred and its
    /// height changed): the logos sit on one line, the figures and the latest films under it.
    private func hero(_ folder: CollectionFolder?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                if let url = Self.logoURL(folder) {
                    OrbitBalancedLogo(url: url, area: 72_000, maxSize: Self.logoSize,
                                      whiten: OrbitBalancedLogo.isGrey(folder?.title ?? ""), alignment: .bottomLeading)
                        // (Steven, 2026-10-31: the Disney signature sat a little high on the Studios
                        // page — its "y" hangs below its line, so its line stood above the others'.
                        // Lowered by that hang.)
                        .offset(y: OrbitStudioLogos.isDisney(folder?.title ?? "") ? 24 : 0)
                        .shadow(color: .black.opacity(0.45), radius: 18, y: 4)
                        .id(url)
                        .transition(slide)
                } else if let title = folder?.title {
                    Text(title)
                        .font(.system(size: 64, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .shadow(color: .black.opacity(0.45), radius: 18, y: 4)
                        .id(title)
                        .transition(slide)
                }
            }
            .frame(width: Self.logoSize.width, height: Self.logoSize.height, alignment: .bottomLeading)

        }
        .allowsHitTesting(false)
    }
}

/// The studio's backdrop in a frame: whole, rounded, a soft shadow. A new studio's image comes in
/// over the old one with a short glide the way the focus went and a slight zoom settling (the
/// logo on the right glides the same way).
private struct OrbitStudioFrame: View {
    let url: String?
    let forward: Bool
    /// How far the image is lowered in the frame from its centre (0…1 of what the frame cuts):
    /// the panorama crops the top and bottom of a 16:9 image, a head may be cut.
    var lift: CGFloat = 0
    /// The shade in the bottom left corner, under the studio's name.
    var shade: Double = 0.55

    /// Steven (2026-10-31, Pixar's sky: "une grosse ombre foncée sur la gauche"): on a light, plain
    /// picture the corner's shade showed as a dark patch — lighter there (the name keeps its shadow).
    static func shade(title raw: String) -> Double {
        let t = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if t.contains("pixar") { return 0.18 }
        return 0.55
    }

    /// Steven: Darth Vader's head was cut (Lucasfilm).
    static func lift(title raw: String) -> CGFloat {
        let t = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if t.contains("lucasfilm") || t.contains("star wars") { return 0.75 }
        // (Steven, 2026-10-31: Iron Man's hair cut at the top of Marvel's new picture.)
        if t.contains("marvel") { return 0.35 }
        return 0
    }

    @State private var zoom: CGFloat = 1
    @State private var shift: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Steven (2026-10-30: "un bandeau large"): the frame becomes a banner across the whole width,
    /// from the screen's top down to where the frame ended; no corners, its bottom melting into the
    /// studio's colour, a light shade under the bar.
    static var bannerSize: CGSize {
        CGSize(width: OrbitHomeLayout.screenWidth, height: OrbitStudiosPage.heroTop + OrbitStudiosPage.frameSize.height)
    }

    var body: some View {
        let size = Self.bannerSize
        ZStack {
            // (The image itself is the page's ground now — `OrbitStudiosBackdrop`, sharp and blurred
            // as one; the frame keeps its shades.)
            Color.clear
            // The name reads at the bottom left; the rest of the image stays clean.
            RadialGradient(colors: [.black.opacity(shade), .black.opacity(shade * 0.36), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 900)
                .animation(.easeInOut(duration: 0.3), value: shade)
            // Under the bar: a light shade, as on Home's hero.
            LinearGradient(stops: [.init(color: .black.opacity(0.4), location: 0),
                                   .init(color: .clear, location: 0.2)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        // Its bottom melts into the page's colour (the tiles come just under it).
        // (Steven, 2026-10-30: the blur starting lower.)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                     .init(color: .black, location: 0.92),
                                     .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        // (Steven, 2026-10-31: drawn once into one plain picture with its mask — the mask was worked
        // out again at every frame of a banner's change.)
        .drawingGroup()
        // (Steven, 2026-10-26: the image in a plain fade — no glide, no zoom.)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A logo drawn at a balanced size: every logo covers about the same area (a tall, narrow one —
/// Ghibli, DreamWorks — no longer ends up tiny next to a wide one — Illumination), within a
/// maximum box. `whiten`: a grey logo drawn white (its shape kept).
struct OrbitBalancedLogo: View {
    let url: String
    let area: CGFloat
    let maxSize: CGSize
    var whiten = false
    var alignment: Alignment = .center
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    /// Steven's grey logos (unreadable on a colour).
    static func isGrey(_ raw: String) -> Bool {
        let t = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        // (Pixar's new logo — Steven's, 2026-10-31 — is solid white: balanced as the others.)
        return t.contains("ghibli")
    }

    var body: some View {
        ZStack(alignment: alignment) {
            if let image, image.size.width > 0, image.size.height > 0 {
                let fitted = Self.size(aspect: image.size.width / image.size.height, area: area, max: maxSize)
                let picture = Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                // (A grey logo comes whitened in its picture itself — see `load`.)
                picture
                    .frame(width: fitted.width, height: fitted.height)
            }
        }
        .frame(width: maxSize.width, height: maxSize.height, alignment: alignment)
        .task(id: url) { await load() }
    }

    static func size(aspect: CGFloat, area: CGFloat, max: CGSize) -> CGSize {
        var width = (area * aspect).squareRoot()
        var height = width / aspect
        if width > max.width { width = max.width; height = width / aspect }
        if height > max.height { height = max.height; width = height * aspect }
        return CGSize(width: width, height: height)
    }

    private func load() async {
        guard let address = URL(string: url) else { image = nil; return }
        let request = ArtworkDecodeRequest(size: .points(width: maxSize.width, height: maxSize.height),
                                           fill: false, scale: displayScale)
        let key = "\(url)|\(maxSize.width)x\(maxSize.height)|\(displayScale)" as NSString
        if whiten, let ready = Self.white.object(forKey: key) { image = ready; return }
        var found = ArtworkStore.cached(address, decode: request)
        if found == nil { found = try? await ArtworkStore.fetch(address, decode: request) }
        guard let found else { image = nil; return }
        guard whiten else { image = found; return }
        // Steven: Pixar's and Ghibli's thin, half-transparent lines read pale even whitened — drawn
        // three times over, they come out solid white. (Steven, 2026-10-31: made once into the
        // picture — three filtered copies were worked out again at every frame of a change.)
        let whitened = Self.whitened(found)
        Self.white.setObject(whitened, forKey: key)
        image = whitened
    }

    nonisolated(unsafe) private static let white: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 20
        return cache
    }()

    /// The logo in white, its lines laid three times over (as three white copies stacked).
    private static func whitened(_ logo: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = logo.scale
        format.opaque = false
        let rect = CGRect(origin: .zero, size: logo.size)
        let silhouette = UIGraphicsImageRenderer(size: logo.size, format: format).image { ctx in
            logo.draw(in: rect)
            UIColor.white.setFill()
            ctx.fill(rect, blendMode: .sourceIn)
        }
        return UIGraphicsImageRenderer(size: logo.size, format: format).image { _ in
            for _ in 0..<3 { silhouette.draw(in: rect) }
        }
    }
}

/// One studio tile, landscape: its logo in white on its own colour; dimmed while another studio
/// is focused, full with the white frame and a lift when focused (half-way while the focus is on
/// its films below).
private struct OrbitStudioTile: View {
    let folder: CollectionFolder
    let focused: Bool
    var selected: Bool = false
    let tint: Color

    var body: some View {
        let size = OrbitStudiosPage.tileSize
        let radius: CGFloat = 14
        let lift: CGFloat = focused ? 1 : (selected ? 0.6 : 0)
        ZStack {
            if let logo = OrbitStudiosPage.logoURL(folder) {
                // The thin logos (Pixar, Ghibli) a little larger, to read as well as the others.
                OrbitBalancedLogo(url: logo, area: OrbitBalancedLogo.isGrey(folder.title) ? 10_500 : 7_600,
                                  maxSize: CGSize(width: size.width - 50, height: size.height - 40),
                                  whiten: OrbitBalancedLogo.isGrey(folder.title), alignment: .center)
                    // The logos are white or light: kept white on the colour.
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    // The logo and its shadow drawn once into a picture (room for the shadow).
                    .padding(12).drawingGroup().padding(-12)
            } else {
                name
            }
        }
        .frame(width: size.width, height: size.height)
        // Steven (2026-10-30, video again: dark slivers inside the frame on each side, the focused
        // tile): the colour was part of the picture below, whose edge pixels blend with nothing
        // once scaled. Only the logo is a picture now; the colour is drawn as a shape, under it.
        .background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(white: 0.08))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(0.55 + 0.45 * lift))
        }
        // Steven (2026-10-30: the studios' row jerky when pressed quickly or swiped): every tile's
        // logo shadow and soft tile shadow were worked out again at every frame of a slide (as on
        // HBO Max and Apple TV). The tile is drawn once into a picture (its logo's shadow in it), and
        // only the focused or chosen tile casts a shadow.
        // (Steven, video: dark slivers inside the frame on each side — the rounded edge drawn into the
        // picture came out with a dark fringe. The whole tile drawn, then rounded.)
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : (selected ? 0.5 : 0.12)),
                              lineWidth: focused ? 4 : (selected ? 3 : 1.5))
        }
        .scaleEffect(focused ? 1.1 : (selected ? 1.05 : 1))
        .shadow(color: .black.opacity(lift > 0 ? 0.3 + 0.3 * lift : 0), radius: lift > 0 ? 10 + 16 * lift : 0, y: lift > 0 ? 6 + 8 * lift : 0)
        .zIndex(focused || selected ? 1 : 0)
        .accessibilityLabel(folder.title)
    }

    private var name: some View {
        Text(folder.title)
            .font(.system(size: 26, weight: .heavy))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .padding(16)
    }
}

// MARK: - The studio's films

@MainActor
final class OrbitStudioFilmsModel: ObservableObject {
    static let shared = OrbitStudioFilmsModel()

    @Published private(set) var title: String?
    /// The two rows shown: "Nouveautés" (when the studio has recent releases), "Les
    /// incontournables", "Les plus populaires" — the first two of them.
    @Published private(set) var rows: [(title: String, items: [MetaPreview])] = []
    /// "Studio · 432 films".
    @Published private(set) var statsLine: String?
    /// "Derniers films : Thunderbolts*, Les 4 Fantastiques".
    @Published private(set) var latestLine: String?

    private struct Found {
        var recent: [MetaPreview]
        var best: [MetaPreview]
        var popular: [MetaPreview]
        var count: Int
    }

    private var cache: [String: Found] = [:]
    private var pending: Task<Void, Never>?
    private var current: String?

    /// TMDB company ids for a studio folder, from its title.
    static func companies(forTitle raw: String) -> String? {
        let t = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        if t.contains("pixar") { return "3" }
        if t.contains("marvel") { return "420" }
        if t.contains("lucasfilm") || t.contains("starwars") { return "1" }
        if t.contains("dreamworks") { return "521" }
        if t.contains("illumination") { return "6704" }
        if t.contains("ghibli") { return "10342" }
        if t.contains("dc") { return "128064|9993" }
        if t.contains("warner") { return "174" }
        if t.contains("universal") { return "33" }
        if t.contains("sony") || t.contains("columbia") { return "34|5" }
        if t.contains("paramount") { return "4" }
        if t.contains("20th") || t.contains("century") { return "25|127928" }
        if t.contains("a24") { return "41077" }
        if t.contains("blumhouse") { return "3172" }
        if t.contains("legendary") { return "923" }
        if t.contains("lionsgate") { return "1632" }
        if t.contains("pathe") { return "7981|866" }
        if t.contains("gaumont") { return "9" }
        if t.contains("studiocanal") { return "694" }
        if t.contains("nationalgeographic") || t.contains("natgeo") { return "7521" }
        if t.contains("disney") { return "2|6125" }
        return nil
    }

    func focus(title folderTitle: String) {
        guard let companies = Self.companies(forTitle: folderTitle) else {
            pending?.cancel()
            current = nil
            withAnimation(.easeInOut(duration: 0.25)) { title = nil; rows = []; statsLine = nil; latestLine = nil }
            return
        }
        guard companies != current else { return }
        current = companies
        pending?.cancel()
        if let cached = cache[companies] {
            withAnimation(.easeInOut(duration: 0.25)) { show(cached, title: folderTitle) }
            return
        }
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        let language = TmdbSettingsRepository.shared.snapshot().language
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let lists = await Self.fetch(companies: companies, apiKey: key, language: language)
            guard !Task.isCancelled, let self, self.current == companies else { return }
            let found = Found(recent: lists.recent, best: lists.best, popular: lists.popular, count: lists.count)
            self.cache[companies] = found
            withAnimation(.easeInOut(duration: 0.25)) { self.show(found, title: folderTitle) }
        }
    }

    private func show(_ found: Found, title folderTitle: String) {
        title = folderTitle
        var list: [(title: String, items: [MetaPreview])] = []
        // Steven: "Les incontournables" everywhere (a studio with few new films looked empty).
        if found.best.count >= 3 { list.append((String(localized: "Les incontournables"), found.best)) }
        let bestIds = Set(found.best.prefix(20).map(\.id))
        let popular = found.popular.filter { !bestIds.contains($0.id) }
        if popular.count >= 3 { list.append((String(localized: "Les plus populaires"), popular)) }
        // One row: the essentials (the most popular when TMDB has too few well-rated ones).
        rows = Array(list.prefix(1))
        // Only with real recent releases (Ghibli showed an obscure 1987 documentary).
        let latest = found.recent.count >= 6 ? found.recent.prefix(2).map(\.name) : []
        latestLine = latest.isEmpty ? nil : String(localized: "Derniers films : \(latest.joined(separator: ", "))")
        statsLine = found.count > 0 ? String(localized: "Studio · \(found.count) films") : String(localized: "Studio")
    }

    nonisolated private struct Response: Decodable {
        nonisolated struct Result: Decodable {
            let id: Int
            let title: String?
            let overview: String?
            let poster_path: String?
            let backdrop_path: String?
            let release_date: String?
            let vote_average: Double?
        }
        let results: [Result]?
        let total_results: Int?
    }

    /// "Nouveautés": the films out in the last eighteen months (feature length, most popular of
    /// them, newest first); "Les incontournables": the best rated (feature length, well known).
    nonisolated private static func fetch(companies: String, apiKey: String, language: String) async
        -> (recent: [MetaPreview], best: [MetaPreview], popular: [MetaPreview], count: Int) {
        let lang = language.isEmpty ? "fr-FR" : language
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: Date())
        let since = formatter.string(from: Date().addingTimeInterval(-548 * 24 * 3600))
        let encoded = companies.replacingOccurrences(of: "|", with: "%7C")
        let base = "https://api.themoviedb.org/3/discover/movie?api_key=\(apiKey)&language=\(lang)"
            + "&with_companies=\(encoded)&with_runtime.gte=60"
        async let recentCall = results(base + "&sort_by=popularity.desc&primary_release_date.gte=\(since)&primary_release_date.lte=\(today)")
        async let bestCall = results(base + "&sort_by=vote_average.desc&vote_count.gte=300")
        async let popularCall = results(base + "&sort_by=popularity.desc&vote_count.gte=50")
        async let popular2Call = results(base + "&sort_by=popularity.desc&vote_count.gte=50&page=2")
        async let allCall = results("https://api.themoviedb.org/3/discover/movie?api_key=\(apiKey)&with_companies=\(encoded)")
        let (recentValue, bestValue, popularValue, popular2Value, allValue) =
            await (recentCall, bestCall, popularCall, popular2Call, allCall)
        let recent = recentValue.items.sorted { ($0.release_date ?? "") > ($1.release_date ?? "") }
        return (recent.compactMap(preview), bestValue.items.compactMap(preview),
                (popularValue.items + popular2Value.items).compactMap(preview), allValue.total)
    }

    nonisolated private static func preview(_ r: Response.Result) -> MetaPreview? {
        guard let name = r.title, !name.isEmpty, let poster = r.poster_path else { return nil }
        return MetaPreview(id: "tmdb:\(r.id)", type: "movie", name: name,
                           poster: "https://image.tmdb.org/t/p/w780\(poster)",
                           banner: r.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" },
                           logo: nil, posterShape: .poster,
                           description: r.overview, releaseInfo: r.release_date.map { String($0.prefix(4)) },
                           rawReleaseDate: r.release_date, popularity: nil, voteCount: nil,
                           imdbRating: r.vote_average.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil },
                           genres: [], rawPosterUrl: nil, landscapePoster: nil,
                           rawLandscapePosterUrl: nil, customPosterApplied: false)
    }

    nonisolated private static func results(_ address: String) async -> (items: [Response.Result], total: Int) {
        guard let url = URL(string: address),
              let response = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(Response.self, from: response.0) else { return ([], 0) }
        return (decoded.results ?? [], decoded.total_results ?? 0)
    }
}

/// A row of the studio's films in small portrait posters, scrolling sideways (no return to its
/// start: the focus lands where the system puts it, as in Apple's app).
struct OrbitStudioFilmsRow: View {
    /// 0: the upper row, 1: the lower one.
    let slot: Int

    @ObservedObject private var model = OrbitStudioFilmsModel.shared
    @FocusState private var focused: String?
    @MainActor static var lostAt: TimeInterval = 0
    /// A film (of either row) holds the focus (read by the studios' line when the focus comes up).
    @MainActor static var hasFocus = false
    @MainActor private static var holders = 0

    static let posterSize = CGSize(width: 150, height: 225)

    private var row: (title: String, items: [MetaPreview])? {
        model.rows.indices.contains(slot) ? model.rows[slot] : nil
    }
    private var items: [MetaPreview] { row?.items ?? [] }

    var body: some View {
        let items = items
        VStack(alignment: .leading, spacing: 14) {
            if let title = model.title, let heading = row?.title {
                Text(heading)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    .frame(height: 40)
                    .padding(.leading, OrbitHomeLayout.margin)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        ForEach(items, id: \.id) { item in
                            NavigationLink(value: TitleRoute(preview: item)) {
                                OrbitStudioFilmPoster(item: item, focused: focused == item.id)
                            }
                            .buttonStyle(OrbitPlatformTileStyle())
                            .focused($focused, equals: item.id)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, OrbitHomeLayout.margin)
                }
                .scrollClipDisabled()
                .padding(.vertical, -16)
                .id("films-\(heading)-\(title)")
                .transition(.opacity)
            }
        }
        // The slot keeps its height when empty (the rows never move).
        .frame(height: 40 + 14 + Self.posterSize.height, alignment: .topLeading)
        .focusSection()
        .onChange(of: focused) { old, id in
            if old == nil, id != nil { Self.holders += 1 }
            if old != nil, id == nil { Self.holders = max(0, Self.holders - 1) }
            Self.hasFocus = Self.holders > 0
            guard let id else { Self.lostAt = ProcessInfo.processInfo.systemUptime; return }
        }
    }
}

private struct OrbitStudioFilmPoster: View {
    let item: MetaPreview
    let focused: Bool

    var body: some View {
        let size = OrbitStudioFilmsRow.posterSize
        ZStack {
            Color(white: 0.12)
            OrbitImage(url: item.poster, size: size)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 4)
        }
        .scaleEffect(focused ? 1.08 : 1)
        .shadow(color: .black.opacity(focused ? 0.55 : 0.25), radius: 16, y: 8)
        .animation(.easeOut(duration: 0.14), value: focused)
        .accessibilityLabel(item.name)
    }
}


/// The Studios page's picture: the studio's image across the banner, sharp, melting at its foot into
/// the same image blurred, down to the screen's bottom — one still picture (the next studio's image
/// fading in over it).
private struct OrbitStudiosBackdrop: View {
    let url: String?
    var lift: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    /// One studio's three pictures, made once: its colours (the thick blur), the blurred continuation
    /// already darkened and faded, the sharp banner with its foot already faded.
    private struct Layer {
        let thick: UIImage?
        let blurred: UIImage
        let sharp: UIImage
    }
    /// Two slots: the one shown, and the one the next studio is put in, unseen, before it fades in.
    @State private var slotA: Layer?
    @State private var slotB: Layer?
    @State private var showsB = false
    @State private var busyUntil: TimeInterval = 0
    @State private var waiting: Layer?
    @State private var generation = 0

    /// A hidden slot is drawn at almost nothing, not at nothing: the TV loads its pictures then,
    /// before the fade, not at its first frame.
    private static let unseen: Double = 0.001
    private static let fadeIn: Double = 0.3
    private static let fadeOut: Double = 0.2
    private static let outDelay: Double = 0.16

    var body: some View {
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        // Steven (2026-10-31, slow motion, several times: the change jerky at its start or its end,
        // "l'ancienne image disparaît d'un coup sec"). Measured on his video: the new picture jumped
        // from nothing to half in one frame — the TV loading a 4K picture at the fade's first frame —
        // and the old one was taken away at once at the end, seen through the new one's faded foot.
        // Now: the new studio's three pictures are put in the hidden slot first, drawn unseen; the
        // fade starts a few frames later, the old studio fading out as the new one is nearly in.
        ZStack(alignment: .top) {
            layer(slotA)
                .opacity(showsB ? Self.unseen : 1)
                .animation(showsB ? .easeIn(duration: Self.fadeOut).delay(Self.outDelay)
                                  : .easeOut(duration: Self.fadeIn), value: showsB)
                .zIndex(showsB ? 0 : 1)
            layer(slotB)
                .opacity(showsB ? 1 : Self.unseen)
                .animation(showsB ? .easeOut(duration: Self.fadeIn)
                                  : .easeIn(duration: Self.fadeOut).delay(Self.outDelay), value: showsB)
                .zIndex(showsB ? 1 : 0)
        }
        .frame(width: W, height: H, alignment: .top)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: "\(url ?? "-")|\(lift)") {
            guard let url else { return }
            let scale = displayScale
            var pair = OrbitStudioBake.ready(url, lift: lift, scale: scale)
            if pair == nil { pair = await OrbitStudioBake.make(url, lift: lift, scale: scale) }
            guard let pair, !Task.isCancelled else { return }
            if OrbitThickBlur.made.object(forKey: url as NSString) == nil { await OrbitThickBlur.prepare(url) }
            guard !Task.isCancelled else { return }
            show(Layer(thick: OrbitThickBlur.made.object(forKey: url as NSString), blurred: pair.blurred, sharp: pair.sharp))
        }
    }

    @ViewBuilder
    private func layer(_ layer: Layer?) -> some View {
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        let band = OrbitStudioFrame.bannerSize.height
        ZStack(alignment: .top) {
            if let layer {
                if let thick = layer.thick {
                    Image(uiImage: thick).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: W, height: H).clipped()
                }
                Image(uiImage: layer.blurred).resizable().frame(width: W, height: H)
                Image(uiImage: layer.sharp).resizable().frame(width: W, height: band)
            }
        }
        .frame(width: W, height: H, alignment: .top)
    }

    private func show(_ next: Layer) {
        // The first studio: at once.
        if slotA == nil && slotB == nil {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { slotA = next; showsB = false }
            return
        }
        // A change still running: the latest studio waits for it (never put in the slot fading out).
        let now = ProcessInfo.processInfo.systemUptime
        if now < busyUntil {
            let first = waiting == nil
            waiting = next
            if first {
                DispatchQueue.main.asyncAfter(deadline: .now() + (busyUntil - now) + 0.02) {
                    guard let queued = waiting else { return }
                    waiting = nil
                    show(queued)
                }
            }
            return
        }
        waiting = nil
        generation &+= 1
        let mine = generation
        busyUntil = now + 0.07 + Self.outDelay + Self.fadeOut + 0.05
        // Into the hidden slot, unseen…
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { if showsB { slotA = next } else { slotB = next } }
        // …then, once the TV has drawn it, the fade.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            guard mine == generation else { return }
            showsB.toggle()
            // The old pictures let go once gone (memory: 4K pictures).
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.outDelay + Self.fadeOut + 0.1) {
                guard mine == generation else { return }
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { if showsB { slotA = nil } else { slotB = nil } }
            }
        }
    }
}

/// The Studios banner's pictures, made once per studio (and ahead, as the page opens).
enum OrbitStudioBake {
    nonisolated(unsafe) private static let made: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // (The sharp ones are 4K-wide pictures: kept by their weight, the oldest let go first.)
        cache.totalCostLimit = 220 * 1024 * 1024
        return cache
    }()

    private static func key(_ url: String, _ lift: CGFloat, _ kind: String) -> NSString {
        "\(url)|\(lift)|\(kind)" as NSString
    }

    @MainActor
    static func ready(_ url: String, lift: CGFloat, scale: CGFloat) -> (sharp: UIImage, blurred: UIImage)? {
        guard let sharp = made.object(forKey: key(url, lift, "sharp\(scale)")),
              let blurred = made.object(forKey: key(url, lift, "blurred")) else { return nil }
        return (sharp, blurred)
    }

    /// The sharp banner (the screen's width, the banner's height, its foot faded from 80 %) and the
    /// blurred continuation (the screen, darkened, faded out 135 pt under the banner), each at the
    /// very place the page showed them.
    @MainActor
    @discardableResult
    static func make(_ url: String, lift: CGFloat, scale: CGFloat) async -> (sharp: UIImage, blurred: UIImage)? {
        if let ready = ready(url, lift: lift, scale: scale) { return ready }
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        let band = OrbitStudioFrame.bannerSize.height
        let fullH = W * 9 / 16
        let shift = max(0, fullH - band) / 2 * lift
        let request = ArtworkDecodeRequest(size: .points(width: W, height: fullH), fill: true, scale: scale)
        guard let main = URL(string: url) else { return nil }
        let best = ArtworkURLUpgrade.upgraded(main, role: .backdrop)
        var source: UIImage?
        for candidate in [best, main].compactMap({ $0 }) {
            if let hit = ArtworkStore.cached(candidate, decode: request) { source = hit; break }
            if let fetched = try? await ArtworkStore.fetch(candidate, decode: request) { source = fetched; break }
        }
        guard let source else { return nil }
        guard let soft = await OrbitPreBlurred.prepare(url, radius: 16) else { return nil }
        let pair: (UIImage, UIImage) = await Task.detached(priority: .userInitiated) {
            // The sharp banner: the 16:9 picture centred on the banner, lowered by its lift, cut to
            // the banner, its foot fading from 80 % to nothing.
            let sharpFormat = UIGraphicsImageRendererFormat()
            sharpFormat.scale = scale
            sharpFormat.opaque = false
            let sharp = UIGraphicsImageRenderer(size: CGSize(width: W, height: band), format: sharpFormat).image { ctx in
                source.draw(in: CGRect(x: 0, y: (band - fullH) / 2 + shift, width: W, height: fullH))
                // (Steven, 2026-10-31: "le flou en bas trop marqué, on dirait pas l'image qui continue"
                // — the sharp picture now melts into its own blurred copy from 70 % of the banner, not
                // its last 12 %. The blurred copy under it is unchanged, at the very same place.)
                // (Then "c'est mieux, même si je descendrais encore": from 80 %.)
                Self.fade(ctx.cgContext, from: band * 0.80, to: band)
            }
            // The blurred copy: the screen, the picture centred where the sharp one is, darkened,
            // fading out under the banner. (Half the screen's pixels: it is a blur.)
            let softFormat = UIGraphicsImageRendererFormat()
            softFormat.scale = 0.5
            softFormat.opaque = false
            let blurred = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: softFormat).image { ctx in
                soft.draw(in: CGRect(x: 0, y: band / 2 - H / 2 + shift, width: W, height: H))
                UIColor.black.withAlphaComponent(0.22).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: W, height: H), blendMode: .normal)
                Self.fade(ctx.cgContext, from: band, to: band + 135)
            }
            return (sharp, blurred)
        }.value
        made.setObject(pair.0, forKey: key(url, lift, "sharp\(scale)"), cost: Self.weight(pair.0))
        made.setObject(pair.1, forKey: key(url, lift, "blurred"), cost: Self.weight(pair.1))
        return pair
    }

    private static func weight(_ image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    /// Keeps what is drawn above `from`, fades it to nothing at `to`, clears what is below.
    nonisolated private static func fade(_ context: CGContext, from: CGFloat, to: CGFloat) {
        let space = CGColorSpaceCreateDeviceRGB()
        let colors = [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
        context.saveGState()
        context.setBlendMode(.destinationIn)
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: from), end: CGPoint(x: 0, y: to),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }
}


/// Steven (2026-10-31: "Walt Disney" and "Pixar Animation Studios" read small on the tiles — "je suis
/// ton conseil"): their short logos, his files (white, transparent), kept with Orbit's code, in place
/// of the folders' own wherever a studio's logo shows (the tiles, the banner, the studio's page,
/// Disney+'s brands).
enum OrbitStudioLogos {
    private static let base = "https://raw.githubusercontent.com/mrStevenx3/NuvioMobile/detail-apple-style/orbit-assets/logos/"

    static func url(forTitle title: String?) -> String? {
        guard let title else { return nil }
        let key = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if key.contains("pixar") { return base + "pixar.png" }
        // (Star Wars's own page, from Disney+: the app's Star Wars logo, in white.)
        if key.contains("star wars") { return base + "starwars.png" }
        // (Disney's studio — not Disney+, the platform.)
        if isDisney(title) { return base + "disney.png" }
        return nil
    }

    static func isDisney(_ title: String) -> Bool {
        let key = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return key.contains("disney") && !key.contains("+") && !key.contains("plus")
    }
}

