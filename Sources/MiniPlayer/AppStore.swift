import Foundation
import Observation

@MainActor @Observable
final class AppStore {
    let auth: SpotifyAuth
    let api: SpotifyAPI
    let engine: PlaybackEngine
    let player: PlayerModel
    let library: LibraryModel
    let artwork = ArtworkModel()
    let lyrics = LyricsModel()

    var editingClientID = false
    /// Settings page replaces the library section (like the lyrics view).
    private(set) var settingsShown = false
    /// Library hidden, only the cover is shown.
    private(set) var compact = UserDefaults.standard.bool(forKey: "compact")
    /// Player lives in its own floating window instead of the menu bar popover.
    private(set) var detached = UserDefaults.standard.bool(forKey: "detached")

    @ObservationIgnored private var popoverOpen = false
    @ObservationIgnored private var windowVisible = false

    @ObservationIgnored var showPlayer: (() -> Void)?
    @ObservationIgnored var onLayoutChanged: (() -> Void)?
    @ObservationIgnored var onDetachedChanged: ((Bool) -> Void)?

    init() {
        auth = SpotifyAuth()
        api = SpotifyAPI(auth: auth)
        engine = PlaybackEngine()
        player = PlayerModel(api: api, engine: engine)
        library = LibraryModel(api: api, player: player)

        player.onTrackChanged = { [weak artwork, weak lyrics] track in
            artwork?.update(for: track)
            lyrics?.trackChanged(track)
        }
        lyrics.onVisibilityChanged = { [weak self] visible in
            self?.player.setFastTicks(visible)
            if visible {
                self?.settingsShown = false
                if self?.compact == true { self?.setCompact(false) }
            }
        }
        player.onLikeChanged = { [weak library] track, saved in
            library?.likeChanged(track, saved: saved)
        }
        AppSettings.shared.onQualityChanged = { [weak self] _ in
            MainActor.assumeIsolated { self?.restartEngineKeepingPlayback() }
        }
        auth.onLogin = { [weak self] in self?.didLogin() }
        auth.onLogout = { [weak self] in
            self?.player.reset()
            self?.library.reset()
            self?.engine.forgetCredentials()
            self?.onLayoutChanged?()
        }
    }

    func launched() {
        engine.killOrphan()
        if auth.isLoggedIn {
            if engine.hasCredentials { engine.start() }
            Task { await player.refresh(force: true) }
        }
    }

    func terminate() {
        engine.stop()
    }

    /// librespot reads the bitrate at start, so a new quality needs a restart.
    /// If MiniPlayer itself was playing, playback resumes where it was.
    private func restartEngineKeepingPlayback() {
        guard engine.isRunning else { return }
        let wasPlayingHere = player.isPlaying && player.device?.id == PlaybackEngine.deviceID
        engine.restart()
        guard wasPlayingHere else { return }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await player.startPlayback()
        }
    }

    // MARK: - Layout

    /// Compact only applies to the player itself, not to the setup and login screens.
    var compactLayout: Bool {
        compact && auth.isLoggedIn && !auth.clientID.isEmpty && !editingClientID
    }

    func showSettings(_ show: Bool) {
        settingsShown = show
        if show {
            lyrics.hide()
            if compact { setCompact(false) }
        }
    }

    func setCompact(_ value: Bool) {
        guard value != compact else { return }
        compact = value
        UserDefaults.standard.set(value, forKey: "compact")
        if value {
            lyrics.hide()
            settingsShown = false
        }
        onLayoutChanged?()
    }

    func setDetached(_ value: Bool) {
        guard value != detached else { return }
        detached = value
        UserDefaults.standard.set(value, forKey: "detached")
        onDetachedChanged?(value)
    }

    // MARK: - Visibility

    func popoverDidOpen() {
        popoverOpen = true
        updateVisibility()
    }

    func popoverDidClose() {
        popoverOpen = false
        updateVisibility()
    }

    /// The detached window counts as visible only while it is on screen and not fully covered.
    func setWindowVisible(_ visible: Bool) {
        guard visible != windowVisible else { return }
        windowVisible = visible
        updateVisibility()
    }

    private func updateVisibility() {
        player.setVisible(auth.isLoggedIn && (popoverOpen || windowVisible))
    }

    func logout() {
        settingsShown = false
        auth.logout()
    }

    private func didLogin() {
        player.reset()
        library.reset()
        if engine.hasCredentials { engine.start() }
        onLayoutChanged?()
        if popoverOpen || windowVisible {
            updateVisibility()
        } else {
            showPlayer?()
        }
    }
}
