import Combine
import SwiftUI
import UIKit

// Orbit Studios (Steven, 2026-10-23): the Studios page draws its own backdrop instead of the
// shared stage. The stage waits for a rest and keeps the last art when a folder has none, so the
// Lucasfilm still (Darth Vader) stayed behind Marvel, DreamWorks and Pixar, and the page opened on
// a bare slate until a tile took focus. Here the focused studio's backdrop crossfades in at once
// (the first studio's as the page opens) and a studio without one fades back to the slate.

struct OrbitStudiosBackdrop: View {
    let url: String?

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var shownURL: String?

    static let slate = Color(red: 31 / 255, green: 38 / 255, blue: 48 / 255)

    var body: some View {
        let size = CGSize(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
        ZStack {
            Self.slate
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .id(shownURL ?? "-")
                    .transition(.opacity)
                // Steven: the bottom of the art blurred, under the tiles.
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .blur(radius: 36, opaque: true)
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.6),
                            .init(color: .black, location: 0.84),
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .id("blur-\(shownURL ?? "-")")
                    .transition(.opacity)
            }
            // The logo (top left) and the tiles (bottom) stay legible on any art.
            LinearGradient(stops: [
                .init(color: .black.opacity(0.55), location: 0),
                .init(color: .black.opacity(0.15), location: 0.5),
                .init(color: .clear, location: 0.75),
            ], startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [
                .init(color: .clear, location: 0.45),
                .init(color: .black.opacity(0.7), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .animation(.easeInOut(duration: 0.3), value: shownURL)
        .task(id: url ?? "-") { await load(size: size) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func load(size: CGSize) async {
        guard let url, let address = URL(string: url) else {
            image = nil
            shownURL = nil
            return
        }
        let request = ArtworkDecodeRequest(size: .points(width: size.width, height: size.height),
                                           fill: true, scale: displayScale)
        if let cached = ArtworkStore.cached(address, decode: request) {
            image = cached
            shownURL = url
            return
        }
        guard let fetched = try? await ArtworkStore.fetch(address, decode: request), !Task.isCancelled else { return }
        image = fetched
        shownURL = url
    }
}
