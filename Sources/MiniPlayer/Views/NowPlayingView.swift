import SwiftUI

struct NowPlayingView: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                RemoteImage(url: player.track?.coverURL(300), size: 58, radius: 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.track?.name ?? "Gerade läuft nichts")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(player.track?.subtitle ?? "Wähle unten einen Song aus")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if player.track != nil {
                    IconButton(systemName: player.isLiked ? "heart.fill" : "heart",
                               size: 15,
                               tint: player.isLiked ? .spotifyGreen : .secondary,
                               help: player.isLiked ? "Aus Lieblingssongs entfernen" : "Zu Lieblingssongs hinzufügen") {
                        player.toggleLike()
                    }
                }
            }

            ProgressRow()

            HStack(spacing: 0) {
                IconButton(systemName: "shuffle", size: 13,
                           tint: player.shuffle ? .spotifyGreen : .secondary, help: "Zufallswiedergabe") {
                    player.toggleShuffle()
                }
                Spacer()
                IconButton(systemName: "backward.fill", size: 15, help: "Zurück") { player.previous() }
                Spacer()
                PlayCircle(playing: player.isPlaying, size: 36) { player.togglePlay() }
                Spacer()
                IconButton(systemName: "forward.fill", size: 15, help: "Weiter") { player.next() }
                Spacer()
                IconButton(systemName: player.repeatMode == "track" ? "repeat.1" : "repeat", size: 13,
                           tint: player.repeatMode == "off" ? .secondary : .spotifyGreen, help: "Wiederholen") {
                    player.cycleRepeat()
                }
            }
            .padding(.horizontal, 14)

            HStack(spacing: 8) {
                DeviceMenu()
                Spacer()
                VolumeControl()
            }
        }
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
            .foregroundStyle(.secondary)
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
            .frame(width: 86)
        }
    }
}

struct DeviceMenu: View {
    @Environment(PlayerModel.self) private var player
    @Environment(PlaybackEngine.self) private var engine

    var body: some View {
        Menu {
            if player.devices.isEmpty {
                Text("Keine Geräte gefunden")
            }
            ForEach(player.devices, id: \.self) { device in
                Button {
                    player.select(device)
                } label: {
                    let name = device.id == PlaybackEngine.deviceID ? "Dieser Mac (MiniPlayer)" : device.name
                    if device.isActive == true {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Label(name, systemImage: device.icon)
                    }
                }
            }
            Divider()
            if engine.hasCredentials {
                Button("Eingebauten Player neu starten") { engine.restart() }
            }
            Button("Geräteliste aktualisieren") {
                Task { await player.loadDevices() }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: player.device?.icon ?? "hifispeaker")
                Text(deviceLabel)
                    .lineLimit(1)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(player.device != nil ? Color.spotifyGreen : Color.secondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Wiedergabegerät")
    }

    private var deviceLabel: String {
        guard let device = player.device else { return "Gerät wählen" }
        return device.id == PlaybackEngine.deviceID ? "Dieser Mac" : device.name
    }
}
