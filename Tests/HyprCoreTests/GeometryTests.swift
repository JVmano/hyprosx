import Testing
@testable import HyprCore

@Suite struct GeometryTests {
    @Test func rectEdgesAndCenter() {
        let r = Rect(x: 10, y: 20, width: 100, height: 50)
        #expect(r.maxX == 110 && r.maxY == 70)
        #expect(r.center == Point(x: 60, y: 45))
    }

    @Test func containsIsHalfOpen() {
        let r = Rect(x: 0, y: 0, width: 10, height: 10)
        #expect(r.contains(Point(x: 0, y: 0)))
        #expect(!r.contains(Point(x: 10, y: 5)))
    }

    @Test func insetByEdges() {
        let r = Rect(x: 0, y: 0, width: 100, height: 100)
        #expect(r.inset(by: Edges(top: 1, right: 2, bottom: 3, left: 4)) == Rect(x: 4, y: 1, width: 94, height: 96))
    }

    @Test func distanceSquaredIsZeroInsideAndAxisDistanceOutside() {
        let r = Rect(x: 0, y: 0, width: 10, height: 10)
        #expect(r.distanceSquared(to: Point(x: 5, y: 5)) == 0)
        #expect(r.distanceSquared(to: Point(x: 13, y: 14)) == 9 + 16)
    }

    @Test(arguments: [
        ([5.0], Edges(top: 5, right: 5, bottom: 5, left: 5)),
        ([5.0, 10], Edges(top: 5, right: 10, bottom: 5, left: 10)),
        ([1.0, 2, 3], Edges(top: 1, right: 2, bottom: 3, left: 2)),
        ([1.0, 2, 3, 4], Edges(top: 1, right: 2, bottom: 3, left: 4)),
    ])
    func cssEdges(_ values: [Double], _ expected: Edges) {
        #expect(Edges(css: values) == expected)
    }

    @Test func roundedRoundsEachComponent() {
        #expect(Rect(x: 0.4, y: 0.6, width: 9.5, height: 10.49).rounded() == Rect(x: 0, y: 1, width: 10, height: 10))
    }

    @Test func diagnosticDescription() {
        let d = Diagnostic(SourceLocation(file: "/a/hyprland.conf", line: 3), "bad value", isWarning: false)
        #expect(d.description == "hyprland.conf:3: bad value")
    }
}
