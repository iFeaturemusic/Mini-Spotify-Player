import AppKit
import SwiftUI

struct RootView: View {
    static let size = NSSize(width: 340, height: 760)

    @Environment(AppStore.self) private var store
    @Environment(SpotifyAuth.self) private var auth

    var body: some View {
        let compact = store.compactLayout
        let detached = store.detached
        Group {
            if auth.clientID.isEmpty || store.editingClientID {
                SetupView()
            } else if !auth.isLoggedIn {
                LoginView()
            } else {
                MainView()
            }
        }
        // Popover: fixed size. Detached window: follows the window size (resizable).
        .frame(width: detached ? nil : Self.size.width, height: detached || compact ? nil : Self.size.height)
        .frame(maxWidth: detached ? .infinity : nil, maxHeight: detached && !compact ? .infinity : nil)
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
                    Text(L("Einrichtung")).font(.system(size: 15, weight: .bold))
                    Text(L("Nur einmal nötig")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            SetupStep(number: 1, text: L("Erstelle im Spotify Developer Dashboard eine App (Name egal).")) {
                Link(destination: URL(string: "https://developer.spotify.com/dashboard")!) {
                    Label(L("Dashboard öffnen"), systemImage: "arrow.up.right.square")
                }
                .font(.system(size: 11, weight: .semibold))
            }

            SetupStep(number: 2, text: L("Trage diese Redirect URI ein und hake „Web API“ an:")) {
                HStack(spacing: 6) {
                    Text(SpotifyAuth.redirectURI)
                        .font(.system(size: 10.5, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .textSelection(.enabled)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                    Button(copied ? L("Kopiert ✓") : L("Kopieren")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(SpotifyAuth.redirectURI, forType: .string)
                        copied = true
                    }
                    .controlSize(.small)
                }
            }

            SetupStep(number: 3, text: L("Kopiere die Client ID der App hierher:")) {
                TextField(L("z. B. 3f9a…"), text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit(save)
            }

            Text(L("Hinweis: Spotify verlangt seit 2026 für eigene Developer-Apps ein Premium-Konto."))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()

            HStack {
                if !auth.clientID.isEmpty {
                    Button(L("Abbrechen")) { store.editingClientID = false }
                }
                Spacer()
                Button(L("Weiter"), action: save)
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
            Text(L("Melde dich mit deinem Spotify-Konto an,\num deine Musik hier zu steuern."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if auth.isAuthorizing {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Bestätige die Anmeldung im Browser …"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button(L("Abbrechen")) { auth.cancelLogin() }.controlSize(.small)
                }
                .padding(.top, 6)
            } else {
                Button { auth.login() } label: {
                    Text(L("Mit Spotify anmelden"))
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
            Button(L("Client ID ändern")) { store.editingClientID = true }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
    }
}
