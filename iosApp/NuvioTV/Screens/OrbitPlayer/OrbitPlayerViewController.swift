import AVKit
import Combine
import CoreMedia
import OrbitEngine
import SharedCore
import SwiftUI
import UIKit

// Orbit's player screen is Apple's own (option A, Steven 2026-10-25): AVPlayerViewController with its
// transport bar, scrubbing with thumbnails, subtitles menu, info panel and Now Playing — fluid by
// construction. Orbit adds what Apple does not know: the audio-track menu (the engine switches
// tracks), "Passer l'intro / le générique" and "Épisode suivant" as contextual actions, and Menu
// closing the up-next card before leaving.
//
// Sources the Apple TV cannot decode in hardware (old MPEG-2, VC-1, AV1 on models without an AV1
// decoder) play through the engine's software path, which has no AVPlayer: the engine's own surface
// is shown instead, with the basic remote controls handled here.

final class OrbitPlayerViewController: AVPlayerViewController {
    private let session: OrbitPlayerSession
    /// Menu press: true when the screen used it (the up-next card was dismissed).
    var onMenu: (() -> Bool)?

    private var bag = Set<AnyCancellable>()
    /// The current item's watchers (subtitle look and SDH choice).
    private var itemBag = Set<AnyCancellable>()
    private var surface: AetherPlayerView?
    private var actionsSignature = ""
    private var audioSignature = ""

    init(session: OrbitPlayerSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        showsPlaybackControls = true
        // The engine writes the display criteria itself, before the item (tvOS 26.5+ rejects an HDR
        // item whose range the panel is not already in). AVKit writing them too would race it.
        appliesPreferredDisplayCriteriaAutomatically = false
        allowsPictureInPicturePlayback = false
        contextualActions = []

        guard let engine = session.engine else { return }
        engine.$currentAVPlayer
            .receive(on: RunLoop.main)
            .sink { [weak self] player in
                self?.player = player
                self?.watchItems(of: player)
            }
            .store(in: &bag)
        engine.$playbackBackend
            .receive(on: RunLoop.main)
            .sink { [weak self] backend in self?.showSurface(backend == .software) }
            .store(in: &bag)
        session.$audioTracks.combineLatest(session.$activeAudioTrackId)
            .receive(on: RunLoop.main)
            .sink { [weak self] tracks, active in self?.installAudioMenu(tracks: tracks, active: active) }
            .store(in: &bag)
    }

    // MARK: - Subtitles (Steven, 2026-10-25: the settings' look was Chris's player's only)

    private var subtitleSettings: SubtitleStyleState? {
        (PlayerSettingsRepository.shared.uiState.value_ as? PlayerSettingsUiState)?.subtitleStyle
    }

    private func watchItems(of player: AVPlayer?) {
        itemBag.removeAll()
        guard let player else { return }
        player.publisher(for: \.currentItem)
            .receive(on: RunLoop.main)
            .sink { [weak self] item in
                guard let self, let item else { return }
                self.applySubtitleLook(to: item)
                item.publisher(for: \.status)
                    .filter { $0 == .readyToPlay }
                    .first()
                    .receive(on: RunLoop.main)
                    .sink { [weak self, weak item] _ in
                        guard let self, let item else { return }
                        self.applySubtitleLook(to: item)
                        self.avoidSdh(on: item)
                    }
                    .store(in: &self.itemBag)
            }
            .store(in: &itemBag)
    }

    /// Réglages › Langues et sous-titres › Apparence: the size and the background, on Apple's own
    /// subtitle rendering.
    private func applySubtitleLook(to item: AVPlayerItem) {
        guard let style = subtitleSettings else { return }
        let percent: Int
        switch style.fontSizeSp {
        case ..<16: percent = 80
        case 16..<21: percent = 100
        case 21..<27: percent = 130
        default: percent = 160
        }
        var attributes: [String: Any] = [kCMTextMarkupAttribute_RelativeFontSize as String: percent]
        let argb = UInt64(bitPattern: style.backgroundColor)
        let alpha = Double((argb >> 24) & 0xFF) / 255
        if alpha > 0 {
            attributes[kCMTextMarkupAttribute_BackgroundColorARGB as String] = [
                alpha, Double((argb >> 16) & 0xFF) / 255, Double((argb >> 8) & 0xFF) / 255, Double(argb & 0xFF) / 255,
            ]
        }
        item.textStyleRules = AVTextStyleRule(textMarkupAttributes: attributes).map { [$0] }
    }

    /// "Retirer les sous-titres pour sourds et malentendants": Apple's player draws a track as it
    /// is, so the plain track of the same language is chosen instead of an SDH one when there is.
    private func avoidSdh(on item: AVPlayerItem) {
        guard subtitleSettings?.stripSdh == true else { return }
        Task { @MainActor [weak item] in
            guard let item,
                  let group = try? await item.asset.loadMediaSelectionGroup(for: .legible),
                  let selected = item.currentMediaSelection.selectedMediaOption(in: group),
                  selected.hasMediaCharacteristic(.describesMusicAndSoundForAccessibility)
            else { return }
            let language = selected.extendedLanguageTag ?? selected.locale?.identifier
            let plain = group.options.first { option in
                !option.hasMediaCharacteristic(.describesMusicAndSoundForAccessibility)
                    && !option.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
                    && (option.extendedLanguageTag ?? option.locale?.identifier) == language
            }
            if let plain { item.select(plain, in: group) }
        }
    }

    // MARK: - Contextual actions

    /// Skip prompt and up-next actions; reinstalled only when their meaning changes (reassigning
    /// identical actions makes the transport bar re-animate them).
    func setActions(skip: SkipPrompt?, upNext: OrbitUpNextAction?,
                    onSkip: @escaping (Double) -> Void, onPlayNow: @escaping () -> Void,
                    onDismissUpNext: @escaping () -> Void) {
        let signature = "\(skip.map { "\($0.label)@\($0.targetSec)" } ?? "-")|\(upNext?.rawValue ?? "-")"
        guard signature != actionsSignature else { return }
        actionsSignature = signature
        var actions: [UIAction] = []
        if let skip {
            let target = skip.targetSec
            actions.append(UIAction(title: skip.label,
                                    image: UIImage(systemName: "forward.end.fill")) { _ in onSkip(target) })
        }
        if let upNext {
            actions.append(UIAction(title: upNext.title, image: UIImage(systemName: "play.fill")) { _ in onPlayNow() })
            actions.append(UIAction(title: String(localized: "Voir le générique"),
                                    image: UIImage(systemName: "xmark")) { _ in onDismissUpNext() })
        }
        contextualActions = actions
    }

    // MARK: - Audio menu

    private func installAudioMenu(tracks: [TrackInfo], active: Int?) {
        let signature = tracks.map { "\($0.id)" }.joined(separator: ",") + "|\(active ?? -1)"
        guard signature != audioSignature else { return }
        audioSignature = signature
        guard tracks.count > 1 else {
            transportBarCustomMenuItems = []
            return
        }
        let session = session
        let children: [UIMenuElement] = tracks.map { track in
            UIAction(title: OrbitPlayerText.audioLabel(track),
                     state: track.id == active ? .on : .off) { _ in session.selectAudioTrack(id: track.id) }
        }
        transportBarCustomMenuItems = [
            UIMenu(title: String(localized: "Audio"), image: UIImage(systemName: "speaker.wave.2"),
                   options: [.singleSelection], children: children),
        ]
    }

    // MARK: - Software path

    private func showSurface(_ shown: Bool) {
        guard let engine = session.engine else { return }
        if shown {
            guard surface == nil, let host = contentOverlayView else { return }
            let view = AetherPlayerView(frame: host.bounds)
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.insertSubview(view, at: 0)
            engine.bind(view: view)
            surface = view
        } else if let view = surface {
            view.removeFromSuperview()
            surface = nil
        }
    }

    // MARK: - Remote

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // The software path has no AVPlayer, so no Apple transport: the basics are handled here.
        let software = player == nil && surface != nil
        let session = session
        for press in presses {
            switch press.type {
            case .menu:
                if onMenu?() == true { return }
            case .select, .playPause:
                if software { session.togglePlayPause(); return }
            case .leftArrow:
                if software {
                    let target = max(0, session.positionSec - 10)
                    Task { await session.seek(to: target) }
                    return
                }
            case .rightArrow:
                if software {
                    let target = session.positionSec + 10
                    Task { await session.seek(to: target) }
                    return
                }
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }
}

/// The up-next contextual action.
enum OrbitUpNextAction: String {
    case playNext, continueWatching

    var title: String {
        switch self {
        case .playNext: return String(localized: "Lire l'épisode suivant")
        case .continueWatching: return String(localized: "Continuer à regarder")
        }
    }
}

/// Apple's player in SwiftUI.
struct OrbitPlayerContainer: UIViewControllerRepresentable {
    let session: OrbitPlayerSession
    let skip: SkipPrompt?
    let upNext: OrbitUpNextAction?
    let onSkip: (Double) -> Void
    let onPlayNow: () -> Void
    let onDismissUpNext: () -> Void
    let onMenu: () -> Bool

    func makeUIViewController(context: Context) -> OrbitPlayerViewController {
        let controller = OrbitPlayerViewController(session: session)
        controller.onMenu = onMenu
        return controller
    }

    func updateUIViewController(_ controller: OrbitPlayerViewController, context: Context) {
        controller.onMenu = onMenu
        controller.setActions(skip: skip, upNext: upNext, onSkip: onSkip, onPlayNow: onPlayNow,
                              onDismissUpNext: onDismissUpNext)
    }
}
