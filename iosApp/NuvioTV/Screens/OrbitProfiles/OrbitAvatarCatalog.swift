import Foundation

// Orbit Profils — Orbit's own avatars (Steven, 2026-10-24): the mascot, the rabbit on its ring, in
// twelve scenes. Drawn for Orbit (orbit-avatars/ in the repository, the SVG sources beside the
// PNGs) and served from the public repository, so a profile's avatar shows on every device —
// the phone app included — like any custom avatar address.

struct OrbitAvatar512: Identifiable, Hashable {
    let id: String
    let name: String
    var url: String { OrbitAvatarCatalog.base + id + ".png" }
}

enum OrbitAvatarCatalog {
    static let base = "https://raw.githubusercontent.com/mrStevenx3/NuvioMobile/detail-apple-style/orbit-avatars/"

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
