import Foundation
import Testing
@testable import HyprCore

private let area = Rect(x: 0, y: 0, width: 1000, height: 600)

private func mctx(_ focused: WindowID? = nil, _ edit: (inout MasterOptions) -> Void = { _ in }) -> LayoutContext {
    var o = MasterOptions()
    edit(&o)
    return LayoutContext(workArea: area, focused: focused, master: o)
}

private func master(_ count: WindowID, _ edit: (inout MasterOptions) -> Void = { _ in }) -> MasterLayout {
    var m = MasterLayout()
    for id in 1...count { m.insert(id, mctx(id > 1 ? id - 1 : nil, edit)) }
    return m
}

private func finiteAndInside(_ boxes: [WindowID: Rect]) -> Bool {
    boxes.values.allSatisfy { r in
        [r.x, r.y, r.width, r.height].allSatisfy(\.isFinite)
            && r.width >= 0 && r.height >= 0 && r.minX >= -1e-6 && r.minY >= -1e-6
            && r.maxX <= area.maxX + 1e-6 && r.maxY <= area.maxY + 1e-6
    }
}

@Suite struct MasterMonocleTests {
    @Test func singleWindowFillsTheArea() {
        #expect(master(1).tileBoxes(mctx()) == [1: area])
        let kept = master(1) { $0.alwaysKeepPosition = true }
        #expect(kept.tileBoxes(mctx { $0.alwaysKeepPosition = true })[1] == Rect(x: 0, y: 0, width: 550, height: 600))
    }

    @Test func leftOrientation() {
        let b = master(3).tileBoxes(mctx())
        #expect(b[1] == Rect(x: 0, y: 0, width: 550, height: 600))
        #expect(b[2] == Rect(x: 550, y: 0, width: 450, height: 300))
        #expect(b[3] == Rect(x: 550, y: 300, width: 450, height: 300))
    }

    @Test func otherOrientations() {
        let m = master(3)
        #expect(m.tileBoxes(mctx { $0.orientation = "right" })[1] == Rect(x: 450, y: 0, width: 550, height: 600))
        let top = m.tileBoxes(mctx { $0.orientation = "top" })
        #expect(top[1] == Rect(x: 0, y: 0, width: 1000, height: 330))
        #expect(top[3] == Rect(x: 500, y: 330, width: 500, height: 270))
        #expect(m.tileBoxes(mctx { $0.orientation = "bottom" })[1] == Rect(x: 0, y: 270, width: 1000, height: 330))
        let center = m.tileBoxes(mctx { $0.orientation = "center" })
        #expect(center[1] == Rect(x: 225, y: 0, width: 550, height: 600))
        #expect(center[2] == Rect(x: 0, y: 0, width: 225, height: 600))
        #expect(center[3] == Rect(x: 775, y: 0, width: 225, height: 600))
        let fallback = master(2).tileBoxes(mctx { $0.orientation = "center" })
        #expect(fallback[1] == Rect(x: 0, y: 0, width: 550, height: 600))
    }

    @Test func newStatusMasterDemotesOldMaster() {
        let m = master(2) { $0.newStatus = "master" }
        let b = m.tileBoxes(mctx())
        #expect(b[2] == Rect(x: 0, y: 0, width: 550, height: 600))
        #expect(b[1] == Rect(x: 550, y: 0, width: 450, height: 600))
    }

    @Test func newOnTopAndNewOnActive() {
        let top = master(3) { $0.newOnTop = true }
        #expect(top.tileBoxes(mctx())[3] == Rect(x: 550, y: 0, width: 450, height: 300))
        var after = master(3)
        after.insert(4, mctx(2) { $0.newOnActive = "after" })
        #expect(after.windowIDs == [1, 2, 4, 3])
    }

    @Test func removingMasterPromotesFirstSlave() {
        var m = master(3)
        m.remove(1)
        let b = m.tileBoxes(mctx())
        #expect(b[2] == Rect(x: 0, y: 0, width: 550, height: 600))
        #expect(b[3] == Rect(x: 550, y: 0, width: 450, height: 600))
        m.remove(2)
        #expect(m.tileBoxes(mctx()) == [3: area])
    }

    @Test func swapWithMasterAndFocusMaster() {
        var m = master(3)
        #expect(m.message("swapwithmaster", mctx(3)) == .ok)
        #expect(m.tileBoxes(mctx())[3] == Rect(x: 0, y: 0, width: 550, height: 600))
        #expect(m.message("swapwithmaster child", mctx(2)) == .focus(3))
        #expect(m.message("focusmaster", mctx(1)) == .focus(2))
        #expect(m.message("focusmaster auto", mctx(2)) == .focus(3))
    }

    @Test func cycleAndSwapNext() {
        var m = master(3)
        #expect(m.message("cyclenext", mctx(3)) == .focus(1))
        #expect(m.message("cyclenext noloop", mctx(3)) == .ok)
        #expect(m.message("cycleprev", mctx(1)) == .focus(3))
        #expect(m.message("swapnext", mctx(2)) == .ok)
        #expect(m.windowIDs == [1, 3, 2])
    }

    @Test func addAndRemoveMaster() {
        var m = master(3)
        #expect(m.message("addmaster", mctx(2)) == .ok)
        let b = m.tileBoxes(mctx())
        #expect(b[1] == Rect(x: 0, y: 0, width: 550, height: 300))
        #expect(b[2] == Rect(x: 0, y: 300, width: 550, height: 300))
        #expect(b[3] == Rect(x: 550, y: 0, width: 450, height: 600))
        #expect(m.message("addmaster", mctx(3)) == .error("nothing to do"))
        #expect(m.message("removemaster", mctx(3)) == .ok)
        #expect(m.tileBoxes(mctx())[1] == Rect(x: 0, y: 0, width: 550, height: 600))
    }

    @Test func orientationMessagesAndMfact() {
        var m = master(3)
        #expect(m.message("orientationtop", mctx(1)) == .ok)
        #expect(m.tileBoxes(mctx())[1]?.height == 330)
        #expect(m.message("orientationnext", mctx(1)) == .ok)
        #expect(m.tileBoxes(mctx())[1] == Rect(x: 450, y: 0, width: 550, height: 600))
        #expect(m.message("mfact exact 0.7", mctx(1)) == .ok)
        #expect(m.tileBoxes(mctx())[1]?.width == 700)
        #expect(m.message("mfact 0.5", mctx(1)) == .ok)
        #expect(m.tileBoxes(mctx())[1]?.width == 950)
    }

    @Test func rollNext() {
        var m = master(3)
        #expect(m.message("rollnext", mctx(1)) == .focus(2))
        #expect(m.tileBoxes(mctx())[2] == Rect(x: 0, y: 0, width: 550, height: 600))
        #expect(m.windowIDs == [2, 3, 1])
    }

    @Test func rollPrev() {
        var m = master(3)
        #expect(m.message("rollprev", mctx(1)) == .focus(3))
        #expect(m.windowIDs == [3, 1, 2])
        let b = m.tileBoxes(mctx())
        #expect(b[3] == Rect(x: 0, y: 0, width: 550, height: 600))
        #expect(b[1] == Rect(x: 550, y: 0, width: 450, height: 300))
        #expect(b[2] == Rect(x: 550, y: 300, width: 450, height: 300))
        #expect(m.message("rollnext", mctx(3)) == .focus(1))
        #expect(m.windowIDs == [1, 2, 3])
        #expect(m.tileBoxes(mctx())[1] == Rect(x: 0, y: 0, width: 550, height: 600))
    }

    @Test func rollNextThenRollPrevRestoresTheOrder() {
        var m = master(4)
        #expect(m.message("rollnext", mctx(1)) == .focus(2))
        #expect(m.windowIDs == [2, 3, 4, 1])
        #expect(m.message("rollprev", mctx(2)) == .focus(1))
        #expect(m.windowIDs == [1, 2, 3, 4])
        #expect(m.tileBoxes(mctx())[1] == Rect(x: 0, y: 0, width: 550, height: 600))
        #expect(m.message("rollprev", mctx(1)) == .focus(4))
        #expect(m.message("rollnext", mctx(4)) == .focus(1))
        #expect(m.windowIDs == [1, 2, 3, 4])
    }

    @Test func centerMasterResizeDoublesTheMasterDelta() {
        let center: (inout MasterOptions) -> Void = { $0.orientation = "center" }
        var m = master(3)
        m.resize(1, by: Point(x: 100, y: 0), corner: .none, mctx(1, center))
        #expect(abs((m.tileBoxes(mctx(nil, center))[1]?.width ?? 0) - 750) < 1e-9)
        var few = master(2)
        few.resize(1, by: Point(x: 100, y: 0), corner: .none, mctx(1, center))
        #expect(abs((few.tileBoxes(mctx(nil, center))[1]?.width ?? 0) - 650) < 1e-9)
    }

    @Test func resizeFollowsTheCenterFallbackOrientation() {
        let right: (inout MasterOptions) -> Void = { $0.orientation = "center"; $0.centerMasterFallback = "right" }
        var m = master(2)
        m.resize(1, by: Point(x: 100, y: 0), corner: .none, mctx(1, right))
        let b = m.tileBoxes(mctx(nil, right))
        #expect(abs((b[1]?.width ?? 0) - 450) < 1e-9)
        #expect(abs((b[1]?.minX ?? 0) - 550) < 1e-9)
        let top: (inout MasterOptions) -> Void = { $0.orientation = "center"; $0.centerMasterFallback = "top" }
        var t = master(2)
        t.resize(1, by: Point(x: 0, y: 60), corner: .none, mctx(1, top))
        #expect(abs((t.tileBoxes(mctx(nil, top))[1]?.height ?? 0) - 390) < 1e-9)
    }

    @Test func centerColumnResizeUsesTheNodesInItsOwnColumn() {
        let center: (inout MasterOptions) -> Void = { $0.orientation = "center" }
        var m = master(5)
        m.resize(2, by: Point(x: 0, y: 150), corner: .none, mctx(2, center))
        let b = m.tileBoxes(mctx(nil, center))
        #expect(b[1] == Rect(x: 225, y: 0, width: 550, height: 600))
        #expect(b[2] == Rect(x: 0, y: 0, width: 225, height: 360))
        #expect(b[4] == Rect(x: 0, y: 360, width: 225, height: 240))
        #expect(b[3] == Rect(x: 775, y: 0, width: 225, height: 300))
        #expect(b[5] == Rect(x: 775, y: 300, width: 225, height: 300))
    }

    @Test func centerColumnResizeFollowsTheFallbackStartingSide() {
        let right: (inout MasterOptions) -> Void = { $0.orientation = "center"; $0.centerMasterFallback = "right" }
        var m = master(4)
        m.resize(4, by: Point(x: 0, y: 150), corner: .none, mctx(4, right))
        let b = m.tileBoxes(mctx(nil, right))
        #expect(b[2] == Rect(x: 775, y: 0, width: 225, height: 240))
        #expect(b[4] == Rect(x: 775, y: 240, width: 225, height: 360))
        #expect(b[3] == Rect(x: 0, y: 0, width: 225, height: 600))
    }

    @Test func mfactMessageWritesEveryMaster() {
        var m = master(3)
        #expect(m.message("addmaster", mctx(2)) == .ok)
        #expect(m.message("mfact exact 0.7", mctx(1)) == .ok)
        #expect(m.message("removemaster", mctx(1)) == .ok)
        #expect(m.tileBoxes(mctx())[2]?.width == 700)
        #expect(m.message("addmaster", mctx(3)) == .ok)
        #expect(m.message("mfact 0.1", mctx(2)) == .ok)
        #expect(m.message("removemaster", mctx(2)) == .ok)
        #expect(abs((m.tileBoxes(mctx())[3]?.width ?? 0) - 800) < 1e-9)
    }

    @Test func extremeOptionsKeepBoxesFinite() {
        for mfact in [1e300, -1e300, 0, 1, -0.5] {
            for orientation in ["left", "right", "top", "bottom", "center"] {
                let edit: (inout MasterOptions) -> Void = { $0.mfact = mfact; $0.orientation = orientation; $0.slaveCountForCenterMaster = Int.min }
                let b = master(4, edit).tileBoxes(mctx(nil, edit))
                #expect(b.count == 4)
                #expect(finiteAndInside(b))
            }
        }
        for count in [Int.max, Int.min, 0, -1] {
            let edit: (inout MasterOptions) -> Void = { $0.orientation = "center"; $0.slaveCountForCenterMaster = count }
            #expect(finiteAndInside(master(4, edit).tileBoxes(mctx(nil, edit))))
        }
        let huge: (inout MasterOptions) -> Void = { $0.mfact = 1e300; $0.alwaysKeepPosition = true }
        #expect(finiteAndInside(master(1, huge).tileBoxes(mctx(nil, huge))))
    }

    @Test func resizeClampsAndIgnoresNonFiniteDeltas() {
        var m = master(3)
        m.resize(1, by: Point(x: 1e300, y: 0), corner: .none, mctx(1))
        #expect(m.tileBoxes(mctx())[1]?.width == 950)
        m.resize(1, by: Point(x: -1e300, y: 0), corner: .none, mctx(1))
        #expect(m.tileBoxes(mctx())[1]?.width == 50)
        let before = m
        m.resize(2, by: Point(x: .nan, y: .nan), corner: .none, mctx(2))
        m.resize(2, by: Point(x: .infinity, y: -.infinity), corner: .none, mctx(2))
        #expect(finiteAndInside(m.tileBoxes(mctx())))
        var flat = before
        let degenerate = LayoutContext(workArea: Rect(x: 0, y: 0, width: 0, height: 0), focused: 2)
        flat.resize(2, by: Point(x: 10, y: 10), corner: .none, degenerate)
        #expect(flat == before)
    }

    @Test func stackResizeIsClampedAndSharedBySmartMode() {
        var m = master(3)
        m.resize(2, by: Point(x: 0, y: 1e9), corner: .none, mctx(2))
        let b = m.tileBoxes(mctx())
        #expect(abs((b[2]?.height ?? 0) - 600 * 1.95 / 2.95) < 1e-9)
        #expect(abs((b[3]?.height ?? 0) - 600 / 2.95) < 1e-9)
        var plain = master(3) { $0.smartResizing = false }
        plain.resize(2, by: Point(x: 0, y: 150), corner: .none, mctx(2) { $0.smartResizing = false })
        let p = plain.tileBoxes(mctx { $0.smartResizing = false })
        #expect(p[2]?.height == 300 * 1.5)
        #expect(p[3]?.height == 150)
    }

    @Test func messagesRejectBadNumbersAndNames() {
        var m = master(3)
        let before = m.tileBoxes(mctx())
        for text in ["mfact nan", "mfact inf", "mfact exact nan", "mfact exact -inf", "mfact", "mfact exact"] {
            #expect(m.message(text, mctx(1)) == .error("invalid mfact"))
        }
        #expect(m.tileBoxes(mctx()) == before)
        #expect(m.message("orientationcycle left bogus", mctx(1)) == .error("unknown orientation"))
        #expect(m.message("orientationbogus", mctx(1)) == .error("unknown master layout message 'orientationbogus'"))
        #expect(m.message("nonsense", mctx(1)) == .error("unknown master layout message 'nonsense'"))
        #expect(m.message("", mctx(1)) == .error("empty layout message"))
        #expect(m.message("cyclenext", mctx(99)) == .error("no focused tiled window"))
        #expect(m.tileBoxes(mctx()) == before)
    }

    @Test func orientationCycleUsesTheGivenList() {
        var m = master(2)
        #expect(m.message("orientationcycle top right", mctx(1)) == .ok)
        #expect(m.tileBoxes(mctx())[1]?.height == 330)
        #expect(m.message("orientationcycle top right", mctx(1)) == .ok)
        #expect(m.tileBoxes(mctx())[1]?.minX == 450)
        #expect(m.message("orientationprev", mctx(1)) == .ok)
        #expect(m.tileBoxes(mctx())[1]?.height == 330)
    }

    @Test func removalKeepsAMasterAndEmptiesCleanly() {
        var m = master(3)
        #expect(m.message("addmaster", mctx(2) { $0.allowSmallSplit = true }) == .ok)
        m.remove(1)
        #expect(m.tileBoxes(mctx()).count == 2)
        #expect(finiteAndInside(m.tileBoxes(mctx())))
        m.remove(2)
        m.remove(3)
        #expect(m.windowIDs.isEmpty)
        #expect(m.tileBoxes(mctx()).isEmpty)
    }

    @Test func nextFocusCandidate() {
        let m = master(3)
        #expect(m.nextFocusCandidate(near: Point(x: 900, y: 500), mctx()) == 3)
        #expect(m.nextFocusCandidate(near: Point(x: 10, y: 10), mctx()) == 1)
        #expect(m.nextFocusCandidate(near: Point(x: 900, y: 500), mctx { $0.focusMasterOnClose = true }) == 1)
        #expect(MasterLayout().nextFocusCandidate(near: .zero, mctx()) == nil)
    }

    @Test func codableRoundTrip() throws {
        var m = master(3)
        _ = m.message("orientationtop", mctx(1))
        let data = try JSONEncoder().encode(m)
        #expect(try JSONDecoder().decode(MasterLayout.self, from: data) == m)
        var mono = MonocleLayout()
        mono.insert(5, LayoutContext(workArea: area))
        mono.insert(6, LayoutContext(workArea: area))
        #expect(try JSONDecoder().decode(MonocleLayout.self, from: JSONEncoder().encode(mono)) == mono)
    }

    @Test func monocleSurvivesDuplicateIDsFromASnapshot() throws {
        let dup = try JSONDecoder().decode(MonocleLayout.self, from: Data(#"{"order":[1,1,2]}"#.utf8))
        #expect(dup.tileBoxes(LayoutContext(workArea: area)).count == 2)
    }

    @Test func monocleEdges() {
        var m = MonocleLayout()
        #expect(m.message("cyclenext", LayoutContext(workArea: area)) == .error("no focused tiled window"))
        m.insert(1, LayoutContext(workArea: area))
        #expect(m.neighbor(of: 1, forward: true) == nil)
        #expect(m.message("cyclenext", LayoutContext(workArea: area, focused: 1)) == .ok)
        #expect(m.message("bogus", LayoutContext(workArea: area, focused: 1)) == .error("unknown monocle layout message 'bogus'"))
        #expect(m.moveWindow(9, .left, LayoutContext(workArea: area)) == false)
        m.insert(2, LayoutContext(workArea: area))
        #expect(m.moveWindow(1, .up, LayoutContext(workArea: area)) == false)
        #expect(m.message("cycleprev", LayoutContext(workArea: area, focused: 1)) == .focus(2))
        #expect(m.nextFocusCandidate(near: .zero, LayoutContext(workArea: area)) == 2)
        m.swap(1, 2)
        #expect(m.windowIDs == [2, 1])
        m.remove(2)
        #expect(m.windowIDs == [1])
    }

    @Test func resizeMovesMfactAndStackSizes() {
        var m = master(3)
        m.resize(1, by: Point(x: 100, y: 0), corner: .none, mctx(1))
        #expect(m.tileBoxes(mctx())[1]?.width == 650)
        m.resize(2, by: Point(x: 0, y: 150), corner: .none, mctx(2))
        let b = m.tileBoxes(mctx())
        #expect(b[2] == Rect(x: 650, y: 0, width: 350, height: 360))
        #expect(b[3] == Rect(x: 650, y: 360, width: 350, height: 240))
    }

    @Test func moveWindowSwapsWithNeighbour() {
        var m = master(3)
        #expect(m.moveWindow(3, .left, mctx(3)) == true)
        #expect(m.tileBoxes(mctx())[3] == Rect(x: 0, y: 0, width: 550, height: 600))
        #expect(m.moveWindow(3, .left, mctx(3)) == false)
    }

    @Test func monocle() {
        var m = MonocleLayout()
        m.insert(1, LayoutContext(workArea: area))
        m.insert(2, LayoutContext(workArea: area, focused: 1))
        m.insert(3, LayoutContext(workArea: area, focused: 1))
        #expect(m.windowIDs == [1, 3, 2])
        #expect(Set(m.tileBoxes(LayoutContext(workArea: area)).values) == [area])
        #expect(m.neighbor(of: 2, forward: true) == 1)
        #expect(m.neighbor(of: 1, forward: false) == 2)
        #expect(m.message("cyclenext", LayoutContext(workArea: area, focused: 3)) == .focus(2))
        #expect(m.moveWindow(3, .right, LayoutContext(workArea: area)) == true)
        #expect(m.windowIDs == [1, 2, 3])
        #expect(m.moveWindow(3, .right, LayoutContext(workArea: area)) == false)
    }
}
