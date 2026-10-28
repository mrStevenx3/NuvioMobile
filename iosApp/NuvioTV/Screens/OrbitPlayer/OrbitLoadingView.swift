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
                                     decodeSize: .points(width: 960, height: 540))
                        .ignoresSafeArea()
                        .opacity(0.2)
                        .blur(radius: 34)
                }
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    let now = timeline.date
                    VStack(spacing: 40) {
                        mark
                            .brightness(lit ? 0 : -0.45)
                            .shadow(color: (tone ?? .white).opacity(glow), radius: 44)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.7)) { lit = true }
                withAnimation(.easeOut(duration: 0.45)) { glow = 0.85 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 1.2)) { glow = 0.3 }
                }
            }
        }
        .task(id: backdropUrl ?? "-") {
            guard let backdropUrl, !backdropUrl.isEmpty else { return }
            tone = await OrbitDominantColor.color(for: backdropUrl)
        }
    }

    /// 0.5 → 1 → 0.5, the same phase for every instance (wall clock).
    private static func breath(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return 0.75 - 0.25 * cos(t * 2 * .pi)
    }

    @ViewBuilder
    private var mark: some View {
        if let logoUrl, !logoUrl.isEmpty {
            CachedAsyncImage(string: logoUrl, contentMode: .fit, decodeSize: .points(width: 640, height: 260))
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
}
