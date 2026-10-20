# HyprOSX M2: Motion and Decoration Implementation Plan


**Goal:** Add Hyprland-style window motion, border rings, dimming, battery-aware motion, and mouse and scroll binds to HyprOSX.

**Architecture:** HyprCore stays pure: the World tags every frame change and park with a motion intent, pure planners turn an intent plus the config into a `MotionPlan`, and a pure `Animator` advances plans on injected time. The HyprOSX app layer runs the `Animator` from one `CADisplayLink` that exists only while an animation runs, writes frames through the existing per-app `AXAppThread` slot (which already keeps only the newest frame), and draws borders and dim overlays as click-through `NSWindow`s ordered relative to the target window. Mouse binds use a pure `MouseBindMatcher` in HyprCore and a `CGEvent` tap in the app that exists only while the config has mouse or scroll binds.

**Tech Stack:** Swift 6.4 toolchain, Swift 5 language mode, SwiftPM, Swift Testing, AppKit, QuartzCore, ApplicationServices, CoreGraphics. No third-party packages.

**Spec:** `docs/specs/2026-10-12-hyprosx-design.md` (sections 3.3, 4.3, 7.4, 8, 11, 12, 20 item 2). Formulas: `docs/research/hyprland-algorithms.md` sections 3 to 5.

## Global Constraints

- Every `swift` command runs with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (Command Line Tools lack the Swift Testing macros).
- Platform floor `.macOS(.v14)`; Swift 5 language mode; zero compiler warnings.
- No code comments unless nothing else can explain the code.
- No Accessibility call on the main thread. Every AX call goes through the window's `AXAppThread`.
- No third-party packages. No private API.
- Idle CPU below 0.1% over 60 s with no input: the display link exists only while an animation runs; no timers while idle.
- Resident memory below 50 MB with about ten windows open and Settings closed.
- Never push. The repo is local only, branch `main`.
- Do not create, delete or change keychain items or signing identities. Install with `scripts/build-app.sh --install` (it signs with the existing "HyprOSX Local Signing" identity).
- Do not use `rm -rf`.
- HyprCore files import Foundation only. HyprOSX files may import AppKit, QuartzCore, ApplicationServices, CoreGraphics.

## Review Focus

1. A key pressed again while an animation runs (fast ⌥+1/⌥+2, held Ctrl+⌥+L): the window continues from where it is now, never jumps back to the old start. Pinned in Task 3 (`aRetargetStartsFromTheCurrentValue`).
2. A window that closes or whose app quits mid-animation: no more AX writes and no border left on screen. Pinned in Task 3 (`cancelStopsTheWindow`) and Task 4 wiring (`motion.cancel` before `windowDisappeared`/`appTerminated`).
3. Switching back to a workspace before its windows finish gliding out: the windows come back and are not parked at the end. Pinned in Task 3 (`aNewGoalWithoutParkClearsThePark`).
4. Parked windows and windows of hidden workspaces never get a border or dim window. Pinned in Task 5 (`parkedWindowsGetNoDecoration`).
5. A plain click or scroll with no bound modifiers always reaches the app, and a bound button press never leaks its release to the app. Pinned in Task 8 (`unboundClicksPass`, `aClaimedButtonConsumesItsRelease`).

---

### Task 1: Motion intents in the World

**Files:**
- Modify: `Sources/HyprCore/World/Effects.swift`
- Modify: `Sources/HyprCore/World/World.swift` (`refresh`, `staticOutcome`)
- Modify: `Sources/HyprCore/World/World+Workspaces.swift` (`switchWorkspace`, `toggleSpecial`)
- Modify: `Sources/HyprCore/World/World+Events.swift` (`frameChanged`)
- Create: `Sources/HyprCore/World/World+Motion.swift`
- Test: `Tests/HyprCoreTests/WorldMotionIntentTests.swift`

**Interfaces:**
- Produces:
  - `public enum FrameReason { case layout, open, workspaceIn(leftward: Bool), specialIn, manualResize, restore }`
  - `public enum SlideOut: Equatable, Sendable { case workspace(leftward: Bool), special }`
  - `ParkRequest.slide: SlideOut?` and `ParkRequest.init(id:origin:slide: = nil)`
  - `public struct WindowMotion: Equatable, Sendable { var noAnim: Bool; var style: String? }`
  - `World.motion(for: WindowID) -> WindowMotion` (public)
  - `World.monitorFrame(of: WindowID) -> Rect?` (public)
  - `World.dynamicOutcome(for: ManagedWindow) -> DynamicRuleOutcome` (internal)
  - `World.windowRules(forPID: Int32) -> [WindowRule]` (internal)

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/WorldMotionIntentTests.swift`:

```swift
import Testing
@testable import HyprCore

private func run(_ w: World, _ dispatcher: String, _ arguments: String = "") -> [Effect] {
    w.run(try! CommandParser.parse(dispatcher: dispatcher, arguments: arguments).get()).effects
}

private func reasons(_ effects: [Effect]) -> [WindowID: FrameReason] {
    var out: [WindowID: FrameReason] = [:]
    for case .setFrames(let changes) in effects { for c in changes { out[c.id] = c.reason } }
    return out
}

private func slides(_ effects: [Effect]) -> [WindowID: SlideOut?] {
    var out: [WindowID: SlideOut?] = [:]
    for case .park(let parks) in effects { for p in parks { out[p.id] = p.slide } }
    return out
}

private func twoWorkspaces(_ text: String = "") -> World {
    let w = world(text)
    _ = w.handle(.windowAppeared(snap(1)))
    _ = w.handle(.windowAppeared(snap(2, pid: 200)))
    _ = run(w, "movetoworkspacesilent", "2,address:0x2")
    return w
}

@Suite struct WorldMotionIntentTests {
    @Test func aSwitchToAHigherIDSlidesLeftAndTagsTheParks() {
        let w = twoWorkspaces()
        let e = run(w, "workspace", "2")
        #expect(reasons(e)[2] == .workspaceIn(leftward: true))
        #expect(slides(e)[1] == .workspace(leftward: true))
    }

    @Test func aSwitchToALowerIDSlidesRight() {
        let w = twoWorkspaces()
        _ = run(w, "workspace", "2")
        let e = run(w, "workspace", "1")
        #expect(reasons(e)[1] == .workspaceIn(leftward: false))
        #expect(slides(e)[2] == .workspace(leftward: false))
    }

    @Test func wraparoundTreatsLastToFirstAsForward() {
        let w = twoWorkspaces("animations {\n workspace_wraparound = true\n}\n")
        _ = run(w, "movetoworkspacesilent", "3,address:0x2")
        _ = run(w, "workspace", "3")
        let e = run(w, "workspace", "1")
        #expect(reasons(e)[1] == .workspaceIn(leftward: true))
    }

    @Test func specialWorkspacesUseTheirOwnIntent() {
        let w = twoWorkspaces()
        _ = run(w, "movetoworkspacesilent", "special:magic,address:0x2")
        let shown = run(w, "togglespecialworkspace", "magic")
        #expect(reasons(shown)[2] == .specialIn)
        let hidden = run(w, "togglespecialworkspace", "magic")
        #expect(slides(hidden)[2] == .special)
    }

    @Test func plainParksCarryNoSlide() {
        let w = twoWorkspaces()
        let e = run(w, "movetoworkspacesilent", "3,address:0x1")
        #expect(slides(e)[1] == .some(nil))
    }

    @Test func aUserResizeTagsTheNeighboursAsManual() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, pid: 200)))
        let a = w.windows[1]!.appliedFrame!
        let e = w.handle(.windowFrameChanged(1, Rect(x: a.x, y: a.y, width: a.width - 100, height: a.height), userDriven: true))
        #expect(reasons(e)[2] == .manualResize)
    }

    @Test func motionReadsRulesAndSetprop() {
        let w = world("windowrule = animation popin 50%, match:class Ghostty\n")
        _ = w.handle(.windowAppeared(snap(1)))
        #expect(w.motion(for: 1) == WindowMotion(noAnim: false, style: "popin 50%"))
        _ = run(w, "setprop", "address:0x1 no_anim 1")
        #expect(w.motion(for: 1).noAnim)
        let r = world("windowrule = no_anim on, match:class Ghostty\n")
        _ = r.handle(.windowAppeared(snap(1)))
        #expect(r.motion(for: 1).noAnim)
    }

    @Test func monitorFrameFollowsTheWorkspaceMonitor() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        #expect(w.monitorFrame(of: 1) == laptop.frame)
        #expect(w.monitorFrame(of: 99) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter WorldMotionIntentTests 2>&1 | tail -5`
Expected: build failure: `type 'FrameReason' has no member 'specialIn'` (and similar for `SlideOut`, `motion(for:)`).

- [ ] **Step 3: Extend the effect types**

In `Sources/HyprCore/World/Effects.swift` replace the `FrameReason` and `ParkRequest` declarations with:

```swift
public enum FrameReason: Equatable, Sendable { case layout, open, workspaceIn(leftward: Bool), specialIn, manualResize, restore }

public enum SlideOut: Equatable, Sendable { case workspace(leftward: Bool), special }

public struct ParkRequest: Equatable, Sendable {
    public var id: WindowID
    public var origin: Point
    public var slide: SlideOut?
    public init(id: WindowID, origin: Point, slide: SlideOut? = nil) { self.id = id; self.origin = origin; self.slide = slide }
}
```

- [ ] **Step 4: Carry the slide through `refresh`**

In `Sources/HyprCore/World/World.swift`, change the `refresh` signature and the park line:

```swift
    func refresh(_ ids: Set<Int>, reason: FrameReason = .layout, opened: WindowID? = nil, skip: WindowID? = nil, slide: SlideOut? = nil) {
```

```swift
                    parkList.append(ParkRequest(id: id, origin: Parking.origin(windowSize: size, monitor: mon, among: monitors, bundleID: w.bundleID), slide: slide))
```

- [ ] **Step 5: Tag workspace switches, special workspaces and manual resizes**

In `Sources/HyprCore/World/World+Workspaces.swift`, `switchWorkspace`, replace

```swift
        refresh([target], reason: .workspaceIn(leftward: target > (old ?? target)))
        if let old {
            refresh([old])
            destroyIfUnused(old)
        }
```

with

```swift
        let leftward = slidesLeft(from: old, to: target, on: mon)
        refresh([target], reason: .workspaceIn(leftward: leftward))
        if let old {
            refresh([old], slide: .workspace(leftward: leftward))
            destroyIfUnused(old)
        }
```

In `toggleSpecial`, show branch: `refresh([previous])` becomes `refresh([previous], slide: .special)`, and `refresh([id], reason: .workspaceIn(leftward: true))` becomes `refresh([id], reason: .specialIn)`. Hide branch: `refresh([id])` becomes `refresh([id], slide: .special)`.

In `Sources/HyprCore/World/World+Events.swift`, `frameChanged`, the last `refresh([ws.id], skip: id)` becomes `refresh([ws.id], reason: .manualResize, skip: id)`.

Existing tests that expect `.workspaceIn(leftward: true)` for a special workspace now expect `.specialIn`; update them.

- [ ] **Step 6: Add `World+Motion.swift`**

```swift
import Foundation

public struct WindowMotion: Equatable, Sendable {
    public var noAnim: Bool
    public var style: String?
    public init(noAnim: Bool = false, style: String? = nil) { self.noAnim = noAnim; self.style = style }
}

extension World {
    func windowRules(forPID pid: Int32) -> [WindowRule] {
        var rules = config.windowRules
        for part in (pidRules[pid] ?? "").split(separator: ";") {
            let text = part.trimmingCharacters(in: .whitespaces) + ", match:class .*"
            if let rule = WindowRuleParser.parse(keyword: "windowrule", value: text, location: SourceLocation(file: "exec", line: 0)).rule {
                rules.append(rule)
            }
        }
        return rules
    }

    func dynamicOutcome(for w: ManagedWindow) -> DynamicRuleOutcome {
        RuleEngine.dynamicOutcome(windowRules(forPID: w.pid), facts(for: w))
    }

    public func motion(for id: WindowID) -> WindowMotion {
        guard let w = windows[id] else { return WindowMotion() }
        let rules = dynamicOutcome(for: w)
        let prop = w.props["no_anim"].flatMap { ConfigValue.bool($0) }
        return WindowMotion(noAnim: prop ?? rules.noAnim, style: rules.animationStyle)
    }

    public func monitorFrame(of id: WindowID) -> Rect? {
        guard let w = windows[id], let ws = workspaces[w.workspace] else { return nil }
        return monitor(ws.monitor)?.frame
    }

    func slidesLeft(from old: Int?, to target: Int, on mon: Int) -> Bool {
        guard let old else { return false }
        if config.animationsOptions.workspaceWraparound {
            let ids = workspaces.values.filter { !$0.isSpecial && $0.monitor == mon && $0.id > 0 }.map(\.id) + [target]
            if let lo = ids.min(), let hi = ids.max(), lo != hi {
                if old == hi && target == lo { return true }
                if old == lo && target == hi { return false }
            }
        }
        return target > old
    }
}
```

`pidRules` is a `[Int32: String]` today; if its value type differs, adapt the loop to it. Then make `staticOutcome(for:)` in `World.swift` use it:

```swift
    func staticOutcome(for w: ManagedWindow) -> StaticRuleOutcome {
        RuleEngine.staticOutcome(windowRules(forPID: w.pid), facts(for: w))
    }
```

- [ ] **Step 7: Run the new tests and the full suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | grep -E 'Test run with|✘' | head`
Expected: `Test run with N tests ... passed`, no `✘` lines.

- [ ] **Step 8: Commit**

```bash
git add Sources/HyprCore Tests/HyprCoreTests
git commit -m "feat: tag frame changes and parks with motion intents"
```

---

### Task 2: Motion planning

**Files:**
- Create: `Sources/HyprCore/Animation/Motion.swift`
- Test: `Tests/HyprCoreTests/MotionTests.swift`

**Interfaces:**
- Consumes: `FrameReason`, `SlideOut`, `ParkRequest`, `FrameChange`, `WindowMotion` (Task 1); `Config.animations.leaf(_:)`, `Config.beziers`, `Bezier.builtIns` (M1).
- Produces:
  - `public struct MotionEnvironment { lowPower: Bool; reduceMotion: Bool; init(lowPower: = false, reduceMotion: = false) }`
  - `public struct MotionTiming { duration: Double /* seconds */; curve: Bezier }`
  - `public struct MotionPlan { from: Rect; to: Rect; timing: MotionTiming }`
  - `Motion.timing(_ leaf: String, config:, environment:, noAnim: = false) -> MotionTiming?`
  - `Motion.decorationTiming(_ leaf: String, config:) -> MotionTiming?`
  - `Motion.plan(_ change: FrameChange, current: Rect?, monitor: Rect, config:, environment:, window: WindowMotion, live: Bool) -> MotionPlan?`
  - `Motion.planOut(_ park: ParkRequest, current: Rect, monitor: Rect, config:, environment:, window: WindowMotion) -> MotionPlan?`
  - `Motion.openStart(goal:monitor:style:) -> Rect`, `Motion.slideIn(goal:monitor:style:leftward:) -> Rect`, `Motion.slideOut(current:monitor:style:leftward:) -> Rect?`

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/MotionTests.swift`:

```swift
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
```

The `fade` expectation is `100 + 1512 * 0.08 = 220.96`; `slidefade 20%` is `100 + 1512 * 0.2 = 402.4`.

- [ ] **Step 2: Run the tests to see them fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MotionTests 2>&1 | tail -5`
Expected: build failure: `cannot find 'Motion' in scope`.

- [ ] **Step 3: Implement `Sources/HyprCore/Animation/Motion.swift`**

```swift
import Foundation

public struct MotionEnvironment: Equatable, Sendable {
    public var lowPower: Bool
    public var reduceMotion: Bool
    public init(lowPower: Bool = false, reduceMotion: Bool = false) { self.lowPower = lowPower; self.reduceMotion = reduceMotion }
}

public struct MotionTiming: Equatable, Sendable {
    public var duration: Double
    public var curve: Bezier
    public init(duration: Double, curve: Bezier) { self.duration = duration; self.curve = curve }
}

public struct MotionPlan: Equatable, Sendable {
    public var from: Rect
    public var to: Rect
    public var timing: MotionTiming
    public init(from: Rect, to: Rect, timing: MotionTiming) { self.from = from; self.to = to; self.timing = timing }
}

public enum Motion {
    public static func timing(_ leafName: String, config: Config, environment: MotionEnvironment, noAnim: Bool = false) -> MotionTiming? {
        guard !noAnim else { return nil }
        if environment.lowPower && !config.macos.animationsOnLowPower { return nil }
        if environment.reduceMotion && config.macos.respectReduceMotion { return nil }
        return decorationTiming(leafName, config: config)
    }

    public static func decorationTiming(_ leafName: String, config: Config) -> MotionTiming? {
        guard config.animationsOptions.enabled else { return nil }
        let leaf = config.animations.leaf(leafName)
        guard leaf.enabled, leaf.durationMs > 0 else { return nil }
        return MotionTiming(duration: leaf.durationMs / 1000, curve: config.beziers[leaf.curve] ?? Bezier.builtIns["default"]!)
    }

    static func leafName(for reason: FrameReason, config: Config) -> String? {
        switch reason {
        case .layout: return "windowsMove"
        case .open: return "windowsIn"
        case .workspaceIn: return "workspacesIn"
        case .specialIn: return "specialWorkspaceIn"
        case .manualResize: return config.misc.animateManualResizes ? "windowsMove" : nil
        case .restore: return nil
        }
    }

    public static func plan(_ change: FrameChange, current: Rect?, monitor: Rect, config: Config, environment: MotionEnvironment,
                            window: WindowMotion, live: Bool) -> MotionPlan? {
        guard let name = leafName(for: change.reason, config: config),
              let timing = timing(name, config: config, environment: environment, noAnim: window.noAnim) else { return nil }
        let goal = change.frame
        let leafStyle = config.animations.leaf(name).style
        let from: Rect
        switch change.reason {
        case .open:
            if !live, let current { from = current } else { from = openStart(goal: goal, monitor: monitor, style: window.style ?? leafStyle) }
        case .workspaceIn(let leftward):
            from = slideIn(goal: goal, monitor: monitor, style: leafStyle, leftward: leftward)
        case .specialIn:
            from = slideIn(goal: goal, monitor: monitor, style: leafStyle, leftward: true)
        default:
            guard let current else { return nil }
            from = current
        }
        guard !from.isClose(to: goal, tolerance: 0.5) else { return nil }
        return MotionPlan(from: from, to: goal, timing: timing)
    }

    public static func planOut(_ park: ParkRequest, current: Rect, monitor: Rect, config: Config, environment: MotionEnvironment,
                               window: WindowMotion) -> MotionPlan? {
        guard let slide = park.slide else { return nil }
        let name: String
        let leftward: Bool
        switch slide {
        case .workspace(let l): name = "workspacesOut"; leftward = l
        case .special: name = "specialWorkspaceOut"; leftward = false
        }
        guard let timing = timing(name, config: config, environment: environment, noAnim: window.noAnim),
              let end = slideOut(current: current, monitor: monitor, style: config.animations.leaf(name).style, leftward: leftward) else { return nil }
        return MotionPlan(from: current, to: end, timing: timing)
    }

    public static func openStart(goal: Rect, monitor: Rect, style: String) -> Rect {
        let words = style.split(separator: " ").map(String.init)
        if words.first == "slide" {
            let side = words.count > 1 ? words[1] : nearestSide(goal, monitor)
            switch side {
            case "bottom": return Rect(x: goal.x, y: monitor.maxY, width: goal.width, height: goal.height)
            case "left": return Rect(x: goal.x - goal.width, y: goal.y, width: goal.width, height: goal.height)
            case "right": return Rect(x: goal.x + goal.width, y: goal.y, width: goal.width, height: goal.height)
            default: return Rect(x: goal.x, y: monitor.minY - goal.height, width: goal.width, height: goal.height)
            }
        }
        let percent = words.first == "popin" && words.count > 1 ? (finiteDouble(String(words[1].dropLast())) ?? 0) : 0
        let w = min(max(goal.width * percent / 100, 5), goal.width)
        let h = min(max(goal.height * percent / 100, 5), goal.height)
        return Rect(x: goal.center.x - w / 2, y: goal.center.y - h / 2, width: w, height: h)
    }

    static func nearestSide(_ goal: Rect, _ monitor: Rect) -> String {
        let c = goal.center
        let distances = [("bottom", monitor.maxY - c.y), ("left", c.x - monitor.minX), ("right", monitor.maxX - c.x), ("top", c.y - monitor.minY)]
        return distances.min { $0.1 < $1.1 }!.0
    }

    static func slideStyle(_ style: String) -> (kind: String, vertical: Bool, percent: Double) {
        let words = style.split(separator: " ").map(String.init)
        let kind = words.first ?? "slide"
        var vertical = kind.hasSuffix("vert")
        var percent = 100.0
        for w in words.dropFirst() {
            if w == "top" || w == "bottom" { vertical = true }
            if w == "left" || w == "right" { vertical = false }
            if w.hasSuffix("%"), let n = finiteDouble(String(w.dropLast())) { percent = n }
        }
        return (kind, vertical, percent)
    }

    public static func slideIn(goal: Rect, monitor: Rect, style: String, leftward: Bool) -> Rect {
        let s = slideStyle(style)
        let percent = s.kind == "fade" ? 8 : s.percent
        let sign: Double = leftward ? 1 : -1
        if s.vertical {
            return Rect(x: goal.x, y: goal.y + sign * monitor.height * percent / 100, width: goal.width, height: goal.height)
        }
        return Rect(x: goal.x + sign * monitor.width * percent / 100, y: goal.y, width: goal.width, height: goal.height)
    }

    public static func slideOut(current: Rect, monitor: Rect, style: String, leftward: Bool) -> Rect? {
        let s = slideStyle(style)
        guard s.kind == "slide" || s.kind == "slidevert" else { return nil }
        if s.vertical {
            let y = leftward ? monitor.minY - current.height + 1 : monitor.maxY - 1
            return Rect(x: current.x, y: y, width: current.width, height: current.height)
        }
        let x = leftward ? monitor.minX - current.width + 1 : monitor.maxX - 1
        return Rect(x: x, y: current.y, width: current.width, height: current.height)
    }
}
```

If `finiteDouble` takes a `Substring` or generic `StringProtocol`, the `String(...)` wrapper is still valid.

- [ ] **Step 4: Run the tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MotionTests 2>&1 | grep -E 'passed|failed|Expectation' | head`
Expected: all MotionTests pass. If `animation = windows, 0` is rejected by the M1 parser, use the form the parser accepts for a disabled leaf (check `AnimationTree.apply`) and keep the assertion.

- [ ] **Step 5: Commit**

```bash
git add Sources/HyprCore/Animation/Motion.swift Tests/HyprCoreTests/MotionTests.swift
git commit -m "feat: plan window motion from Hyprland animation leaves and styles"
```

---

### Task 3: Animator

**Files:**
- Create: `Sources/HyprCore/Animation/Animator.swift`
- Test: `Tests/HyprCoreTests/AnimatorTests.swift`

**Interfaces:**
- Consumes: `MotionPlan`, `MotionTiming` (Task 2), `Bezier` (M1).
- Produces:
  - `public struct FrameAnimation { begun: Rect; goal: Rect; start: Double; timing: MotionTiming; progress(at:) -> Double; value(at:) -> Rect }`
  - `public enum AnimationStep: Equatable { case frame(WindowID, Rect, writesSize: Bool); case finished(WindowID, Rect, parkAt: Point?) }`
  - `public struct Animator { isActive: Bool; animating: Set<WindowID>; current(_:at:) -> Rect?; animate(_:_:live:now:parkAt:); cancel(_:); tick(_ now: Double) -> [AnimationStep] }`

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/AnimatorTests.swift`:

```swift
import Testing
@testable import HyprCore

private let linear = MotionTiming(duration: 1, curve: Bezier.builtIns["linear"]!)
private let a = Rect(x: 0, y: 0, width: 100, height: 100)
private let b = Rect(x: 100, y: 0, width: 300, height: 100)

private func close(_ x: Rect?, _ y: Rect) -> Bool {
    guard let x else { return false }
    return abs(x.x - y.x) < 0.5 && abs(x.y - y.y) < 0.5 && abs(x.width - y.width) < 0.5 && abs(x.height - y.height) < 0.5
}

@Suite struct AnimatorTests {
    @Test func aLiveAnimationWritesEveryFrameWithItsSize() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: true, now: 10)
        guard case .frame(1, let f, let size)? = m.tick(10.5).first else { Issue.record("no frame"); return }
        #expect(close(f, Rect(x: 50, y: 0, width: 200, height: 100)))
        #expect(size)
    }

    @Test func theEndWritesTheExactGoalAndStops() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: true, now: 0)
        #expect(m.tick(1.2) == [.finished(1, b, parkAt: nil)])
        #expect(!m.isActive)
        #expect(m.tick(1.3).isEmpty)
    }

    @Test func aRetargetStartsFromTheCurrentValue() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: true, now: 0)
        let c = Rect(x: 300, y: 0, width: 100, height: 100)
        m.animate(1, MotionPlan(from: a, to: c, timing: linear), live: true, now: 0.5)
        #expect(close(m.current(1, at: 0.5), Rect(x: 50, y: 0, width: 200, height: 100)))
        #expect(close(m.current(1, at: 1.0), Rect(x: 175, y: 0, width: 150, height: 100)))
    }

    @Test func theSameGoalDoesNotRestartTheTimer() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: true, now: 0)
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: true, now: 0.5)
        #expect(m.tick(1.0) == [.finished(1, b, parkAt: nil)])
    }

    @Test func aSlowAppGetsPositionTicksAndOneSizeWriteAtTheMiddle() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: false, now: 0)
        guard case .frame(_, _, let early)? = m.tick(0.2).first,
              case .frame(_, let mid, let midSize)? = m.tick(0.6).first,
              case .frame(_, _, let late)? = m.tick(0.8).first else { Issue.record("missing frames"); return }
        #expect(!early)
        #expect(midSize && mid.size == b.size)
        #expect(!late)
    }

    @Test func aParkGlideEndsWithThePark() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: false, now: 0, parkAt: Point(x: 1511, y: 981))
        #expect(m.tick(2) == [.finished(1, b, parkAt: Point(x: 1511, y: 981))])
    }

    @Test func aNewGoalWithoutParkClearsThePark() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: false, now: 0, parkAt: Point(x: 1511, y: 981))
        m.animate(1, MotionPlan(from: b, to: a, timing: linear), live: true, now: 0.5)
        #expect(m.tick(3) == [.finished(1, a, parkAt: nil)])
    }

    @Test func cancelStopsTheWindow() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: true, now: 0)
        m.animate(2, MotionPlan(from: a, to: b, timing: linear), live: true, now: 0)
        m.cancel(1)
        #expect(m.animating == [2])
        #expect(m.current(1, at: 0.5) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AnimatorTests 2>&1 | tail -5`
Expected: build failure: `cannot find 'Animator' in scope`.

- [ ] **Step 3: Implement `Sources/HyprCore/Animation/Animator.swift`**

```swift
import Foundation

public struct FrameAnimation: Equatable, Sendable {
    public var begun: Rect
    public var goal: Rect
    public var start: Double
    public var timing: MotionTiming

    public func progress(at now: Double) -> Double {
        guard timing.duration > 0 else { return 1 }
        return min(max((now - start) / timing.duration, 0), 1)
    }

    public func value(at now: Double) -> Rect {
        let p = progress(at: now)
        guard p < 1 else { return goal }
        let k = timing.curve.y(at: p)
        func mix(_ from: Double, _ to: Double) -> Double { from + (to - from) * k }
        return Rect(x: mix(begun.x, goal.x), y: mix(begun.y, goal.y), width: mix(begun.width, goal.width), height: mix(begun.height, goal.height))
    }
}

public enum AnimationStep: Equatable, Sendable {
    case frame(WindowID, Rect, writesSize: Bool)
    case finished(WindowID, Rect, parkAt: Point?)
}

public struct Animator: Equatable, Sendable {
    struct Running: Equatable, Sendable {
        var animation: FrameAnimation
        var live: Bool
        var sizeSent: Bool
        var parkAt: Point?
    }

    private var running: [WindowID: Running] = [:]

    public init() {}

    public var isActive: Bool { !running.isEmpty }
    public var animating: Set<WindowID> { Set(running.keys) }

    public func current(_ id: WindowID, at now: Double) -> Rect? { running[id]?.animation.value(at: now) }

    public mutating func animate(_ id: WindowID, _ plan: MotionPlan, live: Bool, now: Double, parkAt: Point? = nil) {
        if let r = running[id], r.animation.goal == plan.to, r.parkAt == parkAt { return }
        let begun = running[id]?.animation.value(at: now) ?? plan.from
        let animation = FrameAnimation(begun: begun, goal: plan.to, start: now, timing: plan.timing)
        running[id] = Running(animation: animation, live: live, sizeSent: begun.size == plan.to.size, parkAt: parkAt)
    }

    public mutating func cancel(_ id: WindowID) { running[id] = nil }

    public mutating func tick(_ now: Double) -> [AnimationStep] {
        var steps: [AnimationStep] = []
        for id in running.keys.sorted() {
            guard var r = running[id] else { continue }
            let p = r.animation.progress(at: now)
            if p >= 1 {
                steps.append(.finished(id, r.animation.goal, parkAt: r.parkAt))
                running[id] = nil
                continue
            }
            var frame = r.animation.value(at: now)
            var writesSize = r.live
            if !r.live && !r.sizeSent && p >= 0.5 {
                frame = Rect(origin: frame.origin, size: r.animation.goal.size)
                writesSize = true
                r.sizeSent = true
            }
            steps.append(.frame(id, frame, writesSize: writesSize))
            running[id] = r
        }
        return steps
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AnimatorTests 2>&1 | grep -E 'passed|failed|Expectation' | head`
Expected: all AnimatorTests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/HyprCore/Animation/Animator.swift Tests/HyprCoreTests/AnimatorTests.swift
git commit -m "feat: add a frame animator with Hyprland retarget semantics"
```

---

### Task 4: Motion engine in the app

**Files:**
- Create: `Sources/HyprOSX/Motion/MotionEngine.swift`
- Modify: `Sources/HyprOSX/Platform/EffectExecutor.swift`
- Modify: `Sources/HyprOSX/AX/AXAppThread.swift` (add `readFrame`)
- Modify: `Sources/HyprOSX/AppController.swift` (create the engine, cancel on close, read back, stop on pause and quit)

**Interfaces:**
- Consumes: `Motion.plan`, `Motion.planOut`, `MotionEnvironment` (Task 2); `Animator` (Task 3); `World.motion(for:)`, `World.monitorFrame(of:)` (Task 1); `AXAppThread.setFrame/setPosition/averageLatencyMs/callCount` (M1).
- Produces:
  - `final class MotionEngine: NSObject` with `init(thread: @escaping (WindowID) -> AXAppThread?, world: @escaping () -> World?)`, `setFrames(_ changes: [FrameChange])`, `park(_ parks: [ParkRequest])`, `cancel(_ id: WindowID)`, `stopAll()`, `var animating: Set<WindowID>`, `var onFrame: (WindowID, Rect) -> Void`, `var onSettled: (WindowID) -> Void`
  - `AXAppThread.readFrame(_ id: WindowID, _ done: @escaping (Rect?) -> Void)` (calls `done` on the main queue)
  - `EffectExecutor.init(tracker:windowPID:environment:motion:)`

This task has no unit tests: all logic it calls is tested in Tasks 1 to 3. It ends with a live check.

- [ ] **Step 1: Add `readFrame` to `AXAppThread`**

Next to `setFrame`:

```swift
    func readFrame(_ id: WindowID, _ done: @escaping (Rect?) -> Void) {
        let queued = perform { [weak self] in
            let frame = self?.windows[id].flatMap { AX.frame($0) }
            DispatchQueue.main.async { done(frame) }
        }
        if !queued { done(nil) }
    }
```

- [ ] **Step 2: Create `Sources/HyprOSX/Motion/MotionEngine.swift`**

```swift
import AppKit
import QuartzCore
import HyprCore

final class MotionEngine: NSObject {
    private var animator = Animator()
    private var written: [WindowID: Rect] = [:]
    private var link: CADisplayLink?
    private let thread: (WindowID) -> AXAppThread?
    private let world: () -> World?
    var onFrame: (WindowID, Rect) -> Void = { _, _ in }
    var onSettled: (WindowID) -> Void = { _ in }

    init(thread: @escaping (WindowID) -> AXAppThread?, world: @escaping () -> World?) {
        self.thread = thread
        self.world = world
        super.init()
    }

    var animating: Set<WindowID> { animator.animating }

    static var environment: MotionEnvironment {
        MotionEnvironment(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                          reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func setFrames(_ changes: [FrameChange]) {
        guard let world = world() else { return }
        let environment = Self.environment
        let now = CACurrentMediaTime()
        for change in changes {
            let t = thread(change.id)
            let live = (t?.callCount ?? 0) == 0 || (t?.averageLatencyMs ?? 0) < world.config.macos.liveResizeMaxLatency
            let current = animator.current(change.id, at: now) ?? written[change.id] ?? world.windows[change.id]?.lastFrame
            let monitor = world.monitorFrame(of: change.id) ?? change.frame
            if let plan = Motion.plan(change, current: current, monitor: monitor, config: world.config, environment: environment,
                                      window: world.motion(for: change.id), live: live) {
                animator.animate(change.id, plan, live: live, now: now)
            } else {
                animator.cancel(change.id)
                t?.setFrame(change.id, change.frame)
                written[change.id] = change.frame
                onFrame(change.id, change.frame)
            }
        }
        startIfNeeded()
    }

    func park(_ parks: [ParkRequest]) {
        guard let world = world() else { return }
        let environment = Self.environment
        let now = CACurrentMediaTime()
        for p in parks {
            let w = world.windows[p.id]
            let current = animator.current(p.id, at: now) ?? w?.appliedFrame ?? w?.lastFrame
            if let current, let monitor = world.monitorFrame(of: p.id),
               let plan = Motion.planOut(p, current: current, monitor: monitor, config: world.config, environment: environment,
                                         window: world.motion(for: p.id)) {
                animator.animate(p.id, plan, live: false, now: now, parkAt: p.origin)
            } else {
                animator.cancel(p.id)
                thread(p.id)?.setPosition(p.id, p.origin)
            }
            written[p.id] = nil
        }
        startIfNeeded()
    }

    func cancel(_ id: WindowID) {
        animator.cancel(id)
        written[id] = nil
    }

    func stopAll() {
        animator = Animator()
        written = [:]
        link?.invalidate()
        link = nil
    }

    private func startIfNeeded() {
        guard animator.isActive, link == nil, let screen = NSScreen.main else { return }
        let l = screen.displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ sender: CADisplayLink) {
        for step in animator.tick(CACurrentMediaTime()) {
            switch step {
            case .frame(let id, let frame, let writesSize):
                if writesSize { thread(id)?.setFrame(id, frame) } else { thread(id)?.setPosition(id, frame.origin) }
                written[id] = frame
                onFrame(id, frame)
            case .finished(let id, let frame, let parkAt):
                if let parkAt {
                    thread(id)?.setPosition(id, parkAt)
                    written[id] = nil
                } else {
                    thread(id)?.setFrame(id, frame)
                    written[id] = frame
                    onFrame(id, frame)
                    onSettled(id)
                }
            }
        }
        if !animator.isActive {
            sender.invalidate()
            link = nil
        }
    }
}
```

- [ ] **Step 3: Route frames and parks through the engine**

In `EffectExecutor.swift`, add `private let motion: MotionEngine`, take it as the last `init` parameter, and replace the two cases:

```swift
            case .setFrames(let changes):
                motion.setFrames(changes)
            case .park(let parks):
                motion.park(parks)
```

- [ ] **Step 4: Wire the engine in `AppController.swift`**

- Add `private var motion: MotionEngine!`.
- Before `executor = EffectExecutor(...)`, create it:

```swift
        motion = MotionEngine(thread: { [weak self] id in
            self?.world?.windows[id].flatMap { self?.tracker.threads[$0.pid] }
        }, world: { [weak self] in self?.world })
        motion.onSettled = { [weak self] id in self?.readBack(id) }
```

- Pass `motion: motion` to `EffectExecutor`.
- Add:

```swift
    private func readBack(_ id: WindowID) {
        guard let pid = world?.windows[id]?.pid else { return }
        tracker.threads[pid]?.readFrame(id) { [weak self] frame in
            guard let frame else { return }
            self?.handle(.windowFrameChanged(id, frame, userDriven: false))
        }
    }
```

- At the top of `handle(_:)`, after the `guard`, cancel animations of windows that leave:

```swift
        switch event {
        case .windowDisappeared(let id): motion.cancel(id)
        case .appTerminated(let pid): for w in world.windows.values where w.pid == pid { motion.cancel(w.id) }
        default: break
        }
```

- In `togglePause()` call `motion.stopAll()` before `execute(world.releaseParked())`. Do the same in `applicationWillTerminate` before its release of parked windows.

- [ ] **Step 5: Build, test, install**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build 2>&1 | grep -E 'warning:|error:' ; DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | grep -E 'Test run with|✘' | head -3 ; scripts/build-app.sh --install 2>&1 | grep -E 'installed|error'
```
Expected: no warnings or errors, all tests pass, `installed ...`.

- [ ] **Step 6: Live check with hyprctl**

Run (the owner's config uses `workspaces ... fade` and `windowsIn ... popin 87%`):
```bash
H=~/.local/bin/hyprctl; $H dispatch workspace 2; /bin/sleep 1; $H dispatch workspace 1; /bin/sleep 1; $H clients -j | /usr/bin/python3 -c 'import json,sys; [print(c["address"],c["workspace"]["id"],c["at"],c["size"]) for c in json.load(sys.stdin)]'
```
Expected: every window of workspace 1 is back at its tile frame (same `at`/`size` as before the switch). Then measure idle CPU: `H=~/.local/bin/hyprctl; a=$($H perf | head -1); ALLOW_SLEEP=1 /bin/sleep 60; $H perf | head -1; echo "$a"`. Expected: the CPU line stays below 0.1% over the 60 s (the display link is gone after the motion ends).

- [ ] **Step 7: Commit**

```bash
git add Sources/HyprOSX
git commit -m "feat: animate window frames with a display link that runs only while moving"
```

---

### Task 5: Decoration model

**Files:**
- Create: `Sources/HyprCore/World/World+Decorations.swift`
- Modify: `Sources/HyprCore/Config/Options.swift` (`DecorationOptions.dimAround`, option `decoration:dim_around`, remove it from the ignored list)
- Test: `Tests/HyprCoreTests/DecorationTests.swift`

**Interfaces:**
- Consumes: `World.dynamicOutcome(for:)` (Task 1), `World.borderSize(for:)`, `World.borderWidth(_:)`, `ConfigValue.gradient(_:)`, `isVisible(_:)` (M1).
- Produces:
  - `public struct Decoration: Equatable, Sendable { id: WindowID; frame: Rect; border: Gradient?; borderWidth: Double; isActive: Bool; dim: Double }`
  - `public struct DecorationSet: Equatable, Sendable { windows: [Decoration]; dimAround: [WindowID]; dimAroundStrength: Double }`
  - `World.decorations() -> DecorationSet` (public)
  - `DecorationOptions.dimAround: Double` (default 0.4)

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/DecorationTests.swift`:

```swift
import Testing
@testable import HyprCore

private let colors = "general {\n border_size = 2\n col.active_border = rgb(ff0000)\n col.inactive_border = rgb(00ff00)\n}\n"

private func run(_ w: World, _ dispatcher: String, _ arguments: String = "") {
    _ = w.run(try! CommandParser.parse(dispatcher: dispatcher, arguments: arguments).get())
}

private func pair(_ text: String) -> World {
    let w = world(colors + text)
    _ = w.handle(.windowAppeared(snap(1)))
    _ = w.handle(.windowAppeared(snap(2, pid: 200)))
    run(w, "focuswindow", "address:0x1")
    return w
}

private func deco(_ w: World, _ id: WindowID) -> Decoration? { w.decorations().windows.first { $0.id == id } }

@Suite struct DecorationTests {
    @Test func theFocusedWindowGetsTheActiveColor() {
        let w = pair("")
        #expect(deco(w, 1)?.isActive == true)
        #expect(deco(w, 1)?.border?.colors.first?.r == 1)
        #expect(deco(w, 2)?.border?.colors.first?.g == 1)
        #expect(deco(w, 1)?.borderWidth == 2)
        #expect(deco(w, 1)?.frame == w.windows[1]?.appliedFrame)
    }

    @Test func aTransparentInactiveColorMeansNoInactiveBorder() {
        let w = pair("general {\n col.inactive_border = rgba(00000000)\n}\n")
        #expect(deco(w, 2)?.border == nil)
        #expect(deco(w, 1)?.border != nil)
    }

    @Test func zeroWidthAndFullscreenMeanNoBorder() {
        let zero = pair("general {\n border_size = 0\n}\n")
        #expect(deco(zero, 1)?.border == nil)
        let full = pair("")
        run(full, "fullscreen", "0")
        #expect(deco(full, 1)?.border == nil)
    }

    @Test func parkedWindowsGetNoDecoration() {
        let w = pair("")
        run(w, "movetoworkspacesilent", "2,address:0x2")
        #expect(deco(w, 2) == nil)
        #expect(deco(w, 1) != nil)
    }

    @Test func rulesAndSetpropOverrideTheBorder() {
        let w = pair("windowrule = border_size 5, match:class Ghostty\n")
        #expect(deco(w, 1)?.borderWidth == 5)
        run(w, "setprop", "address:0x1 border_size 7")
        #expect(deco(w, 1)?.borderWidth == 7)
        run(w, "setprop", "address:0x1 border_color rgb(0000ff)")
        #expect(deco(w, 1)?.border?.colors.first?.b == 1)
    }

    @Test func dimInactiveDimsOnlyInactiveTiledWindows() {
        let w = pair("decoration {\n dim_inactive = true\n dim_strength = 0.3\n}\n")
        #expect(deco(w, 1)?.dim == 0)
        #expect(deco(w, 2)?.dim == 0.3)
        run(w, "setfloating", "address:0x2")
        #expect(deco(w, 2)?.dim == 0)
    }

    @Test func dimAroundListsMatchingVisibleWindows() {
        let w = pair("windowrule = dim_around on, match:class Ghostty\n")
        #expect(w.decorations().dimAround == [1, 2])
        #expect(w.decorations().dimAroundStrength == 0.4)
    }
}
```

`snap(2, pid: 200)` has app name "Ghostty" too, so the `dim_around` rule matches both windows.

- [ ] **Step 2: Run the tests to see them fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DecorationTests 2>&1 | tail -5`
Expected: build failure: `cannot find type 'Decoration' in scope`.

- [ ] **Step 3: Read `decoration:dim_around`**

In `Options.swift`: add `public var dimAround = 0.4` to `DecorationOptions`, add `float("decoration:dim_around", \.decoration.dimAround)` next to `decoration:dim_strength`, and delete `"decoration:dim_around"` from the ignored-options list.

- [ ] **Step 4: Implement `Sources/HyprCore/World/World+Decorations.swift`**

```swift
import Foundation

public struct Decoration: Equatable, Sendable {
    public var id: WindowID
    public var frame: Rect
    public var border: Gradient?
    public var borderWidth: Double
    public var isActive: Bool
    public var dim: Double
}

public struct DecorationSet: Equatable, Sendable {
    public var windows: [Decoration] = []
    public var dimAround: [WindowID] = []
    public var dimAroundStrength = 0.0
}

extension World {
    public func decorations() -> DecorationSet {
        var set = DecorationSet()
        set.dimAroundStrength = config.decoration.dimAround
        for id in windows.keys.sorted() {
            guard let w = windows[id], w.suspended == nil, !w.isParked, let frame = w.appliedFrame,
                  let ws = workspaces[w.workspace], isVisible(ws.id) else { continue }
            let rules = dynamicOutcome(for: w)
            if rules.dimAround { set.dimAround.append(id) }
            let active = focusedWindow == id
            let width = w.props["border_size"].flatMap { finiteDouble($0) }.map(World.borderWidth)
                ?? rules.borderSize.map { World.borderWidth(Double($0)) }
                ?? borderSize(for: ws)
            var border = w.props["border_color"].flatMap { ConfigValue.gradient($0) }
                ?? (active ? rules.activeBorder ?? config.general.activeBorder : rules.inactiveBorder ?? config.general.inactiveBorder)
            if w.fullscreenMode != nil || width <= 0 || border?.isFullyTransparent == true { border = nil }
            let dims = config.decoration.dimInactive && !active && !w.isFloating && w.fullscreenMode == nil
            set.windows.append(Decoration(id: id, frame: frame, border: border, borderWidth: width, isActive: active,
                                          dim: dims ? config.decoration.dimStrength : 0))
        }
        return set
    }
}
```

- [ ] **Step 5: Run the tests and the full suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | grep -E 'Test run with|✘' | head`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/HyprCore Tests/HyprCoreTests/DecorationTests.swift
git commit -m "feat: compute per-window border and dim decorations"
```

---

### Task 6: Border windows

**Files:**
- Create: `Sources/HyprOSX/UI/BorderWindows.swift`
- Modify: `Sources/HyprOSX/AppController.swift` (apply decorations after every effect batch, follow motion ticks, reorder after raise, clear on pause and quit)
- Modify: `Sources/HyprOSX/Platform/EffectExecutor.swift` (report `.raise` and `.focus` ids)

**Interfaces:**
- Consumes: `World.decorations()`, `DecorationSet`, `Decoration` (Task 5); `Motion.decorationTiming` (Task 2); `MotionEngine.onFrame`, `MotionEngine.animating` (Task 4).
- Produces:
  - `final class BorderWindows` with `apply(_ set: DecorationSet, animating: Set<WindowID>, radius: Double, colorTiming: MotionTiming?, angle: (timing: MotionTiming, loop: Bool)?)`, `move(_ id: WindowID, _ frame: Rect)`, `reorder(_ id: WindowID)`, `removeAll()`
  - `static func BorderWindows.defaultRadius() -> Double`
  - `EffectExecutor.onRaised: (WindowID) -> Void`

Spec 7.4 says the ring reads the real window radius from the WindowServer. No public API returns it, so `macos:border_radius = -1` uses a per-version fallback: 16 pt on macOS 26 and later, 10 pt before. Record this as a ruling and in spec 12.

- [ ] **Step 1: Create `Sources/HyprOSX/UI/BorderWindows.swift`**

```swift
import AppKit
import QuartzCore
import HyprCore

private final class BorderView: NSView {
    let ring = CAShapeLayer()
    let gradient = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let root = CALayer()
        root.addSublayer(gradient)
        ring.fillRule = .evenOdd
        root.mask = ring
        layer = root
    }

    required init?(coder: NSCoder) { nil }
}

final class BorderWindows {
    private struct Entry {
        let window: NSWindow
        let view: BorderView
        var state: Decoration
    }

    private var entries: [WindowID: Entry] = [:]
    private var radius = 10.0

    static func defaultRadius() -> Double {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 16 : 10
    }

    func apply(_ set: DecorationSet, animating: Set<WindowID>, radius: Double, colorTiming: MotionTiming?, angle: (timing: MotionTiming, loop: Bool)?) {
        let radiusChanged = radius != self.radius
        self.radius = radius
        var wanted: [WindowID: Decoration] = [:]
        for d in set.windows where d.border != nil { wanted[d.id] = d }
        for id in entries.keys where wanted[id] == nil {
            entries[id]?.window.orderOut(nil)
            entries[id] = nil
        }
        for (id, d) in wanted {
            if var e = entries[id] {
                if e.state.border != d.border { paint(e.view, d, timing: colorTiming) }
                if !animating.contains(id), radiusChanged || e.state.frame != d.frame || e.state.borderWidth != d.borderWidth {
                    place(e.window, e.view, frame: d.frame, width: d.borderWidth)
                }
                if d.isActive && !e.state.isActive {
                    spin(e.view, angle)
                    e.window.order(.below, relativeTo: Int(id))
                }
                e.state = d
                entries[id] = e
            } else {
                let e = make(d)
                entries[id] = e
                paint(e.view, d, timing: nil)
                place(e.window, e.view, frame: d.frame, width: d.borderWidth)
                spin(e.view, angle)
                e.window.order(.below, relativeTo: Int(id))
            }
        }
    }

    func move(_ id: WindowID, _ frame: Rect) {
        guard let e = entries[id] else { return }
        place(e.window, e.view, frame: frame, width: e.state.borderWidth)
    }

    func reorder(_ id: WindowID) {
        entries[id]?.window.order(.below, relativeTo: Int(id))
    }

    func removeAll() {
        for e in entries.values { e.window.orderOut(nil) }
        entries = [:]
    }

    private func make(_ d: Decoration) -> Entry {
        let view = BorderView(frame: .zero)
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.contentView = view
        return Entry(window: window, view: view, state: d)
    }

    private func place(_ window: NSWindow, _ view: BorderView, frame f: Rect, width w: Double) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let outer = NSRect(x: f.x - w, y: primaryHeight - f.maxY - w, width: f.width + 2 * w, height: f.height + 2 * w)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.setFrame(outer, display: false)
        let bounds = NSRect(origin: .zero, size: outer.size)
        let path = CGMutablePath()
        path.addRoundedRect(in: bounds, cornerWidth: radius + w, cornerHeight: radius + w)
        path.addRoundedRect(in: bounds.insetBy(dx: w, dy: w), cornerWidth: radius, cornerHeight: radius)
        view.ring.frame = bounds
        view.ring.path = path
        let side = hypot(bounds.width, bounds.height)
        view.gradient.frame = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        CATransaction.commit()
    }

    private func paint(_ view: BorderView, _ d: Decoration, timing: MotionTiming?) {
        guard let g = d.border else { return }
        var colors = g.colors.map { CGColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: $0.a) }
        if colors.count == 1 { colors.append(colors[0]) }
        let radians = g.angleDegrees * .pi / 180
        let start = CGPoint(x: 0.5 - cos(radians) / 2, y: 0.5 - sin(radians) / 2)
        let end = CGPoint(x: 0.5 + cos(radians) / 2, y: 0.5 + sin(radians) / 2)
        if let timing {
            let fade = CABasicAnimation(keyPath: "colors")
            fade.fromValue = view.gradient.presentation()?.colors ?? view.gradient.colors
            fade.toValue = colors
            fade.duration = timing.duration
            fade.timingFunction = Self.function(timing.curve)
            view.gradient.add(fade, forKey: "colors")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.gradient.colors = colors
        view.gradient.startPoint = start
        view.gradient.endPoint = end
        CATransaction.commit()
    }

    private func spin(_ view: BorderView, _ angle: (timing: MotionTiming, loop: Bool)?) {
        guard let angle else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = 2 * Double.pi
        turn.duration = angle.timing.duration
        turn.timingFunction = Self.function(angle.timing.curve)
        turn.repeatCount = angle.loop ? .infinity : 1
        view.gradient.add(turn, forKey: "angle")
    }

    private static func function(_ curve: Bezier) -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(curve.p1.x), Float(curve.p1.y), Float(curve.p2.x), Float(curve.p2.y))
    }
}
```

- [ ] **Step 2: Report raises from the executor**

In `EffectExecutor.swift` add `var onRaised: (WindowID) -> Void = { _ in }` and call it after `thread(id)?.raise(id)` and after `thread(id)?.focus(id)`.

- [ ] **Step 3: Wire borders in `AppController.swift`**

- Add `private let borders = BorderWindows()`.
- After creating `motion`, add `motion.onFrame = { [weak self] id, frame in self?.borders.move(id, frame) }` and `executor.onRaised = { [weak self] id in self?.borders.reorder(id) }`.
- Add:

```swift
    private func decorate() {
        guard let world, !paused else { return }
        let c = world.config
        let angleLeaf = c.animations.leaf("borderangle")
        let angle = Motion.decorationTiming("borderangle", config: c).map { (timing: $0, loop: angleLeaf.style == "loop") }
        borders.apply(world.decorations(), animating: motion.animating,
                      radius: c.macos.borderRadius >= 0 ? Double(c.macos.borderRadius) : BorderWindows.defaultRadius(),
                      colorTiming: Motion.decorationTiming("border", config: c), angle: angle)
    }
```

- In `execute(_:)`, call `decorate()` after `executor.execute(effects)` (inside the `if !effects.isEmpty`).
- In `readBack`, after `handle(...)`, call `self?.borders.move(id, frame)`.
- In `togglePause()` and `applicationWillTerminate`, call `borders.removeAll()`.

- [ ] **Step 4: Build, test, install**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build 2>&1 | grep -E 'warning:|error:' ; DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | grep -E 'Test run with|✘' | head -3 ; scripts/build-app.sh --install 2>&1 | grep -E 'installed|error'
```
Expected: clean build, all tests pass, installed.

- [ ] **Step 5: Live check**

Ask the owner to look at workspace 1: the focused window has the green-yellow gradient ring (owner `col.active_border`), the others the dark ring, the ring sits outside the window edge and follows it during a workspace switch and a Ctrl+⌥+L resize, and clicks near a ring reach the app below. Measure memory: `ps -o rss= -p $(pgrep -x HyprOSX)`; expected below 51200 (KB).

- [ ] **Step 6: Commit**

```bash
git add Sources/HyprOSX
git commit -m "feat: draw border rings below managed windows"
```

---

### Task 7: Dim overlays

**Files:**
- Create: `Sources/HyprOSX/UI/DimWindows.swift`
- Modify: `Sources/HyprOSX/AppController.swift` (`decorate()`, motion ticks, pause and quit)

**Interfaces:**
- Consumes: `DecorationSet` (Task 5), `Motion.decorationTiming` (Task 2), `World.monitorFrame(of:)` (Task 1).
- Produces: `final class DimWindows` with `apply(_ set: DecorationSet, animating: Set<WindowID>, timing: MotionTiming?, monitorFrame: (WindowID) -> Rect?)`, `move(_ id: WindowID, _ frame: Rect)`, `removeAll()`.

- [ ] **Step 1: Create `Sources/HyprOSX/UI/DimWindows.swift`**

```swift
import AppKit
import HyprCore

final class DimWindows {
    private var inactive: [WindowID: NSWindow] = [:]
    private var around: (id: WindowID, window: NSWindow)?

    func apply(_ set: DecorationSet, animating: Set<WindowID>, timing: MotionTiming?, monitorFrame: (WindowID) -> Rect?) {
        var wanted: [WindowID: Decoration] = [:]
        for d in set.windows where d.dim > 0 { wanted[d.id] = d }
        for (id, window) in inactive where wanted[id] == nil {
            fade(window, to: 0, timing: timing) { window.orderOut(nil) }
            inactive[id] = nil
        }
        for (id, d) in wanted {
            let window = inactive[id] ?? make(alpha: d.dim)
            if inactive[id] == nil {
                inactive[id] = window
                window.alphaValue = 0
                place(window, d.frame)
                window.order(.above, relativeTo: Int(id))
                fade(window, to: 1, timing: timing) {}
            } else if !animating.contains(id) {
                place(window, d.frame)
            }
        }
        let target = set.dimAround.last
        if let current = around, current.id != target {
            fade(current.window, to: 0, timing: timing) { current.window.orderOut(nil) }
            around = nil
        }
        if let target, around == nil, let frame = monitorFrame(target) {
            let window = make(alpha: set.dimAroundStrength)
            window.alphaValue = 0
            place(window, frame)
            window.order(.below, relativeTo: Int(target))
            fade(window, to: 1, timing: timing) {}
            around = (target, window)
        }
    }

    func move(_ id: WindowID, _ frame: Rect) {
        if let window = inactive[id] { place(window, frame) }
    }

    func removeAll() {
        for window in inactive.values { window.orderOut(nil) }
        inactive = [:]
        around?.window.orderOut(nil)
        around = nil
    }

    private func make(alpha: Double) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(alpha)
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.transient, .ignoresCycle]
        return window
    }

    private func place(_ window: NSWindow, _ f: Rect) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        window.setFrame(NSRect(x: f.x, y: primaryHeight - f.maxY, width: f.width, height: f.height), display: false)
    }

    private func fade(_ window: NSWindow, to alpha: CGFloat, timing: MotionTiming?, done: @escaping () -> Void) {
        guard let timing else {
            window.alphaValue = alpha
            done()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = timing.duration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: Float(timing.curve.p1.x), Float(timing.curve.p1.y),
                                                       Float(timing.curve.p2.x), Float(timing.curve.p2.y))
            window.animator().alphaValue = alpha
        }, completionHandler: done)
    }
}
```

- [ ] **Step 2: Wire it**

In `AppController.swift`: add `private let dims = DimWindows()`; in `decorate()` add

```swift
        dims.apply(world.decorations(), animating: motion.animating, timing: Motion.decorationTiming("fadeDim", config: c),
                   monitorFrame: { [weak world] id in world?.monitorFrame(of: id) })
```

Compute `world.decorations()` once in `decorate()` and pass the same value to `borders.apply` and `dims.apply`. Extend `motion.onFrame` to also call `self?.dims.move(id, frame)`. Call `dims.removeAll()` next to `borders.removeAll()`.

- [ ] **Step 3: Build, test, install, live check**

Run the Task 6 Step 4 command. Then:
```bash
H=~/.local/bin/hyprctl; $H keyword decoration:dim_inactive true; /bin/sleep 3; $H keyword decoration:dim_inactive false
```
Expected: for about 3 s the inactive tiled windows on the screen are darker, the focused one is not, then the dim fades away. Clicks on a dimmed window still focus it.

- [ ] **Step 4: Commit**

```bash
git add Sources/HyprOSX
git commit -m "feat: add dim_inactive and dim_around overlays with fades"
```

---

### Task 8: Mouse and scroll binds in HyprCore

**Files:**
- Create: `Sources/HyprCore/Input/MouseBindMatcher.swift`
- Create: `Sources/HyprCore/World/World+MouseBinds.swift`
- Modify: `Sources/HyprCore/World/Effects.swift` (three `PlatformEvent` cases)
- Modify: `Sources/HyprCore/World/World.swift` (`mouseDrag` property, `apply` cases, clear `mouseDrag` where `dragging` is cleared)
- Modify: `Sources/HyprCore/World/World+Events.swift` (clear `mouseDrag` in `suspend`)
- Test: `Tests/HyprCoreTests/MouseBindTests.swift`

**Interfaces:**
- Consumes: `Bind`, `BindTrigger.mouse(Int)`, `BindTrigger.scroll(ScrollDirection)`, `BindFlags.mouse/.release`, `Modifiers` (M1); `World.windowAt(_:)`, `endDrag(at:)`, `clearPlacement(_:)`, `layoutContext(_:)`, `focusWindow(_:warp:emitEffect:)`, `Corner` (M1); `FrameReason.manualResize` (Task 1).
- Produces:
  - `public enum MouseBindAction: Equatable, Sendable { case move, resize }`
  - `public enum MouseDecision: Equatable, Sendable { case pass, consume, run([Bind]), start(MouseBindAction, Point), move(Point), end(Point) }`
  - `public struct MouseBindMatcher` with `init()`, `setBinds(_ binds: [Bind], dragThreshold: Int, scrollEventDelayMs: Int)`, `isEmpty: Bool`, `down(button: Int, modifiers: Modifiers, at: Point) -> MouseDecision`, `dragged(to: Point) -> MouseDecision`, `up(button: Int, modifiers: Modifiers, at: Point) -> MouseDecision`, `scroll(_ direction: ScrollDirection, modifiers: Modifiers, now: Double) -> MouseDecision`
  - `PlatformEvent.mouseBindStarted(MouseBindAction, Point)`, `.mouseBindMoved(Point)`, `.mouseBindEnded(Point)`
  - `World.resizedFloating(_ f: Rect, by d: Point, corner: Corner) -> Rect` (static, internal)

Button numbers: `button` is the CGEvent button number (left 0, right 1, middle 2, ...); the bind trigger is `mouse:272 + button`.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/MouseBindTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter Mouse 2>&1 | tail -5`
Expected: build failure: `cannot find 'MouseBindMatcher' in scope`.

- [ ] **Step 3: Implement `Sources/HyprCore/Input/MouseBindMatcher.swift`**

```swift
import Foundation

public enum MouseBindAction: Equatable, Sendable { case move, resize }

public enum MouseDecision: Equatable, Sendable {
    case pass
    case consume
    case run([Bind])
    case start(MouseBindAction, Point)
    case move(Point)
    case end(Point)
}

public struct MouseBindMatcher: Sendable {
    public static let buttonBase = 272

    private struct Press: Sendable {
        var button: Int
        var action: MouseBindAction
        var origin: Point
        var started: Bool
    }

    private var binds: [Bind] = []
    private var threshold = 0.0
    private var scrollDelay = 0.0
    private var press: Press?
    private var claimed: Set<Int> = []
    private var lastScroll = -Double.infinity

    public init() {}

    public var isEmpty: Bool { binds.isEmpty }

    public mutating func setBinds(_ binds: [Bind], dragThreshold: Int, scrollEventDelayMs: Int) {
        self.binds = binds.filter {
            switch $0.trigger {
            case .mouse, .scroll: return true
            case .key, .catchall: return false
            }
        }
        threshold = Double(max(0, dragThreshold))
        scrollDelay = Double(max(0, scrollEventDelayMs)) / 1000
    }

    static func clean(_ m: Modifiers) -> Modifiers { m.intersection([.command, .option, .control, .shift, .function]) }

    static func action(_ dispatcher: String) -> MouseBindAction? {
        switch dispatcher.lowercased() {
        case "movewindow": return .move
        case "resizewindow": return .resize
        default: return nil
        }
    }

    public mutating func down(button: Int, modifiers: Modifiers, at p: Point) -> MouseDecision {
        let trigger = BindTrigger.mouse(Self.buttonBase + button)
        let mods = Self.clean(modifiers)
        let matching = binds.filter { $0.trigger == trigger && $0.modifiers == mods }
        guard !matching.isEmpty else { return .pass }
        claimed.insert(button)
        if let drag = matching.first(where: { $0.flags.contains(.mouse) }), let action = Self.action(drag.dispatcher) {
            press = Press(button: button, action: action, origin: p, started: threshold == 0)
            return threshold == 0 ? .start(action, p) : .consume
        }
        let onPress = matching.filter { !$0.flags.contains(.mouse) && !$0.flags.contains(.release) }
        return onPress.isEmpty ? .consume : .run(onPress)
    }

    public mutating func dragged(to p: Point) -> MouseDecision {
        guard var current = press else { return claimed.isEmpty ? .pass : .consume }
        if !current.started {
            guard hypot(p.x - current.origin.x, p.y - current.origin.y) >= threshold else { return .consume }
            current.started = true
            press = current
            return .start(current.action, current.origin)
        }
        return .move(p)
    }

    public mutating func up(button: Int, modifiers: Modifiers, at p: Point) -> MouseDecision {
        guard claimed.remove(button) != nil else { return .pass }
        if let current = press, current.button == button {
            press = nil
            return current.started ? .end(p) : .consume
        }
        let trigger = BindTrigger.mouse(Self.buttonBase + button)
        let mods = Self.clean(modifiers)
        let onRelease = binds.filter { $0.trigger == trigger && $0.modifiers == mods && $0.flags.contains(.release) }
        return onRelease.isEmpty ? .consume : .run(onRelease)
    }

    public mutating func scroll(_ direction: ScrollDirection, modifiers: Modifiers, now: Double) -> MouseDecision {
        let mods = Self.clean(modifiers)
        let matching = binds.filter { $0.trigger == .scroll(direction) && $0.modifiers == mods }
        guard !matching.isEmpty else { return .pass }
        guard now - lastScroll >= scrollDelay else { return .consume }
        lastScroll = now
        return .run(matching)
    }
}
```

- [ ] **Step 4: Add the events and the World handling**

In `Effects.swift`, add to `PlatformEvent`:

```swift
    case mouseBindStarted(MouseBindAction, Point)
    case mouseBindMoved(Point)
    case mouseBindEnded(Point)
```

In `World.swift`: next to `var dragging: WindowID?` add `var mouseDrag: MouseDrag?`; in `apply(_:)` add

```swift
        case .mouseBindStarted(let action, let point): mouseBindStarted(action, at: point)
        case .mouseBindMoved(let point): mouseBindMoved(to: point)
        case .mouseBindEnded(let point): mouseBindEnded(at: point)
```

Where `World.swift` (around line 488) and `World+Events.swift` (`suspend`) set `dragging = nil` for a window that leaves, also add `if mouseDrag?.id == id { mouseDrag = nil }` (use the local id name of that function).

Create `Sources/HyprCore/World/World+MouseBinds.swift`:

```swift
import Foundation

struct MouseDrag: Equatable, Sendable {
    var id: WindowID
    var action: MouseBindAction
    var start: Point
    var last: Point
    var corner: Corner
    var startFrame: Rect
}

extension World {
    func mouseBindStarted(_ action: MouseBindAction, at p: Point) {
        cursor = p
        guard let id = windowAt(p), let w = windows[id], w.suspended == nil, w.fullscreenMode == nil else { return }
        let frame = w.appliedFrame ?? w.lastFrame
        let left = p.x < frame.center.x, top = p.y < frame.center.y
        let corner: Corner = top ? (left ? .topLeft : .topRight) : (left ? .bottomLeft : .bottomRight)
        mouseDrag = MouseDrag(id: id, action: action, start: p, last: p, corner: corner, startFrame: frame)
        clearPlacement(id)
        if action == .move && !w.isFloating {
            dragging = id
            dragIsResize = false
        }
        focusWindow(id, warp: false, emitEffect: true)
    }

    func mouseBindMoved(to p: Point) {
        cursor = p
        guard var drag = mouseDrag, let w = windows[drag.id], var ws = workspaces[w.workspace] else { return }
        let total = p - drag.start
        let step = p - drag.last
        drag.last = p
        mouseDrag = drag
        switch (drag.action, w.isFloating) {
        case (.move, true):
            windows[drag.id]?.floatingFrame = Rect(origin: drag.startFrame.origin + total, size: drag.startFrame.size)
            refresh([ws.id], reason: .manualResize)
        case (.move, false):
            let frame = Rect(origin: drag.startFrame.origin + total, size: drag.startFrame.size)
            windows[drag.id]?.lastFrame = frame
            emit(.setFrames([FrameChange(id: drag.id, frame: frame, reason: .manualResize)]))
        case (.resize, true):
            windows[drag.id]?.floatingFrame = World.resizedFloating(drag.startFrame, by: total, corner: drag.corner)
            refresh([ws.id], reason: .manualResize)
        case (.resize, false):
            let ctx = layoutContext(ws)
            ws.layout.update { $0.resize(drag.id, by: step, corner: drag.corner, ctx) }
            workspaces[ws.id] = ws
            refresh([ws.id], reason: .manualResize)
        }
    }

    func mouseBindEnded(at p: Point) {
        cursor = p
        guard let drag = mouseDrag else { return }
        mouseDrag = nil
        if drag.action == .move, dragging == drag.id {
            endDrag(at: p)
            return
        }
        if let w = windows[drag.id] { refresh([w.workspace]) }
        emit(.saveState)
    }

    static func resizedFloating(_ f: Rect, by d: Point, corner: Corner) -> Rect {
        let movesLeft = corner == .topLeft || corner == .bottomLeft
        let movesTop = corner == .topLeft || corner == .topRight
        let width = max(50, f.width + (movesLeft ? -d.x : d.x))
        let height = max(50, f.height + (movesTop ? -d.y : d.y))
        return Rect(x: movesLeft ? f.maxX - width : f.minX, y: movesTop ? f.maxY - height : f.minY, width: width, height: height)
    }
}
```

`clearPlacement` returns a `Bool`; if it is not `@discardableResult`, write `_ = clearPlacement(id)`. If the layout `resize` method has a different label set, call it the same way `frameChanged` in `World+Events.swift` does.

- [ ] **Step 5: Run the tests and the full suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | grep -E 'Test run with|✘' | head`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/HyprCore Tests/HyprCoreTests/MouseBindTests.swift
git commit -m "feat: add mouse and scroll bind matching and mouse drags in the world"
```

---

### Task 9: Mouse event tap

**Files:**
- Create: `Sources/HyprOSX/Input/MouseTap.swift`
- Modify: `Sources/HyprOSX/AppController.swift` (install with the binds, route decisions, stop on pause and quit)

**Interfaces:**
- Consumes: `MouseBindMatcher`, `MouseDecision` (Task 8); `World.activeBinds`, `config.bindsOptions.dragThreshold/scrollEventDelay` (M1); `runBinds(_:)`, `handle(_:)`, `updateDropPreview()`, `dropPreview` (M1).
- Produces: `final class MouseTap` with `init(onDecision: @escaping (MouseDecision) -> Void)`, `update(_ binds: [Bind], dragThreshold: Int, scrollEventDelayMs: Int) -> Bool` (false when the tap could not start), `stop()`.

The tap pattern is `Sources/HyprOSX/Input/KeyTap.swift`: same thread, run loop, lock, re-enable and stop logic. Copy that structure; only the mask and the handler differ.

- [ ] **Step 1: Create `Sources/HyprOSX/Input/MouseTap.swift`**

```swift
import CoreGraphics
import Foundation
import QuartzCore
import HyprCore

private func mouseTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let info else { return Unmanaged.passUnretained(event) }
    let consumed = Unmanaged<MouseTap>.fromOpaque(info).takeUnretainedValue().handle(type, event)
    return consumed ? nil : Unmanaged.passUnretained(event)
}

final class MouseTap {
    private let onDecision: (MouseDecision) -> Void
    private let lock = NSLock()
    private var matcher = MouseBindMatcher()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)

    init(onDecision: @escaping (MouseDecision) -> Void) { self.onDecision = onDecision }

    func update(_ binds: [Bind], dragThreshold: Int, scrollEventDelayMs: Int) -> Bool {
        var next = MouseBindMatcher()
        next.setBinds(binds, dragThreshold: dragThreshold, scrollEventDelayMs: scrollEventDelayMs)
        guard !next.isEmpty else {
            stop()
            return true
        }
        lock.lock()
        matcher = next
        let running = port != nil
        lock.unlock()
        return running || start()
    }

    func stop() {
        lock.lock()
        matcher = MouseBindMatcher()
        let stopped = (port: port, runLoop: runLoop)
        port = nil
        runLoop = nil
        lock.unlock()
        guard let port = stopped.port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let rl = stopped.runLoop {
            CFRunLoopStop(rl)
            _ = finished.wait(timeout: .now() + 1)
        }
    }

    private static let mask: CGEventMask = [
        CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel,
    ].reduce(0) { $0 | (1 << $1.rawValue) }

    private func start() -> Bool {
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: Self.mask, callback: mouseTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        lock.lock()
        self.port = port
        lock.unlock()
        let thread = Thread { [weak self] in
            guard let self else { return }
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            let rl = CFRunLoopGetCurrent()
            CFRunLoopAddSource(rl, source, .commonModes)
            self.lock.lock()
            self.runLoop = rl
            self.lock.unlock()
            CGEvent.tapEnable(tap: port, enable: true)
            self.ready.signal()
            CFRunLoopRun()
            self.finished.signal()
        }
        thread.name = "dev.hyprosx.mousetap"
        thread.start()
        _ = ready.wait(timeout: .now() + 1)
        return true
    }

    static func modifiers(_ flags: CGEventFlags) -> Modifiers {
        var m: Modifiers = []
        if flags.contains(.maskCommand) { m.insert(.command) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskControl) { m.insert(.control) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        if flags.contains(.maskSecondaryFn) { m.insert(.function) }
        return m
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            lock.unlock()
            return false
        }
        let p = Point(x: Double(event.location.x), y: Double(event.location.y))
        let mods = Self.modifiers(event.flags)
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        lock.lock()
        let decision: MouseDecision
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            decision = matcher.down(button: button, modifiers: mods, at: p)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            decision = matcher.dragged(to: p)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            decision = matcher.up(button: button, modifiers: mods, at: p)
        case .scrollWheel:
            let vertical = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let horizontal = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let direction: ScrollDirection? = vertical > 0 ? .up : vertical < 0 ? .down : horizontal > 0 ? .left : horizontal < 0 ? .right : nil
            decision = direction.map { matcher.scroll($0, modifiers: mods, now: CACurrentMediaTime()) } ?? .pass
        default:
            decision = .pass
        }
        lock.unlock()
        switch decision {
        case .pass: return false
        case .consume: return true
        default:
            DispatchQueue.main.async { [onDecision] in onDecision(decision) }
            return true
        }
    }
}
```

If `KeyTap.swift` creates its thread differently (for example with `Thread(target:selector:)`), follow `KeyTap.swift` exactly so both taps behave the same.

- [ ] **Step 2: Wire it in `AppController.swift`**

- Add `private var mouseTap: MouseTap!`, created in `setUp()` next to `hotkeys`:

```swift
        mouseTap = MouseTap { [weak self] decision in self?.mouseDecision(decision) }
```

- Add:

```swift
    private func mouseDecision(_ decision: MouseDecision) {
        switch decision {
        case .run(let binds): runBinds(binds)
        case .start(let action, let p): handle(.mouseBindStarted(action, p))
        case .move(let p):
            handle(.mouseBindMoved(p))
            updateDropPreview()
        case .end(let p):
            handle(.mouseBindEnded(p))
            dropPreview.hide()
        case .pass, .consume: break
        }
    }
```

- In `refreshHotkeys()`, after `hotkeys.activate(...)`:

```swift
        if !mouseTap.update(world.activeBinds, dragThreshold: world.config.bindsOptions.dragThreshold,
                            scrollEventDelayMs: world.config.bindsOptions.scrollEventDelay) {
            runtimeErrors.append("Mouse binds need the mouse event tap; it could not start")
        }
```

  Add the message only once: skip the append when `runtimeErrors` already contains it.
- Call `mouseTap.stop()` next to `hotkeys.deactivate()` in `togglePause()` and in `applicationWillTerminate`.

- [ ] **Step 3: Build, test, install**

Run the Task 6 Step 4 command. Expected: clean build, all tests pass, installed.

- [ ] **Step 4: Live check**

Ask the owner to:
1. Hold Ctrl+⌥ and drag inside a tiled window with the left button: the window follows the cursor, the drop preview shows, and the window lands at the drop point on release.
2. Hold Ctrl+⌥ and drag with the right button near a window edge: the split moves.
3. Hold Ctrl+⌥ and scroll the wheel down and up: the workspace changes one step per notch, at most one step per 300 ms.
4. Click and scroll without modifiers in any app: everything behaves as normal.

- [ ] **Step 5: Commit**

```bash
git add Sources/HyprOSX
git commit -m "feat: route mouse and scroll binds through a mouse event tap"
```

---

### Task 10: Owner config, spec notes and the M2 performance pass

**Files:**
- Modify: `Tests/HyprCoreTests/OwnerConfigTests.swift`
- Modify: `docs/specs/2026-10-12-hyprosx-design.md` (sections 11.2 and 12)
- Create: `docs/perf/m2-motion.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the M2 baseline numbers.

- [ ] **Step 1: Pin the owner's motion settings**

Append to the owner config test (the function that already loads `config/owner/hyprland.conf`):

```swift
        #expect(Motion.timing("windowsIn", config: config, environment: MotionEnvironment())?.duration == 0.41)
        #expect(config.animations.leaf("windowsIn").style == "popin 87%")
        #expect(config.animations.leaf("workspacesIn").style == "fade")
        #expect(Motion.decorationTiming("border", config: config) != nil)
        #expect(config.binds.filter { $0.flags.contains(.mouse) }.map(\.dispatcher) == ["movewindow", "resizewindow"])
```

If the duration comparison fails on floating-point rounding (`4.1 * 100 / 1000`), compare with `abs(... - 0.41) < 1e-9`.

- [ ] **Step 2: Run the full suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | grep -E 'Test run with|✘' | head`
Expected: all pass.

- [ ] **Step 3: Record the two platform rulings in the spec**

In section 11.2, after "A per-screen `CADisplayLink`...", add: "M2 uses one display link from the main screen; a second link per screen comes when a mixed-refresh setup shows stutter." In section 12, after the ring bullet, add: "macOS has no public API for a window's corner radius. With `macos:border_radius = -1` the ring uses 16 pt on macOS 26 and later and 10 pt before."

- [ ] **Step 4: Measure and write `docs/perf/m2-motion.md`**

Run, with the Mac untouched during the sleep:
```bash
H=~/.local/bin/hyprctl; a=$($H perf | head -1); ALLOW_SLEEP=1 /bin/sleep 60; b=$($H perf | head -1); echo "$a / $b"; ps -o rss= -p $(pgrep -x HyprOSX)
```
Then switch workspaces 10 times with `hyprctl dispatch workspace 2` / `1` and run `$H perf` again to read the AX write count and average latency.

Write `docs/perf/m2-motion.md` with: date, machine, idle CPU over 60 s (target below 0.1%), RSS (target below 50 MB), AX writes per workspace switch, and the per-app average write latency. Use the format of `docs/perf/m1-baseline.md`.

- [ ] **Step 5: Commit**

```bash
git add Tests/HyprCoreTests/OwnerConfigTests.swift docs
git commit -m "docs: record the M2 motion baseline and platform notes"
```
