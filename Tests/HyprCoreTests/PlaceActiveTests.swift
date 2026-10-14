import Testing
import Foundation
@testable import HyprCore

func place(_ w: World, _ width: Measure, _ height: Measure, _ x: Measure, _ y: Measure) -> CommandResult {
    w.run(.placeActive(width, height, x, y))
}

let leftThird = Rect(x: 0, y: 32, width: 504, height: 950)

func placeThird(_ w: World) -> CommandResult {
    place(w, .percent(33.33), .percent(100), .pixels(0), .pixels(0))
}

func placeRightHalf(_ w: World) -> CommandResult {
    place(w, .percent(50), .percent(100), .percent(50), .pixels(0))
}

func tileFrames(_ w: World) -> [WindowID: Rect] {
    Dictionary(uniqueKeysWithValues: w.windows.compactMap { id, win in win.appliedFrame.map { (id, $0) } })
}

@Suite struct PlaceActiveParserTests {
    @Test func parsesFourMeasures() {
        #expect(CommandParser.parse(dispatcher: "placeactive", arguments: "33.33% 100% 0 0")
            == .success(.placeActive(.percent(33.33), .percent(100), .pixels(0), .pixels(0))))
        #expect(CommandParser.parse(dispatcher: "placeactive", arguments: "50% 100% 50% 660")
            == .success(.placeActive(.percent(50), .percent(100), .percent(50), .pixels(660))))
    }

    @Test func rejectsBadArguments() {
        for bad in ["", "1 2 3", "1 2 3 4 5", "a b c d", "1 2 3 x%", "nan 1 2 3", "1 inf 2 3", "1 2 -inf 3", "1e999 1 2 3", "exact 1 2 3 4"] {
            #expect(CommandParser.parse(dispatcher: "placeactive", arguments: bad) == .failure(CommandError("Invalid argument for placeactive: \(bad)")), "\(bad)")
        }
    }
}

@Suite struct PlaceActiveTests {
    @Test func placingATiledWindowEmitsOnlyItsFrameAndKeepsTheLayout() {
        let w = threeWindows()
        let layout = w.workspaces[1]?.layout
        let others = tileFrames(w).filter { $0.key != 3 }
        let r = placeThird(w)
        #expect(!r.isError)
        #expect(frames(r.effects) == [3: leftThird])
        #expect(w.workspaces[1]?.layout == layout)
        #expect(w.windows[3]?.isFloating == false)
        #expect(w.workspaces[1]?.floating == [])
        #expect(tileFrames(w).filter { $0.key != 3 } == others)
        #expect(w.windows[3]?.placedFrame == leftThird)
    }

    @Test func theAppEchoingThePlacedFrameChangesNothing() {
        let w = threeWindows()
        _ = placeThird(w)
        let echo = w.handle(.windowFrameChanged(3, leftThird, userDriven: false))
        #expect(echo.isEmpty)
        #expect(w.windows[3]?.placedFrame != nil)
    }

    @Test func ownerValuesGiveTheExactThirdsAndHalvesWithGapsOut10() {
        let w = world("general:gaps_out = 10")
        _ = w.handle(.windowAppeared(snap(1)))
        let thirds: [(Measure, Rect)] = [
            (.percent(0), Rect(x: 10, y: 42, width: 497, height: 930)),
            (.percent(33.33), Rect(x: 507, y: 42, width: 497, height: 930)),
            (.percent(66.67), Rect(x: 1005, y: 42, width: 497, height: 930)),
        ]
        for (x, expected) in thirds {
            #expect(frames(place(w, .percent(33.33), .percent(100), x, .pixels(0)).effects)[1] == expected)
        }
        #expect(frames(place(w, .percent(50), .percent(100), .percent(0), .pixels(0)).effects)[1] == Rect(x: 10, y: 42, width: 746, height: 930))
        #expect(frames(place(w, .percent(50), .percent(100), .percent(50), .pixels(0)).effects)[1] == Rect(x: 756, y: 42, width: 746, height: 930))
    }

    @Test func ownerValuesGiveTheExactThirdsAndHalvesWithTheWorkspaceRuleGapsOut20() {
        let w = world("workspace = 1, gapsout:20")
        _ = w.handle(.windowAppeared(snap(1)))
        let thirds: [(Measure, Rect)] = [
            (.percent(0), Rect(x: 20, y: 52, width: 491, height: 910)),
            (.percent(33.33), Rect(x: 511, y: 52, width: 491, height: 910)),
            (.percent(66.67), Rect(x: 1001, y: 52, width: 491, height: 910)),
        ]
        for (x, expected) in thirds {
            #expect(frames(place(w, .percent(33.33), .percent(100), x, .pixels(0)).effects)[1] == expected)
        }
        #expect(frames(place(w, .percent(50), .percent(100), .percent(0), .pixels(0)).effects)[1] == Rect(x: 20, y: 52, width: 736, height: 910))
        #expect(frames(place(w, .percent(50), .percent(100), .percent(50), .pixels(0)).effects)[1] == Rect(x: 756, y: 52, width: 736, height: 910))
    }

    @Test func openingClosingAndResizingReturnThePlacedWindowToItsTile() {
        func scenario(_ change: (World) -> Void) -> (World, World) {
            let placed = threeWindows(), plain = threeWindows()
            _ = placeThird(placed)
            change(placed)
            change(plain)
            return (placed, plain)
        }
        let changes: [(World) -> Void] = [
            { _ = $0.handle(.windowAppeared(snap(4, pid: 400))) },
            { _ = $0.handle(.windowDisappeared(1)) },
            { _ = $0.run(.resizeWindow(.relative(.pixels(60), .pixels(0)), .address(1))) },
        ]
        for change in changes {
            let (placed, plain) = scenario(change)
            #expect(placed.windows[3]?.placedFrame == nil)
            #expect(tileFrames(placed) == tileFrames(plain))
        }
    }

    @Test func aTileBoxChangeEmitsTheTileFrameForThePlacedWindow() {
        let w = twoWindows()
        _ = placeThird(w)
        let open = w.handle(.windowAppeared(snap(3, pid: 300)))
        let reference = twoWindows()
        let referenceOpen = reference.handle(.windowAppeared(snap(3, pid: 300)))
        #expect(frames(open) == frames(referenceOpen))
    }

    @Test func movingFocusIntoThePlacedWindowReturnsItToItsTile() {
        let w = twoWindows()
        _ = placeThird(w)
        _ = w.run(.focusWindow(.address(1)))
        #expect(w.windows[2]?.placedFrame != nil)
        let back = w.run(.focusWindow(.address(2)))
        #expect(w.windows[2]?.placedFrame == nil)
        #expect(frames(back.effects)[2] == rightHalf)
    }

    @Test func aNativeFocusEventIntoThePlacedWindowReturnsItToItsTileButARepeatDoesNot() {
        let w = twoWindows()
        _ = placeThird(w)
        _ = w.handle(.focusChanged(2))
        #expect(w.windows[2]?.placedFrame != nil)
        _ = w.handle(.focusChanged(1))
        let click = w.handle(.focusChanged(2))
        #expect(w.windows[2]?.placedFrame == nil)
        #expect(frames(click)[2] == rightHalf)
    }

    @Test func dispatchersActingOnThePlacedWindowReturnItToItsTile() {
        let commands: [Command] = [
            .floating(.toggle, .active), .floating(.set, .active), .floating(.unset, .active), .fullscreen(mode: 0, .toggle),
            .fullscreen(mode: 1, .toggle), .pseudo(.active), .moveWindow(.direction(.left), silent: false), .swapWindow(.direction(.left)),
            .resizeActive(.relative(.pixels(40), .pixels(0))), .resizeActive(.relative(.pixels(0), .pixels(0))),
            .resizeActive(.exact(.percent(40), .percent(100))), .layoutMessage("togglesplit"),
            .moveToWorkspace(.id(2), .active, silent: false), .moveWindow(.monitor(.relative(1)), silent: true),
        ]
        for command in commands {
            let w = world(monitors: [laptop, ultrawide])
            _ = w.handle(.windowAppeared(snap(1)))
            _ = w.handle(.windowAppeared(snap(2, pid: 200)))
            _ = placeThird(w)
            #expect(w.windows[2]?.placedFrame != nil)
            let r = w.run(command)
            #expect(w.windows[2]?.placedFrame == nil, "\(command) \(r.reply)")
            #expect(w.windows[2]?.placedSlot == nil)
        }
    }

    @Test func settingTiledOnAPlacedTiledWindowSnapsItBack() {
        let w = twoWindows()
        _ = placeThird(w)
        let r = w.run(.floating(.unset, .active))
        #expect(frames(r.effects)[2] == rightHalf)
        #expect(w.windows[2]?.isFloating == false)
    }

    @Test func togglingFloatingTwiceLeavesNoOverride() {
        let w = twoWindows()
        _ = placeThird(w)
        _ = w.run(.floating(.toggle, .active))
        #expect(w.windows[2]?.isFloating == true)
        let back = w.run(.floating(.toggle, .active))
        #expect(frames(back.effects)[2] == rightHalf)
        #expect(w.windows[2]?.placedFrame == nil)
    }

    @Test func aUserDragClearsTheOverrideAndTheDropSnapsIntoTheTile() {
        let w = twoWindows()
        _ = placeThird(w)
        _ = w.handle(.windowFrameChanged(2, Rect(x: 800, y: 300, width: 504, height: 950), userDriven: true))
        #expect(w.windows[2]?.placedFrame == nil)
        let end = w.handle(.dragEnded(cursor: Point(x: 1300, y: 800)))
        #expect(frames(end)[2] == rightHalf)
        #expect(w.windows[2]?.appliedFrame == rightHalf)
    }

    @Test func switchingAwayAndBackKeepsTheOverrideAndParkingToo() {
        let w = twoWindows()
        _ = placeThird(w)
        let placed = w.windows[2]!.placedFrame
        w.switchWorkspace(2)
        _ = w.handle(.windowAppeared(snap(3, pid: 300)))
        #expect(w.focusedWindow == 3)
        _ = w.takeEffects()
        w.switchWorkspace(1)
        let back = w.takeEffects()
        #expect(w.focusedWindow == 2)
        #expect(w.windows[2]?.placedFrame == placed)
        #expect(frames(back)[2] == placed)
        #expect(frames(back)[1] == leftHalf)
    }

    @Test func placingAFloatingWindowSetsItsFloatingFrameLikeResizeAndMoveExact() {
        let w = twoWindows()
        _ = w.run(.floating(.set, .active))
        let r = placeRightHalf(w)
        let reference = twoWindows()
        _ = reference.run(.floating(.set, .active))
        _ = reference.run(.resizeActive(.exact(.percent(50), .percent(100))))
        _ = reference.run(.moveActive(.exact(.percent(50), .pixels(0))))
        #expect(w.windows[2]?.floatingFrame == reference.windows[2]?.floatingFrame)
        #expect(w.windows[2]?.floatingFrame == rightHalf)
        #expect(frames(r.effects) == [2: rightHalf])
        #expect(w.windows[2]?.placedFrame == nil)
    }

    @Test func placingNeedsAnActiveWindowAndRefusesFullscreen() {
        #expect(placeThird(world()).reply == "no active window")
        let w = twoWindows()
        _ = w.run(.fullscreen(mode: 0, .set))
        let r = placeThird(w)
        #expect(r.isError)
        #expect(w.windows[2]?.placedFrame == nil)
    }

    @Test func snapshotsDropThePlacementAndRestoreIgnoresASavedOne() throws {
        let w = twoWindows()
        _ = placeThird(w)
        let saved = w.snapshot()
        #expect(saved.windows.allSatisfy { $0.placedFrame == nil && $0.placedSlot == nil })
        let json = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
        #expect(!json.contains("placedFrame") && !json.contains("placedSlot"))
        var tampered = saved
        for i in tampered.windows.indices {
            tampered.windows[i].placedFrame = Rect(x: 1, y: 2, width: 3, height: 4)
            tampered.windows[i].placedSlot = Rect(x: 1, y: 2, width: 3, height: 4)
        }
        let fresh = world()
        let e = fresh.restore(tampered, alive: [snap(1), snap(2, pid: 200)])
        #expect(fresh.windows.values.allSatisfy { $0.placedFrame == nil && $0.placedSlot == nil })
        #expect(frames(e)[2] == rightHalf)
    }

    @Test func extremeValuesStayBounded() {
        let w = twoWindows()
        let huge = [1e308, -1e308, 1e15, -1e15, Double.nan, Double.infinity, -Double.infinity]
        for v in huge {
            let r = place(w, .pixels(v), .percent(v), .percent(-v), .pixels(v))
            #expect(allBounded(r.effects, limit: 1_000_000))
        }
        _ = w.run(.floating(.set, .active))
        for v in huge {
            let r = place(w, .percent(v), .pixels(v), .pixels(-v), .percent(v))
            #expect(allBounded(r.effects, limit: 1_000_000))
            let f = w.windows[2]!.floatingFrame
            #expect(abs(f.x) <= World.extent * 2 && abs(f.y) <= World.extent * 2 && f.width <= World.extent && f.height <= World.extent && f.width >= 20 && f.height >= 20)
        }
    }
}
