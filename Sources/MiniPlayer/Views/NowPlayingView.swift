import SwiftUI

struct NowPlayingView: View {
    @Environment(AppStore.self) private var store
    @Environment(PlayerModel.self) private var player
    @Environment(ArtworkModel.self) private var artwork
    @Environment(LyricsModel.self) private var lyrics
    @Environment(\.accent) private var accent
    @State private var hovering = false

    var body: some View {
        // Compact mode shows the bare cover; title and controls appear on hover.
        let showOverlays = !store.compact || hovering
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                cover
                    .overlay {
                        if store.detached { WindowDragArea() }
                    }
                Group {
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                        .allowsHitTesting(false)
                    VStack(spacing: 4) {
                        ProgressRow()
                        controls
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
                .opacity(showOverlays ? 1 : 0)
                .allowsHitTesting(showOverlays)
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .top) {
                HStack(alignment: .top, spacing: 6) {
                    TrackPill()
                    Spacer(minLength: 4)
                    if player.track != nil {
                        CircleButton(systemName: player.isLiked ? "heart.fill" : "heart",
                                     tint: player.isLiked ? accent : .white,
                                     help: player.isLiked ? L("Aus Lieblingssongs entfernen") : L("Zu Lieblingssongs hinzufügen")) {
                            player.toggleLike()
                        }
                    }
                    if let track = player.track, let url = track.webURL {
                        ShareLink(item: url, subject: Text(track.name), message: Text("\(track.name) – \(track.subtitle)"),
                                  preview: SharePreview("\(track.name) – \(track.subtitle)",
                                                        image: Image(nsImage: artwork.cover ?? NSImage()))) {
                            CircleLabel(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(PressStyle())
                        .help(L("Song teilen"))
                    }
                    CircleButton(systemName: "quote.bubble.fill",
                                 tint: lyrics.isShown ? .black : .white,
                                 fill: lyrics.isShown ? accent : nil,
                                 help: "Lyrics") {
                        lyrics.toggle()
                    }
                }
                .padding(10)
                .opacity(showOverlays ? 1 : 0)
                .allowsHitTesting(showOverlays)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            .onHover { hovering = $0 }
            .animation(.easeInOut(duration: 0.25), value: showOverlays)

            HStack(spacing: 6) {
                DeviceMenu()
                Spacer(minLength: 4)
                VolumeControl()
                IconButton(systemName: store.compact ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                           size: 11, tint: .secondary,
                           help: store.compact ? L("Bibliothek einblenden") : L("Nur das Cover zeigen")) {
                    store.setCompact(!store.compact)
                }
                IconButton(systemName: store.detached ? "menubar.arrow.up.rectangle" : "macwindow.on.rectangle",
                           size: 11, tint: .secondary,
                           help: store.detached ? L("Zurück in die Menüleiste") : L("Als Fenster lösen")) {
                    store.setDetached(!store.detached)
                }
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let image = artwork.cover {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .transition(.opacity)
                .id(artwork.key)
        } else {
            ZStack {
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "music.note")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            IconButton(systemName: "shuffle", size: 13,
                       tint: player.shuffle ? accent : .white.opacity(0.75), help: L("Zufallswiedergabe")) {
                player.toggleShuffle()
            }
            Spacer()
            IconButton(systemName: "backward.fill", size: 16, tint: .white, help: L("Vorheriger Titel")) { player.previous() }
            Spacer()
            PlayCircle(playing: player.isPlaying, size: 40) { player.togglePlay() }
            Spacer()
            IconButton(systemName: "forward.fill", size: 16, tint: .white, help: L("Nächster Titel")) { player.next() }
            Spacer()
            IconButton(systemName: player.repeatMode == "track" ? "repeat.1" : "repeat", size: 13,
                       tint: player.repeatMode == "off" ? .white.opacity(0.75) : accent, help: L("Wiederholen")) {
                player.cycleRepeat()
            }
        }
    }
}

private struct TrackPill: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        HStack(spacing: 8) {
            RemoteImage(url: player.track?.coverURL(60), size: 28, radius: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.track?.name ?? L("Gerade läuft nichts"))
                    .font(.system(size: 12, weight: .semibold))
                Text(player.track?.subtitle ?? L("Wähle unten einen Song aus"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .lineLimit(1)
            .padding(.trailing, 6)
        }
        .foregroundStyle(.white)
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: 180, alignment: .leading)
    }
}

private struct CircleButton: View {
    let systemName: String
    var tint: Color = .white
    var fill: Color?
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CircleLabel(systemName: systemName, tint: tint, fill: fill)
        }
        .buttonStyle(PressStyle())
        .help(help)
    }
}

private struct CircleLabel: View {
    let systemName: String
    var tint: Color = .white
    var fill: Color?

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background {
                if let fill {
                    Circle().fill(fill)
                } else {
                    Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                }
            }
            .contentShape(Circle())
    }
}

struct ProgressRow: View {
    @Environment(PlayerModel.self) private var player
    @State private var scrub: Double?

    var body: some View {
        let duration = player.durationMs
        let position = scrub.map { Int($0 * Double(duration)) } ?? player.position(at: player.now)
        VStack(spacing: 1) {
            ScrubBar(value: duration > 0 ? Double(position) / Double(duration) : 0,
                     enabled: duration > 0,
                     onChange: { scrub = $0 },
                     onCommit: { value in
                         player.seek(to: Int(value * Double(duration)))
                         scrub = nil
                     })
            HStack {
                Text(formatTime(position))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
        }
    }
}

struct VolumeControl: View {
    @Environment(PlayerModel.self) private var player
    @State private var local: Double?

    var body: some View {
        let value = local ?? player.volume
        let enabled = player.device != nil && player.device?.supportsVolume != false
        HStack(spacing: 5) {
            Image(systemName: value == 0 ? "speaker.slash.fill" : value < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            ScrubBar(value: value, height: 3, enabled: enabled,
                     onChange: { local = $0 },
                     onCommit: { value in
                         player.setVolume(value)
                         local = nil
                     })
            .frame(width: 72)
        }
    }
}

struct DeviceMenu: View {
    @Environment(PlayerModel.self) private var player
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.accent) private var accent

    var body: some View {
        Menu {
            if player.devices.isEmpty {
                Text(L("Keine Geräte gefunden"))
            }
            ForEach(player.devices, id: \.self) { device in
                Button {
                    player.select(device)
                } label: {
                    let name = device.id == PlaybackEngine.deviceID ? L("Dieser Mac (MiniPlayer)") : device.name
                    if device.isActive == true {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Label(name, systemImage: device.icon)
                    }
                }
            }
            Divider()
            if engine.hasCredentials {
                Button(L("Eingebauten Player neu starten")) { engine.restart() }
            }
            Button(L("Geräteliste aktualisieren")) {
                Task { await player.loadDevices() }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: player.device?.icon ?? "hifispeaker")
                Text(deviceLabel)
                    .lineLimit(1)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(player.device != nil ? accent : Color.secondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Wiedergabegerät"))
    }

    private var deviceLabel: String {
        guard let device = player.device else { return L("Gerät wählen") }
        return device.id == PlaybackEngine.deviceID ? L("Dieser Mac") : device.name
    }
}
