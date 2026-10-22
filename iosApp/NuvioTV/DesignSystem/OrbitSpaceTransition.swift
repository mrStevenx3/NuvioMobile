import SwiftUI

/// Steven's fork (Orbit bar): the "portal" — a short Orbit-logo transition when the bar enters
/// Plateformes / Studios from another page, or leaves them for another page (never between those
/// two). The logo fades in on black, then the planet's tilted ring opens out of it and uncovers the
/// page as it grows (the collection intro's "logo big on black" language). Drawn over the whole
/// screen by `OrbitTopBar`, never hit-tested and never focusable, so the remote keeps working.
struct OrbitSpaceTransition: View {
    let onDone: () -> Void

    // Portal
    @State private var black: Double = 0
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.7
    @State private var hole: CGFloat = 0
    @State private var ringOpacity: Double = 0
    private static let logoWidth: CGFloat = 760
    private static let ringAspect: CGFloat = 0.42
    private static let ringTilt = Angle.degrees(-14)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            ZStack {
                portal(size: size, centre: centre)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: run)
    }

    // MARK: Portal

    @ViewBuilder
    private func portal(size: CGSize, centre: CGPoint) -> some View {
        Color.black
            .opacity(black)
            .mask {
                ZStack {
                    Rectangle()
                    Ellipse()
                        .frame(width: hole * 2, height: hole * 2 * Self.ringAspect)
                        .rotationEffect(Self.ringTilt)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
        Ellipse()
            .stroke(Color.white, lineWidth: 10)
            .frame(width: max(hole, 1) * 2, height: max(hole, 1) * 2 * Self.ringAspect)
            .rotationEffect(Self.ringTilt)
            .opacity(ringOpacity)
        wordmark
            .frame(width: Self.logoWidth)
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
    }

    private var wordmark: some View {
        Image("OrbitWordmark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }

    // MARK: Timeline

    private func run() {
            withAnimation(.easeOut(duration: 0.2)) {
                black = 1
                logoOpacity = 1
                logoScale = 1
            }
            after(0.42) {
                ringOpacity = 1
                withAnimation(.easeIn(duration: 0.6)) {
                    hole = 2400
                    logoScale = 1.3
                    logoOpacity = 0
                }
                withAnimation(.easeIn(duration: 0.6).delay(0.2)) { ringOpacity = 0 }
            }
            after(1.1) { onDone() }
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
