import Foundation

public struct WindowFacts: Equatable, Sendable {
    public var bundleID: String
    public var appName: String
    public var title: String
    public var initialTitle: String
    public var isFloating: Bool
    public var isFullscreen: Bool
    public var isPinned: Bool
    public var isFocused: Bool
    public var isModal: Bool
    public var workspaceID: Int?
    public var workspaceName: String?
    public var monitorSize: Size
    public var windowFrame: Rect
    public var cursor: Point
    public init(bundleID: String, appName: String, title: String, initialTitle: String, isFloating: Bool, isFullscreen: Bool,
                isPinned: Bool, isFocused: Bool, isModal: Bool, workspaceID: Int?, workspaceName: String?,
                monitorSize: Size, windowFrame: Rect, cursor: Point) {
        self.bundleID = bundleID; self.appName = appName; self.title = title; self.initialTitle = initialTitle
        self.isFloating = isFloating; self.isFullscreen = isFullscreen; self.isPinned = isPinned; self.isFocused = isFocused
        self.isModal = isModal; self.workspaceID = workspaceID; self.workspaceName = workspaceName
        self.monitorSize = monitorSize; self.windowFrame = windowFrame; self.cursor = cursor
    }
}

public struct WorkspaceTarget: Equatable, Sendable {
    public var selector: String
    public var silent: Bool
    public init(selector: String, silent: Bool) { self.selector = selector; self.silent = silent }
}

public struct StaticRuleOutcome: Equatable, Sendable {
    public var floating: Bool?
    public var fullscreenMode: Int?
    public var move: ExprPair?
    public var size: ExprPair?
    public var center = false
    public var pseudo = false
    public var pin = false
    public var noInitialFocus = false
    public var ignore = false
    public var monitor: String?
    public var workspace: WorkspaceTarget?
    public var matched: [SourceLocation] = []
    public init() {}
}

public struct DynamicRuleOutcome: Equatable, Sendable {
    public var activeBorder: Gradient?
    public var inactiveBorder: Gradient?
    public var borderSize: Int?
    public var noAnim = false
    public var minSize: Size?
    public var maxSize: Size?
    public var animationStyle: String?
    public var dimAround = false
    public init() {}
}

public enum RuleEngine {
    public static func ordered(_ rules: [WindowRule]) -> [WindowRule] {
        rules.filter { $0.name != nil } + rules.filter { $0.name == nil }
    }

    public static func matches(_ rule: WindowRule, _ f: WindowFacts) -> Bool {
        rule.matchers.allSatisfy { m in
            switch m {
            case .cls(let r), .initialClass(let r): return r.matchesAny(f.bundleID.isEmpty ? [f.appName] : [f.bundleID, f.appName])
            case .title(let r): return r.matches(f.title)
            case .initialTitle(let r): return r.matches(f.initialTitle)
            case .float(let b): return f.isFloating == b
            case .fullscreen(let b): return f.isFullscreen == b
            case .pin(let b): return f.isPinned == b
            case .focus(let b): return f.isFocused == b
            case .modal(let b): return f.isModal == b
            case .workspace(let w):
                if w.hasPrefix("name:") { return f.workspaceName == String(w.dropFirst(5)) }
                if let id = Int(w) { return f.workspaceID == id }
                return false
            case .never: return false
            }
        }
    }

    public static func staticOutcome(_ rules: [WindowRule], _ f: WindowFacts) -> StaticRuleOutcome {
        var o = StaticRuleOutcome()
        for rule in ordered(rules) where matches(rule, f) {
            if rule.effects.contains(where: \.isStatic) { o.matched.append(rule.location) }
            for e in rule.effects {
                switch e {
                case .float(let b): o.floating = b ? true : nil
                case .tile(let b): o.floating = b ? false : nil
                case .fullscreen(let b): o.fullscreenMode = b ? 0 : nil
                case .maximize(let b): o.fullscreenMode = b ? 1 : nil
                case .center(let b): o.center = b
                case .pseudo(let b): o.pseudo = b
                case .pin(let b): o.pin = b
                case .noInitialFocus(let b): o.noInitialFocus = b
                case .ignore(let b): o.ignore = b
                case .move(let p): o.move = p
                case .size(let p): o.size = p
                case .monitor(let m): o.monitor = m
                case .workspace(let w, let silent): o.workspace = WorkspaceTarget(selector: w, silent: silent)
                case .workspaceUnset: o.workspace = nil
                default: break
                }
            }
        }
        return o
    }

    public static func dynamicOutcome(_ rules: [WindowRule], _ f: WindowFacts) -> DynamicRuleOutcome {
        var o = DynamicRuleOutcome()
        for rule in ordered(rules) where matches(rule, f) {
            for e in rule.effects {
                switch e {
                case .borderColor(let a, let i): o.activeBorder = a; if let i { o.inactiveBorder = i }
                case .borderSize(let n): o.borderSize = n
                case .noAnim(let b): o.noAnim = b
                case .minSize(let s): o.minSize = s
                case .maxSize(let s): o.maxSize = s
                case .animation(let s): o.animationStyle = s
                case .dimAround(let b): o.dimAround = b
                default: break
                }
            }
        }
        return o
    }

    static func variables(_ f: WindowFacts) -> [String: Double] {
        ["monitor_w": f.monitorSize.width, "monitor_h": f.monitorSize.height, "window_x": f.windowFrame.x, "window_y": f.windowFrame.y,
         "window_w": f.windowFrame.width, "window_h": f.windowFrame.height, "cursor_x": f.cursor.x, "cursor_y": f.cursor.y]
    }

    public static func resolveMove(_ p: ExprPair, _ f: WindowFacts) -> Point? {
        let v = variables(f)
        guard let x = evaluate(p.x, axisLength: f.monitorSize.width, variables: v),
              let y = evaluate(p.y, axisLength: f.monitorSize.height, variables: v) else { return nil }
        return Point(x: x, y: y)
    }

    public static func resolveSize(_ p: ExprPair, _ f: WindowFacts) -> Size? {
        let v = variables(f)
        guard let w = evaluate(p.x, axisLength: f.monitorSize.width, variables: v),
              let h = evaluate(p.y, axisLength: f.monitorSize.height, variables: v) else { return nil }
        return Size(width: w, height: h)
    }

    public static func evaluate(_ expr: String, axisLength: Double, variables: [String: Double]) -> Double? {
        let e = expr.trimmingCharacters(in: .whitespaces)
        if e.hasSuffix("%"), let n = finiteDouble(e.dropLast()) { return finite(n / 100 * axisLength) }
        var p = ExpressionParser(chars: Array(e.replacingOccurrences(of: " ", with: "")), variables: variables)
        guard let v = p.expression(), p.index == p.chars.count else { return nil }
        return finite(v)
    }

    private static func finite(_ v: Double) -> Double? {
        v.isFinite ? v : nil
    }
}

private struct ExpressionParser {
    let chars: [Character]
    let variables: [String: Double]
    var index = 0
    var depth = 0

    init(chars: [Character], variables: [String: Double]) { self.chars = chars; self.variables = variables }

    mutating func expression() -> Double? {
        guard var value = term() else { return nil }
        while index < chars.count, chars[index] == "+" || chars[index] == "-" {
            let op = chars[index]; index += 1
            guard let rhs = term() else { return nil }
            value = op == "+" ? value + rhs : value - rhs
        }
        return value
    }

    mutating func term() -> Double? {
        guard var value = factor() else { return nil }
        while index < chars.count, chars[index] == "*" || chars[index] == "/" {
            let op = chars[index]; index += 1
            guard let rhs = factor() else { return nil }
            if op == "/" && rhs == 0 { return nil }
            value = op == "*" ? value * rhs : value / rhs
        }
        return value
    }

    mutating func factor() -> Double? {
        depth += 1
        defer { depth -= 1 }
        guard index < chars.count, depth <= 64 else { return nil }
        if chars[index] == "-" { index += 1; return factor().map { -$0 } }
        if chars[index] == "(" {
            index += 1
            guard let v = expression(), index < chars.count, chars[index] == ")" else { return nil }
            index += 1
            return v
        }
        let start = index
        if chars[index].isNumber || chars[index] == "." {
            while index < chars.count, chars[index].isNumber || chars[index] == "." { index += 1 }
            return finiteDouble(String(chars[start..<index]))
        }
        while index < chars.count, chars[index].isLetter || chars[index] == "_" { index += 1 }
        guard index > start else { return nil }
        return variables[String(chars[start..<index])]
    }
}
