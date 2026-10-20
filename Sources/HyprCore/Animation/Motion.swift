import Foundation

public struct MotionEnvironment: Equatable, Sendable {
    public var lowPower: Bool
    public var reduceMotion: Bool
    public init(lowPower: Bool = false, reduceMotion: Bool = false) { self.lowPower = lowPower; self.reduceMotion = reduceMotion }
}

public struct MotionTiming: Equatable, Sendable {
    public var duration: Double
    public var curve: Bezier
    public init(duration: Double, curve: Bezier) { self.duration = duration; self.curve = curve }
}

public struct MotionPlan: Equatable, Sendable {
    public var from: Rect
    public var to: Rect
    public var timing: MotionTiming
    public init(from: Rect, to: Rect, timing: MotionTiming) { self.from = from; self.to = to; self.timing = timing }
}

public enum Motion {
    public static func timing(_ leafName: String, config: Config, environment: MotionEnvironment, noAnim: Bool = false) -> MotionTiming? {
        guard !noAnim else { return nil }
        if environment.lowPower && !config.macos.animationsOnLowPower { return nil }
        if environment.reduceMotion && config.macos.respectReduceMotion { return nil }
        return decorationTiming(leafName, config: config)
    }

    public static func decorationTiming(_ leafName: String, config: Config) -> MotionTiming? {
        guard config.animationsOptions.enabled else { return nil }
        let leaf = config.animations.leaf(leafName)
        guard leaf.enabled, leaf.durationMs > 0 else { return nil }
        return MotionTiming(duration: leaf.durationMs / 1000, curve: config.beziers[leaf.curve] ?? Bezier.builtIns["default"]!)
    }

    static func leafName(for reason: FrameReason, config: Config) -> String? {
        switch reason {
        case .layout: return "windowsMove"
        case .open: return "windowsIn"
        case .workspaceIn: return "workspacesIn"
        case .specialIn: return "specialWorkspaceIn"
        case .manualResize: return config.misc.animateManualResizes ? "windowsMove" : nil
        case .restore: return nil
        }
    }

    public static func plan(_ change: FrameChange, current: Rect?, monitor: Rect, config: Config, environment: MotionEnvironment,
                            window: WindowMotion, live: Bool) -> MotionPlan? {
        guard let name = leafName(for: change.reason, config: config),
              let timing = timing(name, config: config, environment: environment, noAnim: window.noAnim) else { return nil }
        let goal = change.frame
        let leafStyle = config.animations.leaf(name).style
        let from: Rect
        switch change.reason {
        case .open:
            let style = window.style ?? leafStyle
            if !live, !style.hasPrefix("slide"), let current { from = current } else { from = openStart(goal: goal, monitor: monitor, style: style) }
        case .workspaceIn(let leftward):
            from = slideIn(goal: goal, monitor: monitor, style: leafStyle, leftward: leftward, gap: Double(config.general.gapsWorkspaces))
        case .specialIn:
            from = slideIn(goal: goal, monitor: monitor, style: leafStyle, leftward: true, gap: Double(config.general.gapsWorkspaces))
        default:
            guard let current else { return nil }
            from = current
        }
        guard !from.isClose(to: goal, tolerance: 0.5) else { return nil }
        return MotionPlan(from: from, to: goal, timing: timing)
    }

    public static func planOut(_ park: ParkRequest, current: Rect, monitor: Rect, config: Config, environment: MotionEnvironment,
                               window: WindowMotion) -> MotionPlan? {
        guard let slide = park.slide else { return nil }
        let name: String
        let leftward: Bool
        switch slide {
        case .workspace(let l): name = "workspacesOut"; leftward = l
        case .special: name = "specialWorkspaceOut"; leftward = false
        }
        guard let timing = timing(name, config: config, environment: environment, noAnim: window.noAnim),
              let end = slideOut(current: current, monitor: monitor, style: config.animations.leaf(name).style, leftward: leftward) else { return nil }
        return MotionPlan(from: current, to: end, timing: timing)
    }

    public static func openStart(goal: Rect, monitor: Rect, style: String) -> Rect {
        let words = style.split(separator: " ").map(String.init)
        if words.first == "slide" {
            let side = words.count > 1 ? words[1] : nearestSide(goal, monitor)
            switch side {
            case "bottom": return Rect(x: goal.x, y: monitor.maxY, width: goal.width, height: goal.height)
            case "left": return Rect(x: goal.x - goal.width, y: goal.y, width: goal.width, height: goal.height)
            case "right": return Rect(x: goal.x + goal.width, y: goal.y, width: goal.width, height: goal.height)
            default: return Rect(x: goal.x, y: monitor.minY - goal.height, width: goal.width, height: goal.height)
            }
        }
        let percent = words.first == "popin" && words.count > 1 && words[1].hasSuffix("%") ? (finiteDouble(String(words[1].dropLast())) ?? 0) : 0
        let w = min(max(goal.width * percent / 100, 5), goal.width)
        let h = min(max(goal.height * percent / 100, 5), goal.height)
        return Rect(x: goal.center.x - w / 2, y: goal.center.y - h / 2, width: w, height: h)
    }

    static func nearestSide(_ goal: Rect, _ monitor: Rect) -> String {
        let c = goal.center
        let distances = [("bottom", monitor.maxY - c.y), ("left", c.x - monitor.minX), ("right", monitor.maxX - c.x), ("top", c.y - monitor.minY)]
        return distances.min { $0.1 < $1.1 }!.0
    }

    static func slideStyle(_ style: String) -> (kind: String, vertical: Bool, percent: Double) {
        let words = style.split(separator: " ").map(String.init)
        let kind = words.first ?? "slide"
        var vertical = kind.hasSuffix("vert")
        var percent = 100.0
        for w in words.dropFirst() {
            if w == "top" || w == "bottom" { vertical = true }
            if w == "left" || w == "right" { vertical = false }
            if w.hasSuffix("%"), let n = finiteDouble(String(w.dropLast())) { percent = n }
        }
        return (kind, vertical, percent)
    }

    public static func slideIn(goal: Rect, monitor: Rect, style: String, leftward: Bool, gap: Double = 0) -> Rect {
        let s = slideStyle(style)
        let percent = s.kind == "fade" ? 8 : s.percent
        let sign: Double = leftward ? 1 : -1
        if s.vertical {
            return Rect(x: goal.x, y: goal.y + sign * (monitor.height + gap) * percent / 100, width: goal.width, height: goal.height)
        }
        return Rect(x: goal.x + sign * (monitor.width + gap) * percent / 100, y: goal.y, width: goal.width, height: goal.height)
    }

    public static func slideOut(current: Rect, monitor: Rect, style: String, leftward: Bool) -> Rect? {
        let s = slideStyle(style)
        guard s.kind == "slide" || s.kind == "slidevert" else { return nil }
        if s.vertical {
            let y = leftward ? monitor.minY - current.height + 1 : monitor.maxY - 1
            return Rect(x: current.x, y: y, width: current.width, height: current.height)
        }
        let x = leftward ? monitor.minX - current.width + 1 : monitor.maxX - 1
        return Rect(x: x, y: current.y, width: current.width, height: current.height)
    }
}
