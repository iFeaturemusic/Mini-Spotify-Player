import Foundation
import Observation

struct LyricLine: Identifiable, Hashable {
    let id: Int
    let time: Int // ms
    let text: String
}

enum LyricsState: Equatable {
    case idle
    case loading
    case synced([LyricLine])
    case plain([String])
    case instrumental
    case notFound
    case failed
}

/// Synced lyrics from LRCLIB (lrclib.net), loaded only while the lyrics view is open.
@MainActor @Observable
final class LyricsModel {
    private(set) var isShown = false
    private(set) var state: LyricsState = .idle

    @ObservationIgnored private var track: Track?
    @ObservationIgnored private var loadedURI: String?
    @ObservationIgnored private var cache: [String: LyricsState] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored var onVisibilityChanged: ((Bool) -> Void)?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = ["User-Agent": "MiniPlayer (https://github.com/iFeaturemusic/Mini-Spotify-Player-)"]
        return URLSession(configuration: config)
    }()

    func toggle() {
        isShown.toggle()
        onVisibilityChanged?(isShown)
        if isShown { load() }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        onVisibilityChanged?(false)
    }

    func trackChanged(_ newTrack: Track?) {
        track = newTrack
        if isShown { load() }
    }

    func retry() {
        loadedURI = nil
        load()
    }

    private func load() {
        guard let track else {
            state = .idle
            return
        }
        guard track.uri != loadedURI else { return }
        loadedURI = track.uri
        task?.cancel()
        if let cached = cache[track.uri] {
            state = cached
            return
        }
        state = .loading
        task = Task {
            let result = await fetch(track)
            guard !Task.isCancelled, loadedURI == track.uri else { return }
            if result != .failed { cache[track.uri] = result }
            state = result
        }
    }

    // MARK: - LRCLIB

    private struct Item: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    func fetch(_ track: Track) async -> LyricsState {
        let artist = track.artists?.first?.name ?? track.show?.name ?? ""
        let seconds = Double(track.duration) / 1000
        let cleaned = Self.cleanTitle(track.name)
        var networkFailed = false

        for title in cleaned == track.name ? [cleaned] : [cleaned, track.name] {
            do {
                let item: Item = try await request("get", ["track_name": title, "artist_name": artist,
                                                          "duration": String(Int(seconds.rounded()))])
                if let state = Self.state(from: item) { return state }
            } catch is NotFound {
            } catch {
                networkFailed = true
            }
        }

        do {
            let items: [Item] = try await request("search", ["track_name": cleaned, "artist_name": artist])
            let matching = items.filter { abs(($0.duration ?? 0) - seconds) <= 4 }
            let best = matching.first { !($0.syncedLyrics ?? "").isEmpty }
                ?? matching.first { !($0.plainLyrics ?? "").isEmpty }
                ?? matching.first { $0.instrumental == true }
            if let best, let state = Self.state(from: best) { return state }
        } catch is NotFound {
        } catch {
            networkFailed = true
        }
        return networkFailed ? .failed : .notFound
    }

    private struct NotFound: Error {}

    private func request<T: Decodable>(_ endpoint: String, _ query: [String: String]) async throws -> T {
        let parameters = query.map { "\($0.key)=\(urlEncode($0.value))" }.joined(separator: "&")
        let url = URL(string: "https://lrclib.net/api/\(endpoint)?\(parameters)")!
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw NotFound() }
        guard status == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func state(from item: Item) -> LyricsState? {
        if let synced = item.syncedLyrics, !synced.isEmpty {
            let lines = parse(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = item.plainLyrics, !plain.isEmpty {
            return .plain(plain.components(separatedBy: "\n"))
        }
        return item.instrumental == true ? .instrumental : nil
    }

    /// Parses LRC lines like `[01:23.45] text`, including several timestamps per line.
    static func parse(_ lrc: String) -> [LyricLine] {
        var entries: [(time: Int, text: String)] = []
        for raw in lrc.split(separator: "\n") {
            var rest = Substring(raw)
            var times: [Int] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                let parts = tag.split(separator: ":")
                if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) {
                    times.append(Int((minutes * 60 + seconds) * 1000))
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            entries += times.map { ($0, text) }
        }
        return entries.sorted { $0.time < $1.time }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text) }
    }

    /// "Song (feat. X) - Remastered 2011" → "Song"
    static func cleanTitle(_ title: String) -> String {
        var result = title
        for marker in [" (feat.", " (with ", " [feat.", " (ft.", " - "] {
            if let range = result.range(of: marker, options: .caseInsensitive) {
                result = String(result[..<range.lowerBound])
            }
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    #if DEBUG
    func setDemo(_ lines: [LyricLine]) {
        isShown = true
        state = .synced(lines)
    }
    #endif
}
