import AppKit
import HyprCore

final class DimWindows {
    private struct Entry {
        let window: NSWindow
        var strength: Double
        var frame: Rect
    }

    private var inactive: [WindowID: Entry] = [:]
    private var pending: Set<WindowID> = []
    private var timing: MotionTiming?
    private var around: (id: WindowID, window: NSWindow, strength: Double)?

    func apply(_ set: DecorationSet, animating: Set<WindowID>, timing: MotionTiming?, monitorFrame: (WindowID) -> Rect?) {
        self.timing = timing
        var wanted: [WindowID: Decoration] = [:]
        for d in set.windows where d.dim > 0 { wanted[d.id] = d }
        for (id, entry) in inactive where wanted[id] == nil {
            inactive[id] = nil
            if pending.remove(id) != nil { continue }
            fade(entry.window, to: 0, timing: timing) { entry.window.orderOut(nil) }
        }
        for (id, d) in wanted {
            if var entry = inactive[id] {
                if entry.strength != d.dim {
                    entry.window.backgroundColor = NSColor.black.withAlphaComponent(d.dim)
                    entry.strength = d.dim
                }
                let release = pending.contains(id) && !animating.contains(id)
                if release { pending.remove(id) }
                if !animating.contains(id), release || entry.frame != d.frame {
                    place(entry.window, d.frame)
                    entry.frame = d.frame
                }
                if release { show(entry.window, above: id) }
                inactive[id] = entry
            } else {
                let window = make(alpha: d.dim)
                inactive[id] = Entry(window: window, strength: d.dim, frame: d.frame)
                window.alphaValue = 0
                place(window, d.frame)
                if animating.contains(id) {
                    pending.insert(id)
                } else {
                    show(window, above: id)
                }
            }
        }
        let target = set.dimAround.last
        if let current = around, current.id != target {
            fade(current.window, to: 0, timing: timing) { current.window.orderOut(nil) }
            around = nil
        }
        if let target, let frame = monitorFrame(target) {
            if var current = around {
                if current.strength != set.dimAroundStrength {
                    current.window.backgroundColor = NSColor.black.withAlphaComponent(set.dimAroundStrength)
                    current.strength = set.dimAroundStrength
                    around = current
                }
                place(current.window, frame)
            } else {
                let window = make(alpha: set.dimAroundStrength)
                window.alphaValue = 0
                place(window, frame)
                window.order(.below, relativeTo: Int(target))
                fade(window, to: 1, timing: timing) {}
                around = (target, window, set.dimAroundStrength)
            }
        }
    }

    func move(_ id: WindowID, _ frame: Rect) {
        guard let entry = inactive[id] else { return }
        place(entry.window, frame)
        inactive[id]?.frame = frame
        if pending.remove(id) != nil { show(entry.window, above: id) }
    }

    func reorder(_ id: WindowID) {
        guard !pending.contains(id) else { return }
        inactive[id]?.window.order(.above, relativeTo: Int(id))
    }

    func removeAll() {
        for entry in inactive.values { entry.window.orderOut(nil) }
        inactive = [:]
        pending = []
        around?.window.orderOut(nil)
        around = nil
    }

    private func show(_ window: NSWindow, above id: WindowID) {
        window.order(.above, relativeTo: Int(id))
        fade(window, to: 1, timing: timing) {}
    }

    private func make(alpha: Double) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(alpha)
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.transient, .ignoresCycle]
        return window
    }

    private func place(_ window: NSWindow, _ f: Rect) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        window.setFrame(NSRect(x: f.x, y: primaryHeight - f.maxY, width: f.width, height: f.height), display: false)
    }

    private func fade(_ window: NSWindow, to alpha: CGFloat, timing: MotionTiming?, done: @escaping () -> Void) {
        guard let timing else {
            window.alphaValue = alpha
            done()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = timing.duration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: Float(timing.curve.p1.x), Float(timing.curve.p1.y),
                                                       Float(timing.curve.p2.x), Float(timing.curve.p2.y))
            window.animator().alphaValue = alpha
        }, completionHandler: done)
    }
}
