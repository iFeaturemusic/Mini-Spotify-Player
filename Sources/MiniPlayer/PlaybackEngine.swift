import CryptoKit
import Darwin
import Foundation
import Observation

@MainActor @Observable
/// Runs librespot in the background as the Spotify Connect device "MiniPlayer".
/// The first run opens the browser once for librespot's own login; credentials are cached afterwards.
final class PlaybackEngine {
    enum Status: Equatable {
        case unavailable
        case needsSetup
        case authorizing
        case stopped
        case running
        case failed(String)
    }

    static let deviceName = "MiniPlayer"
/// librespot derives its device id from the SHA-1 of the device name.
    static let deviceID = Insecure.SHA1.hash(data: Data(deviceName.utf8)).map { String(format: "%02x", $0) }.joined()

    private(set) var status: Status = .stopped

    let binary: URL?
    let cacheDirectory: URL
    let logURL: URL
    let audio = AudioOutput()

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var restartCount = 0
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var credentialWatch: Task<Void, Never>?
    @ObservationIgnored private let pidURL: URL

    init() {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiniPlayer", isDirectory: true)
        cacheDirectory = support.appendingPathComponent("librespot", isDirectory: true)
        pidURL = support.appendingPathComponent("librespot.pid")
        let logs = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/MiniPlayer", isDirectory: true)
        logURL = logs.appendingPathComponent("librespot.log")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true,
                                         attributes: [.posixPermissions: 0o700])
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cacheDirectory.path)
        try? fileManager.createDirectory(at: logs, withIntermediateDirectories: true)

        binary = Self.findBinary()
        status = binary == nil ? .unavailable : (hasCredentials ? .stopped : .needsSetup)
    }

    var isAvailable: Bool { binary != nil }
    var isRunning: Bool { process?.isRunning == true }
    var hasCredentials: Bool {
        FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent("credentials.json").path)
    }

    private static func findBinary() -> URL? {
        let candidates = [
            Bundle.main.url(forAuxiliaryExecutable: "librespot")?.path,
            "/opt/homebrew/bin/librespot",
            "/usr/local/bin/librespot",
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    // MARK: - Start / Stop

    func start() {
        guard let binary, !isRunning else { return }
        restartTask?.cancel()

        let needsLogin = !hasCredentials
        var arguments = [
            "--name", Self.deviceName,
            "--device-type", "computer",
            "--bitrate", "320",
            "--cache", cacheDirectory.path,
            "--disable-audio-cache",
            "--disable-discovery",
            "--initial-volume", "70",
        ]
        var audioPipe: Pipe?
        if needsLogin {
            arguments += ["--enable-oauth", "--oauth-port", "5588"]
        } else {
// PCM goes to stdout so MiniPlayer can play it and drive the visualizer.
// (During the login run librespot prints text to stdout, so it uses its own output there.)
            arguments += ["--backend", "pipe", "--format", "F32"]
            audioPipe = Pipe()
        }

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try? FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = audioPipe ?? log
        process.standardError = log
        process.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            Task { @MainActor in self?.processEnded(code) }
        }

        do {
            try process.run()
            if let audioPipe { audio.attach(audioPipe.fileHandleForReading) }
            self.process = process
            stopping = false
            savePID(process.processIdentifier)
            if needsLogin {
                status = .authorizing
                watchForCredentials()
            } else {
                status = .running
            }
        } catch {
            status = .failed("librespot konnte nicht starten: \(error.localizedDescription)")
        }
    }

    func stop() {
        restartTask?.cancel()
        credentialWatch?.cancel()
        guard let process, process.isRunning else { return }
        stopping = true
        process.terminate()
    }

    func restart() {
        restartCount = 0
        if isRunning {
            stop()
            Task {
                for _ in 0..<20 where isRunning { try? await Task.sleep(for: .milliseconds(100)) }
                start()
            }
        } else {
            start()
        }
    }

    func forgetCredentials() {
        stop()
        try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent("credentials.json"))
        if isAvailable { status = .needsSetup }
    }

    // MARK: - Private

    private func watchForCredentials() {
        credentialWatch?.cancel()
        credentialWatch = Task { [weak self] in
            for _ in 0..<600 {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                if self.hasCredentials {
                    if self.status == .authorizing { self.restart() }
                    return
                }
            }
        }
    }

    private func processEnded(_ code: Int32) {
        process = nil
        credentialWatch?.cancel()
        clearPID()

        if stopping {
            stopping = false
            status = hasCredentials ? .stopped : .needsSetup
            return
        }

        let tail = logTail()
        if tail.contains("does not support \"free\" accounts") {
            status = .failed("Spotify Premium nötig: Der eingebaute Player funktioniert nur mit einem Premium-Konto.")
            return
        }
        if tail.localizedCaseInsensitiveContains("BadCredentials") || tail.localizedCaseInsensitiveContains("bad credentials") {
            try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent("credentials.json"))
            status = .needsSetup
            return
        }
        if !hasCredentials {
            status = .needsSetup
            return
        }

        restartCount += 1
        guard restartCount <= 5 else {
            status = .failed(Self.shortError(from: tail) ?? "librespot wurde beendet (Code \(code)).")
            return
        }
        status = .failed("Verbindung verloren – starte neu …")
        let delay = min(60.0, 2.0 * pow(2.0, Double(restartCount)))
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }

    func markHealthy() {
        restartCount = 0
    }

    private func logTail() -> String {
        guard let data = try? Data(contentsOf: logURL) else { return "" }
        return String(decoding: data.suffix(4000), as: UTF8.self)
    }

    private static func shortError(from log: String) -> String? {
        let line = log.split(separator: "\n").last { $0.contains("ERROR") || $0.contains("error") }
        return line.map { String($0.suffix(160)) }
    }

    /// Called once at app launch: stops a librespot left behind by a crashed MiniPlayer.
    func killOrphan() {
        guard let text = try? String(contentsOf: pidURL, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return }
        var name = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &name, UInt32(name.count)) > 0, String(cString: name) == "librespot" {
            kill(pid, SIGTERM)
        }
        clearPID()
    }

    private func savePID(_ pid: Int32) {
        try? String(pid).write(to: pidURL, atomically: true, encoding: .utf8)
    }

    private func clearPID() {
        try? FileManager.default.removeItem(at: pidURL)
    }
}
