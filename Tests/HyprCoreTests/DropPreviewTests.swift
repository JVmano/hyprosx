import Testing
@testable import HyprCore

let wideMonitor = MonitorInfo(id: 0, name: "Wide", frame: Rect(x: 0, y: 0, width: 3440, height: 1440),
                              visibleFrame: Rect(x: 0, y: 0, width: 3440, height: 1440))

func startDrag(_ w: World, _ id: WindowID, offset: Point = Point(x: 300, y: 200)) {
    let a = w.windows[id]!.appliedFrame!
    _ = w.handle(.windowFrameChanged(id, Rect(x: offset.x, y: offset.y, width: a.width, height: a.height), userDriven: true))
}

func landing(_ make: () -> World, drag id: WindowID, at cursor: Point) -> Rect? {
    let w = make()
    startDrag(w, id)
    _ = w.handle(.dragEnded(cursor: cursor))
    return w.windows[id]?.appliedFrame
}

@Suite struct DropPreviewTests {
    @Test func dwindlePreviewFollowsTheHalfUnderTheCursorAndMatchesTheDrop() {
        func make() -> World { world(monitors: [wideMonitor]).with3Windows() }
        let left = Point(x: 400, y: 700), right = Point(x: 1500, y: 700)
        let w = make()
        startDrag(w, 3)
        let previewLeft = w.dropPreview(cursor: left), previewRight = w.dropPreview(cursor: right)
        #expect(previewLeft != nil && previewRight != nil)
        #expect(previewLeft != previewRight)
        #expect(previewLeft == landing(make, drag: 3, at: left))
        #expect(previewRight == landing(make, drag: 3, at: right))
        #expect(previewLeft?.minX == 0 && previewRight?.minX ?? 0 > 0)
    }

    @Test func dwindlePreviewOverAnotherTileMatchesTheDrop() {
        func make() -> World { threeWindows() }
        let w = make()
        startDrag(w, 1)
        let cursor = Point(x: 1300, y: 800)
        #expect(w.dropPreview(cursor: cursor) != nil)
        #expect(w.dropPreview(cursor: cursor) == landing(make, drag: 1, at: cursor))
    }

    @Test func masterPreviewIsTheSwapTargetFrame() {
        let w = twoWindows("general:layout = master")
        let b = w.windows[2]!.appliedFrame!
        startDrag(w, 1)
        #expect(w.dropPreview(cursor: b.center) == b)
        #expect(w.dropPreview(cursor: b.center) == landing({ twoWindows("general:layout = master") }, drag: 1, at: b.center))
    }

    @Test func ownTileOrNoTileGivesNil() {
        let w = twoWindows()
        startDrag(w, 1)
        #expect(w.dropPreview(cursor: Point(x: 100, y: 500)) == nil)
        let master = twoWindows("general:layout = master")
        startDrag(master, 1)
        #expect(master.dropPreview(cursor: Point(x: 100, y: 500)) == nil)
        #expect(master.dropPreview(cursor: Point(x: 1000, y: 10)) == nil)
        let monocle = twoWindows("general:layout = monocle")
        startDrag(monocle, 1)
        #expect(monocle.dropPreview(cursor: Point(x: 100, y: 500)) == nil)
    }

    @Test func noDragFloatingDragAndResizeDragGiveNil() {
        let idle = twoWindows()
        #expect(idle.dropPreview(cursor: Point(x: 1300, y: 800)) == nil)

        let resizing = twoWindows()
        _ = resizing.handle(.windowFrameChanged(1, Rect(x: 0, y: 32, width: 856, height: 950), userDriven: true))
        #expect(resizing.dragging == 1 && resizing.dragIsResize)
        #expect(resizing.dropPreview(cursor: Point(x: 1300, y: 800)) == nil)

        let floating = twoWindows()
        _ = floating.run(.floating(.set, .address(1)))
        startDrag(floating, 1)
        #expect(floating.dropPreview(cursor: Point(x: 1300, y: 800)) == nil)
    }

    @Test func previewNeverMutatesTheWorld() {
        let w = twoWindows()
        startDrag(w, 1)
        let before = (w.snapshot(), w.windows, w.workspaces, w.dragging, w.dragIsResize, w.cursor, w.focusedMonitor, w.focusedWindow)
        _ = w.dropPreview(cursor: Point(x: 1300, y: 800))
        #expect(w.snapshot() == before.0)
        #expect(w.windows == before.1)
        #expect(w.workspaces == before.2)
        #expect(w.dragging == before.3 && w.dragIsResize == before.4 && w.cursor == before.5)
        #expect(w.focusedMonitor == before.6 && w.focusedWindow == before.7)
        #expect(w.takeEffects().isEmpty)
        let end = w.handle(.dragEnded(cursor: Point(x: 1300, y: 800)))
        #expect(frames(end)[1] == landing({ twoWindows() }, drag: 1, at: Point(x: 1300, y: 800)))
    }

    @Test func dropOntoAnotherMonitorsWorkspaceShowsThatMonitorsFrame() {
        func make() -> World {
            let w = world("windowrule = workspace 2, match:class Term", monitors: [laptop, ultrawide])
            _ = w.handle(.windowAppeared(snap(1)))
            _ = w.handle(.windowAppeared(snap(2, app: "Term", bundle: "x.term", pid: 200)))
            return w
        }
        let w = make()
        #expect(w.windows[2]?.workspace == 2)
        startDrag(w, 1)
        let cursor = Point(x: 4000, y: 700)
        let preview = w.dropPreview(cursor: cursor)
        #expect(preview != nil)
        #expect(preview.map { ultrawide.frame.contains($0.center) } == true)
        #expect(preview == landing(make, drag: 1, at: cursor))
    }
}

extension World {
    func with3Windows() -> World {
        for id: WindowID in 1 ... 3 { _ = handle(.windowAppeared(snap(id, pid: Int32(id) * 100))) }
        return self
    }
}
