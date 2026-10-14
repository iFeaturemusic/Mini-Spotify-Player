#if DEBUG
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Debug builds only: `swift run MiniPlayer --screenshots <dir>` renders the README images
/// from the real views, using fictional demo data.
@MainActor
enum Screenshots {
    static func run(to directory: String) {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        Demo.preloadCovers()
        let store = AppStore()
        store.player.setDemoState(track: Demo.tracks[0], progressMs: 84_000, liked: true)
        store.library.setDemo(likes: Demo.tracks, likesTotal: 1_284, playlists: Demo.playlists,
                              results: Demo.searchResults, query: "night")

        func nowPlaying(_ index: Int) {
            store.player.setDemoState(track: Demo.tracks[index], progressMs: 84_000, liked: index == 0)
            if let cover = ImageLoader.shared.cached(Demo.coverURL(index)) { store.artwork.setDemo(cover) }
        }

        nowPlaying(0)
        let likes = popover(store, tab: .likes)
        store.lyrics.setDemo(Demo.lyrics)
        let lyrics = popover(store, tab: .likes)
        store.lyrics.hide()

        nowPlaying(2)
        store.library.setDemoOpenPlaylist(Demo.playlists[0], tracks: Array(Demo.tracks.reversed()))
        let playlistDetail = popover(store, tab: .playlists)
        store.library.setDemoOpenPlaylist(nil, tracks: [])

        nowPlaying(6)
        let search = popover(store, tab: .search)

        nowPlaying(7)
        store.setCompact(true)
        let compact = popover(store, tab: .likes, compact: true)
        store.setCompact(false)

        if CommandLine.arguments.contains("--with-settings") {
            store.showSettings(true)
            AppSettings.shared.setLanguage(.de)
            let settingsGerman = popover(store, tab: .likes)
            AppSettings.shared.setLanguage(.en)
            let settingsEnglish = popover(store, tab: .likes)
            store.showSettings(false)
            let likesEnglish = popover(store, tab: .likes)
            AppSettings.shared.setLanguage(.system)
            save(ScreensImage(popovers: [settingsGerman, settingsEnglish, likesEnglish]),
                 to: folder.appendingPathComponent("settings-preview.jpg"))
        }

        save(HeroImage(popover: likes), to: folder.appendingPathComponent("hero.jpg"))
        save(ScreensImage(popovers: [lyrics, playlistDetail, search]), to: folder.appendingPathComponent("screens.jpg"))
        save(CompactImage(window: compact), to: folder.appendingPathComponent("compact.jpg"))
        saveVisualizerGIF(to: folder.appendingPathComponent("visualizer.gif"))
    }

    /// `swift run MiniPlayer --icon <file.png>` renders the 1024 px app icon master.
    static func renderIcon(to path: String) {
        _ = NSApplication.shared
        let renderer = ImageRenderer(content: AppIconArtwork())
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
        print("✓ \(path)")
    }

    private static func popover(_ store: AppStore, tab: LibraryTab, compact: Bool = false) -> NSImage {
        UserDefaults.standard.set(tab.rawValue, forKey: "tab")
        let view = MainView()
            .environment(store)
            .environment(store.auth)
            .environment(store.player)
            .environment(store.library)
            .environment(store.engine)
            .environment(store.artwork)
            .environment(store.lyrics)
            .environment(\.screenshotMode, true)
            .frame(width: RootView.size.width, height: compact ? nil : RootView.size.height)
            .fixedSize(horizontal: false, vertical: compact)
            .background(Color.popover)
            .environment(\.colorScheme, .dark)
        return image(view, scale: 2)
    }

    private static func image<V: View>(_ view: V, scale: CGFloat) -> NSImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.nsImage ?? NSImage()
    }

    private static func save<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        try? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86])?.write(to: url)
        print("✓ \(url.lastPathComponent)")
    }

    private static func saveVisualizerGIF(to url: URL) {
        let fps = 16.0
        let frameCount = 48 // 3 s, seamless loop
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else { return }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)

        var bars: [CGFloat] = [0.3, 0.3, 0.3, 0.3]
        for frame in 0..<(frameCount * 2) {
            let phase: Double = 2 * .pi * Double(frame % frameCount) / Double(frameCount)
            let beat: Double = pow(max(0, cos(phase * 6)), 8)
            let bass: Double = 0.35 + 0.55 * beat + 0.1 * sin(phase * 3)
            let lowMid: Double = 0.45 + 0.30 * sin(phase * 4 + 1) + 0.2 * beat
            let highMid: Double = 0.50 + 0.30 * sin(phase * 7 + 2)
            let high: Double = 0.40 + 0.35 * sin(phase * 9 + 0.5) * sin(phase * 2)
            let targets: [CGFloat] = [bass, lowMid, highMid, high].map { CGFloat(min(max($0, 0.1), 1)) }
            for band in 0..<4 {
                let current = bars[band]
                bars[band] = targets[band] > current
                    ? current + (targets[band] - current) * 0.6
                    : current * 0.75 + targets[band] * 0.25
            }
            // first pass only warms up the smoothing so the loop is seamless
            guard frame >= frameCount else { continue }
            let renderer = ImageRenderer(content: MenuBarStrip(levels: bars, compact: true).environment(\.colorScheme, .dark))
            renderer.scale = 3
            if let cgImage = renderer.cgImage {
                CGImageDestinationAddImage(destination, cgImage, [
                    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps],
                ] as CFDictionary)
            }
        }
        if CGImageDestinationFinalize(destination) { print("✓ \(url.lastPathComponent)") }
    }
}

// MARK: - App icon

/// macOS icon grid: 1024 canvas, 824 pt squircle, room for the drop shadow.
private struct AppIconArtwork: View {
    private let squircle = RoundedRectangle(cornerRadius: 185, style: .continuous)
    private let bars: [CGFloat] = [0.55, 1.0, 0.72, 0.42]

    var body: some View {
        ZStack {
            ZStack {
                Color.black
                HStack(alignment: .center, spacing: 46) {
                    ForEach(bars.indices, id: \.self) { index in
                        Capsule()
                            .fill(Color.white)
                            .frame(width: 84, height: 120 + bars[index] * 330)
                    }
                }
            }
            .frame(width: 824, height: 824)
            .clipShape(squircle)
            .overlay(squircle.strokeBorder(Color.white.opacity(0.12), lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 12)
        }
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - Compositions

private extension Color {
    static let popover = Color(red: 0.15, green: 0.15, blue: 0.16)
}

private struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.06, blue: 0.16), Color(red: 0.20, green: 0.08, blue: 0.28),
                                    Color(red: 0.45, green: 0.16, blue: 0.24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.11, green: 0.73, blue: 0.33).opacity(0.35)).frame(width: 520).blur(radius: 140).offset(x: -380, y: 220)
            Circle().fill(Color(red: 0.95, green: 0.45, blue: 0.25).opacity(0.30)).frame(width: 460).blur(radius: 140).offset(x: 420, y: -160)
        }
    }
}

private struct BarsGlyph: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(spacing: 1.8) {
            ForEach(0..<4, id: \.self) { index in
                Capsule().frame(width: 2.6, height: 2.6 + levels[index] * 12.4)
            }
        }
        .frame(width: 22, height: 22)
    }
}

private struct MenuBarStrip: View {
    let levels: [CGFloat]
    var highlighted = false
    var compact = false

    var body: some View {
        HStack(spacing: 14) {
            if !compact {
                Image(systemName: "apple.logo").font(.system(size: 14))
                Text("Finder").font(.system(size: 13, weight: .bold))
                ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) {
                    Text($0).font(.system(size: 13))
                }
                Spacer()
            }
            BarsGlyph(levels: levels)
                .padding(.horizontal, 5)
                .background(Capsule().fill(Color.white.opacity(highlighted ? 0.22 : 0)).frame(height: 22))
            Image(systemName: "wifi").font(.system(size: 13, weight: .medium))
            Image(systemName: "battery.75percent").font(.system(size: 15))
            Image(systemName: "switch.2").font(.system(size: 13))
            Text("Fri 9 Oct  16:20").font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(compact ? Color(red: 0.12, green: 0.11, blue: 0.16) : Color.black.opacity(0.28))
    }
}

private struct PopoverCard: View {
    let image: NSImage
    var arrow = true

    var body: some View {
        VStack(spacing: 0) {
            if arrow {
                Triangle().fill(Color.popover).frame(width: 24, height: 11)
            }
            Image(nsImage: image)
                .resizable()
                .frame(width: RootView.size.width, height: RootView.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08)))
        }
        .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct HeroImage: View {
    let popover: NSImage

    var body: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper()
            VStack(spacing: 0) {
                MenuBarStrip(levels: [0.55, 0.95, 0.7, 0.4], highlighted: true)
                HStack(alignment: .top) {
                    Tagline()
                        .padding(.leading, 90)
                        .padding(.top, 230)
                    Spacer()
                    PopoverCard(image: popover)
                        .padding(.trailing, 135)
                }
                .padding(.top, 4)
                Spacer()
            }
        }
        .frame(width: 1200, height: 880)
    }
}

private struct Tagline: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                BarsGlyph(levels: [0.55, 1.0, 0.72, 0.42])
                    .scaleEffect(1.9)
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.black))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
                Text("MiniPlayer")
                    .font(.system(size: 54, weight: .heavy))
            }
            Text("Spotify, living quietly in your Mac menu bar.")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            VStack(alignment: .leading, spacing: 10) {
                Label("Likes, playlists and search", systemImage: "music.note.list")
                Label("Plays by itself, no Spotify app needed", systemImage: "hifispeaker.fill")
                Label("Colors adapt to the cover", systemImage: "paintpalette.fill")
                Label("Synced lyrics to sing along", systemImage: "quote.bubble.fill")
                Label("Live visualizer right in the icon", systemImage: "waveform")
                Label("Native Swift, ~0 % CPU when idle", systemImage: "leaf.fill")
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.top, 8)
        }
        .foregroundStyle(.white)
    }
}

private struct CompactImage: View {
    let window: NSImage

    var body: some View {
        ZStack {
            Wallpaper()
            Image(nsImage: window)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: RootView.size.width)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
        }
        .frame(width: 900, height: 560)
    }
}

private struct ScreensImage: View {
    let popovers: [NSImage]

    var body: some View {
        ZStack {
            Wallpaper()
            HStack(spacing: 36) {
                ForEach(popovers.indices, id: \.self) { PopoverCard(image: popovers[$0], arrow: false) }
            }
        }
        .frame(width: 1240, height: 880)
    }
}

// MARK: - Demo data (fictional)

private enum Demo {
    static let palette: [(NSColor, NSColor)] = [
        (#colorLiteral(red: 1, green: 0.37, blue: 0.43, alpha: 1), #colorLiteral(red: 1, green: 0.76, blue: 0.44, alpha: 1)),
        (#colorLiteral(red: 0.13, green: 0.58, blue: 0.69, alpha: 1), #colorLiteral(red: 0.43, green: 0.84, blue: 0.93, alpha: 1)),
        (#colorLiteral(red: 0.56, green: 0.18, blue: 0.89, alpha: 1), #colorLiteral(red: 0.29, green: 0, blue: 0.88, alpha: 1)),
        (#colorLiteral(red: 0.07, green: 0.6, blue: 0.56, alpha: 1), #colorLiteral(red: 0.22, green: 0.94, blue: 0.49, alpha: 1)),
        (#colorLiteral(red: 0.99, green: 0.29, blue: 0.1, alpha: 1), #colorLiteral(red: 0.97, green: 0.72, blue: 0.2, alpha: 1)),
        (#colorLiteral(red: 0.4, green: 0.31, blue: 0.64, alpha: 1), #colorLiteral(red: 0.92, green: 0.69, blue: 0.78, alpha: 1)),
        (#colorLiteral(red: 0, green: 0.78, blue: 1, alpha: 1), #colorLiteral(red: 0, green: 0.45, blue: 1, alpha: 1)),
        (#colorLiteral(red: 0.93, green: 0.04, blue: 0.47, alpha: 1), #colorLiteral(red: 1, green: 0.42, blue: 0, alpha: 1)),
        (#colorLiteral(red: 0.26, green: 0.81, blue: 0.64, alpha: 1), #colorLiteral(red: 0.09, green: 0.35, blue: 0.62, alpha: 1)),
        (#colorLiteral(red: 0.85, green: 0.27, blue: 0.33, alpha: 1), #colorLiteral(red: 0.54, green: 0.13, blue: 0.42, alpha: 1)),
    ]

    static func coverURL(_ index: Int) -> URL { URL(string: "demo://cover/\(index)")! }

    static func preloadCovers() {
        for index in 0..<24 {
            let (start, end) = palette[index % palette.count]
            let image = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
                NSGradient(starting: start, ending: end)?.draw(in: rect, angle: CGFloat(index * 47 % 360))
                NSColor.white.withAlphaComponent(0.16).setFill()
                let radius = CGFloat(55 + index * 29 % 80)
                NSBezierPath(ovalIn: NSRect(x: CGFloat(index * 53 % 180), y: CGFloat(index * 31 % 170),
                                            width: radius * 2, height: radius * 2)).fill()
                NSColor.black.withAlphaComponent(0.12).setFill()
                NSBezierPath(rect: NSRect(x: 0, y: 0, width: rect.width, height: CGFloat(40 + index * 17 % 90))).fill()
                return true
            }
            ImageLoader.shared.preload(image, for: coverURL(index))
        }
    }

    static func track(_ index: Int, _ name: String, _ artist: String, _ seconds: Int) -> Track {
        Track(id: "demo\(index)", uri: "spotify:track:demo\(index)", name: name, durationMs: seconds * 1000,
              artists: [Artist(id: nil, name: artist)],
              album: Album(id: nil, name: name, images: [SpotifyImage(url: coverURL(index).absoluteString, width: 300)]),
              images: nil, show: nil)
    }

    static let tracks: [Track] = [
        track(0, "Neon Skyline", "Lumen Drift", 238),
        track(1, "Midnight Circuit", "Vela Kade", 201),
        track(2, "Glass Gardens", "Oro Bloom", 245),
        track(3, "Afterglow FM", "Saint Novak", 192),
        track(4, "Static Hearts", "Kiro & The Wires", 178),
        track(5, "Low Tide", "Marlo Vance", 224),
        track(6, "Paper Planets", "Juno Lark", 210),
        track(7, "Velvet Engine", "Halcyon Six", 252),
        track(8, "Northern Echo", "Aster Vale", 216),
        track(9, "Slow Motion City", "Nova Reyes", 229),
    ]

    // Original placeholder lines for the screenshots
    static let lyrics: [LyricLine] = [
        "City lights are fading slow", "Every window's got a glow", "We keep running on the midnight line",
        "Chasing echoes, losing time", "Neon skyline, hold me tight", "Paint the dark in electric light",
        "Neon skyline, don't let go", "Take me where the night winds blow", "", "Static on the radio",
    ].enumerated().map { LyricLine(id: $0.offset, time: 70_000 + $0.offset * 3_600, text: $0.element) }

    static let searchResults: [Track] = [
        track(10, "Night Swim", "Coral Ivy", 203),
        track(11, "Nightfall Avenue", "Lumen Drift", 236),
        track(12, "Night Shift Lovers", "The Velvet Ones", 187),
        track(1, "Midnight Circuit", "Vela Kade", 201),
        track(13, "Night Bus Home", "Pale Harbor", 219),
        track(14, "Nights Like These", "Sola Wren", 198),
        track(15, "Starry Night Drive", "Echo Park Kids", 241),
        track(16, "Nightingale", "Mira Sol", 226),
    ]

    static let playlists: [Playlist] = {
        let entries: [(String, Int)] = [
            ("Late Night Drive", 42), ("Studio Focus", 128), ("Morning Coffee", 37), ("Synthwave Nights", 86),
            ("Beats to Produce To", 73), ("Gym Rotation", 54), ("Sunday Reset", 29), ("Road Trip '26", 61),
        ]
        let json = entries.enumerated().map { index, entry in
            """
            {"id":"pl\(index)","name":"\(entry.0)","uri":"spotify:playlist:pl\(index)",
             "images":[{"url":"\(coverURL(16 + index).absoluteString)","width":300}],
             "owner":{"id":"demo","display_name":"iFeature"},"items":{"total":\(entry.1)}}
            """
        }.joined(separator: ",")
        return (try? JSONDecoder.spotify.decode([Playlist].self, from: Data("[\(json)]".utf8))) ?? []
    }()
}
#endif
