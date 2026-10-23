import Combine
import SharedCore
import SwiftUI

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
        if t.contains("hdr") { out.insert(.hdr) }
        if t.contains("atmos") { out.insert(.atmos) }
        return out
    }
}

@MainActor
final class OrbitQualityModel: ObservableObject {
    @Published private(set) var found: OrbitQuality = []
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

    var body: some View {
        HStack(spacing: 10) {
            // Always the best definition the sources have, one badge.
            if quality.contains(.uhd) {
                badge("4K")
            } else if quality.contains(.fullHD) {
                badge("Full HD")
            } else if quality.contains(.hd) {
                badge("HD")
            } else if quality.contains(.sd) {
                badge("SD")
            }
            if quality.contains(.dolbyVision) {
                badge("Dolby Vision")
            } else if quality.contains(.hdr10Plus) {
                badge("HDR10+")
            } else if quality.contains(.hdr) {
                badge("HDR")
            }
            if quality.contains(.atmos) { badge("Dolby Atmos") }
        }
    }

    private func badge(_ text: String) -> some View {
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
