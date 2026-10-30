import SwiftUI
import UIKit

// Orbit's one loading screen (Steven, 2026-10-25): black, the title's backdrop faint behind, its logo
// breathing in the middle; nothing technical. Only when it lasts does a quiet "Encore un instant…"
// appear. The source page (finding and preparing a source) and the player (opening it) both draw
// it, and the breathing is read off the wall clock, so going from one to the other shows no seam.

struct OrbitLoadingView: View {
    let title: String
    let logoUrl: String?
    let backdropUrl: String?
    /// The close-time hold (the page leaving after a player): plain black, no logo.
    var plain = false
    /// The logo lights up as the screen opens (off: it opens lit — the player's, taking over from
    /// the sources' page already lit).
    var lightsUp = true

    @State private var appearedAt = Date()
    /// Steven (2026-10-28, B): the logo comes up dim and lights up, a glow in the film's own colour
    /// (as the platforms' logos switch on), then breathes.
    @State private var lit = false
    /// The light-up's start this screen follows (the one already begun, from its first frame).
    @State private var lightStart: Date? = OrbitLoadingView.lightStartedAt
    @State private var glow: Double = 0
    @State private var tone: Color?

    /// Steven (2026-10-28: the loading screen came up black, its art a moment later): the art
    /// fetched ahead, at the loading screen's own size, so it is there from its first frame.
    @MainActor static func prefetch(_ raw: String?) {
        guard let raw, !raw.isEmpty, let url = URL(string: raw) else { return }
        let request = ArtworkDecodeRequest(size: .points(width: 960, height: 540), fill: true,
                                           scale: UIScreen.main.scale).normalized
        guard ArtworkStore.cached(url, decode: request) == nil else { return }
        Task { _ = try? await ArtworkStore.fetch(url, decode: request) }
    }

    /// The logo fetched ahead at the loading screen's own size (Lecture's glide draws this very image).
    @MainActor static func prefetchLogo(_ raw: String?) {
        guard let raw, !raw.isEmpty, let url = URL(string: raw) else { return }
        let request = ArtworkDecodeRequest(size: .points(width: 640, height: 260), fill: false,
                                           scale: UIScreen.main.scale).normalized
        guard ArtworkStore.cached(url, decode: request) == nil else { return }
        Task { _ = try? await ArtworkStore.fetch(url, decode: request) }
    }

    /// The logo as the loading screen draws it (Lecture's glide ends on exactly this).
    @ViewBuilder
    static func logo(_ logoUrl: String?, title: String) -> some View {
        if let logoUrl, !logoUrl.isEmpty {
            // (Steven, 2026-10-29: a grey rectangle behind the title the first time — the loader's
            // shimmer while the logo was not fetched yet. Nothing while it comes; its name if it fails.)
            CachedAsyncImage(string: logoUrl, contentMode: .fit, decodeSize: .points(width: 640, height: 260),
                             loading: { Color.clear },
                             failure: {
                                 Text(title)
                                     .font(.system(size: 64, weight: .heavy))
                                     .foregroundStyle(Color.white)
                                     .multilineTextAlignment(.center)
                                     .lineLimit(3)
                             })
                .frame(maxWidth: 640, maxHeight: 260)
        } else {
            Text(title)
                .font(.system(size: 64, weight: .heavy))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 1200)
        }
    }

    /// A message after this long.
    static let slowAfter: TimeInterval = 8
    /// One breath, in seconds.
    private static let period: Double = 2.4

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !plain {
                if let backdropUrl, !backdropUrl.isEmpty {
                    CachedAsyncImage(string: backdropUrl, contentMode: .fill,
                                     decodeSize: .points(width: 960, height: 540),
                                     loading: { Color.clear }, failure: { Color.clear })
                        .ignoresSafeArea()
                        .opacity(0.2)
                        .blur(radius: 34)
                }
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    let now = timeline.date
                    VStack(spacing: 40) {
                        // Steven (2026-10-29: "le logo se place au centre et s'illumine"): come to the
                        // middle a little dim, it lights up once — no pulse, no halo.
                        // Steven (2026-10-30: "ça arrive par saccade"): the light was worked out frame by
                        // frame on the main thread, busy opening the film then — it stepped. A dimmed
                        // copy over the logo now fades out on the screen's own animator, smooth
                        // whatever the app is doing.
                        mark
                            // Steven (2026-10-30: "quand il s'éclaire il faudrait qu'il y ait un halo
                            // autour"): a soft glow of the logo's own colours rises with the light.
                            .background { OrbitHaloRise(start: lightStart) { mark }.padding(-90) }
                            .overlay {
                                OrbitDimFade(start: lightStart,
                                             dimFully: lightsUp && Self.lightIsStale(at: Date(), start: lightStart)) {
                                    mark
                                }
                            }
                            .opacity(Self.breath(at: now))
                        Text("Encore un instant…")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .opacity(now.timeIntervalSince(appearedAt) > Self.slowAfter ? 1 : 0)
                            .animation(.easeInOut(duration: 0.6), value: now.timeIntervalSince(appearedAt) > Self.slowAfter)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel(Text("Chargement"))
        .onAppear {
            guard !plain else { return }
            // Steven (2026-10-30: the logo lit "d'un coup sec", not little by little): the source was
            // found before the light-up ended, and the player's own screen took over already lit. The
            // light is read off the wall clock from when it began, so the player's screen carries it
            // on where the sources' page left it.
            if !lightsUp {
                lit = true
                glow = 0.3
                return
            }
            lit = false
            // (The same opening seen again — the page drawn anew — does not dim the logo again.)
            if let started = Self.lightStartedAt, Date().timeIntervalSince(started) < 3 {
                lightStart = started
                return
            }
            Self.lightStartedAt = Date().addingTimeInterval(0.1)
            lightStart = Self.lightStartedAt
        }
        .task(id: backdropUrl ?? "-") {
            guard let backdropUrl, !backdropUrl.isEmpty else { return }
            tone = await OrbitDominantColor.color(for: backdropUrl)
        }
    }

    /// Steven (2026-10-29: "la lueur qui s'éclaircit et s'assombrit n'apporte rien", the film comes
    /// quickly): the logo stays lit, steady — the film's start is marked by the logo bursting open
    /// instead (`PlayerScreen`). (Kept as a function: Lecture's glide ends on it.)
    static func breath(at date: Date) -> Double { 1 }

    /// The old breath: 0.5 → 1 → 0.5, the same phase for every instance (wall clock).
    static func oldBreath(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return 0.75 - 0.25 * cos(t * 2 * .pi)
    }

    private var mark: some View { Self.logo(logoUrl, title: title) }

    /// When the logo began to light up (the sources' page); the player's screen goes on from it.
    nonisolated(unsafe) static var lightStartedAt: Date?
    /// (Steven, 2026-10-30: "il arrive trop sombre au début pendant longtemps" — less dark, lit sooner.)
    /// (Then "trop illuminé au début, on ne le voit pas s'éclairer": between the two — dim enough to
    /// be seen lighting up, the light even over its time instead of all at its start.)
    static let lightDuration: Double = 0.9
    /// The dimmed copy's darkening (was −0.45, then −0.25).
    static let dimLevel: Double = -0.38

    /// No light-up begun lately (none yet, or one from an earlier opening).
    static func lightIsStale(at date: Date, start: Date? = OrbitLoadingView.lightStartedAt) -> Bool {
        guard let start else { return true }
        return date.timeIntervalSince(start) > 3
    }

    /// The logo's dimming at `date` (−0.45: off, 0: lit), on an ease-out over `lightDuration`.
    static func dimming(at date: Date) -> Double {
        guard let start = lightStartedAt else { return 0 }
        let t = min(1, max(0, date.timeIntervalSince(start) / lightDuration))
        let eased = 1 - pow(1 - t, 3)
        return dimLevel * (1 - eased)
    }
}


/// A dimmed copy of `content` laid over it, fading out from `start` over the light-up's duration —
/// animated by Core Animation (the render server), so it stays smooth while the main thread is busy.
/// `dimFully`: held dim (no light-up begun yet). No start: not drawn (lit).
struct OrbitDimFade<Content: View>: UIViewRepresentable {
    let start: Date?
    var dimFully = false
    @ViewBuilder let content: () -> Content

    final class Coordinator {
        var host: UIHostingController<AnyView>?
        var key: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        let host = UIHostingController(rootView: AnyView(dimmed))
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        context.coordinator.host = host
        apply(view, context.coordinator)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.host?.rootView = AnyView(dimmed)
        apply(view, context.coordinator)
    }

    private var dimmed: some View {
        content()
            .brightness(OrbitLoadingView.dimLevel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func apply(_ view: UIView, _ coordinator: Coordinator) {
        let key = dimFully ? "dim" : (start.map { "\($0.timeIntervalSinceReferenceDate)" } ?? "lit")
        guard key != coordinator.key else { return }
        coordinator.key = key
        let layer = view.layer
        layer.removeAnimation(forKey: "light")
        if dimFully { layer.opacity = 1; return }
        guard let start else { layer.opacity = 0; return }
        let duration = OrbitLoadingView.lightDuration
        let elapsed = Date().timeIntervalSince(start)
        layer.opacity = 0
        guard elapsed < duration else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fade.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - elapsed
        fade.fillMode = .backwards
        layer.add(fade, forKey: "light")
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}


/// The logo's halo: a blurred, brightened copy of it behind it, rising as the logo lights up
/// (0 → a peak at the light's end → settling a little lower, held) — on Core Animation, like
/// `OrbitDimFade`, so it stays smooth while the film is being opened. Drawn larger than the logo
/// (`spread` all round) so the glow is not cut at its edges. No start, or an old one: held settled.
struct OrbitHaloRise<Content: View>: UIViewRepresentable {
    let start: Date?
    var spread: CGFloat = 90
    @ViewBuilder let content: () -> Content

    static var peak: Float { 0.85 }
    static var settled: Float { 0.6 }
    static var settleDuration: Double { 0.6 }

    final class Coordinator {
        var host: UIHostingController<AnyView>?
        var key: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.clipsToBounds = false
        let host = UIHostingController(rootView: AnyView(glow))
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.clipsToBounds = false
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.frame = view.bounds
        view.addSubview(host.view)
        context.coordinator.host = host
        apply(view, context.coordinator)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.host?.rootView = AnyView(glow)
        apply(view, context.coordinator)
    }

    /// Two blurs of the logo: a close one (the rim's light) and a wide one (the halo).
    private var glow: some View {
        ZStack {
            content().brightness(0.35).saturation(1.3).blur(radius: 46).opacity(0.9)
            content().brightness(0.45).blur(radius: 16).opacity(0.7)
        }
        .padding(spread)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .compositingGroup()
    }

    private func apply(_ view: UIView, _ coordinator: Coordinator) {
        let key = start.map { "\($0.timeIntervalSinceReferenceDate)" } ?? "lit"
        guard key != coordinator.key else { return }
        coordinator.key = key
        let layer = view.layer
        layer.removeAnimation(forKey: "halo")
        layer.opacity = Self.settled
        guard let start else { return }
        let rise = OrbitLoadingView.lightDuration
        let total = rise + Self.settleDuration
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed < total else { return }
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [0, Self.peak, Self.settled]
        anim.keyTimes = [0, NSNumber(value: rise / total), 1]
        anim.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut),
                                CAMediaTimingFunction(name: .easeInEaseOut)]
        anim.duration = total
        anim.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - elapsed
        anim.fillMode = .backwards
        layer.add(anim, forKey: "halo")
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}
