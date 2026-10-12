import AppKit

@main
enum MiniPlayerApp {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            Task { @MainActor in
                let seconds = args.firstIndex(of: "--seconds").flatMap { args.indices.contains($0 + 1) ? Int(args[$0 + 1]) : nil }
                exit(await SelfTest.run(play: args.contains("--play"), seconds: min(max(seconds ?? 6, 2), 60)))
            }
            dispatchMain()
        }

        #if DEBUG
        if let index = args.firstIndex(of: "--icon"), index + 1 < args.count {
            Screenshots.renderIcon(to: args[index + 1])
            return
        }
        if let index = args.firstIndex(of: "--screenshots"), index + 1 < args.count {
            Screenshots.run(to: args[index + 1])
            return
        }
        #endif

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
