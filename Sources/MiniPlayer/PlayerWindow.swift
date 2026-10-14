import AppKit
import SwiftUI

/// Borderless, resizable floating window for the detached player. Borderless windows can't
/// become key by default, which would break typing in the search field.
final class PlayerPanel: NSPanel, NSWindowDelegate {
    static let normalWidths: ClosedRange<CGFloat> = 300...420
    static let compactWidths: ClosedRange<CGFloat> = 300...900

    /// SwiftUI height for a given width; used to keep the cover-only layout tight while resizing.
    var heightForWidth: ((CGFloat) -> CGFloat)?
    private(set) var compact = false
    private var normalHeight: CGFloat

    init(contentViewController: NSViewController) {
        let stored = UserDefaults.standard.double(forKey: "windowNormalHeight")
        normalHeight = stored > 0 ? stored : RootView.size.height
        super.init(contentRect: NSRect(origin: .zero, size: RootView.size), styleMask: [.borderless, .resizable],
                   backing: .buffered, defer: false)
        self.contentViewController = contentViewController
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .darkAqua)
        delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Applies the size rules of the current layout while keeping the top edge in place.
    func applyLayout(compact: Bool, animated: Bool) {
        self.compact = compact
        let widths = compact ? Self.compactWidths : Self.normalWidths
        minSize = NSSize(width: widths.lowerBound, height: compact ? 100 : 600)
        maxSize = NSSize(width: widths.upperBound, height: 10_000)

        let width = min(max(frame.width, widths.lowerBound), widths.upperBound)
        let height = compact ? (heightForWidth?(width) ?? frame.height) : normalHeight
        var newFrame = frame
        newFrame.origin.y += frame.height - height
        newFrame.size = NSSize(width: width, height: height)
        if newFrame != frame {
            setFrame(newFrame, display: true, animate: animated)
        }
        invalidateShadow()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard compact, let heightForWidth else { return frameSize }
        let width = min(max(frameSize.width, Self.compactWidths.lowerBound), Self.compactWidths.upperBound)
        return NSSize(width: width, height: heightForWidth(width))
    }

    func windowDidResize(_ notification: Notification) {
        invalidateShadow()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard !compact else { return }
        normalHeight = frame.height
        UserDefaults.standard.set(Double(normalHeight), forKey: "windowNormalHeight")
    }
}

/// Lets the user move the detached window by dragging the cover.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
