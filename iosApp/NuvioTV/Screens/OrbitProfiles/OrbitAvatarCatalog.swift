import Foundation

// Orbit Profils — Orbit's own avatars (Steven, 2026-10-24): the mascot, the rabbit on its ring, in
// twelve scenes. Drawn for Orbit (orbit-avatars/ in the repository, the SVG sources beside the
// PNGs) and served from the public repository, so a profile's avatar shows on every device —
// the phone app included — like any custom avatar address.

struct OrbitAvatar512: Identifiable, Hashable {
    let id: String
    let name: String
    var url: String { OrbitAvatarCatalog.base + id + ".png?v=\(OrbitAvatarCatalog.version)" }
}

enum OrbitAvatarCatalog {
    static let base = "https://raw.githubusercontent.com/mrStevenx3/NuvioMobile/detail-apple-style/orbit-avatars/"
    /// Bumped when the drawings change (Steven, 2026-10-25: the old ones stayed in the image cache).
    static let version = 3

    /// An Orbit avatar's address at the current drawings' version (a profile saved earlier keeps
    /// the old address); any other address as it is.
    static func current(_ url: String?) -> String? {
        guard let url, url.hasPrefix(base) else { return url }
        let plain = url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
        return plain + "?v=\(version)"
    }

    static let all: [OrbitAvatar512] = [
        OrbitAvatar512(id: "classique", name: String(localized: "Orbit")),
        OrbitAvatar512(id: "popcorn", name: String(localized: "Pop-corn")),
        OrbitAvatar512(id: "lunettes-3d", name: String(localized: "Lunettes 3D")),
        OrbitAvatar512(id: "astronaute", name: String(localized: "Astronaute")),
        OrbitAvatar512(id: "cosmos", name: String(localized: "Cosmos")),
        OrbitAvatar512(id: "clap", name: String(localized: "Clap")),
        OrbitAvatar512(id: "telecommande", name: String(localized: "Télécommande")),
        OrbitAvatar512(id: "endormi", name: String(localized: "Endormi")),
        OrbitAvatar512(id: "realisateur", name: String(localized: "Réalisateur")),
        OrbitAvatar512(id: "fusee", name: String(localized: "Fusée")),
        OrbitAvatar512(id: "casque", name: String(localized: "Casque audio")),
        OrbitAvatar512(id: "couronne", name: String(localized: "Couronne")),
    ]
}
