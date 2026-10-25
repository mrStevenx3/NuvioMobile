import SwiftUI
import SharedCore

/// The Library tab: the titles saved in the active library (the local Nuvio library, or the
/// Trakt / Simkl / MDBList library picked in Settings), plus — when a debrid provider with cloud
/// support is connected — a "Debrid Cloud" source listing the provider's cloud files for direct
/// playback.
///
/// Library L1 (2026-10-04, `docs/library-l1-grid-plan-2026-10-04.md` in the outer repo):
/// - header: title, a count line ("31 movies · 17 series") and a source badge (TRAKT / SIMKL /
///   MDBLIST);
/// - one control row: a List pill (the provider's lists), type segments (only with more than one
///   type), a Sort pill, and the smart filters Unwatched / In Progress / Watched (only the ones
///   that would change the grid);
/// - cards with a watched tick or a progress bar (`PosterCard.watchBadge`);
/// - a hold menu with Mark as Watched / Unwatched and a list-aware Remove;
/// - real loading, failed (with Retry), empty and no-match states.
struct LibraryView: View {
    @StateObject private var model = LibraryViewModel()
    @StateObject private var cloud = CloudLibraryViewModel()
    @State private var showingCloud = false
    @State private var filePicker: CloudFilePickerRoute?
    /// Steven's fork (Orbit Library): the stack's path, so the Orbit page can push a title.
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                // Steven's fork (2026-10-23): the Orbit Library page (`OrbitLibraryPage`).
                OrbitLibraryPage(model: model,
                                 cloudConnected: cloud.hasConnectedProvider,
                                 showingCloud: $showingCloud,
                                 onOpen: { path.append(TitleRoute(preview: $0)) },
                                 cloudContent: { cloudContent })
            }
            // Simkl: leaving a status also clears the title's watched history and rating there, so
            // the hold menu's remove asks first (`LibraryRepository.removalNeedsConfirmation`).
            .alert(
                LibraryGridPolicy.removeConfirmationTitle(listTitle: model.pendingRemoval?.listTitle),
                isPresented: Binding(
                    get: { model.pendingRemoval != nil },
                    set: { if !$0 { model.cancelRemoval() } }
                ),
                presenting: model.pendingRemoval
            ) { removal in
                Button(String(localized: "Remove"), role: .destructive) {
                    model.confirmRemoval(removal)
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    model.cancelRemoval()
                }
            } message: { removal in
                Text(LibraryGridPolicy.removeConfirmationMessage(providerName: removal.providerName))
            }
            .navigationDestination(for: TitleRoute.self) { route in
                DetailView(preview: route.preview)
            }
            .navigationDestination(for: PersonRoute.self) { route in
                PersonDetailView(personId: route.id, personName: route.name)
            }
            .navigationDestination(for: EntityRoute.self) { route in
                OrbitStudioPage(route: .entity(route))
            }
        }
        .environment(\.orbitPush, { path.append($0) })
        .orbitPopsToRootOnGoHome($path)
        // A failed remove. The shared toast controller is a no-op on tvOS, so the screen says it.
        .alert(
            LibraryGridPolicy.removeFailedTitle(providerName: model.providerName),
            isPresented: Binding(
                get: { model.actionError != nil },
                set: { if !$0 { model.actionError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                model.actionError = nil
            }
        } message: {
            Text(model.actionError ?? "")
        }
        .onAppear {
            model.start()
            cloud.start()
        }
        .onDisappear {
            model.stop()
            cloud.stop()
        }
        .fullScreenCover(item: $filePicker) { route in
            CloudFilePickerView(item: route.item) { file in
                cloud.play(item: route.item, file: file)
            }
        }
        .fullScreenCover(item: $cloud.playback) { ctx in
            // `.id` forces a fresh player per context (same rule as StreamPickerView).
            PlayerScreen(context: ctx)
                .ignoresSafeArea()
                .id(ctx.id)
        }
    }

    // MARK: - Header

    // MARK: - Saved library

    // MARK: - Control row (List · type · Sort · Refresh · smart filters)

    // MARK: - States

    // MARK: - Source switcher (Saved / Debrid Cloud)

    // MARK: - Debrid cloud content

    @ViewBuilder
    private var cloudContent: some View {
        if let error = cloud.errorMessage {
            Text(error)
                .font(Theme.Font.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: 1100, alignment: .leading)
        }

        HStack(spacing: Theme.Spacing.md) {
            Button {
                cloud.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(Theme.Font.meta)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
            }
            .buttonStyle(.chip)
            if cloud.isRefreshing {
                ProgressView()
            }
        }
        // Full-width section, same as `sourceChips`: Down from "Debrid Cloud" reaches Refresh.
        .focusRow(alignment: .leading)

        ForEach(cloud.providers, id: \.providerId) { provider in
            CloudProviderSection(
                provider: provider,
                resolvingFileKey: cloud.resolvingFileKey
            ) { item in
                selectCloudItem(item)
            }
        }
    }

    private func selectCloudItem(_ item: CloudLibraryItem) {
        let files = item.playableFiles
        if files.count == 1, let file = files.first {
            cloud.play(item: item, file: file)
        } else if !files.isEmpty {
            filePicker = CloudFilePickerRoute(item: item)
        }
    }
}
