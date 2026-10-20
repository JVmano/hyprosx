import AppKit
import QuartzCore
import HyprCore

final class DimWindows {
    private struct Entry {
        let window: NSWindow
        var strength: Double
        var frame: Rect
        var timing: MotionTiming?
    }

    private struct Around {
        let id: WindowID
        let window: NSWindow
        var strength: Double
        var frame: Rect
    }

    private var inactive: [WindowID: Entry] = [:]
    private var pending: Set<WindowID> = []
    private var around: Around?

    @discardableResult
    func apply(_ set: DecorationSet, animating: Set<WindowID>, timing base: MotionTiming?, noAnim: (WindowID) -> Bool,
               monitorFrame: (WindowID) -> Rect?) -> WindowID? {
        let primaryHeight = Self.primaryHeight()
        func timing(_ id: WindowID) -> MotionTiming? { noAnim(id) ? nil : base }
        var wanted: [WindowID: Decoration] = [:]
        for d in set.windows where d.dim > 0 { wanted[d.id] = d }
        let present = Set(set.windows.map(\.id))
        for (id, entry) in inactive where wanted[id] == nil {
            inactive[id] = nil
            if pending.remove(id) != nil { continue }
            if present.contains(id) {
                fade(entry.window, to: 0, timing: timing(id)) { entry.window.orderOut(nil) }
            } else {
                entry.window.orderOut(nil)
            }
        }
        for (id, d) in wanted {
            if var entry = inactive[id] {
                if entry.strength != d.dim {
                    entry.window.backgroundColor = NSColor.black.withAlphaComponent(d.dim)
                    entry.strength = d.dim
                }
                entry.timing = timing(id)
                let release = pending.contains(id) && !animating.contains(id)
                if release { pending.remove(id) }
                if !animating.contains(id), release || entry.frame != d.frame {
                    place(entry.window, d.frame, primaryHeight: primaryHeight)
                    entry.frame = d.frame
                }
                if release { show(entry.window, above: id, timing: entry.timing) }
                inactive[id] = entry
            } else {
                let window = make(alpha: d.dim)
                inactive[id] = Entry(window: window, strength: d.dim, frame: d.frame, timing: timing(id))
                window.alphaValue = 0
                place(window, d.frame, primaryHeight: primaryHeight)
                if animating.contains(id) {
                    pending.insert(id)
                } else {
                    show(window, above: id, timing: timing(id))
                }
            }
        }
        let target = set.dimAroundStrength > 0 ? set.dimAround.last : nil
        if let current = around, current.id != target {
            fade(current.window, to: 0, timing: timing(current.id)) { current.window.orderOut(nil) }
            around = nil
        }
        guard let target, let frame = monitorFrame(target) else { return nil }
        if var current = around {
            if current.strength != set.dimAroundStrength {
                current.window.backgroundColor = NSColor.black.withAlphaComponent(set.dimAroundStrength)
                current.strength = set.dimAroundStrength
            }
            if current.frame != frame {
                place(current.window, frame, primaryHeight: primaryHeight)
                current.frame = frame
            }
            around = current
            return nil
        }
        let window = make(alpha: set.dimAroundStrength)
        window.alphaValue = 0
        place(window, frame, primaryHeight: primaryHeight)
        window.order(.below, relativeTo: Int(target))
        fade(window, to: 1, timing: timing(target)) {}
        around = Around(id: target, window: window, strength: set.dimAroundStrength, frame: frame)
        return target
    }

    func move(_ id: WindowID, _ frame: Rect) {
        guard let entry = inactive[id] else { return }
        place(entry.window, frame, primaryHeight: Self.primaryHeight())
        inactive[id]?.frame = frame
        if pending.remove(id) != nil { show(entry.window, above: id, timing: entry.timing) }
    }

    func reorder(_ id: WindowID) {
        if let current = around, current.id == id { current.window.order(.below, relativeTo: Int(id)) }
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

    private func show(_ window: NSWindow, above id: WindowID, timing: MotionTiming?) {
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

    private static func primaryHeight() -> Double {
        Double(NSScreen.screens.first?.frame.height ?? 0)
    }

    private func place(_ window: NSWindow, _ f: Rect, primaryHeight: Double) {
        let target = NSRect(x: f.x, y: primaryHeight - f.maxY, width: f.width, height: f.height)
        if window.frame.size == target.size {
            window.setFrameOrigin(target.origin)
        } else {
            window.setFrame(target, display: false)
        }
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
