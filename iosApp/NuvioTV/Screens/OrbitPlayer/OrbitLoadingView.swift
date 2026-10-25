import SwiftUI

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
                        mark.opacity(Self.breath(at: now))
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
