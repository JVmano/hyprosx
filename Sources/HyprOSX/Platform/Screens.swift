import AppKit
import HyprCore

enum Screens {
    static func current() -> [MonitorInfo] {
        MonitorLayout.infos(NSScreen.screens.map {
            ScreenDescription(name: $0.localizedName, frame: Rect($0.frame), visibleFrame: Rect($0.visibleFrame))
        })
    }

    static func cursor() -> Point {
        let p = CGEvent(source: nil)?.location ?? .zero
        return Point(x: Double(p.x), y: Double(p.y))
    }
}
