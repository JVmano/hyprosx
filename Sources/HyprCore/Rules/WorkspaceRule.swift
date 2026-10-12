import Foundation

public struct WorkspaceFacts: Equatable, Sendable {
    public var id: Int
    public var name: String
    public var isSpecial: Bool
    public var monitorName: String
    public var tiledCount: Int
    public var floatingCount: Int
    public var fullscreenMode: Int
    public init(id: Int, name: String, isSpecial: Bool, monitorName: String, tiledCount: Int, floatingCount: Int, fullscreenMode: Int) {
        self.id = id; self.name = name; self.isSpecial = isSpecial; self.monitorName = monitorName
        self.tiledCount = tiledCount; self.floatingCount = floatingCount; self.fullscreenMode = fullscreenMode
    }
}

public enum WorkspaceFilter: Equatable, Sendable {
    case idRange(Int, Int)
    case special(Bool)
    case named(Bool)
    case nameStarts(String)
    case nameEnds(String)
    case monitor(String)
    case windowCount(tiled: Bool, floating: Bool, min: Int, max: Int)
    case fullscreen(Int)
}

public enum WorkspaceRuleSelector: Equatable, Sendable {
    case id(Int)
    case name(String)
    case special(String?)
    case filters([WorkspaceFilter])
}

public struct WorkspaceRule: Equatable, Sendable {
    public var selector: WorkspaceRuleSelector
    public var monitor: String?
    public var isDefault: Bool?
    public var gapsIn: Edges?
    public var gapsOut: Edges?
    public var borderSize: Int?
    public var border: Bool?
    public var persistent: Bool?
    public var defaultName: String?
    public var layout: String?
    public var orientation: String?
    public var onCreatedEmpty: String?
    public var location: SourceLocation

    static let ignoredRules: Set<String> = ["shadow", "rounding", "decorate", "animations", "animation", "gapsworkspaces"]

    public static func parse(_ value: String, location: SourceLocation) -> (rule: WorkspaceRule?, diagnostics: [Diagnostic]) {
        let parts = WindowRuleParser.splitRuleParts(value)
        guard let first = parts.first, let selector = parseSelector(first) else {
            return (nil, [Diagnostic(location, "invalid workspace selector '\(parts.first ?? "")'")])
        }
        var rule = WorkspaceRule(selector: selector, location: location)
        var diagnostics: [Diagnostic] = []
        for part in parts.dropFirst() {
            guard let colon = part.firstIndex(of: ":") else { diagnostics.append(Diagnostic(location, "invalid workspace rule '\(part)'")); continue }
            let key = String(part[..<colon]).trimmingCharacters(in: .whitespaces)
            let v = String(part[part.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            func invalid() { diagnostics.append(Diagnostic(location, "invalid value '\(v)' for \(key)")) }
            switch key {
            case "monitor": rule.monitor = v
            case "default": if let b = ConfigValue.bool(v) { rule.isDefault = b } else { invalid() }
            case "gapsin": if let e = gaps(v) { rule.gapsIn = e } else { invalid() }
            case "gapsout": if let e = gaps(v) { rule.gapsOut = e } else { invalid() }
            case "bordersize":
                if let n = ConfigValue.int(v), (0...Int(Int32.max)).contains(n) { rule.borderSize = n } else { invalid() }
            case "border": if let b = ConfigValue.bool(v) { rule.border = b } else { invalid() }
            case "persistent": if let b = ConfigValue.bool(v) { rule.persistent = b } else { invalid() }
            case "defaultName": rule.defaultName = v
            case "layout": rule.layout = v
            case "layoutopt":
                if v.hasPrefix("orientation:") {
                    rule.orientation = String(v.dropFirst("orientation:".count))
                } else {
                    let name = v.split(separator: ":", maxSplits: 1).first.map(String.init) ?? v
                    diagnostics.append(Diagnostic(location, "unsupported workspace layoutopt '\(name)'", isWarning: true))
                }
            case "on-created-empty": rule.onCreatedEmpty = v
            default:
                if !ignoredRules.contains(key) { diagnostics.append(Diagnostic(location, "invalid workspace rule '\(key)'")) }
            }
        }
        return (rule, diagnostics)
    }

    init(selector: WorkspaceRuleSelector, location: SourceLocation) { self.selector = selector; self.location = location }

    static func gaps(_ v: String) -> Edges? {
        guard let e = ConfigValue.edges(v), [e.top, e.right, e.bottom, e.left].allSatisfy({ abs($0) <= Double(Int32.max) }) else { return nil }
        return e
    }

    static func intRange(_ s: Substring, allowSingle: Bool) -> (Int, Int)? {
        let p = s.split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 2 || (allowSingle && p.count == 1) else { return nil }
        let n = p.map { $0.allSatisfy { $0.isASCII && $0.isNumber } ? boundedInt($0) : nil }
        guard let lo = n[0], let hi = n[p.count - 1], lo <= hi else { return nil }
        return (lo, hi)
    }

    static func parseSelector(_ s: String) -> WorkspaceRuleSelector? {
        if let n = boundedInt(s) { return .id(n) }
        if s.hasPrefix("name:") { return .name(String(s.dropFirst(5))) }
        if s == "special" { return .special(nil) }
        if s.hasPrefix("special:") { return .special(String(s.dropFirst(8))) }
        guard s.contains("[") else { return nil }
        var filters: [WorkspaceFilter] = []
        var rest = Substring(s)
        while !rest.isEmpty {
            guard let open = rest.firstIndex(of: "["), let close = rest.firstIndex(of: "]"), open < close else { return nil }
            let kind = rest[rest.startIndex..<open]
            let body = String(rest[rest.index(after: open)..<close])
            guard let filter = parseFilter(String(kind), body) else { return nil }
            filters.append(filter)
            rest = rest[rest.index(after: close)...]
        }
        return .filters(filters)
    }

    static func parseFilter(_ kind: String, _ body: String) -> WorkspaceFilter? {
        switch kind {
        case "r": return intRange(Substring(body), allowSingle: false).map { .idRange($0.0, $0.1) }
        case "s": return ConfigValue.bool(body).map { .special($0) }
        case "n":
            if body.hasPrefix("s:") { return .nameStarts(String(body.dropFirst(2))) }
            if body.hasPrefix("e:") { return .nameEnds(String(body.dropFirst(2))) }
            return ConfigValue.bool(body).map { .named($0) }
        case "m": return body.isEmpty ? nil : .monitor(body)
        case "w":
            let flags = body.prefix(while: { "tfgvp".contains($0) })
            guard let (lo, hi) = intRange(body.dropFirst(flags.count), allowSingle: true) else { return nil }
            return .windowCount(tiled: flags.contains("t"), floating: flags.contains("f"), min: lo, max: hi)
        case "f": return boundedInt(body).flatMap { (-1...2).contains($0) ? .fullscreen($0) : nil }
        default: return nil
        }
    }

    public func matches(_ f: WorkspaceFacts, monitorMatches: (String) -> Bool) -> Bool {
        switch selector {
        case .id(let id): return f.id == id
        case .name(let n): return !f.isSpecial && f.name == n
        case .special(let n): return f.isSpecial && f.name == (n ?? "special")
        case .filters(let filters):
            return filters.allSatisfy { filter in
                switch filter {
                case .idRange(let a, let b): return f.id >= a && f.id <= b
                case .special(let b): return f.isSpecial == b
                case .named(let b): return (Int(f.name) == nil) == b
                case .nameStarts(let p): return f.name.hasPrefix(p)
                case .nameEnds(let p): return f.name.hasSuffix(p)
                case .monitor(let m): return monitorMatches(m)
                case .windowCount(let tiled, let floating, let lo, let hi):
                    let count = tiled && !floating ? f.tiledCount : (floating && !tiled ? f.floatingCount : f.tiledCount + f.floatingCount)
                    return count >= lo && count <= hi
                case .fullscreen(let mode): return f.fullscreenMode == mode
                }
            }
        }
    }
}
