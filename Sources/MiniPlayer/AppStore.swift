import Foundation
import Observation

@MainActor @Observable
final class AppStore {
    let auth: SpotifyAuth
    let api: SpotifyAPI
    let engine: PlaybackEngine
    let player: PlayerModel
    let library: LibraryModel

    private(set) var popoverOpen = false
    var editingClientID = false

    @ObservationIgnored var showPopover: (() -> Void)?

    init() {
        auth = SpotifyAuth()
        api = SpotifyAPI(auth: auth)
        engine = PlaybackEngine()
        player = PlayerModel(api: api, engine: engine)
        library = LibraryModel(api: api, player: player)

        player.onLikeChanged = { [weak library] track, saved in
            library?.likeChanged(track, saved: saved)
        }
        auth.onLogin = { [weak self] in self?.didLogin() }
        auth.onLogout = { [weak self] in
            self?.player.reset()
            self?.library.reset()
            self?.engine.forgetCredentials()
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

    func popoverDidOpen() {
        popoverOpen = true
        if auth.isLoggedIn { player.setVisible(true) }
    }

    func popoverDidClose() {
        popoverOpen = false
        player.setVisible(false)
    }

    func logout() {
        auth.logout()
    }

    private func didLogin() {
        player.reset()
        library.reset()
        if engine.hasCredentials { engine.start() }
        if popoverOpen {
            player.setVisible(true)
        } else {
            showPopover?()
        }
    }
}
