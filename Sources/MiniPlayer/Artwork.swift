import AppKit
import CoreImage
import Observation
import SwiftUI

/// Large cover of the current track plus colors derived from it: a blurred backdrop for the
/// "ambient light" background and an accent color for the controls. Computed once per track.
@MainActor @Observable
final class ArtworkModel {
    private(set) var cover: NSImage?
    private(set) var backdrop: NSImage?
    private(set) var accent: Color = .spotifyGreen
    private(set) var key: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    func update(for track: Track?) {
        let url = track?.coverURL(640)
        guard url?.absoluteString != key else { return }
        key = url?.absoluteString
        task?.cancel()

        guard let url else {
            withAnimation(.easeInOut(duration: 0.6)) {
                cover = nil
                backdrop = nil
                accent = .spotifyGreen
            }
            return
        }

        task = Task {
            guard let image = await ImageLoader.shared.load(url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  !Task.isCancelled else { return }
            let palette = await Task.detached(priority: .utility) { Palette(image: cgImage) }.value
            guard !Task.isCancelled, key == url.absoluteString else { return }
            apply(cover: image, palette: palette)
        }
    }

    private func apply(cover image: NSImage, palette: Palette) {
        withAnimation(.easeInOut(duration: 0.8)) {
            cover = image
            backdrop = palette.backdrop.map { NSImage(cgImage: $0, size: .zero) }
            accent = Color(nsColor: palette.accent)
        }
    }

    #if DEBUG
    func setDemo(_ image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        key = "demo"
        apply(cover: image, palette: Palette(image: cgImage))
    }
    #endif
}

struct Palette: @unchecked Sendable {
    let backdrop: CGImage?
    let accent: NSColor

    private static let context = CIContext(options: [.cacheIntermediates: false])

    init(image: CGImage) {
        backdrop = Self.blurred(image)
        accent = Self.dominantVibrantColor(image)
    }

    private static func blurred(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let scale = 160 / max(input.extent.width, 1)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let output = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 16)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.6,
                kCIInputBrightnessKey: -0.04,
            ])
            .cropped(to: small.extent)
        return context.createCGImage(output, from: small.extent)
    }

    /// Hue with the most "vivid" weight (saturation × brightness) across a 16×16 thumbnail.
    /// Kept light and only moderately saturated so it stays readable on the backdrop,
    /// which is a darkened version of the same colors.
    private static func dominantVibrantColor(_ image: CGImage) -> NSColor {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return NSColor(Color.spotifyGreen) }

        var weight = [CGFloat](repeating: 0, count: 12)
        var red = weight, green = weight, blue = weight
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = CGFloat(pixels[index]) / 255
            let g = CGFloat(pixels[index + 1]) / 255
            let b = CGFloat(pixels[index + 2]) / 255
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            NSColor(srgbRed: r, green: g, blue: b, alpha: 1).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            guard brightness > 0.25, saturation > 0.2 else { continue }
            let bucket = min(Int(hue * 12), 11)
            let w = saturation * brightness
            weight[bucket] += w
            red[bucket] += r * w
            green[bucket] += g * w
            blue[bucket] += b * w
        }

        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0.5 else {
            return NSColor(white: 0.92, alpha: 1) // black-and-white cover
        }
        let average = NSColor(srgbRed: red[best] / weight[best], green: green[best] / weight[best],
                              blue: blue[best] / weight[best], alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(max(saturation, 0.35), 0.6), brightness: max(brightness, 0.97), alpha: 1)
    }
}

private struct AccentKey: EnvironmentKey {
    static let defaultValue = Color.spotifyGreen
}

extension EnvironmentValues {
    var accent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}
