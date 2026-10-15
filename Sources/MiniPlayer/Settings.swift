import Foundation
import Observation
import ServiceManagement

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, de, en
    var id: String { rawValue }
}

/// Streaming bitrate of the built-in player (librespot `--bitrate`).
enum StreamQuality: Int, CaseIterable, Identifiable {
    case low = 96, normal = 160, high = 320
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: L("Niedrig (96 kbit/s)")
        case .normal: L("Normal (160 kbit/s)")
        case .high: L("Hoch (320 kbit/s)")
        }
    }
}

/// User preferences from the settings page. Observable, so the UI updates live
/// (including the language, which `L()` reads).
@Observable
final class AppSettings: @unchecked Sendable {
    static let shared = AppSettings()

    private(set) var language: AppLanguage
    private(set) var visualizerEnabled: Bool
    private(set) var alwaysOnTop: Bool
    private(set) var launchAtLogin: Bool
    private(set) var quality: StreamQuality

    @ObservationIgnored var onVisualizerChanged: ((Bool) -> Void)?
    @ObservationIgnored var onAlwaysOnTopChanged: ((Bool) -> Void)?
    @ObservationIgnored var onQualityChanged: ((StreamQuality) -> Void)?

    private init() {
        let defaults = UserDefaults.standard
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        visualizerEnabled = defaults.string(forKey: "visualizerMode") != "off"
        alwaysOnTop = defaults.object(forKey: "alwaysOnTop") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        quality = StreamQuality(rawValue: defaults.integer(forKey: "streamQuality")) ?? .high
    }

    var isEnglish: Bool {
        switch language {
        case .en: true
        case .de: false
        case .system: !(Locale.preferredLanguages.first ?? "en").hasPrefix("de")
        }
    }

    func setLanguage(_ value: AppLanguage) {
        language = value
        UserDefaults.standard.set(value.rawValue, forKey: "language")
    }

    func setVisualizer(_ value: Bool) {
        visualizerEnabled = value
        UserDefaults.standard.set(value ? "on" : "off", forKey: "visualizerMode")
        onVisualizerChanged?(value)
    }

    func setAlwaysOnTop(_ value: Bool) {
        alwaysOnTop = value
        UserDefaults.standard.set(value, forKey: "alwaysOnTop")
        onAlwaysOnTopChanged?(value)
    }

    func setQuality(_ value: StreamQuality) {
        guard value != quality else { return }
        quality = value
        UserDefaults.standard.set(value.rawValue, forKey: "streamQuality")
        onQualityChanged?(value)
    }

    func setLaunchAtLogin(_ value: Bool) throws {
        defer { launchAtLogin = SMAppService.mainApp.status == .enabled }
        if value {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }
}

/// UI text: the German string is the key; English comes from the table below.
func L(_ german: String) -> String {
    AppSettings.shared.isEnglish ? (englishStrings[german] ?? german) : german
}

func L(_ german: String, _ arguments: CVarArg...) -> String {
    String(format: L(german), arguments: arguments)
}

private let englishStrings: [String: String] = [
    // Menus
    "MiniPlayer beenden": "Quit MiniPlayer",
    "Einstellungen …": "Settings …",
    "Bei Anmeldung starten": "Launch at Login",
    "Zurück in die Menüleiste": "Back to Menu Bar",
    "Als Fenster lösen": "Pop Out as Window",
    "Visualizer in der Menüleiste": "Menu Bar Visualizer",
    "Von Spotify abmelden": "Sign Out of Spotify",
    "Client ID ändern …": "Change Client ID …",

    // Setup and login
    "Einrichtung": "Setup",
    "Nur einmal nötig": "Only needed once",
    "Erstelle im Spotify Developer Dashboard eine App (Name egal).": "Create an app in the Spotify Developer Dashboard (any name).",
    "Dashboard öffnen": "Open Dashboard",
    "Trage diese Redirect URI ein und hake „Web API“ an:": "Add this redirect URI and tick “Web API”:",
    "Kopiert ✓": "Copied ✓",
    "Kopieren": "Copy",
    "Kopiere die Client ID der App hierher:": "Paste the app's Client ID here:",
    "z. B. 3f9a…": "e.g. 3f9a…",
    "Hinweis: Spotify verlangt seit 2026 für eigene Developer-Apps ein Premium-Konto.": "Note: since 2026 Spotify requires a Premium account for developer apps.",
    "Abbrechen": "Cancel",
    "Weiter": "Continue",
    "Melde dich mit deinem Spotify-Konto an,\num deine Musik hier zu steuern.": "Sign in with your Spotify account\nto control your music from here.",
    "Bestätige die Anmeldung im Browser …": "Confirm the sign-in in your browser …",
    "Mit Spotify anmelden": "Sign in with Spotify",
    "Client ID ändern": "Change Client ID",
    "Angemeldet ✓": "Signed in ✓",
    "Anmeldung abgebrochen": "Sign-in cancelled",
    "Du kannst diesen Tab schließen und den Player oben in der Menüleiste benutzen.": "You can close this tab and use the player in the menu bar.",
    "Versuche es im Player erneut.": "Please try again in the player.",
    "Port %d ist belegt: %@": "Port %d is in use: %@",
    "Zeitüberschreitung bei der Anmeldung.": "Sign-in timed out.",
    "Anmeldung wurde abgelehnt.": "Sign-in was declined.",
    "Spotify-Fehler: %@": "Spotify error: %@",
    "Ungültige Antwort von Spotify.": "Invalid response from Spotify.",
    "Nicht angemeldet.": "Not signed in.",
    "Sitzung abgelaufen – bitte neu anmelden.": "Session expired, please sign in again.",
    "Kein Token erhalten.": "No token received.",
    "Token-Fehler (%d)": "Token error (%d)",

    // Player
    "Gerade läuft nichts": "Nothing playing",
    "Wähle unten einen Song aus": "Pick a song below",
    "Aus Lieblingssongs entfernen": "Remove from Liked Songs",
    "Zu Lieblingssongs hinzufügen": "Add to Liked Songs",
    "Zu Lieblingssongs hinzugefügt": "Added to Liked Songs",
    "Aus Lieblingssongs entfernt": "Removed from Liked Songs",
    "Song teilen": "Share Song",
    "Zufallswiedergabe": "Shuffle",
    "Vorheriger Titel": "Previous",
    "Nächster Titel": "Next",
    "Wiederholen": "Repeat",
    "Bibliothek einblenden": "Show Library",
    "Nur das Cover zeigen": "Show Cover Only",
    "Keine Geräte gefunden": "No devices found",
    "Dieser Mac (MiniPlayer)": "This Mac (MiniPlayer)",
    "Dieser Mac": "This Mac",
    "Eingebauten Player neu starten": "Restart Built-in Player",
    "Geräteliste aktualisieren": "Refresh Devices",
    "Wiedergabegerät": "Playback Device",
    "Gerät wählen": "Choose Device",
    "Zur Warteschlange hinzugefügt": "Added to queue",
    "Aktiviere zuerst den eingebauten Player (Button oben).": "Activate the built-in player first (button above).",
    "Starte eingebauten Player …": "Starting built-in player …",
    "Kein Wiedergabegerät gefunden.": "No playback device found.",

    // Library
    "Likes": "Likes",
    "Playlists": "Playlists",
    "Suche": "Search",
    "Lieblingssongs": "Liked Songs",
    "%d Songs": "%d songs",
    "Neu laden": "Reload",
    "Zufällig abspielen": "Shuffle Play",
    "Noch keine Lieblingssongs.": "No liked songs yet.",
    "Deine Playlists": "Your Playlists",
    "Keine Playlists gefunden.": "No playlists found.",
    "Zurück": "Back",
    "Spotify zeigt die Songs nur für eigene Playlists an.\nAbspielen funktioniert trotzdem.": "Spotify only lists the songs of your own playlists.\nPlaying still works.",
    "Diese Playlist ist leer.": "This playlist is empty.",
    "Songs, Künstler, Alben …": "Songs, artists, albums …",
    "Finde neue Songs auf Spotify.": "Find new songs on Spotify.",
    "Keine Treffer.": "No results.",
    "Abspielen": "Play",
    "Zur Warteschlange hinzufügen": "Add to Queue",
    "Teilen …": "Share …",
    "Link kopieren": "Copy Link",
    "Erneut versuchen": "Try Again",

    // Lyrics
    "Lyrics schließen": "Close Lyrics",
    "Instrumental, kein Text zum Mitsingen.": "Instrumental, nothing to sing along to.",
    "Für diesen Song wurden keine Lyrics gefunden.": "No lyrics found for this song.",
    "Lyrics konnten nicht geladen werden.": "Lyrics could not be loaded.",
    "Starte einen Song, um die Lyrics zu sehen.": "Play a song to see its lyrics.",
    "Lyrics von LRCLIB": "Lyrics from LRCLIB",

    // Built-in player
    "Eingebauter Player": "Built-in Player",
    "Einmal im Browser bestätigen, dann spielt MiniPlayer selbst ab. Ohne Spotify-App.": "Confirm once in the browser, then MiniPlayer plays by itself. No Spotify app needed.",
    "Aktivieren": "Activate",
    "Bestätige im Browser …": "Confirm in your browser …",
    "Danach ist der eingebaute Player sofort bereit.": "The built-in player is ready right after.",
    "Neu starten": "Restart",
    "librespot fehlt": "librespot is missing",
    "Installiere es mit: brew install librespot": "Install it with: brew install librespot",
    "librespot konnte nicht starten: %@": "librespot could not start: %@",
    "Spotify Premium nötig: Der eingebaute Player funktioniert nur mit einem Premium-Konto.": "Spotify Premium required: the built-in player only works with a Premium account.",
    "librespot wurde beendet (Code %d).": "librespot exited (code %d).",
    "Verbindung verloren – starte neu …": "Connection lost, restarting …",

    // Errors
    "Für die Steuerung braucht Spotify ein Premium-Konto.": "Spotify requires a Premium account for playback control.",
    "Kein aktives Gerät gefunden.": "No active device found.",
    "Spotify verweigert den Zugriff: Dein Konto ist in der Developer-App nicht freigeschaltet. Im Dashboard unter „User Management“ deine Spotify-E-Mail eintragen.": "Spotify denied access: your account isn't enabled for this developer app. Add your Spotify email under “User Management” in the dashboard.",
    "Spotify verweigert den Zugriff (403): fehlende Berechtigung. Bitte abmelden und neu anmelden.": "Spotify denied access (403): missing permission. Please sign out and sign in again.",
    "Spotify verweigert den Zugriff (403). Seit 2026 funktionieren eigene Developer-Apps nur, wenn das Konto des App-Besitzers Spotify Premium hat.": "Spotify denied access (403). Since 2026, developer apps only work if the app owner's account has Spotify Premium.",
    "Spotify verweigert den Zugriff (403): %@": "Spotify denied access (403): %@",
    "Zu viele Anfragen – Spotify bremst kurz. Gleich nochmal versuchen.": "Too many requests, Spotify is throttling. Try again in a moment.",

    // Settings
    "Einstellungen": "Settings",
    "Einstellungen schließen": "Close Settings",
    "Allgemein": "General",
    "Sprache": "Language",
    "Automatisch": "Automatic",
    "Mit dem Mac starten": "Start with your Mac",
    "Fenster immer im Vordergrund": "Keep window on top",
    "Gilt für den als Fenster gelösten Player.": "Applies to the popped-out player window.",
    "Konto": "Account",
    "Bei Spotify angemeldet": "Signed in to Spotify",
    "Abmelden": "Sign Out",
    "Läuft": "Running",
    "Gestoppt": "Stopped",
    "Nicht eingerichtet": "Not set up",
    "Wartet auf Browser …": "Waiting for browser …",
    "Nicht verfügbar": "Not available",
    "Über": "About",
    "Quellcode auf GitHub": "Source code on GitHub",
    "Konnte nicht geändert werden: %@": "Could not be changed: %@",
    "Audioqualität": "Audio quality",
    "Niedrig (96 kbit/s)": "Low (96 kbit/s)",
    "Normal (160 kbit/s)": "Normal (160 kbit/s)",
    "Hoch (320 kbit/s)": "High (320 kbit/s)",
    "Beim Ändern startet der Player kurz neu.": "The player restarts briefly when changed.",
]
