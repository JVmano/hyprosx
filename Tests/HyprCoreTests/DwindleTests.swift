import Foundation
import Testing
@testable import HyprCore

private let wide = Rect(x: 0, y: 0, width: 800, height: 500)

private func ctx(_ focused: WindowID? = nil, cursor: Point = Point(x: 1e9, y: 1e9), _ edit: (inout DwindleOptions) -> Void = { _ in }) -> LayoutContext {
    var o = DwindleOptions()
    edit(&o)
    return LayoutContext(workArea: wide, focused: focused, cursor: cursor, dwindle: o)
}

private func three(_ edit: (inout DwindleOptions) -> Void = { _ in }) -> DwindleLayout {
    var d = DwindleLayout()
    d.insert(1, ctx(nil, edit))
    d.insert(2, ctx(1, edit))
    d.insert(3, ctx(2, edit))
    return d
}

@Suite struct DwindleTests {
    @Test func firstWindowFillsTheArea() {
        var d = DwindleLayout()
        d.insert(1, ctx())
        #expect(d.tileBoxes(ctx()) == [1: wide])
    }

    @Test func splitsByAspectRatioAndAppendsAfterFocus() {
        let d = three()
        let b = d.tileBoxes(ctx())
        #expect(b[1] == Rect(x: 0, y: 0, width: 400, height: 500))
        #expect(b[2] == Rect(x: 400, y: 0, width: 400, height: 250))
        #expect(b[3] == Rect(x: 400, y: 250, width: 400, height: 250))
        #expect(d.windowIDs == [1, 2, 3])
    }

    @Test func squareBoxSplitsSideBySideAfterRecalc() {
        var d = DwindleLayout()
        let square = LayoutContext(workArea: Rect(x: 0, y: 0, width: 500, height: 500))
        d.insert(1, square)
        var c = square
        c.focused = 1
        d.insert(2, c)
        #expect(d.tileBoxes(square)[2] == Rect(x: 250, y: 0, width: 250, height: 500))
    }

    @Test func cursorInFirstHalfPutsNewWindowFirst() {
        var d = DwindleLayout()
        d.insert(1, ctx())
        d.insert(2, ctx(1, cursor: Point(x: 100, y: 100)))
        #expect(d.tileBoxes(ctx())[2] == Rect(x: 0, y: 0, width: 400, height: 500))
    }

    @Test func forceSplit() {
        var first = DwindleLayout()
        first.insert(1, ctx { $0.forceSplit = 1 })
        first.insert(2, ctx(1) { $0.forceSplit = 1 })
        #expect(first.windowIDs == [2, 1])
        var second = DwindleLayout()
        second.insert(1, ctx { $0.forceSplit = 2 })
        second.insert(2, ctx(1, cursor: Point(x: 10, y: 10)) { $0.forceSplit = 2 })
        #expect(second.windowIDs == [1, 2])
    }

    @Test func smartSplitUsesCursorTriangle() {
        var d = DwindleLayout()
        d.insert(1, ctx { $0.smartSplit = true })
        d.insert(2, ctx(1, cursor: Point(x: 400, y: 20)) { $0.smartSplit = true })
        let b = d.tileBoxes(ctx { $0.smartSplit = true })
        #expect(b[2] == Rect(x: 0, y: 0, width: 800, height: 250))
    }

    @Test func splitBiasKeepsExistingWindowLarger() {
        var d = DwindleLayout()
        let opts: (inout DwindleOptions) -> Void = { $0.splitBias = 1; $0.defaultSplitRatio = 1.2; $0.forceSplit = 1 }
        d.insert(1, ctx(nil, opts))
        d.insert(2, ctx(1, opts))
        let b = d.tileBoxes(ctx(nil, opts))
        #expect(b[2] == Rect(x: 0, y: 0, width: 320, height: 500))
        #expect(b[1] == Rect(x: 320, y: 0, width: 480, height: 500))
    }

    @Test func removalPromotesSibling() {
        var d = three()
        d.remove(2)
        #expect(d.tileBoxes(ctx()) == [1: Rect(x: 0, y: 0, width: 400, height: 500), 3: Rect(x: 400, y: 0, width: 400, height: 500)])
        d.remove(1)
        #expect(d.tileBoxes(ctx()) == [3: wide])
        d.remove(3)
        #expect(d.windowIDs.isEmpty)
    }

    @Test func splitRatioMessage() {
        var d = three()
        #expect(d.message("splitratio exact 1.5", ctx(1)) == .ok)
        #expect(d.tileBoxes(ctx())[1]?.width == 600)
        #expect(d.message("splitratio -0.5", ctx(1)) == .ok)
        #expect(d.tileBoxes(ctx())[1]?.width == 400)
        #expect(d.message("splitratio exact 5", ctx(1)) == .ok)
        #expect(d.tileBoxes(ctx())[1]?.width == 760)
    }

    @Test func smartResizeMovesTheSplitLine() {
        var d = three()
        d.resize(1, by: Point(x: 100, y: 0), corner: .none, ctx())
        #expect(d.tileBoxes(ctx())[1]?.width == 500)
        d.resize(3, by: Point(x: 0, y: 50), corner: .none, ctx())
        #expect(d.tileBoxes(ctx())[3] == Rect(x: 500, y: 300, width: 300, height: 200))
    }

    @Test func toggleSplitNeedsPreserveSplit() {
        var plain = three()
        #expect(plain.message("togglesplit", ctx(2)) == .ok)
        #expect(plain.tileBoxes(ctx())[2] == Rect(x: 400, y: 0, width: 400, height: 250))
        var kept = three { $0.preserveSplit = true }
        #expect(kept.message("togglesplit", ctx(2) { $0.preserveSplit = true }) == .ok)
        #expect(kept.tileBoxes(ctx { $0.preserveSplit = true })[2] == Rect(x: 400, y: 0, width: 200, height: 500))
    }

    @Test func swapSplitAndRotate() {
        var d = three { $0.preserveSplit = true }
        let c = ctx(2) { $0.preserveSplit = true }
        #expect(d.message("swapsplit", c) == .ok)
        #expect(d.windowIDs == [1, 3, 2])
        #expect(d.message("rotatesplit", c) == .ok)
        #expect(d.tileBoxes(c)[2] == Rect(x: 400, y: 0, width: 200, height: 500))
    }

    @Test func preselectForcesNextSplit() {
        var d = DwindleLayout()
        d.insert(1, ctx())
        #expect(d.message("preselect d", ctx(1)) == .ok)
        d.insert(2, ctx(1))
        #expect(d.tileBoxes(ctx())[2] == Rect(x: 0, y: 250, width: 800, height: 250))
    }

    @Test func moveWindowLeftSwapsWithLeafSibling() {
        var d = DwindleLayout()
        d.insert(1, ctx())
        d.insert(2, ctx(1))
        #expect(d.moveWindow(2, .left, ctx(2)) == true)
        #expect(d.windowIDs == [2, 1])
        #expect(d.moveWindow(2, .left, ctx(2)) == false)
    }

    @Test func moveToRoot() {
        var d = three { $0.preserveSplit = true }
        #expect(d.message("movetoroot", ctx(3) { $0.preserveSplit = true }) == .ok)
        #expect(d.windowIDs == [2, 1, 3])
        #expect(d.tileBoxes(ctx { $0.preserveSplit = true })[3] == Rect(x: 400, y: 0, width: 400, height: 500))
    }

    @Test func nextFocusCandidateIsClosest() {
        let d = three()
        #expect(d.nextFocusCandidate(near: Point(x: 700, y: 400), ctx()) == 3)
        #expect(d.nextFocusCandidate(near: Point(x: 10, y: 10), ctx()) == 1)
    }

    @Test func codableRoundTrip() throws {
        let d = three()
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(DwindleLayout.self, from: data)
        #expect(back == d)
        #expect(back.tileBoxes(ctx()) == d.tileBoxes(ctx()))
    }

    @Test func directionalMoveStoresForcedSplit() {
        var d = DwindleLayout()
        d.insert(1, ctx())
        d.insert(2, ctx(1))
        #expect(d.moveWindow(2, .left, ctx(2)) == true)
        let root = d.root.flatMap { d.nodes[$0] }
        #expect(root?.forced == true)
        #expect(root?.splitTop == false)
    }

    @Test func extremeOptionsKeepBoxesFinite() {
        for multiplier in [0.0, 1e-300, 1e300, -1e300, .nan, .infinity] {
            for ratio in [-1e300, 0.0, 1e300, .nan] {
                for smart in [true, false] {
                    let edit: (inout DwindleOptions) -> Void = {
                        $0.splitWidthMultiplier = multiplier
                        $0.defaultSplitRatio = ratio
                        $0.smartResizing = smart
                    }
                    var d = three(edit)
                    d.resize(2, by: Point(x: 1e300, y: -1e300), corner: .none, ctx(nil, edit))
                    d.resize(3, by: Point(x: -1e300, y: 1e300), corner: .bottomRight, ctx(nil, edit))
                    let boxes = d.tileBoxes(ctx(nil, edit))
                    #expect(boxes.count == 3)
                    for b in boxes.values {
                        #expect([b.x, b.y, b.width, b.height].allSatisfy { $0.isFinite })
                        #expect(b.width >= 0 && b.height >= 0)
                        #expect(b.minX >= 0 && b.minY >= 0 && b.maxX <= 800 + 1e-6 && b.maxY <= 500 + 1e-6)
                    }
                }
            }
        }
    }

    @Test func nonFiniteInputsAreRejectedOrIgnored() {
        var d = three()
        let before = d.tileBoxes(ctx())
        #expect(d.message("splitratio nan", ctx(1)) == .error("invalid splitratio"))
        #expect(d.message("splitratio exact inf", ctx(1)) == .error("invalid splitratio"))
        d.resize(1, by: Point(x: .nan, y: .infinity), corner: .none, ctx())
        #expect(d.tileBoxes(ctx()) == before)
        d.resize(1, by: Point(x: 1e300, y: 0), corner: .none, ctx())
        #expect(d.tileBoxes(ctx())[1]?.width == 760)
    }
}
