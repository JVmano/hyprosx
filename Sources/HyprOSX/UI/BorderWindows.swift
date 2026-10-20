import AppKit
import QuartzCore
import HyprCore

private struct Shape: Equatable {
    var size: NSSize
    var width: Double
    var radius: Double
}

private final class BorderView: NSView {
    let ring = CAShapeLayer()
    let gradient = CAGradientLayer()
    var shape: Shape?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.addSublayer(gradient)
        ring.fillRule = .evenOdd
        root.mask = ring
        layer = root
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }
}

final class BorderWindows {
    private struct Entry {
        let window: NSWindow
        let view: BorderView
        var state: Decoration
    }

    private var entries: [WindowID: Entry] = [:]
    private var pending: Set<WindowID> = []
    private var radius = 10.0

    static func defaultRadius() -> Double {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 16 : 10
    }

    func apply(_ set: DecorationSet, animating: Set<WindowID>, radius: Double, colorTiming: MotionTiming?, angle: (timing: MotionTiming, loop: Bool)?) {
        let radiusChanged = radius != self.radius
        self.radius = radius
        let primaryHeight = Self.primaryHeight()
        var wanted: [WindowID: Decoration] = [:]
        for d in set.windows where d.border != nil { wanted[d.id] = d }
        for id in entries.keys where wanted[id] == nil {
            entries[id]?.window.orderOut(nil)
            entries[id] = nil
            pending.remove(id)
        }
        for (id, d) in wanted {
            if var e = entries[id] {
                let release = pending.contains(id) && !animating.contains(id)
                if release { pending.remove(id) }
                if e.state.border != d.border { paint(e.view, d, timing: colorTiming) }
                if !animating.contains(id), release || radiusChanged || e.state.frame != d.frame || e.state.borderWidth != d.borderWidth {
                    place(e.window, e.view, frame: d.frame, width: d.borderWidth, primaryHeight: primaryHeight)
                }
                let activated = d.isActive && !e.state.isActive
                if activated { spin(e.view, angle) }
                if release || (activated && !pending.contains(id)) { e.window.order(.below, relativeTo: Int(id)) }
                e.state = d
                entries[id] = e
            } else {
                let e = make(d)
                entries[id] = e
                paint(e.view, d, timing: nil)
                place(e.window, e.view, frame: d.frame, width: d.borderWidth, primaryHeight: primaryHeight)
                spin(e.view, angle)
                if animating.contains(id) {
                    pending.insert(id)
                } else {
                    e.window.order(.below, relativeTo: Int(id))
                }
            }
        }
    }

    func move(_ id: WindowID, _ frame: Rect) {
        guard let e = entries[id] else { return }
        place(e.window, e.view, frame: frame, width: e.state.borderWidth, primaryHeight: Self.primaryHeight())
        if pending.remove(id) != nil { e.window.order(.below, relativeTo: Int(id)) }
    }

    func reorder(_ id: WindowID) {
        guard !pending.contains(id) else { return }
        entries[id]?.window.order(.below, relativeTo: Int(id))
    }

    func removeAll() {
        for e in entries.values { e.window.orderOut(nil) }
        entries = [:]
        pending = []
    }

    private func make(_ d: Decoration) -> Entry {
        let view = BorderView(frame: .zero)
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.contentView = view
        return Entry(window: window, view: view, state: d)
    }

    private static func primaryHeight() -> Double {
        Double(NSScreen.screens.first?.frame.height ?? 0)
    }

    private func place(_ window: NSWindow, _ view: BorderView, frame f: Rect, width w: Double, primaryHeight: Double) {
        let outer = NSRect(x: f.x - w, y: primaryHeight - f.maxY - w, width: f.width + 2 * w, height: f.height + 2 * w)
        let shape = Shape(size: outer.size, width: w, radius: radius)
        guard view.shape != shape else { return window.setFrameOrigin(outer.origin) }
        view.shape = shape
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.setFrame(outer, display: false)
        let bounds = NSRect(origin: .zero, size: outer.size)
        let path = CGMutablePath()
        path.addRoundedRect(in: bounds, cornerWidth: radius + w, cornerHeight: radius + w)
        path.addRoundedRect(in: bounds.insetBy(dx: w, dy: w), cornerWidth: radius, cornerHeight: radius)
        view.ring.frame = bounds
        view.ring.path = path
        let side = hypot(bounds.width, bounds.height)
        view.gradient.frame = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        CATransaction.commit()
    }

    private func paint(_ view: BorderView, _ d: Decoration, timing: MotionTiming?) {
        guard let g = d.border else { return }
        var colors = g.colors.map { CGColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: $0.a) }
        if colors.count == 1 { colors.append(colors[0]) }
        let radians = g.angleDegrees * .pi / 180
        let start = CGPoint(x: 0.5 - cos(radians) / 2, y: 0.5 - sin(radians) / 2)
        let end = CGPoint(x: 0.5 + cos(radians) / 2, y: 0.5 + sin(radians) / 2)
        if let timing {
            let fade = CABasicAnimation(keyPath: "colors")
            fade.fromValue = view.gradient.presentation()?.colors ?? view.gradient.colors
            fade.toValue = colors
            fade.duration = timing.duration
            fade.timingFunction = Self.function(timing.curve)
            view.gradient.add(fade, forKey: "colors")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.gradient.colors = colors
        view.gradient.startPoint = start
        view.gradient.endPoint = end
        CATransaction.commit()
    }

    private func spin(_ view: BorderView, _ angle: (timing: MotionTiming, loop: Bool)?) {
        guard let angle else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = 2 * Double.pi
        turn.duration = angle.timing.duration
        turn.timingFunction = Self.function(angle.timing.curve)
        turn.repeatCount = angle.loop ? .infinity : 1
        view.gradient.add(turn, forKey: "angle")
    }

    private static func function(_ curve: Bezier) -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(curve.p1.x), Float(curve.p1.y), Float(curve.p2.x), Float(curve.p2.y))
    }
}
