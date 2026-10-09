import AppKit
import SwiftUI

extension JSONDecoder {
    static var spotify: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

func urlEncode(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

func formatTime(_ ms: Int) -> String {
    let seconds = max(0, ms / 1000)
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

extension Color {
    static let spotifyGreen = Color(red: 0.114, green: 0.725, blue: 0.329)
}

final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 64 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    #if DEBUG
    func preload(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
    #endif

    func cached(_ url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func load(_ url: URL) async -> NSImage? {
        if let image = cached(url) { return image }
        guard let (data, _) = try? await session.data(from: url), let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
