import Testing
@testable import HyprCore

private let screen = Rect(x: 0, y: 0, width: 1512, height: 982)
private let goal = Rect(x: 100, y: 100, width: 1000, height: 500)

private func near(_ a: Rect?, _ b: Rect) -> Bool {
    guard let a else { return false }
    return abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01 && abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
}

@Suite struct MotionTests {
    @Test func timingFollowsTheLeafAndTheSwitches() {
        let c = makeConfig("animations {\n animation = windowsMove, 1, 5, default\n}\n")
        #expect(Motion.timing("windowsMove", config: c, environment: MotionEnvironment())?.duration == 0.5)
        #expect(Motion.timing("windowsMove", config: c, environment: MotionEnvironment(), noAnim: true) == nil)
        #expect(Motion.timing("windowsMove", config: makeConfig("animations {\n enabled = false\n}\n"), environment: MotionEnvironment()) == nil)
        #expect(Motion.timing("windowsMove", config: makeConfig("animations {\n animation = windows, 0\n}\n"), environment: MotionEnvironment()) == nil)
    }

    @Test func lowPowerAndReduceMotionTurnMotionOffButKeepBorderFades() {
        let c = makeConfig()
        #expect(Motion.timing("windowsMove", config: c, environment: MotionEnvironment(lowPower: true)) == nil)
        #expect(Motion.timing("windowsMove", config: c, environment: MotionEnvironment(reduceMotion: true)) == nil)
        #expect(Motion.decorationTiming("border", config: c) != nil)
        let keep = makeConfig("macos {\n animations_on_low_power = true\n respect_reduce_motion = false\n}\n")
        #expect(Motion.timing("windowsMove", config: keep, environment: MotionEnvironment(lowPower: true, reduceMotion: true)) != nil)
    }

    @Test func popinStartsCenteredAtThePercent() {
        #expect(near(Motion.openStart(goal: goal, monitor: screen, style: "popin 87%"), Rect(x: 165, y: 132.5, width: 870, height: 435)))
        #expect(near(Motion.openStart(goal: goal, monitor: screen, style: ""), Rect(x: 597.5, y: 347.5, width: 5, height: 5)))
        #expect(near(Motion.openStart(goal: goal, monitor: screen, style: "gnomed"), Rect(x: 597.5, y: 347.5, width: 5, height: 5)))
    }

    @Test func slideOpensFromTheNamedOrNearestSide() {
        #expect(Motion.openStart(goal: goal, monitor: screen, style: "slide left") == Rect(x: -900, y: 100, width: 1000, height: 500))
        #expect(Motion.openStart(goal: goal, monitor: screen, style: "slide bottom") == Rect(x: 100, y: 982, width: 1000, height: 500))
        let right = Rect(x: 1300, y: 300, width: 200, height: 200)
        #expect(Motion.openStart(goal: right, monitor: screen, style: "slide") == Rect(x: 1500, y: 300, width: 200, height: 200))
    }

    @Test func workspacesSlideInFromTheSideOfTravel() {
        #expect(Motion.slideIn(goal: goal, monitor: screen, style: "slide", leftward: true) == Rect(x: 1612, y: 100, width: 1000, height: 500))
        #expect(Motion.slideIn(goal: goal, monitor: screen, style: "", leftward: false) == Rect(x: -1412, y: 100, width: 1000, height: 500))
        #expect(Motion.slideIn(goal: goal, monitor: screen, style: "slidevert", leftward: true) == Rect(x: 100, y: 1082, width: 1000, height: 500))
        #expect(near(Motion.slideIn(goal: goal, monitor: screen, style: "fade", leftward: true), Rect(x: 220.96, y: 100, width: 1000, height: 500)))
        #expect(near(Motion.slideIn(goal: goal, monitor: screen, style: "slidefade 20%", leftward: true), Rect(x: 402.4, y: 100, width: 1000, height: 500)))
    }

    @Test func onlySlideStylesGlideOut() {
        #expect(Motion.slideOut(current: goal, monitor: screen, style: "slide", leftward: true) == Rect(x: -999, y: 100, width: 1000, height: 500))
        #expect(Motion.slideOut(current: goal, monitor: screen, style: "slide", leftward: false) == Rect(x: 1511, y: 100, width: 1000, height: 500))
        #expect(Motion.slideOut(current: goal, monitor: screen, style: "slidevert", leftward: false) == Rect(x: 100, y: 981, width: 1000, height: 500))
        #expect(Motion.slideOut(current: goal, monitor: screen, style: "fade", leftward: true) == nil)
        #expect(Motion.slideOut(current: goal, monitor: screen, style: "slidefade 20%", leftward: true) == nil)
    }

    @Test func plansPickTheStartFromTheReason() {
        let c = makeConfig("animations {\n animation = windowsIn, 1, 4, default, popin 50%\n}\n")
        let open = FrameChange(id: 1, frame: goal, reason: .open)
        let appFrame = Rect(x: 0, y: 0, width: 300, height: 300)
        let live = Motion.plan(open, current: appFrame, monitor: screen, config: c, environment: MotionEnvironment(), window: WindowMotion(), live: true)
        #expect(near(live?.from, Rect(x: 350, y: 225, width: 500, height: 250)))
        let slow = Motion.plan(open, current: appFrame, monitor: screen, config: c, environment: MotionEnvironment(), window: WindowMotion(), live: false)
        #expect(slow?.from == appFrame)
        let styled = Motion.plan(open, current: nil, monitor: screen, config: c, environment: MotionEnvironment(), window: WindowMotion(style: "slide left"), live: true)
        #expect(styled?.from == Rect(x: -900, y: 100, width: 1000, height: 500))
    }

    @Test func slideOpensIgnoreTheAppFrameEvenWhenSlow() {
        let c = makeConfig("animations {\n animation = windowsIn, 1, 4, default, slide left\n}\n")
        let open = FrameChange(id: 1, frame: goal, reason: .open)
        let appFrame = Rect(x: 0, y: 0, width: 300, height: 300)
        let slow = Motion.plan(open, current: appFrame, monitor: screen, config: c, environment: MotionEnvironment(), window: WindowMotion(), live: false)
        #expect(slow?.from == Rect(x: -900, y: 100, width: 1000, height: 500))
        let ruled = Motion.plan(open, current: appFrame, monitor: screen, config: makeConfig(), environment: MotionEnvironment(), window: WindowMotion(style: "slide left"), live: false)
        #expect(ruled?.from == Rect(x: -900, y: 100, width: 1000, height: 500))
    }

    @Test func popinNeedsAPercentSign() {
        #expect(near(Motion.openStart(goal: goal, monitor: screen, style: "popin 87"), Rect(x: 597.5, y: 347.5, width: 5, height: 5)))
        #expect(near(Motion.openStart(goal: goal, monitor: screen, style: "popin"), Rect(x: 597.5, y: 347.5, width: 5, height: 5)))
    }

    @Test func workspaceGapsWidenTheSlideInOffset() {
        #expect(Motion.slideIn(goal: goal, monitor: screen, style: "slide", leftward: true, gap: 10) == Rect(x: 1622, y: 100, width: 1000, height: 500))
        #expect(Motion.slideIn(goal: goal, monitor: screen, style: "slidevert", leftward: false, gap: 10) == Rect(x: 100, y: -892, width: 1000, height: 500))
        let c = makeConfig("general {\n gaps_workspaces = 10\n}\n")
        let change = FrameChange(id: 1, frame: goal, reason: .workspaceIn(leftward: true))
        #expect(Motion.plan(change, current: nil, monitor: screen, config: c, environment: MotionEnvironment(), window: WindowMotion(), live: true)?.from.x == 1622)
    }

    @Test func workspaceAndSpecialPlansStartOffscreen() {
        let c = makeConfig("animations {\n animation = workspacesIn, 1, 4, default, slidevert\n}\n")
        let back = FrameChange(id: 1, frame: goal, reason: .workspaceIn(leftward: false))
        #expect(Motion.plan(back, current: nil, monitor: screen, config: c, environment: MotionEnvironment(), window: WindowMotion(), live: true)?.from.y == -882)
        let special = FrameChange(id: 1, frame: goal, reason: .specialIn)
        #expect(Motion.plan(special, current: nil, monitor: screen, config: makeConfig(), environment: MotionEnvironment(), window: WindowMotion(), live: true)?.from.x == 1612)
    }

    @Test func moveAndManualResizePlans() {
        let c = makeConfig()
        let move = FrameChange(id: 1, frame: goal, reason: .layout)
        #expect(Motion.plan(move, current: goal, monitor: screen, config: c, environment: MotionEnvironment(), window: WindowMotion(), live: true) == nil)
        #expect(Motion.plan(move, current: nil, monitor: screen, config: c, environment: MotionEnvironment(), window: WindowMotion(), live: true) == nil)
        let from = Rect(x: 0, y: 0, width: 10, height: 10)
        #expect(Motion.plan(move, current: from, monitor: screen, config: c, environment: MotionEnvironment(), window: WindowMotion(), live: true)?.from == from)
        let manual = FrameChange(id: 1, frame: goal, reason: .manualResize)
        #expect(Motion.plan(manual, current: from, monitor: screen, config: c, environment: MotionEnvironment(), window: WindowMotion(), live: true) == nil)
        let animated = makeConfig("misc {\n animate_manual_resizes = true\n}\n")
        #expect(Motion.plan(manual, current: from, monitor: screen, config: animated, environment: MotionEnvironment(), window: WindowMotion(), live: true) != nil)
        let restore = FrameChange(id: 1, frame: goal, reason: .restore)
        #expect(Motion.plan(restore, current: from, monitor: screen, config: c, environment: MotionEnvironment(), window: WindowMotion(), live: true) == nil)
    }

    @Test func parkPlansGlideOnlyForTaggedSlideParks() {
        let c = makeConfig("animations {\n animation = workspaces, 1, 3, default, slide\n}\n")
        let tagged = ParkRequest(id: 1, origin: Point(x: 1511, y: 981), slide: .workspace(leftward: true))
        #expect(Motion.planOut(tagged, current: goal, monitor: screen, config: c, environment: MotionEnvironment(), window: WindowMotion())?.to == Rect(x: -999, y: 100, width: 1000, height: 500))
        let plain = ParkRequest(id: 1, origin: Point(x: 1511, y: 981))
        #expect(Motion.planOut(plain, current: goal, monitor: screen, config: c, environment: MotionEnvironment(), window: WindowMotion()) == nil)
        let special = ParkRequest(id: 1, origin: Point(x: 1511, y: 981), slide: .special)
        #expect(Motion.planOut(special, current: goal, monitor: screen, config: c, environment: MotionEnvironment(), window: WindowMotion())?.to.x == 1511)
    }
}
