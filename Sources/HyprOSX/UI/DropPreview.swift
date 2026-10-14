import AppKit
import HyprCore

private final class DropPreviewView: NSView {
    static let radius: CGFloat = 10
    static let stroke: CGFloat = 2

    var color = NSColor.controlAccentColor

    override func draw(_ dirtyRect: NSRect) {
        let inset = Self.stroke / 2
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: Self.radius, yRadius: Self.radius)
        color.withAlphaComponent(0.25).setFill()
        path.fill()
        color.setStroke()
        path.lineWidth = Self.stroke
        path.stroke()
    }
}

final class DropPreview {
    private var window: NSWindow?
    private let view = DropPreviewView()

    func show(_ frame: Rect, border: Gradient) {
        let window = self.window ?? makeWindow()
        self.window = window
        view.color = Self.color(of: border)
        view.needsDisplay = true
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        window.setFrame(NSRect(x: frame.x, y: primaryHeight - frame.y - frame.height, width: frame.width, height: frame.height), display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        window.contentView = view
        return window
    }

    private static func color(of border: Gradient) -> NSColor {
        guard let c = border.colors.first, !border.isFullyTransparent else { return .controlAccentColor }
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}
