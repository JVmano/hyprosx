import Testing
@testable import HyprCore

func dirtyWorld() -> World {
    let w = world("windowrule = float on, match:class Calc", monitors: [laptop, ultrawide])
    _ = w.handle(.windowAppeared(snap(1)))
    _ = w.handle(.windowAppeared(snap(2, pid: 200)))
    _ = w.run(.moveToWorkspace(.special("magic"), .address(2), silent: false))
    _ = w.run(.exec("true", rules: "float", raw: false))
    _ = w.run(.exec("true", rules: "float", raw: false))
    w.registerSpawn(token: 1, pid: 77)
    w.switchWorkspace(3)
    _ = w.run(.focusMonitor(.id(1)))
    _ = w.run(.submap("x"))
    w.cursor = Point(x: 5, y: 6)
    w.isStartingUp = true
    w.ignored.insert(99)
    w.nextNamedID = 1_000_042
    w.focusedWindow = 1
    w.dragging = 1
    w.dragIsResize = true
    return w
}

@Suite struct ScratchCopyTests {
    @Test func scratchCopyCopiesEveryStoredPropertyOfWorld() {
        let original = dirtyWorld()
        let copy = original.scratchCopy()
        let fresh = World(config: original.config)
        let a = Array(Mirror(reflecting: original).children)
        let b = Array(Mirror(reflecting: copy).children)
        let c = Array(Mirror(reflecting: fresh).children)
        #expect(a.count == b.count && a.count == c.count)
        #expect(a.count > 20)
        for i in a.indices where a[i].label != "effects" && a[i].label != "config" {
            let label = a[i].label ?? "?"
            #expect(String(describing: a[i].value) == String(describing: b[i].value), "\(label) is not copied by scratchCopy")
            #expect(String(describing: a[i].value) != String(describing: c[i].value), "\(label) is not set by dirtyWorld, so the test cannot see it")
        }
        #expect(String(describing: original.config) == String(describing: copy.config))
    }
}
