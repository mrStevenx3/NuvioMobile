import SwiftUI

/// FEAT-35: `.play` is the one focus target `DetailView` asks the engine to land on first
/// (`.defaultFocus`). The synopsis teaser can be focusable and sits above Play, so without this the
/// engine's top-leading default would land on the teaser. The other cases only give each hero
/// target an identity so a move between them reads as user input (review r1 #2).
nonisolated enum DetailHeroFocus: Hashable {
    case play
    case startOver
    case trailer
    case watched
    case library
    case shuffle
    case teaser
}

/// Review r1 #2: the series Play button mounts only once the meta and primary action land, after
/// `.defaultFocus` has already run, so `DetailView` claims it once, late, under these rules.
nonisolated enum DetailLatePlayFocus {
    /// Seconds after the page appears during which a late Play claim may still move focus.
    static let claimWindow: TimeInterval = 4

    /// Write attempts per claim: the first, plus one retry `retryDelay` later if focus never
    /// reached Play (review r2 #1). After that the claim gives up.
    static let maxClaimAttempts = 2
    static let retryDelay: Duration = .milliseconds(120)

    /// A focus change between two different hero targets can only come from the user, and so can
    /// leaving the hero targets for something else (non-nil → nil: Watched → a row → Watched never
    /// passes two hero targets back to back, review r2 #2). nil → a target is the engine's landing.
    static func isUserMove(old: DetailHeroFocus?, new: DetailHeroFocus?) -> Bool {
        guard let old else { return false }
        guard let new else { return true }
        return old != new
    }

    /// While a claim is in flight, focus arriving on Play is the claim landing: latch it there and
    /// do not count it as a user move.
    static func latchesClaim(pending: Bool, new: DetailHeroFocus?) -> Bool {
        pending && new == .play
    }

    /// `playEnabled`: a disabled Play button (guest, no playback source) is not focusable, so the
    /// claim is skipped while it is off (review r2 #1).
    static func shouldClaim(isCinematic: Bool, alreadyClaimed: Bool, userInteracted: Bool,
                            userMovedInHero: Bool, heroHasFocus: Bool, playEnabled: Bool,
                            currentFocus: DetailHeroFocus?) -> Bool {
        guard isCinematic, !alreadyClaimed, !userInteracted, !userMovedInHero, heroHasFocus, playEnabled else {
            return false
        }
        return currentFocus != .play
    }
}

/// FEAT-35 (Detail revamp "Cinematic Clean", Christian's pick 2026-10-02): the first screen of the
/// Cinematic Detail layout. A bottom-anchored text column (fixed logo slot, meta line, MDBList
/// ratings strip, a four-line synopsis teaser, the action row) with a non-focusable credits block
/// right-aligned beside the action row (D9). The hero fills the viewport minus a peek band, so the
/// first row's title shows under it on landing.
///
/// Every slot above the action row has a constant height once laid out (correction F3): the logo
/// slot, the meta line, the reserved ratings slot and the synopsis slot. Late data (the logo image,
/// the MDBList emission, the enriched overview) fills a slot in place, so the bottom-anchored stack
/// never moves after first paint.
///
/// The action row is `DetailView.actionRow`, passed in verbatim, so its closures, labels and
/// accessibility identifiers are the same ones Classic uses.
struct DetailCinematicHero<Actions: View>: View {
    let title: String
    let logoURL: String?
    /// BUG-193: the page's own backdrop (upgraded URL) and its fallback, for the full-synopsis cover.
    var backdropURL: String? = nil
    var backdropFallbackURL: String? = nil
    let meta: DetailMetaLineModel
    let ratings: [DetailRatingEntry]
    /// The ratings strip's slot is laid out (reserved, possibly still empty) only while this is on:
    /// the Ratings section toggle and the MDBList gate, both known before first paint
    /// (`DetailRatings.reservesSlot`).
    let ratingsGateOn: Bool
    /// The Ratings section toggle alone (D10: OFF also hides the meta line's IMDb ★).
    let ratingsSectionOn: Bool
    let overview: String?
    /// False once the meta has resolved with no overview at all: the slot then goes away.
    let synopsisSlotVisible: Bool
    let credits: DetailCreditsText
    /// Correction F8: owned by `DetailView` (it also pauses the background trailer).
    @Binding var showSynopsisSheet: Bool
    /// `DetailView`'s hero focus state; the teaser binds `.teaser` (identity only, review r1 #2).
    var heroFocus: FocusState<DetailHeroFocus?>.Binding
    /// Runs before the sheet opens (counts as interacting; withdraws a leaving trailer bridge).
    let onOpenSynopsis: () -> Void
    /// Steven's fork (Apple TV style, `DetailAppleStyle`): the synopsis moves out of the text column
    /// to the right of the action row, two lines, with a chevron button that opens the full text.
    /// The credits block is not drawn in that mode (the synopsis takes its place).
    var synopsisBeside: Bool = false
    /// How much taller the unfolded synopsis is than its two lines (0 folded). `DetailView` adds
    /// it under the hero, inside the same animation, so the rows below move down with the text.
    var onSynopsisExtraHeight: (CGFloat) -> Void = { _ in }
    @ViewBuilder let actions: () -> Actions

    @State private var measuredSynopsisHeight: CGFloat = 0
    /// Steven's fork: the beside-synopsis is unfolded (see `synopsisBesideBlock`).
    @State private var synopsisUnfolded = false
    @State private var synopsisFoldedHeight: CGFloat = 0
    @State private var synopsisFullHeight: CGFloat = 0
    /// The rendered height of four `Theme.Font.synopsis` lines (a hidden probe, font-only). The slot
    /// is sized from this, not from `UIFont.lineHeight` — see `DetailSynopsisTeaser.resolvedSlotHeight`.
    @State private var measuredFourLineHeight: CGFloat = 0
    #if DEBUG
    @State private var measuredHeroHeight: CGFloat = 0
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var synopsisLineHeight: CGFloat { Theme.Font.synopsisLineHeight }
    private var synopsisSlotHeight: CGFloat {
        DetailSynopsisTeaser.resolvedSlotHeight(measuredFourLineHeight: measuredFourLineHeight,
                                                lineHeight: synopsisLineHeight)
    }
    /// The measurement's answer. It can flip after the teaser was focused (a late overview, a
    /// re-measure), so the rendered form follows `synopsisTruncated` below instead.
    private var measuredTruncated: Bool {
        DetailSynopsisTeaser.isTruncated(fullTextHeight: measuredSynopsisHeight, slotHeight: synopsisSlotHeight)
    }
    /// Review r1 #10: whether the teaser renders as the focusable button. Becomes true as soon as
    /// the measurement says so, but only goes back to plain text while the teaser is NOT focused,
    /// so a re-measure never pulls the focused button out from under the user.
    @State private var synopsisTruncated = false

    private func syncSynopsisTruncated() {
        let next = DetailSynopsisTeaser.rendersAsButton(measuredTruncated: measuredTruncated,
                                                       currentlyButton: synopsisTruncated,
                                                       teaserFocused: heroFocus.wrappedValue == .teaser)
        if synopsisTruncated != next { synopsisTruncated = next }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Correction F5: the hero's height comes from the scroll view's container through
            // `containerRelativeFrame`, with no stored viewport state and no extra scroll-geometry
            // observer. It sits on an invisible spacer so it acts as a MINIMUM: Larger Text grows
            // the hero (and shrinks the peek) instead of clipping the text column.
            Color.clear
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical) { height, _ in
                    DetailCinematicLayout.heroHeight(containerHeight: height)
                }
                .accessibilityHidden(true)
            content
        }
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .onChange(of: measuredTruncated, initial: true) { _, _ in syncSynopsisTruncated() }
        .onChange(of: heroFocus.wrappedValue) { _, _ in syncSynopsisTruncated() }
        #if DEBUG
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height.rounded() }, action: { height in
            measuredHeroHeight = height
        })
        .overlay(alignment: .topLeading) {
            // Gate 1 diagnostic (invisible, harness-readable), same shape as `debug_bridge`.
            Text("debug_detail_hero h=\(Int(measuredHeroHeight)) logo=\(Int(DetailCinematicLayout.logoSlotHeight)) syn=\(Int(synopsisSlotHeight)) trunc=\(synopsisTruncated ? 1 : 0) ratings=\(ratings.count) reserved=\(ratingsGateOn ? 1 : 0)")
                .font(.system(size: 8))
                .opacity(0.011)
                .accessibilityIdentifier("debug_detail_hero")
        }
        #endif
        // BUG-117 (kept): the hero spans the full content width, so Up from a far-right season
        // poster still finds a target in here.
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail_hero")
        .fullScreenCover(isPresented: $showSynopsisSheet) {
            DetailSynopsisSheet(title: title, logoURL: logoURL, overview: overview ?? "",
                                backdropURL: backdropURL, backdropFallbackURL: backdropFallbackURL)
        }
    }

    // MARK: - Layout

    /// D9: the action row sits inside the text column; the credits are right-aligned and bottom-
    /// aligned to it. The column takes priority so it always gets its full 900 pt before the
    /// credits block claims what is left.
    private var content: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    logoSlot
                    metaLine
                    if ratingsGateOn { ratingsSlot }
                    if synopsisSlotVisible && !synopsisBeside { synopsisSlot }
                }
                // Steven's fork (device pass 1): beside the synopsis the row was squeezed and
                // Play wrapped onto four lines; it now always keeps its natural width.
                if synopsisBeside {
                    actions().fixedSize(horizontal: true, vertical: false)
                } else {
                    actions()
                }
            }
            .frame(maxWidth: synopsisBeside ? nil : DetailCinematicLayout.textColumnMaxWidth,
                   alignment: .leading)
            .fixedSize(horizontal: synopsisBeside, vertical: false)
            .layoutPriority(1)
            if synopsisBeside {
                if synopsisSlotVisible, let overview, !overview.isEmpty {
                    synopsisBesideBlock(overview)
                        .frame(maxWidth: .infinity, alignment: .bottomLeading)
                }
            } else if !credits.isEmpty {
                creditsBlock
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    private var titleFallback: some View {
        Text(title)
            .font(Theme.Font.hero)
            .foregroundStyle(Theme.Palette.textPrimary)
            .lineLimit(2)
    }

    /// Fixed 180 pt slot, logo (or the title) bottom-leading inside it.
    private var logoSlot: some View {
        Group {
            if let logoURL, !logoURL.isEmpty {
                // beta.19-rc1 verdict (I1, BUG-134): the TMDB `original` logo (the data keeps w500),
                // decoded for the slot it is drawn in; the w500 file is the automatic fallback.
                CachedAsyncImage(string: logoURL, contentMode: .fit,
                                 decodeSize: .points(width: DetailCinematicLayout.logoMaxWidth,
                                                     height: DetailCinematicLayout.logoSlotHeight),
                                 upgrade: .logo,
                                 // BUG-152 (Steven, beta.19-rc3 verdict 2026-10-06): the title while the
                                 // logo downloads, not the shimmer (a grey block in this 600×180 slot).
                                 loading: { titleFallback },
                                 failure: { titleFallback })
                    .frame(maxWidth: DetailCinematicLayout.logoMaxWidth,
                           maxHeight: DetailCinematicLayout.logoSlotHeight,
                           alignment: .bottomLeading)
            } else {
                titleFallback
            }
        }
        .frame(maxWidth: DetailCinematicLayout.logoMaxWidth, alignment: .bottomLeading)
        .frame(height: DetailCinematicLayout.logoSlotHeight, alignment: .bottomLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail_logo_slot")
    }

    private var metaParts: [String] {
        DetailMetaLine.textParts(year: meta.year, runtime: meta.runtime, genres: meta.genres)
    }

    private var showImdbStar: Bool {
        DetailRatings.showsImdbStar(sectionRatings: ratingsSectionOn, ratingsGateOn: ratingsGateOn,
                                    ratingCount: ratings.count, imdbRating: meta.imdbRating)
    }

    /// Year · Runtime · Genres, the stroked age chip, then the IMDb ★ (D10). One line in a fixed
    /// slot; no spinner (correction F3).
    private var metaLine: some View {
        HStack(spacing: Theme.Spacing.md) {
            if !metaParts.isEmpty {
                Text(metaParts.joined(separator: " \u{00B7} "))
            }
            if let age = meta.ageRating, !age.isEmpty {
                // Stroke only: the Cinematic hero carries no glass chips (nothing for BUG-41's
                // flattening to do here).
                Text(age)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.chip)
                            .stroke(Theme.Palette.textSecondary, lineWidth: 1)
                    }
            }
            if showImdbStar, let rating = meta.imdbRating {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "star.fill").foregroundStyle(Theme.Palette.star)
                    Text(rating)
                }
            }
        }
        .font(Theme.Font.metaStrong)
        .foregroundStyle(Theme.Palette.textSecondary)
        .lineLimit(1)
        .frame(height: DetailCinematicLayout.metaLineHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail_meta_line")
    }

    /// Reserved 44 pt whenever the gate is on, even while empty: MDBList lands in a second meta
    /// emission and must fade in without moving anything. Widest candidate that fits wins.
    private var ratingsSlot: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: ratings.count, through: 1, by: -1)), id: \.self) { visible in
                HStack(spacing: Theme.Spacing.lg) {
                    ForEach(ratings.prefix(visible)) { entry in
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(entry.label)
                                .font(Theme.Font.meta)
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Text(entry.value)
                                .font(Theme.Font.metaStrong)
                                .foregroundStyle(Theme.Palette.textPrimary)
                        }
                        .fixedSize()
                    }
                }
            }
        }
        .frame(maxWidth: DetailCinematicLayout.textColumnMaxWidth, alignment: .leading)
        .frame(height: DetailCinematicLayout.ratingsSlotHeight, alignment: .leading)
        .opacity(ratings.isEmpty ? 0 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: ratings.isEmpty)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail_ratings_strip")
    }

    /// Four lines in a fixed slot. D3: when the full text needs more, the teaser is a focusable
    /// button that opens the full text; otherwise plain text that focus skips.
    private var synopsisSlot: some View {
        Group {
            if synopsisTruncated {
                Button {
                    onOpenSynopsis()
                    showSynopsisSheet = true
                } label: {
                    // Batch C (Steven, rc2 reference photo), revised 2026-10-18 (Christian): the
                    // focused teaser draws a Liquid Glass platter so it reads as focused.
                    // BUG-192 (Steven rc9, D3): the "more" after the cut-off text is gone, with no
                    // affordance in its place; the focused glass already says it opens.
                    teaserText
                        .background { teaserPlatter(focused: heroFocus.wrappedValue == .teaser) }
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15),
                                   value: heroFocus.wrappedValue == .teaser)
                }
                .buttonStyle(.borderless)
                .focused(heroFocus, equals: .teaser)
                .accessibilityHint(String(localized: "Shows the full synopsis"))
                .accessibilityIdentifier("detail_synopsis_teaser")
            } else {
                teaserText
                    .accessibilityIdentifier("detail_synopsis_teaser")
            }
        }
        .frame(maxWidth: DetailCinematicLayout.textColumnMaxWidth, alignment: .topLeading)
        .frame(height: synopsisSlotHeight, alignment: .topLeading)
        .background(alignment: .topLeading) {
            // Measures the full (unclamped) text at the slot's width; the truncation decision
            // compares it against four lines (`DetailSynopsisTeaser.isTruncated`).
            Text(overview ?? "")
                .font(Theme.Font.synopsis)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { height in
                    if measuredSynopsisHeight != height { measuredSynopsisHeight = height }
                })
                .accessibilityHidden(true)
        }
        .background(alignment: .topLeading) {
            // Gate 1 fix: four rendered lines of the same font, whatever the title. Font-only, so
            // it lands on the first layout pass and never changes for the visit (correction F3).
            Text(verbatim: "Hg\nHg\nHg\nHg")
                .font(Theme.Font.synopsis)
                .lineLimit(DetailSynopsisTeaser.maxLines)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { height in
                    if measuredFourLineHeight != height { measuredFourLineHeight = height }
                })
                .accessibilityHidden(true)
        }
    }

    /// Same platter as `DetailAboutSection`'s focus: drawn outside the text through negative
    /// padding, so focusing the teaser never shifts the layout.
    /// Christian, 2026-10-18: Liquid Glass behind the focused teaser (chosen over About's surface
    /// fill on the TV). Drawn outside the text through negative padding, so nothing shifts;
    /// mounted only while focused, because a glass layer cannot fade by opacity.
    @ViewBuilder
    private func teaserPlatter(focused: Bool) -> some View {
        if focused {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.hero)
            shape
                .fill(Color.clear)
                .glassEffect(.regular, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5))
                .padding(-Theme.Spacing.md)
                .transition(.opacity)
        }
    }

    private var teaserText: some View {
        Text(overview ?? "")
            .font(Theme.Font.synopsis)
            .foregroundStyle(Theme.Palette.textPrimary)
            .lineLimit(DetailSynopsisTeaser.maxLines)
            .multilineTextAlignment(.leading)
            // Gate 1 fix: the line limit decides how many lines draw, never the proposed height
            // (a proposal a fraction short of four lines made SwiftUI drop to three). The slot
            // above is the measured four-line height, so this never overflows it.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: DetailCinematicLayout.textColumnMaxWidth, alignment: .topLeading)
    }

    /// Steven's fork (`synopsisBeside`): two lines of synopsis beside the action row and a chevron
    /// at their end. The chevron unfolds the full text IN PLACE, downward over a frosted platter
    /// (device pass 1: no full-screen sheet), and folds it back; Menu on the chevron folds it too.
    /// The block's layout height stays the two-line height (the unfolded text is an overlay), so
    /// nothing in the hero moves; the hero carries a zIndex in `DetailView` so the overlay draws
    /// over the rows below it.
    /// Menu folds an unfolded synopsis; nil otherwise, so Menu keeps its usual meaning (Back).
    private var foldSynopsisOnExit: (() -> Void)? {
        guard synopsisUnfolded else { return nil }
        return { setSynopsisUnfolded(false) }
    }

    private func setSynopsisUnfolded(_ unfolded: Bool) {
        withAnimation(reduceMotion ? nil : DetailAppleStyle.unfoldAnimation) {
            synopsisUnfolded = unfolded
            onSynopsisExtraHeight(unfolded ? max(0, synopsisFullHeight - synopsisFoldedHeight) : 0)
        }
    }

    /// Steven's fork (`synopsisBeside`): two lines of synopsis beside the action row and a chevron
    /// at their end. Device pass 2: the chevron unrolls the full text IN PLACE, downward (a clip
    /// that grows from two lines to the full height, no platter, nothing darkened), and the page
    /// below moves down by the same amount (`onSynopsisExtraHeight`, applied by `DetailView` under
    /// the hero), so nothing is covered. Menu on the chevron, or leaving the hero, rolls it back.
    private func synopsisBesideBlock(_ overview: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            // Two-line sizer: the block's layout height in both states.
            Text(overview)
                .font(Theme.Font.detail)
                .lineLimit(DetailAppleStyle.synopsisLines)
                .hidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { h in
                    if synopsisFoldedHeight != h { synopsisFoldedHeight = h }
                })
                .background(alignment: .topLeading) {
                    // Full-height probe at the same width.
                    Text(overview)
                        .font(Theme.Font.detail)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { h in
                            if synopsisFullHeight != h { synopsisFullHeight = h }
                        })
                }
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        Text(overview)
                            .lineLimit(DetailAppleStyle.synopsisLines)
                            .opacity(synopsisUnfolded ? 0 : 1)
                        Text(overview)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(synopsisUnfolded ? 1 : 0)
                    }
                    .font(Theme.Font.detail)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: synopsisUnfolded ? max(synopsisFullHeight, synopsisFoldedHeight) : synopsisFoldedHeight,
                           alignment: .top)
                    .clipped()
                    .accessibilityIdentifier("detail_synopsis_beside")
                }
            Button {
                setSynopsisUnfolded(!synopsisUnfolded)
            } label: {
                Image(systemName: "chevron.down")
                    .font(Theme.Font.metaStrong)
                    .rotationEffect(.degrees(synopsisUnfolded ? 180 : 0))
                    .frame(width: 44, height: 28)
            }
            .focused(heroFocus, equals: .teaser)
            .onExitCommand(perform: foldSynopsisOnExit)
            .accessibilityLabel(String(localized: "Shows the full synopsis"))
            .accessibilityIdentifier("detail_synopsis_more")
        }
        // Leaving the hero rolls it back, so the page never scrolls with it open.
        .onChange(of: heroFocus.wrappedValue) { _, focus in
            if focus == nil, synopsisUnfolded { setSynopsisUnfolded(false) }
        }
    }

    /// "With …" / "Directed by …" ("Created by …" for series), names in the primary colour.
    /// Interpolated `Text`, not `Text + Text` (deprecated in the 26 SDK).
    private var creditsBlock: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            if let cast = credits.castNames {
                Text("With \(Text(cast).foregroundStyle(Theme.Palette.textPrimary))")
                    .lineLimit(2)
            }
            if let crew = credits.crewNames, let label = credits.crewLabel {
                switch label {
                case .directedBy:
                    Text("Directed by \(Text(crew).foregroundStyle(Theme.Palette.textPrimary))")
                        .lineLimit(2)
                case .createdBy:
                    Text("Created by \(Text(crew).foregroundStyle(Theme.Palette.textPrimary))")
                        .lineLimit(2)
                }
            }
        }
        .font(Theme.Font.detail)
        .foregroundStyle(Theme.Palette.textSecondary)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: DetailCinematicLayout.creditsMaxWidth, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail_credits")
    }
}

