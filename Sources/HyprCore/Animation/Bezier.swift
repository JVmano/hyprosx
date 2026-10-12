import Foundation

public struct Bezier: Equatable, Sendable {
    public let p1: Point
    public let p2: Point
    private let baked: [Point]

    public init(p1: Point, p2: Point) {
        self.p1 = p1
        self.p2 = p2
        func axis(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        baked = (0..<255).map { i in
            let t = Double(i + 1) / 255
            return Point(x: axis(t, p1.x, p2.x), y: axis(t, p1.y, p2.y))
        }
    }

    public func y(at x: Double) -> Double {
        if x >= 1 { return 1 }
        if !(x > 0) { return 0 }
        var lo = 0
        var hi = baked.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if baked[mid].x < x { lo = mid + 1 } else { hi = mid }
        }
        let lower = max(0, min(lo - 1, baked.count - 2))
        let a = baked[lower]
        let b = baked[lower + 1]
        let dx = b.x - a.x
        if dx <= 1e-6 { return a.y }
        return a.y + (b.y - a.y) * (x - a.x) / dx
    }

    public static func == (l: Bezier, r: Bezier) -> Bool { l.p1 == r.p1 && l.p2 == r.p2 }

    public static let builtIns: [String: Bezier] = [
        "default": Bezier(p1: Point(x: 0, y: 0.75), p2: Point(x: 0.15, y: 1)),
        "linear": Bezier(p1: Point(x: 0, y: 0), p2: Point(x: 1, y: 1)),
    ]

    public static func parse(_ value: String) -> (name: String, curve: Bezier)? {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 5, !parts[0].isEmpty else { return nil }
        let n = parts.dropFirst().compactMap { finiteDouble($0) }
        guard n.count == 4, n.allSatisfy({ (-1.0...2.0).contains($0) }) else { return nil }
        return (parts[0], Bezier(p1: Point(x: n[0], y: n[1]), p2: Point(x: n[2], y: n[3])))
    }
}
