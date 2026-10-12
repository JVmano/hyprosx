import Foundation

public struct AnimationLeaf: Equatable, Sendable {
    public var enabled: Bool
    public var speed: Double
    public var curve: String
    public var style: String
    public init(enabled: Bool, speed: Double, curve: String, style: String) {
        self.enabled = enabled; self.speed = speed; self.curve = curve; self.style = style
    }
    public var durationMs: Double { speed * 100 }
}

public struct AnimationTree: Equatable, Sendable {
    public static let parents: [String: String] = [
        "windows": "global", "windowsIn": "windows", "windowsOut": "windows", "windowsMove": "windows",
        "layers": "global", "layersIn": "layers", "layersOut": "layers",
        "fade": "global", "fadeIn": "fade", "fadeOut": "fade", "fadeSwitch": "fade", "fadeShadow": "fade", "fadeGlow": "fade",
        "fadeDim": "fade", "fadeLayers": "fade", "fadeLayersIn": "fadeLayers", "fadeLayersOut": "fadeLayers",
        "fadePopups": "fade", "fadePopupsIn": "fadePopups", "fadePopupsOut": "fadePopups", "fadeDpms": "fade",
        "border": "global", "borderangle": "global", "shadowangle": "global", "glowangle": "global",
        "zoomFactor": "global", "monitorAdded": "global",
        "workspaces": "global", "workspacesIn": "workspaces", "workspacesOut": "workspaces",
        "specialWorkspace": "workspaces", "specialWorkspaceIn": "specialWorkspace", "specialWorkspaceOut": "specialWorkspace",
    ]

    static let maxSpeed = 10_000.0
    static let maxPercent = 1_000.0

    private var overrides: [String: AnimationLeaf] = [
        "global": AnimationLeaf(enabled: true, speed: 8, curve: "default", style: ""),
        "borderangle": AnimationLeaf(enabled: false, speed: 1, curve: "default", style: ""),
        "shadowangle": AnimationLeaf(enabled: false, speed: 1, curve: "default", style: ""),
        "glowangle": AnimationLeaf(enabled: false, speed: 1, curve: "default", style: ""),
    ]

    public init() {}

    public func leaf(_ name: String) -> AnimationLeaf {
        var current: String? = name
        while let n = current {
            if let leaf = overrides[n] { return leaf }
            current = AnimationTree.parents[n]
        }
        return overrides["global"]!
    }

    public mutating func apply(_ value: String, curves: Set<String>) -> String? {
        let parts = value.split(separator: ",", maxSplits: 4, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let name = parts.first, name == "global" || AnimationTree.parents[name] != nil else {
            return "no such animation '\(parts.first ?? "")'"
        }
        guard parts.count >= 2, let on = ConfigValue.bool(parts[1]) else { return "invalid animation '\(value)'" }
        if !on {
            overrides[name] = AnimationLeaf(enabled: false, speed: 1, curve: "default", style: "")
            return nil
        }
        guard parts.count >= 4, let speed = finiteDouble(parts[2]) else { return "invalid animation '\(value)'" }
        guard speed > 0 else { return "animation speed must be positive" }
        guard speed <= AnimationTree.maxSpeed else { return "animation speed is too large" }
        guard curves.contains(parts[3]) else { return "no such bezier '\(parts[3])'" }
        let style = parts.count > 4 ? parts[4] : ""
        guard AnimationTree.isValidStyle(style, for: name) else { return "invalid animation style '\(style)' for \(name)" }
        overrides[name] = AnimationLeaf(enabled: true, speed: speed, curve: parts[3], style: style)
        return nil
    }

    static func isValidStyle(_ style: String, for name: String) -> Bool {
        let words = style.split(separator: " ").map(String.init)
        guard let first = words.first else { return true }
        let sides: Set<String> = ["top", "bottom", "left", "right"]
        func isPercent(_ w: String) -> Bool {
            guard w.hasSuffix("%"), let n = finiteDouble(w.dropLast()) else { return false }
            return (0...maxPercent).contains(n)
        }
        if name.hasPrefix("windows") {
            switch first {
            case "slide": return words.count == 1 || (words.count == 2 && sides.contains(words[1]))
            case "popin": return words.count == 1 || (words.count == 2 && isPercent(words[1]))
            case "gnomed": return words.count == 1
            default: return false
            }
        }
        if name.hasPrefix("layers") { return ["slide", "popin", "fade"].contains(first) }
        if name.hasPrefix("workspaces") || name.hasPrefix("specialWorkspace") {
            guard ["slide", "slidevert", "fade", "slidefade", "slidefadevert"].contains(first) else { return false }
            return words.dropFirst().allSatisfy { sides.contains($0) || isPercent($0) }
        }
        if name.hasSuffix("angle") { return words == ["once"] || words == ["loop"] }
        return true
    }
}
