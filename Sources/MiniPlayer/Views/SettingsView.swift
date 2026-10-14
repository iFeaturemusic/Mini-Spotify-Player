import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(PlaybackEngine.self) private var engine
    @Environment(PlayerModel.self) private var player
    @Environment(\.accent) private var accent
    private let settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(L("Einstellungen"), systemImage: "gearshape.fill")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                IconButton(systemName: "xmark", size: 11, tint: .secondary, help: L("Einstellungen schließen")) {
                    store.showSettings(false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            ListScroll {
                VStack(alignment: .leading, spacing: 14) {
                    section(L("Allgemein")) {
                        row(L("Sprache")) {
                            Picker("", selection: Binding(get: { settings.language }, set: { settings.setLanguage($0) })) {
                                Text(L("Automatisch")).tag(AppLanguage.system)
                                Text("Deutsch").tag(AppLanguage.de)
                                Text("English").tag(AppLanguage.en)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }
                        divider
                        toggleRow(L("Mit dem Mac starten"), isOn: settings.launchAtLogin) { value in
                            do {
                                try settings.setLaunchAtLogin(value)
                            } catch {
                                player.flash(L("Konnte nicht geändert werden: %@", error.localizedDescription))
                            }
                        }
                        divider
                        toggleRow(L("Visualizer in der Menüleiste"), isOn: settings.visualizerEnabled) {
                            settings.setVisualizer($0)
                        }
                        divider
                        toggleRow(L("Fenster immer im Vordergrund"), note: L("Gilt für den als Fenster gelösten Player."),
                                  isOn: settings.alwaysOnTop) {
                            settings.setAlwaysOnTop($0)
                        }
                    }

                    section(L("Konto")) {
                        row(L("Bei Spotify angemeldet"), icon: "checkmark.circle.fill") { EmptyView() }
                        divider
                        HStack(spacing: 8) {
                            Button(L("Client ID ändern")) { store.editingClientID = true }
                            Button(L("Abmelden")) { store.logout() }
                            Spacer()
                        }
                        .controlSize(.small)
                        .padding(10)
                    }

                    section(L("Eingebauter Player")) {
                        row(engineStatus) {
                            Button(L("Neu starten")) { engine.restart() }
                                .controlSize(.small)
                                .disabled(!engine.hasCredentials)
                        }
                    }

                    section(L("Über")) {
                        row("MiniPlayer \(settings.version)") {
                            Link(L("Quellcode auf GitHub"),
                                 destination: URL(string: "https://github.com/iFeaturemusic/Mini-Spotify-Player-")!)
                                .font(.system(size: 11))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }

    private var engineStatus: String {
        switch engine.status {
        case .running: L("Läuft")
        case .stopped: L("Gestoppt")
        case .needsSetup: L("Nicht eingerichtet")
        case .authorizing: L("Wartet auf Browser …")
        case .unavailable: L("Nicht verfügbar")
        case .failed(let message): message
        }
    }

    private var divider: some View {
        Divider().opacity(0.4).padding(.leading, 10)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
        }
    }

    private func row<Trailing: View>(_ title: String, icon: String? = nil,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).foregroundStyle(accent)
            }
            Text(title)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func toggleRow(_ title: String, note: String? = nil, isOn: Bool,
                           action: @escaping (Bool) -> Void) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12))
                if let note {
                    Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { isOn }, set: action))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
