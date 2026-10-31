import Combine
import SharedCore
import SwiftUI
import UIKit

// Orbit Home (Steven's fork, 2026-10-23): Home's Films and Séries pages rebuilt from scratch after
// Steven's reference video, independent of the Stage / Classic layouts.
//
// Fluidity is the brief, so nothing here is moved by the focus engine. The page is ONE focusable
// stop (an invisible button over the content) that takes the remote's presses itself:
//  - Up / Down change the current section (hero → genres → rows). The whole column moves as one
//    layer on one curve (`OrbitHomeLayout.vertical`), so the focused section lands on its fixed
//    line; the sections above fade out as they leave.
//  - Left / Right move the current section's lead: every card is drawn at a computed x and they all
//    glide together (`OrbitHomeLayout.horizontal`), under a fixed, opaque frame.
//  - Select opens the title (or resumes it, or opens the genre); Menu goes back to the top.
// Only the sections near the current one exist, and in a row only the cards near its lead.
// While the page is scrolled past its first section, the Orbit bar is out of the focus engine's
// reach (`OrbitBarLock`), so Up is the page's own; at the top, Up goes to the bar.

/// Settings ▸ Home Screen ▸ Orbit Home.
nonisolated enum OrbitHomeSetting {
    static let enabledKey = "orbit_home_enabled"
    static let trailersKey = "orbit_home_trailers"
    /// Steven (2026-10-25): the previews that start on their own play with their sound.
    static let trailerSoundKey = "orbit_trailer_sound"
}

extension Notification.Name {
    /// Asks the Orbit bar to take focus (its current page's item): Menu at the top of an Orbit page.
    /// The system's own Menu sent focus to the hidden tab bar, where the cursor vanished.
    static let orbitBarFocusRequest = Notification.Name("OrbitBarFocusRequest")
}

/// Keeps the Orbit bar out of the focus engine's reach while Orbit Home is scrolled down.
@MainActor
final class OrbitBarLock: ObservableObject {
    static let shared = OrbitBarLock()
    @Published private(set) var locked = false
    private init() {}
    func set(_ value: Bool) {
        if locked != value { locked = value }
    }
}

/// The trailer dwell's rest signal: the page is at rest once no press has come for a moment.
@MainActor
final class OrbitHomeMotion: RowRestSignal {
    private var last = ProcessInfo.processInfo.systemUptime
    func stamp() { last = ProcessInfo.processInfo.systemUptime }
    /// Home's last Up/Down (its rows' window settles once no other came after it).
    var verticalStamp: TimeInterval = 0
    var restPending: Bool { false }
    var secondsSinceMotion: TimeInterval { ProcessInfo.processInfo.systemUptime - last }
}

/// What Home's pages can ask Home's navigation to do.
struct StageHomeActions {
    /// Continue Watching: open the stream picker (`HomeView.resume`).
    let resume: (ResumeTarget) -> Void
    /// Push onto Home's stack (`HomeView.homePath`).
    let push: (TitleRoute) -> Void
}

/// What covers Home from `HomeView`'s own presentation machinery.
nonisolated struct StageCover: Equatable {
    /// Something is pushed over Home (`!homePath.isEmpty`).
    var pushed: Bool
    /// The Continue Watching stream picker is up.
    var resume: Bool
}

/// Films / Séries: Orbit Home. Plateformes / Studios: their Orbit pages.
struct OrbitHomeSwitch: View {
    @ObservedObject var model: HomeViewModel
    let actions: StageHomeActions
    let pushGenre: (OrbitGenre) -> Void
    let cover: StageCover
    @Binding var isScrolledDown: Bool

    @ObservedObject private var contentFilter = HomeContentFilterModel.shared

    var body: some View {
        let filter = contentFilter.filter
        ZStack {
            if filter == .services || filter == .studios {
                OrbitSpacesPage(model: model, studios: filter == .studios, cover: cover)
                    .id(filter)
                    // (Steven, 2026-10-29: Séries → Plateformes came with no fade.) Over Home: coming in
                    // it fades in over it (Home goes once it is in); leaving, it fades out over Home,
                    // already whole under it — no dip to black either way.
                    .zIndex(2)
                    .transition(.opacity.animation(.easeInOut(duration: 0.35)))
                    .onAppear { OrbitBarLock.shared.set(false) }
            }
            // Steven (simulator: Films ↔ Séries took up to a second — the page was built again at
            // each switch): both Homes stay built once visited; the switch only shows the other one.
            // The hidden one is inert (no focus, no trailer, no bar lock).
            ForEach([false, true], id: \.self) { series in
                if visited.contains(series) {
                    let active = isHome && (filter == .series) == series
                    OrbitHomeView(model: model, series: series, active: active, actions: actions, pushGenre: pushGenre,
                                  isScrolledDown: active ? $isScrolledDown : .constant(false))
                        // Steven (2026-10-29: "la transition entre films et séries est trop brute"):
                        // the Home coming in fades in over the one leaving (which stays whole under it,
                        // then goes) — a soft cross-dissolve with no dip to black between the two.
                        // (Steven, 2026-10-29: a lag between the two — quicker, 0.3 s. Towards Plateformes
                        // or Studios, Home stays whole under their page fading in, then goes; back from
                        // them, it is there at once under their page fading out.)
                        .opacity(active ? 1 : 0)
                        .animation(active ? (cameFromSpaces ? nil : .easeInOut(duration: 0.3))
                                   : .linear(duration: 0.01).delay(isHome ? 0.31 : 0.36),
                                   value: active)
                        .disabled(!active)
                        .allowsHitTesting(active)
                        .zIndex(active ? 1 : 0)
                }
            }
        }
        .onAppear { shownFilter = filter; markVisited() }
        .onChange(of: filter) { _, new in
            shownFilter = new
            markVisited()
        }
    }

    /// The filter shown before this update (read while the switch is drawn: coming from Plateformes /
    /// Studios, Home is at once under the page fading out).
    @State private var shownFilter: HomeContentFilter?
    private var cameFromSpaces: Bool { shownFilter == .services || shownFilter == .studios }

    /// The Homes built so far (films, series).
    @State private var visited: Set<Bool> = []

    private var isHome: Bool { contentFilter.filter != .services && contentFilter.filter != .studios }

    private func markVisited() {
        guard isHome else { return }
        visited.insert(contentFilter.filter == .series)
    }
}

struct OrbitHomeView: View {
    @ObservedObject var model: HomeViewModel
    let series: Bool
    /// The Home on screen (the other one stays built, hidden and inert).
    var active: Bool = true
    let actions: StageHomeActions
    let pushGenre: (OrbitGenre) -> Void
    @Binding var isScrolledDown: Bool

    @ObservedObject private var heroModel = StageTrendingHeroModel.shared
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The page's own rows (TMDB): the Top 10 across the platforms, each platform's new titles.
    @StateObject private var extras = OrbitHomeExtrasModel()

    // MARK: Data

    private var heroItems: [MetaPreview] { heroModel.items(series: series) }
    private var genres: [OrbitGenre] { series ? OrbitGenre.series : OrbitGenre.movies }

    /// Steven (pass 3: "trop pauvre", tiles of different kinds and sizes): Reprendre in landscape
    /// tiles; his catalogs alternating the classic frame, large cards and smaller posters (his Top
    /// 10 keep the classic frame); the Top 10 across the platforms after the first catalog; each
    /// platform's new titles in landscape tiles, one every two catalogs.
    /// Fluidity (Steven, 2026-10-25, before the IPA): the rows were rebuilt — every card of every
    /// row, through the Kotlin lists — several times per remote press. They are rebuilt only when
    /// what they are made of changed (a cheap signature of the catalogs, Reprendre and the extras).
    @State private var rowsCache = OrbitRowsCache()

    private var rows: [OrbitRow] {
        let key = rowsSignature()
        if rowsCache.key == key { return rowsCache.rows }
        let built = buildRows()
        rowsCache.key = key
        rowsCache.rows = built
        return built
    }

    private func rowsSignature() -> String {
        var k = series ? "s|" : "m|"
        for e in model.continueWatching { k += "\(e.videoId):\(e.lastUpdatedEpochMs)," }
        k += "|"
        let because = series ? extras.becauseSeries : extras.becauseMovie
        for extra in (series ? extras.seriesRows : extras.movieRows) + [because].compactMap({ $0 }) {
            k += "\(extra.id)#\(extra.items.count)#\(extra.items.first?.id ?? ""),"
        }
        k += "|"
        for row in model.rows {
            guard case .catalog(let section) = row else { continue }
            let items = section.items
            k += "\(section.key)#\(items.count)#\(items.first?.id ?? "")#\(items.last?.id ?? ""),"
        }
        return k
    }

    private func buildRows() -> [OrbitRow] {
        var out: [OrbitRow] = []
        var seen = Set<String>()
        let entries = model.continueWatching.filter { series ? $0.parentMetaType != "movie" : $0.parentMetaType == "movie" }
        if !entries.isEmpty {
            out.append(OrbitRow(id: "continue-watching", title: String(localized: "Reprendre"),
                                cards: Self.unique(entries.map(OrbitCard.continueWatching)), style: .landscape))
            seen.insert("continue-watching")
        }
        let because = series ? extras.becauseSeries : extras.becauseMovie
        let extraRows = ((series ? extras.seriesRows : extras.movieRows) + [because].compactMap { $0 }).map { extra in
            OrbitRow(id: extra.id, title: extra.title, cards: Self.unique(extra.items.map { Self.card(extra.id, $0) }),
                     style: extra.style)
        }
        var top = extraRows.filter { $0.style == .ranked }
        // Orbit's own rows, one after each of his catalogs from the second, in this order.
        let order = ["orbit-because", "orbit-new", "orbit-soon", "orbit-sagas", "orbit-best"]
        var platforms = extraRows.filter { $0.style != .ranked }
            .sorted { a, b in
                (order.firstIndex { a.id.hasPrefix($0) } ?? 9) < (order.firstIndex { b.id.hasPrefix($0) } ?? 9)
            }
        let cycle: [OrbitRowStyle] = [.cards, .classic, .posters]
        var catalogs = 0
        var styled = 0
        for row in model.rows {
            guard case .catalog(let section) = row else { continue }
            let movie = section.target.contentType == "movie"
            guard series ? !movie : movie, !section.items.isEmpty, seen.insert(section.key).inserted else { continue }
            let heading = section.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let isTop = heading.contains("top 10") || heading.contains("top10")
            // Steven: one Top 10 is enough — Orbit's own (across his platforms) replaces his add-on's
            // on Home once it has arrived (the platforms' pages keep theirs).
            if isTop, extraRows.contains(where: { $0.style == .ranked }) { continue }
            var style: OrbitRowStyle = .classic
            if !isTop {
                style = styled == 0 ? .classic : cycle[(styled - 1) % cycle.count]
                styled += 1
            }
            out.append(OrbitRow(id: section.key, title: section.title,
                                cards: Self.unique(section.items.map(OrbitCard.catalog)), sectionKey: section.key,
                                style: style))
            catalogs += 1
            // Steven (2026-10-29): after the first catalog (Nouveaux films), the Top 10, then Nouveau
            // sur vos plateformes.
            if catalogs == 1, !top.isEmpty { out.append(top.removeFirst()) }
            if catalogs == 1, let i = platforms.firstIndex(where: { $0.id.hasPrefix("orbit-new") }) {
                out.append(platforms.remove(at: i))
            }
            if catalogs >= 2, !platforms.isEmpty { out.append(platforms.removeFirst()) }
        }
        return out + top + platforms
    }

    /// An Orbit row's card: a saga keeps its own id (it opens its first film), Prochainement shows
    /// its date ("12 nov.") on the tile.
    private static func card(_ rowId: String, _ item: MetaPreview) -> OrbitCard {
        var card = OrbitCard.catalog(item)
        if rowId.hasPrefix("orbit-sagas") {
            card = OrbitCard(id: "saga:\(item.id)", preview: item, poster: item.poster, landscape: card.landscape)
        }
        if rowId.hasPrefix("orbit-soon"), let raw = item.rawReleaseDate, raw.count >= 10,
           let date = Self.isoDay.date(from: String(raw.prefix(10))) {
            card.badge = String(localized: "Le \(Self.shortDay.string(from: date))")
        }
        return card
    }

    // Made once (a DateFormatter is costly to create).
    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        return f
    }()

    /// "Parce que vous avez regardé": the last title watched of the page's kind — finished (his
    /// watched list) or in progress (Reprendre), the more recent of the two.
    private func becauseSeed(series: Bool) -> (id: String, name: String)? {
        let entry = model.continueWatching
            .filter { series ? $0.parentMetaType != "movie" : $0.parentMetaType == "movie" }
            .max { $0.lastUpdatedEpochMs < $1.lastUpdatedEpochMs }
        let watched = (WatchedRepository.shared.uiState.value_ as? WatchedUiState)?.items
            .filter { series ? $0.type != "movie" : $0.type == "movie" }
            .max { $0.markedAtEpochMs < $1.markedAtEpochMs }
        if let watched, watched.markedAtEpochMs > (entry?.lastUpdatedEpochMs ?? 0) {
            return (watched.id, watched.name)
        }
        if let entry { return (entry.parentMetaId, entry.title) }
        return nil
    }

    private static func unique(_ cards: [OrbitCard]) -> [OrbitCard] {
        var seen = Set<String>()
        return cards.filter { seen.insert($0.id).inserted }
    }

    // MARK: Body

    var body: some View {
        // Steven (2026-10-26): Home built like Apple's TV app — the drawn Home is gone.
        OrbitNativeHome(heroItems: heroItems, rows: rows, actions: actions, isScrolledDown: $isScrolledDown, active: active)
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight, alignment: .topLeading)
        .background(OrbitHomeLayout.background)
        .ignoresSafeArea()
        .onAppear {
            heroModel.loadIfNeeded()
            extras.load()
            WatchedRepository.shared.ensureLoaded()
            extras.loadBecause(seed: becauseSeed(series: series), series: series)
            OrbitPlatformLogos.update()
        }
        .onDisappear {
            if active { OrbitBarLock.shared.set(false) }
        }
        .onChange(of: model.continueWatching.count) { _, _ in
            extras.loadBecause(seed: becauseSeed(series: series), series: series)
        }
    }
}

/// The rows' backdrop: the focused title's art in the top right, fading into the page to the left
/// and down (as on Prime's and Paramount+'s pages), dimmed so the rows stay in front.
/// The colour of Home's wash (the focused title's), shared with the rows' headings.
@MainActor
final class OrbitHomeTone: ObservableObject {
    static let shared = OrbitHomeTone()
    /// A studio's page: the focused title's colour in its rows (Home's own stays Home's).
    static let studio = OrbitHomeTone()
    @Published var color: Color?
}

/// A row's heading on Home. Steven (2026-10-25: the headings melted into the titles' text under
/// them): larger, heavier, a soft white gradient, and a short bar in the wash's colour before it.
struct OrbitRowHeading: View {
    let title: String
    let isCurrent: Bool
    /// The bar's colour where the page has its own (a platform's, a studio's); else Home's wash.
    var accent: Color? = nil
    var size: CGFloat = 34
    @ObservedObject var tone: OrbitHomeTone = OrbitHomeTone.shared
    /// The tone first, the accent when there is none (a studio: its title's colour in the rows,
    /// its own on the banner).
    var prefersTone = false

    var body: some View {
        let colour = prefersTone ? (tone.color ?? accent) : (accent ?? tone.color)
        HStack(spacing: size * 0.4) {
            Capsule()
                .fill(colour ?? Color.white.opacity(0.8))
                .frame(width: max(5, size * 0.18), height: size * 0.88)
                .shadow(color: (colour ?? .white).opacity(0.6), radius: 6)
            Text(title)
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.78)],
                                                startPoint: .top, endPoint: .bottom))
                .lineLimit(1)
        }
        // The whole heading dimmed (not its colour): an emoji in a catalogue's name dims with it.
        .opacity(isCurrent ? 1 : 0.55)
        .frame(height: size * 1.3, alignment: .center)
        .animation(.easeInOut(duration: OrbitRowsBackdrop.fade), value: colour)
    }
}

/// One wash's colours, shared by its views (Home's backdrop drives, the band under the bar shows the
/// same — Steven, 2026-10-29: the band kept the old colour while the page's changed).
@MainActor
final class OrbitWashMirror: ObservableObject {
    static let home = OrbitWashMirror()
    @Published var tone = OrbitWashTone()
}

/// The wash's colour as hue, saturation, brightness, and how present it is (0: none yet).
/// Steven (2026-10-31, simulator videos, several times: "ça passe au noir avant de se mettre sur la
/// bonne couleur" during the change): a cross-fade between two colours mixes them — red and blue
/// meet in a dull grey-brown half-way, read as going through black. The colour itself now travels,
/// by its hue (red → purple → blue), staying as lively all the way.
struct OrbitWashTone: Equatable {
    var hue: Double = 0
    var saturation: Double = 0
    var brightness: Double = 0
    var presence: Double = 0

    /// `color` as the next tone, its hue taken the short way round from this one's.
    func heading(to color: Color) -> OrbitWashTone {
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        var next = OrbitWashTone(hue: Double(h), saturation: Double(sat), brightness: Double(b), presence: 1)
        if presence < 0.01 || saturation < 0.12 {
            // Nothing shown yet, or a grey: no hue to travel from.
            return next
        }
        if next.saturation < 0.12 {
            // To a grey: keep the hue, only the colour fades out of it.
            next.hue = hue
            return next
        }
        while next.hue - hue > 0.5 { next.hue -= 1 }
        while hue - next.hue > 0.5 { next.hue += 1 }
        return next
    }
}

/// One wash, its colour animatable (drawn afresh at each frame of a change only).
struct OrbitToneWash: View, Animatable {
    var tone: OrbitWashTone

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { AnimatablePair(AnimatablePair(tone.hue, tone.saturation), AnimatablePair(tone.brightness, tone.presence)) }
        set {
            tone.hue = newValue.first.first
            tone.saturation = newValue.first.second
            tone.brightness = newValue.second.first
            tone.presence = newValue.second.second
        }
    }

    var body: some View {
        var h = tone.hue.truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        let color = Color(hue: h, saturation: min(1, max(0, tone.saturation)), brightness: min(1, max(0, tone.brightness)))
        let p = min(1, max(0, tone.presence))
        return ZStack {
            OrbitHomeLayout.background
            // Steven (2026-10-29: the left too dark): the light from the top's middle, wider — the whole
            // screen in the title's colour, evenly.
            RadialGradient(colors: [color.opacity(0.38 * p), color.opacity(0.22 * p), color.opacity(0.08 * p)],
                           center: UnitPoint(x: 0.5, y: 0.0), startRadius: 0, endRadius: 1900)
        }
    }
}

/// One wash, opaque: the page's ground and the title's colour drawn together into one picture.
/// Steven (2026-10-31, simulator video: "le changement de couleur se fait en deux fois" — measured: the
/// colour dimmed half-way, then rose again): two see-through washes cross-fading each stood at half
/// at the middle — the ground showing through both. Opaque, the new one simply covers the old one.
struct OrbitWashPicture: View {
    let color: Color?

    var body: some View {
        ZStack {
            OrbitHomeLayout.background
            // Steven (2026-10-29: the left too dark): the light from the top's middle, wider — the whole
            // screen in the title's colour, evenly.
            RadialGradient(colors: [(color ?? .clear).opacity(color == nil ? 0 : 0.38),
                                    (color ?? .clear).opacity(color == nil ? 0 : 0.22),
                                    (color ?? .clear).opacity(color == nil ? 0 : 0.08)],
                           center: UnitPoint(x: 0.5, y: 0.0), startRadius: 0, endRadius: 1900)
        }
        // (Drawn once into its own texture: its fade only fades a picture.)
        .drawingGroup()
    }
}

/// A wash drawn from a mirror (it computes nothing itself).
struct OrbitMirroredWash: View {
    @ObservedObject var mirror: OrbitWashMirror
    var opaque = true

    private func wash(_ color: Color?) -> some View {
        // Steven (2026-10-29: the left too dark): the light from the top's middle, wider — the whole
        // screen in the title's colour, evenly.
        RadialGradient(colors: [(color ?? .clear).opacity(color == nil ? 0 : 0.38),
                                (color ?? .clear).opacity(color == nil ? 0 : 0.22),
                                (color ?? .clear).opacity(color == nil ? 0 : 0.08)],
                       center: UnitPoint(x: 0.5, y: 0.0), startRadius: 0, endRadius: 1900)
            // (Drawn once into its own texture: its cross-fade only fades a picture.)
            .drawingGroup()
    }

    var body: some View {
        let L = OrbitHomeLayout.self
        ZStack {
            OrbitToneWash(tone: mirror.tone)
            // Steven (2026-10-29, trying it): the even wash a little darker towards the bottom.
            LinearGradient(colors: [.clear, .black.opacity(OrbitHomeLayout.footShade)], startPoint: UnitPoint(x: 0.5, y: 0.4), endPoint: .bottom)
            OrbitGrain()
            Color.white.opacity(OrbitHomeLayout.floorLift)
        }
        .compositingGroup()
        .frame(width: L.screenWidth, height: L.screenHeight)
        .allowsHitTesting(false)
    }
}

struct OrbitRowsBackdrop: View {
    let url: String?
    /// The page's black under it (off where the page has its own ground).
    var opaque = true
    /// Its colours told to a mirror too (the views that show the same wash).
    var mirror: OrbitWashMirror? = nil
    /// The wait for the remote to rest before the colour changes (ms). Home's own rows already wait
    /// for their slide's end before they tell the page a new title: none again here.
    var rest: Int = OrbitRowsBackdrop.wait

    /// Steven (device: the art behind the rows looked overloaded): no image any more — a soft wash
    /// of the focused title's dominant colour from the top right, fading into the page (as the
    /// Top 10's ranks take their poster's colour).
    /// Two washes cross-fading (one in, the other out, on the same curve). Steven: the colour went
    /// through black (none under the new one), then rose and suddenly darkened (two washes stacked,
    /// then one) — the two now always add up to one.
    @State private var tone = OrbitWashTone()

    private func wash(_ color: Color?) -> some View {
        // Steven (2026-10-29: the left too dark): the light from the top's middle, wider — the whole
        // screen in the title's colour, evenly.
        RadialGradient(colors: [(color ?? .clear).opacity(color == nil ? 0 : 0.38),
                                (color ?? .clear).opacity(color == nil ? 0 : 0.22),
                                (color ?? .clear).opacity(color == nil ? 0 : 0.08)],
                       center: UnitPoint(x: 0.5, y: 0.0), startRadius: 0, endRadius: 1900)
            // (Drawn once into its own texture: its cross-fade only fades a picture.)
            .drawingGroup()
    }

    var body: some View {
        let L = OrbitHomeLayout.self
        ZStack {
            OrbitToneWash(tone: tone)
            // Steven (2026-10-29, trying it): the even wash a little darker towards the bottom.
            LinearGradient(colors: [.clear, .black.opacity(OrbitHomeLayout.footShade)], startPoint: UnitPoint(x: 0.5, y: 0.4), endPoint: .bottom)
            OrbitGrain()
            Color.white.opacity(OrbitHomeLayout.floorLift)
        }
        // (Steven, 2026-10-30, slow-motion video: the TV still missed frames near the end of each
        // step, as the colour changed — the whole screen redrawn off-screen every frame of the fade.
        // No group pass now, and the colour waits for the slide's end, about half a second.)
        .frame(width: L.screenWidth, height: L.screenHeight)
        .task(id: url ?? "-") {
            guard let url else { return }
            OrbitTrace.log("wash task start mirror=\(mirror != nil) url=\(url)")
            // Steven (device: still a hitch Left / Right): the wash follows the title once the
            // remote rests — a full-screen colour change animating under every step was part of it.
            // (Steven, 2026-10-29: smoother as it was — 300 ms and 0.6 s again.)
            // Steven (2026-10-29, slow-motion video: a little shake as a row's slide ends): the TV
            // missed two or three frames about 0.3 s into each slide — the wash changing colour
            // (two full-screen washes, the headings) while the row still moved; the slide then
            // caught up in a jump. The colour now changes once the slide has ended (about 0.5 s).
            // Steven (2026-10-29, the rows now UIKit — their slides no longer held up by a redraw):
            // more reactive again, 250 ms, and the headings' bar with the wash, on its curve.
            // (Steven, 2026-10-31, video: Home black ~1 s down from the hero, and every colour
            // slow — two waits in a row: the row's, then this one again.)
            // (Steven, 2026-10-31: Découvrir slower to change colour than Home — Home's colours are
            // worked out ahead; here the colour is now worked out during the wait, not after it.)
            async let worked = OrbitDominantColor.color(for: url)
            if rest > 0 {
                do { try await Task.sleep(for: .milliseconds(rest)) } catch { return }
            }
            if let color = await worked, !Task.isCancelled {
                OrbitTrace.log("wash colour ready mirror=\(mirror != nil) \(color.description) url=\(url)")
                show(color)
                // (Only the Home on screen: the hidden one's colour no longer reaches the headings.)
                if opaque, mirror != nil {
                    withAnimation(.easeInOut(duration: Self.fade)) { OrbitHomeTone.shared.color = color }
                }
            }
        }
        .allowsHitTesting(false)
        // Becoming the page shown: the band takes this wash's colours at once.
        .onChange(of: mirror.map(ObjectIdentifier.init), initial: true) { _, id in
            guard id != nil, let mirror else { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { mirror.tone = tone }
        }
    }

    /// The wait once the focus rests, and the cross-fade (the headings' bar on the same curve).
    /// (Steven, 2026-10-31: "remets le réglage d'avant, celui qui était nickel, et fais pareil pour
    /// Rechercher et Découvrir": the validated 0.45 s of commit 8b81393, the same on every page.)
    static let wait = 450
    // (Steven, 2026-10-30: the colours too slow to change — the fade shorter; the wait stays at
    // 0.45 s so it still starts once the row has stopped.)
    // (Steven, 2026-10-31: "moins brutale" — tried at 0.55 s; the brutality was the dip half-way
    // (two see-through washes), now gone — back to his validated 0.3 s.)
    static let fade: Double = 0.3

    private func show(_ color: Color) {
        let next = tone.heading(to: color)
        OrbitTrace.log("wash show \(color.description) from h=\(tone.hue) to h=\(next.hue)")
        if next == tone { return }
        // (A grey reached from nothing, or a first colour: its hue set at once, only its presence fades.)
        if tone.presence < 0.01 {
            var still = Transaction()
            still.disablesAnimations = true
            var start = next
            start.presence = 0
            withTransaction(still) { tone = start; mirror?.tone = start }
        }
        // One wash whose colour travels — a new colour mid-way simply turns it towards the new one.
        withAnimation(.easeInOut(duration: Self.fade)) {
            tone = next
            mirror?.tone = next
        }
    }
}

/// Steven (2026-10-25, Search / Library / Discover in Orbit's language): the focused title's art
/// faded in top right behind a page, as on Home (its add-on art, else TMDB's backdrop).
struct OrbitFocusBackdrop: View {
    let item: MetaPreview?
    @ObservedObject private var metaStore = OrbitMetaStore.shared

    /// The title whose catalog art may be used (TMDB's never came in time).
    @State private var fallbackFor: String?

    var body: some View {
        let banner: String? = item?.banner
        // Steven (Search: an English backdrop for a second): TMDB's art in his language first; the
        // catalog's only if TMDB has none after a moment (the previous art stays meanwhile).
        let tmdb = item.flatMap { metaStore.meta(for: $0)?.backdrop }
        let catalog = (banner?.isEmpty == false && fallbackFor == item?.id) ? banner : nil
        OrbitRowsBackdrop(url: tmdb ?? catalog, opaque: false)
            .task(id: item?.id ?? "-") {
                guard let item else { return }
                metaStore.request([item])
                try? await Task.sleep(for: .milliseconds(700))
                if !Task.isCancelled { fallbackFor = item.id }
            }
    }
}

/// Orbit Home's last built rows and what they were built from (a reference: updating it never
/// re-renders the page).
final class OrbitRowsCache {
    var key: String?
    var rows: [OrbitRow] = []
}

/// Fluidity (Steven, 2026-10-25, before the IPA): what a platform page's rows are made of — his
/// catalogs (compared by their own equality key, no Kotlin list read), the page's filter, the TMDB
/// extras and any page switch. The rows are rebuilt only when it changes.
struct OrbitRowsKey: Equatable {
    var rows: [FolderStripRow]
    var filter: String?
    var extras: [OrbitPlatformExtrasModel.Extra] = []
    var variant: String = ""
    /// The rows' types (the Films / Séries filter reads them; not in a row's own equality key).
    private var types: [String?]

    init(rows: [FolderStripRow], filter: String?, extras: [OrbitPlatformExtrasModel.Extra] = [], variant: String = "") {
        self.rows = rows
        self.filter = filter
        self.extras = extras
        self.variant = variant
        types = rows.map(\.contentType)
    }
}

/// One page's last built value for an `OrbitRowsKey` (a reference: updating it never re-renders).
final class OrbitRowsMemo<Value> {
    private var key: OrbitRowsKey?
    private var value: Value?

    func get(_ key: OrbitRowsKey, _ make: () -> Value) -> Value {
        if let value, self.key == key { return value }
        let built = make()
        self.key = key
        value = built
        return built
    }
}


/// Steven (2026-10-31, on trial: "on enlèvera si ça me va pas"): a grain too fine to see over the
/// large soft gradients — each pixel nudged a level or two lighter or darker at random, which breaks
/// the steps (bands) a smooth gradient shows on a large panel. One small picture made once, tiled at
/// the screen's own pixels, drawn as it is (no filter, no blending pass).
struct OrbitGrain: View {
    /// Off: no grain anywhere (Steven's trial).
    static let enabled = false  // (Steven, 2026-10-31: "c'est même plus marqué" — off.)

    var body: some View {
        if Self.enabled, let tile = Self.tile {
            Image(uiImage: tile)
                .resizable(resizingMode: .tile)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// 128×128 screen pixels of white or black dots, each at 0 to ~1.6 % opacity.
    private static let tile: UIImage? = {
        let side = 128
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt32 = 0x9E3779B9
        for i in 0..<(side * side) {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            let alpha = UInt8(seed % 5)            // 0…4 of 255
            let white = (seed >> 8) & 1 == 1
            // Premultiplied: a white dot carries its alpha in its colour, a black one none.
            let c: UInt8 = white ? alpha : 0
            bytes[i * 4] = c; bytes[i * 4 + 1] = c; bytes[i * 4 + 2] = c; bytes[i * 4 + 3] = alpha
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cg, scale: UIScreen.main.scale, orientation: .up)
    }()
}
