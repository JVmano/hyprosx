import Testing
@testable import HyprCore

private func bind(_ keyword: String, _ value: String) -> Bind {
    BindParser.parse(keyword: keyword, value: value, submap: "", location: SourceLocation(file: "t", line: 1)).bind!
}

private let move = bind("bindm", "CTRL ALT, mouse:272, movewindow")
private let resize = bind("bindm", "CTRL ALT, mouse:273, resizewindow")
private let wheelDown = bind("bind", "CTRL ALT, mouse_down, workspace, e+1")
private let middle = bind("bind", "SUPER, mouse:274, killactive")
private let mods: Modifiers = [.control, .option]

private func matcher(threshold: Int = 0, delay: Int = 300) -> MouseBindMatcher {
    var m = MouseBindMatcher()
    m.setBinds([move, resize, wheelDown, middle], dragThreshold: threshold, scrollEventDelayMs: delay)
    return m
}

@Suite struct MouseBindMatcherTests {
    @Test func unboundClicksPass() {
        var m = matcher()
        #expect(m.down(button: 0, modifiers: [], at: .zero) == .pass)
        #expect(m.dragged(to: Point(x: 5, y: 5)) == .pass)
        #expect(m.up(button: 0, modifiers: [], at: .zero) == .pass)
        #expect(m.scroll(.down, modifiers: [], now: 0) == .pass)
    }

    @Test func aDragBindStartsMovesAndEnds() {
        var m = matcher()
        #expect(m.down(button: 0, modifiers: mods, at: Point(x: 1, y: 1)) == .start(.move, Point(x: 1, y: 1)))
        #expect(m.dragged(to: Point(x: 9, y: 9)) == .move(Point(x: 9, y: 9)))
        #expect(m.up(button: 0, modifiers: mods, at: Point(x: 9, y: 9)) == .end(Point(x: 9, y: 9)))
        #expect(m.down(button: 1, modifiers: mods, at: .zero) == .start(.resize, .zero))
    }

    @Test func theThresholdDelaysTheStart() {
        var m = matcher(threshold: 10)
        #expect(m.down(button: 0, modifiers: mods, at: .zero) == .consume)
        #expect(m.dragged(to: Point(x: 5, y: 0)) == .consume)
        #expect(m.dragged(to: Point(x: 12, y: 0)) == .start(.move, .zero))
        #expect(m.dragged(to: Point(x: 20, y: 0)) == .move(Point(x: 20, y: 0)))
        #expect(m.up(button: 0, modifiers: mods, at: Point(x: 20, y: 0)) == .end(Point(x: 20, y: 0)))
    }

    @Test func aClaimedButtonConsumesItsRelease() {
        var m = matcher(threshold: 10)
        _ = m.down(button: 0, modifiers: mods, at: .zero)
        #expect(m.up(button: 0, modifiers: [], at: .zero) == .consume)
        #expect(m.up(button: 0, modifiers: [], at: .zero) == .pass)
    }

    @Test func clickBindsRunOnPress() {
        var m = matcher()
        #expect(m.down(button: 2, modifiers: [.command], at: .zero) == .run([middle]))
        #expect(m.up(button: 2, modifiers: [.command], at: .zero) == .consume)
    }

    @Test func scrollBindsAreThrottled() {
        var m = matcher(delay: 300)
        #expect(m.scroll(.down, modifiers: mods, now: 10) == .run([wheelDown]))
        #expect(m.scroll(.down, modifiers: mods, now: 10.1) == .consume)
        #expect(m.scroll(.down, modifiers: mods, now: 10.4) == .run([wheelDown]))
        #expect(m.scroll(.up, modifiers: mods, now: 11) == .pass)
    }

    @Test func aSecondDragPressKeepsTheActiveDrag() {
        var m = matcher()
        #expect(m.down(button: 0, modifiers: mods, at: .zero) == .start(.move, .zero))
        #expect(m.down(button: 1, modifiers: mods, at: Point(x: 3, y: 3)) == .consume)
        #expect(m.up(button: 1, modifiers: mods, at: Point(x: 3, y: 3)) == .consume)
        #expect(m.dragged(to: Point(x: 4, y: 4)) == .move(Point(x: 4, y: 4)))
        #expect(m.up(button: 0, modifiers: mods, at: Point(x: 4, y: 4)) == .end(Point(x: 4, y: 4)))
    }

    @Test func aDragBindWithAnUnknownDispatcherDoesNotShadowAValidOne() {
        var m = MouseBindMatcher()
        m.setBinds([bind("bindm", "CTRL ALT, mouse:272, bogus"), move], dragThreshold: 0, scrollEventDelayMs: 0)
        #expect(m.down(button: 0, modifiers: mods, at: .zero) == .start(.move, .zero))
    }

    @Test func cancellingAStartedDragEndsItAndClearsThePress() {
        var m = matcher()
        _ = m.down(button: 0, modifiers: mods, at: .zero)
        #expect(m.cancel(at: Point(x: 7, y: 7)) == .end(Point(x: 7, y: 7)))
        #expect(m.up(button: 0, modifiers: mods, at: Point(x: 7, y: 7)) == .pass)
        #expect(m.dragged(to: Point(x: 8, y: 8)) == .pass)
        #expect(m.down(button: 1, modifiers: mods, at: .zero) == .start(.resize, .zero))
    }

    @Test func cancellingWithoutAStartedDragPasses() {
        var m = matcher(threshold: 10)
        #expect(m.cancel(at: .zero) == .pass)
        _ = m.down(button: 0, modifiers: mods, at: .zero)
        #expect(m.cancel(at: .zero) == .pass)
        #expect(m.up(button: 0, modifiers: mods, at: .zero) == .pass)
    }

    @Test func keyBindsAreIgnored() {
        var m = MouseBindMatcher()
        m.setBinds([bind("bind", "ALT, H, movefocus, l")], dragThreshold: 0, scrollEventDelayMs: 0)
        #expect(m.isEmpty)
    }
}

@Suite struct WorldMouseBindTests {
    private func pair() -> World {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, pid: 200)))
        return w
    }

    @Test func movingAFloatingWindowFollowsTheCursor() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.run(try! CommandParser.parse(dispatcher: "setfloating", arguments: "address:0x1").get())
        let start = w.windows[1]!.floatingFrame
        _ = w.handle(.mouseBindStarted(.move, start.center))
        _ = w.handle(.mouseBindMoved(start.center + Point(x: 40, y: 30)))
        _ = w.handle(.mouseBindEnded(start.center + Point(x: 40, y: 30)))
        #expect(w.windows[1]!.floatingFrame == Rect(x: start.x + 40, y: start.y + 30, width: start.width, height: start.height))
    }

    @Test func droppingATiledWindowOnTheOtherSideMovesIt() {
        let w = pair()
        let left = w.windows[1]!.appliedFrame!, right = w.windows[2]!.appliedFrame!
        _ = w.handle(.mouseBindStarted(.move, left.center))
        _ = w.handle(.mouseBindMoved(Point(x: right.center.x + 100, y: right.center.y)))
        _ = w.handle(.mouseBindEnded(Point(x: right.center.x + 100, y: right.center.y)))
        #expect(w.windows[1]!.appliedFrame!.minX > w.windows[2]!.appliedFrame!.minX)
    }

    @Test func resizingATiledWindowMovesTheSplit() {
        let w = pair()
        let left = w.windows[1]!.appliedFrame!
        let grip = Point(x: left.maxX - 10, y: left.center.y + 10)
        _ = w.handle(.mouseBindStarted(.resize, grip))
        _ = w.handle(.mouseBindMoved(grip + Point(x: 100, y: 0)))
        _ = w.handle(.mouseBindEnded(grip + Point(x: 100, y: 0)))
        #expect(abs(w.windows[1]!.appliedFrame!.width - (left.width + 100)) <= 2)
    }

    @Test func aBindDragOwnsItsWindowFrameAgainstAxEchoes() {
        let w = pair()
        let left = w.windows[1]!.appliedFrame!
        let grip = Point(x: left.maxX - 10, y: left.center.y + 10)
        _ = w.handle(.mouseBindStarted(.resize, grip))
        _ = w.handle(.mouseBindMoved(grip + Point(x: 60, y: 0)))
        let echo = w.handle(.windowFrameChanged(1, Rect(x: 0, y: 40, width: 300, height: 300), userDriven: false))
        let layoutSteps = echo.flatMap { effect -> [FrameChange] in
            if case .setFrames(let changes) = effect { return changes.filter { $0.id == 1 && $0.reason == .layout } }
            return []
        }
        #expect(layoutSteps.isEmpty)
    }

    @Test func aBindDragDropsThePlacementOfItsWindow() {
        let w = ownerWorld()
        _ = placeOwner(w, width: 33.33, x: 33.33)
        #expect(w.windows[1]!.placedFrame != nil)
        let frame = w.windows[1]!.appliedFrame!
        _ = w.handle(.mouseBindStarted(.move, frame.center))
        #expect(w.windows[1]!.placedFrame == nil)
    }

    @Test func aFailedStartLeavesNoStaleDrag() {
        let w = pair()
        _ = w.handle(.mouseBindStarted(.move, w.windows[1]!.appliedFrame!.center))
        #expect(w.mouseDrag != nil)
        _ = w.handle(.mouseBindStarted(.move, Point(x: 5000, y: 5000)))
        #expect(w.mouseDrag == nil)
    }

    @Test func aDragOverEmptySpaceDoesNothing() {
        let w = world()
        #expect(w.handle(.mouseBindStarted(.move, Point(x: 5, y: 5))).isEmpty)
        #expect(w.handle(.mouseBindMoved(Point(x: 50, y: 50))).isEmpty)
        #expect(w.handle(.mouseBindEnded(Point(x: 50, y: 50))).isEmpty)
    }

    @Test func resizingAFloatingWindowKeepsTheOppositeCorner() {
        let f = Rect(x: 100, y: 100, width: 400, height: 300)
        #expect(World.resizedFloating(f, by: Point(x: -50, y: -20), corner: .topLeft) == Rect(x: 50, y: 80, width: 450, height: 320))
        #expect(World.resizedFloating(f, by: Point(x: -1000, y: 0), corner: .bottomRight) == Rect(x: 100, y: 100, width: 50, height: 300))
    }
}
