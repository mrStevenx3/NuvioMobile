import Combine
import SwiftUI
import ImageIO
import UIKit
import Vision

// Steven (2026-10-27): "on doit ajouter les logos nous-mêmes ? Il y a des doublons, à moins de
// détecter quand c'est écrit". Orbit reads a poster once (Apple's text recognition, on the device)
// and draws a platform's mark only when the poster does not already print it.

/// The words each poster prints, by its address (read once, kept).
@MainActor
final class OrbitPrintedMarks: ObservableObject {
    static let shared = OrbitPrintedMarks()
    @Published private(set) var words: [String: Set<String>] = [:]
    /// Where the poster prints its own text (its title): its top, its foot (Steven: Orbit's mark
    /// goes where the poster leaves room).
    @Published private(set) var busy: [String: OrbitPrintedZones] = [:]
    private var asked = Set<String>()

    /// Orbit's mark at the poster's top (its title at its foot, or not read yet), else at its foot.
    func markAtTop(_ url: String?) -> Bool {
        guard let url, let zones = busy[url] else { return true }
        return !zones.top || zones.foot
    }

    /// The poster's words, nil while it is being read.
    func words(of url: String?) -> Set<String>? {
        guard let url else { return [] }
        if let found = words[url] { return found }
        read(url)
        return nil
    }

    /// The poster already prints one of these (nil: not read yet).
    func prints(_ url: String?, any marks: [String]) -> Bool? {
        guard let found = words(of: url) else { return nil }
        // A one-letter mark (Netflix's N) only as a word of its own; the others anywhere.
        return marks.contains { mark in found.contains { mark.count == 1 ? $0 == mark : $0.contains(mark) } }
    }

    /// One poster read at a time, after the others' images (Steven's screen: every poster blank —
    /// dozens of readings at once took the whole machine).
    private var queue: [String] = []
    private var reading = false

    private func read(_ url: String) {
        guard !asked.contains(url) else { return }
        asked.insert(url)
        queue.append(url)
        pump()
    }

    private func pump() {
        guard !reading, !queue.isEmpty else { return }
        // The newest first (the row on screen).
        let url = queue.removeLast()
        guard let address = URL(string: url) else { pump(); return }
        reading = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            let read: (Set<String>, OrbitPrintedZones)? = await Task.detached(priority: .background) { () -> (Set<String>, OrbitPrintedZones)? in
                guard let (data, _) = try? await URLSession.shared.data(from: address),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceThumbnailMaxPixelSize: 540,
                      ] as CFDictionary) else { return nil }
                return Self.recognise(cg)
            }.value
            guard let self else { return }
            if let read {
                OrbitTrace.log("printed \(url) top=\(read.1.top) foot=\(read.1.foot) \(read.0.sorted().joined(separator: ","))")
                self.busy[url] = read.1
                self.words[url] = read.0
            } else {
                OrbitTrace.log("printed \(url) unreadable")
                self.words[url] = []
            }
            self.reading = false
            self.pump()
        }
    }

    nonisolated private static func recognise(_ image: CGImage) -> (Set<String>, OrbitPrintedZones) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.015
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        var out = Set<String>()
        var zones = OrbitPrintedZones()
        for observation in request.results ?? [] {
            // (Vision's boxes start at the bottom.) Any sizeable text: the poster's own there.
            if observation.boundingBox.height >= 0.025 {
                if observation.boundingBox.maxY > 0.75 { zones.top = true }
                if observation.boundingBox.minY < 0.3 { zones.foot = true }
            }
            // (Steven, Lanterns: HBO's mark printed so small it could not be read — a mark that
            // small does not count, Orbit draws its own.)
            guard observation.boundingBox.height >= 0.03 else { continue }
            // The credits block at a poster's foot names the network in small print: not its mark.
            guard observation.boundingBox.minY > 0.1 || observation.boundingBox.height >= 0.05 else { continue }
            for candidate in observation.topCandidates(3) {
                let text = candidate.string.lowercased()
                out.insert(text.trimmingCharacters(in: .whitespacesAndNewlines))
                for word in text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) { out.insert(String(word)) }
            }
        }
        return (out, zones)
    }
}

nonisolated struct OrbitPrintedZones: Sendable, Equatable {
    var top = false
    var foot = false
}

/// A view redrawn when a poster's words are known.
struct OrbitPrintedReader<Content: View>: View {
    let url: String?
    let marks: [String]
    @ViewBuilder let content: (_ printed: Bool?, _ atTop: Bool) -> Content
    @ObservedObject private var store = OrbitPrintedMarks.shared

    var body: some View { content(store.prints(url, any: marks), store.markAtTop(url)) }
}
