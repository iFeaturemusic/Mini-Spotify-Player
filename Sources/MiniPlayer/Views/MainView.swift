import SwiftUI

enum LibraryTab: String, CaseIterable {
    case likes = "Likes"
    case playlists = "Playlists"
    case search = "Suche"

    var title: String { L(rawValue) }

    var icon: String {
        switch self {
        case .likes: "heart.fill"
        case .playlists: "music.note.list"
        case .search: "magnifyingglass"
        }
    }
}

struct MainView: View {
    @Environment(AppStore.self) private var store
    @Environment(PlayerModel.self) private var player
    @Environment(ArtworkModel.self) private var artwork
    @Environment(LyricsModel.self) private var lyrics
    @AppStorage("tab") private var tab: LibraryTab = .likes

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingView()
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, store.compact ? 14 : 10)

            if !store.compact {
                librarySection
            }
        }
        .animation(.easeInOut(duration: 0.25), value: lyrics.isShown)
        .animation(.easeInOut(duration: 0.25), value: store.settingsShown)
        .background { AmbientBackground() }
        .environment(\.accent, artwork.accent)
        .tint(artwork.accent)
        .overlay(alignment: .bottom) {
            if let message = player.message {
                Banner(text: message)
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: player.message)
    }

    @ViewBuilder
    private var librarySection: some View {
        EngineCard()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

        if store.settingsShown {
            SettingsView()
                .transition(.opacity)
        } else if lyrics.isShown {
            LyricsView()
                .transition(.opacity)
        } else {
            TabBar(selection: $tab)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider().opacity(0.5)

            Group {
                switch tab {
                case .likes: LikesView()
                case .playlists: PlaylistsView()
                case .search: SearchView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// "Ambient light": a heavily blurred, saturated copy of the cover behind the whole player.
private struct AmbientBackground: View {
    @Environment(ArtworkModel.self) private var artwork

    var body: some View {
        ZStack {
            if let backdrop = artwork.backdrop {
                Image(nsImage: backdrop)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
                    .id(artwork.key)
            }
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
    }
}

private struct TabBar: View {
    @Binding var selection: LibraryTab
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            ForEach(LibraryTab.allCases, id: \.self) { tab in
                let selected = selection == tab
                Button { selection = tab } label: {
                    Label(tab.title, systemImage: tab.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .foregroundStyle(selected ? Color.black : Color.primary)
                        .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.12)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            IconButton(systemName: "gearshape", size: 12, tint: .secondary, help: L("Einstellungen")) {
                store.showSettings(true)
            }
        }
    }
}

private struct SectionHeader<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 13, weight: .bold))
                if let detail {
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Likes

private struct LikesView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.accent) private var accent
    @Environment(PlayerModel.self) private var player

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: L("Lieblingssongs"), detail: library.likesTotal.map { L("%d Songs", $0) }) {
                IconButton(systemName: "arrow.clockwise", size: 11, tint: .secondary, help: L("Neu laden")) {
                    Task { await library.loadLikes(reset: true) }
                }
                IconButton(systemName: "shuffle", size: 12, tint: .secondary, help: L("Zufällig abspielen")) {
                    library.playAllLikes(shuffled: true)
                }
                PlayCircle(playing: false, size: 28, color: accent) {
                    library.playAllLikes(shuffled: false)
                }
                .disabled(library.likes.isEmpty)
            }
            TrackList(tracks: library.likes,
                      loading: library.likesLoading,
                      emptyText: L("Noch keine Lieblingssongs."),
                      error: library.likesError,
                      inLikes: true,
                      onPlay: { library.playLike(at: $0) },
                      onReachEnd: { Task { await library.loadLikes() } },
                      onRetry: { Task { await library.loadLikes(reset: true) } })
        }
        .task { await library.loadLikesIfNeeded() }
    }
}

// MARK: - Playlists

private struct PlaylistsView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        if let playlist = library.openPlaylist {
            PlaylistDetailView(playlist: playlist)
        } else {
            VStack(spacing: 0) {
                SectionHeader(title: L("Deine Playlists"), detail: library.playlists.isEmpty ? nil : "\(library.playlists.count)") {
                    IconButton(systemName: "arrow.clockwise", size: 11, tint: .secondary, help: L("Neu laden")) {
                        Task { await library.loadPlaylists(reset: true) }
                    }
                }
                ListScroll {
                    ForEach(Array(library.playlists.enumerated()), id: \.offset) { index, playlist in
                        PlaylistRow(playlist: playlist) { library.open(playlist) }
                            .onAppear {
                                if index == library.playlists.count - 1 {
                                    Task { await library.loadPlaylists() }
                                }
                            }
                    }
                    if library.playlistsLoading {
                        ProgressView().controlSize(.small).padding(14)
                    } else if let error = library.playlistsError, library.playlists.isEmpty {
                        ErrorState(text: error) { Task { await library.loadPlaylists(reset: true) } }
                    } else if library.playlists.isEmpty {
                        Text(L("Keine Playlists gefunden."))
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 40)
                    }
                }
            }
            .task { await library.loadPlaylistsIfNeeded() }
        }
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RemoteImage(url: playlist.images?.url(fitting: 60), size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.white.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let owner = playlist.owner?.displayName { parts.append(owner) }
        if let total = playlist.total { parts.append(L("%d Songs", total)) }
        return parts.joined(separator: " · ")
    }
}

private struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(LibraryModel.self) private var library
    @Environment(\.accent) private var accent
    @Environment(PlayerModel.self) private var player

    var body: some View {
        let isThisPlaying = player.isPlaying && player.contextURI == playlist.uri
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                IconButton(systemName: "chevron.left", size: 12, help: L("Zurück")) { library.closePlaylist() }
                RemoteImage(url: playlist.images?.url(fitting: 120), size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    Text(playlist.total.map { L("%d Songs", $0) } ?? "Playlist")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                IconButton(systemName: "shuffle", size: 12, tint: .secondary, help: L("Zufällig abspielen")) {
                    library.playPlaylist(playlist, shuffled: true)
                }
                PlayCircle(playing: isThisPlaying, size: 30, color: accent) {
                    if isThisPlaying {
                        player.togglePlay()
                    } else {
                        library.playPlaylist(playlist, shuffled: false)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Divider().opacity(0.5)

            if library.playlistTracksHidden {
                VStack(spacing: 8) {
                    Image(systemName: "lock").font(.system(size: 20)).foregroundStyle(.secondary)
                    Text(L("Spotify zeigt die Songs nur für eigene Playlists an.\nAbspielen funktioniert trotzdem."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                .padding(.horizontal, 20)
                Spacer()
            } else {
                TrackList(tracks: library.playlistTracks,
                          loading: library.playlistTracksLoading,
                          emptyText: L("Diese Playlist ist leer."),
                          error: library.playlistTracksError,
                          onPlay: { library.playPlaylistTrack(at: $0) },
                          onReachEnd: { Task { await library.loadPlaylistTracks() } },
                          onRetry: { Task { await library.loadPlaylistTracks(first: true) } })
            }
        }
    }
}

// MARK: - Search

private struct SearchView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.screenshotMode) private var screenshotMode
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var library = library
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if screenshotMode {
                    Text(library.query).font(.system(size: 13))
                    Spacer(minLength: 0)
                } else {
                    TextField(L("Songs, Künstler, Alben …"), text: $library.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focused)
                }
                if !library.query.isEmpty {
                    Button { library.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .onChange(of: library.query) { library.queryChanged() }

            TrackList(tracks: library.results,
                      loading: library.searching,
                      emptyText: library.query.isEmpty ? L("Finde neue Songs auf Spotify.") : L("Keine Treffer."),
                      error: library.searchError,
                      onPlay: { library.playResult(at: $0) },
                      onReachEnd: { Task { await library.loadMoreResults() } })
        }
        .onAppear { focused = true }
    }
}
