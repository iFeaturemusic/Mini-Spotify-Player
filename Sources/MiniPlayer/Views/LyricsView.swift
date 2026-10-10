import SwiftUI

struct LyricsView: View {
    @Environment(LyricsModel.self) private var lyrics

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Lyrics", systemImage: "quote.bubble.fill")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                IconButton(systemName: "xmark", size: 11, tint: .secondary, help: "Lyrics schließen") {
                    lyrics.hide()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Group {
                switch lyrics.state {
                case .synced(let lines):
                    SyncedLyrics(lines: lines)
                case .plain(let lines):
                    PlainLyrics(lines: lines)
                case .loading:
                    ProgressView().controlSize(.small).frame(maxHeight: .infinity)
                case .instrumental:
                    message("Instrumental, kein Text zum Mitsingen.", icon: "pianokeys")
                case .notFound:
                    message("Für diesen Song wurden keine Lyrics gefunden.", icon: "text.page.slash")
                case .failed:
                    ErrorState(text: "Lyrics konnten nicht geladen werden.") { lyrics.retry() }
                        .frame(maxHeight: .infinity, alignment: .top)
                case .idle:
                    message("Starte einen Song, um die Lyrics zu sehen.", icon: "music.mic")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Lyrics von LRCLIB")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 6)
        }
    }

    private func message(_ text: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxHeight: .infinity)
    }
}

private struct SyncedLyrics: View {
    let lines: [LyricLine]
    @Environment(PlayerModel.self) private var player
    @Environment(\.screenshotMode) private var screenshotMode

    var body: some View {
        let position = player.lyricsPosition
        let current = lines.lastIndex { $0.time <= position } ?? -1
        if screenshotMode {
            stack(current: current, visible: lines.filter { $0.id >= current - 2 })
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    stack(current: current, visible: lines)
                        .padding(.vertical, 140)
                }
                .onChange(of: current) { _, line in
                    withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(max(line, 0), anchor: .center) }
                }
                .onAppear { proxy.scrollTo(max(current, 0), anchor: .center) }
            }
        }
    }

    private func stack(current: Int, visible: [LyricLine]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(visible) { line in
                Text(line.text.isEmpty ? "♪" : line.text)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(line.id == current ? 1 : line.id < current ? 0.3 : 0.5))
                    .scaleEffect(line.id == current ? 1.04 : 1, anchor: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { player.seek(to: line.time) }
                    .id(line.id)
            }
        }
        .padding(.horizontal, 18)
        .animation(.easeOut(duration: 0.25), value: current)
    }
}

private struct PlainLyrics: View {
    let lines: [String]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
        }
    }
}
