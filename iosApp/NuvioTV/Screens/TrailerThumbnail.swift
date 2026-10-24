import SwiftUI
import SharedCore

// MARK: - Thumbnail URL resolution

extension MetaTrailer {
    /// A 16:9 YouTube thumbnail for this trailer, or `nil` when the key isn't a recognizable
    /// YouTube video id/URL. Mirrors upstream `DetailTrailersSection`'s
    /// `https://img.youtube.com/vi/{key}/hqdefault.jpg` construction, but — unlike upstream, which
    /// assumes `key` is always a bare video id — this also copes with `key` holding a full YouTube
    /// URL (watch/embed/shorts/youtu.be), the same shape `youtubePlaybackUrl()` in
    /// `HeroTrailerSelector.kt` already has to handle for playback. `nil` degrades gracefully:
    /// `CachedAsyncImage` renders its flat surface/film glyph instead of an endless shimmer.
    var thumbnailURLString: String? {
        guard let id = youtubeVideoId else { return nil }
        return "https://img.youtube.com/vi/\(id)/hqdefault.jpg"
    }

    /// Extracts a bare YouTube video id from `key`, whether `key` already IS a bare id or a full
    /// YouTube URL in any of its common shapes.
    private var youtubeVideoId: String? {
        let key = self.key
        guard !key.isEmpty else { return nil }

        if !key.hasPrefix("http://") && !key.hasPrefix("https://") {
            // A bare key is only a YouTube id if the record SAYS it's YouTube — a bare Vimeo (or
            // other provider) id would synthesize a guaranteed-404 img.youtube.com URL and render
            // the failure glyph instead of the honest no-thumbnail surface. Full URLs below stay
            // site-agnostic: the host check identifies YouTube regardless of a mislabeled `site`.
            guard site.caseInsensitiveCompare("YouTube") == .orderedSame else { return nil }
            // And only plausible if it doesn't look like a stray path/query fragment.
            let disallowed = CharacterSet(charactersIn: "/?& ")
            guard key.rangeOfCharacter(from: disallowed) == nil else { return nil }
            return key
        }

        guard let components = URLComponents(string: key), let host = components.host else { return nil }

        // youtube-nocookie.com is the privacy-enhanced embed host — same ids, same thumbnails.
        if host.contains("youtube.com") || host.contains("youtube-nocookie.com") {
            if let v = components.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
                return v
            }
            let segments = components.path.split(separator: "/").map(String.init)
            for prefix in ["embed", "shorts", "v"] {
                if let idx = segments.firstIndex(of: prefix), segments.count > idx + 1 {
                    return segments[idx + 1]
                }
            }
            return nil
        }

        if host.contains("youtu.be") {
            let segments = components.path.split(separator: "/").map(String.init)
            return segments.first
        }

        return nil
    }
}

