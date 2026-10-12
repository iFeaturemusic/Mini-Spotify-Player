import AppKit
import SwiftUI

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct IconButton: View {
    let systemName: String
    var size: CGFloat = 13
    var tint: Color = .primary
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .opacity(hovering ? 1 : 0.8)
                .frame(width: size + 16, height: size + 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct PlayCircle: View {
    var playing: Bool
    var size: CGFloat = 34
    var color: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.black)
                .offset(x: playing ? 0 : size * 0.03)
                .frame(width: size, height: size)
                .background(Circle().fill(color))
        }
        .buttonStyle(PressStyle())
    }
}

struct ScrubBar: View {
    @Environment(\.accent) private var accent
    var value: Double
    var height: CGFloat = 4
    var enabled = true
    var onChange: (Double) -> Void
    var onCommit: (Double) -> Void

    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fraction = min(max(value, 0), 1)
            let active = enabled && (hovering || dragging)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: height)
                Capsule()
                    .fill(active ? accent : Color.white.opacity(0.85))
                    .frame(width: width * fraction, height: height)
                Circle()
                    .fill(Color.white)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.4), radius: 1.5)
                    .offset(x: width * fraction - 5.5)
                    .opacity(active ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragging = true
                        onChange(min(max(gesture.location.x / width, 0), 1))
                    }
                    .onEnded { gesture in
                        dragging = false
                        onCommit(min(max(gesture.location.x / width, 0), 1))
                    }
            )
        }
        .frame(height: 14)
        .onHover { hovering = $0 }
        .allowsHitTesting(enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

struct RemoteImage: View {
    let url: URL?
    var size: CGFloat
    var radius: CGFloat = 4

    @State private var image: NSImage?

    init(url: URL?, size: CGFloat, radius: CGFloat = 4) {
        self.url = url
        self.size = size
        self.radius = radius
        _image = State(initialValue: url.flatMap { ImageLoader.shared.cached($0) })
    }

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.08))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let cached = ImageLoader.shared.cached(url) {
                image = cached
                return
            }
            image = nil
            image = await ImageLoader.shared.load(url)
        }
    }
}

struct TrackRow: View {
    @Environment(\.accent) private var accent
    let track: Track
    let isCurrent: Bool
    var inLikes = false
    let action: () -> Void

    @Environment(PlayerModel.self) private var player
    @Environment(LibraryModel.self) private var library
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RemoteImage(url: track.coverURL(60), size: 36)
                    if hovering {
                        RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.5))
                        Image(systemName: "play.fill").font(.system(size: 12)).foregroundStyle(.white)
                    }
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isCurrent ? accent : Color.primary)
                        .lineLimit(1)
                    Text(track.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if isCurrent && player.isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundStyle(accent)
                }
                Text(formatTime(track.duration))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.white.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Abspielen", action: action)
            Button("Zur Warteschlange hinzufügen") { player.addToQueue(track) }
            Divider()
            if inLikes {
                Button("Aus Lieblingssongs entfernen") { library.setLiked(track, false) }
            } else {
                Button("Zu Lieblingssongs hinzufügen") { library.setLiked(track, true) }
            }
            if let url = track.webURL {
                ShareLink("Teilen …", item: url, subject: Text(track.name),
                          message: Text("\(track.name) – \(track.subtitle)"))
                Button("Link kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
        }
    }
}

struct TrackList: View {
    let tracks: [Track]
    var loading: Bool
    var emptyText: String
    var error: String?
    var inLikes = false
    var onPlay: (Int) -> Void
    var onReachEnd: (() -> Void)?
    var onRetry: (() -> Void)?

    @Environment(PlayerModel.self) private var player

    var body: some View {
        let currentURI = player.track?.uri
        ListScroll {
            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                TrackRow(track: track, isCurrent: track.uri == currentURI, inLikes: inLikes) {
                    onPlay(index)
                }
                .onAppear {
                    if index == tracks.count - 1 { onReachEnd?() }
                }
            }
            if loading {
                ProgressView().controlSize(.small).padding(14)
            } else if tracks.isEmpty {
                if let error {
                    ErrorState(text: error, onRetry: onRetry)
                } else {
                    Text(emptyText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 40)
                        .padding(.horizontal, 24)
                }
            }
        }
    }
}

/// Scroll container for the lists. In screenshot mode it renders as a plain stack,
/// because ImageRenderer cannot draw NSScrollView-backed views.
struct ListScroll<Content: View>: View {
    @Environment(\.screenshotMode) private var screenshotMode
    @ViewBuilder let content: Content

    var body: some View {
        if screenshotMode {
            VStack(spacing: 0) { content }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) { content }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
        }
    }
}

private struct ScreenshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var screenshotMode: Bool {
        get { self[ScreenshotModeKey.self] }
        set { self[ScreenshotModeKey.self] = newValue }
    }
}

struct ErrorState: View {
    let text: String
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let onRetry {
                Button("Erneut versuchen", action: onRetry)
                    .controlSize(.small)
            }
        }
        .padding(.top, 30)
        .padding(.horizontal, 24)
    }
}

struct EngineCard: View {
    @Environment(\.accent) private var accent
    @Environment(PlaybackEngine.self) private var engine

    var body: some View {
        switch engine.status {
        case .needsSetup:
            card(icon: "hifispeaker.fill",
                 title: "Eingebauter Player",
                 text: "Einmal im Browser bestätigen, dann spielt MiniPlayer selbst ab. Ohne Spotify-App.",
                 button: "Aktivieren") { engine.start() }
        case .authorizing:
            card(icon: "safari",
                 title: "Bestätige im Browser …",
                 text: "Danach ist der eingebaute Player sofort bereit.",
                 button: "Abbrechen") { engine.stop() }
        case .failed(let message):
            card(icon: "exclamationmark.triangle.fill",
                 title: "Eingebauter Player",
                 text: message,
                 button: "Neu starten") { engine.restart() }
        case .unavailable:
            card(icon: "exclamationmark.triangle.fill",
                 title: "librespot fehlt",
                 text: "Installiere es mit: brew install librespot",
                 button: nil) {}
        case .stopped, .running:
            EmptyView()
        }
    }

    private func card(icon: String, title: String, text: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(text)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let button {
                Button(action: action) {
                    Text(button)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
    }
}

struct Banner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
}
