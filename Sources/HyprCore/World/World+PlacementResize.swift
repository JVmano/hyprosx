import Foundation

enum PlacementAxis { case x, y }

enum PlacementAnchor { case lo, hi, center }

extension Rect {
    func lo(_ axis: PlacementAxis) -> Double { axis == .x ? minX : minY }
    func hi(_ axis: PlacementAxis) -> Double { axis == .x ? maxX : maxY }
    func with(_ axis: PlacementAxis, _ lo: Double, _ hi: Double) -> Rect {
        axis == .x ? Rect(x: lo, y: y, width: hi - lo, height: height) : Rect(x: x, y: lo, width: width, height: hi - lo)
    }
}

struct PlacementResize {
    static let minimumSize = 100.0

    let area: Rect
    let gaps: Edges
    var rects: [WindowID: Rect]
    let rest: [Rect]

    static func fit(lo: Double, hi: Double, length: Double, anchor: PlacementAnchor, floor: Double, ceil: Double) -> (lo: Double, hi: Double) {
        let floor = min(floor, lo), ceil = max(ceil, hi)
        let room: Double
        switch anchor {
        case .lo: room = ceil - lo
        case .hi: room = hi - floor
        case .center: room = ceil - floor
        }
        let len = min(max(length, min(minimumSize, hi - lo)), room)
        let start: Double
        switch anchor {
        case .lo: start = lo
        case .hi: start = hi - len
        case .center: start = (lo + hi) / 2 - len / 2
        }
        let placed = min(max(start, floor), ceil - len)
        return (placed, placed + len)
    }

    func gap(_ axis: PlacementAxis) -> (lo: Double, hi: Double) {
        axis == .x ? (gaps.left, gaps.right) : (gaps.top, gaps.bottom)
    }

    func across(_ a: Rect, _ b: Rect, _ axis: PlacementAxis) -> Bool {
        let other: PlacementAxis = axis == .x ? .y : .x
        return min(a.hi(other), b.hi(other)) - max(a.lo(other), b.lo(other)) > World.overlapTolerance
    }

    func anchor(of rect: Rect, _ axis: PlacementAxis) -> PlacementAnchor? {
        let lo = abs(rect.lo(axis) - area.lo(axis)) <= World.overlapTolerance
        let hi = abs(rect.hi(axis) - area.hi(axis)) <= World.overlapTolerance
        if lo && hi { return nil }
        return lo ? .lo : hi ? .hi : .center
    }

    func limits(_ id: WindowID, _ rect: Rect, _ axis: PlacementAxis) -> (floor: Double, ceil: Double) {
        let tol = World.overlapTolerance
        let g = gap(axis)
        var floor = area.lo(axis), ceil = area.hi(axis)
        for (key, other) in rects where key != id && across(other, rect, axis) {
            if other.hi(axis) <= rect.lo(axis) + tol { floor = max(floor, other.hi(axis)) }
            if other.lo(axis) >= rect.hi(axis) - tol { ceil = min(ceil, other.lo(axis)) }
        }
        let before = rest.contains { across($0, rect, axis) && $0.hi(axis) <= rect.lo(axis) + tol && $0.lo(axis) >= floor - tol }
        let after = rest.contains { across($0, rect, axis) && $0.lo(axis) >= rect.hi(axis) - tol && $0.hi(axis) <= ceil + tol }
        if before {
            let open = floor == area.lo(axis)
            floor = (open ? floor : floor + g.hi) + g.lo + PlacementResize.minimumSize + (open ? 0 : g.lo) + g.hi
        }
        if after {
            let open = ceil == area.hi(axis)
            ceil = (open ? ceil : ceil - g.lo) - g.hi - PlacementResize.minimumSize - g.lo - (open ? 0 : g.hi)
        }
        return (floor, ceil)
    }

    mutating func fit(_ id: WindowID, _ axis: PlacementAxis, length: Double, anchor: PlacementAnchor) {
        guard let rect = rects[id] else { return }
        let l = limits(id, rect, axis)
        let out = PlacementResize.fit(lo: rect.lo(axis), hi: rect.hi(axis), length: length, anchor: anchor, floor: l.floor, ceil: l.ceil)
        rects[id] = rect.with(axis, out.lo, out.hi)
    }

    func neighbors(of box: Rect, _ axis: PlacementAxis) -> [(id: WindowID, anchor: PlacementAnchor)] {
        let tol = World.overlapTolerance
        let g = gap(axis)
        return rects.sorted { $0.key < $1.key }.compactMap { key, rect in
            guard across(rect, box, axis) else { return nil }
            if (-tol ... g.lo + tol).contains(rect.lo(axis) - box.hi(axis)) { return (key, .hi) }
            if (-tol ... g.hi + tol).contains(box.lo(axis) - rect.hi(axis)) { return (key, .lo) }
            return nil
        }
    }
}

extension World {
    func placementStrips(_ ws: Workspace, placements: [WindowID: Rect], area: Rect) -> [Rect] {
        let found = World.freeStrips(placed: placements.values.compactMap { World.clip($0, to: area) }, in: area, gaps: gapsIn(for: ws))
        return found.isEmpty ? [area] : found
    }

    func resizeAmongPlacements(_ id: WindowID, in ws: inout Workspace, placements: [WindowID: Rect], size: Size, current: Rect) {
        let area = workArea(for: ws)
        let boxes = effectiveBoxes(ws)
        var plan = PlacementResize(area: area, gaps: gapsIn(for: ws), rects: placements,
                                   rest: ws.tiledIDs.filter { placements[$0] == nil }.compactMap { boxes[$0] })
        if let rect = placements[id] {
            for axis in [PlacementAxis.x, .y] {
                guard let anchor = plan.anchor(of: plan.rects[id] ?? rect, axis) else { continue }
                plan.fit(id, axis, length: axis == .x ? size.width : size.height, anchor: anchor)
            }
        } else if let box = boxes[id] {
            var layoutDelta = Point(x: 0, y: 0)
            for axis in [PlacementAxis.x, .y] {
                let delta = axis == .x ? size.width - current.width : size.height - current.height
                let adjacent = plan.neighbors(of: box, axis)
                guard !adjacent.isEmpty else {
                    if axis == .x { layoutDelta.x = delta } else { layoutDelta.y = delta }
                    continue
                }
                for (key, anchor) in adjacent {
                    guard let rect = plan.rects[key] else { continue }
                    let length = (axis == .x ? rect.width : rect.height) - delta / Double(adjacent.count)
                    plan.fit(key, axis, length: length, anchor: anchor)
                }
            }
            resizeInsideStrip(id, in: &ws, placements: placements, area: area, by: layoutDelta)
        }
        for (key, rect) in plan.rects { windows[key]?.placedFrame = rect.rounded() }
        workspaces[ws.id] = ws
    }

    func resizeInsideStrip(_ id: WindowID, in ws: inout Workspace, placements: [WindowID: Rect], area: Rect, by delta: Point) {
        let strips = placementStrips(ws, placements: placements, area: area)
        guard delta.x != 0 || delta.y != 0, strips.count == 1, case .dwindle(var full) = ws.layout else { return }
        var rest = ws.layout
        for key in placements.keys { rest.update { $0.remove(key) } }
        var ctx = layoutContext(ws)
        ctx.workArea = strips[0]
        rest.update { $0.resize(id, by: delta, corner: .none, ctx) }
        guard case .dwindle(let resized) = rest else { return }
        full.adoptRatios(from: resized)
        ws.layout = .dwindle(full)
    }
}
