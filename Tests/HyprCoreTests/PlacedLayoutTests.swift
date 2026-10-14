import Testing
@testable import HyprCore

func ownerWorld(windows count: Int = 3, extra: String = "") -> World {
    let w = world("general:gaps_in = 4\ndwindle:preserve_split = true\nworkspace = 1, gapsout:20\n" + extra)
    for id in 1 ... count { _ = w.handle(.windowAppeared(snap(WindowID(id), pid: Int32(id) * 100))) }
    _ = w.run(.focusWindow(.address(1)))
    return w
}

func placeOwner(_ w: World, width: Double, x: Double, height: Double = 100, y: Double = 0) -> CommandResult {
    place(w, .percent(width), .percent(height), .percent(x), .percent(y))
}

func overlap(_ a: Rect, _ b: Rect) -> Bool { min(a.maxX, b.maxX) - max(a.minX, b.minX) > 0 && min(a.maxY, b.maxY) - max(a.minY, b.minY) > 0 }

let workArea20 = Rect(x: 20, y: 52, width: 1472, height: 910)

@Suite struct PlacedLayoutTests {
    @Test func leftThirdLeavesTheRightTwoThirdsToTheOthers() {
        let w = ownerWorld()
        let before = tileFrames(w)
        let r = placeOwner(w, width: 33.33, x: 0)
        #expect(!r.isError)
        let expected: [WindowID: Rect] = [
            1: Rect(x: 20, y: 52, width: 491, height: 910),
            2: Rect(x: 519, y: 52, width: 973, height: 451),
            3: Rect(x: 519, y: 511, width: 973, height: 451),
        ]
        #expect(frames(r.effects) == expected)
        #expect(tileFrames(w) == expected)
        #expect(tileFrames(w) != before)
        #expect(w.windows[1]?.isFloating == false && w.workspaces[1]?.floating == [])
        #expect(w.windows[1]?.placedFrame == expected[1])
    }

    @Test func centerThirdGivesTheLeftStripToTheFirstAndTheRightStripToTheSecond() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 33.33, x: 33.33)
        #expect(tileFrames(w) == [
            1: Rect(x: 511, y: 52, width: 491, height: 910),
            2: Rect(x: 20, y: 52, width: 483, height: 910),
            3: Rect(x: 1010, y: 52, width: 482, height: 910),
        ])
    }

    @Test func leftHalfLetsTheOthersShareTheRightHalf() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 50, x: 0)
        #expect(tileFrames(w) == [
            1: Rect(x: 20, y: 52, width: 736, height: 910),
            2: Rect(x: 764, y: 52, width: 728, height: 451),
            3: Rect(x: 764, y: 511, width: 728, height: 451),
        ])
    }

    @Test func spacingNextToThePlacedWindowMatchesNormalTiling() {
        let normal = ownerWorld()
        let a = normal.windows[1]!.appliedFrame!, b = normal.windows[2]!.appliedFrame!
        let normalGap = b.minX - a.maxX
        let w = ownerWorld()
        _ = placeOwner(w, width: 50, x: 0)
        #expect(tileFrames(w)[2]!.minX - tileFrames(w)[1]!.maxX == normalGap)
        #expect(normalGap == 8)
    }

    @Test func fourOthersWithACenterPlacementAlternateBetweenTheStripsAndStack() {
        let w = ownerWorld(windows: 5)
        let order = w.workspaces[1]!.tiledIDs.filter { $0 != 1 }
        #expect(order.count == 4)
        _ = placeOwner(w, width: 33.33, x: 33.33)
        let f = tileFrames(w)
        #expect(f[1] == Rect(x: 511, y: 52, width: 491, height: 910))
        #expect(f[order[0]] == Rect(x: 20, y: 52, width: 483, height: 451))
        #expect(f[order[2]] == Rect(x: 20, y: 511, width: 483, height: 451))
        #expect(f[order[1]] == Rect(x: 1010, y: 52, width: 482, height: 451))
        #expect(f[order[3]] == Rect(x: 1010, y: 511, width: 482, height: 451))
    }

    @Test func aNewWindowTilesInTheFreeAreaAndThePlacedWindowDoesNotMove() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 33.33, x: 0)
        let placed = w.windows[1]!.placedFrame!
        let open = w.handle(.windowAppeared(snap(4, pid: 400)))
        #expect(frames(open)[1] == nil)
        #expect(w.windows[1]?.placedFrame == placed && w.windows[1]?.appliedFrame == placed)
        let f = tileFrames(w)
        for id: WindowID in 2 ... 4 {
            #expect(f[id] != nil && f[id]!.minX >= 515 && f[id]!.maxX <= 1493 && !overlap(f[id]!, placed))
        }
        let others = [f[2]!, f[3]!, f[4]!]
        #expect(!overlap(others[0], others[1]) && !overlap(others[0], others[2]) && !overlap(others[1], others[2]))
    }

    @Test func aClosingWindowReTilesTheRestInTheFreeArea() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 33.33, x: 0)
        let e = w.handle(.windowDisappeared(3))
        #expect(frames(e) == [2: Rect(x: 519, y: 52, width: 973, height: 910)])
        #expect(w.windows[1]?.placedFrame == Rect(x: 20, y: 52, width: 491, height: 910))
    }

    @Test func closingTheLastOtherWindowLeavesOnlyThePlacedWindow() {
        let w = ownerWorld(windows: 2)
        _ = placeOwner(w, width: 33.33, x: 0)
        _ = w.handle(.windowDisappeared(2))
        #expect(tileFrames(w) == [1: Rect(x: 20, y: 52, width: 491, height: 910)])
    }

    @Test func clearingDispatchersReTileEverythingLikeAWorldThatWasNeverPlaced() {
        let commands: [(String, Command)] = [
            ("settiled", .floating(.unset, .active)),
            ("pseudo", .pseudo(.active)),
            ("fullscreen", .fullscreen(mode: 1, .toggle)),
            ("togglefloating", .floating(.toggle, .active)),
            ("setfloating", .floating(.set, .active)),
            ("movetoworkspace", .moveToWorkspace(.id(2), .active, silent: true)),
            ("movewindow", .moveWindow(.direction(.right), silent: false)),
            ("layoutmsg", .layoutMessage("togglesplit")),
        ]
        for (name, command) in commands {
            let w = ownerWorld()
            _ = placeOwner(w, width: 33.33, x: 0)
            #expect(w.windows[1]?.placedFrame != nil, "\(name)")
            let r = w.run(command)
            #expect(w.windows[1]?.placedFrame == nil, "\(name) \(r.reply)")
            let reference = ownerWorld()
            _ = reference.run(command)
            let visible = { (world: World) in
                tileFrames(world).filter { world.windows[$0.key]?.workspace == 1 && world.windows[$0.key]?.isParked == false }
            }
            #expect(visible(w) == visible(reference), "\(name)")
        }
    }

    @Test func settiledAndTogglefloatingRestoreTheOriginalArrangement() {
        let original = ownerWorld()
        let settiled = ownerWorld()
        _ = placeOwner(settiled, width: 33.33, x: 0)
        let r = settiled.run(.floating(.unset, .active))
        #expect(tileFrames(settiled) == tileFrames(original))
        #expect(frames(r.effects) == tileFrames(original))

        let floated = ownerWorld()
        _ = placeOwner(floated, width: 33.33, x: 0)
        _ = floated.run(.floating(.toggle, .active))
        let reference = ownerWorld()
        _ = reference.run(.floating(.toggle, .active))
        #expect(tileFrames(floated) == tileFrames(reference))
        _ = floated.run(.floating(.toggle, .active))
        #expect(floated.windows[1]?.isFloating == false && floated.windows[1]?.placedFrame == nil)
    }

    @Test func aUserDragOfThePlacedWindowClearsItAndTheDropReTilesEverything() {
        let original = ownerWorld()
        let w = ownerWorld()
        _ = placeOwner(w, width: 33.33, x: 0)
        let a = w.windows[1]!.appliedFrame!
        _ = w.handle(.windowFrameChanged(1, Rect(x: 300, y: 300, width: a.width, height: a.height), userDriven: true))
        #expect(w.windows[1]?.placedFrame == nil)
        _ = w.handle(.dragEnded(cursor: Point(x: 100, y: 500)))
        #expect(tileFrames(w) == tileFrames(original))
    }

    @Test func focusMovesAndWorkspaceSwitchesKeepThePlacement() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 33.33, x: 0)
        let placed = w.windows[1]!.placedFrame
        let toB = w.run(.focusWindow(.address(2)))
        #expect(w.windows[1]?.placedFrame == placed)
        #expect(frames(toB.effects).isEmpty)
        let back = w.run(.focusWindow(.address(1)))
        #expect(w.windows[1]?.placedFrame == placed)
        #expect(frames(back.effects).isEmpty)
        _ = w.handle(.focusChanged(2))
        _ = w.handle(.focusChanged(1))
        #expect(w.windows[1]?.placedFrame == placed)
        let expected = tileFrames(w)
        w.switchWorkspace(2)
        _ = w.handle(.windowAppeared(snap(9, pid: 900)))
        _ = w.takeEffects()
        w.switchWorkspace(1)
        let returned = w.takeEffects()
        #expect(w.windows[1]?.placedFrame == placed)
        #expect(frames(returned)[1] == placed)
        #expect(frames(returned)[2] == expected[2] && frames(returned)[3] == expected[3])
    }

    @Test func aNonFullHeightRectUsesTheLargestStrip() {
        let tall = ownerWorld()
        _ = placeOwner(tall, width: 25, x: 0, height: 50, y: 0)
        #expect(tileFrames(tall) == [
            1: Rect(x: 20, y: 52, width: 368, height: 455),
            2: Rect(x: 396, y: 52, width: 1096, height: 451),
            3: Rect(x: 396, y: 511, width: 1096, height: 451),
        ])
        let wide = ownerWorld()
        _ = placeOwner(wide, width: 100, x: 0, height: 25, y: 0)
        #expect(tileFrames(wide) == [
            1: Rect(x: 20, y: 52, width: 1472, height: 228),
            2: Rect(x: 20, y: 288, width: 1472, height: 331),
            3: Rect(x: 20, y: 627, width: 1472, height: 335),
        ])
    }

    @Test func aNewerOverlappingPlacementClearsTheOlderOne() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 50, x: 0)
        _ = w.run(.focusWindow(.address(2)))
        _ = placeOwner(w, width: 33.33, x: 0)
        #expect(w.windows[1]?.placedFrame == nil)
        #expect(w.windows[2]?.placedFrame == Rect(x: 20, y: 52, width: 491, height: 910))
    }

    @Test func nonOverlappingPlacementsKeepTheMiddleStripForTheRest() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 33.33, x: 0)
        _ = w.run(.focusWindow(.address(2)))
        _ = placeOwner(w, width: 33.33, x: 66.67)
        #expect(w.windows[1]?.placedFrame != nil && w.windows[2]?.placedFrame != nil)
        let f = tileFrames(w)
        #expect(f[3] == Rect(x: 519, y: 52, width: 474, height: 910))
        #expect(!overlap(f[1]!, f[3]!) && !overlap(f[2]!, f[3]!))
    }

    @Test func threeAdjacentThirdsOnThreeWindowsAllStayPlaced() {
        let w = ownerWorld()
        for (id, x) in [(1, 0.0), (2, 33.33), (3, 66.67)] {
            _ = w.run(.focusWindow(.address(WindowID(id))))
            _ = placeOwner(w, width: 33.33, x: x)
        }
        #expect(w.windows.values.allSatisfy { $0.placedFrame != nil })
    }

    @Test func placingAgainOnTheSameWindowReplacesTheRect() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 33.33, x: 0)
        _ = placeOwner(w, width: 50, x: 50)
        #expect(w.windows[1]?.placedFrame == Rect(x: 756, y: 52, width: 736, height: 910))
        #expect(tileFrames(w)[2] == Rect(x: 20, y: 52, width: 728, height: 451))
    }

    @Test func movefocusTreatsThePlacedWindowAsANeighbourByItsRect() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 33.33, x: 0)
        _ = w.run(.moveFocus(.right))
        #expect(w.focusedWindow == 2 || w.focusedWindow == 3)
        _ = w.run(.moveFocus(.left))
        #expect(w.focusedWindow == 1)
        _ = w.run(.focusWindow(.address(3)))
        _ = w.run(.moveFocus(.left))
        #expect(w.focusedWindow == 1)
    }

    @Test func aMonitorChangeDropsPlacementsMadeForTheOldWorkArea() {
        let w = world(monitors: [laptop, ultrawide])
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, pid: 200)))
        _ = place(w, .percent(50), .percent(100), .percent(0), .percent(0))
        #expect(w.windows[2]?.placedFrame != nil)
        _ = w.run(.moveCurrentWorkspaceToMonitor(.id(1)))
        #expect(w.windows[2]?.placedFrame == nil)
        let same = world()
        _ = same.handle(.windowAppeared(snap(1)))
        _ = same.handle(.windowAppeared(snap(2, pid: 200)))
        _ = place(same, .percent(50), .percent(100), .percent(0), .percent(0))
        _ = same.handle(.monitorsChanged([laptop]))
        #expect(same.windows[2]?.placedFrame != nil)
    }

    @Test func movewindowDoesNotReleaseThePlacementWhenNothingMoves() {
        let single = world()
        _ = single.handle(.windowAppeared(snap(1)))
        _ = placeOwner(single, width: 50, x: 0)
        let none = single.run(.moveWindow(.direction(.left), silent: false))
        #expect(!none.isError && single.windows[1]?.placedFrame != nil)
        let bad = single.run(.moveWindow(.monitor(.id(7)), silent: false))
        #expect(bad.isError && single.windows[1]?.placedFrame != nil)
        let same = single.run(.moveWindow(.monitor(.id(0)), silent: false))
        #expect(!same.isError && single.windows[1]?.placedFrame != nil)
    }

    @Test func aRectOutsideTheWorkAreaIsDroppedAndAnOlderPlacementIsCleared() {
        let original = ownerWorld()
        let w = ownerWorld()
        let off = placeOwner(w, width: 33.33, x: 200)
        #expect(off.isError)
        #expect(w.windows[1]?.placedFrame == nil)
        #expect(tileFrames(w) == tileFrames(original))
        _ = placeOwner(w, width: 33.33, x: 0)
        #expect(w.windows[1]?.placedFrame != nil)
        let again = placeOwner(w, width: 33.33, x: 200)
        #expect(again.isError)
        #expect(w.windows[1]?.placedFrame == nil)
        #expect(tileFrames(w) == tileFrames(original))
        let negative = placeOwner(w, width: 33.33, x: -200)
        #expect(negative.isError && w.windows[1]?.placedFrame == nil)
    }

    @Test func aPartlyOutsideRectIsClampedForTheStrips() {
        let w = ownerWorld()
        let r = placeOwner(w, width: 50, x: 75)
        #expect(!r.isError)
        #expect(w.windows[1]?.placedFrame == Rect(x: 1124, y: 52, width: 736, height: 910))
        #expect(tileFrames(w)[2] == Rect(x: 20, y: 52, width: 1096, height: 451))
        #expect(tileFrames(w)[3] == Rect(x: 20, y: 511, width: 1096, height: 451))
        for id: WindowID in [2, 3] {
            let f = tileFrames(w)[id]!
            #expect(f.minX >= workArea20.minX && f.maxX <= workArea20.maxX && f.minY >= workArea20.minY && f.maxY <= workArea20.maxY)
        }
        let spanning = ownerWorld()
        _ = placeOwner(spanning, width: 50, x: 0, height: 200, y: -50)
        for id: WindowID in [2, 3] {
            let f = tileFrames(spanning)[id]!
            #expect(f.minX >= workArea20.minX && f.maxX <= workArea20.maxX && f.minY >= workArea20.minY && f.maxY <= workArea20.maxY)
        }
        #expect(tileFrames(spanning)[2]!.minX >= 760)
    }

    @Test func aReloadThatShrinksTheWorkAreaKeepsTheOthersInsideIt() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 33.33, x: 0)
        _ = w.reload(makeConfig("general:gaps_in = 4\ndwindle:preserve_split = true\nworkspace = 1, gapsout:100"))
        let area = Rect(x: 100, y: 132, width: 1312, height: 750)
        #expect(w.windows[1]?.placedFrame != nil)
        for id: WindowID in [2, 3] {
            let f = tileFrames(w)[id]!
            #expect(f.minX >= area.minX && f.maxX <= area.maxX && f.minY >= area.minY && f.maxY <= area.maxY)
        }
        _ = w.reload(makeConfig("general:gaps_in = 4\ndwindle:preserve_split = true\nworkspace = 1, gapsout:700"))
        #expect(w.windows[1]?.placedFrame == nil)
    }

    @Test func aDirectionalMovewindowTowardThePlacedWindowClearsItFirst() {
        let cases: [(Direction, Bool)] = [(.left, true), (.right, false), (.up, false), (.down, false)]
        for (direction, clears) in cases {
            let w = ownerWorld()
            _ = placeOwner(w, width: 33.33, x: 0)
            _ = w.run(.focusWindow(.address(2)))
            let before = w.windows[1]?.placedFrame
            _ = w.run(.moveWindow(.direction(direction), silent: false))
            #expect((w.windows[1]?.placedFrame == nil) == clears, "\(direction)")
            if clears {
                let reference = ownerWorld()
                _ = reference.run(.focusWindow(.address(2)))
                _ = reference.run(.moveWindow(.direction(direction), silent: false))
                #expect(tileFrames(w) == tileFrames(reference))
            } else {
                #expect(w.windows[1]?.placedFrame == before)
            }
        }
        for (focused, direction) in [(WindowID(3), Direction.left), (WindowID(2), Direction.right)] {
            let w = ownerWorld()
            _ = placeOwner(w, width: 33.33, x: 33.33)
            _ = w.run(.focusWindow(.address(focused)))
            _ = w.run(.moveWindow(.direction(direction), silent: false))
            #expect(w.windows[1]?.placedFrame == nil, "\(focused) \(direction)")
        }
    }

    @Test func aPlacementThatLeavesNoRoomForTheOthersIsClearedAsTheNewest() {
        let original = ownerWorld()
        let full = ownerWorld()
        let r = placeOwner(full, width: 100, x: 0)
        #expect(r.isError && full.windows[1]?.placedFrame == nil)
        #expect(tileFrames(full) == tileFrames(original))

        let w = ownerWorld()
        _ = placeOwner(w, width: 50, x: 0)
        _ = w.run(.focusWindow(.address(2)))
        let second = placeOwner(w, width: 50, x: 50)
        #expect(second.isError)
        #expect(w.windows[2]?.placedFrame == nil && w.windows[1]?.placedFrame != nil)
        #expect(tileFrames(w)[3]!.minX >= 764)
    }

    @Test func aWindowOpeningWhenThePlacedRectsFillTheWidthClearsTheNewestPlacement() {
        let w = ownerWorld()
        for (id, x) in [(1, 0.0), (2, 33.33), (3, 66.67)] {
            _ = w.run(.focusWindow(.address(WindowID(id))))
            _ = placeOwner(w, width: 33.33, x: x)
        }
        #expect(w.windows.values.allSatisfy { $0.placedFrame != nil })
        _ = w.handle(.windowAppeared(snap(4, pid: 400)))
        #expect(w.windows[3]?.placedFrame == nil)
        #expect(w.windows[1]?.placedFrame != nil && w.windows[2]?.placedFrame != nil)
        let f = tileFrames(w)
        #expect(f[3]!.minX >= 1010 && f[4]!.minX >= 1010)
        #expect(!overlap(f[3]!, f[4]!) && !overlap(f[1]!, f[3]!) && !overlap(f[2]!, f[4]!))
    }

    @Test func aSingleWindowMayFillTheWholeWorkArea() {
        let w = ownerWorld(windows: 1)
        let r = placeOwner(w, width: 100, x: 0)
        #expect(!r.isError)
        #expect(tileFrames(w) == [1: workArea20])
    }

    @Test func thePlacedWindowClosingReTilesTheRestOverTheFullArea() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 33.33, x: 33.33)
        _ = w.handle(.windowDisappeared(1))
        let reference = ownerWorld()
        _ = reference.handle(.windowDisappeared(1))
        #expect(tileFrames(w) == tileFrames(reference))
        #expect(w.windows[1] == nil)
    }
}
