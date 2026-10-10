import AppKit
import SwiftUI

struct RootView: View {
    static let size = NSSize(width: 340, height: 760)

    @Environment(AppStore.self) private var store
    @Environment(SpotifyAuth.self) private var auth

    var body: some View {
        let showsPlayer = !auth.clientID.isEmpty && !store.editingClientID && auth.isLoggedIn
        let compact = showsPlayer && store.compact
        Group {
            if auth.clientID.isEmpty || store.editingClientID {
                SetupView()
            } else if !auth.isLoggedIn {
                LoginView()
            } else {
                MainView()
            }
        }
        .frame(width: Self.size.width, height: compact ? nil : Self.size.height)
        .fixedSize(horizontal: false, vertical: compact)
        .background(store.detached ? Color(white: 0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: store.detached ? 18 : 0, style: .continuous))
        .tint(.spotifyGreen)
    }
}

// MARK: - Setup

struct SetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(SpotifyAuth.self) private var auth
    @State private var clientID = ""
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.spotifyGreen))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Einrichtung").font(.system(size: 15, weight: .bold))
                    Text("Nur einmal nötig").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            SetupStep(number: 1, text: "Erstelle im Spotify Developer Dashboard eine App (Name egal).") {
                Link(destination: URL(string: "https://developer.spotify.com/dashboard")!) {
                    Label("Dashboard öffnen", systemImage: "arrow.up.right.square")
                }
                .font(.system(size: 11, weight: .semibold))
            }

            SetupStep(number: 2, text: "Trage diese Redirect URI ein und hake „Web API“ an:") {
                HStack(spacing: 6) {
                    Text(SpotifyAuth.redirectURI)
                        .font(.system(size: 10.5, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .textSelection(.enabled)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                    Button(copied ? "Kopiert ✓" : "Kopieren") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(SpotifyAuth.redirectURI, forType: .string)
                        copied = true
                    }
                    .controlSize(.small)
                }
            }

            SetupStep(number: 3, text: "Kopiere die Client ID der App hierher:") {
                TextField("z. B. 3f9a…", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit(save)
            }

            Text("Hinweis: Spotify verlangt seit 2026 für eigene Developer-Apps ein Premium-Konto.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()

            HStack {
                if !auth.clientID.isEmpty {
                    Button("Abbrechen") { store.editingClientID = false }
                }
                Spacer()
                Button("Weiter", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(clientID.trimmingCharacters(in: .whitespaces).count < 16)
            }
        }
        .padding(20)
        .onAppear { clientID = auth.clientID }
    }

    private func save() {
        guard clientID.trimmingCharacters(in: .whitespaces).count >= 16 else { return }
        auth.setClientID(clientID)
        store.editingClientID = false
    }
}

private struct SetupStep<Content: View>: View {
    let number: Int
    let text: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                content
            }
        }
    }
}

// MARK: - Login

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @Environment(SpotifyAuth.self) private var auth

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.spotifyGreen))
            Text("MiniPlayer").font(.system(size: 20, weight: .bold))
            Text("Melde dich mit deinem Spotify-Konto an,\num deine Musik hier zu steuern.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if auth.isAuthorizing {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Bestätige die Anmeldung im Browser …")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Abbrechen") { auth.cancelLogin() }.controlSize(.small)
                }
                .padding(.top, 6)
            } else {
                Button { auth.login() } label: {
                    Text("Mit Spotify anmelden")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(Capsule().fill(Color.spotifyGreen))
                }
                .buttonStyle(PressStyle())
                .padding(.top, 6)
            }

            if let error = auth.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
            Button("Client ID ändern") { store.editingClientID = true }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
    }
}
