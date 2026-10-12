import Foundation

public enum Direction: String, Codable, Sendable, CaseIterable {
    case left, right, up, down
    public static func parse(_ s: String) -> Direction? {
        switch s.trimmingCharacters(in: .whitespaces).lowercased() {
        case "l", "left": return .left
        case "r", "right": return .right
        case "u", "t", "up", "top": return .up
        case "d", "b", "down", "bottom": return .down
        default: return nil
        }
    }
}

public enum WorkspaceSelector: Equatable, Hashable, Sendable {
    case id(Int)
    case relative(Int)
    case onMonitor(Int, includeEmpty: Bool)
    case onMonitorAbsolute(Int, includeEmpty: Bool)
    case existing(Int)
    case existingAbsolute(Int)
    case name(String)
    case previous
    case previousPerMonitor
    case empty(currentMonitorOnly: Bool, next: Bool)
    case special(String?)

    public static func parse(_ s: String) -> WorkspaceSelector? {
        let v = s.trimmingCharacters(in: .whitespaces)
        if let n = boundedInt(v), !v.hasPrefix("+"), !v.hasPrefix("-") { return .id(n) }
        if (v.hasPrefix("+") || v.hasPrefix("-")), let n = boundedInt(v) { return .relative(n) }
        if v.hasPrefix("name:") { return .name(String(v.dropFirst(5))) }
        if v == "special" { return .special(nil) }
        if v.hasPrefix("special:") { return .special(String(v.dropFirst(8))) }
        switch v {
        case "previous": return .previous
        case "previous_per_monitor": return .previousPerMonitor
        case "empty": return .empty(currentMonitorOnly: false, next: false)
        case "emptym": return .empty(currentMonitorOnly: true, next: false)
        case "emptyn": return .empty(currentMonitorOnly: false, next: true)
        case "emptynm", "emptymn": return .empty(currentMonitorOnly: true, next: true)
        default: break
        }
        guard v.count >= 3, let kind = v.first else { return nil }
        let sign = v[v.index(after: v.startIndex)]
        let digits = v.dropFirst(2)
        guard let n = boundedInt(digits), n >= 0 else { return nil }
        switch (kind, sign) {
        case ("m", "+"): return .onMonitor(n, includeEmpty: false)
        case ("m", "-"): return .onMonitor(-n, includeEmpty: false)
        case ("r", "+"): return .onMonitor(n, includeEmpty: true)
        case ("r", "-"): return .onMonitor(-n, includeEmpty: true)
        case ("m", "~"): return .onMonitorAbsolute(n, includeEmpty: false)
        case ("r", "~"): return .onMonitorAbsolute(n, includeEmpty: true)
        case ("e", "+"): return .existing(n)
        case ("e", "-"): return .existing(-n)
        case ("e", "~"): return .existingAbsolute(n)
        default: return nil
        }
    }
}

public enum WindowSelector: Equatable, Hashable, Sendable {
    case active
    case classRegex(String)
    case initialClass(String)
    case title(String)
    case initialTitle(String)
    case pid(Int32)
    case address(UInt32)
    case floating
    case tiled
    case tag(String)

    public static func parse(_ s: String) -> WindowSelector? {
        let v = s.trimmingCharacters(in: .whitespaces)
        switch v {
        case "", "active", "activewindow": return .active
        case "floating": return .floating
        case "tiled": return .tiled
        default: break
        }
        func after(_ p: String) -> String? { v.hasPrefix(p) ? String(v.dropFirst(p.count)) : nil }
        if let x = after("class:") { return .classRegex(x) }
        if let x = after("initialclass:") { return .initialClass(x) }
        if let x = after("title:") { return .title(x) }
        if let x = after("initialtitle:") { return .initialTitle(x) }
        if let x = after("tag:") { return .tag(x) }
        if let x = after("pid:") { return Int32(x).map { .pid($0) } }
        if let x = after("address:") {
            let hex = x.lowercased().hasPrefix("0x") ? String(x.dropFirst(2)) : x
            return UInt32(hex, radix: 16).map { .address($0) }
        }
        return .classRegex(v)
    }
}

public enum MonitorSelector: Equatable, Hashable, Sendable {
    case direction(Direction)
    case id(Int)
    case name(String)
    case current
    case relative(Int)

    public static func parse(_ s: String) -> MonitorSelector? {
        let v = s.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { return nil }
        if let d = Direction.parse(v) { return .direction(d) }
        if v == "current" { return .current }
        let unsigned = v.hasPrefix("+") || v.hasPrefix("-") ? v.dropFirst() : Substring(v)
        if !unsigned.isEmpty, unsigned.allSatisfy({ $0.isASCII && $0.isNumber }) {
            guard let n = boundedInt(v) else { return nil }
            return unsigned.count < v.count ? .relative(n) : .id(n)
        }
        return .name(v)
    }
}

func boundedInt<S: StringProtocol>(_ s: S) -> Int? {
    Int(s).flatMap { $0.magnitude <= UInt(Int32.max) ? $0 : nil }
}

public enum Measure: Equatable, Hashable, Sendable {
    case pixels(Double)
    case percent(Double)
    static func parse(_ s: String) -> Measure? {
        if s.hasSuffix("%") { return finiteDouble(s.dropLast()).map { .percent($0) } }
        return finiteDouble(s).map { .pixels($0) }
    }
}

public enum ResizeParam: Equatable, Hashable, Sendable {
    case relative(Measure, Measure)
    case exact(Measure, Measure)
    public static func parse(_ s: String) -> ResizeParam? {
        var parts = s.split(separator: " ").map(String.init)
        let exact = parts.first == "exact"
        if exact { parts.removeFirst() }
        guard parts.count == 2, let a = Measure.parse(parts[0]), let b = Measure.parse(parts[1]) else { return nil }
        return exact ? .exact(a, b) : .relative(a, b)
    }
}

public enum FloatValue: Equatable, Hashable, Sendable {
    case relative(Double)
    case exact(Double)
    public static func parse(_ s: String) -> FloatValue? {
        let parts = s.split(separator: " ").map(String.init)
        if parts.count == 2, parts[0] == "exact" { return finiteDouble(parts[1]).map { .exact($0) } }
        if parts.count == 1 { return finiteDouble(parts[0]).map { .relative($0) } }
        return nil
    }
}

public enum ToggleAction: String, Equatable, Sendable { case toggle, set, unset }
public enum MoveTarget: Equatable, Sendable { case direction(Direction), monitor(MonitorSelector) }
public enum SwapTarget: Equatable, Sendable { case direction(Direction), window(WindowSelector) }

public struct CycleOptions: Equatable, Sendable {
    public var previous = false
    public var tiledOnly = false
    public var floatingOnly = false
    public var visible = false
    public var history = false
    public init() {}
}
