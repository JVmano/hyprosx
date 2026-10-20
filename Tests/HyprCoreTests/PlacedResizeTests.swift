import Testing
@testable import HyprCore

private func grow(_ w: World, _ id: WindowID, _ dx: Double, _ dy: Double = 0) -> CommandResult {
    w.run(.resizeWindow(.relative(.pixels(dx), .pixels(dy)), .address(id)))
}

private func centerPlaced(windows: Int = 3) -> World {
    let w = ownerWorld(windows: windows)
    _ = placeOwner(w, width: 33.33, x: 33.33)
    return w
}

private func leftPlaced(windows: Int = 3) -> World {
    let w = ownerWorld(windows: windows)
    _ = placeOwner(w, width: 33.33, x: 0)
    return w
}

@Suite struct PlacedResizeTests {
    @Test func growingACenterPlacementSplitsTheDeltaAndNarrowsBothStrips() {
        let w = centerPlaced()
        let r = w.run(.resizeActive(.relative(.pixels(100), .pixels(0))))
        #expect(!r.isError)
        let expected: [WindowID: Rect] = [
            1: Rect(x: 461, y: 52, width: 591, height: 910),
            2: Rect(x: 20, y: 52, width: 433, height: 910),
            3: Rect(x: 1060, y: 52, width: 432, height: 910),
        ]
        #expect(frames(r.effects) == expected)
        #expect(tileFrames(w) == expected)
        #expect(w.windows[1]?.placedFrame == expected[1])
    }

    @Test func shrinkingACenterPlacementWidensBothStrips() {
        let w = centerPlaced()
        _ = w.run(.resizeActive(.relative(.pixels(-100), .pixels(0))))
        #expect(tileFrames(w)[1] == Rect(x: 561, y: 52, width: 391, height: 910))
        #expect(tileFrames(w)[2] == Rect(x: 20, y: 52, width: 533, height: 910))
        #expect(tileFrames(w)[3] == Rect(x: 960, y: 52, width: 532, height: 910))
    }

    @Test func growingALeftPlacementMovesOnlyItsRightEdge() {
        let w = leftPlaced()
        let r = w.run(.resizeActive(.relative(.pixels(100), .pixels(0))))
        #expect(!r.isError)
        let f = tileFrames(w)
        #expect(f[1] == Rect(x: 20, y: 52, width: 591, height: 910))
        #expect(f[2] == Rect(x: 619, y: 52, width: 873, height: 451))
        #expect(f[3] == Rect(x: 619, y: 511, width: 873, height: 451))
        #expect(frames(r.effects) == f)
    }

    @Test func growingARightPlacementMovesOnlyItsLeftEdge() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 33.33, x: 66.67)
        let before = w.windows[1]!.placedFrame!
        _ = w.run(.resizeActive(.relative(.pixels(100), .pixels(0))))
        let after = w.windows[1]!.placedFrame!
        #expect(after.maxX == before.maxX && after.width == before.width + 100)
    }

    @Test func anExactWidthSetsThePlacementWidthWithTheSameAnchoring() {
        let w = leftPlaced()
        _ = w.run(.resizeActive(.exact(.percent(50), .percent(100))))
        #expect(w.windows[1]?.placedFrame == Rect(x: 20, y: 52, width: 736, height: 910))
        let c = centerPlaced()
        _ = c.run(.resizeActive(.exact(.pixels(591), .pixels(910))))
        #expect(c.windows[1]?.placedFrame == Rect(x: 461, y: 52, width: 591, height: 910))
    }

    @Test func aFullHeightPlacementIgnoresDy() {
        let w = centerPlaced()
        let before = tileFrames(w)
        let r = w.run(.resizeActive(.relative(.pixels(0), .pixels(100))))
        #expect(!r.isError && frames(r.effects).isEmpty)
        #expect(tileFrames(w) == before)
        #expect(w.windows[1]?.placedFrame != nil)
    }

    @Test func aFullWidthPlacementIgnoresDx() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 100, x: 0, height: 25, y: 0)
        let before = w.windows[1]!.placedFrame!
        _ = w.run(.resizeActive(.relative(.pixels(100), .pixels(0))))
        #expect(w.windows[1]?.placedFrame == before)
    }

    @Test func aTopLeftPlacementGrowsRightAndDownOnly() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 25, x: 0, height: 50, y: 0)
        _ = w.run(.resizeActive(.relative(.pixels(100), .pixels(100))))
        #expect(w.windows[1]?.placedFrame == Rect(x: 20, y: 52, width: 468, height: 555))
    }

    @Test func aBottomRightPlacementGrowsLeftAndUpOnly() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 25, x: 75, height: 50, y: 50)
        let before = w.windows[1]!.placedFrame!
        _ = w.run(.resizeActive(.relative(.pixels(100), .pixels(100))))
        let after = w.windows[1]!.placedFrame!
        #expect(after.maxX == before.maxX && after.maxY == before.maxY)
        #expect(after.width == before.width + 100 && after.height == before.height + 100)
    }

    @Test func shrinkingStopsAtOneHundredPoints() {
        let w = leftPlaced()
        _ = w.run(.resizeActive(.relative(.pixels(-2000), .pixels(0))))
        #expect(w.windows[1]?.placedFrame == Rect(x: 20, y: 52, width: 100, height: 910))
        let c = centerPlaced()
        _ = c.run(.resizeActive(.relative(.pixels(-2000), .pixels(0))))
        #expect(c.windows[1]?.placedFrame == Rect(x: 707, y: 52, width: 100, height: 910))
        let t = ownerWorld()
        _ = placeOwner(t, width: 25, x: 0, height: 50, y: 0)
        _ = t.run(.resizeActive(.relative(.pixels(0), .pixels(-2000))))
        #expect(t.windows[1]?.placedFrame?.height == 100)
    }

    @Test func growingStopsWhereTheStripsKeepOneHundredPointFrames() {
        let w = leftPlaced()
        _ = w.run(.resizeActive(.relative(.pixels(2000), .pixels(0))))
        let f = tileFrames(w)
        #expect(w.windows[1]?.placedFrame != nil)
        #expect(f[1] == Rect(x: 20, y: 52, width: 1364, height: 910))
        #expect(f[2]?.width == 100 && f[3]?.width == 100)

        let c = centerPlaced()
        _ = c.run(.resizeActive(.relative(.pixels(2000), .pixels(0))))
        let g = tileFrames(c)
        #expect(g[1] == Rect(x: 128, y: 52, width: 1256, height: 910))
        #expect(g[2]?.width == 100 && g[3]?.width == 100)
    }

    @Test func theStripLimitCountsTheBorder() {
        let w = ownerWorld(extra: "general:border_size = 2\n")
        _ = placeOwner(w, width: 33.33, x: 0)
        _ = w.run(.resizeActive(.relative(.pixels(2000), .pixels(0))))
        let f = tileFrames(w)
        #expect(f[2]?.width == 100 && f[3]?.width == 100)
    }

    @Test func anEmptyStripDoesNotLimitTheGrowth() {
        let w = centerPlaced(windows: 2)
        _ = w.run(.resizeActive(.relative(.pixels(2000), .pixels(0))))
        #expect(w.windows[1]?.placedFrame == Rect(x: 128, y: 52, width: 1364, height: 910))
        #expect(w.windows[2]?.appliedFrame?.width == 100)
    }

    @Test func aLeftStripWindowMovesTheLeftEdgeOfThePlacement() {
        let w = centerPlaced()
        let r = grow(w, 2, 60)
        #expect(!r.isError)
        let f = tileFrames(w)
        #expect(f[1] == Rect(x: 571, y: 52, width: 431, height: 910))
        #expect(f[2] == Rect(x: 20, y: 52, width: 543, height: 910))
        #expect(f[3] == Rect(x: 1010, y: 52, width: 482, height: 910))
        #expect(frames(r.effects) == [1: f[1]!, 2: f[2]!])
    }

    @Test func aRightStripWindowMovesTheRightEdgeOfThePlacement() {
        let w = centerPlaced()
        _ = grow(w, 3, 60)
        let f = tileFrames(w)
        #expect(f[1] == Rect(x: 511, y: 52, width: 431, height: 910))
        #expect(f[2] == Rect(x: 20, y: 52, width: 483, height: 910))
        #expect(f[3] == Rect(x: 950, y: 52, width: 542, height: 910))
    }

    @Test func shrinkingAStripWindowGrowsThePlacement() {
        let w = centerPlaced()
        _ = grow(w, 2, -60)
        #expect(w.windows[1]?.placedFrame == Rect(x: 451, y: 52, width: 551, height: 910))
    }

    @Test func aStripWindowNextToALeftPlacementMovesItsRightEdge() {
        let w = leftPlaced()
        _ = grow(w, 2, 60)
        let f = tileFrames(w)
        #expect(f[1] == Rect(x: 20, y: 52, width: 431, height: 910))
        #expect(f[2]?.minX == 459 && f[3]?.minX == 459)
    }

    @Test func aStripWindowStopsAtTheMinimumPlacementSize() {
        let w = centerPlaced()
        _ = grow(w, 2, 5000)
        #expect(w.windows[1]?.placedFrame == Rect(x: 902, y: 52, width: 100, height: 910))
    }

    @Test func dyOnAStripWindowResizesTheSplitInsideASingleStrip() {
        let w = leftPlaced()
        let placed = w.windows[1]!.placedFrame
        let before = tileFrames(w)
        _ = grow(w, 2, 0, 50)
        let f = tileFrames(w)
        #expect(w.windows[1]?.placedFrame == placed && f[1] == before[1])
        #expect(f[2]!.height > before[2]!.height && f[3]!.height < before[3]!.height)
        #expect(f[2]!.height + f[3]!.height == before[2]!.height + before[3]!.height)
    }

    @Test func dyOnAStackedRoundRobinStripWindowChangesNothing() {
        let w = centerPlaced(windows: 5)
        let before = tileFrames(w)
        let other = w.workspaces[1]!.tiledIDs.first { $0 != 1 }!
        let r = grow(w, other, 0, 60)
        #expect(!r.isError && frames(r.effects).isEmpty)
        #expect(tileFrames(w) == before)
    }

    @Test func resizeWindowPixelOnThePlacedWindowAdjustsItLikeResizeActive() {
        let a = centerPlaced()
        let b = centerPlaced()
        _ = a.run(.resizeActive(.relative(.pixels(100), .pixels(0))))
        _ = grow(b, 1, 100)
        #expect(tileFrames(a) == tileFrames(b))
    }

    @Test func aResizeNeverClearsThePlacementAndKeepsOtherPlacements() {
        let w = ownerWorld(windows: 4)
        _ = w.run(.focusWindow(.address(2)))
        _ = placeOwner(w, width: 33.33, x: 0)
        _ = w.run(.focusWindow(.address(1)))
        _ = placeOwner(w, width: 33.33, x: 66.67)
        let left = w.windows[2]!.placedFrame!
        _ = w.run(.resizeActive(.relative(.pixels(2000), .pixels(0))))
        #expect(w.windows[1]?.placedFrame != nil && w.windows[2]?.placedFrame == left)
        #expect(w.windows[1]!.placedFrame!.minX >= left.maxX)
    }
}
