import Foundation

public struct Decoration: Equatable, Sendable {
    public var id: WindowID
    public var frame: Rect
    public var border: Gradient?
    public var borderWidth: Double
    public var isActive: Bool
    public var dim: Double
}

public struct DecorationSet: Equatable, Sendable {
    public var windows: [Decoration] = []
    public var dimAround: [WindowID] = []
    public var dimAroundStrength = 0.0
}

extension World {
    public func decorations() -> DecorationSet {
        var set = DecorationSet()
        set.dimAroundStrength = config.decoration.dimAround
        for id in windows.keys.sorted() {
            guard let w = windows[id], w.suspended == nil, !w.isParked, let frame = w.appliedFrame,
                  let ws = workspaces[w.workspace], isVisible(ws.id) else { continue }
            let rules = dynamicOutcome(for: w)
            if rules.dimAround { set.dimAround.append(id) }
            let active = focusedWindow == id
            let width = w.props["border_size"].flatMap { finiteDouble($0) }.map(World.borderWidth)
                ?? rules.borderSize.map { World.borderWidth(Double($0)) }
                ?? borderSize(for: ws)
            var border: Gradient? = w.props["border_color"].flatMap { ConfigValue.gradient($0) }
                ?? (active ? rules.activeBorder ?? config.general.activeBorder : rules.inactiveBorder ?? config.general.inactiveBorder)
            if w.fullscreenMode != nil || width <= 0 || border?.isFullyTransparent == true { border = nil }
            let dims = config.decoration.dimInactive && !active && !w.isFloating && w.fullscreenMode == nil
            set.windows.append(Decoration(id: id, frame: frame, border: border, borderWidth: width, isActive: active,
                                          dim: dims ? config.decoration.dimStrength : 0))
        }
        return set
    }
}
