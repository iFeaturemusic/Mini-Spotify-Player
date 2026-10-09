// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MiniPlayer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AudioRing", path: "Sources/AudioRing"),
        .executableTarget(name: "MiniPlayer", dependencies: ["AudioRing"], path: "Sources/MiniPlayer"),
    ]
)
