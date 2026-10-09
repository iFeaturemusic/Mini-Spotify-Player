import AVFoundation
import AudioRing
import Foundation

/// Plays the raw PCM stream from librespot (`--backend pipe --format F32`) and measures levels.
/// librespot stdout → reader thread → lock-free ring buffer → AVAudioSourceNode.
/// The engine only runs while audio arrives and stops itself after 3 s of silence.
final class AudioOutput: @unchecked Sendable {
    static let sampleRate = 44_100.0
    private static let bytesPerFrame = 8

    var onActivityChanged: ((Bool) -> Void)?

    private let ring: OpaquePointer
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: AudioOutput.sampleRate, channels: 2)!
    private var sourceNode: AVAudioSourceNode?

    private var idleTimer: Timer?
    private var lastRendered: UInt64 = 0
    private var idleTicks = 0
    private(set) var isActive = false

    private let lock = NSLock()
    private var engineRunning = false
    private var startPending = false

    init() {
        ring = audio_ring_create(UInt32(Self.sampleRate * 0.25), Self.sampleRate)

        let ring = self.ring
        let node = AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            if audio_ring_render(ring, left, right, frameCount) == 0 {
                isSilence.pointee = true
            }
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.isActive else { return }
            self.setEngineRunning(false)
            self.startEngine()
        }
    }

    deinit {
        audio_ring_destroy(ring)
    }

    // MARK: - Input

    func attach(_ handle: FileHandle) {
        let thread = Thread { [weak self] in
            self?.readLoop(fd: handle.fileDescriptor)
            try? handle.close()
        }
        thread.name = "MiniPlayer.audio-reader"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func readLoop(fd: Int32) {
        let chunkFrames = 2048
        let capacity = chunkFrames * Self.bytesPerFrame
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
        defer { buffer.deallocate() }
        var pending = 0

        while true {
            let count = read(fd, buffer + pending, capacity - pending)
            if count <= 0 { break }
            pending += count

            let frames = pending / Self.bytesPerFrame
            guard frames > 0 else { continue }
            requestEngineStart()

            let samples = buffer.assumingMemoryBound(to: Float.self)
            var written = 0
            var waits = 0
            while written < frames {
                written += Int(audio_ring_write(ring, samples + written * 2, UInt32(frames - written)))
                if written < frames {
// Ring buffer full: wait for playback. This keeps librespot at real-time speed.
                    usleep(15_000)
                    waits += 1
                    if waits % 70 == 0 { requestEngineStart() }
                }
            }

            let rest = pending - frames * Self.bytesPerFrame
            if rest > 0 { memmove(buffer, buffer + frames * Self.bytesPerFrame, rest) }
            pending = rest
        }
    }

    // MARK: - Engine

    private func requestEngineStart() {
        lock.lock()
        let needsStart = !engineRunning && !startPending
        if needsStart { startPending = true }
        lock.unlock()
        guard needsStart else { return }
        DispatchQueue.main.async { [weak self] in self?.startEngine() }
    }

    private func setEngineRunning(_ running: Bool) {
        lock.lock()
        engineRunning = running
        startPending = false
        lock.unlock()
    }

    private func startEngine() {
        guard !engine.isRunning else {
            setEngineRunning(true)
            return
        }
        do {
            engine.prepare()
            try engine.start()
            setEngineRunning(true)
            setActive(true)
            startIdleWatch()
            AudioLog.write("audio output started")
        } catch {
            setEngineRunning(false)
            AudioLog.write("audio output failed to start: \(error.localizedDescription)")
        }
    }

    private func stopEngine() {
        idleTimer?.invalidate()
        idleTimer = nil
        engine.stop()
        setEngineRunning(false)
        setActive(false)
        AudioLog.write("audio output stopped (idle)")
    }

    private func startIdleWatch() {
        idleTimer?.invalidate()
        lastRendered = audio_ring_rendered_frames(ring)
        idleTicks = 0
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let rendered = audio_ring_rendered_frames(self.ring)
            if rendered == self.lastRendered {
                self.idleTicks += 1
                if self.idleTicks >= 3 { self.stopEngine() }
            } else {
                self.idleTicks = 0
                self.lastRendered = rendered
            }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        onActivityChanged?(active)
    }

    // MARK: - Control

    func flush() {
        audio_ring_request_flush(ring)
    }

    func levels() -> (Float, Float, Float, Float) {
        var values: (Float, Float, Float, Float) = (0, 0, 0, 0)
        withUnsafeMutablePointer(to: &values) { pointer in
            pointer.withMemoryRebound(to: Float.self, capacity: 4) { audio_ring_levels(ring, $0) }
        }
        return values
    }
}

enum AudioLog {
    static func write(_ line: String) {
        let url = APILog.url.deletingLastPathComponent().appendingPathComponent("audio.log")
        let entry = "\(Date().formatted(.iso8601)) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            if (try? handle.seekToEnd()) ?? 0 > 256 * 1024 { try? handle.truncate(atOffset: 0) }
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }
}
