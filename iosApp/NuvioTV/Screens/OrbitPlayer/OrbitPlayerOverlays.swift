import OrbitEngine
import SwiftUI

// What Orbit draws over Apple's player (Steven's mockup, 2026-10-25). None of it is focusable or
// hit-tested: the remote always reaches the player underneath.

/// While the source opens: black, the backdrop faint behind, the title's logo breathing.
struct OrbitPlayerLoading: View {
    let context: PlaybackContext
    @State private var breathing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let backdrop = context.background, !backdrop.isEmpty {
                CachedAsyncImage(string: backdrop, contentMode: .fill,
                                 decodeSize: .points(width: 960, height: 540))
                    .ignoresSafeArea()
                    .opacity(0.22)
                    .blur(radius: 30)
            }
            VStack(spacing: 28) {
                title
                    .opacity(breathing ? 1 : 0.55)
                if let line = OrbitPlayerText.episodeLine(context) {
                    Text(line)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathing = true }
        }
    }

    @ViewBuilder
    private var title: some View {
        if let logo = context.logo, !logo.isEmpty {
            CachedAsyncImage(string: logo, contentMode: .fit, decodeSize: .points(width: 640, height: 260))
                .frame(maxWidth: 640, maxHeight: 260)
        } else {
            Text(context.title)
                .font(.system(size: 64, weight: .heavy))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1200)
        }
    }
}

/// Paused: the title's logo top left, its details, the picture and sound formats, the end time.
struct OrbitPauseCard: View {
    let context: PlaybackContext
    @ObservedObject var session: OrbitPlayerSession

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0)],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4))
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                title
                if !details.isEmpty {
                    Text(details.joined(separator: "  ·  "))
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                if !badges.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(badges, id: \.self) { badge in
                            Text(badge)
                                .font(.system(size: 18, weight: .heavy))
                                .kerning(1)
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.75), lineWidth: 2))
                        }
                    }
                }
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
            CachedAsyncImage(string: logo, contentMode: .fit, decodeSize: .points(width: 560, height: 200))
                .frame(maxWidth: 560, maxHeight: 160, alignment: .leading)
        } else {
            Text(context.title)
                .font(.system(size: 64, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .frame(maxWidth: 1000, alignment: .leading)
        }
    }

    private var details: [String] {
        var parts: [String] = []
        if let line = OrbitPlayerText.episodeLine(context) { parts.append(line) }
        if let year = context.meta?.year { parts.append(year) }
        if let runtime = context.meta?.runtime { parts.append(runtime) }
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
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 96)
        .padding(.bottom, 200)
        .allowsHitTesting(false)
    }
}
