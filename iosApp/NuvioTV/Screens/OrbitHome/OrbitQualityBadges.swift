import Combine
import SharedCore
import SwiftUI
import UIKit

// Orbit Detail (Steven, 2026-10-23): the best quality the viewer's own sources offer for the title,
// shown on the hero beside the meta line — the best definition (4K, else Full HD, HD, SD), Dolby
// Vision (else HDR10+ / HDR), Dolby Atmos.
// The page asks the source add-ons for the title's streams once as it opens (the source picker
// asks again when Play is pressed) and reads the tags from each stream's name / title /
// description. A badge only ever appears (once seen it stays for the visit).

nonisolated struct OrbitQuality: OptionSet, Sendable, Equatable {
    let rawValue: Int
    static let uhd = OrbitQuality(rawValue: 1 << 0)
    static let dolbyVision = OrbitQuality(rawValue: 1 << 1)
    static let hdr10Plus = OrbitQuality(rawValue: 1 << 2)
    static let hdr = OrbitQuality(rawValue: 1 << 3)
    static let atmos = OrbitQuality(rawValue: 1 << 4)
    static let fullHD = OrbitQuality(rawValue: 1 << 5)
    static let hd = OrbitQuality(rawValue: 1 << 6)
    static let sd = OrbitQuality(rawValue: 1 << 7)
    static let hdr10 = OrbitQuality(rawValue: 1 << 8)

    /// The one quality a badge rule's name stands for ("Dolby Vision", "DV", "4K", "Atmos"…).
    static func single(_ name: String) -> OrbitQuality? {
        let read = read(name)
        for flag in [OrbitQuality.dolbyVision, .hdr10Plus, .hdr10, .atmos, .uhd, .fullHD, .hd, .sd, .hdr] where read.contains(flag) {
            return flag
        }
        return nil
    }

    /// Tags read in one stream's text.
    static func read(_ text: String) -> OrbitQuality {
        let t = " " + text.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .replacingOccurrences(of: "|", with: " ") + " "
        var out: OrbitQuality = []
        if t.contains("2160") || t.contains(" 4k") || t.contains("uhd") { out.insert(.uhd) }
        if t.contains("1080") || t.contains("fhd") || t.contains("full hd") { out.insert(.fullHD) }
        if t.contains("720p") || t.contains(" 720 ") { out.insert(.hd) }
        if t.contains("480p") || t.contains("576p") || t.contains(" sd ") || t.contains("dvdrip") { out.insert(.sd) }
        if t.contains("dolby vision") || t.contains("dovi") || t.contains(" dv ") || t.contains("hdr dv")
            || t.contains("dv hdr") || t.contains(" dv+") || t.contains("+dv") { out.insert(.dolbyVision) }
        if t.contains("hdr10+") || t.contains("hdr10plus") || t.contains("hdr10 plus") { out.insert(.hdr10Plus) }
        // HDR10 alone (many films have only it): "hdr10" not followed by "+" / "plus".
        if t.replacingOccurrences(of: "hdr10+", with: "").replacingOccurrences(of: "hdr10plus", with: "")
            .replacingOccurrences(of: "hdr10 plus", with: "").contains("hdr10") { out.insert(.hdr10) }
        if t.contains("hdr") { out.insert(.hdr) }
        if t.contains("atmos") { out.insert(.atmos) }
        return out
    }
}

@MainActor
final class OrbitQualityModel: ObservableObject {
    @Published private(set) var found: OrbitQuality = []
    /// Steven: the logos his badge rules (regex import) already give the streams — the image of
    /// each quality, by its flag's raw value.
    @Published private(set) var logos: [Int: String] = [:]
    private var watcher: FlowWatcher?
    private var requested: String?
    private var pending: Task<Void, Never>?
    /// Streams already read, per add-on group (only the new ones are read on each update).
    private var readCount: [String: Int] = [:]

    /// The badges seen this session per title, shown at once on a return (half an hour).
    private static var memory: [String: (quality: OrbitQuality, at: Date)] = [:]

    func start(type: String, videoId: String, parentMetaId: String?, season: Int?, episode: Int?) {
        let key = "\(type):\(videoId)"
        guard requested != key else { return }
        requested = key
        readCount = [:]
        found = Self.memory[key].flatMap { Date().timeIntervalSince($0.at) < 1800 ? $0.quality : nil } ?? []
        watcher?.cancel()
        pending?.cancel()
        // Steven: never at the page's expense — the request goes out once the page has settled.
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, let self else { return }
            self.watcher = FlowWatcherKt.watch(StreamsRepository.shared.uiState) { [weak self] emitted in
                guard let self, let state = emitted as? StreamsUiState else { return }
                var seen = self.found
                for group in state.groups {
                    let done = self.readCount[group.addonId] ?? 0
                    let streams = group.streams
                    guard streams.count > done else { continue }
                    for stream in streams[done...] {
                        let text = [stream.name, stream.title, stream.description_, stream.streamLabel]
                            .compactMap { $0 }.joined(separator: " ")
                        seen.formUnion(OrbitQuality.read(text))
                        for badge in stream.badges where !badge.imageURL.isEmpty {
                            let flag = OrbitQuality.single(badge.name)
                            if let flag, self.logos[flag.rawValue] == nil {
                                self.logos[flag.rawValue] = badge.imageURL
                            }
                        }
                    }
                    self.readCount[group.addonId] = streams.count
                }
                if seen != self.found {
                    Self.memory[key] = (seen, Date())
                    withAnimation(.easeInOut(duration: 0.3)) { self.found = seen }
                }
            }
            // The same request the source picker makes (manual selection, the same ids), so when
            // Lire is pressed the repository already holds the answer and the list shows at once.
            // With "auto-play the first source" on, the picker asks its own way (it re-fetches).
            StreamsRepository.shared.load(type: type, videoId: videoId, parentMetaId: parentMetaId,
                                          season: season.map { KotlinInt(int: Int32($0)) },
                                          episode: episode.map { KotlinInt(int: Int32($0)) },
                                          manualSelection: true)
        }
    }

    func stop() {
        pending?.cancel()
        watcher?.cancel()
        watcher = nil
    }
}

/// The badges, Apple TV style: outlined, small, after the meta line.
struct OrbitQualityBadges: View {
    let quality: OrbitQuality
    /// The badge rules' own images, by flag (see `OrbitQualityModel.logos`).
    var logos: [Int: String] = [:]

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            // Always the best definition the sources have, one badge.
            if quality.contains(.uhd) {
                badge("4K", asset: "orbit-badge-4k", flag: .uhd)
            } else if quality.contains(.fullHD) {
                badge("Full HD", asset: "orbit-badge-fullhd", flag: .fullHD)
            } else if quality.contains(.hd) {
                badge("HD", asset: "orbit-badge-hd", flag: .hd)
            } else if quality.contains(.sd) {
                badge("SD", asset: "orbit-badge-sd", flag: .sd)
            }
            if quality.contains(.dolbyVision) {
                badge("Dolby Vision", asset: "orbit-badge-dolby-vision", flag: .dolbyVision)
            } else if quality.contains(.hdr10Plus) {
                badge("HDR10+", asset: "orbit-badge-hdr10plus", flag: .hdr10Plus)
            } else if quality.contains(.hdr10) {
                badge("HDR10", asset: "orbit-badge-hdr10", flag: .hdr10)
            } else if quality.contains(.hdr) {
                badge("HDR", asset: "orbit-badge-hdr", flag: .hdr)
            }
            if quality.contains(.atmos) { badge("Dolby Atmos", asset: "orbit-badge-dolby-atmos", flag: .atmos) }
        }
    }

    /// Steven's official logo when its image is in the asset catalog (`asset`, drawn white),
    /// else the text badge.
    @ViewBuilder
    private func badge(_ text: String, asset: String, flag: OrbitQuality) -> some View {
        // Steven's own logo files first (the regex logos looked poor: small, padded, uneven).
        if let image = UIImage(named: asset), image.size.height > 0 {
            // Each logo at its height, but never wider than 80 pt (the wide marks come down).
            let aspect = image.size.width / image.size.height
            let height = min(Self.logoHeight(asset), 80 / aspect)
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: height * aspect, height: height)
                // Steven: every technical badge in a thin rounded frame, the age box's own stroke;
                // the Full HD and HDR10 marks are boxes already, the Dolby marks stay free.
                .modifier(OrbitBadgeFrame(on: Self.framed(flag)))
                .accessibilityLabel(text)
                .transition(.opacity)
        } else {
            textBadge(text)
        }
    }

    static func framed(_ flag: OrbitQuality) -> Bool {
        // Everything but the Dolby marks, and the Full HD and HDR10 marks (boxes already).
        flag == .uhd || flag == .hd || flag == .sd || flag == .hdr10Plus || flag == .hdr
    }

    /// Each logo's height, so they read at one size side by side: the two-line Dolby marks and
    /// the boxed 1080p taller, the wide HDR10+ lower.
    static func logoHeight(_ asset: String) -> CGFloat {
        switch asset {
        case "orbit-badge-dolby-vision", "orbit-badge-dolby-atmos": return 28
        case "orbit-badge-fullhd": return 28
        case "orbit-badge-4k": return 13
        case "orbit-badge-hdr10plus": return 12
        case "orbit-badge-hdr": return 13
        case "orbit-badge-sd", "orbit-badge-hd": return 13
        default: return 20
        }
    }

    private func textBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .heavy))
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.8))
            .transition(.opacity)
    }
}

/// The definition badge's frame: the meta line's age box stroke, a little air around the mark,
/// as tall as the Dolby marks beside it.
private struct OrbitBadgeFrame: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.8), lineWidth: 2))
        } else {
            content
        }
    }
}
