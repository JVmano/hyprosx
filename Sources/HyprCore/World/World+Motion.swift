import Foundation

public struct WindowMotion: Equatable, Sendable {
    public var noAnim: Bool
    public var style: String?
    public init(noAnim: Bool = false, style: String? = nil) { self.noAnim = noAnim; self.style = style }
}

extension World {
    func windowRules(forPID pid: Int32) -> [WindowRule] {
        var rules = config.windowRules
        for part in (pidRules[pid] ?? "").split(separator: ";") {
            let text = part.trimmingCharacters(in: .whitespaces) + ", match:class .*"
            if let rule = WindowRuleParser.parse(keyword: "windowrule", value: text, location: SourceLocation(file: "exec", line: 0)).rule {
                rules.append(rule)
            }
        }
        return rules
    }

    func dynamicOutcome(for w: ManagedWindow) -> DynamicRuleOutcome {
        RuleEngine.dynamicOutcome(windowRules(forPID: w.pid), facts(for: w))
    }

    public func motion(for id: WindowID) -> WindowMotion {
        guard let w = windows[id] else { return WindowMotion() }
        let rules = dynamicOutcome(for: w)
        let prop = w.props["no_anim"].flatMap { ConfigValue.bool($0) }
        return WindowMotion(noAnim: prop ?? rules.noAnim, style: rules.animationStyle)
    }

    public func monitorFrame(of id: WindowID) -> Rect? {
        guard let w = windows[id], let ws = workspaces[w.workspace] else { return nil }
        return monitor(ws.monitor)?.frame
    }

    func slidesLeft(from old: Int?, to target: Int, on mon: Int) -> Bool {
        guard let old else { return false }
        if config.animationsOptions.workspaceWraparound {
            let ids = workspaces.values.filter { !$0.isSpecial && $0.monitor == mon && $0.id > 0 }.map(\.id) + [target]
            if let lo = ids.min(), let hi = ids.max(), lo != hi {
                if old == hi && target == lo { return true }
                if old == lo && target == hi { return false }
            }
        }
        return target > old
    }
}
