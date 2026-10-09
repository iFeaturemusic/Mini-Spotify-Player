import Foundation

/// `MiniPlayer --selftest [--play] [--seconds N]` checks login, library, search and devices.
/// With `--play` it plays a liked song on "MiniPlayer" at 25 % volume, then pauses.
@MainActor
enum SelfTest {
    static func run(play: Bool, seconds: Int = 6) async -> Int32 {
        let auth = SpotifyAuth()
        guard auth.isLoggedIn else {
            print("✗ Not signed in")
            return 1
        }
        let api = SpotifyAPI(auth: auth)
        var failures = 0

        func step(_ name: String, _ body: () async throws -> String) async {
            do {
                print("✓ \(name): \(try await body())")
            } catch let error as SpotifyError {
                failures += 1
                print("✗ \(name): \(error.status) \(error.reason ?? "") \(error.message)")
            } catch {
                failures += 1
                print("✗ \(name): \(error.localizedDescription)")
            }
        }

        var firstLike: Track?
        var engineDeviceFound = false

        await step("Profile") {
            let me = try await api.get("/me", as: Me.self)
            return "signed in (id \(me.id.prefix(4))…)"
        }
        await step("Likes") {
            let page = try await api.get("/me/tracks", query: ["limit": "3"], as: Paging<SavedTrack>.self)
            firstLike = page.items.first?.track
            return "\(page.total ?? page.items.count) songs, e.g. \"\(firstLike?.name ?? "-")\""
        }
        var ownPlaylist: Playlist?
        await step("Playlists") {
            let page = try await api.get("/me/playlists", query: ["limit": "50"], as: Paging<Playlist>.self)
            ownPlaylist = page.items.first { ($0.total ?? 0) > 0 }
            return "\(page.total ?? page.items.count) playlists"
        }
        if let playlist = ownPlaylist {
            await step("Playlist items (\"\(playlist.name)\")") {
                do {
                    let page = try await api.get("/playlists/\(playlist.id)/items", query: ["limit": "3"], as: Paging<PlaylistItem>.self)
                    return "\(page.items.compactMap(\.track).count) loaded"
                } catch let error as SpotifyError where error.status == 403 || error.status == 404 {
                    return "not visible (playlist owned by someone else, \(error.status)), playback still works"
                }
            }
        }
        await step("Search (\"Daft Punk\")") {
            let result = try await api.get("/search", query: LibraryModel.searchQuery("Daft Punk"), as: SearchResult.self)
            return (result.tracks?.items ?? []).map(\.name).joined(separator: ", ")
        }
        await step("Devices") {
            let devices = try await api.get("/me/player/devices", as: DeviceList.self).devices
            engineDeviceFound = devices.contains { $0.id == PlaybackEngine.deviceID }
            let names = devices.map { "\($0.name)\($0.isActive == true ? " (active)" : "")" }
            return names.isEmpty ? "none" : names.joined(separator: ", ")
        }

        if play {
            await step("Playback") {
                guard engineDeviceFound else { return "skipped, device \"MiniPlayer\" not found (is the app running?)" }
                guard let track = firstLike else { return "skipped, no song to test with" }

                let current = try await api.send("GET", "/me/player")
                if !current.isEmpty, let state = try? api.decoder.decode(PlaybackState.self, from: current),
                   state.isPlaying, state.device?.id != PlaybackEngine.deviceID {
                    return "skipped, currently playing on \"\(state.device?.name ?? "another device")\""
                }

                let device = PlaybackEngine.deviceID
                try await api.send("PUT", "/me/player", json: ["device_ids": [device], "play": false])
                try await Task.sleep(for: .milliseconds(800))
                try await api.send("PUT", "/me/player/volume", query: ["volume_percent": "25", "device_id": device])
                try await api.send("PUT", "/me/player/play", query: ["device_id": device], json: ["uris": [track.uri]])
                try await Task.sleep(for: .seconds(seconds))

                let data = try await api.send("GET", "/me/player")
                let state = data.isEmpty ? nil : try? api.decoder.decode(PlaybackState.self, from: data)
                _ = try? await api.send("PUT", "/me/player/pause", query: ["device_id": device])

                guard let state, state.isPlaying, state.device?.id == device else {
                    throw SpotifyError(status: 0, message: "playback did not start", reason: nil)
                }
                return "\"\(state.item?.name ?? track.name)\" played on \"\(state.device?.name ?? "")\" until \(formatTime(state.progressMs)), then paused"
            }
        }

        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
        return failures == 0 ? 0 : 1
    }
}
