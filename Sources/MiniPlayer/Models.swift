import Foundation

struct SpotifyImage: Decodable, Hashable {
    let url: String
    let width: Int?
}

extension Array where Element == SpotifyImage {
    func url(fitting pixels: Int) -> URL? {
        let sorted = self.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        let pick = sorted.first { ($0.width ?? .max) >= pixels } ?? sorted.last
        return pick.flatMap { URL(string: $0.url) }
    }
}

struct Artist: Decodable, Hashable {
    let id: String?
    let name: String
}

struct Album: Decodable, Hashable {
    let id: String?
    let name: String?
    let images: [SpotifyImage]?
}

struct Show: Decodable, Hashable {
    let name: String?
    let images: [SpotifyImage]?
}

struct Track: Decodable, Hashable {
    let id: String?
    let uri: String
    let name: String
    let durationMs: Int?
    let artists: [Artist]?
    let album: Album?
    let images: [SpotifyImage]?
    let show: Show?

    var duration: Int { durationMs ?? 0 }

    var subtitle: String {
        if let artists, !artists.isEmpty { return artists.map(\.name).joined(separator: ", ") }
        return show?.name ?? ""
    }

    func coverURL(_ pixels: Int) -> URL? {
        let images = album?.images ?? images ?? show?.images ?? []
        return images.url(fitting: pixels)
    }

    var webURL: URL? {
        let parts = uri.split(separator: ":")
        guard parts.count == 3 else { return nil }
        return URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])")
    }
}

/// Skips null or malformed entries instead of failing the whole page.
struct Paging<T: Decodable>: Decodable {
    let items: [T]
    let next: String?
    let total: Int?

    private enum CodingKeys: String, CodingKey { case items, next, total }
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        next = try? c.decodeIfPresent(String.self, forKey: .next)
        total = try? c.decodeIfPresent(Int.self, forKey: .total)
        var list: [T] = []
        if var array = try? c.nestedUnkeyedContainer(forKey: .items) {
            while !array.isAtEnd {
                let index = array.currentIndex
                if (try? array.decodeNil()) == true { continue }
                if let value = try? array.decode(T.self) {
                    list.append(value)
                } else {
                    _ = try? array.decode(Skip.self)
                }
                if array.currentIndex == index { break }
            }
        }
        items = list
    }
}

struct SavedTrack: Decodable {
    let track: Track
}

/// Spotify renamed `track` to `item` in the February 2026 API update; both are accepted.
struct PlaylistItem: Decodable {
    let track: Track?

    private enum CodingKeys: String, CodingKey { case item, track }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        track = (try? c.decodeIfPresent(Track.self, forKey: .item))
            ?? (try? c.decodeIfPresent(Track.self, forKey: .track))
    }
}

struct Playlist: Decodable, Hashable, Identifiable {
    struct Owner: Decodable, Hashable {
        let id: String?
        let displayName: String?
    }

    let id: String
    let name: String
    let uri: String
    let images: [SpotifyImage]?
    let owner: Owner?
    let total: Int?

    private enum CodingKeys: String, CodingKey { case id, name, uri, images, owner, items, tracks }
    private struct Ref: Decodable { let total: Int? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Playlist"
        uri = try c.decode(String.self, forKey: .uri)
        images = try? c.decodeIfPresent([SpotifyImage].self, forKey: .images)
        owner = try? c.decodeIfPresent(Owner.self, forKey: .owner)
        total = (try? c.decodeIfPresent(Ref.self, forKey: .items))?.total
            ?? (try? c.decodeIfPresent(Ref.self, forKey: .tracks))?.total
    }
}

struct Device: Decodable, Hashable {
    let id: String?
    let name: String
    let type: String?
    let isActive: Bool?
    let volumePercent: Int?
    let supportsVolume: Bool?

    var icon: String {
        switch type?.lowercased() {
        case "computer": "laptopcomputer"
        case "smartphone": "iphone"
        case "tablet": "ipad"
        case "tv": "tv"
        case "game_console": "gamecontroller"
        case "car": "car"
        default: "hifispeaker"
        }
    }
}

struct DeviceList: Decodable {
    let devices: [Device]
}

struct PlaybackState: Decodable {
    struct Context: Decodable { let uri: String? }

    let device: Device?
    let isPlaying: Bool
    let progressMs: Int
    let item: Track?
    let shuffleState: Bool
    let repeatState: String
    let context: Context?

    private enum CodingKeys: String, CodingKey {
        case device, isPlaying, progressMs, item, shuffleState, repeatState, context
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        device = try? c.decodeIfPresent(Device.self, forKey: .device)
        isPlaying = (try? c.decodeIfPresent(Bool.self, forKey: .isPlaying)) ?? false
        progressMs = (try? c.decodeIfPresent(Int.self, forKey: .progressMs)) ?? 0
        item = try? c.decodeIfPresent(Track.self, forKey: .item)
        shuffleState = (try? c.decodeIfPresent(Bool.self, forKey: .shuffleState)) ?? false
        repeatState = (try? c.decodeIfPresent(String.self, forKey: .repeatState)) ?? "off"
        context = try? c.decodeIfPresent(Context.self, forKey: .context)
    }
}

struct SearchResult: Decodable {
    let tracks: Paging<Track>?
}

struct Me: Decodable {
    let id: String
}

struct SpotifyErrorBody: Decodable {
    struct Detail: Decodable {
        let status: Int?
        let message: String?
        let reason: String?
    }
    let error: Detail?
}
