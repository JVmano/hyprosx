import Foundation

func finiteDouble<S: StringProtocol>(_ s: S) -> Double? {
    Double(s).flatMap { $0.isFinite ? $0 : nil }
}

public struct Color: Equatable, Hashable, Codable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(r: Double, g: Double, b: Double, a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }
}

public struct Gradient: Equatable, Hashable, Codable, Sendable {
    public var colors: [Color]
    public var angleDegrees: Double
    public init(colors: [Color], angleDegrees: Double = 0) { self.colors = colors; self.angleDegrees = angleDegrees }
    public init(_ color: Color) { self.init(colors: [color]) }
    public var isFullyTransparent: Bool { colors.allSatisfy { $0.a == 0 } }
}

public enum ConfigValue {
    public static func bool(_ s: String) -> Bool? {
        let v = s.trimmingCharacters(in: .whitespaces).lowercased()
        for t in ["true", "yes", "on"] where v.hasPrefix(t) { return true }
        for f in ["false", "off", "no"] where v.hasPrefix(f) { return false }
        if let n = Int(v) { return n != 0 }
        return nil
    }

    public static func int(_ s: String) -> Int? {
        let v = s.trimmingCharacters(in: .whitespaces)
        if v.lowercased().hasPrefix("0x") { return Int(v.dropFirst(2), radix: 16) }
        if let n = Int(v) { return n }
        if let d = Double(v) { return Int(exactly: d) }
        return bool(v).map { $0 ? 1 : 0 }
    }

    private static func finiteList(_ parts: [Substring]) -> [Double]? {
        let numbers = parts.compactMap { finiteDouble($0) }
        return numbers.count == parts.count ? numbers : nil
    }

    public static func float(_ s: String) -> Double? {
        finiteDouble(s.trimmingCharacters(in: .whitespaces))
    }

    public static func color(_ s: String) -> Color? {
        let v = s.trimmingCharacters(in: .whitespaces)
        if v.lowercased().hasPrefix("0x"), let n = UInt32(v.dropFirst(2), radix: 16) {
            return Color(r: Double((n >> 16) & 0xff) / 255, g: Double((n >> 8) & 0xff) / 255, b: Double(n & 0xff) / 255, a: Double(n >> 24) / 255)
        }
        for prefix in ["rgba(", "rgb("] where v.hasPrefix(prefix) && v.hasSuffix(")") {
            let inner = v.dropFirst(prefix.count).dropLast().replacingOccurrences(of: " ", with: "")
            if inner.contains(",") {
                guard let parts = finiteList(inner.split(separator: ",", omittingEmptySubsequences: false)),
                      parts.count == (prefix == "rgba(" ? 4 : 3),
                      parts[0...2].allSatisfy({ (0...255).contains($0) }) else { return nil }
                let alpha = prefix == "rgba(" ? parts[3] : 1
                guard (0...1).contains(alpha) else { return nil }
                return Color(r: parts[0] / 255, g: parts[1] / 255, b: parts[2] / 255, a: alpha)
            }
            guard let n = UInt32(inner, radix: 16) else { return nil }
            if prefix == "rgba(" && inner.count == 8 {
                return Color(r: Double(n >> 24) / 255, g: Double((n >> 16) & 0xff) / 255, b: Double((n >> 8) & 0xff) / 255, a: Double(n & 0xff) / 255)
            }
            if prefix == "rgb(" && inner.count == 6 {
                return Color(r: Double(n >> 16) / 255, g: Double((n >> 8) & 0xff) / 255, b: Double(n & 0xff) / 255, a: 1)
            }
            return nil
        }
        return nil
    }

    public static func gradient(_ s: String) -> Gradient? {
        var colors: [Color] = []
        var angle = 0.0
        var token = ""
        var depth = 0
        var tokens: [String] = []
        for ch in s {
            if ch == "(" { depth += 1 }
            if ch == ")" { depth -= 1 }
            if ch == " " && depth == 0 { if !token.isEmpty { tokens.append(token) }; token = ""; continue }
            token.append(ch)
        }
        if !token.isEmpty { tokens.append(token) }
        for t in tokens {
            if t.hasSuffix("deg"), let d = finiteDouble(t.dropLast(3)) { angle = d; continue }
            guard let c = color(t) else { return nil }
            colors.append(c)
        }
        return colors.isEmpty ? nil : Gradient(colors: colors, angleDegrees: angle)
    }

    public static func vec2(_ s: String) -> (Double, Double)? {
        guard let parts = finiteList(s.split(whereSeparator: { $0 == " " || $0 == "," })), parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    public static func edges(_ s: String) -> Edges? {
        guard let parts = finiteList(s.split(whereSeparator: { $0 == " " || $0 == "," })), !parts.isEmpty, parts.count <= 4 else { return nil }
        return Edges(css: parts)
    }
}
