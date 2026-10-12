import Foundation

public struct MonocleLayout: TiledLayout, Equatable, Codable, Sendable {
    var order: [WindowID] = []

    public init() {}

    public var windowIDs: [WindowID] { order }

    public mutating func insert(_ id: WindowID, _ ctx: LayoutContext) {
        guard !order.contains(id) else { return }
        if let f = ctx.focused, let i = order.firstIndex(of: f) { order.insert(id, at: i + 1) } else { order.append(id) }
    }

    public mutating func remove(_ id: WindowID) { order.removeAll { $0 == id } }

    public func tileBoxes(_ ctx: LayoutContext) -> [WindowID: Rect] {
        Dictionary(order.map { ($0, ctx.workArea) }) { first, _ in first }
    }

    public mutating func resize(_ id: WindowID, by delta: Point, corner: Corner, _ ctx: LayoutContext) {}

    public mutating func swap(_ a: WindowID, _ b: WindowID) {
        guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b) else { return }
        order.swapAt(i, j)
    }

    public mutating func moveWindow(_ id: WindowID, _ direction: Direction, _ ctx: LayoutContext) -> Bool {
        guard let i = order.firstIndex(of: id) else { return false }
        let j = (direction == .left || direction == .up) ? i - 1 : i + 1
        guard order.indices.contains(j) else { return false }
        order.swapAt(i, j)
        return true
    }

    public func neighbor(of id: WindowID, forward: Bool) -> WindowID? {
        guard let i = order.firstIndex(of: id), order.count > 1 else { return nil }
        return order[(i + (forward ? 1 : order.count - 1)) % order.count]
    }

    public mutating func message(_ text: String, _ ctx: LayoutContext) -> LayoutMessageResult {
        guard let f = ctx.focused else { return .error("no focused tiled window") }
        switch text.split(separator: " ").first {
        case "cyclenext": return neighbor(of: f, forward: true).map { .focus($0) } ?? .ok
        case "cycleprev": return neighbor(of: f, forward: false).map { .focus($0) } ?? .ok
        default: return .error("unknown monocle layout message '\(text)'")
        }
    }

    public func nextFocusCandidate(near point: Point, _ ctx: LayoutContext) -> WindowID? { order.last }
}
