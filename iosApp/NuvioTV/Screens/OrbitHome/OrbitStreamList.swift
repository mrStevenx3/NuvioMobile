import Combine
import SharedCore
import SwiftUI
import UIKit

// Orbit Sources (Steven, 2026-10-24): the source list rebuilt from scratch in the Orbit style.
// What it looks like only: the playback machinery (debrid resolve, auto-play, failover, external
// players) is `StreamPickerView`'s and unchanged.
//
//  - The title's backdrop behind, blurred and dark (the description page's section look): the
//    list feels like part of the title's page.
//  - Top left: the title's logo, "Choisir une source", the episode for a series.
//  - Filters (only those with a match, with their count): Toutes, Instantané, 4K, 1080p,
//    Dolby Vision, HDR.
//  - ONE list, best first: instant (cached on the debrid account, or a direct link) before the
//    rest, then picture (definition, then Dolby Vision > HDR10+ > HDR10 > HDR), then the file
//    size (the same quality bigger = a higher bitrate, a Remux before a WEB-DL).
//  - Each source a card: the quality marks on the left (the page's own badges), the name and the
//    description in the middle (in full on the focused card), the tags read natively from the
//    texts (source, codec, sound, channels, language), the size and "Instantané" on the right.
//    The imported regex badges are no longer drawn here.

// MARK: - Tags read from a stream's texts

nonisolated struct OrbitStreamTags: Equatable, Sendable {
    var quality: OrbitQuality = []
    var source: String?
    var codec: String?
    var audio: String?
    var channels: String?
    var languages: [String] = []
    var sizeBytes: Int64?
    var instant = false
    var notCached = false
    /// The file's name (the description line that ends in .mkv / .mp4…), and its release group.
    var fileName: String?
    var group: String?
    /// The debrid service the source goes through ("AllDebrid"), or "Lien direct".
    var service: String?

    static let services: [String: String] = [
        "AD": "AllDebrid", "RD": "Real-Debrid", "PM": "Premiumize", "TB": "TorBox",
        "DL": "Debrid-Link", "ED": "EasyDebrid", "OC": "Offcloud", "PKP": "PikPak",
        "EN": "Easynews", "SD": "Seedr",
    ]

    /// Source rank: Remux 3, BluRay 2, WEB-DL / WEBRip / WEB 1, other 0.
    var sourceRank: Int {
        switch source {
        case "Remux": return 3
        case "BluRay": return 2
        case "WEB-DL", "WEBRip", "WEB": return 1
        default: return 0
        }
    }

    /// The card's heading: what the file is ("Remux · HYPERION"), not the add-on's name.
    func heading(fallback: String) -> String {
        let kind = source
        switch (kind, group) {
        case let (k?, g?): return "\(k) · \(g)"
        case let (k?, nil): return k
        case let (nil, g?): return g
        default: return fallback
        }
    }

    /// French audio: MULTI, VFF or VF 2, VFQ 1, none 0 (VOSTFR is French subtitles only).
    var frenchRank: Int {
        if languages.contains(where: { ["MULTI", "VFF", "VF"].contains($0) }) { return 2 }
        if languages.contains("VFQ") { return 1 }
        return 0
    }

    /// Definition rank: 4K 4, 1080p 3, 720p 2, SD 1, unknown 0.
    var definitionRank: Int {
        if quality.contains(.uhd) { return 4 }
        if quality.contains(.fullHD) { return 3 }
        if quality.contains(.hd) { return 2 }
        if quality.contains(.sd) { return 1 }
        return 0
    }

    /// The card's marks, one per line: the best definition, the best picture range, Atmos.
    static func markLines(_ quality: OrbitQuality) -> [OrbitQuality] {
        var out: [OrbitQuality] = []
        if let d = [OrbitQuality.uhd, .fullHD, .hd, .sd].first(where: { quality.contains($0) }) { out.append(d) }
        if let r = [OrbitQuality.dolbyVision, .hdr10Plus, .hdr10, .hdr].first(where: { quality.contains($0) }) { out.append(r) }
        if quality.contains(.atmos) { out.append(.atmos) }
        return out
    }

    /// Dynamic range rank: Dolby Vision 4, HDR10+ 3, HDR10 2, HDR 1, SDR 0.
    var rangeRank: Int {
        if quality.contains(.dolbyVision) { return 4 }
        if quality.contains(.hdr10Plus) { return 3 }
        if quality.contains(.hdr10) { return 2 }
        if quality.contains(.hdr) { return 1 }
        return 0
    }

    static func read(_ stream: StreamItem) -> OrbitStreamTags {
        let name: String? = stream.name
        let title: String? = stream.title
        let desc: String? = stream.description_
        let raw = [name, title, desc].compactMap { $0 }.joined(separator: " ")
        var tags = OrbitStreamTags()
        tags.quality = OrbitQuality.read(raw)
        let t = " " + raw.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "•", with: " ") + " "

        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }

        if has("remux") { tags.source = "Remux" }
        else if has("bluray", "blu-ray", "bdrip", "brrip", " bd ") { tags.source = "BluRay" }
        else if has("web-dl", "webdl", " web dl") { tags.source = "WEB-DL" }
        else if has("webrip", "web-rip") { tags.source = "WEBRip" }
        else if has(" web ") { tags.source = "WEB" }
        else if has("hdtv") { tags.source = "HDTV" }

        if has("hevc", "x265", "h265", "h 265", "h-265") { tags.codec = "HEVC" }
        else if has(" av1 ") { tags.codec = "AV1" }
        else if has("x264", "h264", "h 264", "h-264", " avc ") { tags.codec = "H.264" }

        // The best sound named (Atmos is a badge of its own, on the left).
        if has("dts:x", "dts-x", "dtsx", "dts x ") { tags.audio = "DTS:X" }
        else if has("truehd", "true hd", "truhd") { tags.audio = "TrueHD" }
        else if has("dts-hd", "dts hd", "dtshd") { tags.audio = "DTS-HD MA" }
        else if has("ddp", "dd+", "e-ac3", "eac3", "e ac3") { tags.audio = "Dolby Digital+" }
        else if has(" dts ") { tags.audio = "DTS" }
        else if has(" ac3 ", " dd ", "dd5", "dd 5", "dolby digital") { tags.audio = "Dolby Digital" }
        else if has(" aac ") { tags.audio = "AAC" }

        if has("7 1", "7.1") { tags.channels = "7.1" }
        else if has("5 1", "5.1") { tags.channels = "5.1" }
        else if has("2 0 ", "2.0", "stereo") { tags.channels = "2.0" }

        var langs: [String] = []
        if has(" multi ", "multi-", " multi") { langs.append("MULTI") }
        if has(" vff ", "truefrench", " vf2 ") { langs.append("VFF") }
        if has(" vfq ") { langs.append("VFQ") }
        if langs.isEmpty, has(" vf ", " french ", "🇫🇷") { langs.append("VF") }
        if has("vostfr", " subfrench ") { langs.append("VOSTFR") }
        tags.languages = langs

        if let bytes = stream.behaviorHints.videoSize?.int64Value, bytes > 0 {
            tags.sizeBytes = bytes
        } else {
            tags.sizeBytes = readSize(raw)
        }

        // The file's name and its group ("…HEVC-HYPERION.mkv" → HYPERION).
        let lines = raw.components(separatedBy: "\n")
        if let line = lines.first(where: { l in
            let low = l.lowercased()
            return [".mkv", ".mp4", ".avi", ".m2ts", ".ts", ".mov", ".webm"].contains { low.contains($0) }
        }) {
            var file = line.trimmingCharacters(in: .whitespaces)
            // Drop a leading emoji / symbol ("📁 Get.Out…").
            while let first = file.unicodeScalars.first, !(CharacterSet.alphanumerics.contains(first)) {
                file.removeFirst()
            }
            file = file.trimmingCharacters(in: .whitespaces)
            if !file.isEmpty {
                tags.fileName = file
                let stem = (file as NSString).deletingPathExtension
                if let dash = stem.range(of: "-", options: .backwards) {
                    let after = stem[dash.upperBound...].trimmingCharacters(in: .whitespaces)
                    let token = after.split(separator: " ").first.map(String.init) ?? ""
                    if !token.isEmpty, token.count <= 20, token.rangeOfCharacter(from: .letters) != nil,
                       !["dl", "rip", "hd", "ma", "x"].contains(token.lowercased()) {
                        tags.group = token
                    }
                }
            }
        }

        let status = stream.debridCacheStatus
        // The service: the add-on's "[AD⚡]" / "[RD+]" tag in the name, else the app's own debrid
        // check, else a direct link.
        if let regex = try? NSRegularExpression(pattern: #"\[([A-Za-z]{2,3})\s*[⚡+⏳☁️✓]*\s*\]"#),
           let name, let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
           let codeRange = Range(match.range(at: 1), in: name),
           let full = services[name[codeRange].uppercased()] {
            tags.service = full
        } else if let status {
            let provider = status.providerName.trimmingCharacters(in: .whitespaces)
            tags.service = provider.isEmpty ? nil : provider
        } else if stream.playableDirectUrl != nil, stream.infoHash == nil {
            tags.service = String(localized: "Lien direct")
        }
        if status?.state == .cached || raw.contains("⚡") || has(" instant ", "cached") {
            tags.instant = true
        } else if status?.state == .notCached || raw.contains("⏳") {
            tags.notCached = true
        } else if stream.playableDirectUrl != nil, stream.infoHash == nil {
            // A direct link (no torrent behind it) plays at once too.
            tags.instant = true
        }
        return tags
    }

    /// "58,2 Go", "54.2 GB", "700 MB", "1.4 To".
    static func readSize(_ text: String) -> Int64? {
        let pattern = #"(\d+(?:[.,]\d+)?)\s?(to|tb|tib|go|gb|gib|mo|mb|mib)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var best: Int64?
        for match in regex.matches(in: text, range: range) {
            guard let numberRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[numberRange].replacingOccurrences(of: ",", with: ".")) else { continue }
            let unit = text[unitRange].lowercased()
            let factor: Double = unit.hasPrefix("t") ? 1e12 : unit.hasPrefix("g") ? 1e9 : 1e6
            let bytes = Int64(value * factor)
            best = max(best ?? 0, bytes)
        }
        return best
    }
}

/// The tags read once per source (a reference box: filling it never redraws the list).
final class OrbitStreamTagCache {
    private var byKey: [String: OrbitStreamTags] = [:]

    func tags(_ key: String, _ stream: StreamItem) -> OrbitStreamTags {
        let name: String? = stream.name
        let desc: String? = stream.description_
        let id = "\(key)|\(name ?? "")|\(desc?.count ?? 0)"
        if let known = byKey[id] { return known }
        let read = OrbitStreamTags.read(stream)
        byKey[id] = read
        return read
    }
}

// MARK: - The list's rows

struct OrbitStreamRow: Identifiable {
    let key: String
    let stream: StreamItem
    let tags: OrbitStreamTags
    let order: Int
    var id: String { key }

    /// Orbit's order (Steven, 2026-10-25), for the list and the automatic start alike:
    ///  1. French audio (MULTI, VFF, VF, then VFQ) before everything else;
    ///  2. ready at once (cached on the debrid service);
    ///  3. the definition (4K, 1080p, 720p…);
    ///  4. the picture: Dolby Vision, then HDR10+, HDR10, HDR;
    ///  5. Dolby Atmos;
    ///  6. the source (Remux, Blu-ray, WEB);
    ///  7. the size; the add-on's own order breaks the ties.
    static func sorted(_ rows: [OrbitStreamRow]) -> [OrbitStreamRow] {
        rows.sorted { a, b in
            if a.tags.frenchRank != b.tags.frenchRank { return a.tags.frenchRank > b.tags.frenchRank }
            if a.tags.instant != b.tags.instant { return a.tags.instant }
            if a.tags.definitionRank != b.tags.definitionRank { return a.tags.definitionRank > b.tags.definitionRank }
            if a.tags.rangeRank != b.tags.rangeRank { return a.tags.rangeRank > b.tags.rangeRank }
            let atmosA = a.tags.quality.contains(.atmos), atmosB = b.tags.quality.contains(.atmos)
            if atmosA != atmosB { return atmosA }
            if a.tags.sourceRank != b.tags.sourceRank { return a.tags.sourceRank > b.tags.sourceRank }
            let sa = a.tags.sizeBytes ?? 0, sb = b.tags.sizeBytes ?? 0
            if sa != sb { return sa > sb }
            return a.order < b.order
        }
    }

    /// The same order for a plain list of streams (the auto-play candidates).
    static func best(_ streams: [StreamItem]) -> [StreamItem] {
        let rows = streams.enumerated().map { index, stream in
            OrbitStreamRow(key: "auto#\(index)", stream: stream, tags: OrbitStreamTags.read(stream), order: index)
        }
        return sorted(rows).map(\.stream)
    }
}

enum OrbitStreamFilter: String, CaseIterable, Identifiable {
    case all, instant, uhd, fullHD, dolbyVision, hdr

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return String(localized: "Toutes")
        case .instant: return String(localized: "Instantané")
        case .uhd: return "4K"
        case .fullHD: return "1080p"
        case .dolbyVision: return "Dolby Vision"
        case .hdr: return "HDR"
        }
    }

    func matches(_ tags: OrbitStreamTags) -> Bool {
        switch self {
        case .all: return true
        case .instant: return tags.instant
        case .uhd: return tags.quality.contains(.uhd)
        case .fullHD: return !tags.quality.contains(.uhd) && tags.quality.contains(.fullHD)
        case .dolbyVision: return tags.quality.contains(.dolbyVision)
        case .hdr: return tags.rangeRank > 0
        }
    }
}

enum OrbitStreamFormat {
    static func size(_ bytes: Int64) -> String {
        // Steven: 1 Go = 1000 Mo, as his add-on counts (75,5 read against its 81,1).
        let gb = Double(bytes) / 1e9
        if gb >= 1 {
            return gb >= 100 ? String(format: "%.0f Go", gb) : String(format: "%.1f Go", gb).replacingOccurrences(of: ".", with: ",")
        }
        return String(format: "%.0f Mo", Double(bytes) / 1e6)
    }
}

// MARK: - Background

/// The title's backdrop, blurred and dark, as under the description page's sections.
struct OrbitStreamBackground: View {
    let url: String?

    var body: some View {
        let size = CGSize(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
        ZStack {
            OrbitHomeLayout.background
            if let url, !url.isEmpty {
                // Steven (2026-10-31: "le même flou épais que la page de description"): the description
                // page's ground — the film's picture down to its colour fields, made once — a little
                // darker for the sources' text.
                OrbitThickBlur(url: url)
                // (A bright film — Ali G's yellow — left the sources hard to read: darker.)
                Color.black.opacity(0.5)
            }
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.45)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Header

struct OrbitStreamHeader: View {
    let title: String
    let logoUrl: String?
    let episodeLine: String?
    let count: Int
    let loading: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 40) {
            VStack(alignment: .leading, spacing: 18) {
                OrbitTitleMark(name: title, logo: logoUrl, maxSize: CGSize(width: 420, height: 130), textSize: 48)
                    .frame(width: 420, height: 130, alignment: .bottomLeading)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Choisir une source"))
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(Color.white)
                    if let episodeLine, !episodeLine.isEmpty {
                        Text(episodeLine)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                if loading { ProgressView().scaleEffect(0.8) }
                if count > 0 {
                    Text(count == 1 ? String(localized: "1 source") : String(localized: "\(count) sources"))
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
            .padding(.bottom, 6)
        }
    }
}

// MARK: - Filter chip

struct OrbitStreamFilterChip: View {
    let label: String
    let count: Int
    let selected: Bool
    let focused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 25, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 21, weight: .bold))
                    .opacity(0.6)
            }
            .foregroundStyle(focused ? Color.black : Color.white)
            .padding(.horizontal, 26)
            .frame(height: 58)
            .background(Capsule().fill(focused ? Color.white
                                       : (selected ? Color.white.opacity(0.32) : Color.white.opacity(0.12))))
            .overlay(Capsule().strokeBorder(Color.white.opacity(selected && !focused ? 0.7 : 0), lineWidth: 2))
            .scaleEffect(focused ? 1.06 : 1)
            .shadow(color: .black.opacity(focused ? 0.35 : 0), radius: 12, y: 6)
            .animation(.easeOut(duration: 0.16), value: focused)
        }
        .buttonStyle(OrbitPlainStyle())
    }
}

// MARK: - Source card

struct OrbitStreamCard: View {
    let stream: StreamItem
    let tags: OrbitStreamTags
    let focused: Bool
    let resolving: Bool
    let failedRecently: Bool
    let fromYouTube: Bool
    /// "Instantané" only means something when some sources are not.
    let showsInstant: Bool
    /// In the sources' collection view the cell itself is the focusable thing: no button of its own.
    var plain = false
    let action: () -> Void

    /// Every card's height (the heading, two lines of file name, the tags).
    static let height: CGFloat = 190

    var body: some View {
        if plain {
            card
        } else {
            Button(action: action) { card }
                .buttonStyle(OrbitPlainStyle())
        }
    }

    private var card: some View {
            HStack(alignment: .center, spacing: 34) {
                // The quality marks, the description page's own.
                // Steven: the marks on one line, as under the description page's title (the
                // definition, the picture, the sound), the column wide enough for all three.
                HStack(spacing: 12) {
                    ForEach(OrbitStreamTags.markLines(tags.quality), id: \.rawValue) { mark in
                        OrbitQualityBadges(quality: mark)
                    }
                }
                .frame(width: 250, height: 34, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text(tags.heading(fallback: stream.streamLabel))
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        if resolving { ProgressView().scaleEffect(0.7) }
                    }
                    if let file = tags.fileName {
                        // The file's name: what the badges and tags cannot say.
                        Text(file)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.6))
                            // Steven (2026-10-29, device: cards over each other, then the app
                            // closed): a card no longer grows when focused — every card one height.
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        let desc: String? = stream.description_
                        if let desc, !desc.isEmpty {
                            Text(desc)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .lineSpacing(3)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    tagLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 12) {
                    if let bytes = tags.sizeBytes {
                        Text(OrbitStreamFormat.size(bytes))
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Color.white)
                            .monospacedDigit()
                    }
                    if let service = tags.service {
                        // Steven: which account the source goes through, always shown (the
                        // yellow bolt: already in its cache).
                        HStack(spacing: 8) {
                            if tags.instant {
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.3))
                            }
                            Text(service)
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                        .font(.system(size: 21, weight: .semibold))
                        .lineLimit(1)
                    }
                    if tags.instant && showsInstant {
                        Label(String(localized: "Instantané"), systemImage: "bolt.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.3))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color(red: 1, green: 0.84, blue: 0.3).opacity(0.16)))
                    } else if tags.notCached {
                        Label(String(localized: "Pas en cache"), systemImage: "hourglass")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
                .frame(width: 210, alignment: .trailing)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
            // Steven (2026-10-31, video: cards over each other while scrolling, their text doubled):
            // the focus animation was set on the whole card — a card redrawn in a reused line during
            // the scroll slid its text in from where the line's last card had it. Only the focus's
            // own look is animated now (its plate, rim, growth and shadow), never the card's layout.
            .animation(.easeOut(duration: 0.18)) { card in
                card
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Color.white.opacity(focused ? 0.2 : 0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Color.white.opacity(focused ? 0.55 : 0), lineWidth: 2)
                    )
                    .scaleEffect(focused ? 1.015 : 1)
                    .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 22, y: 10)
            }
    }

    /// Source · codec · sound · channels · languages, as small outlined tags.
    private var tagLine: some View {
        var items: [String] = []
        if let s = tags.source { items.append(s) }
        if let c = tags.codec { items.append(c) }
        if let a = tags.audio { items.append(a) }
        if let ch = tags.channels { items.append(ch) }
        items.append(contentsOf: tags.languages)
        if fromYouTube { items.append("YouTube") }
        return HStack(spacing: 10) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5))
            }
            if failedRecently {
                Label(String(localized: "Échec récent"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.orange.opacity(0.9))
            }
        }
        .lineLimit(1)
    }
}

// MARK: - Placeholder while searching

struct OrbitStreamPlaceholder: View {
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.white.opacity(pulse ? 0.09 : 0.04))
            .frame(height: 150)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}


// MARK: - The sources' collection view

/// Steven (2026-10-28: "le défilement dans la liste des sources n'est pas le même que Rechercher"):
/// the sources in a UIKit collection view, scrolled by the focus engine as Search's results. The
/// header (title, notice, filters) is SwiftUI, drawn over the list's top and carried with it.
struct OrbitStreamCollection: UIViewControllerRepresentable {
    let rows: [OrbitStreamRow]
    /// Anything a card shows besides its row (a source resolving, failing): a change redraws them.
    let version: String
    let topInset: CGFloat
    let scroll: OrbitStreamScroll
    /// Asks for the first source to take the focus (each change of the value).
    let focusFirst: Int
    let card: (OrbitStreamRow, Bool) -> AnyView
    let onSelect: (OrbitStreamRow) -> Void
    let menu: (OrbitStreamRow) -> UIMenu?

    func makeUIViewController(context: Context) -> OrbitStreamCollectionController {
        let controller = OrbitStreamCollectionController(scroll: scroll)
        update(controller)
        return controller
    }

    func updateUIViewController(_ controller: OrbitStreamCollectionController, context: Context) {
        update(controller)
    }

    private func update(_ controller: OrbitStreamCollectionController) {
        controller.card = card
        controller.onSelect = onSelect
        controller.menu = menu
        controller.show(rows: rows, version: version, topInset: topInset, focusFirst: focusFirst)
    }
}

/// How far the sources are scrolled (the header follows the first one).
@MainActor
final class OrbitStreamScroll: ObservableObject {
    @Published var y: CGFloat = 0
}

@MainActor
final class OrbitStreamCollectionController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    var card: (OrbitStreamRow, Bool) -> AnyView = { _, _ in AnyView(EmptyView()) }
    var onSelect: (OrbitStreamRow) -> Void = { _ in }
    var menu: (OrbitStreamRow) -> UIMenu? = { _ in nil }

    private let scroll: OrbitStreamScroll
    private var collectionView: UICollectionView!
    private var rows: [OrbitStreamRow] = []
    private var version = ""
    private var topInset: CGFloat = 0
    private var focusFirst = 0
    private var preferFirst = false
    private var registration: UICollectionView.CellRegistration<OrbitDiscoverCell, String>!

    init(scroll: OrbitStreamScroll) {
        self.scroll = scroll
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        // One source a line, every line one height. (Steven, 2026-10-29, device: with self-sized
        // cells growing on focus, cards were drawn over each other while scrolling and the app
        // closed after a while — the layout fighting the sizes.)
        let rowHeight = OrbitStreamCard.height
        let margin = OrbitHomeLayout.margin
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                              heightDimension: .absolute(rowHeight))
            let item = NSCollectionLayoutItem(layoutSize: size)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 18
            section.contentInsets = .init(top: 0, leading: margin, bottom: 0, trailing: margin)
            section.contentInsetsReference = .none
            return section
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.insetsLayoutMarginsFromSafeArea = false
        collectionView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: 120, right: 0)
        collectionView.showsVerticalScrollIndicator = false
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        // Steven (2026-10-31, photo: the sources at the top and the bottom of the screen over their
        // neighbours): a hosting configuration keeps the TV's safe area — the lines near the screen's
        // edges had their card pushed in and grown over the next ones. Découvrir's cell (a hosting
        // controller that ignores it) instead, as Découvrir had the very same trouble.
        registration = UICollectionView.CellRegistration<OrbitDiscoverCell, String> { [weak self] cell, _, key in
            cell.backgroundConfiguration = .clear()
            cell.configurationUpdateHandler = { [weak self] cell, state in
                guard let self, let row = self.rows.first(where: { $0.key == key }) else { return }
                // Steven (2026-10-31: sources still over each other at the top and the bottom while
                // scrolling): the lines coming in at the edges were filled inside the scroll's own
                // animation — the new card animated in over the old one. Filled at once now.
                UIView.performWithoutAnimation {
                    (cell as? OrbitDiscoverCell)?.show(self.card(row, state.isFocused))
                    cell.layoutIfNeeded()
                }
            }
        }
    }

    func show(rows new: [OrbitStreamRow], version newVersion: String, topInset inset: CGFloat, focusFirst ask: Int) {
        loadViewIfNeeded()
        if abs(inset - topInset) > 0.5 {
            let atTop = collectionView.contentOffset.y <= -topInset + 1
            topInset = inset
            collectionView.contentInset.top = inset
            if atTop { collectionView.setContentOffset(CGPoint(x: 0, y: -inset), animated: false) }
        }
        let oldKeys = rows.map(\.key)
        rows = new
        if oldKeys != new.map(\.key) {
            collectionView.reloadData()
            if oldKeys.isEmpty {
                collectionView.layoutIfNeeded()
                collectionView.setContentOffset(CGPoint(x: 0, y: -topInset), animated: false)
            }
        } else if newVersion != version {
            for cell in collectionView.visibleCells { cell.setNeedsUpdateConfiguration() }
        }
        version = newVersion
        if ask != focusFirst {
            focusFirst = ask
            guard !rows.isEmpty else { return }
            preferFirst = true
            collectionView.setContentOffset(CGPoint(x: 0, y: -topInset), animated: false)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.collectionView.setNeedsFocusUpdate()
                self.collectionView.updateFocusIfNeeded()
                self.view.window?.windowScene?.focusSystem?.requestFocusUpdate(to: self.collectionView)
            }
        }
    }

    // MARK: Data

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { rows.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        var cell: UICollectionViewCell!
        UIView.performWithoutAnimation {
            cell = collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: rows[indexPath.item].key)
        }
        return cell
    }

    // MARK: Delegate

    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        guard preferFirst, !rows.isEmpty else { return nil }
        preferFirst = false
        return IndexPath(item: 0, section: 0)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard rows.indices.contains(indexPath.item) else { return }
        onSelect(rows[indexPath.item])
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let path = indexPaths.first, rows.indices.contains(path.item), let menu = menu(rows[path.item]) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { followHeader() }

    // Steven (2026-10-31, video: "le défilement est bizarre" — the focused source landing at the
    // bottom one step, in the middle the next, the system aiming each time): the focused source
    // goes down to one line (the second source's place), then stays on it, the list sliding under it.
    private var focusedIndex: Int?

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                        with coordinator: UIFocusAnimationCoordinator) {
        if let next = context.nextFocusedIndexPath { focusedIndex = next.item }
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard let index = focusedIndex,
              let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return }
        let line = topInset + OrbitStreamCard.height + 18
        let lowest = -topInset
        let highest = max(lowest, collectionView.contentSize.height + collectionView.contentInset.bottom - scrollView.bounds.height)
        targetContentOffset.pointee.y = min(highest, max(lowest, frame.minY - line))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        followHeader()
    }

    /// The header rides on the first source.
    private func followHeader() {
        guard let collectionView else { return }
        let y = max(0, collectionView.contentOffset.y + topInset)
        if abs(scroll.y - y) > 0.5 { scroll.y = y }
    }
}
