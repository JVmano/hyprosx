import Foundation

public struct Point: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public static let zero = Point(x: 0, y: 0)
    public static func + (a: Point, b: Point) -> Point { Point(x: a.x + b.x, y: a.y + b.y) }
    public static func - (a: Point, b: Point) -> Point { Point(x: a.x - b.x, y: a.y - b.y) }
}

public struct Size: Equatable, Hashable, Codable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public struct Edges: Equatable, Hashable, Codable, Sendable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double
    public init(top: Double, right: Double, bottom: Double, left: Double) {
        self.top = top; self.right = right; self.bottom = bottom; self.left = left
    }
    public init(all v: Double) { self.init(top: v, right: v, bottom: v, left: v) }
    public init(css v: [Double]) {
        switch v.count {
        case 1: self.init(all: v[0])
        case 2: self.init(top: v[0], right: v[1], bottom: v[0], left: v[1])
        case 3: self.init(top: v[0], right: v[1], bottom: v[2], left: v[1])
        case 4...: self.init(top: v[0], right: v[1], bottom: v[2], left: v[3])
        default: self.init(all: 0)
        }
    }
    public static let zero = Edges(all: 0)
}

public struct Rect: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public init(origin: Point, size: Size) {
        self.init(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }
    public static let zero = Rect(x: 0, y: 0, width: 0, height: 0)
    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var origin: Point { Point(x: x, y: y) }
    public var size: Size { Size(width: width, height: height) }
    public var center: Point { Point(x: x + width / 2, y: y + height / 2) }
    public func contains(_ p: Point) -> Bool { p.x >= x && p.x < maxX && p.y >= y && p.y < maxY }
    public func intersects(_ o: Rect) -> Bool { x < o.maxX && o.x < maxX && y < o.maxY && o.y < maxY }
    public func inset(by e: Edges) -> Rect {
        Rect(x: x + e.left, y: y + e.top, width: max(0, width - e.left - e.right), height: max(0, height - e.top - e.bottom))
    }
    public func rounded() -> Rect {
        Rect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }
    public func distanceSquared(to p: Point) -> Double {
        let dx = max(0, x - p.x, p.x - maxX)
        let dy = max(0, y - p.y, p.y - maxY)
        return dx * dx + dy * dy
    }
    public func isClose(to o: Rect, tolerance: Double = 1) -> Bool {
        abs(x - o.x) < tolerance && abs(y - o.y) < tolerance && abs(width - o.width) < tolerance && abs(height - o.height) < tolerance
    }
}
