import Testing
@testable import HyprCore

@Suite struct WindowGeometryTests {
    let wa = Rect(x: 10, y: 42, width: 1492, height: 898)

    @Test func loneWindowGetsNoInnerGapButBorderInset() {
        let f = WindowGeometry.frame(tile: wa, workArea: wa, gapsIn: Edges(all: 4), borderSize: 2, pseudoSize: nil)
        #expect(f == Rect(x: 12, y: 44, width: 1488, height: 894))
    }

    @Test func neighboursAreTwoInnerGapsApart() {
        let left = Rect(x: 10, y: 42, width: 746, height: 898)
        let right = Rect(x: 756, y: 42, width: 746, height: 898)
        let a = WindowGeometry.frame(tile: left, workArea: wa, gapsIn: Edges(all: 4), borderSize: 0, pseudoSize: nil)
        let b = WindowGeometry.frame(tile: right, workArea: wa, gapsIn: Edges(all: 4), borderSize: 0, pseudoSize: nil)
        #expect(a == Rect(x: 10, y: 42, width: 742, height: 898))
        #expect(b == Rect(x: 760, y: 42, width: 742, height: 898))
        #expect(b.minX - a.maxX == 8)
    }

    @Test func pseudoIsCenteredAndShrunkToFit() {
        let small = WindowGeometry.frame(tile: wa, workArea: wa, gapsIn: .zero, borderSize: 0, pseudoSize: Size(width: 400, height: 300))
        #expect(small == Rect(x: 556, y: 341, width: 400, height: 300))
        let big = WindowGeometry.frame(tile: Rect(x: 0, y: 0, width: 400, height: 400), workArea: Rect(x: 0, y: 0, width: 400, height: 400),
                                       gapsIn: .zero, borderSize: 0, pseudoSize: Size(width: 800, height: 400))
        #expect(big == Rect(x: 0, y: 100, width: 400, height: 200))
    }

    @Test func focalPoints() {
        let b = Rect(x: 100, y: 100, width: 200, height: 100)
        #expect(WindowGeometry.focalPoint(of: b, .left) == Point(x: 99, y: 150))
        #expect(WindowGeometry.focalPoint(of: b, .right) == Point(x: 301, y: 150))
        #expect(WindowGeometry.focalPoint(of: b, .up) == Point(x: 200, y: 99))
        #expect(WindowGeometry.focalPoint(of: b, .down) == Point(x: 200, y: 201))
    }

    @Test func hugeValuesDoNotTrap() {
        let huge = Rect(x: 0, y: 0, width: 1e300, height: 1e300)
        let f = WindowGeometry.frame(tile: huge, workArea: huge, gapsIn: Edges(all: 1e300), borderSize: 1e300, pseudoSize: Size(width: 1e300, height: 1e300))
        #expect(f.width >= 1 || f.width.isNaN)
        let g = WindowGeometry.frame(tile: huge, workArea: wa, gapsIn: Edges(all: 9e18), borderSize: 9e18, pseudoSize: nil)
        #expect(g.width >= 1 || g.width.isNaN)
        let inf = WindowGeometry.frame(tile: Rect(x: 0, y: 0, width: .infinity, height: .infinity), workArea: wa,
                                       gapsIn: Edges(all: .infinity), borderSize: .infinity, pseudoSize: Size(width: .infinity, height: 1))
        #expect(inf.width >= 1 || inf.width.isNaN)
    }
}
