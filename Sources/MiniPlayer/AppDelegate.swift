import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = AppStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    private var visualizerTimer: Timer?
    private var visualizerView: VisualizerView?
    private var bars: [CGFloat] = [0, 0, 0, 0]
    private var bandAverages: [Float] = [0, 0, 0, 0]
    private var tick = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusIcon()

        let root = RootView()
            .environment(store)
            .environment(store.auth)
            .environment(store.player)
            .environment(store.library)
            .environment(store.engine)
            .environment(store.artwork)
            .environment(store.lyrics)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = RootView.size
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        store.player.onStatusChanged = { [weak self] in self?.updateStatusIcon() }
        store.engine.audio.onActivityChanged = { [weak self] active in self?.setVisualizer(active) }
        store.showPopover = { [weak self] in self?.showPopover() }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(spotifyStateChanged(_:)),
            name: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        store.launched()

        if ProcessInfo.processInfo.arguments.contains("--show") {
            DispatchQueue.main.async { self.showPopover() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.terminate()
    }

    // MARK: - Status Item

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        if let track = store.player.track {
            button.toolTip = "\(track.name) – \(track.subtitle)"
        } else {
            button.toolTip = "MiniPlayer"
        }
        guard visualizerTimer == nil else { return }
        let playing = store.player.isPlaying
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: playing ? "waveform" : "music.note",
                            accessibilityDescription: "MiniPlayer")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
    }

    // MARK: - Visualizer

    // On macOS 26 only the active menu bar shows the real status item; other displays show a
    // snapshot that is re-rendered on every redraw (expensive). The bars are therefore CALayers
    // animated directly, and the snapshots are refreshed only a couple of times per second.
    private static let visualizerFPS = 24.0
    private static let snapshotEveryTicks = 12

    static var visualizerEnabled: Bool {
        UserDefaults.standard.string(forKey: "visualizerMode") != "off"
    }

    private func setVisualizer(_ active: Bool) {
        guard let button = statusItem.button else { return }
        if active, visualizerTimer == nil, Self.visualizerEnabled {
            bars = [0, 0, 0, 0]
            bandAverages = [0, 0, 0, 0]
            let view = visualizerView ?? VisualizerView(frame: button.bounds)
            view.frame = button.bounds
            view.autoresizingMask = [.width, .height]
            if view.superview == nil { button.addSubview(view) }
            view.isHidden = false
            view.setLevels(bars)
            visualizerView = view
            button.image = nil
            let timer = Timer(timeInterval: 1 / Self.visualizerFPS, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.visualizerTick() }
            }
            timer.tolerance = 0.005
            RunLoop.main.add(timer, forMode: .common)
            visualizerTimer = timer
        } else if !active || !Self.visualizerEnabled {
            visualizerTimer?.invalidate()
            visualizerTimer = nil
            visualizerView?.isHidden = true
            updateStatusIcon()
        }
    }

    private func visualizerTick() {
        let raw = store.engine.audio.levels()
        let levels = [raw.0, raw.1, raw.2, raw.3]
        for band in 0..<4 {
            let level = levels[band]
            var target: CGFloat = 0
            if level > 1e-5 {
                // Relative to the band's recent average, so the bars move at any volume.
                if bandAverages[band] < 1e-7 { bandAverages[band] = level }
                bandAverages[band] = bandAverages[band] * 0.97 + level * 0.03
                let db = 20 * log10(level / bandAverages[band])
                target = CGFloat(min(max(0.55 + db / 14, 0.1), 1))
            }
            let current = bars[band]
            bars[band] = target > current ? current + (target - current) * 0.6 : current * 0.8 + target * 0.2
        }
        visualizerView?.setLevels(bars)

        tick += 1
        if tick % Self.snapshotEveryTicks == 0 {
            statusItem.button?.needsDisplay = true
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func spotifyStateChanged(_ notification: Notification) {
        store.player.handleLocalSpotifyChange(notification.userInfo)
    }

    // MARK: - Context menu

    private func showMenu() {
        if popover.isShown { popover.performClose(nil) }
        let menu = NSMenu()

        let login = NSMenuItem(title: "Bei Anmeldung starten", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let visualizer = NSMenuItem(title: "Visualizer in der Menüleiste", action: #selector(toggleVisualizer), keyEquivalent: "")
        visualizer.target = self
        visualizer.state = Self.visualizerEnabled ? .on : .off
        menu.addItem(visualizer)
        menu.addItem(.separator())

        if store.auth.isLoggedIn {
            let logout = NSMenuItem(title: "Von Spotify abmelden", action: #selector(logout), keyEquivalent: "")
            logout.target = self
            menu.addItem(logout)
        }
        let clientID = NSMenuItem(title: "Client ID ändern …", action: #selector(editClientID), keyEquivalent: "")
        clientID.target = self
        menu.addItem(clientID)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "MiniPlayer beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleVisualizer() {
        UserDefaults.standard.set(Self.visualizerEnabled ? "off" : "on", forKey: "visualizerMode")
        setVisualizer(false)
        if store.engine.audio.isActive { setVisualizer(true) }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    }

    @objc private func logout() {
        store.logout()
    }

    @objc private func editClientID() {
        store.editingClientID = true
        showPopover()
    }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        store.popoverDidOpen()
    }

    func popoverDidClose(_ notification: Notification) {
        store.popoverDidClose()
    }
}

final class VisualizerView: NSView {
    private let barLayers: [CALayer] = (0..<4).map { _ in CALayer() }
    private var levels: [CGFloat] = [0, 0, 0, 0]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in barLayers {
            bar.cornerRadius = 1.3
            bar.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
            layer?.addSublayer(bar)
        }
        updateColor()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    override func layout() {
        super.layout()
        setLevels(levels)
    }

    func setLevels(_ newLevels: [CGFloat]) {
        levels = newLevels
        let width: CGFloat = 2.6
        let gap: CGFloat = 1.8
        let minHeight: CGFloat = 2.6
        let maxHeight = min(bounds.height - 6, 15)
        var x = ((bounds.width - (width * 4 + gap * 3)) / 2).rounded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (bar, level) in zip(barLayers, newLevels) {
            let height = minHeight + level * (maxHeight - minHeight)
            bar.frame = CGRect(x: x, y: (bounds.height - height) / 2, width: width, height: height)
            x += width + gap
        }
        CATransaction.commit()
    }

    private func updateColor() {
        var color = NSColor.labelColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.cgColor
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        barLayers.forEach { $0.backgroundColor = color }
        CATransaction.commit()
    }
}
