import AppKit
import SwiftUI

/// Borderless floating window for the detached player. Borderless windows can't become key by
/// default, which would break typing in the search field.
final class PlayerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentViewController: NSViewController) {
        super.init(contentRect: NSRect(origin: .zero, size: RootView.size), styleMask: [.borderless],
                   backing: .buffered, defer: false)
        self.contentViewController = contentViewController
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .darkAqua)
    }

    /// Resize to the SwiftUI content while keeping the top edge in place.
    func fitToContent(animated: Bool) {
        guard let view = contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        guard size.height > 0, size != frame.size else { return }
        var newFrame = frame
        newFrame.origin.y += frame.height - size.height
        newFrame.size = size
        setFrame(newFrame, display: true, animate: animated)
        invalidateShadow()
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
