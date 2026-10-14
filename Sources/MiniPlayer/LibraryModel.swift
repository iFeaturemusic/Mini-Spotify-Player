import Foundation
import Observation

@MainActor @Observable
final class LibraryModel {
    let api: SpotifyAPI
    let player: PlayerModel

    private(set) var likes: [Track] = []
    private(set) var likesTotal: Int?
    private(set) var likesLoading = false
    private(set) var likesError: String?
    @ObservationIgnored private var likesNext: String?
    @ObservationIgnored private var likesLoaded = false

    private(set) var playlists: [Playlist] = []
    private(set) var playlistsLoading = false
    private(set) var playlistsError: String?
    @ObservationIgnored private var playlistsNext: String?
    @ObservationIgnored private var playlistsLoaded = false

    private(set) var openPlaylist: Playlist?
    private(set) var playlistTracks: [Track] = []
    private(set) var playlistTracksLoading = false
    private(set) var playlistTracksHidden = false
    private(set) var playlistTracksError: String?
    @ObservationIgnored private var playlistTracksNext: String?

    var query = ""
    private(set) var results: [Track] = []
    private(set) var searching = false
    private(set) var searchError: String?
    @ObservationIgnored private var resultsNext: String?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    @ObservationIgnored private var userID: String?

    init(api: SpotifyAPI, player: PlayerModel) {
        self.api = api
        self.player = player
    }

    func reset() {
        likes = []; likesTotal = nil; likesNext = nil; likesLoaded = false
        playlists = []; playlistsNext = nil; playlistsLoaded = false
        openPlaylist = nil; playlistTracks = []; playlistTracksNext = nil; playlistTracksHidden = false
        query = ""; results = []; resultsNext = nil
        likesError = nil; playlistsError = nil; playlistTracksError = nil; searchError = nil
        userID = nil
    }

    private func describe(_ error: Error) -> String {
        (error as? SpotifyError)?.userMessage ?? error.localizedDescription
    }

    // MARK: - Likes

    func loadLikesIfNeeded() async {
        if !likesLoaded { await loadLikes(reset: true) }
    }

    func loadLikes(reset: Bool = false) async {
        guard !likesLoading else { return }
        let firstPage = reset || !likesLoaded
        guard firstPage || likesNext != nil else { return }
        likesLoading = true
        defer { likesLoading = false }
        do {
            let page = firstPage
                ? try await api.get("/me/tracks", query: ["limit": "50"], as: Paging<SavedTrack>.self)
                : try await api.get(likesNext!, as: Paging<SavedTrack>.self)
            let tracks = page.items.map(\.track)
            likes = firstPage ? tracks : likes + tracks
            likesNext = page.next
            likesTotal = page.total
            likesLoaded = true
            likesError = nil
        } catch {
            if firstPage { likesError = describe(error) } else { player.show(error) }
        }
    }

    func likeChanged(_ track: Track, saved: Bool) {
        if saved {
            guard !likes.contains(where: { $0.uri == track.uri }) else { return }
            likes.insert(track, at: 0)
            likesTotal = likesTotal.map { $0 + 1 }
        } else {
            let before = likes.count
            likes.removeAll { $0.uri == track.uri }
            if likes.count != before { likesTotal = likesTotal.map { max(0, $0 - 1) } }
        }
    }

    func setLiked(_ track: Track, _ saved: Bool) {
        Task {
            do {
                try await api.setSaved(track, saved: saved)
                likeChanged(track, saved: saved)
                player.likeChangedElsewhere(uri: track.uri, saved: saved)
                player.flash(saved ? L("Zu Lieblingssongs hinzugefügt") : L("Aus Lieblingssongs entfernt"))
            } catch {
                player.show(error)
            }
        }
    }

    private func likesContextURI() async -> String? {
        if userID == nil {
            userID = try? await api.get("/me", as: Me.self).id
        }
        return userID.map { "spotify:user:\($0):collection" }
    }

    func playLike(at index: Int) {
        guard likes.indices.contains(index) else { return }
        let track = likes[index]
        let fallback = likes[index..<min(likes.count, index + 100)].map(\.uri)
        Task {
            if let context = await likesContextURI(),
               await player.startPlayback(context: context, offsetURI: track.uri, reportErrors: false) {
                return
            }
            await player.startPlayback(uris: fallback)
        }
    }

    func playAllLikes(shuffled: Bool) {
        let fallback = Array(likes.prefix(100).map(\.uri))
        let startIndex = shuffled && !likes.isEmpty ? Int.random(in: 0..<likes.count) : 0
        Task {
            var ok = false
            if let context = await likesContextURI() {
                ok = await player.startPlayback(context: context,
                                                offsetURI: likes.indices.contains(startIndex) ? likes[startIndex].uri : nil,
                                                reportErrors: false)
            }
            if !ok {
                ok = await player.startPlayback(uris: fallback, offsetIndex: min(startIndex, max(0, fallback.count - 1)))
            }
            if ok { player.setShuffle(shuffled) }
        }
    }

    // MARK: - Playlists

    func loadPlaylistsIfNeeded() async {
        if !playlistsLoaded { await loadPlaylists(reset: true) }
    }

    func loadPlaylists(reset: Bool = false) async {
        guard !playlistsLoading else { return }
        let firstPage = reset || !playlistsLoaded
        guard firstPage || playlistsNext != nil else { return }
        playlistsLoading = true
        defer { playlistsLoading = false }
        do {
            let page = firstPage
                ? try await api.get("/me/playlists", query: ["limit": "50"], as: Paging<Playlist>.self)
                : try await api.get(playlistsNext!, as: Paging<Playlist>.self)
            playlists = firstPage ? page.items : playlists + page.items
            playlistsNext = page.next
            playlistsLoaded = true
            playlistsError = nil
        } catch {
            if firstPage { playlistsError = describe(error) } else { player.show(error) }
        }
    }

    func open(_ playlist: Playlist) {
        openPlaylist = playlist
        playlistTracks = []
        playlistTracksNext = nil
        playlistTracksHidden = false
        playlistTracksError = nil
        Task { await loadPlaylistTracks(first: true) }
    }

    func closePlaylist() {
        openPlaylist = nil
        playlistTracks = []
    }

    func loadPlaylistTracks(first: Bool = false) async {
        guard let playlist = openPlaylist, !playlistTracksLoading else { return }
        guard first || playlistTracksNext != nil else { return }
        playlistTracksLoading = true
        defer { playlistTracksLoading = false }

        do {
            let page: Paging<PlaylistItem>
            if first {
                page = try await firstPlaylistPage(playlist.id)
            } else {
                page = try await api.get(playlistTracksNext!, as: Paging<PlaylistItem>.self)
            }
            guard openPlaylist?.id == playlist.id else { return }
            let tracks = page.items.compactMap(\.track)
            playlistTracks = first ? tracks : playlistTracks + tracks
            playlistTracksNext = page.next
            if first, tracks.isEmpty, (playlist.total ?? 0) > 0 { playlistTracksHidden = true }
        } catch let error as SpotifyError where (error.status == 403 || error.status == 404)
                    && !error.message.localizedCaseInsensitiveContains("not be registered") {
            if openPlaylist?.id == playlist.id { playlistTracksHidden = true }
        } catch {
            if first { playlistTracksError = describe(error) } else { player.show(error) }
        }
    }

    private func firstPlaylistPage(_ id: String) async throws -> Paging<PlaylistItem> {
        let query = ["limit": "50", "additional_types": "episode"]
        do {
            return try await api.get("/playlists/\(id)/items", query: query, as: Paging<PlaylistItem>.self)
        } catch let error as SpotifyError where error.status == 404 || error.status == 403 {
            return try await api.get("/playlists/\(id)/tracks", query: query, as: Paging<PlaylistItem>.self)
        }
    }

    func playPlaylist(_ playlist: Playlist, shuffled: Bool) {
        let total = playlist.total ?? 0
        let offset = shuffled && total > 0 ? Int.random(in: 0..<total) : nil
        Task {
            if await player.startPlayback(context: playlist.uri, offsetIndex: offset) {
                player.setShuffle(shuffled)
            }
        }
    }

    func playPlaylistTrack(at index: Int) {
        guard let playlist = openPlaylist, playlistTracks.indices.contains(index) else { return }
        let track = playlistTracks[index]
        if track.uri.hasPrefix("spotify:local:") {
            player.play(context: playlist.uri, offsetIndex: index)
        } else {
            player.play(context: playlist.uri, offsetURI: track.uri)
        }
    }

    // MARK: - Search

    func queryChanged() {
        searchTask?.cancel()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            resultsNext = nil
            searching = false
            searchError = nil
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.search(term)
        }
    }

    private func search(_ term: String) async {
        searching = true
        defer { searching = false }
        do {
            let result = try await api.get("/search",
                                           query: Self.searchQuery(term),
                                           as: SearchResult.self)
            guard !Task.isCancelled, term == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            results = result.tracks?.items ?? []
            resultsNext = result.tracks?.next
            searchError = nil
        } catch {
            if !Task.isCancelled { searchError = describe(error) }
        }
    }

    /// Spotify allows at most 10 results per page since 2026. No `market` parameter:
    /// `market=from_token` would require the `user-read-private` scope for search, and with a
    /// user token Spotify applies the account's country anyway.
    static func searchQuery(_ term: String) -> [String: String] {
        ["q": term, "type": "track", "limit": "10"]
    }

    func loadMoreResults() async {
        guard let next = resultsNext, !searching, results.count < 200 else { return }
        searching = true
        defer { searching = false }
        do {
            let result = try await api.get(next, as: SearchResult.self)
            results += result.tracks?.items ?? []
            resultsNext = result.tracks?.next
        } catch {
            player.show(error)
        }
    }

    func playResult(at index: Int) {
        guard results.indices.contains(index) else { return }
        player.play(uris: results.map(\.uri), offsetIndex: index)
    }
}

#if DEBUG
extension LibraryModel {
    func setDemo(likes: [Track], likesTotal: Int, playlists: [Playlist], results: [Track], query: String) {
        self.likes = likes
        self.likesTotal = likesTotal
        likesLoaded = true
        self.playlists = playlists
        playlistsLoaded = true
        self.results = results
        self.query = query
    }

    func setDemoOpenPlaylist(_ playlist: Playlist?, tracks: [Track]) {
        openPlaylist = playlist
        playlistTracks = tracks
    }
}
#endif
