import OrbitEngine
import SwiftUI
import UIKit

// What Orbit draws over Apple's player (Steven's mockup, 2026-10-25). None of it is focusable or
// hit-tested: the remote always reaches the player underneath.

/// Paused: the title's logo top left, its details, the end time.
struct OrbitPauseCard: View {
    let context: PlaybackContext
    @ObservedObject var session: OrbitPlayerSession

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0)],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4))
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                title
                if !details.isEmpty {
                    Text(details.joined(separator: "  ·  "))
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                // Steven: no picture / sound formats on the pause card.
                if let endsAt = OrbitPlayerText.endsAt(remainingSec: session.durationSec - session.positionSec) {
                    Text(endsAt)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .padding(.leading, 96)
            .padding(.top, 84)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var title: some View {
        if let logo = context.logo, !logo.isEmpty {
            // Steven: the details right under the title — the logo takes its own height (no empty
            // box under a wide logo).
            OrbitTitleMark(name: context.title, logo: logo, maxSize: CGSize(width: 560, height: 160), textSize: 64,
                           hugsLogo: true)
        } else {
            Text(context.title)
                .font(.system(size: 64, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .frame(maxWidth: 1000, alignment: .leading)
        }
    }

    /// Steven ("130 minutes" for Superman): hours and minutes — "2 h 10", "45 min".
    static func hoursAndMinutes(_ runtime: String) -> String {
        let digits = runtime.prefix { $0.isNumber }
        guard let minutes = Int(digits), minutes > 0,
              !runtime.contains("h") else { return runtime }
        if minutes < 60 { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : String(format: "%d h %02d", minutes / 60, rest)
    }

    private var details: [String] {
        var parts: [String] = []
        if let line = OrbitPlayerText.episodeLine(context) { parts.append(line) }
        if let year = context.meta?.year { parts.append(year) }
        if let runtime = context.meta?.runtime { parts.append(Self.hoursAndMinutes(runtime)) }
        if let genre = context.meta?.genres.first { parts.append(genre) }
        return parts
    }

    private var badges: [String] {
        var list: [String] = []
        if let video = OrbitPlayerText.videoBadge(session.videoFormat) { list.append(video) }
        if OrbitPlayerText.hasHeights(session.activeAudioTrack) {
            list.append(OrbitPlayerText.audioFormat(session.activeAudioTrack!).uppercased())
        }
        return list
    }
}

/// The next episode: a small card bottom right, above Apple's action buttons.
struct OrbitUpNextCard: View {
    let caption: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ÉPISODE SUIVANT")
                .font(.system(size: 20, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(Color.white.opacity(0.6))
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
            }
            Text(caption)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
        }
        .padding(28)
        .frame(width: 520, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(OrbitGlass.tint))
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(OrbitGlass.rim, lineWidth: 1.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 96)
        .padding(.bottom, 200)
        .allowsHitTesting(false)
    }
}

/// A format badge on the pause card: Orbit's own logos (the same as on a title's page) for Dolby
/// Vision, Dolby Atmos and HDR10(+) — Steven (device): they were text — else the framed text.
private struct OrbitPlayerBadge: View {
    let text: String

    private var asset: (name: String, height: CGFloat)? {
        let t = text.uppercased()
        if t.contains("DOLBY VISION") { return ("orbit-badge-dolby-vision", 34) }
        if t.contains("ATMOS") { return ("orbit-badge-dolby-atmos", 34) }
        if t == "HDR10+" { return ("orbit-badge-hdr10plus", 28) }
        if t == "HDR10" { return ("orbit-badge-hdr10", 28) }
        return nil
    }

    var body: some View {
        if let asset, let image = UIImage(named: asset.name), image.size.height > 0 {
            Image(asset.name)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: asset.height)
                .foregroundStyle(Color.white.opacity(0.92))
                .accessibilityLabel(text)
        } else {
            Text(text)
                .font(.system(size: 18, weight: .heavy))
                .kerning(1)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.75), lineWidth: 2))
        }
    }
}
