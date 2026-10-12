import Foundation

public struct RuleRegex: Equatable, @unchecked Sendable {
    public let pattern: String
    public let negative: Bool
    private let regex: NSRegularExpression

    public init?(_ raw: String) {
        var p = raw.trimmingCharacters(in: .whitespaces)
        let neg = p.hasPrefix("negative:")
        if neg { p = String(p.dropFirst("negative:".count)) }
        guard p.isEmpty || (try? NSRegularExpression(pattern: p)) != nil, let r = try? NSRegularExpression(pattern: "^(?:\(p))$") else { return nil }
        pattern = p; negative = neg; regex = r
    }

    public func matches(_ s: String) -> Bool { matchesAny([s]) }

    public func matchesAny(_ values: [String]) -> Bool {
        values.contains { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil } != negative
    }

    public static func == (a: RuleRegex, b: RuleRegex) -> Bool { a.pattern == b.pattern && a.negative == b.negative }
}

public enum RuleMatcher: Equatable, Sendable {
    case cls(RuleRegex), title(RuleRegex), initialClass(RuleRegex), initialTitle(RuleRegex)
    case float(Bool), fullscreen(Bool), pin(Bool), focus(Bool), modal(Bool)
    case workspace(String)
    case never
}

public struct ExprPair: Equatable, Sendable {
    public var x: String
    public var y: String
    public init(x: String, y: String) { self.x = x; self.y = y }
}

public enum RuleEffect: Equatable, Sendable {
    case float(Bool), tile(Bool), fullscreen(Bool), maximize(Bool), center(Bool), pseudo(Bool), pin(Bool)
    case noInitialFocus(Bool), ignore(Bool), noAnim(Bool), dimAround(Bool)
    case move(ExprPair), size(ExprPair), monitor(String), workspace(String, silent: Bool), workspaceUnset
    case borderColor(active: Gradient, inactive: Gradient?), borderSize(Int), minSize(Size), maxSize(Size), animation(String)
    case accepted(String)

    var isStatic: Bool {
        switch self {
        case .float, .tile, .fullscreen, .maximize, .center, .pseudo, .pin, .noInitialFocus, .ignore,
             .move, .size, .monitor, .workspace, .workspaceUnset: return true
        default: return false
        }
    }
}

public struct WindowRule: Equatable, Sendable {
    public var name: String?
    public var matchers: [RuleMatcher]
    public var effects: [RuleEffect]
    public var location: SourceLocation
    public init(name: String?, matchers: [RuleMatcher], effects: [RuleEffect], location: SourceLocation) {
        self.name = name; self.matchers = matchers; self.effects = effects; self.location = location
    }
}

public enum WindowRuleParser {
    static let legacyFields: [String: String] = [
        "class": "class", "title": "title", "initialClass": "initial_class", "initialTitle": "initial_title",
        "tag": "tag", "xdgtag": "xdg_tag", "content": "content", "xwayland": "xwayland", "floating": "float",
        "fullscreen": "fullscreen", "pinned": "pin", "focus": "focus", "group": "group",
        "fullscreenstate": "fullscreen_state_internal", "workspace": "workspace", "onworkspace": "workspace",
    ]
    static let legacyEffects: [String: String] = [
        "noinitialfocus": "no_initial_focus", "bordercolor": "border_color", "bordersize": "border_size", "noanim": "no_anim",
        "maxsize": "max_size", "minsize": "min_size", "dimaround": "dim_around", "suppressevent": "suppress_event",
        "stayfocused": "stay_focused", "nofocus": "no_focus", "nomaxsize": "no_max_size", "persistentsize": "persistent_size",
        "idleinhibit": "idle_inhibit", "noblur": "no_blur", "noshadow": "no_shadow", "nodim": "no_dim", "forcergbx": "force_rgbx",
        "keepaspectratio": "keep_aspect_ratio", "nearestneighbor": "nearest_neighbor", "focusonactivate": "focus_on_activate",
        "allowsinput": "allows_input", "roundingpower": "rounding_power", "scrollmouse": "scroll_mouse",
        "scrolltouchpad": "scroll_touchpad", "noscreenshare": "no_screen_share", "novrr": "no_vrr",
        "syncfullscreen": "sync_fullscreen", "renderunfocused": "render_unfocused", "noclosefor": "no_close_for",
        "fullscreenstate": "fullscreen_state", "noshortcutsinhibit": "no_shortcuts_inhibit", "nofollowmouse": "no_follow_mouse",
    ]
    static let acceptedEffects: Set<String> = [
        "fullscreen_state", "group", "suppress_event", "content", "no_close_for", "scrolling_width", "persistent_size",
        "no_max_size", "stay_focused", "idle_inhibit", "opacity", "tag", "rounding", "rounding_power", "allows_input",
        "decorate", "focus_on_activate", "keep_aspect_ratio", "nearest_neighbor", "no_blur", "no_dim", "no_focus",
        "no_follow_mouse", "no_shadow", "no_shortcuts_inhibit", "no_screen_share", "no_vrr", "opaque", "force_rgbx",
        "sync_fullscreen", "immediate", "xray", "render_unfocused", "scroll_mouse", "scroll_touchpad", "confine_pointer",
        "no_auto_hdr", "no_glow", "no_wobble", "no_xdg_drags", "tonemap", "norounding", "unset",
    ]
    static let boolEffects: [String: (Bool) -> RuleEffect] = [
        "float": RuleEffect.float, "tile": RuleEffect.tile, "fullscreen": RuleEffect.fullscreen, "maximize": RuleEffect.maximize,
        "center": RuleEffect.center, "pseudo": RuleEffect.pseudo, "pin": RuleEffect.pin, "no_initial_focus": RuleEffect.noInitialFocus,
        "ignore": RuleEffect.ignore, "no_anim": RuleEffect.noAnim, "dim_around": RuleEffect.dimAround,
    ]

    private struct Builder {
        var name: String?
        var matchers: [RuleMatcher] = []
        var effects: [RuleEffect] = []
        var props: Set<String> = []
        var diagnostics: [Diagnostic] = []
        let location: SourceLocation

        mutating func prop(_ rawName: String, _ value: String) {
            let name = rawName.trimmingCharacters(in: .whitespaces)
            let v = value.trimmingCharacters(in: .whitespaces)
            guard !props.contains(name) else { diagnostics.append(Diagnostic(location, "duplicate rule prop '\(name)'")); return }
            props.insert(name)
            func regex(_ make: (RuleRegex) -> RuleMatcher) {
                if let r = RuleRegex(v) { matchers.append(make(r)) } else { diagnostics.append(Diagnostic(location, "invalid regex '\(v)'")) }
            }
            func flag(_ make: (Bool) -> RuleMatcher) {
                if let b = ConfigValue.bool(v) { matchers.append(make(b)) } else { diagnostics.append(Diagnostic(location, "invalid value '\(v)' for \(name)")) }
            }
            switch name {
            case "class": regex(RuleMatcher.cls)
            case "title": regex(RuleMatcher.title)
            case "initial_class": regex(RuleMatcher.initialClass)
            case "initial_title": regex(RuleMatcher.initialTitle)
            case "float": flag(RuleMatcher.float)
            case "fullscreen": flag(RuleMatcher.fullscreen)
            case "pin": flag(RuleMatcher.pin)
            case "focus": flag(RuleMatcher.focus)
            case "modal": flag(RuleMatcher.modal)
            case "workspace": matchers.append(.workspace(v))
            case "xwayland", "group":
                if let b = ConfigValue.bool(v) { if b { matchers.append(.never) } }
                else { diagnostics.append(Diagnostic(location, "invalid value '\(v)' for \(name)")) }
            case "tag", "content", "xdg_tag", "fullscreen_state_client", "fullscreen_state_internal": matchers.append(.never)
            default: props.remove(name); diagnostics.append(Diagnostic(location, "invalid rule prop '\(name)'"))
            }
        }

        mutating func effect(_ rawName: String, _ rawArgs: String) {
            var name = rawName.trimmingCharacters(in: .whitespaces)
            let args = rawArgs.trimmingCharacters(in: .whitespaces)
            if name == "noborder" { effects.append(.borderSize(0)); return }
            name = WindowRuleParser.legacyEffects[name] ?? name
            let tokens = args.split(separator: " ").map(String.init)
            if let make = WindowRuleParser.boolEffects[name] {
                if args.isEmpty { effects.append(make(true)); return }
                if let b = ConfigValue.bool(args) { effects.append(make(b)) } else { diagnostics.append(Diagnostic(location, "invalid value '\(args)' for \(name)")) }
                return
            }
            switch name {
            case "move", "size":
                guard tokens.count == 2 else { diagnostics.append(Diagnostic(location, "invalid \(name) '\(args)'")); return }
                let pair = ExprPair(x: tokens[0], y: tokens[1])
                effects.append(name == "move" ? .move(pair) : .size(pair))
            case "monitor":
                guard !args.isEmpty else { diagnostics.append(Diagnostic(location, "missing monitor")); return }
                effects.append(.monitor(args))
            case "workspace":
                if args == "unset" { effects.append(.workspaceUnset); return }
                var t = tokens
                let silent = t.last == "silent"
                if silent { t.removeLast() }
                guard !t.isEmpty else { diagnostics.append(Diagnostic(location, "missing workspace")); return }
                effects.append(.workspace(t.joined(separator: " "), silent: silent))
            case "border_color":
                guard let (active, inactive) = WindowRuleParser.borderColors(tokens) else {
                    diagnostics.append(Diagnostic(location, "invalid border_color '\(args)'")); return
                }
                effects.append(.borderColor(active: active, inactive: inactive))
            case "border_size":
                guard let n = boundedInt(args), n >= 0 else { diagnostics.append(Diagnostic(location, "invalid border_size '\(args)'")); return }
                effects.append(.borderSize(n))
            case "min_size", "max_size":
                guard let (w, h) = ConfigValue.vec2(args), (0...Double(Int32.max)).contains(w), (0...Double(Int32.max)).contains(h) else { diagnostics.append(Diagnostic(location, "invalid \(name) '\(args)'")); return }
                effects.append(name == "min_size" ? .minSize(Size(width: w, height: h)) : .maxSize(Size(width: w, height: h)))
            case "animation":
                effects.append(.animation(args))
            default:
                if WindowRuleParser.acceptedEffects.contains(name) { effects.append(.accepted(name)) }
                else { diagnostics.append(Diagnostic(location, "invalid rule effect '\(name)'")) }
            }
        }

        func finish() -> (rule: WindowRule?, diagnostics: [Diagnostic]) {
            if !diagnostics.isEmpty { return (nil, diagnostics) }
            if props.isEmpty { return (nil, [Diagnostic(location, "rule needs at least one match prop")]) }
            return (WindowRule(name: name, matchers: matchers, effects: effects, location: location), [])
        }
    }

    static func borderColors(_ tokens: [String]) -> (Gradient, Gradient?)? {
        if !tokens.contains(where: { $0.hasSuffix("deg") }) {
            let colors = tokens.compactMap(ConfigValue.color)
            guard colors.count == tokens.count, (1...2).contains(colors.count) else { return nil }
            return (Gradient(colors[0]), colors.count == 2 ? Gradient(colors[1]) : nil)
        }
        guard let split = tokens.firstIndex(where: { $0.hasSuffix("deg") }) else { return nil }
        guard let active = ConfigValue.gradient(tokens[...split].joined(separator: " ")) else { return nil }
        let rest = tokens[(split + 1)...]
        if rest.isEmpty { return (active, nil) }
        guard let inactive = ConfigValue.gradient(rest.joined(separator: " ")) else { return nil }
        return (active, inactive)
    }

    private static func splitFirstSpace(_ s: String) -> (String, String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let i = t.firstIndex(of: " ") else { return (t, "") }
        return (String(t[..<i]), String(t[t.index(after: i)...]))
    }

    public static func parse(keyword: String, value: String, location: SourceLocation) -> (rule: WindowRule?, diagnostics: [Diagnostic]) {
        var b = Builder(location: location)
        let parts = value.split(separator: ",", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
        if keyword == "windowrule" && parts.contains(where: { $0.hasPrefix("match:") }) {
            for part in parts {
                if part.hasPrefix("match:") {
                    let (p, v) = splitFirstSpace(String(part.dropFirst(6)))
                    b.prop(p, v)
                } else {
                    let (e, a) = splitFirstSpace(part)
                    b.effect(e, a)
                }
            }
            return b.finish()
        }
        func field(_ part: String) -> (String, String)? {
            guard let colon = part.firstIndex(of: ":") else { return nil }
            let key = String(part[..<colon])
            guard let mapped = legacyFields[key] else { return nil }
            return (mapped, String(part[part.index(after: colon)...]))
        }
        let fields = parts.compactMap(field)
        if fields.isEmpty && parts.count == 2 {
            let (e, a) = splitFirstSpace(parts[0])
            b.effect(e, a)
            b.prop("class", parts[1])
            return b.finish()
        }
        for part in parts {
            if let (p, v) = field(part) { b.prop(p, v) } else { let (e, a) = splitFirstSpace(part); b.effect(e, a) }
        }
        return b.finish()
    }

    public static func parseBlock(_ fields: [(key: String, value: String)], location: SourceLocation) -> (rule: WindowRule?, diagnostics: [Diagnostic]) {
        var b = Builder(location: location)
        for (key, value) in fields {
            if key == "name" { b.name = value; continue }
            if key == "enable" { continue }
            if key.hasPrefix("match:") { b.prop(String(key.dropFirst(6)), value) } else { b.effect(key, value) }
        }
        return b.finish()
    }
}
