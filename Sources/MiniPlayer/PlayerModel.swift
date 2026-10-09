import AppKit
import Observation

@MainActor @Observable
/// Playback state and Spotify Connect commands.
/// Polls only while the popover is open; the progress bar is interpolated locally.
final class PlayerModel {
    private(set) var track: Track?
    private(set) var isPlaying = false
    private(set) var progressMs = 0
    private(set) var now = Date()
    private(set) var shuffle = false
    private(set) var repeatMode = "off"
    private(set) var volume: Double = 0.5
    private(set) var device: Device?
    private(set) var devices: [Device] = []
    private(set) var isLiked = false
    private(set) var contextURI: String?
    private(set) var message: String?

    @ObservationIgnored var onStatusChanged: (() -> Void)?
    @ObservationIgnored var onLikeChanged: ((Track, Bool) -> Void)?

    let api: SpotifyAPI
    let engine: PlaybackEngine

    @ObservationIgnored private var progressStamp = Date()
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var messageTask: Task<Void, Never>?
    @ObservationIgnored private var lastRefresh = Date.distantPast
/// Right after a command Spotify may still report the old state; polls are ignored briefly.
    @ObservationIgnored private var holdUntil = Date.distantPast
    @ObservationIgnored private var likeCheckedURI: String?

    init(api: SpotifyAPI, engine: PlaybackEngine) {
        self.api = api
        self.engine = engine
    }

    var durationMs: Int { track?.duration ?? 0 }

    func position(at date: Date) -> Int {
        guard isPlaying else { return progressMs }
        let position = progressMs + Int(date.timeIntervalSince(progressStamp) * 1000)
        return durationMs > 0 ? min(position, durationMs) : position
    }

    // MARK: - Polling

    func setVisible(_ isVisible: Bool) {
        visible = isVisible
        pollTask?.cancel()
        pollTask = nil
        if isVisible {
            now = Date()
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            Task { await loadDevices() }
        }
        updateTicker()
    }

    func reset() {
        track = nil
        setPlaying(false)
        progressMs = 0
        device = nil
        devices = []
        isLiked = false
        contextURI = nil
        likeCheckedURI = nil
        onStatusChanged?()
    }

    func refresh(force: Bool = false) async {
        lastRefresh = Date()
        do {
            let data = try await api.send("GET", "/me/player", query: ["additional_types": "episode"])
            if !force && Date() < holdUntil { return }
            if data.isEmpty {
                setPlaying(false)
                if device != nil { device = nil }
                return
            }
            apply(try api.decoder.decode(PlaybackState.self, from: data))
        } catch {
        }
    }

    private func apply(_ state: PlaybackState) {
        let trackChanged = track?.uri != state.item?.uri
        if trackChanged {
            track = state.item
            isLiked = false
        }
        progressMs = state.progressMs
        progressStamp = Date()
        now = progressStamp
        setPlaying(state.isPlaying)
        if shuffle != state.shuffleState { shuffle = state.shuffleState }
        if repeatMode != state.repeatState { repeatMode = state.repeatState }
        if device != state.device { device = state.device }
        if state.isPlaying, state.device?.id == PlaybackEngine.deviceID { engine.markHealthy() }
        if let percent = state.device?.volumePercent {
            let value = Double(percent) / 100
            if abs(value - volume) > 0.005 { volume = value }
        }
        if contextURI != state.context?.uri { contextURI = state.context?.uri }
        if trackChanged { onStatusChanged?() }

        if let track, track.uri != likeCheckedURI {
            likeCheckedURI = track.uri
            Task {
                if let saved = await api.isSaved(track), self.track?.uri == track.uri, saved != isLiked {
                    isLiked = saved
                }
            }
        }
    }

    private func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else { return }
        if !playing { progressMs = position(at: Date()) }
        progressStamp = Date()
        isPlaying = playing
        onStatusChanged?()
        updateTicker()
    }

    private func updateTicker() {
        let shouldRun = visible && isPlaying
        if shouldRun, tickTask == nil {
            tickTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    self.now = Date()
                    if self.durationMs > 0, self.position(at: self.now) >= self.durationMs,
                       Date().timeIntervalSince(self.lastRefresh) > 2 {
                        await self.refresh(force: true)
                    }
                }
            }
        } else if !shouldRun {
            tickTask?.cancel()
            tickTask = nil
        }
    }

    private func refreshSoon() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            for delay in [0.5, 1.5] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await self?.refresh(force: true)
            }
        }
    }

    func handleLocalSpotifyChange(_ info: [AnyHashable: Any]?) {
        if visible {
            refreshSoon()
        } else if let state = info?["Player State"] as? String {
            setPlaying(state == "Playing")
        }
    }

    // MARK: - Commands

    func togglePlay() {
        if isPlaying {
            setPlaying(false)
            if device?.id == PlaybackEngine.deviceID { engine.audio.flush() }
            run { try await self.api.send("PUT", "/me/player/pause") }
        } else {
            Task { await startPlayback() }
        }
    }

    func next() {
        run { try await self.api.send("POST", "/me/player/next") }
    }

    func previous() {
        run { try await self.api.send("POST", "/me/player/previous") }
    }

    func seek(to ms: Int) {
        progressMs = ms
        progressStamp = Date()
        now = progressStamp
        run { try await self.api.send("PUT", "/me/player/seek", query: ["position_ms": String(ms)]) }
    }

    func toggleShuffle() {
        setShuffle(!shuffle)
    }

    func setShuffle(_ value: Bool) {
        shuffle = value
        run { try await self.api.send("PUT", "/me/player/shuffle", query: ["state": value ? "true" : "false"]) }
    }

    func cycleRepeat() {
        let next = ["off": "context", "context": "track"][repeatMode] ?? "off"
        repeatMode = next
        run { try await self.api.send("PUT", "/me/player/repeat", query: ["state": next]) }
    }

    func setVolume(_ value: Double) {
        volume = value
        run(refreshAfter: false) {
            try await self.api.send("PUT", "/me/player/volume", query: ["volume_percent": String(Int((value * 100).rounded()))])
        }
    }

    func addToQueue(_ track: Track) {
        Task {
            do {
                try await api.send("POST", "/me/player/queue", query: ["uri": track.uri])
                flash("Zur Warteschlange hinzugefügt")
            } catch {
                show(error)
            }
        }
    }

    func toggleLike() {
        guard let track else { return }
        let saved = !isLiked
        isLiked = saved
        Task {
            do {
                try await api.setSaved(track, saved: saved)
                onLikeChanged?(track, saved)
            } catch {
                if self.track?.uri == track.uri { isLiked = !saved }
                show(error)
            }
        }
    }

    func likeChangedElsewhere(uri: String, saved: Bool) {
        if track?.uri == uri { isLiked = saved }
    }

    func play(context: String? = nil, uris: [String]? = nil, offsetURI: String? = nil, offsetIndex: Int? = nil) {
        Task { await startPlayback(context: context, uris: uris, offsetURI: offsetURI, offsetIndex: offsetIndex) }
    }

    @discardableResult
    func startPlayback(context: String? = nil, uris: [String]? = nil, offsetURI: String? = nil,
                       offsetIndex: Int? = nil, reportErrors: Bool = true) async -> Bool {
        var body: [String: Any] = [:]
        if let context { body["context_uri"] = context }
        if let uris { body["uris"] = uris }
        if let offsetURI {
            body["offset"] = ["uri": offsetURI]
        } else if let offsetIndex {
            body["offset"] = ["position": offsetIndex]
        }

        setPlaying(true)
        holdUntil = Date().addingTimeInterval(1)
        defer { refreshSoon() }

        do {
            try await sendPlay(body, deviceID: nil)
            return true
        } catch let error as SpotifyError where error.isNoActiveDevice {
            do {
                let deviceID = try await pickDevice()
                if body.isEmpty {
                    try await transfer(to: deviceID, play: true)
                } else {
                    try await sendPlay(body, deviceID: deviceID)
                }
                return true
            } catch {
                setPlaying(false)
                if reportErrors { show(error) }
                return false
            }
        } catch {
            setPlaying(false)
            if reportErrors { show(error) }
            return false
        }
    }

    private func sendPlay(_ body: [String: Any], deviceID: String?) async throws {
        try await api.send("PUT", "/me/player/play",
                           query: deviceID.map { ["device_id": $0] } ?? [:],
                           json: body.isEmpty ? nil : body)
    }

    private func run(refreshAfter: Bool = true, _ operation: @escaping () async throws -> Void) {
        holdUntil = Date().addingTimeInterval(1)
        Task {
            do {
                try await operation()
            } catch let error as SpotifyError where error.isNoActiveDevice {
                do {
                    try await transfer(to: try await pickDevice(), play: false)
                    try await operation()
                } catch {
                    show(error)
                }
            } catch {
                show(error)
            }
            if refreshAfter { refreshSoon() }
        }
    }

    // MARK: - Devices

    @discardableResult
    func fetchDevices() async throws -> [Device] {
        let list = try await api.get("/me/player/devices", as: DeviceList.self).devices
        if devices != list { devices = list }
        return list
    }

    func loadDevices() async {
        _ = try? await fetchDevices()
    }

    func select(_ device: Device) {
        guard let id = device.id else { return }
        let wasPlaying = isPlaying
        run { try await self.transfer(to: id, play: wasPlaying) }
    }

    private func transfer(to deviceID: String, play: Bool) async throws {
        try await api.send("PUT", "/me/player", json: ["device_ids": [deviceID], "play": play])
    }

    private func pickDevice() async throws -> String {
        if engine.isAvailable {
            guard engine.hasCredentials else {
                throw SpotifyError(status: 0, message: "Aktiviere zuerst den eingebauten Player (Button oben).", reason: "ENGINE_SETUP")
            }
            if !engine.isRunning {
                flash("Starte eingebauten Player …")
                engine.start()
            }
            for _ in 0..<24 {
                if let list = try? await fetchDevices(),
                   let own = list.first(where: { $0.id == PlaybackEngine.deviceID || $0.name == PlaybackEngine.deviceName }),
                   let id = own.id {
                    if message == "Starte eingebauten Player …" { message = nil }
                    return id
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        let list = try await fetchDevices()
        guard let id = (list.first { $0.isActive == true } ?? list.first)?.id else {
            throw SpotifyError(status: 404, message: "Kein Wiedergabegerät gefunden.", reason: "NO_DEVICE")
        }
        return id
    }

    // MARK: - Messages

    func show(_ error: Error) {
        flash((error as? SpotifyError)?.userMessage ?? error.localizedDescription)
    }

    func flash(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { message = nil }
        }
    }
}

#if DEBUG
extension PlayerModel {
    func setDemoState(track: Track, progressMs: Int, liked: Bool) {
        self.track = track
        isPlaying = true
        self.progressMs = progressMs
        progressStamp = Date()
        now = progressStamp
        isLiked = liked
        shuffle = true
        volume = 0.7
        device = Device(id: PlaybackEngine.deviceID, name: PlaybackEngine.deviceName, type: "Computer",
                        isActive: true, volumePercent: 70, supportsVolume: true)
    }
}
#endif
