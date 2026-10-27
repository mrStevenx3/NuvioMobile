import Combine
import SwiftUI
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
    private var asked = Set<String>()

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

    private func read(_ url: String) {
        guard !asked.contains(url), let address = URL(string: url) else { return }
        asked.insert(url)
        Task { [weak self] in
            let request = ArtworkDecodeRequest(size: .points(width: 360, height: 540), fill: false, scale: 1).normalized
            guard let image = try? await ArtworkStore.fetch(address, decode: request), let cg = image.cgImage else {
                OrbitTrace.log("printed \(url) unreadable")
                self?.words[url] = []
                return
            }
            let found = await Task.detached(priority: .utility) { Self.recognise(cg) }.value
            OrbitTrace.log("printed \(url) \(found.sorted().joined(separator: ","))")
            self?.words[url] = found
        }
    }

    nonisolated private static func recognise(_ image: CGImage) -> Set<String> {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.015
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        var out = Set<String>()
        for observation in request.results ?? [] {
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
        return out
    }
}

/// A view redrawn when a poster's words are known.
struct OrbitPrintedReader<Content: View>: View {
    let url: String?
    let marks: [String]
    @ViewBuilder let content: (_ printed: Bool?) -> Content
    @ObservedObject private var store = OrbitPrintedMarks.shared

    var body: some View { content(store.prints(url, any: marks)) }
}
