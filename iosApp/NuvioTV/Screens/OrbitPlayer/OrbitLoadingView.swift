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
                        mark
                            // (Steven, 2026-10-29: still a glow — the halo behind the logo, white then the
                            // film's colour once read, changed under his eyes. No halo: the logo alone.)
                            // Steven (2026-10-29, later: "le logo se place au centre et s'illumine"): come
                            // to the middle a little dim, it lights up once — no pulse, no halo.
                            .brightness(Self.dimming(at: now))
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
            if let started = Self.lightStartedAt, Date().timeIntervalSince(started) < 3 { return }
            Self.lightStartedAt = Date().addingTimeInterval(0.1)
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
    static let lightDuration: Double = 1.1

    /// The logo's dimming at `date` (−0.45: off, 0: lit), on an ease-out over `lightDuration`.
    static func dimming(at date: Date) -> Double {
        guard let start = lightStartedAt else { return 0 }
        let t = min(1, max(0, date.timeIntervalSince(start) / lightDuration))
        let eased = 1 - pow(1 - t, 3)
        return -0.45 * (1 - eased)
    }
}
