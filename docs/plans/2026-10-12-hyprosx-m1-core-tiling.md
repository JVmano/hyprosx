# HyprOSX Milestone 1 (Core Tiling) Implementation Plan


**Goal:** A daily-usable HyprOSX without motion: Hyprland 0.54 config, dwindle, master and monocle layouts, floating, fullscreen, workspaces and special workspaces, rules, parking, hotkeys and submaps, focus, `hyprctl` with the security rules, restore after restart, menu bar basics, build and install, and the owner's config.

**Architecture:** `HyprCore` (pure Swift, Foundation only) holds a `World` that takes platform events and dispatcher commands and returns effects. `HyprOSX` (AppKit) feeds the world from per-app Accessibility threads, Carbon hotkeys and a Unix socket, and executes the effects. `hyprctl` is a small socket client.

**Tech Stack:** Swift 6.4 toolchain in Swift 5 language mode, SwiftPM, Swift Testing, AppKit, ApplicationServices (Accessibility), Carbon (hotkeys), POSIX sockets.

**Spec:** `docs/specs/2026-10-12-hyprosx-design.md`. Algorithms: `docs/research/hyprland-algorithms.md`. Config reference: `docs/research/hyprland-config-reference.md`. Platform notes: `docs/research/macos-platform-notes.md`. AeroSpace source (MIT): `../AeroSpace/Sources/AppBundle/`.

**How to read the code steps:** test code is complete and is the acceptance contract. Where a step ports an algorithm that `docs/research/hyprland-algorithms.md` already gives as exact pseudo-code, the step names the section and gives the Swift signatures; port that pseudo-code line by line. All other implementation code is written out in full.

## Global Constraints

- Minimum macOS 14.0 (`platforms: [.macOS(.v14)]`, `LSMinimumSystemVersion` 14.0); built on macOS 27 with Swift 6.4.
- `swift-tools-version: 6.0`, every target with `swiftSettings: [.swiftLanguageMode(.v5)]`.
- SwiftPM only. No third-party packages. No Xcode project.
- `HyprCore` imports Foundation only (never AppKit, ApplicationServices or Carbon).
- No code comments unless nothing else can explain the code. Port attribution goes in `NOTICE`.
- Bundle id `dev.hyprosx.HyprOSX`. Config `~/.config/hyprosx/hyprland.conf` and `~/.config/hyprosx/apps.conf`. State `~/Library/Application Support/HyprOSX/state.json`. Socket `$TMPDIR/hyprosx/.socket.sock`.
- No Accessibility call on the main thread. Every AX call runs on the owning app's thread.
- Every command HyprOSX starts uses `posix_spawn` with `responsibility_spawnattrs_setdisclaim(attr, 1)`.
- No polling loop except the Accessibility trust check before trust is granted.
- Coordinates in `HyprCore` are top-left origin, y down, in points (the Accessibility coordinate space).
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) and run with `swift test`.

## Review Focus

1. A config file with CRLF line endings, tabs, a UTF-8 BOM or trailing spaces must parse exactly like a clean LF file (test added in Task 2).
2. An app with no bundle id (some Java and command-line GUI apps) must still match `match:class` by app name, show up in `hyprctl clients`, and never crash (tests in Tasks 6 and 13).
3. A window that disappears between an event and the next AX call (closed during a move) must leave the world cleanly: no crash, focus moves to the next candidate, and late events for it are ignored (`windowClosedDuringDragLeavesWorldClean` in Task 14).
4. Unplugging a monitor while it shows workspaces (undocking the ultrawide) must move those workspaces to monitor 0 and bring them back on re-plug without losing windows (tests in Task 14).
5. Non-ASCII titles and app names (emoji, CJK, quotes, backslashes) must match rules correctly and produce valid JSON in `hyprctl` (tests in Tasks 6 and 16).

## File Structure

```
Package.swift
NOTICE
Resources/Info.plist
scripts/build-app.sh                     build, bundle, sign, install
scripts/make-signing-identity.sh         one-time local code-signing identity
config/owner/hyprland.conf               the owner's config
config/owner/apps.conf                   the owner's app rules
Sources/HyprCore/
  Geometry.swift                         Point, Size, Rect, Edges
  Diagnostics.swift                      SourceLocation, Diagnostic
  Config/Hyprlang.swift                  hyprlang text -> ConfigEntry list
  Config/Values.swift                    bool, int, float, color, gradient, vec2, edges
  Config/Options.swift                   option structs, defaults, option registry, known-ignored names
  Config/Config.swift                    Config and ConfigBuilder
  Input/Keys.swift                       Modifiers, keysym table
  Input/Bind.swift                       Bind, BindTrigger, BindFlags, BindParser
  Commands/Selectors.swift               Direction, WorkspaceSelector, WindowSelector, MonitorSelector, ResizeParam, FloatValue
  Commands/Command.swift                 Command enum and CommandParser
  Rules/WindowRule.swift                 WindowRule, matchers, effects, parsers for every syntax
  Rules/RuleEngine.swift                 WindowFacts, static and dynamic outcomes
  Rules/WorkspaceRule.swift              WorkspaceRule, selector filters
  Animation/Bezier.swift                 baked bezier curves
  Animation/AnimationTree.swift          animation leaves and inheritance
  Layout/TiledLayout.swift               TiledLayout protocol, LayoutContext, Corner
  Layout/WindowGeometry.swift            tile box -> window frame (gaps, border, pseudo)
  Layout/Dwindle.swift                   DwindleLayout
  Layout/Master.swift                    MasterLayout
  Layout/Monocle.swift                   MonocleLayout
  World/Model.swift                      WindowID, MonitorInfo, WindowSnapshot, ManagedWindow, Workspace, Monitor
  World/Effects.swift                    Effect, FrameChange, FrameReason, CommandResult, PlatformEvent
  World/Parking.swift                    corner choice and park points
  World/World.swift                      World core: windows, workspaces, layout pass
  World/World+Workspaces.swift           selector resolution, switching, special workspaces, monitors
  World/World+Focus.swift                focus history, directional search, cycling
  World/World+Dispatch.swift             Command execution
  World/World+Events.swift               PlatformEvent handling
  World/Snapshot.swift                   Codable state snapshot
  IPC/IPCRequest.swift                   request parsing, batch, security filter
  IPC/IPCResponder.swift                 replies for hyprctl commands (text and JSON)
  IPC/Socket.swift                       socket paths, owner-only server, client, hyprctl exit codes
  Platform/WindowClassifier.swift        AeroSpace window and dialog heuristics
  Platform/MonitorLayout.swift           screen descriptions -> MonitorInfo (ids, names, flip)
  Platform/Spawner.swift                 disclaimed posix_spawn, environment, reaping
  Input/HotkeyPlan.swift                 binds -> hotkey groups, Carbon modifier mask
  Config/DefaultConfig.swift             bundled default hyprland.conf and apps.conf
  Config/ConfigLoader.swift              file loading with glob, apps.conf source check
  World/World+Release.swift              bring parked windows back (quit, pause)
Sources/HyprOSX/
  main.swift                             NSApplication bootstrap
  AppController.swift                    startup sequence, wiring, effect dispatch
  AX/AXSupport.swift                     AX helpers, _AXUIElementGetWindow, attributes
  AX/AXAppThread.swift                   per-app thread, observers, jobs, frame slots, latency
  Platform/AppTracker.swift              NSWorkspace observers, app and window registration
  Platform/Screens.swift                 NSScreen -> MonitorInfo, cursor position
  Platform/EffectExecutor.swift          executes effects (instant frames in M1)
  Platform/MouseUpMonitor.swift          left-mouse-up monitor for drags and delayed registration
  Input/HotkeyManager.swift              Carbon hotkeys, submaps, repeat
  Config/ConfigStore.swift               config path, default files, watch with debounce
  State/StateStore.swift                 debounced state save and load
  UI/StatusItem.swift                    menu bar item and menu
Sources/hyprctl/main.swift               CLI client
Tests/HyprCoreTests/                     one test file per HyprCore unit (named per task)
```

## Task Overview

| # | task | depends on |
|---|---|---|
| 1 | Package scaffold, geometry, diagnostics | - |
| 2 | Hyprlang parser | 1 |
| 3 | Value parsing | 1 |
| 4 | Keys and binds | 1, 3 |
| 5 | Selectors and dispatcher commands | 1 |
| 6 | Window rules and rule engine | 1, 3 |
| 7 | Workspace rules | 1, 3 |
| 8 | Bezier and animation tree | 1 |
| 9 | Options and config builder | 2-8 |
| 10 | Layout protocol and window geometry | 1 |
| 11 | Dwindle layout | 10 |
| 12 | Master and monocle layouts | 10 |
| 13 | World core: model, windows, layout pass, parking | 9-12 |
| 14 | World: workspaces, monitors, events | 13 |
| 15 | World: focus and dispatchers | 14 |
| 16 | Snapshot and IPC (requests, policy, replies) | 15 |
| 17 | Window classification and Accessibility layer | 13 |
| 18 | App tracking and effect executor | 13, 17 |
| 19 | Hotkeys and submaps | 4, 18 |
| 20 | Socket server and hyprctl | 16 |
| 21 | App lifecycle, config store, state store, menu bar | 18-20 |
| 22 | Build, signing, install, configs | 21 |
| 23 | Live verification and performance baseline | 22 |

Tasks 2-8 and 10 only need Task 1, so they can run in parallel. Task 17 can run in parallel with Tasks 14-16.

---

### Task 1: Package scaffold, geometry, diagnostics

**Files:**
- Create: `Package.swift`, `Sources/HyprCore/Geometry.swift`, `Sources/HyprCore/Diagnostics.swift`, `Sources/HyprOSX/main.swift`, `Sources/hyprctl/main.swift`, `Tests/HyprCoreTests/GeometryTests.swift`

**Interfaces:**
- Produces: `Point`, `Size`, `Rect`, `Edges`, `SourceLocation`, `Diagnostic` (exact definitions below). Every later task uses them.

- [ ] **Step 1: Write the package manifest and placeholder executables**

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "HyprOSX",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HyprOSX", targets: ["HyprOSX"]),
        .executable(name: "hyprctl", targets: ["hyprctl"]),
    ],
    targets: [
        .target(name: "HyprCore", swiftSettings: v5),
        .executableTarget(name: "HyprOSX", dependencies: ["HyprCore"], swiftSettings: v5),
        .executableTarget(name: "hyprctl", swiftSettings: v5),
        .testTarget(name: "HyprCoreTests", dependencies: ["HyprCore"], swiftSettings: v5),
    ]
)
```

`Sources/HyprOSX/main.swift` and `Sources/hyprctl/main.swift` both start as:

```swift
import Foundation
print("HyprOSX")
```

- [ ] **Step 2: Write the failing geometry tests**

`Tests/HyprCoreTests/GeometryTests.swift`:

```swift
import Testing
@testable import HyprCore

@Suite struct GeometryTests {
    @Test func rectEdgesAndCenter() {
        let r = Rect(x: 10, y: 20, width: 100, height: 50)
        #expect(r.maxX == 110 && r.maxY == 70)
        #expect(r.center == Point(x: 60, y: 45))
    }

    @Test func containsIsHalfOpen() {
        let r = Rect(x: 0, y: 0, width: 10, height: 10)
        #expect(r.contains(Point(x: 0, y: 0)))
        #expect(!r.contains(Point(x: 10, y: 5)))
    }

    @Test func insetByEdges() {
        let r = Rect(x: 0, y: 0, width: 100, height: 100)
        #expect(r.inset(by: Edges(top: 1, right: 2, bottom: 3, left: 4)) == Rect(x: 4, y: 1, width: 94, height: 96))
    }

    @Test func distanceSquaredIsZeroInsideAndAxisDistanceOutside() {
        let r = Rect(x: 0, y: 0, width: 10, height: 10)
        #expect(r.distanceSquared(to: Point(x: 5, y: 5)) == 0)
        #expect(r.distanceSquared(to: Point(x: 13, y: 14)) == 9 + 16)
    }

    @Test(arguments: [
        ([5.0], Edges(top: 5, right: 5, bottom: 5, left: 5)),
        ([5.0, 10], Edges(top: 5, right: 10, bottom: 5, left: 10)),
        ([1.0, 2, 3], Edges(top: 1, right: 2, bottom: 3, left: 2)),
        ([1.0, 2, 3, 4], Edges(top: 1, right: 2, bottom: 3, left: 4)),
    ])
    func cssEdges(_ values: [Double], _ expected: Edges) {
        #expect(Edges(css: values) == expected)
    }

    @Test func roundedRoundsEachComponent() {
        #expect(Rect(x: 0.4, y: 0.6, width: 9.5, height: 10.49).rounded() == Rect(x: 0, y: 1, width: 10, height: 10))
    }

    @Test func diagnosticDescription() {
        let d = Diagnostic(SourceLocation(file: "/a/hyprland.conf", line: 3), "bad value", isWarning: false)
        #expect(d.description == "hyprland.conf:3: bad value")
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter GeometryTests`
Expected: FAIL, compile errors such as "cannot find 'Rect' in scope".

- [ ] **Step 4: Write the geometry and diagnostics types**

`Sources/HyprCore/Geometry.swift`:

```swift
import Foundation

public struct Point: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public static let zero = Point(x: 0, y: 0)
    public static func + (a: Point, b: Point) -> Point { Point(x: a.x + b.x, y: a.y + b.y) }
    public static func - (a: Point, b: Point) -> Point { Point(x: a.x - b.x, y: a.y - b.y) }
}

public struct Size: Equatable, Hashable, Codable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public struct Edges: Equatable, Hashable, Codable, Sendable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double
    public init(top: Double, right: Double, bottom: Double, left: Double) {
        self.top = top; self.right = right; self.bottom = bottom; self.left = left
    }
    public init(all v: Double) { self.init(top: v, right: v, bottom: v, left: v) }
    public init(css v: [Double]) {
        switch v.count {
        case 1: self.init(all: v[0])
        case 2: self.init(top: v[0], right: v[1], bottom: v[0], left: v[1])
        case 3: self.init(top: v[0], right: v[1], bottom: v[2], left: v[1])
        case 4...: self.init(top: v[0], right: v[1], bottom: v[2], left: v[3])
        default: self.init(all: 0)
        }
    }
    public static let zero = Edges(all: 0)
}

public struct Rect: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public init(origin: Point, size: Size) {
        self.init(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }
    public static let zero = Rect(x: 0, y: 0, width: 0, height: 0)
    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var origin: Point { Point(x: x, y: y) }
    public var size: Size { Size(width: width, height: height) }
    public var center: Point { Point(x: x + width / 2, y: y + height / 2) }
    public func contains(_ p: Point) -> Bool { p.x >= x && p.x < maxX && p.y >= y && p.y < maxY }
    public func intersects(_ o: Rect) -> Bool { x < o.maxX && o.x < maxX && y < o.maxY && o.y < maxY }
    public func inset(by e: Edges) -> Rect {
        Rect(x: x + e.left, y: y + e.top, width: max(0, width - e.left - e.right), height: max(0, height - e.top - e.bottom))
    }
    public func rounded() -> Rect {
        Rect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }
    public func distanceSquared(to p: Point) -> Double {
        let dx = max(0, x - p.x, p.x - maxX)
        let dy = max(0, y - p.y, p.y - maxY)
        return dx * dx + dy * dy
    }
    public func isClose(to o: Rect, tolerance: Double = 1) -> Bool {
        abs(x - o.x) < tolerance && abs(y - o.y) < tolerance && abs(width - o.width) < tolerance && abs(height - o.height) < tolerance
    }
}
```

`Sources/HyprCore/Diagnostics.swift`:

```swift
import Foundation

public struct SourceLocation: Equatable, Hashable, Codable, Sendable {
    public var file: String
    public var line: Int
    public init(file: String, line: Int) { self.file = file; self.line = line }
}

public struct Diagnostic: Equatable, Sendable, CustomStringConvertible {
    public var location: SourceLocation
    public var message: String
    public var isWarning: Bool
    public init(_ location: SourceLocation, _ message: String, isWarning: Bool = false) {
        self.location = location; self.message = message; self.isWarning = isWarning
    }
    public var description: String {
        "\((location.file as NSString).lastPathComponent):\(location.line): \(message)"
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter GeometryTests`
Expected: PASS (7 tests). Also run `swift build` and expect success for all targets.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: add package scaffold with geometry and diagnostics"
```

---

### Task 2: Hyprlang parser

**Files:**
- Create: `Sources/HyprCore/Config/Hyprlang.swift`
- Test: `Tests/HyprCoreTests/HyprlangTests.swift`

**Interfaces:**
- Consumes: `SourceLocation`, `Diagnostic` (Task 1).
- Produces:

```swift
public struct ConfigEntry: Equatable, Sendable {
    public var key: String          // full path, e.g. "general:gaps_in", "bind", "animations:bezier", "windowrule:match:class"
    public var value: String        // variables expanded, trimmed, comments removed
    public var location: SourceLocation
    public var block: Int?          // id of the innermost `name {` block that opened this entry, nil at top level
}
public struct HyprlangParser {
    public init(environment: [String: String],
                readFile: @escaping (String) -> String?,
                glob: @escaping (String) -> [String])
    public func parse(path: String) -> (entries: [ConfigEntry], diagnostics: [Diagnostic])
    public func parse(text: String, path: String) -> (entries: [ConfigEntry], diagnostics: [Diagnostic])
}
```

Behavior (from `hyprland-config-reference.md`, "Syntax"):
- Strip a leading UTF-8 BOM. Split lines on `\n`; drop a trailing `\r` on each line. Join lines ending in `\` with the next line (remove the backslash and trailing spaces/tabs; append the next line with no separator). A backslash on the last line gives the diagnostic "Last line ends with backslash".
- Directives at column 0 after trimming: `# hyprlang noerror true|false|yes|...`, `# hyprlang if VAR`, `# hyprlang if !VAR`, `# hyprlang endif`. A stray endif gives "stray endif". Inside a failed `if`, skip lines (but keep tracking nested `if`/`endif`). A variable is true when it exists (config variable or environment) and is not empty.
- Comments: scan left to right; `##` becomes `#` and scanning continues; the first single `#` cuts the rest of the line.
- Trim the line. Empty lines are skipped.
- `}` closes a category (stray `}` gives "Stray category close"). A line with no `=` that ends in `{` opens a category named by the trimmed text before `{`; each open gets a new block id (incrementing from 1). A line with no `=` otherwise gives "Invalid config line".
- `KEY = VALUE`: split at the first `=`; trim both sides. Empty key gives "Empty lhs.".
- If KEY starts with `$`: define variable `KEY.dropFirst()` with the value after expansion. Variables are global; later definitions overwrite.
- Expansion: replace `$NAME` occurrences, longest names first, repeating until no change (max 100 rounds, then "Expanding variables exceeded max iteration limit"). Variables come from the environment first, overridden by config definitions. Expansion applies to the value and to the key.
- Arithmetic: after expansion, `{{A op B}}` with `op` in `+ - * /` and spaces around it, where A and B are numbers or variable names without `$`, is replaced by the result (integers print without a decimal point). `\{{` and `{\{` stay literal (the backslash is removed).
- The entry key is the open category path joined with `:` plus the key (`general { gaps_in = 5 }` gives `general:gaps_in`).
- `source = PATH` is handled by the parser: `~` expands to `$HOME` (from environment), a relative path resolves against the directory of the current file, globs go through `glob`; no match gives "source= globbing error: found no match"; each matched file is parsed in place (entries inserted at that point). A file that `readFile` returns nil for gives "source= file <path> is inaccessible!". A file already on the current source stack gives "source= recursion detected" and is skipped.
- Unclosed categories at end of a file give "Unclosed category at EOF".

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/HyprlangTests.swift`:

```swift
import Testing
@testable import HyprCore

private func parse(_ text: String, env: [String: String] = [:], files: [String: String] = [:]) -> (entries: [ConfigEntry], diagnostics: [Diagnostic]) {
    let parser = HyprlangParser(
        environment: env,
        readFile: { files[$0] },
        glob: { pattern in
            if pattern.hasSuffix("*") {
                let prefix = String(pattern.dropLast())
                return files.keys.filter { $0.hasPrefix(prefix) }.sorted()
            }
            return files[pattern] == nil ? [] : [pattern]
        })
    return parser.parse(text: text, path: "/cfg/hyprland.conf")
}

private func pairs(_ r: (entries: [ConfigEntry], diagnostics: [Diagnostic])) -> [String] {
    r.entries.map { "\($0.key)=\($0.value)" }
}

@Suite struct HyprlangTests {
    @Test func simpleAssignmentsAndCategories() {
        let r = parse("""
        general {
            gaps_in = 5
            col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
        }
        decoration:rounding = 10
        """)
        #expect(pairs(r) == ["general:gaps_in=5", "general:col.active_border=rgba(33ccffee) rgba(00ff99ee) 45deg", "decoration:rounding=10"])
        #expect(r.diagnostics.isEmpty)
    }

    @Test func nestedCategoriesJoinWithColon() {
        let r = parse("decoration {\n  blur {\n    size = 3\n  }\n}")
        #expect(pairs(r) == ["decoration:blur:size=3"])
    }

    @Test func blockIdsAreUniquePerOpen() {
        let r = parse("windowrule {\nname = a\n}\nwindowrule {\nname = b\n}")
        #expect(r.entries.map(\.block) == [1, 2])
        #expect(r.entries.map(\.key) == ["windowrule:name", "windowrule:name"])
    }

    @Test func commentsAndEscapedHash() {
        let r = parse("bind = $m, P, pseudo, # dwindle\ncol = ##fff\n# full comment")
        #expect(pairs(r) == ["bind=$m, P, pseudo,", "col=#fff"])
    }

    @Test func variablesExpandLongestFirstAndOverride() {
        let r = parse("$mod = ALT\n$modShift = ALT SHIFT\nbind = $modShift, H, movewindow, l\nbind = $mod, H, movefocus, l\n$mod = SUPER\nx = $mod")
        #expect(pairs(r) == ["bind=ALT SHIFT, H, movewindow, l", "bind=ALT, H, movefocus, l", "x=SUPER"])
    }

    @Test func environmentVariablesArePreloaded() {
        let r = parse("x = $HOME/bin", env: ["HOME": "/Users/me"])
        #expect(pairs(r) == ["x=/Users/me/bin"])
    }

    @Test func arithmetic() {
        let r = parse("$A = 10\ny = {{A + 3}}\nz = {{4 * 2.5}}\nw = \\{{1 + 1}}")
        #expect(pairs(r) == ["y=13", "z=10", "w={{1 + 1}}"])
    }

    @Test func lineContinuation() {
        let r = parse("bind = ALT, H, \\\nmovefocus, l")
        #expect(pairs(r) == ["bind=ALT, H, movefocus, l"])
    }

    @Test func crlfTabsAndBomParseLikeLF() {
        let clean = parse("general {\n\tgaps_in = 5\n}\n")
        let messy = parse("\u{FEFF}general {\r\n\tgaps_in = 5   \r\n}\r\n")
        #expect(pairs(messy) == pairs(clean))
        #expect(messy.diagnostics.isEmpty)
    }

    @Test func conditionals() {
        let r = parse("$ON = 1\n# hyprlang if ON\na = 1\n# hyprlang endif\n# hyprlang if !ON\nb = 2\n# hyprlang endif\n# hyprlang if NOPE\nc = 3\n# hyprlang endif")
        #expect(pairs(r) == ["a=1"])
    }

    @Test func sourceRelativeAndGlobAndTilde() {
        let files = [
            "/cfg/apps.conf": "windowrule = float on, match:class .*",
            "/cfg/parts/a.conf": "x = 1",
            "/cfg/parts/b.conf": "y = 2",
            "/Users/me/extra.conf": "z = 3",
        ]
        let r = parse("before = 0\nsource = apps.conf\nsource = /cfg/parts/*\nsource = ~/extra.conf\nafter = 9", env: ["HOME": "/Users/me"], files: files)
        #expect(pairs(r) == ["before=0", "windowrule=float on, match:class .*", "x=1", "y=2", "z=3", "after=9"])
        #expect(r.entries[1].location == SourceLocation(file: "/cfg/apps.conf", line: 1))
    }

    @Test func diagnosticsCarryLines() {
        let r = parse("a = 1\n}\nnot a line\n = 3\nopen {")
        #expect(r.diagnostics.map(\.message) == ["Stray category close", "Invalid config line", "Empty lhs.", "Unclosed category at EOF"])
        #expect(r.diagnostics.map(\.location.line) == [2, 3, 4, 5])
    }

    @Test func missingSourceIsAnError() {
        let r = parse("source = nothing/*")
        #expect(r.diagnostics.first?.message == "source= globbing error: found no match")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter HyprlangTests`
Expected: FAIL, "cannot find 'HyprlangParser' in scope".

- [ ] **Step 3: Implement the parser**

`Sources/HyprCore/Config/Hyprlang.swift`:

```swift
import Foundation

public struct ConfigEntry: Equatable, Sendable {
    public var key: String
    public var value: String
    public var location: SourceLocation
    public var block: Int?
    public init(key: String, value: String, location: SourceLocation, block: Int?) {
        self.key = key; self.value = value; self.location = location; self.block = block
    }
}

public struct HyprlangParser {
    let environment: [String: String]
    let readFile: (String) -> String?
    let glob: (String) -> [String]

    public init(environment: [String: String], readFile: @escaping (String) -> String?, glob: @escaping (String) -> [String]) {
        self.environment = environment; self.readFile = readFile; self.glob = glob
    }

    public func parse(path: String) -> (entries: [ConfigEntry], diagnostics: [Diagnostic]) {
        guard let text = readFile(path) else {
            return ([], [Diagnostic(SourceLocation(file: path, line: 0), "config file \(path) is inaccessible")])
        }
        return parse(text: text, path: path)
    }

    public func parse(text: String, path: String) -> (entries: [ConfigEntry], diagnostics: [Diagnostic]) {
        var state = State(variables: environment)
        run(text: text, path: path, state: &state, stack: [path])
        return (state.entries, state.diagnostics)
    }

    private struct State {
        var variables: [String: String]
        var entries: [ConfigEntry] = []
        var diagnostics: [Diagnostic] = []
        var nextBlock = 1
    }

    private func run(text: String, path: String, state: inout State, stack: [String]) {
        var categories: [(name: String, block: Int)] = []
        var skipDepth = 0
        var ifDepth = 0
        for (lineNumber, rawLine) in logicalLines(text, path: path, state: &state) {
            let loc = SourceLocation(file: path, line: lineNumber)
            let trimmedRaw = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmedRaw.hasPrefix("# hyprlang ") {
                let words = trimmedRaw.dropFirst("# hyprlang ".count).split(separator: " ").map(String.init)
                switch words.first {
                case "if":
                    ifDepth += 1
                    if skipDepth > 0 { skipDepth += 1; continue }
                    let arg = words.count > 1 ? words[1] : ""
                    let negate = arg.hasPrefix("!")
                    let name = negate ? String(arg.dropFirst()) : arg
                    let truthy = !(state.variables[name] ?? "").isEmpty
                    if truthy == negate { skipDepth = 1 }
                case "endif":
                    if ifDepth == 0 { state.diagnostics.append(Diagnostic(loc, "stray endif")); continue }
                    ifDepth -= 1
                    if skipDepth > 0 { skipDepth -= 1 }
                default:
                    break
                }
                continue
            }
            if skipDepth > 0 { continue }
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line == "}" {
                if categories.isEmpty { state.diagnostics.append(Diagnostic(loc, "Stray category close")) } else { categories.removeLast() }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else {
                if line.hasSuffix("{") {
                    let name = line.dropLast().trimmingCharacters(in: .whitespaces)
                    categories.append((name, state.nextBlock))
                    state.nextBlock += 1
                } else {
                    state.diagnostics.append(Diagnostic(loc, "Invalid config line"))
                }
                continue
            }
            var key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key.isEmpty { state.diagnostics.append(Diagnostic(loc, "Empty lhs.")); continue }
            if key.hasPrefix("$") {
                state.variables[String(key.dropFirst())] = evaluate(value, state: &state, loc: loc)
                continue
            }
            key = expand(key, state: &state, loc: loc)
            value = evaluate(value, state: &state, loc: loc)
            let fullKey = (categories.map(\.name) + [key]).joined(separator: ":")
            if fullKey == "source" {
                source(value, from: path, loc: loc, state: &state, stack: stack)
                continue
            }
            state.entries.append(ConfigEntry(key: fullKey, value: value, location: loc, block: categories.last?.block))
        }
        if !categories.isEmpty {
            let lastLine = text.split(separator: "\n", omittingEmptySubsequences: false).count
            state.diagnostics.append(Diagnostic(SourceLocation(file: path, line: max(1, lastLine)), "Unclosed category at EOF"))
        }
    }

    private func logicalLines(_ text: String, path: String, state: inout State) -> [(Int, String)] {
        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        let physical = body.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var s = String(line)
            if s.hasSuffix("\r") { s.removeLast() }
            return s
        }
        var result: [(Int, String)] = []
        var pending: (Int, String)?
        for (i, line) in physical.enumerated() {
            var current = line
            let start = pending?.0 ?? (i + 1)
            if let p = pending { current = p.1 + line; pending = nil }
            let trimmedTrailing = current.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
            if trimmedTrailing.hasSuffix("\\") && !trimmedTrailing.hasSuffix("\\\\") {
                if i == physical.count - 1 {
                    state.diagnostics.append(Diagnostic(SourceLocation(file: path, line: i + 1), "Last line ends with backslash"))
                    result.append((start, String(trimmedTrailing.dropLast())))
                } else {
                    pending = (start, String(trimmedTrailing.dropLast()))
                }
                continue
            }
            result.append((start, current))
        }
        return result
    }

    private func stripComment(_ line: String) -> String {
        var out = ""
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            if chars[i] == "#" {
                if i + 1 < chars.count && chars[i + 1] == "#" { out.append("#"); i += 2; continue }
                break
            }
            out.append(chars[i]); i += 1
        }
        return out
    }

    private func expand(_ s: String, state: inout State, loc: SourceLocation) -> String {
        guard s.contains("$") else { return s }
        let names = state.variables.keys.sorted { $0.count > $1.count }
        var current = s
        for round in 0..<100 {
            var changed = false
            for name in names where current.contains("$" + name) {
                current = current.replacingOccurrences(of: "$" + name, with: state.variables[name] ?? "")
                changed = true
            }
            if !changed { return current }
            if round == 99 { state.diagnostics.append(Diagnostic(loc, "Expanding variables exceeded max iteration limit")) }
        }
        return current
    }

    private func evaluate(_ value: String, state: inout State, loc: SourceLocation) -> String {
        let expanded = expand(value, state: &state, loc: loc)
        return arithmetic(expanded, state: state)
    }

    private func arithmetic(_ s: String, state: State) -> String {
        guard s.contains("{") else { return s }
        var out = ""
        var rest = Substring(s)
        while let open = rest.range(of: "{{") {
            let before = rest[..<open.lowerBound]
            if before.hasSuffix("\\") {
                out += before.dropLast() + "{{"
                rest = rest[open.upperBound...]
                continue
            }
            guard let close = rest[open.upperBound...].range(of: "}}") else { break }
            out += before
            let expr = rest[open.upperBound..<close.lowerBound].split(separator: " ").map(String.init)
            if expr.count == 3, let a = operand(expr[0], state), let b = operand(expr[2], state), let r = apply(expr[1], a, b) {
                out += r == r.rounded() && abs(r) < 1e15 ? String(Int(r)) : String(r)
            } else {
                out += "{{" + rest[open.upperBound..<close.lowerBound] + "}}"
            }
            rest = rest[close.upperBound...]
        }
        out += rest
        return out.replacingOccurrences(of: "{\\{", with: "{{")
    }

    private func operand(_ token: String, _ state: State) -> Double? {
        Double(token) ?? state.variables[token].flatMap { Double($0) }
    }

    private func apply(_ op: String, _ a: Double, _ b: Double) -> Double? {
        switch op {
        case "+": return a + b
        case "-": return a - b
        case "*": return a * b
        case "/": return b == 0 ? nil : a / b
        default: return nil
        }
    }

    private func source(_ raw: String, from path: String, loc: SourceLocation, state: inout State, stack: [String]) {
        var target = raw
        if target.hasPrefix("~") { target = (state.variables["HOME"] ?? environment["HOME"] ?? "") + target.dropFirst() }
        if !target.hasPrefix("/") {
            let dir = (path as NSString).deletingLastPathComponent
            target = (dir as NSString).appendingPathComponent(target)
        }
        if target.count < 2 { state.diagnostics.append(Diagnostic(loc, "source= path \(raw) bogus!")); return }
        let matches = glob(target)
        if matches.isEmpty { state.diagnostics.append(Diagnostic(loc, "source= globbing error: found no match")); return }
        for file in matches {
            if stack.contains(file) { state.diagnostics.append(Diagnostic(loc, "source= recursion detected")); continue }
            guard let text = readFile(file) else {
                state.diagnostics.append(Diagnostic(loc, "source= file \(file) is inaccessible!"))
                continue
            }
            run(text: text, path: file, state: &state, stack: stack + [file])
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter HyprlangTests`
Expected: PASS (13 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/HyprCore/Config/Hyprlang.swift Tests/HyprCoreTests/HyprlangTests.swift
git commit -m "feat: add hyprlang config parser"
```

---

### Task 3: Value parsing

**Files:**
- Create: `Sources/HyprCore/Config/Values.swift`
- Test: `Tests/HyprCoreTests/ValuesTests.swift`

**Interfaces:**
- Consumes: `Edges` (Task 1).
- Produces:

```swift
public struct Color: Equatable, Hashable, Codable, Sendable { public var r, g, b, a: Double }   // each 0...1
public struct Gradient: Equatable, Hashable, Codable, Sendable { public var colors: [Color]; public var angleDegrees: Double }
public enum ConfigValue {
    public static func bool(_ s: String) -> Bool?
    public static func int(_ s: String) -> Int?
    public static func float(_ s: String) -> Double?
    public static func color(_ s: String) -> Color?
    public static func gradient(_ s: String) -> Gradient?
    public static func vec2(_ s: String) -> (Double, Double)?
    public static func edges(_ s: String) -> Edges?
}
```

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/ValuesTests.swift`:

```swift
import Testing
@testable import HyprCore

@Suite struct ValuesTests {
    @Test(arguments: [("true", true), ("yes", true), ("on", true), ("1", true), ("yes, please :)", true),
                      ("false", false), ("no", false), ("off", false), ("0", false)])
    func bools(_ raw: String, _ expected: Bool) { #expect(ConfigValue.bool(raw) == expected) }

    @Test func badBoolIsNil() { #expect(ConfigValue.bool("maybe") == nil) }

    @Test func ints() {
        #expect(ConfigValue.int("42") == 42)
        #expect(ConfigValue.int("-3") == -3)
        #expect(ConfigValue.int("0x10") == 16)
        #expect(ConfigValue.int("true") == 1)
        #expect(ConfigValue.int("x") == nil)
    }

    @Test func floats() {
        #expect(ConfigValue.float("0.55") == 0.55)
        #expect(ConfigValue.float("1") == 1)
        #expect(ConfigValue.float("nope") == nil)
    }

    @Test func colorForms() {
        #expect(ConfigValue.color("rgba(ff000080)") == Color(r: 1, g: 0, b: 0, a: 128.0 / 255))
        #expect(ConfigValue.color("rgb(00ff00)") == Color(r: 0, g: 1, b: 0, a: 1))
        #expect(ConfigValue.color("rgba(255, 0, 0, 0.5)") == Color(r: 1, g: 0, b: 0, a: 0.5))
        #expect(ConfigValue.color("rgb(0,0,255)") == Color(r: 0, g: 0, b: 1, a: 1))
        #expect(ConfigValue.color("0xff444444") == Color(r: 68.0 / 255, g: 68.0 / 255, b: 68.0 / 255, a: 1))
        #expect(ConfigValue.color("blue") == nil)
    }

    @Test func gradientWithAngle() {
        let g = ConfigValue.gradient("rgba(33ccffee) rgba(00ff99ee) 45deg")
        #expect(g?.colors.count == 2)
        #expect(g?.angleDegrees == 45)
        #expect(ConfigValue.gradient("rgba(595959aa)")?.angleDegrees == 0)
        #expect(ConfigValue.gradient("0xffffffff")?.colors == [Color(r: 1, g: 1, b: 1, a: 1)])
        #expect(ConfigValue.gradient("45deg") == nil)
    }

    @Test func vec2() {
        #expect(ConfigValue.vec2("10 -20.5").map { [$0.0, $0.1] } == [10, -20.5])
        #expect(ConfigValue.vec2("10") == nil)
    }

    @Test func edges() {
        #expect(ConfigValue.edges("5") == Edges(all: 5))
        #expect(ConfigValue.edges("5 10") == Edges(top: 5, right: 10, bottom: 5, left: 10))
        #expect(ConfigValue.edges("5,10,15,20") == Edges(top: 5, right: 10, bottom: 15, left: 20))
        #expect(ConfigValue.edges("a") == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ValuesTests`
Expected: FAIL, "cannot find 'ConfigValue' in scope".

- [ ] **Step 3: Implement value parsing**

`Sources/HyprCore/Config/Values.swift`:

```swift
import Foundation

public struct Color: Equatable, Hashable, Codable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(r: Double, g: Double, b: Double, a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }
}

public struct Gradient: Equatable, Hashable, Codable, Sendable {
    public var colors: [Color]
    public var angleDegrees: Double
    public init(colors: [Color], angleDegrees: Double = 0) { self.colors = colors; self.angleDegrees = angleDegrees }
    public init(_ color: Color) { self.init(colors: [color]) }
    public var isFullyTransparent: Bool { colors.allSatisfy { $0.a == 0 } }
}

public enum ConfigValue {
    public static func bool(_ s: String) -> Bool? {
        let v = s.trimmingCharacters(in: .whitespaces).lowercased()
        for t in ["true", "yes", "on"] where v.hasPrefix(t) { return true }
        for f in ["false", "off", "no"] where v.hasPrefix(f) { return false }
        if let n = Int(v) { return n != 0 }
        return nil
    }

    public static func int(_ s: String) -> Int? {
        let v = s.trimmingCharacters(in: .whitespaces)
        if v.lowercased().hasPrefix("0x") { return Int(v.dropFirst(2), radix: 16) }
        if let n = Int(v) { return n }
        if let d = Double(v), d == d.rounded() { return Int(d) }
        return bool(v).map { $0 ? 1 : 0 }
    }

    public static func float(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces))
    }

    public static func color(_ s: String) -> Color? {
        let v = s.trimmingCharacters(in: .whitespaces)
        if v.lowercased().hasPrefix("0x"), let n = UInt32(v.dropFirst(2), radix: 16) {
            return Color(r: Double((n >> 16) & 0xff) / 255, g: Double((n >> 8) & 0xff) / 255, b: Double(n & 0xff) / 255, a: Double(n >> 24) / 255)
        }
        for prefix in ["rgba(", "rgb("] where v.hasPrefix(prefix) && v.hasSuffix(")") {
            let inner = v.dropFirst(prefix.count).dropLast().replacingOccurrences(of: " ", with: "")
            if inner.contains(",") {
                let parts = inner.split(separator: ",").compactMap { Double($0) }
                if prefix == "rgba(" && parts.count == 4 { return Color(r: parts[0] / 255, g: parts[1] / 255, b: parts[2] / 255, a: parts[3]) }
                if prefix == "rgb(" && parts.count == 3 { return Color(r: parts[0] / 255, g: parts[1] / 255, b: parts[2] / 255, a: 1) }
                return nil
            }
            guard let n = UInt32(inner, radix: 16) else { return nil }
            if prefix == "rgba(" && inner.count == 8 {
                return Color(r: Double(n >> 24) / 255, g: Double((n >> 16) & 0xff) / 255, b: Double((n >> 8) & 0xff) / 255, a: Double(n & 0xff) / 255)
            }
            if prefix == "rgb(" && inner.count == 6 {
                return Color(r: Double(n >> 16) / 255, g: Double((n >> 8) & 0xff) / 255, b: Double(n & 0xff) / 255, a: 1)
            }
            return nil
        }
        return nil
    }

    public static func gradient(_ s: String) -> Gradient? {
        var colors: [Color] = []
        var angle = 0.0
        var token = ""
        var depth = 0
        var tokens: [String] = []
        for ch in s {
            if ch == "(" { depth += 1 }
            if ch == ")" { depth -= 1 }
            if ch == " " && depth == 0 { if !token.isEmpty { tokens.append(token) }; token = ""; continue }
            token.append(ch)
        }
        if !token.isEmpty { tokens.append(token) }
        for t in tokens {
            if t.hasSuffix("deg"), let d = Double(t.dropLast(3)) { angle = d; continue }
            guard let c = color(t) else { return nil }
            colors.append(c)
        }
        return colors.isEmpty ? nil : Gradient(colors: colors, angleDegrees: angle)
    }

    public static func vec2(_ s: String) -> (Double, Double)? {
        let parts = s.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    public static func edges(_ s: String) -> Edges? {
        let raw = s.split(whereSeparator: { $0 == " " || $0 == "," })
        let parts = raw.compactMap { Double($0) }
        guard !parts.isEmpty, parts.count == raw.count, parts.count <= 4 else { return nil }
        return Edges(css: parts)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ValuesTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/HyprCore/Config/Values.swift Tests/HyprCoreTests/ValuesTests.swift
git commit -m "feat: add config value parsing"
```

---
### Task 4: Keys and binds

**Files:**
- Create: `Sources/HyprCore/Input/Keys.swift`, `Sources/HyprCore/Input/Bind.swift`
- Test: `Tests/HyprCoreTests/KeysBindTests.swift`

**Interfaces:**
- Consumes: `SourceLocation`, `Diagnostic` (Task 1).
- Produces:

```swift
public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
    public static let command, option, control, shift, function: Modifiers
    public static func parse(_ s: String) -> Modifiers?          // nil when any name is unknown or unsupported
}
public enum Keysym {
    public static func keyCode(for name: String) -> UInt16?     // case-insensitive XKB name -> macOS ANSI virtual key code
    public static func name(for keyCode: UInt16) -> String?
}
public enum ScrollDirection: String, Codable, Sendable { case up, down, left, right }
public enum BindTrigger: Hashable, Sendable { case key(UInt16), mouse(Int), scroll(ScrollDirection), catchall }
public struct BindFlags: OptionSet, Hashable, Sendable {
    public static let release, repeating, mouse, universal, description, locked, transparent, bypass,
                      nonConsuming, ignoreMods, separate, longPress, click, drag, perDevice: BindFlags
}
public struct Bind: Equatable, Sendable {
    public var modifiers: Modifiers
    public var trigger: BindTrigger
    public var flags: BindFlags
    public var dispatcher: String
    public var arguments: String
    public var description: String?
    public var submap: String            // "" is the default submap
    public var location: SourceLocation
}
public enum BindParser {
    public static func parse(keyword: String, value: String, submap: String, location: SourceLocation) -> (bind: Bind?, diagnostics: [Diagnostic])
    public static func parseTrigger(_ key: String) -> BindTrigger?
    public static func parseUnbind(_ value: String) -> (Modifiers, BindTrigger)?
}
```

Rules:
- Modifier names (case-insensitive): `SUPER`, `WIN`, `LOGO`, `MOD4`, `CMD`, `COMMAND` -> command; `ALT`, `MOD1`, `OPT`, `OPTION` -> option; `CTRL`, `CONTROL` -> control; `SHIFT` -> shift; `FN` -> function. Separators are any characters that are not letters or digits, plus the word `AND`. Names may also be concatenated with no separator (`SUPERSHIFT`): match the longest known name at each position. `CAPS`, `MOD2`, `MOD3`, `MOD5` or anything else makes `parse` return nil. An empty string is `[]`.
- Bind keyword: `bind` followed by flag letters from `lrcgoenmtisdpuk`; any other letter is an error "invalid bind flag 'x'". Letters map: l locked, r release, c click, g drag, o longPress, e repeating, n nonConsuming, m mouse, t transparent, i ignoreMods, s separate, d description, p bypass, u universal, k perDevice.
- Value split on commas: with `d` the parts are MODS, KEY, DESCRIPTION, DISPATCHER, ARGS; with `k` a DEVICES part comes after KEY (and before the description). Without `m`, the last part (ARGS) is everything after the dispatcher's comma, commas included, trimmed; it may be empty. With `m`: MODS, KEY, DISPATCHER (no args).
- Key: `code:NN` -> `.key(NN)`; `mouse:NNN` -> `.mouse(NNN)`; `mouse_up|mouse_down|mouse_left|mouse_right` -> `.scroll`; `catchall` -> `.catchall`; otherwise `Keysym.keyCode`. Unknown key -> error "invalid key 'x'".
- Warnings (bind still loads as a plain bind): flags n, i, s, o, c, g, k -> "bind flag 'x' is not supported on macOS; loaded as a plain bind". Flags l, t, p load silently.
- `catchall` -> warning "catchall binds are not supported on macOS" and no bind.
- `FN` with a `.key` trigger -> error "FN works only with mouse and scroll binds".
- The dispatcher name is trimmed; an empty dispatcher is an error "missing dispatcher".

Key table (macOS ANSI virtual key codes): a 0x00, s 0x01, d 0x02, f 0x03, h 0x04, g 0x05, z 0x06, x 0x07, c 0x08, v 0x09, section 0x0A, b 0x0B, q 0x0C, w 0x0D, e 0x0E, r 0x0F, y 0x10, t 0x11, 1 0x12, 2 0x13, 3 0x14, 4 0x15, 6 0x16, 5 0x17, equal 0x18, 9 0x19, 7 0x1A, minus 0x1B, 8 0x1C, 0 0x1D, bracketright 0x1E, o 0x1F, u 0x20, bracketleft 0x21, i 0x22, p 0x23, Return 0x24 (alias Enter), l 0x25, j 0x26, apostrophe 0x27, k 0x28, semicolon 0x29, backslash 0x2A, comma 0x2B, slash 0x2C, n 0x2D, m 0x2E, period 0x2F, Tab 0x30, space 0x31, grave 0x32, BackSpace 0x33, Escape 0x35, F17 0x40, KP_Decimal 0x41, KP_Multiply 0x43, KP_Add 0x45, KP_Divide 0x4B, KP_Enter 0x4C, KP_Subtract 0x4E, F18 0x4F, F19 0x50, KP_Equal 0x51, KP_0 0x52, KP_1 0x53, KP_2 0x54, KP_3 0x55, KP_4 0x56, KP_5 0x57, KP_6 0x58, KP_7 0x59, F20 0x5A, KP_8 0x5B, KP_9 0x5C, F5 0x60, F6 0x61, F7 0x62, F3 0x63, F8 0x64, F9 0x65, F11 0x67, F13 0x69, F16 0x6A, F14 0x6B, F10 0x6D, F12 0x6F, F15 0x71, Insert 0x72 (alias Help), Home 0x73, Prior 0x74 (alias Page_Up), Delete 0x75, F4 0x76, End 0x77, F2 0x78, Next 0x79 (alias Page_Down), F1 0x7A, Left 0x7B, Right 0x7C, Down 0x7D, Up 0x7E.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/KeysBindTests.swift`:

```swift
import Testing
@testable import HyprCore

private let here = SourceLocation(file: "/cfg/hyprland.conf", line: 7)

@Suite struct KeysBindTests {
    @Test(arguments: [
        ("SUPER", Modifiers.command), ("ALT SHIFT", [.option, .shift]), ("SUPER_SHIFT", [.command, .shift]),
        ("SUPERSHIFT", [.command, .shift]), ("CTRL + ALT", [.control, .option]), ("super and shift", [.command, .shift]),
        ("CMD", Modifiers.command), ("OPTION", Modifiers.option), ("", []), ("FN", Modifiers.function),
    ])
    func modifiers(_ raw: String, _ expected: Modifiers) { #expect(Modifiers.parse(raw) == expected) }

    @Test func unsupportedModifiersAreNil() {
        #expect(Modifiers.parse("MOD2") == nil)
        #expect(Modifiers.parse("HYPER") == nil)
    }

    @Test(arguments: [("h", 0x04), ("H", 0x04), ("Return", 0x24), ("enter", 0x24), ("bracketleft", 0x21),
                      ("semicolon", 0x29), ("1", 0x12), ("0", 0x1D), ("Left", 0x7B), ("F12", 0x6F), ("space", 0x31)])
    func keysyms(_ name: String, _ code: Int) { #expect(Keysym.keyCode(for: name) == UInt16(code)) }

    @Test func plainBind() {
        let r = BindParser.parse(keyword: "bind", value: "ALT, H, movefocus, l", submap: "", location: here)
        #expect(r.diagnostics.isEmpty)
        #expect(r.bind == Bind(modifiers: .option, trigger: .key(0x04), flags: [], dispatcher: "movefocus", arguments: "l",
                               description: nil, submap: "", location: here))
    }

    @Test func argumentsKeepTheirCommas() {
        let r = BindParser.parse(keyword: "bind", value: "ALT, Return, exec, notify-send \"a, b\"", submap: "", location: here)
        #expect(r.bind?.arguments == "notify-send \"a, b\"")
    }

    @Test func emptyModifiersAndEmptyArguments() {
        let r = BindParser.parse(keyword: "bind", value: ", Escape, submap, reset", submap: "resize", location: here)
        #expect(r.bind?.modifiers == [])
        #expect(r.bind?.submap == "resize")
        let k = BindParser.parse(keyword: "bind", value: "SUPER, C, killactive,", submap: "", location: here)
        #expect(k.bind?.arguments == "")
    }

    @Test func flagsAndDescription() {
        let r = BindParser.parse(keyword: "bindrd", value: "ALT, Q, Close it, killactive,", submap: "", location: here)
        #expect(r.bind?.flags == [.release, .description])
        #expect(r.bind?.description == "Close it")
        #expect(r.bind?.dispatcher == "killactive")
    }

    @Test func repeatBind() {
        #expect(BindParser.parse(keyword: "binde", value: ", H, resizeactive, -50 0", submap: "resize", location: here).bind?.flags == .repeating)
    }

    @Test func mouseBindHasNoArguments() {
        let r = BindParser.parse(keyword: "bindm", value: "CTRL ALT, mouse:272, movewindow", submap: "", location: here)
        #expect(r.bind?.trigger == .mouse(272))
        #expect(r.bind?.dispatcher == "movewindow")
        #expect(r.bind?.flags == .mouse)
    }

    @Test func scrollAndCodeTriggers() {
        #expect(BindParser.parseTrigger("mouse_down") == .scroll(.down))
        #expect(BindParser.parseTrigger("code:36") == .key(36))
        #expect(BindParser.parseTrigger("nope") == nil)
    }

    @Test func unsupportedFlagWarnsButLoads() {
        let r = BindParser.parse(keyword: "bindn", value: "ALT, X, exec, true", submap: "", location: here)
        #expect(r.bind != nil)
        #expect(r.diagnostics.first?.isWarning == true)
        #expect(r.diagnostics.first?.message == "bind flag 'n' is not supported on macOS; loaded as a plain bind")
    }

    @Test func catchallIsDroppedWithWarning() {
        let r = BindParser.parse(keyword: "bind", value: ", catchall, submap, reset", submap: "resize", location: here)
        #expect(r.bind == nil)
        #expect(r.diagnostics.map(\.message) == ["catchall binds are not supported on macOS"])
    }

    @Test func errors() {
        #expect(BindParser.parse(keyword: "bindz", value: "ALT, X, exec, a", submap: "", location: here).diagnostics.first?.message == "invalid bind flag 'z'")
        #expect(BindParser.parse(keyword: "bind", value: "ALT, nokey, exec, a", submap: "", location: here).diagnostics.first?.message == "invalid key 'nokey'")
        #expect(BindParser.parse(keyword: "bind", value: "MOD3, X, exec, a", submap: "", location: here).diagnostics.first?.message == "invalid modifiers 'MOD3'")
        #expect(BindParser.parse(keyword: "bind", value: "FN, X, exec, a", submap: "", location: here).diagnostics.first?.message == "FN works only with mouse and scroll binds")
        #expect(BindParser.parse(keyword: "bind", value: "ALT, X", submap: "", location: here).diagnostics.first?.message == "missing dispatcher")
    }

    @Test func unbind() {
        let u = BindParser.parseUnbind("SUPER, O")
        #expect(u?.0 == .command)
        #expect(u?.1 == .key(0x1F))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter KeysBindTests`
Expected: FAIL, "cannot find 'Modifiers' in scope".

- [ ] **Step 3: Implement keys and binds**

`Sources/HyprCore/Input/Keys.swift`:

```swift
import Foundation

public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let control = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)

    private static let names: [(String, Modifiers)] = [
        ("COMMAND", .command), ("CONTROL", .control), ("OPTION", .option), ("SUPER", .command), ("SHIFT", .shift),
        ("LOGO", .command), ("MOD4", .command), ("MOD1", .option), ("CTRL", .control), ("WIN", .command),
        ("CMD", .command), ("ALT", .option), ("OPT", .option), ("FN", .function),
    ]

    public static func parse(_ s: String) -> Modifiers? {
        let upper = s.uppercased().replacingOccurrences(of: " AND ", with: " ")
        let chars = Array(upper)
        var result: Modifiers = []
        var i = 0
        while i < chars.count {
            if !(chars[i].isLetter || chars[i].isNumber) { i += 1; continue }
            let rest = String(chars[i...])
            guard let match = names.filter({ rest.hasPrefix($0.0) }).max(by: { $0.0.count < $1.0.count }) else { return nil }
            result.insert(match.1)
            i += match.0.count
        }
        return result
    }
}

public enum Keysym {
    private static let table: [String: UInt16] = {
        var t: [String: UInt16] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
            "section": 0x0A, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11,
            "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "equal": 0x18, "9": 0x19, "7": 0x1A,
            "minus": 0x1B, "8": 0x1C, "0": 0x1D, "bracketright": 0x1E, "o": 0x1F, "u": 0x20, "bracketleft": 0x21,
            "i": 0x22, "p": 0x23, "return": 0x24, "enter": 0x24, "l": 0x25, "j": 0x26, "apostrophe": 0x27, "k": 0x28,
            "semicolon": 0x29, "backslash": 0x2A, "comma": 0x2B, "slash": 0x2C, "n": 0x2D, "m": 0x2E, "period": 0x2F,
            "tab": 0x30, "space": 0x31, "grave": 0x32, "backspace": 0x33, "escape": 0x35,
            "kp_decimal": 0x41, "kp_multiply": 0x43, "kp_add": 0x45, "kp_divide": 0x4B, "kp_enter": 0x4C,
            "kp_subtract": 0x4E, "kp_equal": 0x51, "kp_0": 0x52, "kp_1": 0x53, "kp_2": 0x54, "kp_3": 0x55, "kp_4": 0x56,
            "kp_5": 0x57, "kp_6": 0x58, "kp_7": 0x59, "kp_8": 0x5B, "kp_9": 0x5C,
            "insert": 0x72, "help": 0x72, "home": 0x73, "prior": 0x74, "page_up": 0x74, "delete": 0x75, "end": 0x77,
            "next": 0x79, "page_down": 0x79, "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        ]
        let f: [UInt16] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A]
        for (i, code) in f.enumerated() { t["f\(i + 1)"] = code }
        return t
    }()

    public static func keyCode(for name: String) -> UInt16? { table[name.lowercased()] }

    public static func name(for keyCode: UInt16) -> String? {
        table.filter { $0.value == keyCode }.map(\.key).min(by: { $0.count < $1.count })
    }
}
```

`Sources/HyprCore/Input/Bind.swift`:

```swift
import Foundation

public enum ScrollDirection: String, Codable, Sendable { case up, down, left, right }

public enum BindTrigger: Hashable, Sendable {
    case key(UInt16)
    case mouse(Int)
    case scroll(ScrollDirection)
    case catchall
}

public struct BindFlags: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let release = BindFlags(rawValue: 1 << 0)
    public static let repeating = BindFlags(rawValue: 1 << 1)
    public static let mouse = BindFlags(rawValue: 1 << 2)
    public static let universal = BindFlags(rawValue: 1 << 3)
    public static let description = BindFlags(rawValue: 1 << 4)
    public static let locked = BindFlags(rawValue: 1 << 5)
    public static let transparent = BindFlags(rawValue: 1 << 6)
    public static let bypass = BindFlags(rawValue: 1 << 7)
    public static let nonConsuming = BindFlags(rawValue: 1 << 8)
    public static let ignoreMods = BindFlags(rawValue: 1 << 9)
    public static let separate = BindFlags(rawValue: 1 << 10)
    public static let longPress = BindFlags(rawValue: 1 << 11)
    public static let click = BindFlags(rawValue: 1 << 12)
    public static let drag = BindFlags(rawValue: 1 << 13)
    public static let perDevice = BindFlags(rawValue: 1 << 14)

    static let letters: [Character: BindFlags] = [
        "l": .locked, "r": .release, "c": .click, "g": .drag, "o": .longPress, "e": .repeating, "n": .nonConsuming,
        "m": .mouse, "t": .transparent, "i": .ignoreMods, "s": .separate, "d": .description, "p": .bypass,
        "u": .universal, "k": .perDevice,
    ]
    static let unsupported: Set<Character> = ["n", "i", "s", "o", "c", "g", "k"]
}

public struct Bind: Equatable, Sendable {
    public var modifiers: Modifiers
    public var trigger: BindTrigger
    public var flags: BindFlags
    public var dispatcher: String
    public var arguments: String
    public var description: String?
    public var submap: String
    public var location: SourceLocation
    public init(modifiers: Modifiers, trigger: BindTrigger, flags: BindFlags, dispatcher: String, arguments: String,
                description: String?, submap: String, location: SourceLocation) {
        self.modifiers = modifiers; self.trigger = trigger; self.flags = flags; self.dispatcher = dispatcher
        self.arguments = arguments; self.description = description; self.submap = submap; self.location = location
    }
}

public enum BindParser {
    public static func parseTrigger(_ key: String) -> BindTrigger? {
        let k = key.trimmingCharacters(in: .whitespaces)
        let lower = k.lowercased()
        if lower.hasPrefix("code:") { return UInt16(lower.dropFirst(5)).map { .key($0) } }
        if lower.hasPrefix("mouse:") { return Int(lower.dropFirst(6)).map { .mouse($0) } }
        switch lower {
        case "mouse_up": return .scroll(.up)
        case "mouse_down": return .scroll(.down)
        case "mouse_left": return .scroll(.left)
        case "mouse_right": return .scroll(.right)
        case "catchall": return .catchall
        default: return Keysym.keyCode(for: k).map { .key($0) }
        }
    }

    public static func parseUnbind(_ value: String) -> (Modifiers, BindTrigger)? {
        let parts = value.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let mods = Modifiers.parse(parts[0]), let trigger = parseTrigger(parts[1]) else { return nil }
        return (mods, trigger)
    }

    public static func parse(keyword: String, value: String, submap: String, location: SourceLocation) -> (bind: Bind?, diagnostics: [Diagnostic]) {
        var diagnostics: [Diagnostic] = []
        var flags: BindFlags = []
        for letter in keyword.dropFirst(4) {
            guard let flag = BindFlags.letters[letter] else {
                return (nil, [Diagnostic(location, "invalid bind flag '\(letter)'")])
            }
            if BindFlags.unsupported.contains(letter) {
                diagnostics.append(Diagnostic(location, "bind flag '\(letter)' is not supported on macOS; loaded as a plain bind", isWarning: true))
            }
            flags.insert(flag)
        }
        var fixed = 3
        if flags.contains(.description) { fixed += 1 }
        if flags.contains(.perDevice) { fixed += 1 }
        let isMouse = flags.contains(.mouse)
        let raw = value.split(separator: ",", maxSplits: isMouse ? fixed - 1 : fixed, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard raw.count >= fixed, !raw[fixed - 1].isEmpty else { return (nil, diagnostics + [Diagnostic(location, "missing dispatcher")]) }
        guard let mods = Modifiers.parse(raw[0]) else { return (nil, diagnostics + [Diagnostic(location, "invalid modifiers '\(raw[0])'")]) }
        guard let trigger = parseTrigger(raw[1]) else { return (nil, diagnostics + [Diagnostic(location, "invalid key '\(raw[1])'")]) }
        if trigger == .catchall {
            return (nil, diagnostics + [Diagnostic(location, "catchall binds are not supported on macOS", isWarning: true)])
        }
        if mods.contains(.function), case .key = trigger {
            return (nil, diagnostics + [Diagnostic(location, "FN works only with mouse and scroll binds")])
        }
        var index = 2
        if flags.contains(.perDevice) { index += 1 }
        var description: String?
        if flags.contains(.description) { description = raw[index]; index += 1 }
        let dispatcher = raw[index]
        let arguments = isMouse ? "" : (raw.count > index + 1 ? raw[index + 1] : "")
        let bind = Bind(modifiers: mods, trigger: trigger, flags: flags, dispatcher: dispatcher, arguments: arguments,
                        description: description, submap: submap, location: location)
        return (bind, diagnostics)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter KeysBindTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/HyprCore/Input Tests/HyprCoreTests/KeysBindTests.swift
git commit -m "feat: add key names, modifiers and bind parsing"
```

---

### Task 5: Selectors and dispatcher commands

**Files:**
- Create: `Sources/HyprCore/Commands/Selectors.swift`, `Sources/HyprCore/Commands/Command.swift`
- Test: `Tests/HyprCoreTests/CommandTests.swift`

**Interfaces:**
- Produces:

```swift
public enum Direction: String, Codable, Sendable, CaseIterable { case left, right, up, down
    public static func parse(_ s: String) -> Direction?            // l r u d t b left right up down top bottom
}
public enum WorkspaceSelector: Equatable, Hashable, Sendable {
    case id(Int), relative(Int), onMonitor(Int, includeEmpty: Bool), onMonitorAbsolute(Int, includeEmpty: Bool)
    case existing(Int), existingAbsolute(Int), name(String), previous, previousPerMonitor
    case empty(currentMonitorOnly: Bool, next: Bool), special(String?)
    public static func parse(_ s: String) -> WorkspaceSelector?
}
public enum WindowSelector: Equatable, Hashable, Sendable {
    case active, classRegex(String), initialClass(String), title(String), initialTitle(String)
    case pid(Int32), address(UInt32), floating, tiled, tag(String)
    public static func parse(_ s: String) -> WindowSelector?
}
public enum MonitorSelector: Equatable, Hashable, Sendable {
    case direction(Direction), id(Int), name(String), current, relative(Int)
    public static func parse(_ s: String) -> MonitorSelector?
}
public enum Measure: Equatable, Hashable, Sendable { case pixels(Double), percent(Double) }
public enum ResizeParam: Equatable, Hashable, Sendable { case relative(Measure, Measure), exact(Measure, Measure)
    public static func parse(_ s: String) -> ResizeParam?
}
public enum FloatValue: Equatable, Hashable, Sendable { case relative(Double), exact(Double)
    public static func parse(_ s: String) -> FloatValue?
}
public enum ToggleAction: String, Equatable, Sendable { case toggle, set, unset }
public enum MoveTarget: Equatable, Sendable { case direction(Direction), monitor(MonitorSelector) }
public enum SwapTarget: Equatable, Sendable { case direction(Direction), window(WindowSelector) }
public struct CycleOptions: Equatable, Sendable {
    public var previous = false, tiledOnly = false, floatingOnly = false, visible = false, history = false
    public init()
}
public enum Command: Equatable, Sendable {
    case exec(String, rules: String?, raw: Bool)
    case killActive(force: Bool)
    case closeWindow(WindowSelector, force: Bool)
    case signal(Int32, WindowSelector)
    case workspace(WorkspaceSelector)
    case moveToWorkspace(WorkspaceSelector, WindowSelector, silent: Bool)
    case floating(ToggleAction, WindowSelector)
    case fullscreen(mode: Int, ToggleAction)
    case pin(WindowSelector)
    case pseudo(WindowSelector)
    case moveFocus(Direction)
    case moveWindow(MoveTarget, silent: Bool)
    case swapWindow(SwapTarget)
    case centerWindow
    case resizeActive(ResizeParam)
    case moveActive(ResizeParam)
    case resizeWindow(ResizeParam, WindowSelector)
    case moveWindowTo(ResizeParam, WindowSelector)
    case cycleNext(CycleOptions)
    case swapNext(previous: Bool)
    case focusWindow(WindowSelector)
    case focusMonitor(MonitorSelector)
    case focusCurrentOrLast
    case focusUrgentOrLast
    case moveCurrentWorkspaceToMonitor(MonitorSelector)
    case moveWorkspaceToMonitor(WorkspaceSelector, MonitorSelector)
    case focusWorkspaceOnCurrentMonitor(WorkspaceSelector)
    case swapActiveWorkspaces(MonitorSelector, MonitorSelector)
    case toggleSpecialWorkspace(String?)
    case renameWorkspace(Int, String)
    case layoutMessage(String)
    case submap(String)
    case alterZOrder(top: Bool)
    case moveCursorToCorner(Int)
    case moveCursor(Double, Double)
    case workspaceLayout([String])
    case setProp(WindowSelector, String, String)
    case exit
    case noop
    case unsupported(String)
}
public struct CommandError: Error, Equatable, Sendable { public var message: String }
public enum CommandParser {
    public static func parse(dispatcher: String, arguments: String) -> Result<Command, CommandError>
}
```

Parsing rules (dispatcher names are case-insensitive, arguments trimmed):
- Workspace selector: integer -> `.id`; `+N`/`-N` -> `.relative`; `m+N`/`m-N` -> `.onMonitor(N, includeEmpty: false)`; `r+N`/`r-N` -> `.onMonitor(N, includeEmpty: true)`; `m~N` / `r~N` -> `.onMonitorAbsolute`; `e+N`/`e-N` -> `.existing`; `e~N` -> `.existingAbsolute`; `name:X` -> `.name`; `previous`, `previous_per_monitor`; `empty`, `emptym`, `emptyn`, `emptynm`/`emptymn`; `special` -> `.special(nil)`, `special:X` -> `.special(X)`. Anything else -> nil.
- Window selector: empty, `active`, `activewindow` -> `.active`; `class:X`, `initialclass:X`, `title:X`, `initialtitle:X`, `tag:X`, `pid:N`, `address:0xHEX`, `floating`, `tiled`; any other text -> `.classRegex(text)`.
- Monitor selector: direction words first, then `current`, then `+N`/`-N` -> `.relative`, then an integer -> `.id`, otherwise `.name(text)` (keeps `desc:` prefixes).
- Resize param: `exact W H` or `W H`; each measure is `N` (pixels) or `N%`. Wrong arity -> nil.
- Float value: `exact V` -> `.exact`; otherwise a signed number -> `.relative`.
- Dispatchers: `exec ARGS` (a leading `[rules]` block becomes `rules`, trimmed), `execr`; `killactive`, `forcekillactive`; `closewindow W`, `killwindow W` (force); `signal N`; `signalwindow W,N`; `workspace WS`; `movetoworkspace WS[,W]`, `movetoworkspacesilent WS[,W]` (window defaults to `.active`); `togglefloating [W]`, `setfloating [W]`, `settiled [W]`; `fullscreen [MODE] [ACTION]` (mode default 0, action default toggle); `fullscreenstate I C [ACTION]` -> mode 0 when max(I, C) >= 2, mode 1 when it is 1, otherwise `.fullscreen(mode: 0, .unset)`; `pin [W]`; `pseudo [W]`; `movefocus D`; `movewindow D|mon:M [silent]`; `swapwindow D|W`; `centerwindow [1]`; `resizeactive R`, `moveactive R`; `resizewindowpixel R,W`, `movewindowpixel R,W`; `cyclenext [prev|next] [tiled] [floating] [visible] [hist]`; `swapnext [prev]`; `focuswindow W`; `focusmonitor M`; `focuscurrentorlast`; `focusurgentorlast`; `movecurrentworkspacetomonitor M`; `moveworkspacetomonitor WS M`; `focusworkspaceoncurrentmonitor WS`; `swapactiveworkspaces M M`; `togglespecialworkspace [NAME]`; `renameworkspace ID [NAME]`; `layoutmsg TEXT`; `splitratio F` -> `.layoutMessage("splitratio F")`; `submap NAME`; `alterzorder top|bottom[,W]`; `bringactivetotop` -> `.alterZOrder(top: true)`; `movecursortocorner N`; `movecursor X Y`; `workspacelayout NAMES...`; `setprop W PROP VALUE`; `exit`; `forcerendererreload` -> `.noop`.
- `pass`, `sendshortcut`, `sendkeystate`, `global`, `event`, `dpms`, `forceidle`, `toggleswallow`, `tagwindow`, `togglegroup`, `changegroupactive`, `lockgroups`, `lockactivegroup`, `moveintogroup`, `moveintoorcreategroup`, `moveoutofgroup`, `movewindoworgroup`, `movegroupwindow`, `denywindowfromgroup`, `setignoregrouplock` -> `.unsupported(name)`.
- Unknown dispatcher -> error "Invalid dispatcher NAME". Bad arguments -> error "Invalid argument for NAME: ARGS".

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/CommandTests.swift`:

```swift
import Testing
@testable import HyprCore

private func cmd(_ d: String, _ a: String = "") -> Command? { try? CommandParser.parse(dispatcher: d, arguments: a).get() }

@Suite struct CommandTests {
    @Test(arguments: [
        ("3", WorkspaceSelector.id(3)), ("+1", .relative(1)), ("-2", .relative(-2)),
        ("m+1", .onMonitor(1, includeEmpty: false)), ("r-1", .onMonitor(-1, includeEmpty: true)),
        ("m~3", .onMonitorAbsolute(3, includeEmpty: false)), ("e+1", .existing(1)), ("e~2", .existingAbsolute(2)),
        ("name:web", .name("web")), ("previous", .previous), ("previous_per_monitor", .previousPerMonitor),
        ("empty", .empty(currentMonitorOnly: false, next: false)), ("emptynm", .empty(currentMonitorOnly: true, next: true)),
        ("special", .special(nil)), ("special:magic", .special("magic")),
    ])
    func workspaceSelectors(_ raw: String, _ expected: WorkspaceSelector) { #expect(WorkspaceSelector.parse(raw) == expected) }

    @Test func badWorkspaceSelector() { #expect(WorkspaceSelector.parse("x+") == nil) }

    @Test(arguments: [
        ("", WindowSelector.active), ("activewindow", .active), ("class:kitty", .classRegex("kitty")), ("kitty", .classRegex("kitty")),
        ("title:^(Mail)$", .title("^(Mail)$")), ("pid:42", .pid(42)), ("address:0x1a", .address(26)), ("floating", .floating),
        ("initialclass:x", .initialClass("x")), ("initialtitle:y", .initialTitle("y")), ("tag:t", .tag("t")),
    ])
    func windowSelectors(_ raw: String, _ expected: WindowSelector) { #expect(WindowSelector.parse(raw) == expected) }

    @Test(arguments: [("l", MonitorSelector.direction(.left)), ("right", .direction(.right)), ("current", .current),
                      ("+1", .relative(1)), ("0", .id(0)), ("desc:PHL", .name("desc:PHL")), ("Built-in Retina Display", .name("Built-in Retina Display"))])
    func monitorSelectors(_ raw: String, _ expected: MonitorSelector) { #expect(MonitorSelector.parse(raw) == expected) }

    @Test func resizeParams() {
        #expect(ResizeParam.parse("-50 0") == .relative(.pixels(-50), .pixels(0)))
        #expect(ResizeParam.parse("exact 33% 100%") == .exact(.percent(33), .percent(100)))
        #expect(ResizeParam.parse("10") == nil)
    }

    @Test func floatValues() {
        #expect(FloatValue.parse("exact 0.5") == .exact(0.5))
        #expect(FloatValue.parse("+0.1") == .relative(0.1))
        #expect(FloatValue.parse("-0.1") == .relative(-0.1))
    }

    @Test func execWithRules() {
        #expect(cmd("exec", "[workspace 2 silent; float] kitty --single") == .exec("kitty --single", rules: "workspace 2 silent; float", raw: false))
        #expect(cmd("execr", "open -na Ghostty") == .exec("open -na Ghostty", rules: nil, raw: true))
    }

    @Test func workspaceDispatchers() {
        #expect(cmd("workspace", "2") == .workspace(.id(2)))
        #expect(cmd("movetoworkspace", "special:magic") == .moveToWorkspace(.special("magic"), .active, silent: false))
        #expect(cmd("movetoworkspacesilent", "3,class:kitty") == .moveToWorkspace(.id(3), .classRegex("kitty"), silent: true))
        #expect(cmd("togglespecialworkspace") == .toggleSpecialWorkspace(nil))
        #expect(cmd("renameworkspace", "2 work") == .renameWorkspace(2, "work"))
    }

    @Test func windowDispatchers() {
        #expect(cmd("togglefloating") == .floating(.toggle, .active))
        #expect(cmd("settiled", "class:x") == .floating(.unset, .classRegex("x")))
        #expect(cmd("fullscreen") == .fullscreen(mode: 0, .toggle))
        #expect(cmd("fullscreen", "1 set") == .fullscreen(mode: 1, .set))
        #expect(cmd("fullscreenstate", "2 2") == .fullscreen(mode: 0, .toggle))
        #expect(cmd("movefocus", "l") == .moveFocus(.left))
        #expect(cmd("movewindow", "mon:+1 silent") == .moveWindow(.monitor(.relative(1)), silent: true))
        #expect(cmd("movewindow", "u") == .moveWindow(.direction(.up), silent: false))
        #expect(cmd("swapwindow", "r") == .swapWindow(.direction(.right)))
        #expect(cmd("resizeactive", "50 0") == .resizeActive(.relative(.pixels(50), .pixels(0))))
        #expect(cmd("resizewindowpixel", "100 100,class:kitty") == .resizeWindow(.relative(.pixels(100), .pixels(100)), .classRegex("kitty")))
        #expect(cmd("killactive") == .killActive(force: false))
        #expect(cmd("killwindow", "pid:9") == .closeWindow(.pid(9), force: true))
        #expect(cmd("signalwindow", "class:x,9") == .signal(9, .classRegex("x")))
    }

    @Test func cycleAndLayout() {
        var o = CycleOptions(); o.previous = true; o.tiledOnly = true
        #expect(cmd("cyclenext", "prev tiled") == .cycleNext(o))
        #expect(cmd("layoutmsg", "togglesplit") == .layoutMessage("togglesplit"))
        #expect(cmd("splitratio", "0.1") == .layoutMessage("splitratio 0.1"))
        #expect(cmd("workspacelayout", "dwindle monocle") == .workspaceLayout(["dwindle", "monocle"]))
        #expect(cmd("bringactivetotop") == .alterZOrder(top: true))
    }

    @Test func unsupportedAndUnknown() {
        #expect(cmd("sendshortcut", "SUPER, F4") == .unsupported("sendshortcut"))
        #expect(cmd("togglegroup") == .unsupported("togglegroup"))
        #expect((try? CommandParser.parse(dispatcher: "nope", arguments: "").get()) == nil)
        if case .failure(let e) = CommandParser.parse(dispatcher: "nope", arguments: "") { #expect(e.message == "Invalid dispatcher nope") }
        if case .failure(let e) = CommandParser.parse(dispatcher: "movefocus", arguments: "x") { #expect(e.message == "Invalid argument for movefocus: x") }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CommandTests`
Expected: FAIL, "cannot find 'CommandParser' in scope".

- [ ] **Step 3: Implement selectors and the command parser**

`Sources/HyprCore/Commands/Selectors.swift`:

```swift
import Foundation

public enum Direction: String, Codable, Sendable, CaseIterable {
    case left, right, up, down
    public static func parse(_ s: String) -> Direction? {
        switch s.trimmingCharacters(in: .whitespaces).lowercased() {
        case "l", "left": return .left
        case "r", "right": return .right
        case "u", "t", "up", "top": return .up
        case "d", "b", "down", "bottom": return .down
        default: return nil
        }
    }
}

public enum WorkspaceSelector: Equatable, Hashable, Sendable {
    case id(Int)
    case relative(Int)
    case onMonitor(Int, includeEmpty: Bool)
    case onMonitorAbsolute(Int, includeEmpty: Bool)
    case existing(Int)
    case existingAbsolute(Int)
    case name(String)
    case previous
    case previousPerMonitor
    case empty(currentMonitorOnly: Bool, next: Bool)
    case special(String?)

    public static func parse(_ s: String) -> WorkspaceSelector? {
        let v = s.trimmingCharacters(in: .whitespaces)
        if let n = Int(v), !v.hasPrefix("+"), !v.hasPrefix("-") { return .id(n) }
        if (v.hasPrefix("+") || v.hasPrefix("-")), let n = Int(v) { return .relative(n) }
        if v.hasPrefix("name:") { return .name(String(v.dropFirst(5))) }
        if v == "special" { return .special(nil) }
        if v.hasPrefix("special:") { return .special(String(v.dropFirst(8))) }
        switch v {
        case "previous": return .previous
        case "previous_per_monitor": return .previousPerMonitor
        case "empty": return .empty(currentMonitorOnly: false, next: false)
        case "emptym": return .empty(currentMonitorOnly: true, next: false)
        case "emptyn": return .empty(currentMonitorOnly: false, next: true)
        case "emptynm", "emptymn": return .empty(currentMonitorOnly: true, next: true)
        default: break
        }
        guard v.count >= 3, let kind = v.first else { return nil }
        let sign = v[v.index(after: v.startIndex)]
        let digits = v.dropFirst(2)
        guard let n = Int(digits) else { return nil }
        switch (kind, sign) {
        case ("m", "+"): return .onMonitor(n, includeEmpty: false)
        case ("m", "-"): return .onMonitor(-n, includeEmpty: false)
        case ("r", "+"): return .onMonitor(n, includeEmpty: true)
        case ("r", "-"): return .onMonitor(-n, includeEmpty: true)
        case ("m", "~"): return .onMonitorAbsolute(n, includeEmpty: false)
        case ("r", "~"): return .onMonitorAbsolute(n, includeEmpty: true)
        case ("e", "+"): return .existing(n)
        case ("e", "-"): return .existing(-n)
        case ("e", "~"): return .existingAbsolute(n)
        default: return nil
        }
    }
}

public enum WindowSelector: Equatable, Hashable, Sendable {
    case active
    case classRegex(String)
    case initialClass(String)
    case title(String)
    case initialTitle(String)
    case pid(Int32)
    case address(UInt32)
    case floating
    case tiled
    case tag(String)

    public static func parse(_ s: String) -> WindowSelector? {
        let v = s.trimmingCharacters(in: .whitespaces)
        switch v {
        case "", "active", "activewindow": return .active
        case "floating": return .floating
        case "tiled": return .tiled
        default: break
        }
        func after(_ p: String) -> String? { v.hasPrefix(p) ? String(v.dropFirst(p.count)) : nil }
        if let x = after("class:") { return .classRegex(x) }
        if let x = after("initialclass:") { return .initialClass(x) }
        if let x = after("title:") { return .title(x) }
        if let x = after("initialtitle:") { return .initialTitle(x) }
        if let x = after("tag:") { return .tag(x) }
        if let x = after("pid:") { return Int32(x).map { .pid($0) } }
        if let x = after("address:") {
            let hex = x.lowercased().hasPrefix("0x") ? String(x.dropFirst(2)) : x
            return UInt32(hex, radix: 16).map { .address($0) }
        }
        return .classRegex(v)
    }
}

public enum MonitorSelector: Equatable, Hashable, Sendable {
    case direction(Direction)
    case id(Int)
    case name(String)
    case current
    case relative(Int)

    public static func parse(_ s: String) -> MonitorSelector? {
        let v = s.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { return nil }
        if let d = Direction.parse(v) { return .direction(d) }
        if v == "current" { return .current }
        if (v.hasPrefix("+") || v.hasPrefix("-")), let n = Int(v) { return .relative(n) }
        if let n = Int(v) { return .id(n) }
        return .name(v)
    }
}

public enum Measure: Equatable, Hashable, Sendable {
    case pixels(Double)
    case percent(Double)
    static func parse(_ s: String) -> Measure? {
        if s.hasSuffix("%") { return Double(s.dropLast()).map { .percent($0) } }
        return Double(s).map { .pixels($0) }
    }
}

public enum ResizeParam: Equatable, Hashable, Sendable {
    case relative(Measure, Measure)
    case exact(Measure, Measure)
    public static func parse(_ s: String) -> ResizeParam? {
        var parts = s.split(separator: " ").map(String.init)
        let exact = parts.first == "exact"
        if exact { parts.removeFirst() }
        guard parts.count == 2, let a = Measure.parse(parts[0]), let b = Measure.parse(parts[1]) else { return nil }
        return exact ? .exact(a, b) : .relative(a, b)
    }
}

public enum FloatValue: Equatable, Hashable, Sendable {
    case relative(Double)
    case exact(Double)
    public static func parse(_ s: String) -> FloatValue? {
        let parts = s.split(separator: " ").map(String.init)
        if parts.count == 2, parts[0] == "exact" { return Double(parts[1]).map { .exact($0) } }
        if parts.count == 1 { return Double(parts[0]).map { .relative($0) } }
        return nil
    }
}

public enum ToggleAction: String, Equatable, Sendable { case toggle, set, unset }
public enum MoveTarget: Equatable, Sendable { case direction(Direction), monitor(MonitorSelector) }
public enum SwapTarget: Equatable, Sendable { case direction(Direction), window(WindowSelector) }

public struct CycleOptions: Equatable, Sendable {
    public var previous = false
    public var tiledOnly = false
    public var floatingOnly = false
    public var visible = false
    public var history = false
    public init() {}
}
```

`Sources/HyprCore/Commands/Command.swift`:

```swift
import Foundation

public enum Command: Equatable, Sendable {
    case exec(String, rules: String?, raw: Bool)
    case killActive(force: Bool)
    case closeWindow(WindowSelector, force: Bool)
    case signal(Int32, WindowSelector)
    case workspace(WorkspaceSelector)
    case moveToWorkspace(WorkspaceSelector, WindowSelector, silent: Bool)
    case floating(ToggleAction, WindowSelector)
    case fullscreen(mode: Int, ToggleAction)
    case pin(WindowSelector)
    case pseudo(WindowSelector)
    case moveFocus(Direction)
    case moveWindow(MoveTarget, silent: Bool)
    case swapWindow(SwapTarget)
    case centerWindow
    case resizeActive(ResizeParam)
    case moveActive(ResizeParam)
    case resizeWindow(ResizeParam, WindowSelector)
    case moveWindowTo(ResizeParam, WindowSelector)
    case cycleNext(CycleOptions)
    case swapNext(previous: Bool)
    case focusWindow(WindowSelector)
    case focusMonitor(MonitorSelector)
    case focusCurrentOrLast
    case focusUrgentOrLast
    case moveCurrentWorkspaceToMonitor(MonitorSelector)
    case moveWorkspaceToMonitor(WorkspaceSelector, MonitorSelector)
    case focusWorkspaceOnCurrentMonitor(WorkspaceSelector)
    case swapActiveWorkspaces(MonitorSelector, MonitorSelector)
    case toggleSpecialWorkspace(String?)
    case renameWorkspace(Int, String)
    case layoutMessage(String)
    case submap(String)
    case alterZOrder(top: Bool)
    case moveCursorToCorner(Int)
    case moveCursor(Double, Double)
    case workspaceLayout([String])
    case setProp(WindowSelector, String, String)
    case exit
    case noop
    case unsupported(String)
}

public struct CommandError: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

public enum CommandParser {
    private static let unsupportedNames: Set<String> = [
        "pass", "sendshortcut", "sendkeystate", "global", "event", "dpms", "forceidle", "toggleswallow", "tagwindow",
        "togglegroup", "changegroupactive", "lockgroups", "lockactivegroup", "moveintogroup", "moveintoorcreategroup",
        "moveoutofgroup", "movewindoworgroup", "movegroupwindow", "denywindowfromgroup", "setignoregrouplock",
    ]

    public static func parse(dispatcher: String, arguments: String) -> Result<Command, CommandError> {
        let name = dispatcher.trimmingCharacters(in: .whitespaces).lowercased()
        let args = arguments.trimmingCharacters(in: .whitespaces)
        if unsupportedNames.contains(name) { return .success(.unsupported(name)) }
        guard let command = build(name, args) else {
            return .failure(CommandError(known.contains(name) ? "Invalid argument for \(name): \(args)" : "Invalid dispatcher \(name)"))
        }
        return .success(command)
    }

    private static let known: Set<String> = [
        "exec", "execr", "killactive", "forcekillactive", "closewindow", "killwindow", "signal", "signalwindow",
        "workspace", "movetoworkspace", "movetoworkspacesilent", "togglefloating", "setfloating", "settiled",
        "fullscreen", "fullscreenstate", "pin", "pseudo", "movefocus", "movewindow", "swapwindow", "centerwindow",
        "resizeactive", "moveactive", "resizewindowpixel", "movewindowpixel", "cyclenext", "swapnext", "focuswindow",
        "focusmonitor", "focuscurrentorlast", "focusurgentorlast", "movecurrentworkspacetomonitor",
        "moveworkspacetomonitor", "focusworkspaceoncurrentmonitor", "swapactiveworkspaces", "togglespecialworkspace",
        "renameworkspace", "layoutmsg", "splitratio", "submap", "alterzorder", "bringactivetotop", "movecursortocorner",
        "movecursor", "workspacelayout", "setprop", "exit", "forcerendererreload",
    ]

    private static func splitComma(_ s: String) -> (String, String?) {
        guard let i = s.firstIndex(of: ",") else { return (s, nil) }
        return (s[..<i].trimmingCharacters(in: .whitespaces), s[s.index(after: i)...].trimmingCharacters(in: .whitespaces))
    }

    private static func build(_ name: String, _ args: String) -> Command? {
        let words = args.split(separator: " ").map(String.init)
        switch name {
        case "exec", "execr":
            var rules: String?
            var command = args
            if name == "exec", args.hasPrefix("["), let close = args.firstIndex(of: "]") {
                rules = args[args.index(after: args.startIndex)..<close].trimmingCharacters(in: .whitespaces)
                command = args[args.index(after: close)...].trimmingCharacters(in: .whitespaces)
            }
            return command.isEmpty ? nil : .exec(command, rules: rules, raw: name == "execr")
        case "killactive": return .killActive(force: false)
        case "forcekillactive": return .killActive(force: true)
        case "closewindow", "killwindow": return WindowSelector.parse(args).map { .closeWindow($0, force: name == "killwindow") }
        case "signal": return Int32(args).map { .signal($0, .active) }
        case "signalwindow":
            let (w, n) = splitComma(args)
            guard let n, let sig = Int32(n), let sel = WindowSelector.parse(w) else { return nil }
            return .signal(sig, sel)
        case "workspace": return WorkspaceSelector.parse(args).map { .workspace($0) }
        case "movetoworkspace", "movetoworkspacesilent":
            let (ws, w) = splitComma(args)
            guard let sel = WorkspaceSelector.parse(ws), let win = WindowSelector.parse(w ?? "") else { return nil }
            return .moveToWorkspace(sel, win, silent: name.hasSuffix("silent"))
        case "togglefloating", "setfloating", "settiled":
            let action: ToggleAction = name == "togglefloating" ? .toggle : (name == "setfloating" ? .set : .unset)
            return WindowSelector.parse(args).map { .floating(action, $0) }
        case "fullscreen":
            let mode = words.first.flatMap { Int($0) } ?? 0
            let action = words.count > 1 ? ToggleAction(rawValue: words[1]) : .toggle
            guard mode == 0 || mode == 1, let action else { return nil }
            return .fullscreen(mode: mode, action)
        case "fullscreenstate":
            guard words.count >= 2, let a = Int(words[0]), let b = Int(words[1]) else { return nil }
            let action = words.count > 2 ? (ToggleAction(rawValue: words[2]) ?? .toggle) : .toggle
            let top = max(a, b)
            if top >= 2 { return .fullscreen(mode: 0, action) }
            if top == 1 { return .fullscreen(mode: 1, action) }
            return .fullscreen(mode: 0, .unset)
        case "pin": return WindowSelector.parse(args).map { .pin($0) }
        case "pseudo": return WindowSelector.parse(args).map { .pseudo($0) }
        case "movefocus": return Direction.parse(args).map { .moveFocus($0) }
        case "movewindow":
            var parts = words
            let silent = parts.last == "silent"
            if silent { parts.removeLast() }
            let target = parts.joined(separator: " ")
            if target.hasPrefix("mon:") { return MonitorSelector.parse(String(target.dropFirst(4))).map { .moveWindow(.monitor($0), silent: silent) } }
            return Direction.parse(target).map { .moveWindow(.direction($0), silent: silent) }
        case "swapwindow":
            if let d = Direction.parse(args) { return .swapWindow(.direction(d)) }
            return args.isEmpty ? nil : WindowSelector.parse(args).map { .swapWindow(.window($0)) }
        case "centerwindow": return .centerWindow
        case "resizeactive": return ResizeParam.parse(args).map { .resizeActive($0) }
        case "moveactive": return ResizeParam.parse(args).map { .moveActive($0) }
        case "resizewindowpixel", "movewindowpixel":
            let (r, w) = splitComma(args)
            guard let p = ResizeParam.parse(r), let sel = WindowSelector.parse(w ?? "") else { return nil }
            return name == "resizewindowpixel" ? .resizeWindow(p, sel) : .moveWindowTo(p, sel)
        case "cyclenext":
            var o = CycleOptions()
            for w in words {
                switch w {
                case "prev": o.previous = true
                case "next": o.previous = false
                case "tiled": o.tiledOnly = true
                case "floating": o.floatingOnly = true
                case "visible": o.visible = true
                case "hist": o.history = true
                default: return nil
                }
            }
            return .cycleNext(o)
        case "swapnext": return words.isEmpty || words == ["next"] ? .swapNext(previous: false) : (words == ["prev"] ? .swapNext(previous: true) : nil)
        case "focuswindow": return args.isEmpty ? nil : WindowSelector.parse(args).map { .focusWindow($0) }
        case "focusmonitor": return MonitorSelector.parse(args).map { .focusMonitor($0) }
        case "focuscurrentorlast": return .focusCurrentOrLast
        case "focusurgentorlast": return .focusUrgentOrLast
        case "movecurrentworkspacetomonitor": return MonitorSelector.parse(args).map { .moveCurrentWorkspaceToMonitor($0) }
        case "moveworkspacetomonitor":
            guard words.count >= 2, let ws = WorkspaceSelector.parse(words[0]),
                  let mon = MonitorSelector.parse(words.dropFirst().joined(separator: " ")) else { return nil }
            return .moveWorkspaceToMonitor(ws, mon)
        case "focusworkspaceoncurrentmonitor": return WorkspaceSelector.parse(args).map { .focusWorkspaceOnCurrentMonitor($0) }
        case "swapactiveworkspaces":
            guard words.count == 2, let a = MonitorSelector.parse(words[0]), let b = MonitorSelector.parse(words[1]) else { return nil }
            return .swapActiveWorkspaces(a, b)
        case "togglespecialworkspace": return .toggleSpecialWorkspace(args.isEmpty ? nil : args)
        case "renameworkspace":
            guard let first = words.first, let id = Int(first) else { return nil }
            return .renameWorkspace(id, words.dropFirst().joined(separator: " "))
        case "layoutmsg": return args.isEmpty ? nil : .layoutMessage(args)
        case "splitratio": return FloatValue.parse(args) == nil ? nil : .layoutMessage("splitratio \(args)")
        case "submap": return args.isEmpty ? nil : .submap(args)
        case "alterzorder":
            let (z, _) = splitComma(args)
            return z == "top" ? .alterZOrder(top: true) : (z == "bottom" ? .alterZOrder(top: false) : nil)
        case "bringactivetotop": return .alterZOrder(top: true)
        case "movecursortocorner": return Int(args).flatMap { (0...3).contains($0) ? .moveCursorToCorner($0) : nil }
        case "movecursor":
            guard words.count == 2, let x = Double(words[0]), let y = Double(words[1]) else { return nil }
            return .moveCursor(x, y)
        case "workspacelayout": return words.isEmpty ? nil : .workspaceLayout(words)
        case "setprop":
            guard words.count >= 3, let sel = WindowSelector.parse(words[0]) else { return nil }
            return .setProp(sel, words[1], words.dropFirst(2).joined(separator: " "))
        case "exit": return .exit
        case "forcerendererreload": return .noop
        default: return nil
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CommandTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/HyprCore/Commands Tests/HyprCoreTests/CommandTests.swift
git commit -m "feat: add dispatcher selectors and command parsing"
```

---
### Task 6: Window rules and rule engine

**Files:**
- Create: `Sources/HyprCore/Rules/WindowRule.swift`, `Sources/HyprCore/Rules/RuleEngine.swift`
- Test: `Tests/HyprCoreTests/WindowRuleTests.swift`

**Interfaces:**
- Consumes: `SourceLocation`, `Diagnostic`, `Point`, `Size`, `Rect` (Task 1); `Gradient`, `ConfigValue` (Task 3).
- Produces:

```swift
public struct RuleRegex: Equatable, @unchecked Sendable {
    public let pattern: String; public let negative: Bool
    public init?(_ raw: String)                       // "negative:" prefix; anchored full match; nil when invalid
    public func matches(_ s: String) -> Bool
    public func matchesAny(_ values: [String]) -> Bool // negation applies to the combined match
}
public enum RuleMatcher: Equatable, Sendable {
    case cls(RuleRegex), title(RuleRegex), initialClass(RuleRegex), initialTitle(RuleRegex)
    case float(Bool), fullscreen(Bool), pin(Bool), focus(Bool), modal(Bool), workspace(String), never
}
public struct ExprPair: Equatable, Sendable { public var x: String; public var y: String }
public enum RuleEffect: Equatable, Sendable {
    case float(Bool), tile(Bool), fullscreen(Bool), maximize(Bool), center(Bool), pseudo(Bool), pin(Bool)
    case noInitialFocus(Bool), ignore(Bool), noAnim(Bool), dimAround(Bool)
    case move(ExprPair), size(ExprPair), monitor(String), workspace(String, silent: Bool), workspaceUnset
    case borderColor(active: Gradient, inactive: Gradient?), borderSize(Int), minSize(Size), maxSize(Size), animation(String)
    case accepted(String)
}
public struct WindowRule: Equatable, Sendable {
    public var name: String?; public var matchers: [RuleMatcher]; public var effects: [RuleEffect]; public var location: SourceLocation
}
public enum WindowRuleParser {
    public static func parse(keyword: String, value: String, location: SourceLocation) -> (rule: WindowRule?, diagnostics: [Diagnostic])
    public static func parseBlock(_ fields: [(key: String, value: String)], location: SourceLocation) -> (rule: WindowRule?, diagnostics: [Diagnostic])
}
public struct WindowFacts: Equatable, Sendable {
    public var bundleID: String; public var appName: String; public var title: String; public var initialTitle: String
    public var isFloating: Bool; public var isFullscreen: Bool; public var isPinned: Bool; public var isFocused: Bool; public var isModal: Bool
    public var workspaceID: Int?; public var workspaceName: String?
    public var monitorSize: Size; public var windowFrame: Rect; public var cursor: Point      // monitor-local
}
public struct WorkspaceTarget: Equatable, Sendable { public var selector: String; public var silent: Bool }
public struct StaticRuleOutcome: Equatable, Sendable {
    public var floating: Bool?; public var fullscreenMode: Int?; public var move: ExprPair?; public var size: ExprPair?
    public var center: Bool; public var pseudo: Bool; public var pin: Bool; public var noInitialFocus: Bool; public var ignore: Bool
    public var monitor: String?; public var workspace: WorkspaceTarget?; public var matched: [SourceLocation]
}
public struct DynamicRuleOutcome: Equatable, Sendable {
    public var activeBorder: Gradient?; public var inactiveBorder: Gradient?; public var borderSize: Int?; public var noAnim: Bool
    public var minSize: Size?; public var maxSize: Size?; public var animationStyle: String?; public var dimAround: Bool
}
public enum RuleEngine {
    public static func ordered(_ rules: [WindowRule]) -> [WindowRule]             // named first, then anonymous, stable
    public static func matches(_ rule: WindowRule, _ facts: WindowFacts) -> Bool
    public static func staticOutcome(_ rules: [WindowRule], _ facts: WindowFacts) -> StaticRuleOutcome
    public static func dynamicOutcome(_ rules: [WindowRule], _ facts: WindowFacts) -> DynamicRuleOutcome
    public static func evaluate(_ expr: String, axisLength: Double, variables: [String: Double]) -> Double?
    public static func resolveMove(_ p: ExprPair, _ facts: WindowFacts) -> Point?
    public static func resolveSize(_ p: ExprPair, _ facts: WindowFacts) -> Size?
}
```

Rules (from `hyprland-config-reference.md`, "Window rules", and spec section 10.1):
- `windowrule` value with any part starting `match:` is the 0.54 form: `match:PROP VALUE` parts are props, every other part is `EFFECT [ARGS]`.
- Otherwise it is a legacy form. A part that starts with a known legacy field and a colon (`class`, `title`, `initialClass`, `initialTitle`, `tag`, `xdgtag`, `content`, `xwayland`, `floating`, `fullscreen`, `pinned`, `focus`, `group`, `fullscreenstate`, `workspace`, `onworkspace`) is a prop, every other part is an effect. With no field part and exactly two parts it is the v1 form: effect then a class regex (`title:` is already a field). `windowrulev2` uses the same legacy handling.
- Legacy names map to new ones: props `initialClass` to `initial_class`, `initialTitle` to `initial_title`, `floating` to `float`, `pinned` to `pin`, `onworkspace` to `workspace`, `xdgtag` to `xdg_tag`; effects `noinitialfocus`, `bordercolor`, `bordersize`, `noanim`, `maxsize`, `minsize`, `dimaround`, `suppressevent`, `stayfocused`, `nofocus`, `nomaxsize`, `persistentsize`, `idleinhibit`, `noblur`, `noshadow`, `nodim`, `forcergbx`, `keepaspectratio`, `nearestneighbor`, `focusonactivate`, `allowsinput`, `roundingpower`, `scrollmouse`, `scrolltouchpad`, `noscreenshare`, `novrr`, `syncfullscreen`, `renderunfocused`, `noclosefor`, `fullscreenstate`, `noshortcutsinhibit`, `nofollowmouse` to their snake_case names; `noborder` becomes `border_size 0`.
- Props: `class`, `title`, `initial_class`, `initial_title` (regex); `float`, `fullscreen`, `pin`, `focus`, `modal` (bool); `workspace` (string); `xwayland` and `group` (true gives `.never`, false is always true and is dropped); `tag`, `content`, `xdg_tag`, `fullscreen_state_client`, `fullscreen_state_internal` give `.never`. Unknown prop: error "invalid rule prop 'x'". Same prop twice: error "duplicate rule prop 'x'". No prop written: error "rule needs at least one match prop". Invalid regex: error "invalid regex 'x'".
- Effects: bool effects (`float`, `tile`, `fullscreen`, `maximize`, `center`, `pseudo`, `pin`, `no_initial_focus`, `ignore`, `no_anim`, `dim_around`) take an optional bool (empty means true; a bad bool is an error); `move X Y` and `size X Y` take exactly two tokens; `monitor M`; `workspace W [silent]` or `workspace unset`; `border_color` takes one or two gradients (a group ends at an `Ndeg` token; without angles, two color tokens mean active and inactive); `border_size N`; `min_size W H`; `max_size W H`; `animation STYLE`. These names give `.accepted(name)`: `fullscreen_state`, `group`, `suppress_event`, `content`, `no_close_for`, `scrolling_width`, `persistent_size`, `no_max_size`, `stay_focused`, `idle_inhibit`, `opacity`, `tag`, `rounding`, `rounding_power`, `allows_input`, `decorate`, `focus_on_activate`, `keep_aspect_ratio`, `nearest_neighbor`, `no_blur`, `no_dim`, `no_focus`, `no_follow_mouse`, `no_shadow`, `no_shortcuts_inhibit`, `no_screen_share`, `no_vrr`, `opaque`, `force_rgbx`, `sync_fullscreen`, `immediate`, `xray`, `render_unfocused`, `scroll_mouse`, `scroll_touchpad`, `confine_pointer`, `no_auto_hdr`, `no_glow`, `no_wobble`, `no_xdg_drags`, `tonemap`, `norounding`, `unset`. Anything else: error "invalid rule effect 'x'".
- Block form fields: `name`, `match:PROP` and effect names as keys.
- `class` and `initial_class` match when the regex fully matches the bundle id or the app name (an empty bundle id is skipped). Regexes are case-sensitive.
- Evaluation: `ordered` puts named rules first, then anonymous, keeping file order. Every matching rule applies its effects in order and the last write wins. `float(true)` sets `floating = true`, `tile(true)` sets `floating = false`, `float(false)` and `tile(false)` clear `floating` to nil. `fullscreen(true)` sets mode 0, `maximize(true)` mode 1. `workspaceUnset` clears `workspace`. `matched` lists the location of every matching rule that has a static effect.
- Expressions: `N%` is a percentage of the axis length; otherwise `+ - * /`, parentheses, unary minus, numbers and the variables `monitor_w`, `monitor_h`, `window_x`, `window_y`, `window_w`, `window_h`, `cursor_x`, `cursor_y`.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/WindowRuleTests.swift`:

```swift
import Testing
@testable import HyprCore

private let here = SourceLocation(file: "/cfg/apps.conf", line: 1)

private func rule(_ v: String, keyword: String = "windowrule") -> WindowRule? {
    WindowRuleParser.parse(keyword: keyword, value: v, location: here).rule
}

private func facts(bundle: String = "com.mitchellh.ghostty", app: String = "Ghostty", title: String = "~",
                   floating: Bool = false, modal: Bool = false, focused: Bool = false) -> WindowFacts {
    WindowFacts(bundleID: bundle, appName: app, title: title, initialTitle: title, isFloating: floating, isFullscreen: false,
                isPinned: false, isFocused: focused, isModal: modal, workspaceID: 1, workspaceName: "1",
                monitorSize: Size(width: 1512, height: 950), windowFrame: Rect(x: 100, y: 100, width: 800, height: 600),
                cursor: Point(x: 50, y: 60))
}

@Suite struct WindowRuleTests {
    @Test func modernInlineForm() {
        let r = rule("float on, match:class .*")
        #expect(r?.effects == [.float(true)])
        #expect(r?.matchers.count == 1)
        let t = rule("match:class com\\.mitchellh\\.ghostty, tile on, match:modal false")
        #expect(t?.effects == [.tile(true)])
        #expect(t?.matchers.count == 2)
    }

    @Test func blockForm() {
        let r = WindowRuleParser.parseBlock([("name", "move-kitty"), ("match:class", "kitty"), ("move", "100 100"), ("animation", "popin")], location: here).rule
        #expect(r?.name == "move-kitty")
        #expect(r?.effects == [.move(ExprPair(x: "100", y: "100")), .animation("popin")])
    }

    @Test func legacyForms() {
        let v51 = rule("float, class:kitty, title:kitty")
        #expect(v51?.effects == [.float(true)])
        #expect(v51?.matchers.count == 2)
        let v2 = rule("noinitialfocus, floating:1, class:^(pavucontrol)$", keyword: "windowrulev2")
        #expect(v2?.effects == [.noInitialFocus(true)])
        #expect(v2?.matchers.contains(.float(true)) == true)
        let v1 = rule("float, ^(kitty)$")
        #expect(v1?.effects == [.float(true)])
        #expect(rule("noborder, class:x")?.effects == [.borderSize(0)])
    }

    @Test func effectsWithArguments() {
        #expect(rule("workspace 2 silent, match:class x")?.effects == [.workspace("2", silent: true)])
        #expect(rule("workspace unset, match:class x")?.effects == [.workspaceUnset])
        #expect(rule("size 800 600, match:class x")?.effects == [.size(ExprPair(x: "800", y: "600"))])
        #expect(rule("opacity 0.8, match:class x")?.effects == [.accepted("opacity")])
        let bc = rule("border_color rgb(FF0000) rgb(880808), match:fullscreen 1")?.effects.first
        if case .borderColor(let a, let i) = bc { #expect(a.colors.count == 1 && i?.colors.count == 1) } else { Issue.record("no border color") }
    }

    @Test func diagnostics() {
        func msg(_ v: String) -> String? { WindowRuleParser.parse(keyword: "windowrule", value: v, location: here).diagnostics.first?.message }
        #expect(msg("float on") == "rule needs at least one match prop")
        #expect(msg("float on, match:class a, match:class b") == "duplicate rule prop 'class'")
        #expect(msg("float on, match:bogus a") == "invalid rule prop 'bogus'")
        #expect(msg("explode, match:class a") == "invalid rule effect 'explode'")
        #expect(msg("float on, match:class (") == "invalid regex '('")
    }

    @Test func classMatchesBundleIdOrAppName() {
        let byId = rule("tile on, match:class com\\.mitchellh\\.ghostty")!
        let byName = rule("tile on, match:class Ghostty")!
        #expect(RuleEngine.matches(byId, facts()))
        #expect(RuleEngine.matches(byName, facts()))
        #expect(!RuleEngine.matches(rule("tile on, match:class ghost")!, facts()))
    }

    @Test func appWithoutBundleIdMatchesByName() {
        let r = rule("float on, match:class Minecraft")!
        #expect(RuleEngine.matches(r, facts(bundle: "", app: "Minecraft")))
        #expect(!RuleEngine.matches(rule("float on, match:class ")!, facts(bundle: "", app: "Minecraft")))
    }

    @Test func negativeRegexAndUnicodeTitles() {
        #expect(RuleEngine.matches(rule("float on, match:class negative:kitty")!, facts()))
        #expect(!RuleEngine.matches(rule("float on, match:class negative:kitty")!, facts(bundle: "net.kovidgoyal.kitty", app: "kitty")))
        #expect(RuleEngine.matches(rule("float on, match:title .*日本語.*")!, facts(title: "メモ 日本語 \"q\" \\ 🎉")))
    }

    @Test func lastMatchWinsAndNamedRulesFirst() {
        let rules = [
            rule("float on, match:class .*")!,
            rule("tile on, match:class Ghostty, match:modal false")!,
            WindowRuleParser.parseBlock([("name", "named"), ("match:class", ".*"), ("float", "on")], location: SourceLocation(file: "/x", line: 99)).rule!,
        ]
        #expect(RuleEngine.ordered(rules).first?.name == "named")
        #expect(RuleEngine.staticOutcome(rules, facts()).floating == false)
        #expect(RuleEngine.staticOutcome(rules, facts(modal: true)).floating == true)
        #expect(RuleEngine.staticOutcome(rules, facts(bundle: "com.apple.calculator", app: "Calculator")).floating == true)
    }

    @Test func ignoreWorkspaceAndMatchedLines() {
        let rules = [rule("ignore on, match:class Raycast")!, rule("workspace 3 silent, match:class Raycast")!]
        let o = RuleEngine.staticOutcome(rules, facts(bundle: "com.raycast.macos", app: "Raycast"))
        #expect(o.ignore)
        #expect(o.workspace == WorkspaceTarget(selector: "3", silent: true))
        #expect(o.matched.count == 2)
    }

    @Test func dynamicOutcomeUsesFocus() {
        let rules = [rule("border_size 4, match:focus true")!, rule("no_anim on, match:class Ghostty")!]
        #expect(RuleEngine.dynamicOutcome(rules, facts(focused: true)).borderSize == 4)
        #expect(RuleEngine.dynamicOutcome(rules, facts(focused: false)).borderSize == nil)
        #expect(RuleEngine.dynamicOutcome(rules, facts()).noAnim)
    }

    @Test func expressions() {
        let vars = ["monitor_w": 1000.0, "window_w": 200.0]
        #expect(RuleEngine.evaluate("monitor_w*0.5", axisLength: 1000, variables: vars) == 500)
        #expect(RuleEngine.evaluate("(monitor_w-window_w)/2", axisLength: 1000, variables: vars) == 400)
        #expect(RuleEngine.evaluate("-10+5", axisLength: 1000, variables: vars) == -5)
        #expect(RuleEngine.evaluate("25%", axisLength: 1000, variables: vars) == 250)
        #expect(RuleEngine.evaluate("bogus", axisLength: 1000, variables: vars) == nil)
        let p = RuleEngine.resolveMove(ExprPair(x: "monitor_w-window_w", y: "20"), facts())
        #expect(p == Point(x: 712, y: 20))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WindowRuleTests`
Expected: FAIL, "cannot find 'WindowRuleParser' in scope".

- [ ] **Step 3: Implement the rule types and parser**

`Sources/HyprCore/Rules/WindowRule.swift`:

```swift
import Foundation

public struct RuleRegex: Equatable, @unchecked Sendable {
    public let pattern: String
    public let negative: Bool
    private let regex: NSRegularExpression

    public init?(_ raw: String) {
        var p = raw.trimmingCharacters(in: .whitespaces)
        let neg = p.hasPrefix("negative:")
        if neg { p = String(p.dropFirst("negative:".count)) }
        guard let r = try? NSRegularExpression(pattern: "^(?:\(p))$") else { return nil }
        pattern = p; negative = neg; regex = r
    }

    public func matches(_ s: String) -> Bool { matchesAny([s]) }

    public func matchesAny(_ values: [String]) -> Bool {
        values.contains { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil } != negative
    }

    public static func == (a: RuleRegex, b: RuleRegex) -> Bool { a.pattern == b.pattern && a.negative == b.negative }
}

public enum RuleMatcher: Equatable, Sendable {
    case cls(RuleRegex), title(RuleRegex), initialClass(RuleRegex), initialTitle(RuleRegex)
    case float(Bool), fullscreen(Bool), pin(Bool), focus(Bool), modal(Bool)
    case workspace(String)
    case never
}

public struct ExprPair: Equatable, Sendable {
    public var x: String
    public var y: String
    public init(x: String, y: String) { self.x = x; self.y = y }
}

public enum RuleEffect: Equatable, Sendable {
    case float(Bool), tile(Bool), fullscreen(Bool), maximize(Bool), center(Bool), pseudo(Bool), pin(Bool)
    case noInitialFocus(Bool), ignore(Bool), noAnim(Bool), dimAround(Bool)
    case move(ExprPair), size(ExprPair), monitor(String), workspace(String, silent: Bool), workspaceUnset
    case borderColor(active: Gradient, inactive: Gradient?), borderSize(Int), minSize(Size), maxSize(Size), animation(String)
    case accepted(String)

    var isStatic: Bool {
        switch self {
        case .float, .tile, .fullscreen, .maximize, .center, .pseudo, .pin, .noInitialFocus, .ignore,
             .move, .size, .monitor, .workspace, .workspaceUnset: return true
        default: return false
        }
    }
}

public struct WindowRule: Equatable, Sendable {
    public var name: String?
    public var matchers: [RuleMatcher]
    public var effects: [RuleEffect]
    public var location: SourceLocation
    public init(name: String?, matchers: [RuleMatcher], effects: [RuleEffect], location: SourceLocation) {
        self.name = name; self.matchers = matchers; self.effects = effects; self.location = location
    }
}

public enum WindowRuleParser {
    static let legacyFields: [String: String] = [
        "class": "class", "title": "title", "initialClass": "initial_class", "initialTitle": "initial_title",
        "tag": "tag", "xdgtag": "xdg_tag", "content": "content", "xwayland": "xwayland", "floating": "float",
        "fullscreen": "fullscreen", "pinned": "pin", "focus": "focus", "group": "group",
        "fullscreenstate": "fullscreen_state_internal", "workspace": "workspace", "onworkspace": "workspace",
    ]
    static let legacyEffects: [String: String] = [
        "noinitialfocus": "no_initial_focus", "bordercolor": "border_color", "bordersize": "border_size", "noanim": "no_anim",
        "maxsize": "max_size", "minsize": "min_size", "dimaround": "dim_around", "suppressevent": "suppress_event",
        "stayfocused": "stay_focused", "nofocus": "no_focus", "nomaxsize": "no_max_size", "persistentsize": "persistent_size",
        "idleinhibit": "idle_inhibit", "noblur": "no_blur", "noshadow": "no_shadow", "nodim": "no_dim", "forcergbx": "force_rgbx",
        "keepaspectratio": "keep_aspect_ratio", "nearestneighbor": "nearest_neighbor", "focusonactivate": "focus_on_activate",
        "allowsinput": "allows_input", "roundingpower": "rounding_power", "scrollmouse": "scroll_mouse",
        "scrolltouchpad": "scroll_touchpad", "noscreenshare": "no_screen_share", "novrr": "no_vrr",
        "syncfullscreen": "sync_fullscreen", "renderunfocused": "render_unfocused", "noclosefor": "no_close_for",
        "fullscreenstate": "fullscreen_state", "noshortcutsinhibit": "no_shortcuts_inhibit", "nofollowmouse": "no_follow_mouse",
    ]
    static let acceptedEffects: Set<String> = [
        "fullscreen_state", "group", "suppress_event", "content", "no_close_for", "scrolling_width", "persistent_size",
        "no_max_size", "stay_focused", "idle_inhibit", "opacity", "tag", "rounding", "rounding_power", "allows_input",
        "decorate", "focus_on_activate", "keep_aspect_ratio", "nearest_neighbor", "no_blur", "no_dim", "no_focus",
        "no_follow_mouse", "no_shadow", "no_shortcuts_inhibit", "no_screen_share", "no_vrr", "opaque", "force_rgbx",
        "sync_fullscreen", "immediate", "xray", "render_unfocused", "scroll_mouse", "scroll_touchpad", "confine_pointer",
        "no_auto_hdr", "no_glow", "no_wobble", "no_xdg_drags", "tonemap", "norounding", "unset",
    ]
    static let boolEffects: [String: (Bool) -> RuleEffect] = [
        "float": RuleEffect.float, "tile": RuleEffect.tile, "fullscreen": RuleEffect.fullscreen, "maximize": RuleEffect.maximize,
        "center": RuleEffect.center, "pseudo": RuleEffect.pseudo, "pin": RuleEffect.pin, "no_initial_focus": RuleEffect.noInitialFocus,
        "ignore": RuleEffect.ignore, "no_anim": RuleEffect.noAnim, "dim_around": RuleEffect.dimAround,
    ]

    private struct Builder {
        var name: String?
        var matchers: [RuleMatcher] = []
        var effects: [RuleEffect] = []
        var props: Set<String> = []
        var diagnostics: [Diagnostic] = []
        let location: SourceLocation

        mutating func prop(_ rawName: String, _ value: String) {
            let name = rawName.trimmingCharacters(in: .whitespaces)
            let v = value.trimmingCharacters(in: .whitespaces)
            guard !props.contains(name) else { diagnostics.append(Diagnostic(location, "duplicate rule prop '\(name)'")); return }
            props.insert(name)
            func regex(_ make: (RuleRegex) -> RuleMatcher) {
                if let r = RuleRegex(v) { matchers.append(make(r)) } else { diagnostics.append(Diagnostic(location, "invalid regex '\(v)'")) }
            }
            func flag(_ make: (Bool) -> RuleMatcher) {
                if let b = ConfigValue.bool(v) { matchers.append(make(b)) } else { diagnostics.append(Diagnostic(location, "invalid value '\(v)' for \(name)")) }
            }
            switch name {
            case "class": regex(RuleMatcher.cls)
            case "title": regex(RuleMatcher.title)
            case "initial_class": regex(RuleMatcher.initialClass)
            case "initial_title": regex(RuleMatcher.initialTitle)
            case "float": flag(RuleMatcher.float)
            case "fullscreen": flag(RuleMatcher.fullscreen)
            case "pin": flag(RuleMatcher.pin)
            case "focus": flag(RuleMatcher.focus)
            case "modal": flag(RuleMatcher.modal)
            case "workspace": matchers.append(.workspace(v))
            case "xwayland", "group": if ConfigValue.bool(v) == true { matchers.append(.never) }
            case "tag", "content", "xdg_tag", "fullscreen_state_client", "fullscreen_state_internal": matchers.append(.never)
            default: props.remove(name); diagnostics.append(Diagnostic(location, "invalid rule prop '\(name)'"))
            }
        }

        mutating func effect(_ rawName: String, _ rawArgs: String) {
            var name = rawName.trimmingCharacters(in: .whitespaces)
            let args = rawArgs.trimmingCharacters(in: .whitespaces)
            if name == "noborder" { effects.append(.borderSize(0)); return }
            name = WindowRuleParser.legacyEffects[name] ?? name
            let tokens = args.split(separator: " ").map(String.init)
            if let make = WindowRuleParser.boolEffects[name] {
                if args.isEmpty { effects.append(make(true)); return }
                if let b = ConfigValue.bool(args) { effects.append(make(b)) } else { diagnostics.append(Diagnostic(location, "invalid value '\(args)' for \(name)")) }
                return
            }
            switch name {
            case "move", "size":
                guard tokens.count == 2 else { diagnostics.append(Diagnostic(location, "invalid \(name) '\(args)'")); return }
                let pair = ExprPair(x: tokens[0], y: tokens[1])
                effects.append(name == "move" ? .move(pair) : .size(pair))
            case "monitor":
                guard !args.isEmpty else { diagnostics.append(Diagnostic(location, "missing monitor")); return }
                effects.append(.monitor(args))
            case "workspace":
                if args == "unset" { effects.append(.workspaceUnset); return }
                var t = tokens
                let silent = t.last == "silent"
                if silent { t.removeLast() }
                guard !t.isEmpty else { diagnostics.append(Diagnostic(location, "missing workspace")); return }
                effects.append(.workspace(t.joined(separator: " "), silent: silent))
            case "border_color":
                guard let (active, inactive) = WindowRuleParser.borderColors(tokens) else {
                    diagnostics.append(Diagnostic(location, "invalid border_color '\(args)'")); return
                }
                effects.append(.borderColor(active: active, inactive: inactive))
            case "border_size":
                guard let n = Int(args) else { diagnostics.append(Diagnostic(location, "invalid border_size '\(args)'")); return }
                effects.append(.borderSize(n))
            case "min_size", "max_size":
                guard let (w, h) = ConfigValue.vec2(args) else { diagnostics.append(Diagnostic(location, "invalid \(name) '\(args)'")); return }
                effects.append(name == "min_size" ? .minSize(Size(width: w, height: h)) : .maxSize(Size(width: w, height: h)))
            case "animation":
                effects.append(.animation(args))
            default:
                if WindowRuleParser.acceptedEffects.contains(name) { effects.append(.accepted(name)) }
                else { diagnostics.append(Diagnostic(location, "invalid rule effect '\(name)'")) }
            }
        }

        func finish() -> (rule: WindowRule?, diagnostics: [Diagnostic]) {
            if !diagnostics.isEmpty { return (nil, diagnostics) }
            if props.isEmpty { return (nil, [Diagnostic(location, "rule needs at least one match prop")]) }
            return (WindowRule(name: name, matchers: matchers, effects: effects, location: location), [])
        }
    }

    static func borderColors(_ tokens: [String]) -> (Gradient, Gradient?)? {
        if !tokens.contains(where: { $0.hasSuffix("deg") }) {
            let colors = tokens.compactMap(ConfigValue.color)
            guard colors.count == tokens.count, (1...2).contains(colors.count) else { return nil }
            return (Gradient(colors[0]), colors.count == 2 ? Gradient(colors[1]) : nil)
        }
        guard let split = tokens.firstIndex(where: { $0.hasSuffix("deg") }) else { return nil }
        guard let active = ConfigValue.gradient(tokens[...split].joined(separator: " ")) else { return nil }
        let rest = tokens[(split + 1)...]
        if rest.isEmpty { return (active, nil) }
        guard let inactive = ConfigValue.gradient(rest.joined(separator: " ")) else { return nil }
        return (active, inactive)
    }

    private static func splitFirstSpace(_ s: String) -> (String, String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let i = t.firstIndex(of: " ") else { return (t, "") }
        return (String(t[..<i]), String(t[t.index(after: i)...]))
    }

    public static func parse(keyword: String, value: String, location: SourceLocation) -> (rule: WindowRule?, diagnostics: [Diagnostic]) {
        var b = Builder(location: location)
        let parts = value.split(separator: ",", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
        if keyword == "windowrule" && parts.contains(where: { $0.hasPrefix("match:") }) {
            for part in parts {
                if part.hasPrefix("match:") {
                    let (p, v) = splitFirstSpace(String(part.dropFirst(6)))
                    b.prop(p, v)
                } else {
                    let (e, a) = splitFirstSpace(part)
                    b.effect(e, a)
                }
            }
            return b.finish()
        }
        func field(_ part: String) -> (String, String)? {
            guard let colon = part.firstIndex(of: ":") else { return nil }
            let key = String(part[..<colon])
            guard let mapped = legacyFields[key] else { return nil }
            return (mapped, String(part[part.index(after: colon)...]))
        }
        let fields = parts.compactMap(field)
        if fields.isEmpty && parts.count == 2 {
            let (e, a) = splitFirstSpace(parts[0])
            b.effect(e, a)
            b.prop("class", parts[1])
            return b.finish()
        }
        for part in parts {
            if let (p, v) = field(part) { b.prop(p, v) } else { let (e, a) = splitFirstSpace(part); b.effect(e, a) }
        }
        return b.finish()
    }

    public static func parseBlock(_ fields: [(key: String, value: String)], location: SourceLocation) -> (rule: WindowRule?, diagnostics: [Diagnostic]) {
        var b = Builder(location: location)
        for (key, value) in fields {
            if key == "name" { b.name = value; continue }
            if key == "enable" { continue }
            if key.hasPrefix("match:") { b.prop(String(key.dropFirst(6)), value) } else { b.effect(key, value) }
        }
        return b.finish()
    }
}
```

`Sources/HyprCore/Rules/RuleEngine.swift`:

```swift
import Foundation

public struct WindowFacts: Equatable, Sendable {
    public var bundleID: String
    public var appName: String
    public var title: String
    public var initialTitle: String
    public var isFloating: Bool
    public var isFullscreen: Bool
    public var isPinned: Bool
    public var isFocused: Bool
    public var isModal: Bool
    public var workspaceID: Int?
    public var workspaceName: String?
    public var monitorSize: Size
    public var windowFrame: Rect
    public var cursor: Point
    public init(bundleID: String, appName: String, title: String, initialTitle: String, isFloating: Bool, isFullscreen: Bool,
                isPinned: Bool, isFocused: Bool, isModal: Bool, workspaceID: Int?, workspaceName: String?,
                monitorSize: Size, windowFrame: Rect, cursor: Point) {
        self.bundleID = bundleID; self.appName = appName; self.title = title; self.initialTitle = initialTitle
        self.isFloating = isFloating; self.isFullscreen = isFullscreen; self.isPinned = isPinned; self.isFocused = isFocused
        self.isModal = isModal; self.workspaceID = workspaceID; self.workspaceName = workspaceName
        self.monitorSize = monitorSize; self.windowFrame = windowFrame; self.cursor = cursor
    }
}

public struct WorkspaceTarget: Equatable, Sendable {
    public var selector: String
    public var silent: Bool
    public init(selector: String, silent: Bool) { self.selector = selector; self.silent = silent }
}

public struct StaticRuleOutcome: Equatable, Sendable {
    public var floating: Bool?
    public var fullscreenMode: Int?
    public var move: ExprPair?
    public var size: ExprPair?
    public var center = false
    public var pseudo = false
    public var pin = false
    public var noInitialFocus = false
    public var ignore = false
    public var monitor: String?
    public var workspace: WorkspaceTarget?
    public var matched: [SourceLocation] = []
    public init() {}
}

public struct DynamicRuleOutcome: Equatable, Sendable {
    public var activeBorder: Gradient?
    public var inactiveBorder: Gradient?
    public var borderSize: Int?
    public var noAnim = false
    public var minSize: Size?
    public var maxSize: Size?
    public var animationStyle: String?
    public var dimAround = false
    public init() {}
}

public enum RuleEngine {
    public static func ordered(_ rules: [WindowRule]) -> [WindowRule] {
        rules.filter { $0.name != nil } + rules.filter { $0.name == nil }
    }

    public static func matches(_ rule: WindowRule, _ f: WindowFacts) -> Bool {
        rule.matchers.allSatisfy { m in
            switch m {
            case .cls(let r), .initialClass(let r): return r.matchesAny(f.bundleID.isEmpty ? [f.appName] : [f.bundleID, f.appName])
            case .title(let r): return r.matches(f.title)
            case .initialTitle(let r): return r.matches(f.initialTitle)
            case .float(let b): return f.isFloating == b
            case .fullscreen(let b): return f.isFullscreen == b
            case .pin(let b): return f.isPinned == b
            case .focus(let b): return f.isFocused == b
            case .modal(let b): return f.isModal == b
            case .workspace(let w):
                if w.hasPrefix("name:") { return f.workspaceName == String(w.dropFirst(5)) }
                if let id = Int(w) { return f.workspaceID == id }
                return false
            case .never: return false
            }
        }
    }

    public static func staticOutcome(_ rules: [WindowRule], _ f: WindowFacts) -> StaticRuleOutcome {
        var o = StaticRuleOutcome()
        for rule in ordered(rules) where matches(rule, f) {
            if rule.effects.contains(where: \.isStatic) { o.matched.append(rule.location) }
            for e in rule.effects {
                switch e {
                case .float(let b): o.floating = b ? true : nil
                case .tile(let b): o.floating = b ? false : nil
                case .fullscreen(let b): o.fullscreenMode = b ? 0 : nil
                case .maximize(let b): o.fullscreenMode = b ? 1 : nil
                case .center(let b): o.center = b
                case .pseudo(let b): o.pseudo = b
                case .pin(let b): o.pin = b
                case .noInitialFocus(let b): o.noInitialFocus = b
                case .ignore(let b): o.ignore = b
                case .move(let p): o.move = p
                case .size(let p): o.size = p
                case .monitor(let m): o.monitor = m
                case .workspace(let w, let silent): o.workspace = WorkspaceTarget(selector: w, silent: silent)
                case .workspaceUnset: o.workspace = nil
                default: break
                }
            }
        }
        return o
    }

    public static func dynamicOutcome(_ rules: [WindowRule], _ f: WindowFacts) -> DynamicRuleOutcome {
        var o = DynamicRuleOutcome()
        for rule in ordered(rules) where matches(rule, f) {
            for e in rule.effects {
                switch e {
                case .borderColor(let a, let i): o.activeBorder = a; if let i { o.inactiveBorder = i }
                case .borderSize(let n): o.borderSize = n
                case .noAnim(let b): o.noAnim = b
                case .minSize(let s): o.minSize = s
                case .maxSize(let s): o.maxSize = s
                case .animation(let s): o.animationStyle = s
                case .dimAround(let b): o.dimAround = b
                default: break
                }
            }
        }
        return o
    }

    static func variables(_ f: WindowFacts) -> [String: Double] {
        ["monitor_w": f.monitorSize.width, "monitor_h": f.monitorSize.height, "window_x": f.windowFrame.x, "window_y": f.windowFrame.y,
         "window_w": f.windowFrame.width, "window_h": f.windowFrame.height, "cursor_x": f.cursor.x, "cursor_y": f.cursor.y]
    }

    public static func resolveMove(_ p: ExprPair, _ f: WindowFacts) -> Point? {
        let v = variables(f)
        guard let x = evaluate(p.x, axisLength: f.monitorSize.width, variables: v),
              let y = evaluate(p.y, axisLength: f.monitorSize.height, variables: v) else { return nil }
        return Point(x: x, y: y)
    }

    public static func resolveSize(_ p: ExprPair, _ f: WindowFacts) -> Size? {
        let v = variables(f)
        guard let w = evaluate(p.x, axisLength: f.monitorSize.width, variables: v),
              let h = evaluate(p.y, axisLength: f.monitorSize.height, variables: v) else { return nil }
        return Size(width: w, height: h)
    }

    public static func evaluate(_ expr: String, axisLength: Double, variables: [String: Double]) -> Double? {
        let e = expr.trimmingCharacters(in: .whitespaces)
        if e.hasSuffix("%"), let n = Double(e.dropLast()) { return n / 100 * axisLength }
        var p = ExpressionParser(chars: Array(e.replacingOccurrences(of: " ", with: "")), variables: variables)
        guard let v = p.expression(), p.index == p.chars.count else { return nil }
        return v
    }
}

private struct ExpressionParser {
    let chars: [Character]
    let variables: [String: Double]
    var index = 0

    init(chars: [Character], variables: [String: Double]) { self.chars = chars; self.variables = variables }

    mutating func expression() -> Double? {
        guard var value = term() else { return nil }
        while index < chars.count, chars[index] == "+" || chars[index] == "-" {
            let op = chars[index]; index += 1
            guard let rhs = term() else { return nil }
            value = op == "+" ? value + rhs : value - rhs
        }
        return value
    }

    mutating func term() -> Double? {
        guard var value = factor() else { return nil }
        while index < chars.count, chars[index] == "*" || chars[index] == "/" {
            let op = chars[index]; index += 1
            guard let rhs = factor() else { return nil }
            if op == "/" && rhs == 0 { return nil }
            value = op == "*" ? value * rhs : value / rhs
        }
        return value
    }

    mutating func factor() -> Double? {
        guard index < chars.count else { return nil }
        if chars[index] == "-" { index += 1; return factor().map { -$0 } }
        if chars[index] == "(" {
            index += 1
            guard let v = expression(), index < chars.count, chars[index] == ")" else { return nil }
            index += 1
            return v
        }
        let start = index
        if chars[index].isNumber || chars[index] == "." {
            while index < chars.count, chars[index].isNumber || chars[index] == "." { index += 1 }
            return Double(String(chars[start..<index]))
        }
        while index < chars.count, chars[index].isLetter || chars[index] == "_" { index += 1 }
        guard index > start else { return nil }
        return variables[String(chars[start..<index])]
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter WindowRuleTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/HyprCore/Rules/WindowRule.swift Sources/HyprCore/Rules/RuleEngine.swift Tests/HyprCoreTests/WindowRuleTests.swift
git commit -m "feat: add window rules in every Hyprland syntax and the rule engine"
```

---

### Task 7: Workspace rules

**Files:**
- Create: `Sources/HyprCore/Rules/WorkspaceRule.swift`
- Test: `Tests/HyprCoreTests/WorkspaceRuleTests.swift`

**Interfaces:**
- Consumes: `Edges`, `SourceLocation`, `Diagnostic` (Task 1); `ConfigValue` (Task 3).
- Produces:

```swift
public struct WorkspaceFacts: Equatable, Sendable {
    public var id: Int; public var name: String; public var isSpecial: Bool; public var monitorName: String
    public var tiledCount: Int; public var floatingCount: Int; public var fullscreenMode: Int     // -1 none, 0 fullscreen, 1 maximize
}
public enum WorkspaceFilter: Equatable, Sendable {
    case idRange(Int, Int), special(Bool), named(Bool), nameStarts(String), nameEnds(String), monitor(String)
    case windowCount(tiled: Bool, floating: Bool, min: Int, max: Int), fullscreen(Int)
}
public enum WorkspaceRuleSelector: Equatable, Sendable { case id(Int), name(String), special(String?), filters([WorkspaceFilter]) }
public struct WorkspaceRule: Equatable, Sendable {
    public var selector: WorkspaceRuleSelector
    public var monitor: String?; public var isDefault: Bool?; public var gapsIn: Edges?; public var gapsOut: Edges?
    public var borderSize: Int?; public var border: Bool?; public var persistent: Bool?; public var defaultName: String?
    public var layout: String?; public var orientation: String?; public var onCreatedEmpty: String?
    public var location: SourceLocation
    public static func parse(_ value: String, location: SourceLocation) -> (rule: WorkspaceRule?, diagnostics: [Diagnostic])
    public func matches(_ f: WorkspaceFacts, monitorMatches: (String) -> Bool) -> Bool
}
```

Rules: the value is `SELECTOR, rule:value, ...`. Selector: integer -> `.id`; `name:X` -> `.name`; `special` / `special:X` -> `.special`; text with `[` -> concatenated filters (`r[A-B]`, `s[bool]`, `n[bool|s:str|e:str]`, `m[monitor]`, `w[FLAGS A-B|X]` with flags among `tfgvp` where `g` and `p` are ignored and `v` counts like no flag, `f[-1|0|1|2]`); anything else is an error "invalid workspace selector 'x'". Each rule part splits at its first colon: `monitor`, `default`, `gapsin`, `gapsout` (CSS edges), `bordersize`, `border`, `persistent`, `defaultName`, `layout`, `layoutopt` (value `orientation:X`), `on-created-empty`; `shadow`, `rounding`, `decorate`, `animations`, `animation`, `gapsworkspaces` are accepted and ignored; others give "invalid workspace rule 'x'". An id selector matches `f.id`, a name selector matches `f.name` for non-special workspaces, a special selector matches special workspaces with that name (`nil` means "special"); filters must all match (`w[t...]` counts tiled only, `w[f...]` floating only, else both; `f[-1]` means no fullscreen).

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/WorkspaceRuleTests.swift`:

```swift
import Testing
@testable import HyprCore

private let here = SourceLocation(file: "/cfg/hyprland.conf", line: 4)
private func ws(_ id: Int, name: String? = nil, special: Bool = false, monitor: String = "Built-in Retina Display",
                tiled: Int = 0, floating: Int = 0, fullscreen: Int = -1) -> WorkspaceFacts {
    WorkspaceFacts(id: id, name: name ?? String(id), isSpecial: special, monitorName: monitor, tiledCount: tiled,
                   floatingCount: floating, fullscreenMode: fullscreen)
}

@Suite struct WorkspaceRuleTests {
    @Test func parsesRules() {
        let r = WorkspaceRule.parse("1, monitor:0, default:true, gapsout:20, layoutopt:orientation:top, layout:master", location: here)
        #expect(r.diagnostics.isEmpty)
        #expect(r.rule?.selector == .id(1))
        #expect(r.rule?.monitor == "0")
        #expect(r.rule?.isDefault == true)
        #expect(r.rule?.gapsOut == Edges(all: 20))
        #expect(r.rule?.orientation == "top")
        #expect(r.rule?.layout == "master")
    }

    @Test func monitorDescriptionKeepsColons() {
        #expect(WorkspaceRule.parse("name:gaming, monitor:desc:PHL 499P9", location: here).rule?.monitor == "desc:PHL 499P9")
    }

    @Test func smartGapsFilters() {
        let tv1 = WorkspaceRule.parse("w[tv1], gapsout:0, gapsin:0", location: here).rule!
        #expect(tv1.matches(ws(1, tiled: 1), monitorMatches: { _ in true }))
        #expect(!tv1.matches(ws(1, tiled: 2), monitorMatches: { _ in true }))
        let f1 = WorkspaceRule.parse("f[1], gapsout:0", location: here).rule!
        #expect(f1.matches(ws(2, tiled: 3, fullscreen: 1), monitorMatches: { _ in true }))
        let combo = WorkspaceRule.parse("w[tv1]s[false], gapsout:0", location: here).rule!
        #expect(!combo.matches(ws(-99, name: "special", special: true, tiled: 1), monitorMatches: { _ in true }))
    }

    @Test func idNameSpecialAndMonitorFilters() {
        #expect(WorkspaceRule.parse("3, bordersize:0", location: here).rule!.matches(ws(3), monitorMatches: { _ in true }))
        #expect(WorkspaceRule.parse("name:web, persistent:true", location: here).rule!.matches(ws(1000000, name: "web"), monitorMatches: { _ in true }))
        #expect(WorkspaceRule.parse("special:magic, gapsout:50", location: here).rule!.matches(ws(-98, name: "magic", special: true), monitorMatches: { _ in true }))
        let m = WorkspaceRule.parse("m[1], gapsout:20", location: here).rule!
        #expect(m.matches(ws(4), monitorMatches: { $0 == "1" }))
        #expect(!m.matches(ws(4), monitorMatches: { _ in false }))
        #expect(WorkspaceRule.parse("r[1-5], gapsout:20", location: here).rule!.matches(ws(5), monitorMatches: { _ in true }))
    }

    @Test func acceptedAndInvalid() {
        #expect(WorkspaceRule.parse("2, rounding:false, shadow:false", location: here).diagnostics.isEmpty)
        #expect(WorkspaceRule.parse("2, wobble:true", location: here).diagnostics.first?.message == "invalid workspace rule 'wobble'")
        #expect(WorkspaceRule.parse("x[1], gapsin:0", location: here).diagnostics.first?.message == "invalid workspace selector 'x[1]'")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WorkspaceRuleTests`
Expected: FAIL, "cannot find 'WorkspaceRule' in scope".

- [ ] **Step 3: Implement workspace rules**

`Sources/HyprCore/Rules/WorkspaceRule.swift`:

```swift
import Foundation

public struct WorkspaceFacts: Equatable, Sendable {
    public var id: Int
    public var name: String
    public var isSpecial: Bool
    public var monitorName: String
    public var tiledCount: Int
    public var floatingCount: Int
    public var fullscreenMode: Int
    public init(id: Int, name: String, isSpecial: Bool, monitorName: String, tiledCount: Int, floatingCount: Int, fullscreenMode: Int) {
        self.id = id; self.name = name; self.isSpecial = isSpecial; self.monitorName = monitorName
        self.tiledCount = tiledCount; self.floatingCount = floatingCount; self.fullscreenMode = fullscreenMode
    }
}

public enum WorkspaceFilter: Equatable, Sendable {
    case idRange(Int, Int)
    case special(Bool)
    case named(Bool)
    case nameStarts(String)
    case nameEnds(String)
    case monitor(String)
    case windowCount(tiled: Bool, floating: Bool, min: Int, max: Int)
    case fullscreen(Int)
}

public enum WorkspaceRuleSelector: Equatable, Sendable {
    case id(Int)
    case name(String)
    case special(String?)
    case filters([WorkspaceFilter])
}

public struct WorkspaceRule: Equatable, Sendable {
    public var selector: WorkspaceRuleSelector
    public var monitor: String?
    public var isDefault: Bool?
    public var gapsIn: Edges?
    public var gapsOut: Edges?
    public var borderSize: Int?
    public var border: Bool?
    public var persistent: Bool?
    public var defaultName: String?
    public var layout: String?
    public var orientation: String?
    public var onCreatedEmpty: String?
    public var location: SourceLocation

    static let ignoredRules: Set<String> = ["shadow", "rounding", "decorate", "animations", "animation", "gapsworkspaces"]

    public static func parse(_ value: String, location: SourceLocation) -> (rule: WorkspaceRule?, diagnostics: [Diagnostic]) {
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = parts.first, let selector = parseSelector(first) else {
            return (nil, [Diagnostic(location, "invalid workspace selector '\(parts.first ?? "")'")])
        }
        var rule = WorkspaceRule(selector: selector, location: location)
        var diagnostics: [Diagnostic] = []
        for part in parts.dropFirst() {
            guard let colon = part.firstIndex(of: ":") else { diagnostics.append(Diagnostic(location, "invalid workspace rule '\(part)'")); continue }
            let key = String(part[..<colon])
            let v = String(part[part.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "monitor": rule.monitor = v
            case "default": rule.isDefault = ConfigValue.bool(v)
            case "gapsin": rule.gapsIn = ConfigValue.edges(v)
            case "gapsout": rule.gapsOut = ConfigValue.edges(v)
            case "bordersize": rule.borderSize = ConfigValue.int(v)
            case "border": rule.border = ConfigValue.bool(v)
            case "persistent": rule.persistent = ConfigValue.bool(v)
            case "defaultName": rule.defaultName = v
            case "layout": rule.layout = v
            case "layoutopt":
                if v.hasPrefix("orientation:") { rule.orientation = String(v.dropFirst("orientation:".count)) }
            case "on-created-empty": rule.onCreatedEmpty = v
            default:
                if !ignoredRules.contains(key) { diagnostics.append(Diagnostic(location, "invalid workspace rule '\(key)'")) }
            }
        }
        return (rule, diagnostics)
    }

    init(selector: WorkspaceRuleSelector, location: SourceLocation) { self.selector = selector; self.location = location }

    static func parseSelector(_ s: String) -> WorkspaceRuleSelector? {
        if let n = Int(s) { return .id(n) }
        if s.hasPrefix("name:") { return .name(String(s.dropFirst(5))) }
        if s == "special" { return .special(nil) }
        if s.hasPrefix("special:") { return .special(String(s.dropFirst(8))) }
        guard s.contains("[") else { return nil }
        var filters: [WorkspaceFilter] = []
        var rest = Substring(s)
        while !rest.isEmpty {
            guard let open = rest.firstIndex(of: "["), let close = rest.firstIndex(of: "]"), open < close else { return nil }
            let kind = rest[rest.startIndex..<open]
            let body = String(rest[rest.index(after: open)..<close])
            guard let filter = parseFilter(String(kind), body) else { return nil }
            filters.append(filter)
            rest = rest[rest.index(after: close)...]
        }
        return .filters(filters)
    }

    static func parseFilter(_ kind: String, _ body: String) -> WorkspaceFilter? {
        switch kind {
        case "r":
            let p = body.split(separator: "-").compactMap { Int($0) }
            return p.count == 2 ? .idRange(p[0], p[1]) : nil
        case "s": return ConfigValue.bool(body).map { .special($0) }
        case "n":
            if body.hasPrefix("s:") { return .nameStarts(String(body.dropFirst(2))) }
            if body.hasPrefix("e:") { return .nameEnds(String(body.dropFirst(2))) }
            return ConfigValue.bool(body).map { .named($0) }
        case "m": return body.isEmpty ? nil : .monitor(body)
        case "w":
            let flags = body.prefix(while: { "tfgvp".contains($0) })
            let range = body.dropFirst(flags.count)
            let nums = range.split(separator: "-").compactMap { Int($0) }
            guard (1...2).contains(nums.count), nums.count == range.split(separator: "-").count else { return nil }
            return .windowCount(tiled: flags.contains("t"), floating: flags.contains("f"), min: nums[0], max: nums.last!)
        case "f": return Int(body).flatMap { (-1...2).contains($0) ? .fullscreen($0) : nil }
        default: return nil
        }
    }

    public func matches(_ f: WorkspaceFacts, monitorMatches: (String) -> Bool) -> Bool {
        switch selector {
        case .id(let id): return f.id == id
        case .name(let n): return !f.isSpecial && f.name == n
        case .special(let n): return f.isSpecial && f.name == (n ?? "special")
        case .filters(let filters):
            return filters.allSatisfy { filter in
                switch filter {
                case .idRange(let a, let b): return (a...b).contains(f.id)
                case .special(let b): return f.isSpecial == b
                case .named(let b): return (Int(f.name) == nil) == b
                case .nameStarts(let p): return f.name.hasPrefix(p)
                case .nameEnds(let p): return f.name.hasSuffix(p)
                case .monitor(let m): return monitorMatches(m)
                case .windowCount(let tiled, let floating, let lo, let hi):
                    let count = tiled && !floating ? f.tiledCount : (floating && !tiled ? f.floatingCount : f.tiledCount + f.floatingCount)
                    return (lo...hi).contains(count)
                case .fullscreen(let mode): return f.fullscreenMode == mode
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter WorkspaceRuleTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/HyprCore/Rules/WorkspaceRule.swift Tests/HyprCoreTests/WorkspaceRuleTests.swift
git commit -m "feat: add workspace rules and selector filters"
```

---
### Task 8: Bezier curves and animation tree

**Files:**
- Create: `Sources/HyprCore/Animation/Bezier.swift`, `Sources/HyprCore/Animation/AnimationTree.swift`
- Test: `Tests/HyprCoreTests/AnimationTests.swift`

**Interfaces:**
- Consumes: `Point` (Task 1).
- Produces:

```swift
public struct Bezier: Equatable, Sendable {
    public let p1: Point; public let p2: Point
    public init(p1: Point, p2: Point)
    public func y(at x: Double) -> Double
    public static let builtIns: [String: Bezier]                       // "default", "linear"
    public static func parse(_ value: String) -> (name: String, curve: Bezier)?   // "NAME, X0, Y0, X1, Y1"
}
public struct AnimationLeaf: Equatable, Sendable { public var enabled: Bool; public var speed: Double; public var curve: String; public var style: String
    public var durationMs: Double { get }                               // speed * 100
}
public struct AnimationTree: Equatable, Sendable {
    public static let parents: [String: String]                         // child -> parent, "global" is the root
    public init()
    public func leaf(_ name: String) -> AnimationLeaf
    public mutating func apply(_ value: String, curves: Set<String>) -> String?   // nil on success, else an error message
}
```

Behavior: `hyprland-algorithms.md` sections 3 to 5. Baking, evaluation, built-in curves, tree shape, defaults (`global` on, speed 8, `default`, style empty; `borderangle` off, speed 1, `default`), all-or-nothing inheritance. `apply` parses `NAME, ONOFF, SPEED, CURVE[, STYLE]`: unknown name gives "no such animation 'X'"; ONOFF 0 sets the node to disabled, speed 1, curve `default`, empty style (the rest may be missing); otherwise SPEED must parse and be > 0 ("animation speed must be positive"), CURVE must be in `curves` ("no such bezier 'X'"), STYLE must be valid for the leaf family ("invalid animation style 'X' for NAME"). Valid styles: windows family `slide`, `slide top|bottom|left|right`, `popin`, `popin N%`, `gnomed`; layers family `slide`, `popin`, `fade` (any arguments); workspaces family (`workspaces*`, `specialWorkspace*`) `slide`, `slidevert`, `fade`, `slidefade`, `slidefadevert`, each optionally followed by `top|bottom|left|right` and/or `N%`; `borderangle`, `shadowangle`, `glowangle`: `once`, `loop`; every other leaf accepts any style. The empty style is always valid.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/AnimationTests.swift`:

```swift
import Testing
@testable import HyprCore

@Suite struct AnimationTests {
    @Test func bezierEndpointsAndClamping() {
        let b = Bezier(p1: Point(x: 0.23, y: 1), p2: Point(x: 0.32, y: 1))
        #expect(b.y(at: 0) == 0)
        #expect(b.y(at: 1) == 1)
        #expect(b.y(at: -1) == 0)
        #expect(b.y(at: 2) == 1)
    }

    @Test func bezierMatchesHandComputedPoint() {
        let b = Bezier(p1: Point(x: 0.23, y: 1), p2: Point(x: 0.32, y: 1))
        #expect(abs(b.y(at: 0.33125) - 0.875) < 0.005)
        let linear = Bezier.builtIns["linear"]!
        #expect(abs(linear.y(at: 0.3) - 0.3) < 0.002)
    }

    @Test func overshootCurveExceedsOne() {
        let b = Bezier(p1: Point(x: 0.05, y: 0.9), p2: Point(x: 0.1, y: 1.1))
        #expect(stride(from: 0.0, through: 1.0, by: 0.01).contains { b.y(at: $0) > 1 })
    }

    @Test func defaultCurveIsBuiltIn() {
        #expect(Bezier.builtIns["default"] == Bezier(p1: Point(x: 0, y: 0.75), p2: Point(x: 0.15, y: 1)))
    }

    @Test func parseBezierLine() {
        let r = Bezier.parse("easeOutQuint,   0.23, 1,    0.32, 1")
        #expect(r?.name == "easeOutQuint")
        #expect(r?.curve == Bezier(p1: Point(x: 0.23, y: 1), p2: Point(x: 0.32, y: 1)))
        #expect(Bezier.parse("bad, 1, 2") == nil)
    }

    @Test func treeDefaults() {
        let t = AnimationTree()
        #expect(t.leaf("windowsIn") == AnimationLeaf(enabled: true, speed: 8, curve: "default", style: ""))
        #expect(t.leaf("borderangle").enabled == false)
        #expect(t.leaf("windowsMove").durationMs == 800)
    }

    @Test func inheritanceIsAllOrNothing() {
        var t = AnimationTree()
        let curves: Set<String> = ["default", "linear", "easeOutQuint"]
        #expect(t.apply("windows, 1, 4.79, easeOutQuint", curves: curves) == nil)
        #expect(t.apply("windowsIn, 1, 4.1, easeOutQuint, popin 87%", curves: curves) == nil)
        #expect(t.leaf("windowsMove") == AnimationLeaf(enabled: true, speed: 4.79, curve: "easeOutQuint", style: ""))
        #expect(t.leaf("windowsIn").style == "popin 87%")
        #expect(t.leaf("windowsOut").speed == 4.79)
        #expect(t.leaf("workspacesIn").speed == 8)
    }

    @Test func disabledLeafNeedsNoMoreFields() {
        var t = AnimationTree()
        #expect(t.apply("fade, 0", curves: ["default"]) == nil)
        #expect(t.leaf("fadeIn").enabled == false)
    }

    @Test func validation() {
        var t = AnimationTree()
        let c: Set<String> = ["default"]
        #expect(t.apply("windowz, 1, 3, default", curves: c) == "no such animation 'windowz'")
        #expect(t.apply("windows, 1, 0, default", curves: c) == "animation speed must be positive")
        #expect(t.apply("windows, 1, 3, nope", curves: c) == "no such bezier 'nope'")
        #expect(t.apply("windows, 1, 3, default, wobble", curves: c) == "invalid animation style 'wobble' for windows")
        #expect(t.apply("workspaces, 1, 3, default, slidefade 20%", curves: c) == nil)
        #expect(t.apply("borderangle, 1, 30, default, loop", curves: c) == nil)
        #expect(t.apply("workspaces, 1, 3, default, slide top", curves: c) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AnimationTests`
Expected: FAIL, "cannot find 'Bezier' in scope".

- [ ] **Step 3: Implement curves and the tree**

`Sources/HyprCore/Animation/Bezier.swift`:

```swift
import Foundation

public struct Bezier: Equatable, Sendable {
    public let p1: Point
    public let p2: Point
    private let baked: [Point]

    public init(p1: Point, p2: Point) {
        self.p1 = p1
        self.p2 = p2
        func axis(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        baked = (0..<255).map { i in
            let t = Double(i + 1) / 255
            return Point(x: axis(t, p1.x, p2.x), y: axis(t, p1.y, p2.y))
        }
    }

    public func y(at x: Double) -> Double {
        if x >= 1 { return 1 }
        if x <= 0 { return 0 }
        var lo = 0
        var hi = baked.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if baked[mid].x < x { lo = mid + 1 } else { hi = mid }
        }
        let lower = max(0, min(lo - 1, baked.count - 2))
        let a = baked[lower]
        let b = baked[lower + 1]
        let dx = b.x - a.x
        if dx <= 1e-6 { return a.y }
        return a.y + (b.y - a.y) * (x - a.x) / dx
    }

    public static func == (l: Bezier, r: Bezier) -> Bool { l.p1 == r.p1 && l.p2 == r.p2 }

    public static let builtIns: [String: Bezier] = [
        "default": Bezier(p1: Point(x: 0, y: 0.75), p2: Point(x: 0.15, y: 1)),
        "linear": Bezier(p1: Point(x: 0, y: 0), p2: Point(x: 1, y: 1)),
    ]

    public static func parse(_ value: String) -> (name: String, curve: Bezier)? {
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 5, !parts[0].isEmpty else { return nil }
        let n = parts.dropFirst().compactMap(Double.init)
        guard n.count == 4, n.allSatisfy(\.isFinite) else { return nil }
        return (parts[0], Bezier(p1: Point(x: n[0], y: n[1]), p2: Point(x: n[2], y: n[3])))
    }
}
```

`Sources/HyprCore/Animation/AnimationTree.swift`:

```swift
import Foundation

public struct AnimationLeaf: Equatable, Sendable {
    public var enabled: Bool
    public var speed: Double
    public var curve: String
    public var style: String
    public init(enabled: Bool, speed: Double, curve: String, style: String) {
        self.enabled = enabled; self.speed = speed; self.curve = curve; self.style = style
    }
    public var durationMs: Double { speed * 100 }
}

public struct AnimationTree: Equatable, Sendable {
    public static let parents: [String: String] = [
        "windows": "global", "windowsIn": "windows", "windowsOut": "windows", "windowsMove": "windows",
        "layers": "global", "layersIn": "layers", "layersOut": "layers",
        "fade": "global", "fadeIn": "fade", "fadeOut": "fade", "fadeSwitch": "fade", "fadeShadow": "fade", "fadeGlow": "fade",
        "fadeDim": "fade", "fadeLayers": "fade", "fadeLayersIn": "fadeLayers", "fadeLayersOut": "fadeLayers",
        "fadePopups": "fade", "fadePopupsIn": "fadePopups", "fadePopupsOut": "fadePopups", "fadeDpms": "fade",
        "border": "global", "borderangle": "global", "shadowangle": "global", "glowangle": "global",
        "zoomFactor": "global", "monitorAdded": "global",
        "workspaces": "global", "workspacesIn": "workspaces", "workspacesOut": "workspaces",
        "specialWorkspace": "workspaces", "specialWorkspaceIn": "specialWorkspace", "specialWorkspaceOut": "specialWorkspace",
    ]

    private var overrides: [String: AnimationLeaf] = [
        "global": AnimationLeaf(enabled: true, speed: 8, curve: "default", style: ""),
        "borderangle": AnimationLeaf(enabled: false, speed: 1, curve: "default", style: ""),
        "shadowangle": AnimationLeaf(enabled: false, speed: 1, curve: "default", style: ""),
        "glowangle": AnimationLeaf(enabled: false, speed: 1, curve: "default", style: ""),
    ]

    public init() {}

    public func leaf(_ name: String) -> AnimationLeaf {
        var current: String? = name
        while let n = current {
            if let leaf = overrides[n] { return leaf }
            current = AnimationTree.parents[n]
        }
        return overrides["global"]!
    }

    public mutating func apply(_ value: String, curves: Set<String>) -> String? {
        let parts = value.split(separator: ",", maxSplits: 4).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let name = parts.first, name == "global" || AnimationTree.parents[name] != nil else {
            return "no such animation '\(parts.first ?? "")'"
        }
        guard parts.count >= 2, let on = ConfigValue.bool(parts[1]) else { return "invalid animation '\(value)'" }
        if !on {
            overrides[name] = AnimationLeaf(enabled: false, speed: 1, curve: "default", style: "")
            return nil
        }
        guard parts.count >= 4, let speed = Double(parts[2]) else { return "invalid animation '\(value)'" }
        guard speed > 0 else { return "animation speed must be positive" }
        guard curves.contains(parts[3]) else { return "no such bezier '\(parts[3])'" }
        let style = parts.count > 4 ? parts[4] : ""
        guard AnimationTree.isValidStyle(style, for: name) else { return "invalid animation style '\(style)' for \(name)" }
        overrides[name] = AnimationLeaf(enabled: true, speed: speed, curve: parts[3], style: style)
        return nil
    }

    static func isValidStyle(_ style: String, for name: String) -> Bool {
        if style.isEmpty { return true }
        let words = style.split(separator: " ").map(String.init)
        let sides: Set<String> = ["top", "bottom", "left", "right"]
        func isPercent(_ w: String) -> Bool { w.hasSuffix("%") && Double(w.dropLast()) != nil }
        if name.hasPrefix("windows") {
            switch words[0] {
            case "slide": return words.count == 1 || (words.count == 2 && sides.contains(words[1]))
            case "popin": return words.count == 1 || (words.count == 2 && isPercent(words[1]))
            case "gnomed": return words.count == 1
            default: return false
            }
        }
        if name.hasPrefix("layers") { return ["slide", "popin", "fade"].contains(words[0]) }
        if name.hasPrefix("workspaces") || name.hasPrefix("specialWorkspace") {
            guard ["slide", "slidevert", "fade", "slidefade", "slidefadevert"].contains(words[0]) else { return false }
            return words.dropFirst().allSatisfy { sides.contains($0) || isPercent($0) }
        }
        if name.hasSuffix("angle") { return words == ["once"] || words == ["loop"] }
        return true
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AnimationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/HyprCore/Animation Tests/HyprCoreTests/AnimationTests.swift
git commit -m "feat: add baked bezier curves and the animation tree"
```

---

### Task 9: Options and config builder

**Files:**
- Create: `Sources/HyprCore/Config/Options.swift`, `Sources/HyprCore/Config/Config.swift`
- Test: `Tests/HyprCoreTests/ConfigBuilderTests.swift`

**Interfaces:**
- Consumes: `ConfigEntry` (Task 2), `ConfigValue`, `Gradient`, `Color` (Task 3), `Bind`, `BindParser` (Task 4), `WindowRule`, `WindowRuleParser` (Task 6), `WorkspaceRule` (Task 7), `Bezier`, `AnimationTree` (Task 8).
- Produces:

```swift
public struct GeneralOptions, DecorationOptions, AnimationsOptions, InputOptions, BindsOptions, CursorOptions,
              MiscOptions, DwindleOptions, MasterOptions, MacOSOptions        // fields and defaults below, all Equatable, Sendable, init()
public struct ExecCommand: Equatable, Sendable { public var command: String; public var raw: Bool }
public struct EnvVar: Equatable, Sendable { public var name: String; public var value: String }
public struct Config: Equatable, Sendable {
    public var general: GeneralOptions; decoration: DecorationOptions; animationsOptions: AnimationsOptions; input: InputOptions
    public var bindsOptions: BindsOptions; cursor: CursorOptions; misc: MiscOptions; dwindle: DwindleOptions; master: MasterOptions; macos: MacOSOptions
    public var binds: [Bind]; windowRules: [WindowRule]; workspaceRules: [WorkspaceRule]
    public var beziers: [String: Bezier]; animations: AnimationTree
    public var execOnce: [ExecCommand]; exec: [ExecCommand]; execShutdown: [ExecCommand]
    public var environment: [EnvVar]; reservedAreas: [String: Edges]          // "" key means every monitor
    public var sourcedFiles: Set<String>
    public init()
}
public enum ConfigBuilder {
    public static func build(_ entries: [ConfigEntry]) -> (config: Config, diagnostics: [Diagnostic])
    public static func applyKeyword(_ key: String, _ value: String, to config: inout Config) -> String?   // hyprctl keyword; nil = ok
    public static func getOption(_ key: String, in config: Config) -> String?
}
```

Option fields (Hyprland key: Swift field = default):
- general: `border_size`: borderSize = 1; `gaps_in`: gapsIn = Edges(all: 5); `gaps_out`: gapsOut = Edges(all: 20); `float_gaps`: floatGaps = Edges(all: 0); `gaps_workspaces`: gapsWorkspaces = 0; `col.active_border`: activeBorder = white; `col.inactive_border`: inactiveBorder = 0xff444444; `layout`: layout = "dwindle" (allowed dwindle, master, monocle; "scrolling" gives "layout scrolling is not supported by HyprOSX"); `no_focus_fallback`: noFocusFallback = false.
- decoration: `rounding`: rounding = 0; `dim_inactive`: dimInactive = false; `dim_strength`: dimStrength = 0.5.
- animations: `enabled`: enabled = true; `workspace_wraparound`: workspaceWraparound = false.
- input: `follow_mouse`: followMouse = 1; `focus_on_close`: focusOnClose = 0.
- binds: `workspace_back_and_forth` = false; `allow_workspace_cycles` = false; `focus_preferred_method` = 0; `movefocus_cycles_fullscreen` = false; `window_direction_monitor_fallback` = true; `drag_threshold` = 0; `scroll_event_delay` = 300; `hide_special_on_workspace_change` = false.
- cursor: `no_warps` = false; `warp_on_change_workspace` = 0.
- misc: `disable_autoreload` = false; `focus_on_activate` = true; `close_special_on_empty` = true; `animate_manual_resizes` = false; `animate_mouse_windowdragging` = false; `size_limits_tiled` = false.
- dwindle: `pseudotile` = false; `force_split` = 0; `preserve_split` = false; `smart_split` = false; `smart_resizing` = true; `permanent_direction_override` = false; `special_scale_factor` = 1; `split_width_multiplier` = 1; `use_active_for_splits` = true; `default_split_ratio` = 1; `split_bias` = 0; `precise_mouse_move` = false.
- master: `allow_small_split` = false; `special_scale_factor` = 1; `mfact` = 0.55; `new_status` = "slave" (master, slave, inherit); `new_on_top` = false; `new_on_active` = "none" (none, before, after); `orientation` = "left" (left, right, top, bottom, center); `slave_count_for_center_master` = 2; `center_master_fallback` = "left" (left, right, top, bottom); `smart_resizing` = true; `drop_at_cursor` = true; `always_keep_position` = false; `focus_master_on_close` = false.
- macos: `unhide_hidden_apps` = false; `hide_parked_apps` = true; `animations_on_low_power` = false; `respect_reduce_motion` = true; `live_resize_max_latency` = 6.0; `border_radius` = -1; `ipc_exec` = false; `ipc_window_titles` = true.

Builder rules:
- A key that is in the option registry is set; a parse failure is the error "invalid value 'V' for KEY".
- Otherwise the last path component is checked against the keywords: `bind` plus flag letters, `unbind`, `submap`, `bezier`, `animation`, `windowrule`, `windowrulev2`, `workspace`, `monitor`, `exec`, `exec-once`, `exec-shutdown`, `execr`, `execr-once`, `env`; accepted silently: `envd`, `plugin`, `gesture`, `device`, `permission`, `layerrule`, `monitorv2`.
- Block entries (`windowrule:...` with a block id) form one block rule, parsed with `WindowRuleParser.parseBlock` at the position of the block's first entry.
- Otherwise a known-but-ignored Hyprland option is skipped (exact names and prefixes listed in the code), a top-level key without `:` is ignored, and anything else is the error "config option KEY does not exist."
- `submap = NAME` sets the current submap for later binds; `submap = reset` returns to the default; `submap = NAME, TARGET` warns "submap auto-switch is not supported on macOS" and sets NAME.
- `unbind` removes earlier binds with the same modifiers and trigger in the current submap.
- `animation` lines are applied after all lines, so curves defined later still resolve.
- `monitor = NAME, addreserved, T, B, L, R` stores `Edges(top: T, right: R, bottom: B, left: L)` under NAME; other monitor lines are accepted.
- `env = NAME,VALUE` splits at the first comma.
- `exec` and `execr` go to `exec`, `exec-once` and `execr-once` to `execOnce`, `exec-shutdown` to `execShutdown`; `raw` is true for the `execr` forms.
- `sourcedFiles` is the set of files that produced entries.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/ConfigBuilderTests.swift`:

```swift
import Testing
@testable import HyprCore

private func build(_ text: String, files: [String: String] = [:]) -> (config: Config, diagnostics: [Diagnostic]) {
    let parser = HyprlangParser(environment: ["HOME": "/Users/me"], readFile: { files[$0] }, glob: { files[$0] == nil ? [] : [$0] })
    let parsed = parser.parse(text: text, path: "/cfg/hyprland.conf")
    let built = ConfigBuilder.build(parsed.entries)
    return (built.config, parsed.diagnostics + built.diagnostics)
}

@Suite struct ConfigBuilderTests {
    @Test func hyprlandExampleSubsetBuildsClean() {
        let r = build("""
        general {
            gaps_in = 5
            gaps_out = 20
            border_size = 2
            col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
            col.inactive_border = rgba(595959aa)
            resize_on_border = false
            allow_tearing = false
            layout = dwindle
        }
        decoration {
            rounding = 10
            rounding_power = 2
            active_opacity = 1.0
            shadow {
                enabled = true
                range = 4
            }
            blur {
                enabled = true
                size = 3
            }
        }
        animations {
            enabled = yes, please :)
            animation = windows, 1, 4.79, easeOutQuint
            bezier = easeOutQuint, 0.23, 1, 0.32, 1
        }
        input {
            kb_layout = us
            follow_mouse = 1
            touchpad {
                natural_scroll = false
            }
        }
        dwindle {
            pseudotile = true
            preserve_split = true
        }
        master {
            new_status = master
        }
        misc {
            force_default_wallpaper = -1
        }
        gesture = 3, horizontal, workspace
        device {
            name = epic-mouse-v1
            sensitivity = -0.5
        }
        """)
        #expect(r.diagnostics.isEmpty)
        #expect(r.config.general.borderSize == 2)
        #expect(r.config.general.activeBorder.angleDegrees == 45)
        #expect(r.config.dwindle.preserveSplit)
        #expect(r.config.master.newStatus == "master")
        #expect(r.config.animations.leaf("windowsIn").curve == "easeOutQuint")
    }

    @Test func unknownOptionIsAnErrorButTopLevelUnknownIsIgnored() {
        let r = build("general:gaps_inn = 4\nwhatever = 3")
        #expect(r.diagnostics.map(\.message) == ["config option general:gaps_inn does not exist."])
    }

    @Test func invalidValue() {
        #expect(build("general:border_size = big").diagnostics.first?.message == "invalid value 'big' for general:border_size")
        #expect(build("master:orientation = diagonal").diagnostics.first?.message == "invalid value 'diagonal' for master:orientation")
        #expect(build("general:layout = scrolling").diagnostics.first?.message == "layout scrolling is not supported by HyprOSX")
    }

    @Test func bindsSubmapsAndUnbind() {
        let r = build("""
        $mainMod = ALT
        bind = $mainMod, R, submap, resize
        submap = resize
        binde = , H, resizeactive, -50 0
        bind = , escape, submap, reset
        submap = reset
        bind = $mainMod, O, pseudo,
        unbind = ALT, O
        """)
        #expect(r.diagnostics.isEmpty)
        #expect(r.config.binds.map(\.submap) == ["", "resize", "resize"])
        #expect(r.config.binds.map(\.dispatcher) == ["submap", "resizeactive", "submap"])
    }

    @Test func rulesAllForms() {
        let r = build("""
        windowrule = float on, match:class .*
        windowrulev2 = float, class:^(pavucontrol)$
        windowrule {
            name = named
            match:class = kitty
            border_size = 4
        }
        workspace = w[tv1], gapsout:0, gapsin:0
        """)
        #expect(r.diagnostics.isEmpty)
        #expect(r.config.windowRules.count == 3)
        #expect(r.config.windowRules[2].name == "named")
        #expect(r.config.workspaceRules.count == 1)
    }

    @Test func monitorEnvExecAndSources() {
        let r = build("""
        monitor = , addreserved, 32, 0, 0, 0
        monitor = DP-1, 1920x1080@144, 0x0, 1
        env = PATH,/opt/homebrew/bin:/usr/bin
        exec-once = open -a Ghostty
        execr = echo hi
        exec-shutdown = echo bye
        source = /cfg/apps.conf
        """, files: ["/cfg/apps.conf": "windowrule = tile on, match:class Ghostty"])
        #expect(r.diagnostics.isEmpty)
        #expect(r.config.reservedAreas[""] == Edges(top: 32, right: 0, bottom: 0, left: 0))
        #expect(r.config.environment == [EnvVar(name: "PATH", value: "/opt/homebrew/bin:/usr/bin")])
        #expect(r.config.execOnce == [ExecCommand(command: "open -a Ghostty", raw: false)])
        #expect(r.config.exec == [ExecCommand(command: "echo hi", raw: true)])
        #expect(r.config.execShutdown.count == 1)
        #expect(r.config.sourcedFiles.contains("/cfg/apps.conf"))
    }

    @Test func macosCategory() {
        let r = build("macos {\n hide_parked_apps = false\n live_resize_max_latency = 8\n ipc_exec = true\n}")
        #expect(r.diagnostics.isEmpty)
        #expect(r.config.macos.hideParkedApps == false)
        #expect(r.config.macos.liveResizeMaxLatency == 8)
        #expect(r.config.macos.ipcExec)
    }

    @Test func keywordAndGetOption() {
        var c = Config()
        #expect(ConfigBuilder.applyKeyword("general:gaps_in", "3", to: &c) == nil)
        #expect(c.general.gapsIn == Edges(all: 3))
        #expect(ConfigBuilder.applyKeyword("bind", "ALT, X, exec, true", to: &c) == nil)
        #expect(c.binds.count == 1)
        #expect(ConfigBuilder.applyKeyword("general:nope", "1", to: &c) == "config option general:nope does not exist.")
        #expect(ConfigBuilder.getOption("general:gaps_in", in: c) == "3 3 3 3")
        #expect(ConfigBuilder.getOption("master:mfact", in: c) == "0.55")
        #expect(ConfigBuilder.getOption("general:layout", in: c) == "dwindle")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ConfigBuilderTests`
Expected: FAIL, "cannot find 'ConfigBuilder' in scope".

- [ ] **Step 3: Implement options**

`Sources/HyprCore/Config/Options.swift`:

```swift
import Foundation

public struct GeneralOptions: Equatable, Sendable {
    public var borderSize = 1
    public var gapsIn = Edges(all: 5)
    public var gapsOut = Edges(all: 20)
    public var floatGaps = Edges(all: 0)
    public var gapsWorkspaces = 0
    public var activeBorder = Gradient(Color(r: 1, g: 1, b: 1, a: 1))
    public var inactiveBorder = Gradient(Color(r: 68.0 / 255, g: 68.0 / 255, b: 68.0 / 255, a: 1))
    public var layout = "dwindle"
    public var noFocusFallback = false
    public init() {}
}

public struct DecorationOptions: Equatable, Sendable {
    public var rounding = 0
    public var dimInactive = false
    public var dimStrength = 0.5
    public init() {}
}

public struct AnimationsOptions: Equatable, Sendable {
    public var enabled = true
    public var workspaceWraparound = false
    public init() {}
}

public struct InputOptions: Equatable, Sendable {
    public var followMouse = 1
    public var focusOnClose = 0
    public init() {}
}

public struct BindsOptions: Equatable, Sendable {
    public var workspaceBackAndForth = false
    public var allowWorkspaceCycles = false
    public var focusPreferredMethod = 0
    public var movefocusCyclesFullscreen = false
    public var windowDirectionMonitorFallback = true
    public var dragThreshold = 0
    public var scrollEventDelay = 300
    public var hideSpecialOnWorkspaceChange = false
    public init() {}
}

public struct CursorOptions: Equatable, Sendable {
    public var noWarps = false
    public var warpOnChangeWorkspace = 0
    public init() {}
}

public struct MiscOptions: Equatable, Sendable {
    public var disableAutoreload = false
    public var focusOnActivate = true
    public var closeSpecialOnEmpty = true
    public var animateManualResizes = false
    public var animateMouseWindowdragging = false
    public var sizeLimitsTiled = false
    public init() {}
}

public struct DwindleOptions: Equatable, Sendable {
    public var pseudotile = false
    public var forceSplit = 0
    public var preserveSplit = false
    public var smartSplit = false
    public var smartResizing = true
    public var permanentDirectionOverride = false
    public var specialScaleFactor = 1.0
    public var splitWidthMultiplier = 1.0
    public var useActiveForSplits = true
    public var defaultSplitRatio = 1.0
    public var splitBias = 0
    public var preciseMouseMove = false
    public init() {}
}

public struct MasterOptions: Equatable, Sendable {
    public var allowSmallSplit = false
    public var specialScaleFactor = 1.0
    public var mfact = 0.55
    public var newStatus = "slave"
    public var newOnTop = false
    public var newOnActive = "none"
    public var orientation = "left"
    public var slaveCountForCenterMaster = 2
    public var centerMasterFallback = "left"
    public var smartResizing = true
    public var dropAtCursor = true
    public var alwaysKeepPosition = false
    public var focusMasterOnClose = false
    public init() {}
}

public struct MacOSOptions: Equatable, Sendable {
    public var unhideHiddenApps = false
    public var hideParkedApps = true
    public var animationsOnLowPower = false
    public var respectReduceMotion = true
    public var liveResizeMaxLatency = 6.0
    public var borderRadius = -1
    public var ipcExec = false
    public var ipcWindowTitles = true
    public init() {}
}

struct OptionSpec {
    let set: (inout Config, String) -> String?
    let get: (Config) -> String
}

enum OptionRegistry {
    static let specs: [String: OptionSpec] = {
        var s: [String: OptionSpec] = [:]
        func invalid(_ v: String, _ k: String) -> String { "invalid value '\(v)' for \(k)" }
        func int(_ k: String, _ p: WritableKeyPath<Config, Int>) {
            s[k] = OptionSpec(set: { c, v in guard let n = ConfigValue.int(v) else { return invalid(v, k) }; c[keyPath: p] = n; return nil },
                              get: { "\($0[keyPath: p])" })
        }
        func bool(_ k: String, _ p: WritableKeyPath<Config, Bool>) {
            s[k] = OptionSpec(set: { c, v in guard let b = ConfigValue.bool(v) else { return invalid(v, k) }; c[keyPath: p] = b; return nil },
                              get: { $0[keyPath: p] ? "true" : "false" })
        }
        func float(_ k: String, _ p: WritableKeyPath<Config, Double>) {
            s[k] = OptionSpec(set: { c, v in guard let d = ConfigValue.float(v) else { return invalid(v, k) }; c[keyPath: p] = d; return nil },
                              get: { String($0[keyPath: p]) })
        }
        func edges(_ k: String, _ p: WritableKeyPath<Config, Edges>) {
            s[k] = OptionSpec(set: { c, v in guard let e = ConfigValue.edges(v) else { return invalid(v, k) }; c[keyPath: p] = e; return nil },
                              get: { let e = $0[keyPath: p]; return [e.top, e.right, e.bottom, e.left].map { String(Int($0)) }.joined(separator: " ") })
        }
        func gradient(_ k: String, _ p: WritableKeyPath<Config, Gradient>) {
            s[k] = OptionSpec(set: { c, v in guard let g = ConfigValue.gradient(v) else { return invalid(v, k) }; c[keyPath: p] = g; return nil },
                              get: { g in g[keyPath: p].colors.map { c in
                                  String(format: "rgba(%02x%02x%02x%02x)", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255), Int(c.a * 255))
                              }.joined(separator: " ") + " \(Int(g[keyPath: p].angleDegrees))deg" })
        }
        func choice(_ k: String, _ p: WritableKeyPath<Config, String>, _ allowed: [String]) {
            s[k] = OptionSpec(set: { c, v in guard allowed.contains(v) else { return invalid(v, k) }; c[keyPath: p] = v; return nil },
                              get: { $0[keyPath: p] })
        }
        int("general:border_size", \.general.borderSize)
        edges("general:gaps_in", \.general.gapsIn)
        edges("general:gaps_out", \.general.gapsOut)
        edges("general:float_gaps", \.general.floatGaps)
        int("general:gaps_workspaces", \.general.gapsWorkspaces)
        gradient("general:col.active_border", \.general.activeBorder)
        gradient("general:col.inactive_border", \.general.inactiveBorder)
        s["general:layout"] = OptionSpec(set: { c, v in
            if v == "scrolling" { return "layout scrolling is not supported by HyprOSX" }
            guard ["dwindle", "master", "monocle"].contains(v) else { return invalid(v, "general:layout") }
            c.general.layout = v; return nil
        }, get: { $0.general.layout })
        bool("general:no_focus_fallback", \.general.noFocusFallback)
        int("decoration:rounding", \.decoration.rounding)
        bool("decoration:dim_inactive", \.decoration.dimInactive)
        float("decoration:dim_strength", \.decoration.dimStrength)
        bool("animations:enabled", \.animationsOptions.enabled)
        bool("animations:workspace_wraparound", \.animationsOptions.workspaceWraparound)
        int("input:follow_mouse", \.input.followMouse)
        int("input:focus_on_close", \.input.focusOnClose)
        bool("binds:workspace_back_and_forth", \.bindsOptions.workspaceBackAndForth)
        bool("binds:allow_workspace_cycles", \.bindsOptions.allowWorkspaceCycles)
        int("binds:focus_preferred_method", \.bindsOptions.focusPreferredMethod)
        bool("binds:movefocus_cycles_fullscreen", \.bindsOptions.movefocusCyclesFullscreen)
        bool("binds:window_direction_monitor_fallback", \.bindsOptions.windowDirectionMonitorFallback)
        int("binds:drag_threshold", \.bindsOptions.dragThreshold)
        int("binds:scroll_event_delay", \.bindsOptions.scrollEventDelay)
        bool("binds:hide_special_on_workspace_change", \.bindsOptions.hideSpecialOnWorkspaceChange)
        bool("cursor:no_warps", \.cursor.noWarps)
        int("cursor:warp_on_change_workspace", \.cursor.warpOnChangeWorkspace)
        bool("misc:disable_autoreload", \.misc.disableAutoreload)
        bool("misc:focus_on_activate", \.misc.focusOnActivate)
        bool("misc:close_special_on_empty", \.misc.closeSpecialOnEmpty)
        bool("misc:animate_manual_resizes", \.misc.animateManualResizes)
        bool("misc:animate_mouse_windowdragging", \.misc.animateMouseWindowdragging)
        bool("misc:size_limits_tiled", \.misc.sizeLimitsTiled)
        bool("dwindle:pseudotile", \.dwindle.pseudotile)
        int("dwindle:force_split", \.dwindle.forceSplit)
        bool("dwindle:preserve_split", \.dwindle.preserveSplit)
        bool("dwindle:smart_split", \.dwindle.smartSplit)
        bool("dwindle:smart_resizing", \.dwindle.smartResizing)
        bool("dwindle:permanent_direction_override", \.dwindle.permanentDirectionOverride)
        float("dwindle:special_scale_factor", \.dwindle.specialScaleFactor)
        float("dwindle:split_width_multiplier", \.dwindle.splitWidthMultiplier)
        bool("dwindle:use_active_for_splits", \.dwindle.useActiveForSplits)
        float("dwindle:default_split_ratio", \.dwindle.defaultSplitRatio)
        int("dwindle:split_bias", \.dwindle.splitBias)
        bool("dwindle:precise_mouse_move", \.dwindle.preciseMouseMove)
        bool("master:allow_small_split", \.master.allowSmallSplit)
        float("master:special_scale_factor", \.master.specialScaleFactor)
        float("master:mfact", \.master.mfact)
        choice("master:new_status", \.master.newStatus, ["master", "slave", "inherit"])
        bool("master:new_on_top", \.master.newOnTop)
        choice("master:new_on_active", \.master.newOnActive, ["none", "before", "after"])
        choice("master:orientation", \.master.orientation, ["left", "right", "top", "bottom", "center"])
        int("master:slave_count_for_center_master", \.master.slaveCountForCenterMaster)
        choice("master:center_master_fallback", \.master.centerMasterFallback, ["left", "right", "top", "bottom"])
        bool("master:smart_resizing", \.master.smartResizing)
        bool("master:drop_at_cursor", \.master.dropAtCursor)
        bool("master:always_keep_position", \.master.alwaysKeepPosition)
        bool("master:focus_master_on_close", \.master.focusMasterOnClose)
        bool("macos:unhide_hidden_apps", \.macos.unhideHiddenApps)
        bool("macos:hide_parked_apps", \.macos.hideParkedApps)
        bool("macos:animations_on_low_power", \.macos.animationsOnLowPower)
        bool("macos:respect_reduce_motion", \.macos.respectReduceMotion)
        float("macos:live_resize_max_latency", \.macos.liveResizeMaxLatency)
        int("macos:border_radius", \.macos.borderRadius)
        bool("macos:ipc_exec", \.macos.ipcExec)
        bool("macos:ipc_window_titles", \.macos.ipcWindowTitles)
        return s
    }()

    static let ignoredExact: Set<String> = [
        "general:col.nogroup_border", "general:col.nogroup_border_active", "general:resize_on_border",
        "general:extend_border_grab_area", "general:hover_icon_on_border", "general:allow_tearing", "general:resize_corner",
        "general:modal_parent_blocking", "general:locale",
        "decoration:rounding_power", "decoration:active_opacity", "decoration:inactive_opacity", "decoration:fullscreen_opacity",
        "decoration:dim_modal", "decoration:dim_special", "decoration:dim_around", "decoration:screen_shader",
        "decoration:border_part_of_window",
        "input:kb_model", "input:kb_layout", "input:kb_variant", "input:kb_options", "input:kb_rules", "input:kb_file",
        "input:numlock_by_default", "input:resolve_binds_by_sym", "input:repeat_rate", "input:repeat_delay", "input:sensitivity",
        "input:accel_profile", "input:force_no_accel", "input:rotation", "input:left_handed", "input:scroll_points",
        "input:scroll_method", "input:scroll_button", "input:scroll_button_lock", "input:scroll_factor", "input:natural_scroll",
        "input:follow_mouse_shrink", "input:follow_mouse_threshold", "input:mouse_refocus", "input:float_switch_override_focus",
        "input:special_fallthrough", "input:off_window_axis_events", "input:emulate_discrete_scroll",
        "binds:pass_mouse_when_bound", "binds:workspace_center_on", "binds:ignore_group_lock", "binds:movefocus_cycles_groupfirst",
        "binds:disable_keybind_grabbing", "binds:allow_pin_fullscreen",
        "cursor:invisible", "cursor:sync_gsettings_theme", "cursor:no_hardware_cursors", "cursor:no_break_fs_vrr",
        "cursor:min_refresh_rate", "cursor:hotspot_padding", "cursor:inactive_timeout", "cursor:persistent_warps",
        "cursor:warp_on_toggle_special", "cursor:default_monitor", "cursor:zoom_factor", "cursor:zoom_rigid",
        "cursor:zoom_detached_camera", "cursor:enable_hyprcursor", "cursor:hide_on_key_press", "cursor:hide_on_touch",
        "cursor:hide_on_tablet", "cursor:use_cpu_buffer", "cursor:warp_back_after_non_mouse_input", "cursor:zoom_disable_aa",
        "misc:disable_hyprland_logo", "misc:disable_splash_rendering", "misc:disable_scale_notification", "misc:col.splash",
        "misc:font_family", "misc:splash_font_family", "misc:force_default_wallpaper", "misc:vrr", "misc:mouse_move_enables_dpms",
        "misc:key_press_enables_dpms", "misc:name_vk_after_proc", "misc:always_follow_on_dnd", "misc:layers_hog_keyboard_focus",
        "misc:enable_swallow", "misc:swallow_regex", "misc:swallow_exception_regex", "misc:mouse_move_focuses_monitor",
        "misc:allow_session_lock_restore", "misc:session_lock_xray", "misc:background_color", "misc:on_focus_under_fullscreen",
        "misc:exit_window_retains_fullscreen", "misc:initial_workspace_tracking", "misc:middle_click_paste",
        "misc:render_unfocused_fps", "misc:disable_xdg_env_checks", "misc:disable_hyprland_qtutils_check",
        "misc:disable_hyprland_guiutils_check", "misc:lockdead_screen_delay", "misc:enable_anr_dialog", "misc:anr_missed_pings",
        "misc:disable_watchdog_warning", "misc:vfr", "misc:screencopy_force_8b", "misc:new_window_takes_over_fullscreen",
        "dwindle:single_window_aspect_ratio", "dwindle:single_window_aspect_ratio_tolerance", "master:center_ignores_reserved",
    ]

    static let ignoredPrefixes = [
        "general:snap:", "decoration:blur:", "decoration:shadow:", "decoration:glow:", "input:touchpad:", "input:touchdevice:",
        "input:tablet:", "input:virtualkeyboard:", "group:", "debug:", "render:", "opengl:", "ecosystem:", "xwayland:",
        "experimental:", "gestures:", "quirks:", "layout:", "plugin:", "device:", "monitorv2:", "scrolling:",
    ]

    static func isIgnored(_ key: String) -> Bool {
        ignoredExact.contains(key) || ignoredPrefixes.contains { key.hasPrefix($0) }
    }
}
```

- [ ] **Step 4: Implement the config and builder**

`Sources/HyprCore/Config/Config.swift`:

```swift
import Foundation

public struct ExecCommand: Equatable, Sendable {
    public var command: String
    public var raw: Bool
    public init(command: String, raw: Bool) { self.command = command; self.raw = raw }
}

public struct EnvVar: Equatable, Sendable {
    public var name: String
    public var value: String
    public init(name: String, value: String) { self.name = name; self.value = value }
}

public struct Config: Equatable, Sendable {
    public var general = GeneralOptions()
    public var decoration = DecorationOptions()
    public var animationsOptions = AnimationsOptions()
    public var input = InputOptions()
    public var bindsOptions = BindsOptions()
    public var cursor = CursorOptions()
    public var misc = MiscOptions()
    public var dwindle = DwindleOptions()
    public var master = MasterOptions()
    public var macos = MacOSOptions()
    public var binds: [Bind] = []
    public var windowRules: [WindowRule] = []
    public var workspaceRules: [WorkspaceRule] = []
    public var beziers: [String: Bezier] = Bezier.builtIns
    public var animations = AnimationTree()
    public var execOnce: [ExecCommand] = []
    public var exec: [ExecCommand] = []
    public var execShutdown: [ExecCommand] = []
    public var environment: [EnvVar] = []
    public var reservedAreas: [String: Edges] = [:]
    public var sourcedFiles: Set<String> = []
    public init() {}
}

public enum ConfigBuilder {
    static let acceptedKeywords: Set<String> = ["envd", "plugin", "gesture", "device", "permission", "layerrule", "monitorv2"]

    struct Builder {
        var config: Config
        var diagnostics: [Diagnostic] = []
        var submap = ""
        var animationLines: [(String, SourceLocation)] = []

        mutating func apply(key: String, value: String, location: SourceLocation) {
            if let spec = OptionRegistry.specs[key] {
                if let error = spec.set(&config, value) { diagnostics.append(Diagnostic(location, error)) }
                return
            }
            let name = key.split(separator: ":").last.map(String.init) ?? key
            if name.hasPrefix("bind"), name.dropFirst(4).allSatisfy({ BindFlags.letters[$0] != nil || !$0.isLetter }) {
                let r = BindParser.parse(keyword: name, value: value, submap: submap, location: location)
                if let b = r.bind { config.binds.append(b) }
                diagnostics += r.diagnostics
                return
            }
            switch name {
            case "unbind":
                guard let (mods, trigger) = BindParser.parseUnbind(value) else { diagnostics.append(Diagnostic(location, "invalid unbind '\(value)'")); return }
                config.binds.removeAll { $0.modifiers == mods && $0.trigger == trigger && $0.submap == submap }
            case "submap":
                let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count > 1 { diagnostics.append(Diagnostic(location, "submap auto-switch is not supported on macOS", isWarning: true)) }
                submap = parts.first == "reset" ? "" : (parts.first ?? "")
            case "bezier":
                guard let (n, curve) = Bezier.parse(value) else { diagnostics.append(Diagnostic(location, "invalid bezier '\(value)'")); return }
                config.beziers[n] = curve
            case "animation":
                animationLines.append((value, location))
            case "windowrule", "windowrulev2":
                let r = WindowRuleParser.parse(keyword: name, value: value, location: location)
                if let rule = r.rule { config.windowRules.append(rule) }
                diagnostics += r.diagnostics
            case "workspace":
                let r = WorkspaceRule.parse(value, location: location)
                if let rule = r.rule { config.workspaceRules.append(rule) }
                diagnostics += r.diagnostics
            case "monitor":
                let p = value.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                if p.count == 6, p[1] == "addreserved" {
                    let n = p[2...].compactMap(Double.init)
                    guard n.count == 4 else { diagnostics.append(Diagnostic(location, "invalid addreserved '\(value)'")); return }
                    config.reservedAreas[p[0]] = Edges(top: n[0], right: n[3], bottom: n[1], left: n[2])
                }
            case "exec", "execr":
                config.exec.append(ExecCommand(command: value, raw: name == "execr"))
            case "exec-once", "execr-once":
                config.execOnce.append(ExecCommand(command: value, raw: name == "execr-once"))
            case "exec-shutdown":
                config.execShutdown.append(ExecCommand(command: value, raw: false))
            case "env":
                guard let comma = value.firstIndex(of: ",") else { diagnostics.append(Diagnostic(location, "invalid env '\(value)'")); return }
                config.environment.append(EnvVar(name: value[..<comma].trimmingCharacters(in: .whitespaces),
                                                 value: value[value.index(after: comma)...].trimmingCharacters(in: .whitespaces)))
            default:
                if ConfigBuilder.acceptedKeywords.contains(name) || OptionRegistry.isIgnored(key) || !key.contains(":") { return }
                diagnostics.append(Diagnostic(location, "config option \(key) does not exist."))
            }
        }

        mutating func finishAnimations() {
            let curves = Set(config.beziers.keys)
            for (line, location) in animationLines {
                if let error = config.animations.apply(line, curves: curves) { diagnostics.append(Diagnostic(location, error)) }
            }
            animationLines = []
        }
    }

    public static func build(_ entries: [ConfigEntry]) -> (config: Config, diagnostics: [Diagnostic]) {
        var b = Builder(config: Config())
        var handledBlocks: Set<Int> = []
        for entry in entries {
            b.config.sourcedFiles.insert(entry.location.file)
            if entry.key.hasPrefix("windowrule:"), let block = entry.block {
                if handledBlocks.insert(block).inserted {
                    let fields = entries.filter { $0.block == block }.map { (key: String($0.key.dropFirst("windowrule:".count)), value: $0.value) }
                    let r = WindowRuleParser.parseBlock(fields, location: entry.location)
                    if let rule = r.rule { b.config.windowRules.append(rule) }
                    b.diagnostics += r.diagnostics
                }
                continue
            }
            b.apply(key: entry.key, value: entry.value, location: entry.location)
        }
        b.finishAnimations()
        return (b.config, b.diagnostics)
    }

    public static func applyKeyword(_ key: String, _ value: String, to config: inout Config) -> String? {
        var b = Builder(config: config)
        b.apply(key: key, value: value, location: SourceLocation(file: "hyprctl", line: 0))
        b.finishAnimations()
        if let error = b.diagnostics.first(where: { !$0.isWarning }) { return error.message }
        config = b.config
        return nil
    }

    public static func getOption(_ key: String, in config: Config) -> String? {
        OptionRegistry.specs[key]?.get(config)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter ConfigBuilderTests`
Expected: PASS. Then run `swift test` and expect every suite so far to pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/HyprCore/Config/Options.swift Sources/HyprCore/Config/Config.swift Tests/HyprCoreTests/ConfigBuilderTests.swift
git commit -m "feat: add option registry and config builder"
```

---
### Task 10: Layout protocol and window geometry

**Files:**
- Create: `Sources/HyprCore/Layout/TiledLayout.swift`, `Sources/HyprCore/Layout/WindowGeometry.swift`
- Test: `Tests/HyprCoreTests/WindowGeometryTests.swift`

**Interfaces:**
- Consumes: `Rect`, `Point`, `Size`, `Edges` (Task 1); `Direction` (Task 5); `DwindleOptions`, `MasterOptions` (Task 9).
- Produces:

```swift
public typealias WindowID = UInt32
public enum Corner: Equatable, Sendable { case none, topLeft, topRight, bottomLeft, bottomRight }
public struct LayoutContext: Sendable {
    public var workArea: Rect; public var focused: WindowID?; public var cursor: Point; public var focalPoint: Point?
    public var isFirstMap: Bool; public var dragging: Bool; public var dwindle: DwindleOptions; public var master: MasterOptions
    public init(workArea: Rect, focused: WindowID? = nil, cursor: Point = Point(x: 1e9, y: 1e9), focalPoint: Point? = nil,
                isFirstMap: Bool = true, dragging: Bool = false, dwindle: DwindleOptions = DwindleOptions(), master: MasterOptions = MasterOptions())
}
public enum LayoutMessageResult: Equatable, Sendable { case ok, focus(WindowID), error(String) }
public protocol TiledLayout: Sendable {
    var windowIDs: [WindowID] { get }
    mutating func insert(_ id: WindowID, _ ctx: LayoutContext)
    mutating func remove(_ id: WindowID)
    func tileBoxes(_ ctx: LayoutContext) -> [WindowID: Rect]
    mutating func resize(_ id: WindowID, by delta: Point, corner: Corner, _ ctx: LayoutContext)
    mutating func swap(_ a: WindowID, _ b: WindowID)
    mutating func moveWindow(_ id: WindowID, _ direction: Direction, _ ctx: LayoutContext) -> Bool   // false: focal point left the work area
    mutating func message(_ text: String, _ ctx: LayoutContext) -> LayoutMessageResult
    func nextFocusCandidate(near point: Point, _ ctx: LayoutContext) -> WindowID?
}
public enum WindowGeometry {
    public static func sticks(_ a: Double, _ b: Double) -> Bool                         // abs(a - b) < 2
    public static func frame(tile: Rect, workArea: Rect, gapsIn: Edges, borderSize: Double, pseudoSize: Size?) -> Rect
    public static func focalPoint(of box: Rect, _ direction: Direction) -> Point
}
```

`frame` is `hyprland-algorithms.md` section 1f; `focalPoint` is section 1g.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/WindowGeometryTests.swift`:

```swift
import Testing
@testable import HyprCore

@Suite struct WindowGeometryTests {
    let wa = Rect(x: 10, y: 42, width: 1492, height: 898)

    @Test func loneWindowGetsNoInnerGapButBorderInset() {
        let f = WindowGeometry.frame(tile: wa, workArea: wa, gapsIn: Edges(all: 4), borderSize: 2, pseudoSize: nil)
        #expect(f == Rect(x: 12, y: 44, width: 1488, height: 894))
    }

    @Test func neighboursAreTwoInnerGapsApart() {
        let left = Rect(x: 10, y: 42, width: 746, height: 898)
        let right = Rect(x: 756, y: 42, width: 746, height: 898)
        let a = WindowGeometry.frame(tile: left, workArea: wa, gapsIn: Edges(all: 4), borderSize: 0, pseudoSize: nil)
        let b = WindowGeometry.frame(tile: right, workArea: wa, gapsIn: Edges(all: 4), borderSize: 0, pseudoSize: nil)
        #expect(a == Rect(x: 10, y: 42, width: 742, height: 898))
        #expect(b == Rect(x: 760, y: 42, width: 742, height: 898))
        #expect(b.minX - a.maxX == 8)
    }

    @Test func pseudoIsCenteredAndShrunkToFit() {
        let small = WindowGeometry.frame(tile: wa, workArea: wa, gapsIn: .zero, borderSize: 0, pseudoSize: Size(width: 400, height: 300))
        #expect(small == Rect(x: 556, y: 341, width: 400, height: 300))
        let big = WindowGeometry.frame(tile: Rect(x: 0, y: 0, width: 400, height: 400), workArea: Rect(x: 0, y: 0, width: 400, height: 400),
                                       gapsIn: .zero, borderSize: 0, pseudoSize: Size(width: 800, height: 400))
        #expect(big == Rect(x: 0, y: 100, width: 400, height: 200))
    }

    @Test func focalPoints() {
        let b = Rect(x: 100, y: 100, width: 200, height: 100)
        #expect(WindowGeometry.focalPoint(of: b, .left) == Point(x: 99, y: 150))
        #expect(WindowGeometry.focalPoint(of: b, .right) == Point(x: 301, y: 150))
        #expect(WindowGeometry.focalPoint(of: b, .up) == Point(x: 200, y: 99))
        #expect(WindowGeometry.focalPoint(of: b, .down) == Point(x: 200, y: 201))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WindowGeometryTests`
Expected: FAIL, "cannot find 'WindowGeometry' in scope".

- [ ] **Step 3: Implement the protocol and geometry**

`Sources/HyprCore/Layout/TiledLayout.swift`:

```swift
import Foundation

public typealias WindowID = UInt32

public enum Corner: Equatable, Sendable { case none, topLeft, topRight, bottomLeft, bottomRight }

public struct LayoutContext: Sendable {
    public var workArea: Rect
    public var focused: WindowID?
    public var cursor: Point
    public var focalPoint: Point?
    public var isFirstMap: Bool
    public var dragging: Bool
    public var dwindle: DwindleOptions
    public var master: MasterOptions
    public init(workArea: Rect, focused: WindowID? = nil, cursor: Point = Point(x: 1e9, y: 1e9), focalPoint: Point? = nil,
                isFirstMap: Bool = true, dragging: Bool = false, dwindle: DwindleOptions = DwindleOptions(), master: MasterOptions = MasterOptions()) {
        self.workArea = workArea; self.focused = focused; self.cursor = cursor; self.focalPoint = focalPoint
        self.isFirstMap = isFirstMap; self.dragging = dragging; self.dwindle = dwindle; self.master = master
    }
}

public enum LayoutMessageResult: Equatable, Sendable { case ok, focus(WindowID), error(String) }

public protocol TiledLayout: Sendable {
    var windowIDs: [WindowID] { get }
    mutating func insert(_ id: WindowID, _ ctx: LayoutContext)
    mutating func remove(_ id: WindowID)
    func tileBoxes(_ ctx: LayoutContext) -> [WindowID: Rect]
    mutating func resize(_ id: WindowID, by delta: Point, corner: Corner, _ ctx: LayoutContext)
    mutating func swap(_ a: WindowID, _ b: WindowID)
    mutating func moveWindow(_ id: WindowID, _ direction: Direction, _ ctx: LayoutContext) -> Bool
    mutating func message(_ text: String, _ ctx: LayoutContext) -> LayoutMessageResult
    func nextFocusCandidate(near point: Point, _ ctx: LayoutContext) -> WindowID?
}

func clampRatio(_ v: Double) -> Double { min(max(v, 0.1), 1.9) }
```

`Sources/HyprCore/Layout/WindowGeometry.swift`:

```swift
import Foundation

public enum WindowGeometry {
    public static func sticks(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 2 }

    public static func frame(tile: Rect, workArea: Rect, gapsIn: Edges, borderSize: Double, pseudoSize: Size?) -> Rect {
        let box = tile.rounded()
        let l = sticks(box.minX, workArea.minX), r = sticks(box.maxX, workArea.maxX)
        let t = sticks(box.minY, workArea.minY), b = sticks(box.maxY, workArea.maxY)
        let offL = l ? 0 : gapsIn.left, offT = t ? 0 : gapsIn.top
        let offR = r ? 0 : gapsIn.right, offB = b ? 0 : gapsIn.bottom
        var pos = Point(x: box.x + offL, y: box.y + offT)
        var size = Size(width: box.width - offL - offR, height: box.height - offT - offB)
        if let pseudo = pseudoSize {
            var scale = 1.0
            if pseudo.width > size.width || pseudo.height > size.height {
                if pseudo.width > size.width { scale = size.width / pseudo.width }
                if pseudo.height * scale > size.height { scale = size.height / pseudo.height }
            }
            let fitted = Size(width: pseudo.width * scale, height: pseudo.height * scale)
            pos = Point(x: pos.x + (size.width - fitted.width) / 2, y: pos.y + (size.height - fitted.height) / 2)
            size = fitted
        }
        return Rect(x: pos.x + borderSize, y: pos.y + borderSize,
                    width: max(1, size.width - 2 * borderSize), height: max(1, size.height - 2 * borderSize)).rounded()
    }

    public static func focalPoint(of box: Rect, _ direction: Direction) -> Point {
        switch direction {
        case .up: return Point(x: box.x + box.width / 2, y: box.y - 1)
        case .down: return Point(x: box.x + box.width / 2, y: box.maxY + 1)
        case .left: return Point(x: box.x - 1, y: box.y + box.height / 2)
        case .right: return Point(x: box.maxX + 1, y: box.y + box.height / 2)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter WindowGeometryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/HyprCore/Layout/TiledLayout.swift Sources/HyprCore/Layout/WindowGeometry.swift Tests/HyprCoreTests/WindowGeometryTests.swift
git commit -m "feat: add tiled layout protocol and window geometry"
```

---

### Task 11: Dwindle layout

**Files:**
- Create: `Sources/HyprCore/Layout/Dwindle.swift`
- Test: `Tests/HyprCoreTests/DwindleTests.swift`

**Interfaces:**
- Consumes: Task 10 types, `DwindleOptions` (Task 9), `Direction` (Task 5).
- Produces: `public struct DwindleLayout: TiledLayout, Equatable, Codable` with `public init()`.

Port of `hyprland-algorithms.md` section 1 with two deliberate choices: (a) the resize edge test compares tile boxes against `ctx.workArea` (the same space as the boxes; upstream compares against a box that includes `gaps_out`, which makes its edge test miss), and (b) a split created by a preselect or a directional move stores `forced = true`, so its direction stays even without `preserve_split`.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/DwindleTests.swift`:

```swift
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
        #expect(d.moveWindow(2, .left, ctx(2)))
        #expect(d.windowIDs == [2, 1])
        #expect(!d.moveWindow(2, .left, ctx(2)))
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
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DwindleTests`
Expected: FAIL, "cannot find 'DwindleLayout' in scope".

- [ ] **Step 3: Implement dwindle**

`Sources/HyprCore/Layout/Dwindle.swift`:

```swift
import Foundation

public struct DwindleLayout: TiledLayout, Equatable, Codable, Sendable {
    struct Node: Equatable, Codable, Sendable {
        var parent: Int?
        var children: [Int] = []
        var window: WindowID?
        var splitTop = false
        var ratio = 1.0
        var forced = false
    }

    var nodes: [Int: Node] = [:]
    var root: Int?
    var nextID = 1
    var overrideDirection: Direction?

    public init() {}

    public var windowIDs: [WindowID] { leaves(from: root).compactMap { nodes[$0]?.window } }

    func leaves(from id: Int?) -> [Int] {
        guard let id, let n = nodes[id] else { return [] }
        return n.children.isEmpty ? [id] : n.children.flatMap { leaves(from: $0) }
    }

    func leaf(of window: WindowID) -> Int? { nodes.first { $0.value.window == window }?.key }

    mutating func make(_ node: Node) -> Int {
        let id = nextID
        nextID += 1
        nodes[id] = node
        return id
    }

    mutating func replace(_ old: Int, with new: Int, in parent: Int?) {
        if let parent, var p = nodes[parent] {
            p.children = p.children.map { $0 == old ? new : $0 }
            nodes[parent] = p
        } else {
            root = new
        }
    }

    func effectiveSplitTop(_ n: Node, _ box: Rect, _ o: DwindleOptions) -> Bool {
        if n.forced || o.preserveSplit || o.smartSplit || o.preciseMouseMove { return n.splitTop }
        return box.height * o.splitWidthMultiplier > box.width
    }

    func nodeBoxes(_ ctx: LayoutContext) -> [Int: Rect] {
        var out: [Int: Rect] = [:]
        func walk(_ id: Int, _ box: Rect) {
            out[id] = box
            guard let n = nodes[id], n.children.count == 2 else { return }
            if !effectiveSplitTop(n, box, ctx.dwindle) {
                let first = box.width / 2 * n.ratio
                walk(n.children[0], Rect(x: box.x, y: box.y, width: max(0, first), height: box.height))
                walk(n.children[1], Rect(x: box.x + first, y: box.y, width: max(0, box.width - first), height: box.height))
            } else {
                let first = box.height / 2 * n.ratio
                walk(n.children[0], Rect(x: box.x, y: box.y, width: box.width, height: max(0, first)))
                walk(n.children[1], Rect(x: box.x, y: box.y + first, width: box.width, height: max(0, box.height - first)))
            }
        }
        if let root { walk(root, ctx.workArea) }
        return out
    }

    public func tileBoxes(_ ctx: LayoutContext) -> [WindowID: Rect] {
        var out: [WindowID: Rect] = [:]
        for (id, box) in nodeBoxes(ctx) { if let w = nodes[id]?.window { out[w] = box } }
        return out
    }

    func closestLeaf(to point: Point, _ boxes: [Int: Rect], skipping: Int? = nil) -> Int? {
        var best: (Int, Double)?
        for id in leaves(from: root) where id != skipping {
            guard let box = boxes[id] else { continue }
            let d = box.distanceSquared(to: point)
            if best == nil || d < best!.1 { best = (id, d) }
        }
        return best?.0
    }

    public mutating func insert(_ id: WindowID, _ ctx: LayoutContext) {
        guard leaf(of: id) == nil else { return }
        let o = ctx.dwindle
        let boxes = nodeBoxes(ctx)
        let mouse = ctx.focalPoint ?? ctx.cursor
        var opening: Int?
        if let focal = ctx.focalPoint {
            opening = closestLeaf(to: focal, boxes)
        } else if o.useActiveForSplits {
            if let f = ctx.focused { opening = leaf(of: f) }
            if opening == nil { opening = closestLeaf(to: mouse, boxes) }
        } else {
            opening = leaves(from: root).first { boxes[$0]?.contains(mouse) == true } ?? closestLeaf(to: mouse, boxes)
        }
        if opening == nil { opening = leaves(from: root).first }
        let newLeaf = make(Node(window: id))
        guard let target = opening, let box = boxes[target] else { root = newLeaf; return }

        let grandparent = nodes[target]?.parent
        var parent = Node(parent: grandparent)
        parent.ratio = clampRatio(o.defaultSplitRatio)
        let sideBySide = box.width > box.height * o.splitWidthMultiplier
        parent.splitTop = !sideBySide
        var newFirst: Bool
        if let dir = overrideDirection {
            parent.splitTop = dir == .up || dir == .down
            parent.forced = true
            newFirst = dir == .up || dir == .left
            if !o.permanentDirectionOverride { overrideDirection = nil }
        } else if o.smartSplit || (o.preciseMouseMove && ctx.dragging) {
            let delta = mouse - box.center
            let slope = delta.y / delta.x
            if abs(slope) < box.height / box.width {
                parent.splitTop = false
                newFirst = delta.x <= 0
            } else {
                parent.splitTop = true
                newFirst = delta.y <= 0
            }
        } else if o.forceSplit == 0 || ctx.focalPoint != nil || ctx.dragging {
            newFirst = (sideBySide && mouse.x < box.x + box.width / 2) || (!sideBySide && mouse.y < box.y + box.height / 2)
        } else {
            newFirst = o.forceSplit == 1
        }
        if o.splitBias == 1 && newFirst { parent.ratio = 2 - parent.ratio }
        parent.children = newFirst ? [newLeaf, target] : [target, newLeaf]
        let parentID = make(parent)
        nodes[target]?.parent = parentID
        nodes[newLeaf]?.parent = parentID
        replace(target, with: parentID, in: grandparent)
    }

    public mutating func remove(_ id: WindowID) {
        guard let l = leaf(of: id) else { return }
        guard let p = nodes[l]?.parent, let parent = nodes[p] else {
            nodes[l] = nil
            root = nil
            return
        }
        guard let sibling = parent.children.first(where: { $0 != l }) else { return }
        nodes[sibling]?.parent = parent.parent
        replace(p, with: sibling, in: parent.parent)
        nodes[l] = nil
        nodes[p] = nil
    }

    public mutating func swap(_ a: WindowID, _ b: WindowID) {
        guard let la = leaf(of: a), let lb = leaf(of: b) else { return }
        nodes[la]?.window = b
        nodes[lb]?.window = a
    }

    public mutating func resize(_ id: WindowID, by delta: Point, corner: Corner, _ ctx: LayoutContext) {
        guard let l = leaf(of: id) else { return }
        let boxes = nodeBoxes(ctx)
        guard let box = boxes[l] else { return }
        let wa = ctx.workArea
        let dl = WindowGeometry.sticks(box.minX, wa.minX), dr = WindowGeometry.sticks(box.maxX, wa.maxX)
        let dt = WindowGeometry.sticks(box.minY, wa.minY), db = WindowGeometry.sticks(box.maxY, wa.maxY)
        var allowed = delta
        if dl && dr { allowed.x = 0 }
        if dt && db { allowed.y = 0 }
        if ctx.dwindle.smartResizing {
            smartResize(l, allowed, corner, dl: dl, dr: dr, dt: dt, db: db, boxes, ctx)
        } else {
            plainResize(l, allowed, boxes, ctx)
        }
    }

    mutating func smartResize(_ l: Int, _ allowed: Point, _ corner: Corner, dl: Bool, dr: Bool, dt: Bool, db: Bool, _ boxes: [Int: Rect], _ ctx: LayoutContext) {
        let none = corner == .none
        let left = corner == .topLeft || corner == .bottomLeft || dr
        let right = corner == .topRight || corner == .bottomRight || dl
        let top = corner == .topLeft || corner == .topRight || db
        let bottom = corner == .bottomLeft || corner == .bottomRight || dt
        var vOuter: Int?, vInner: Int?, hOuter: Int?, hInner: Int?
        var cur = l
        while let p = nodes[cur]?.parent, let pn = nodes[p], let pbox = boxes[p] {
            let splitTop = effectiveSplitTop(pn, pbox, ctx.dwindle)
            if vOuter == nil && splitTop && (none || (top && pn.children[1] == cur) || (bottom && pn.children[0] == cur)) { vOuter = cur }
            else if vOuter == nil && vInner == nil && splitTop { vInner = cur }
            else if hOuter == nil && !splitTop && (none || (left && pn.children[1] == cur) || (right && pn.children[0] == cur)) { hOuter = cur }
            else if hOuter == nil && hInner == nil && !splitTop { hInner = cur }
            if vOuter != nil && hOuter != nil { break }
            cur = p
        }
        func apply(outer: Int?, inner: Int?, amount: Double, extent: (Rect) -> Double) {
            guard let outer, let op = nodes[outer]?.parent, let obox = boxes[op], extent(obox) > 0 else { return }
            nodes[op]?.ratio = clampRatio((nodes[op]?.ratio ?? 1) + amount * 2 / extent(obox))
            guard let inner, let ip = nodes[inner]?.parent, let ibox = boxes[inner] else { return }
            let original = extent(ibox)
            guard let newParentBox = nodeBoxes(ctx)[ip], extent(newParentBox) > 0 else { return }
            let pe = extent(newParentBox)
            nodes[ip]?.ratio = nodes[ip]?.children[0] == inner
                ? clampRatio((original - amount) / pe * 2)
                : clampRatio(2 - (original + amount) / pe * 2)
        }
        apply(outer: hOuter, inner: hInner, amount: allowed.x, extent: { $0.width })
        apply(outer: vOuter, inner: vInner, amount: allowed.y, extent: { $0.height })
    }

    mutating func plainResize(_ l: Int, _ allowed: Point, _ boxes: [Int: Rect], _ ctx: LayoutContext) {
        guard let p = nodes[l]?.parent, let pn = nodes[p], let pbox = boxes[p] else { return }
        let parentSideBySide = !effectiveSplitTop(pn, pbox, ctx.dwindle)
        var other: Int?
        var cur = p
        while let up = nodes[cur]?.parent, let un = nodes[up], let ubox = boxes[up] {
            if !effectiveSplitTop(un, ubox, ctx.dwindle) != parentSideBySide { other = up; break }
            cur = up
        }
        func bump(_ id: Int, _ amount: Double, _ extent: Double) {
            guard extent > 0 else { return }
            nodes[id]?.ratio = clampRatio((nodes[id]?.ratio ?? 1) + amount * 2 / extent)
        }
        guard let other, let obox = boxes[other] else {
            if parentSideBySide { bump(p, allowed.x, pbox.width) } else { bump(p, allowed.y, pbox.height) }
            return
        }
        let side = parentSideBySide ? p : other
        let stacked = parentSideBySide ? other : p
        bump(side, allowed.x, (parentSideBySide ? pbox : obox).width)
        bump(stacked, allowed.y, (parentSideBySide ? obox : pbox).height)
    }

    public mutating func moveWindow(_ id: WindowID, _ direction: Direction, _ ctx: LayoutContext) -> Bool {
        guard let l = leaf(of: id) else { return false }
        let boxes = nodeBoxes(ctx)
        guard let box = boxes[l] else { return false }
        let focal = WindowGeometry.focalPoint(of: box, direction)
        guard ctx.workArea.contains(focal) else { return false }
        if let p = nodes[l]?.parent, let pn = nodes[p], let pbox = boxes[p] {
            let splitTop = effectiveSplitTop(pn, pbox, ctx.dwindle)
            let isFirst = pn.children[0] == l
            let siblingIsLeaf = nodes[pn.children[isFirst ? 1 : 0]]?.children.isEmpty == true
            let lands = (direction == .up && splitTop && !isFirst) || (direction == .down && splitTop && isFirst)
                || (direction == .left && !splitTop && !isFirst) || (direction == .right && !splitTop && isFirst)
            if lands && siblingIsLeaf { overrideDirection = direction }
        }
        remove(id)
        var c = ctx
        c.focalPoint = focal
        c.focused = nil
        insert(id, c)
        return true
    }

    public mutating func message(_ text: String, _ ctx: LayoutContext) -> LayoutMessageResult {
        let words = text.split(separator: " ").map(String.init)
        guard let command = words.first else { return .error("empty layout message") }
        if command == "preselect" {
            overrideDirection = words.count > 1 ? Direction.parse(words[1]) : nil
            return .ok
        }
        guard let focused = ctx.focused, let l = leaf(of: focused) else { return .error("no focused tiled window") }
        let boxes = nodeBoxes(ctx)
        switch command {
        case "togglesplit":
            guard let p = nodes[l]?.parent, let pn = nodes[p], let pbox = boxes[p] else { return .error("window has no split") }
            nodes[p]?.splitTop = !effectiveSplitTop(pn, pbox, ctx.dwindle)
            return .ok
        case "swapsplit":
            guard let p = nodes[l]?.parent else { return .error("window has no split") }
            nodes[p]?.children.reverse()
            return .ok
        case "rotatesplit":
            guard let p = nodes[l]?.parent, let pn = nodes[p], let pbox = boxes[p] else { return .error("window has no split") }
            let angle = words.count > 1 ? (Int(words[1]) ?? 90) : 90
            let n = ((angle / 90 % 4) + 4) % 4
            let splitTop = effectiveSplitTop(pn, pbox, ctx.dwindle)
            var shouldSwap = false
            switch n {
            case 1: shouldSwap = splitTop; nodes[p]?.splitTop = !splitTop; nodes[p]?.forced = true
            case 2: shouldSwap = true
            case 3: shouldSwap = !splitTop; nodes[p]?.splitTop = !splitTop; nodes[p]?.forced = true
            default: break
            }
            if shouldSwap { nodes[p]?.children.reverse() }
            return .ok
        case "splitratio":
            guard let p = nodes[l]?.parent else { return .error("window has no split") }
            let exact = words.contains("exact")
            guard let value = words.dropFirst().first(where: { $0 != "exact" }).flatMap(Double.init) else { return .error("invalid splitratio") }
            nodes[p]?.ratio = clampRatio(exact ? value : (nodes[p]?.ratio ?? 1) + value)
            return .ok
        case "movetoroot":
            return moveToRoot(l, stable: !words.contains("unstable"))
        default:
            return .error("unknown dwindle layout message '\(command)'")
        }
    }

    mutating func moveToRoot(_ l: Int, stable: Bool) -> LayoutMessageResult {
        guard let root, let p = nodes[l]?.parent, p != root else { return .error("window is already at the root") }
        var ancestor = l
        while let up = nodes[ancestor]?.parent, up != root { ancestor = up }
        guard let rootNode = nodes[root], let other = rootNode.children.first(where: { $0 != ancestor }) else { return .error("no root split") }
        guard let lp = nodes[l]?.parent else { return .error("no parent") }
        nodes[lp]?.children = nodes[lp]!.children.map { $0 == l ? other : $0 }
        nodes[root]?.children = rootNode.children.map { $0 == other ? l : $0 }
        nodes[other]?.parent = lp
        nodes[l]?.parent = root
        if stable { nodes[root]?.children.reverse() }
        return .ok
    }

    public func nextFocusCandidate(near point: Point, _ ctx: LayoutContext) -> WindowID? {
        closestLeaf(to: point, nodeBoxes(ctx)).flatMap { nodes[$0]?.window }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DwindleTests`
Expected: PASS. The expected boxes follow `hyprland-algorithms.md` sections 1b to 1g exactly (including the square-box rule and `resizeactive` moving the split line); if a test fails, fix the code, not the test.

- [ ] **Step 5: Commit**

```bash
git add Sources/HyprCore/Layout/Dwindle.swift Tests/HyprCoreTests/DwindleTests.swift
git commit -m "feat: port the Hyprland dwindle layout"
```

---
### Task 12: Master and monocle layouts

**Files:**
- Create: `Sources/HyprCore/Layout/Master.swift`, `Sources/HyprCore/Layout/Monocle.swift`
- Test: `Tests/HyprCoreTests/MasterMonocleTests.swift`

**Interfaces:**
- Consumes: Task 10 types, `MasterOptions` (Task 9).
- Produces: `public struct MasterLayout: TiledLayout, Equatable, Codable` and `public struct MonocleLayout: TiledLayout, Equatable, Codable`, both with `public init()`. `MonocleLayout` also has `public func neighbor(of id: WindowID, forward: Bool) -> WindowID?` (wraps around).

Port of `hyprland-algorithms.md` section 2 with these simplifications: `rollnext` makes the first slave a master and moves the old master to the end of the list (`rollprev`: the last slave becomes master and the old master moves to the front); a resize along the master axis changes every master's `percMaster` by `dx / W` (left), `-dx / W` (right), `dy / H` (top), `-dy / H` (bottom) or `dx / W` (center), clamped to 0.05...0.95; a resize along the stack axis changes the node's `percSize` by `d / (extent / nodesInItsColumn)`, clamped to 0.05...1.95, in both smart and plain modes (smart renormalization then shares the change). `moveWindow` swaps with the window whose tile box contains the focal point, or returns false. The layout keeps `allowSmallSplit` from the last context it saw, because `remove` has no context.

Monocle: every tiled window gets the whole work area; insert appends after the focused window (or at the end); `moveWindow` left/up swaps with the previous window, right/down with the next (false at the ends); `message("cyclenext")` and `message("cycleprev")` return `.focus` of the neighbor; `nextFocusCandidate` returns the last window.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/MasterMonocleTests.swift`:

```swift
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
        #expect(m.moveWindow(3, .left, mctx(3)))
        #expect(m.tileBoxes(mctx())[3] == Rect(x: 0, y: 0, width: 550, height: 600))
        #expect(!m.moveWindow(3, .left, mctx(3)))
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
        #expect(m.moveWindow(3, .right, LayoutContext(workArea: area)))
        #expect(m.windowIDs == [1, 2, 3])
        #expect(!m.moveWindow(3, .right, LayoutContext(workArea: area)))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter MasterMonocleTests`
Expected: FAIL, "cannot find 'MasterLayout' in scope".

- [ ] **Step 3: Implement the master layout**

`Sources/HyprCore/Layout/Master.swift`:

```swift
import Foundation

public struct MasterLayout: TiledLayout, Equatable, Codable, Sendable {
    struct Node: Equatable, Codable, Sendable {
        var window: WindowID
        var isMaster: Bool
        var percMaster: Double
        var percSize: Double
    }

    var nodes: [Node] = []
    var orientationOverride: String?
    var previousFocus: WindowID?
    var allowSmallSplit = false

    static let orientations = ["left", "top", "right", "bottom", "center"]

    public init() {}

    public var windowIDs: [WindowID] { nodes.map(\.window) }

    func index(of id: WindowID?) -> Int? { id.flatMap { w in nodes.firstIndex { $0.window == w } } }

    func orientation(_ ctx: LayoutContext) -> String { orientationOverride ?? ctx.master.orientation }

    static func distribute(_ group: [Node], total: Double, smart: Bool) -> [Double] {
        guard !group.isEmpty else { return [] }
        if smart {
            let avg = total / Double(group.count)
            let acc = group.reduce(0) { $0 + avg * $1.percSize }
            return group.map { acc > 0 ? avg * $0.percSize * total / acc : avg }
        }
        var left = total
        var sizes: [Double] = []
        for (i, n) in group.enumerated() {
            let remaining = group.count - i
            var s = remaining > 1 ? left / Double(remaining) * n.percSize : left
            if remaining > 1 && s > left * 0.9 { s = left * 0.9 }
            sizes.append(s)
            left -= s
        }
        return sizes
    }

    public func tileBoxes(_ ctx: LayoutContext) -> [WindowID: Rect] {
        guard !nodes.isEmpty else { return [:] }
        let wa = ctx.workArea
        let W = wa.width, H = wa.height
        let masters = nodes.filter(\.isMaster)
        let slaves = nodes.filter { !$0.isMaster }
        let smart = ctx.master.smartResizing
        let stored = orientation(ctx)
        var orient = stored
        var centerMaster = false
        if orient == "center" {
            if slaves.count >= ctx.master.slaveCountForCenterMaster { centerMaster = true } else { orient = ctx.master.centerMasterFallback }
        }
        var out: [WindowID: Rect] = [:]
        if nodes.count == 1 && !centerMaster {
            let n = nodes[0]
            guard ctx.master.alwaysKeepPosition else { out[n.window] = wa; return out }
            let w = W * n.percMaster
            let x = stored == "right" ? W - w : (stored == "center" ? (W - w) / 2 : 0)
            out[n.window] = Rect(x: wa.x + x, y: wa.y, width: w, height: H)
            return out
        }
        let perc = masters.first?.percMaster ?? ctx.master.mfact
        var masterW = W, masterH = H
        if orient == "top" || orient == "bottom" {
            masterH = slaves.isEmpty ? H : H * perc
            let y = orient == "bottom" ? H - masterH : 0
            var x = 0.0
            for (n, w) in zip(masters, MasterLayout.distribute(masters, total: W, smart: smart)) {
                out[n.window] = Rect(x: wa.x + x, y: wa.y + y, width: w, height: masterH)
                x += w
            }
        } else {
            masterW = (!slaves.isEmpty || centerMaster) ? W * perc : W
            let x = orient == "right" ? W - masterW : (centerMaster ? (W - masterW) / 2 : 0)
            var y = 0.0
            for (n, h) in zip(masters, MasterLayout.distribute(masters, total: H, smart: smart)) {
                out[n.window] = Rect(x: wa.x + x, y: wa.y + y, width: masterW, height: h)
                y += h
            }
        }
        guard !slaves.isEmpty else { return out }
        switch orient {
        case "top", "bottom":
            let h = H - masterH
            let y = orient == "top" ? masterH : 0
            var x = 0.0
            for (n, w) in zip(slaves, MasterLayout.distribute(slaves, total: W, smart: smart)) {
                out[n.window] = Rect(x: wa.x + x, y: wa.y + y, width: w, height: h)
                x += w
            }
        case _ where centerMaster:
            let colW = (W - masterW) / 2
            var onRight = ctx.master.centerMasterFallback == "right"
            var left: [Node] = [], right: [Node] = []
            for n in slaves { if onRight { right.append(n) } else { left.append(n) }; onRight.toggle() }
            for (column, x) in [(left, 0.0), (right, colW + masterW)] {
                var y = 0.0
                for (n, h) in zip(column, MasterLayout.distribute(column, total: H, smart: smart)) {
                    out[n.window] = Rect(x: wa.x + x, y: wa.y + y, width: colW, height: h)
                    y += h
                }
            }
        default:
            let w = W - masterW
            let x = orient == "left" ? masterW : 0
            var y = 0.0
            for (n, h) in zip(slaves, MasterLayout.distribute(slaves, total: H, smart: smart)) {
                out[n.window] = Rect(x: wa.x + x, y: wa.y + y, width: w, height: h)
                y += h
            }
        }
        return out
    }

    public mutating func insert(_ id: WindowID, _ ctx: LayoutContext) {
        guard index(of: id) == nil else { return }
        let o = ctx.master
        allowSmallSplit = o.allowSmallSplit
        let focusedIndex = index(of: ctx.focused)
        let opening = focusedIndex.map { nodes[$0] } ?? nodes.first(where: \.isMaster)
        let newIsMaster = !ctx.dragging && o.newStatus == "master"
        let count = nodes.count + 1
        let becomesMaster = newIsMaster || count == 1
            || (count > 2 && !ctx.isFirstMap && opening?.isMaster == true)
            || (o.newStatus == "inherit" && opening?.isMaster == true && !ctx.dragging)
        var at = o.newOnTop ? 0 : nodes.count
        if o.newOnActive != "none" && !newIsMaster, let fi = focusedIndex {
            let masterCount = nodes.filter(\.isMaster).count
            if !(nodes[fi].isMaster && (masterCount == 1 || o.newStatus == "slave")) {
                at = o.newOnActive == "before" ? fi : fi + 1
            }
        }
        var node = Node(window: id, isMaster: false, percMaster: nodes.first(where: \.isMaster)?.percMaster ?? o.mfact, percSize: 1)
        if becomesMaster {
            let demote = o.newOnActive == "before" ? nodes.lastIndex(where: \.isMaster) : nodes.firstIndex(where: \.isMaster)
            if let d = demote {
                node.percMaster = nodes[d].percMaster
                nodes[d].isMaster = false
            } else {
                node.percMaster = o.mfact
            }
            node.isMaster = true
        }
        nodes.insert(node, at: at)
    }

    public mutating func remove(_ id: WindowID) {
        guard let i = index(of: id) else { return }
        let node = nodes[i]
        let mastersBefore = nodes.filter(\.isMaster).count
        if node.isMaster && (mastersBefore <= 1 || allowSmallSplit), let s = nodes.firstIndex(where: { !$0.isMaster }) {
            nodes[s].isMaster = true
            nodes[s].percMaster = node.percMaster
        }
        nodes.remove(at: i)
        if previousFocus == id { previousFocus = nil }
        if !nodes.isEmpty && nodes.allSatisfy(\.isMaster) && mastersBefore > 1 && nodes.count > 1 { nodes[nodes.count - 1].isMaster = false }
        if nodes.count == 1 { nodes[0].isMaster = true }
    }

    public mutating func swap(_ a: WindowID, _ b: WindowID) {
        guard let i = index(of: a), let j = index(of: b) else { return }
        nodes[i].window = b
        nodes[j].window = a
    }

    public mutating func resize(_ id: WindowID, by delta: Point, corner: Corner, _ ctx: LayoutContext) {
        guard let i = index(of: id) else { return }
        let wa = ctx.workArea
        let orient = orientation(ctx)
        let vertical = orient == "top" || orient == "bottom"
        let masterDelta: Double
        switch orient {
        case "right": masterDelta = -delta.x / wa.width
        case "top": masterDelta = delta.y / wa.height
        case "bottom": masterDelta = -delta.y / wa.height
        default: masterDelta = delta.x / wa.width
        }
        if masterDelta != 0 {
            for k in nodes.indices where nodes[k].isMaster { nodes[k].percMaster = min(max(nodes[k].percMaster + masterDelta, 0.05), 0.95) }
        }
        let stackDelta = vertical ? delta.x : delta.y
        guard stackDelta != 0 else { return }
        let column = nodes.filter { $0.isMaster == nodes[i].isMaster }.count
        let extent = vertical ? wa.width : wa.height
        let unit = extent / Double(max(column, 1))
        nodes[i].percSize = min(max(nodes[i].percSize + stackDelta / unit, 0.05), 1.95)
    }

    public mutating func moveWindow(_ id: WindowID, _ direction: Direction, _ ctx: LayoutContext) -> Bool {
        let boxes = tileBoxes(ctx)
        guard let box = boxes[id] else { return false }
        let focal = WindowGeometry.focalPoint(of: box, direction)
        guard let target = boxes.first(where: { $0.key != id && $0.value.contains(focal) })?.key else { return false }
        swap(id, target)
        return true
    }

    func nextTarget(_ id: WindowID, next: Bool, loop: Bool) -> WindowID? {
        guard let start = index(of: id) else { return nil }
        let node = nodes[start]
        let list = next ? Array(nodes[start...]) : Array(nodes[...start].reversed())
        var candidate = list.first { $0.window != id && $0.isMaster == node.isMaster }
        if candidate == nil {
            let all = next ? nodes : nodes.reversed()
            candidate = all.first { $0.window != id && $0.isMaster != node.isMaster }
        }
        guard let c = candidate else { return nil }
        if !loop {
            if c.isMaster && next { return nil }
            if !c.isMaster && node.isMaster && !next { return nil }
        }
        return c.window
    }

    public mutating func message(_ text: String, _ ctx: LayoutContext) -> LayoutMessageResult {
        allowSmallSplit = ctx.master.allowSmallSplit
        let words = text.split(separator: " ").map(String.init)
        guard let command = words.first else { return .error("empty layout message") }
        let args = Array(words.dropFirst())
        if command.hasPrefix("orientation") {
            let current = orientation(ctx)
            let pos = MasterLayout.orientations.firstIndex(of: current) ?? 0
            switch command {
            case "orientationnext": orientationOverride = MasterLayout.orientations[(pos + 1) % 5]
            case "orientationprev": orientationOverride = MasterLayout.orientations[(pos + 4) % 5]
            case "orientationcycle":
                let list = args.isEmpty ? MasterLayout.orientations : args
                let at = list.firstIndex(of: current).map { ($0 + 1) % list.count } ?? 0
                orientationOverride = list[at]
            default:
                let name = String(command.dropFirst("orientation".count))
                guard MasterLayout.orientations.contains(name) else { return .error("unknown master layout message '\(command)'") }
                orientationOverride = name
            }
            return .ok
        }
        if command == "mfact" {
            let exact = args.first == "exact"
            guard let v = (exact ? args.dropFirst().first : args.first).flatMap(Double.init),
                  let m = nodes.firstIndex(where: \.isMaster) else { return .error("invalid mfact") }
            nodes[m].percMaster = min(max(exact ? v : nodes[m].percMaster + v, 0.05), 0.95)
            return .ok
        }
        guard let focused = ctx.focused, let fi = index(of: focused) else { return .error("no focused tiled window") }
        switch command {
        case "swapwithmaster":
            if !nodes[fi].isMaster {
                guard let m = nodes.first(where: \.isMaster)?.window else { return .error("no master") }
                swap(focused, m)
                return args.contains("child") ? .focus(m) : .ok
            }
            if args.contains("ignoremaster") { return .ok }
            guard let s = nodes.first(where: { !$0.isMaster })?.window else { return .ok }
            swap(focused, s)
            return args.contains("master") ? .focus(s) : .ok
        case "focusmaster":
            let mode = args.first ?? "auto"
            if !nodes[fi].isMaster {
                if mode == "previous" { previousFocus = focused }
                return nodes.first(where: \.isMaster).map { .focus($0.window) } ?? .ok
            }
            if mode == "master" { return .ok }
            if mode == "previous", let p = previousFocus, p != focused, index(of: p) != nil { return .focus(p) }
            return nodes.first(where: { !$0.isMaster }).map { .focus($0.window) } ?? .ok
        case "cyclenext", "cycleprev":
            return nextTarget(focused, next: command == "cyclenext", loop: !args.contains("noloop")).map { .focus($0) } ?? .ok
        case "swapnext", "swapprev":
            guard let t = nextTarget(focused, next: command == "swapnext", loop: !args.contains("noloop")) else { return .ok }
            swap(focused, t)
            return .ok
        case "addmaster":
            let masters = nodes.filter(\.isMaster).count
            guard masters + 2 <= nodes.count || allowSmallSplit else { return .error("nothing to do") }
            if !nodes[fi].isMaster { nodes[fi].isMaster = true }
            else if let s = nodes.firstIndex(where: { !$0.isMaster }) { nodes[s].isMaster = true }
            return .ok
        case "removemaster":
            let masters = nodes.filter(\.isMaster).count
            guard nodes.count >= 2 && masters >= 2 else { return .error("nothing to do") }
            if nodes[fi].isMaster { nodes[fi].isMaster = false }
            else if let m = nodes.lastIndex(where: \.isMaster) { nodes[m].isMaster = false }
            return .ok
        case "rollnext", "rollprev":
            guard let s = (command == "rollnext" ? nodes.firstIndex(where: { !$0.isMaster }) : nodes.lastIndex(where: { !$0.isMaster })),
                  let m = (nodes[fi].isMaster ? fi : nodes.firstIndex(where: \.isMaster)) else { return .ok }
            let newMaster = nodes[s].window
            nodes[s].isMaster = true
            nodes[s].percMaster = nodes[m].percMaster
            var old = nodes[m]
            old.isMaster = false
            nodes.remove(at: m)
            if command == "rollnext" { nodes.append(old) } else { nodes.insert(old, at: 0) }
            return .focus(newMaster)
        default:
            return .error("unknown master layout message '\(command)'")
        }
    }

    public func nextFocusCandidate(near point: Point, _ ctx: LayoutContext) -> WindowID? {
        if ctx.master.focusMasterOnClose, let m = nodes.first(where: \.isMaster) { return m.window }
        let boxes = tileBoxes(ctx)
        return boxes.min { $0.value.distanceSquared(to: point) < $1.value.distanceSquared(to: point) }?.key ?? nodes.first?.window
    }
}
```

`Sources/HyprCore/Layout/Monocle.swift`:

```swift
import Foundation

public struct MonocleLayout: TiledLayout, Equatable, Codable, Sendable {
    var order: [WindowID] = []

    public init() {}

    public var windowIDs: [WindowID] { order }

    public mutating func insert(_ id: WindowID, _ ctx: LayoutContext) {
        guard !order.contains(id) else { return }
        if let f = ctx.focused, let i = order.firstIndex(of: f) { order.insert(id, at: i + 1) } else { order.append(id) }
    }

    public mutating func remove(_ id: WindowID) { order.removeAll { $0 == id } }

    public func tileBoxes(_ ctx: LayoutContext) -> [WindowID: Rect] {
        Dictionary(uniqueKeysWithValues: order.map { ($0, ctx.workArea) })
    }

    public mutating func resize(_ id: WindowID, by delta: Point, corner: Corner, _ ctx: LayoutContext) {}

    public mutating func swap(_ a: WindowID, _ b: WindowID) {
        guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b) else { return }
        order.swapAt(i, j)
    }

    public mutating func moveWindow(_ id: WindowID, _ direction: Direction, _ ctx: LayoutContext) -> Bool {
        guard let i = order.firstIndex(of: id) else { return false }
        let j = (direction == .left || direction == .up) ? i - 1 : i + 1
        guard order.indices.contains(j) else { return false }
        order.swapAt(i, j)
        return true
    }

    public func neighbor(of id: WindowID, forward: Bool) -> WindowID? {
        guard let i = order.firstIndex(of: id), order.count > 1 else { return nil }
        return order[(i + (forward ? 1 : order.count - 1)) % order.count]
    }

    public mutating func message(_ text: String, _ ctx: LayoutContext) -> LayoutMessageResult {
        guard let f = ctx.focused else { return .error("no focused tiled window") }
        switch text.split(separator: " ").first {
        case "cyclenext": return neighbor(of: f, forward: true).map { .focus($0) } ?? .ok
        case "cycleprev": return neighbor(of: f, forward: false).map { .focus($0) } ?? .ok
        default: return .error("unknown monocle layout message '\(text)'")
        }
    }

    public func nextFocusCandidate(near point: Point, _ ctx: LayoutContext) -> WindowID? { order.last }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter MasterMonocleTests`
Expected: PASS. The expected boxes follow `hyprland-algorithms.md` section 2 and the simplifications above; fix the code, not the tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/HyprCore/Layout/Master.swift Sources/HyprCore/Layout/Monocle.swift Tests/HyprCoreTests/MasterMonocleTests.swift
git commit -m "feat: port the Hyprland master layout and add monocle"
```

---
### Task 13: World core (model, effects, parking, windows, layout pass)

**Files:**
- Create: `Sources/HyprCore/World/Model.swift`, `Sources/HyprCore/World/Effects.swift`, `Sources/HyprCore/World/Parking.swift`, `Sources/HyprCore/World/World.swift`
- Test: `Tests/HyprCoreTests/WorldCoreTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1-12.
- Produces (later tasks extend `World` in new files and add cases to `World.apply`):

```swift
public struct MonitorInfo: Equatable, Codable, Sendable { public var id: Int; public var name: String; public var frame: Rect; public var visibleFrame: Rect }
public enum WindowKind: String, Codable, Sendable { case normal, dialog }
public struct WindowSnapshot: Equatable, Sendable { public var id: WindowID; public var pid: Int32; public var bundleID: String; public var appName: String; public var title: String; public var frame: Rect; public var kind: WindowKind }
public enum SuspendReason: String, Codable, Sendable { case minimized, nativeFullscreen, appHidden }
public struct ManagedWindow: Equatable, Codable, Sendable { id, pid, bundleID, appName, title, initialTitle, isModal, workspace: Int, isFloating, floatingFrame: Rect, fullscreenMode: Int?, isPseudo, pseudoSize: Size, isPinned, everFloated, suspended: SuspendReason?, appliedFrame: Rect?, lastFrame: Rect, isParked, refitTarget: Rect?, props: [String: String]; var address: String }
public enum LayoutKind: String, Codable, Sendable, CaseIterable { case dwindle, master, monocle }
public enum LayoutState: Equatable, Codable, Sendable { case dwindle(DwindleLayout), master(MasterLayout), monocle(MonocleLayout)
    public init(_ kind: LayoutKind); public var kind: LayoutKind; public var current: any TiledLayout
    @discardableResult public mutating func update<R>(_ body: (inout any TiledLayout) -> R) -> R }
public struct Workspace: Equatable, Codable, Sendable { id, name, monitor: Int, homeMonitorName, isSpecial, layout: LayoutState, floating: [WindowID], lastFocused: WindowID?, persistent; var tiledIDs: [WindowID]; var windowIDs: [WindowID] }
public enum FrameReason: Equatable, Sendable { case layout, open, workspaceIn(leftward: Bool), restore }
public struct FrameChange: Equatable, Sendable { public var id: WindowID; public var frame: Rect; public var reason: FrameReason }
public struct ParkRequest: Equatable, Sendable { public var id: WindowID; public var origin: Point }
public enum Effect: Equatable, Sendable {
    case setFrames([FrameChange]), park([ParkRequest]), focus(WindowID), raise(WindowID), close(WindowID)
    case signal(pid: Int32, signal: Int32), hideApp(Int32), unhideApp(Int32), spawn(String, token: Int?), warpCursor(Point)
    case submapChanged(String), statusChanged, saveState, reloadConfig, exitApp
}
public struct CommandResult: Equatable, Sendable { public var reply: String; public var isError: Bool; public var effects: [Effect] }
public enum PlatformEvent: Equatable, Sendable {
    case monitorsChanged([MonitorInfo]), windowAppeared(WindowSnapshot), windowDisappeared(WindowID)
    case windowSuspended(WindowID, SuspendReason), windowResumed(WindowID)
    case appHidden(pid: Int32, byUser: Bool), appUnhidden(pid: Int32), appTerminated(pid: Int32)
    case windowTitleChanged(WindowID, String, early: Bool), windowFrameChanged(WindowID, Rect, userDriven: Bool)
    case dragEnded(cursor: Point), focusChanged(WindowID?), cursorMoved(Point)
}
public enum Parking { public static func usesBottomLeft(_ m: MonitorInfo, among all: [MonitorInfo]) -> Bool
    public static func origin(windowSize: Size, monitor: MonitorInfo, among all: [MonitorInfo], bundleID: String) -> Point }
public final class World {
    public private(set) var config: Config
    public internal(set) var monitors: [MonitorInfo]; workspaces: [Int: Workspace]; windows: [WindowID: ManagedWindow]
    public internal(set) var activeWorkspace: [Int: Int]; activeSpecial: [Int: Int]; focusedMonitor: Int; focusedWindow: WindowID?; focusHistory: [WindowID]; submap: String
    public var cursor: Point; public var isStartingUp: Bool
    public init(config: Config)
    public func handle(_ event: PlatformEvent) -> [Effect]
    public func reload(_ newConfig: Config) -> [Effect]
    public func registerSpawn(token: Int, pid: Int32)
    public var activeBinds: [Bind] { get }
    // internal helpers used by Tasks 14-16 (exact names):
    func emit(_ e: Effect); func takeEffects() -> [Effect]; func apply(_ event: PlatformEvent)
    func monitor(_ id: Int) -> MonitorInfo?; func monitorID(containing p: Point) -> Int?; func resolveMonitor(_ s: String) -> Int?
    func isVisible(_ wsID: Int) -> Bool; func workArea(for ws: Workspace) -> Rect; func fullscreenArea(for ws: Workspace) -> Rect
    func gapsIn(for ws: Workspace) -> Edges; func borderSize(for ws: Workspace) -> Double
    func rules(for ws: Workspace) -> [WorkspaceRule]; func layoutContext(_ ws: Workspace, focalPoint: Point?) -> LayoutContext
    func targetFrames(_ ws: Workspace) -> [WindowID: Rect]; func idealBoxes(_ ws: Workspace) -> [WindowID: Rect]
    func refresh(_ ids: Set<Int>, reason: FrameReason, opened: WindowID?, skip: WindowID?)
    @discardableResult func ensureWorkspace(_ id: Int, name: String?, special: Bool, monitor: Int?, createdEmpty: Bool) -> Int
    func lowestUnusedID() -> Int; func destroyIfUnused(_ id: Int)
    func detach(_ id: WindowID); func attach(_ id: WindowID, to wsID: Int, focalPoint: Point?)
    func facts(for w: ManagedWindow) -> WindowFacts; func staticOutcome(for w: ManagedWindow) -> StaticRuleOutcome
    func resolveRuleWorkspace(_ selector: String) -> Int?
    func focusWindow(_ id: WindowID?, warp: Bool, emitEffect: Bool)
    func focusCandidate(onWorkspace wsID: Int, near point: Point) -> WindowID?
    func setMonitors(_ infos: [MonitorInfo]); func addWindow(_ s: WindowSnapshot); func removeWindow(_ id: WindowID)
}
```

Rules for this task:
- `setMonitors`: sort by id; workspaces whose `homeMonitorName` matches a present monitor move there, others on a missing monitor move to the first monitor; drop active entries for missing monitors or workspaces that moved away; every monitor without an active workspace gets, in order: the workspace remembered as last active for that monitor name, a workspace rule `default:true` bound to it, the lowest hidden workspace on it, or a new workspace with the lowest unused id; the focused monitor falls back to the first; refresh every workspace.
- Work area: monitor `visibleFrame`, inset by `reservedAreas[monitor name]` or `reservedAreas[""]`, inset by `gaps_out` (last matching workspace rule `gapsout` wins); a special workspace uses that area scaled by `special_scale_factor` (master's when its layout is master, else dwindle's) and centered. `fullscreenArea` is the visible frame minus reserved space, no gaps.
- `targetFrames`: tiled windows use `WindowGeometry.frame` with the workspace's `gaps_in`, border size (0 when a rule says `border:false`), and pseudo size when `isPseudo`; floating windows use `floatingFrame`; a window with `fullscreenMode` 0 gets `fullscreenArea`, mode 1 gets the work area inset by the border. Suspended windows never appear.
- `refresh`: for a visible workspace, emit a `FrameChange` for each window whose target differs from `appliedFrame` by 1 pt or more, or that is parked (reason `.open` for `opened`, else `reason`; `skip` is never emitted); update `appliedFrame`, clear `isParked`. For a hidden workspace, park every window that is not parked yet with `Parking.origin` and set `isParked`. Frames are emitted before parks.
- `takeEffects`: keeps only the last frame or park per window across the whole batch, emits one `.setFrames` then one `.park`, then the other effects in order, then one `.statusChanged` and one `.saveState` if any were requested.
- `addWindow`: skip known or ignored ids; the target workspace is the active workspace of the focused monitor (during startup: of the monitor containing the window center); compute static rules with `isFloating = isModal = (kind == .dialog)`, merge rules registered for the window's pid by `registerSpawn` (they come last, so they win), then: `ignore` adds the id to the ignored set and stops; a rule workspace resolves with `resolveRuleWorkspace` (id, `name:`, `special`, `special:x`) and is silent only when the rule says so; a rule monitor picks that monitor's active workspace; `floating = outcome.floating ?? (kind == .dialog)`; the floating frame is the snapshot frame moved inside the monitor's visible frame, then sized by `size`, moved by `move` (monitor-local), centered by `center`; for a new floating window `appliedFrame` starts at the snapshot frame so no write happens unless a rule changed it; `fullscreen`/`maximize` set `fullscreenMode` and clear it on the other windows of that workspace; `pseudo` sets `isPseudo` with the snapshot size; `pin` pins floating windows. Then attach, show the workspace when a non-silent rule moved it to a hidden one (through the small `showWorkspace` helper; Task 14 replaces that call with `switchWorkspace`), refresh with `opened`, focus the window with `emitEffect: true` unless `no_initial_focus` or its workspace is hidden; when it landed hidden, emit `.focus` for the previously focused window to take focus back.
- `removeWindow`: drop from ignored; detach; remove from history; if it was focused, focus the candidate from `focusCandidate` (by `input:focus_on_close`: 0 layout candidate near its center, 1 window under the cursor, 2 most recent in history on that workspace); refresh; destroy the workspace when empty, hidden and not persistent.
- The cursor starts at (1e9, 1e9), which means "unknown": new dwindle windows then go second. The app sets `cursor` from the real mouse position before every event and command.
- Special workspace ids: `special` is -99; named special workspaces get -98, -97 and so on.
- `focusWindow`: sets the focused window, history (most recent last), the workspace's `lastFocused` and the focused monitor; emits `.focus` when `emitEffect`; warps the cursor to the window center when `warp`, `cursor:no_warps` is false and the cursor is not inside the applied frame.
- `reload`: replace the config, refresh every workspace, emit `.statusChanged`.
- `activeBinds`: binds of the current submap plus `universal` binds.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/WorldCoreTests.swift`:

```swift
import Testing
@testable import HyprCore

let laptop = MonitorInfo(id: 0, name: "Built-in Retina Display", frame: Rect(x: 0, y: 0, width: 1512, height: 982),
                         visibleFrame: Rect(x: 0, y: 32, width: 1512, height: 950))

func makeConfig(_ text: String = "") -> Config {
    let parser = HyprlangParser(environment: [:], readFile: { _ in nil }, glob: { _ in [] })
    let base = "general {\n gaps_in = 0\n gaps_out = 0\n border_size = 0\n}\n"
    return ConfigBuilder.build(parser.parse(text: base + text, path: "/t.conf").entries).config
}

func snap(_ id: WindowID, app: String = "Ghostty", bundle: String = "com.mitchellh.ghostty", pid: Int32 = 100,
          frame: Rect = Rect(x: 100, y: 100, width: 600, height: 400), kind: WindowKind = .normal, title: String = "t") -> WindowSnapshot {
    WindowSnapshot(id: id, pid: pid, bundleID: bundle, appName: app, title: title, frame: frame, kind: kind)
}

func frames(_ effects: [Effect]) -> [WindowID: Rect] {
    var out: [WindowID: Rect] = [:]
    for case .setFrames(let changes) in effects { for c in changes { out[c.id] = c.frame } }
    return out
}

func parks(_ effects: [Effect]) -> [WindowID: Point] {
    var out: [WindowID: Point] = [:]
    for case .park(let p) in effects { for r in p { out[r.id] = r.origin } }
    return out
}

func world(_ text: String = "", monitors: [MonitorInfo] = [laptop]) -> World {
    let w = World(config: makeConfig(text))
    _ = w.handle(.monitorsChanged(monitors))
    return w
}

@Suite struct WorldCoreTests {
    @Test func monitorGetsWorkspaceOne() {
        let w = world()
        #expect(w.activeWorkspace[0] == 1)
        #expect(w.workspaces[1]?.monitor == 0)
    }

    @Test func firstWindowFillsTheVisibleFrameAndGetsFocus() {
        let w = world()
        let e = w.handle(.windowAppeared(snap(1)))
        #expect(frames(e) == [1: Rect(x: 0, y: 32, width: 1512, height: 950)])
        #expect(e.contains(.focus(1)))
        #expect(w.focusedWindow == 1)
    }

    @Test func secondWindowSplitsAndOnlyChangedFramesAreSent() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        let e = w.handle(.windowAppeared(snap(2)))
        #expect(frames(e) == [1: Rect(x: 0, y: 32, width: 756, height: 950), 2: Rect(x: 756, y: 32, width: 756, height: 950)])
        let again = w.handle(.monitorsChanged([laptop]))
        #expect(frames(again).isEmpty)
    }

    @Test func gapsBordersAndReservedArea() {
        let w = world("general:gaps_in = 4\ngeneral:gaps_out = 10\ngeneral:border_size = 2\nmonitor = , addreserved, 20, 0, 0, 0")
        _ = w.handle(.windowAppeared(snap(1)))
        let e = w.handle(.windowAppeared(snap(2)))
        #expect(frames(e)[1] == Rect(x: 12, y: 64, width: 738, height: 906))
        #expect(frames(e)[2] == Rect(x: 762, y: 64, width: 738, height: 906))
    }

    @Test func floatRuleKeepsAppFrameWithoutWrites() {
        let w = world("windowrule = float on, match:class Calculator")
        let e = w.handle(.windowAppeared(snap(1, app: "Calculator", bundle: "com.apple.calculator")))
        #expect(frames(e).isEmpty)
        #expect(w.windows[1]?.isFloating == true)
    }

    @Test func dialogsFloatByDefault() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1, kind: .dialog)))
        #expect(w.windows[1]?.isFloating == true)
    }

    @Test func floatByDefaultPolicyWithTileAllowList() {
        let w = world("windowrule = float on, match:class .*\nwindowrule = tile on, match:class Ghostty, match:modal false")
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, app: "Mail", bundle: "com.apple.mail")))
        _ = w.handle(.windowAppeared(snap(3, kind: .dialog)))
        #expect(w.windows[1]?.isFloating == false)
        #expect(w.windows[2]?.isFloating == true)
        #expect(w.windows[3]?.isFloating == true)
    }

    @Test func ignoreRuleLeavesWindowUnmanaged() {
        let w = world("windowrule = ignore on, match:class Raycast")
        let e = w.handle(.windowAppeared(snap(1, app: "Raycast", bundle: "com.raycast.macos")))
        #expect(e.isEmpty)
        #expect(w.windows[1] == nil)
    }

    @Test func appWithoutBundleIdIsManagedByName() {
        let w = world("windowrule = float on, match:class Minecraft")
        _ = w.handle(.windowAppeared(snap(1, app: "Minecraft", bundle: "")))
        #expect(w.windows[1]?.isFloating == true)
    }

    @Test func silentRuleWorkspaceParksWindowAndKeepsFocus() {
        let w = world("windowrule = workspace 3 silent, match:class Slack")
        _ = w.handle(.windowAppeared(snap(1)))
        let e = w.handle(.windowAppeared(snap(2, app: "Slack", bundle: "com.tinyspeck.slackmacgap", pid: 200)))
        #expect(w.windows[2]?.workspace == 3)
        #expect(parks(e)[2] == Point(x: 1511, y: 981))
        #expect(e.contains(.focus(1)))
        #expect(w.focusedWindow == 1)
    }

    @Test func closingFocusedWindowFocusesNeighbourAndRetiles() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2)))
        let e = w.handle(.windowDisappeared(2))
        #expect(frames(e) == [1: Rect(x: 0, y: 32, width: 1512, height: 950)])
        #expect(e.contains(.focus(1)))
    }

    @Test func parkingCornerAndZoom() {
        #expect(Parking.origin(windowSize: Size(width: 500, height: 400), monitor: laptop, among: [laptop], bundleID: "x") == Point(x: 1511, y: 981))
        #expect(Parking.origin(windowSize: Size(width: 500, height: 400), monitor: laptop, among: [laptop], bundleID: "us.zoom.xos") == Point(x: 1512, y: 982))
        let right = MonitorInfo(id: 1, name: "PHL", frame: Rect(x: 1512, y: 0, width: 5120, height: 1440), visibleFrame: Rect(x: 1512, y: 0, width: 5120, height: 1440))
        #expect(Parking.usesBottomLeft(laptop, among: [laptop, right]))
    }

    @Test func spawnRulesApplyToTheSpawnedPid() {
        let w = world()
        var token = 0
        let r = w.run(.exec("kitty", rules: "float; workspace 2 silent", raw: false))
        for case .spawn(_, let t?) in r.effects { token = t }
        w.registerSpawn(token: token, pid: 555)
        _ = w.handle(.windowAppeared(snap(9, app: "kitty", bundle: "net.kovidgoyal.kitty", pid: 555)))
        #expect(w.windows[9]?.isFloating == true)
        #expect(w.windows[9]?.workspace == 2)
    }
}
```

`spawnRulesApplyToTheSpawnedPid` uses `World.run`, which Task 15 adds; mark it `.disabled("needs Task 15")` until then and remove the trait in Task 15:

```swift
    @Test(.disabled("needs Task 15")) func spawnRulesApplyToTheSpawnedPid() {
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WorldCoreTests`
Expected: FAIL, "cannot find 'World' in scope".

- [ ] **Step 3: Implement the model and effects**

`Sources/HyprCore/World/Model.swift`:

```swift
import Foundation

public struct MonitorInfo: Equatable, Codable, Sendable {
    public var id: Int
    public var name: String
    public var frame: Rect
    public var visibleFrame: Rect
    public init(id: Int, name: String, frame: Rect, visibleFrame: Rect) {
        self.id = id; self.name = name; self.frame = frame; self.visibleFrame = visibleFrame
    }
}

public enum WindowKind: String, Codable, Sendable { case normal, dialog }

public struct WindowSnapshot: Equatable, Sendable {
    public var id: WindowID
    public var pid: Int32
    public var bundleID: String
    public var appName: String
    public var title: String
    public var frame: Rect
    public var kind: WindowKind
    public init(id: WindowID, pid: Int32, bundleID: String, appName: String, title: String, frame: Rect, kind: WindowKind) {
        self.id = id; self.pid = pid; self.bundleID = bundleID; self.appName = appName; self.title = title; self.frame = frame; self.kind = kind
    }
}

public enum SuspendReason: String, Codable, Sendable { case minimized, nativeFullscreen, appHidden }

public struct ManagedWindow: Equatable, Codable, Sendable {
    public var id: WindowID
    public var pid: Int32
    public var bundleID: String
    public var appName: String
    public var title: String
    public var initialTitle: String
    public var isModal: Bool
    public var workspace: Int
    public var isFloating: Bool
    public var floatingFrame: Rect
    public var fullscreenMode: Int?
    public var isPseudo = false
    public var pseudoSize = Size(width: 1280, height: 720)
    public var isPinned = false
    public var everFloated = false
    public var suspended: SuspendReason?
    public var appliedFrame: Rect?
    public var lastFrame: Rect
    public var isParked = false
    public var refitTarget: Rect?
    public var props: [String: String] = [:]
    public var address: String { String(format: "0x%x", id) }
}

public enum LayoutKind: String, Codable, Sendable, CaseIterable { case dwindle, master, monocle }

public enum LayoutState: Equatable, Codable, Sendable {
    case dwindle(DwindleLayout)
    case master(MasterLayout)
    case monocle(MonocleLayout)

    public init(_ kind: LayoutKind) {
        switch kind {
        case .dwindle: self = .dwindle(DwindleLayout())
        case .master: self = .master(MasterLayout())
        case .monocle: self = .monocle(MonocleLayout())
        }
    }

    public var kind: LayoutKind {
        switch self {
        case .dwindle: return .dwindle
        case .master: return .master
        case .monocle: return .monocle
        }
    }

    public var current: any TiledLayout {
        switch self {
        case .dwindle(let l): return l
        case .master(let l): return l
        case .monocle(let l): return l
        }
    }

    @discardableResult
    public mutating func update<R>(_ body: (inout any TiledLayout) -> R) -> R {
        var layout = current
        let result = body(&layout)
        if let d = layout as? DwindleLayout { self = .dwindle(d) }
        else if let m = layout as? MasterLayout { self = .master(m) }
        else if let m = layout as? MonocleLayout { self = .monocle(m) }
        return result
    }
}

public struct Workspace: Equatable, Codable, Sendable {
    public var id: Int
    public var name: String
    public var monitor: Int
    public var homeMonitorName: String
    public var isSpecial: Bool
    public var layout: LayoutState
    public var floating: [WindowID] = []
    public var lastFocused: WindowID?
    public var persistent = false
    public var tiledIDs: [WindowID] { layout.current.windowIDs }
    public var windowIDs: [WindowID] { tiledIDs + floating }
}
```

`Sources/HyprCore/World/Effects.swift`:

```swift
import Foundation

public enum FrameReason: Equatable, Sendable { case layout, open, workspaceIn(leftward: Bool), restore }

public struct FrameChange: Equatable, Sendable {
    public var id: WindowID
    public var frame: Rect
    public var reason: FrameReason
    public init(id: WindowID, frame: Rect, reason: FrameReason) { self.id = id; self.frame = frame; self.reason = reason }
}

public struct ParkRequest: Equatable, Sendable {
    public var id: WindowID
    public var origin: Point
    public init(id: WindowID, origin: Point) { self.id = id; self.origin = origin }
}

public enum Effect: Equatable, Sendable {
    case setFrames([FrameChange])
    case park([ParkRequest])
    case focus(WindowID)
    case raise(WindowID)
    case close(WindowID)
    case signal(pid: Int32, signal: Int32)
    case hideApp(Int32)
    case unhideApp(Int32)
    case spawn(String, token: Int?)
    case warpCursor(Point)
    case submapChanged(String)
    case statusChanged
    case saveState
    case reloadConfig
    case exitApp
}

public struct CommandResult: Equatable, Sendable {
    public var reply: String
    public var isError: Bool
    public var effects: [Effect]
}

public enum PlatformEvent: Equatable, Sendable {
    case monitorsChanged([MonitorInfo])
    case windowAppeared(WindowSnapshot)
    case windowDisappeared(WindowID)
    case windowSuspended(WindowID, SuspendReason)
    case windowResumed(WindowID)
    case appHidden(pid: Int32, byUser: Bool)
    case appUnhidden(pid: Int32)
    case appTerminated(pid: Int32)
    case windowTitleChanged(WindowID, String, early: Bool)
    case windowFrameChanged(WindowID, Rect, userDriven: Bool)
    case dragEnded(cursor: Point)
    case focusChanged(WindowID?)
    case cursorMoved(Point)
}
```

`Sources/HyprCore/World/Parking.swift`:

```swift
import Foundation

public enum Parking {
    public static func usesBottomLeft(_ monitor: MonitorInfo, among all: [MonitorInfo]) -> Bool {
        let f = monitor.frame
        let xOff = f.width * 0.1, yOff = f.height * 0.1
        let br = Point(x: f.maxX, y: f.maxY), bl = Point(x: f.minX, y: f.maxY)
        func score(_ p: [Point]) -> Int {
            all.reduce(0) { acc, m in
                acc + (m.frame.contains(p[0]) ? 1 : 0) + (m.frame.contains(p[1]) ? 1 : 0) + (m.frame.contains(p[2]) ? 10 : 0)
            }
        }
        let brScore = score([br + Point(x: 2, y: -yOff), br + Point(x: -xOff, y: 2), br + Point(x: 2, y: 2)])
        let blScore = score([bl + Point(x: -2, y: -yOff), bl + Point(x: xOff, y: 2), bl + Point(x: -2, y: 2)])
        return blScore < brScore
    }

    public static func origin(windowSize: Size, monitor: MonitorInfo, among all: [MonitorInfo], bundleID: String) -> Point {
        let v = monitor.visibleFrame
        let offset: Double = bundleID == "us.zoom.xos" ? 0 : 1
        if usesBottomLeft(monitor, among: all) { return Point(x: v.minX + offset - windowSize.width, y: v.maxY - offset) }
        return Point(x: v.maxX - offset, y: v.maxY - offset)
    }
}
```

- [ ] **Step 4: Implement the world core**

`Sources/HyprCore/World/World.swift`:

```swift
import Foundation

public final class World {
    public private(set) var config: Config
    public internal(set) var monitors: [MonitorInfo] = []
    public internal(set) var workspaces: [Int: Workspace] = [:]
    public internal(set) var windows: [WindowID: ManagedWindow] = [:]
    public internal(set) var activeWorkspace: [Int: Int] = [:]
    public internal(set) var activeSpecial: [Int: Int] = [:]
    public internal(set) var focusedMonitor = 0
    public internal(set) var focusedWindow: WindowID?
    public internal(set) var focusHistory: [WindowID] = []
    public internal(set) var submap = ""
    public var cursor = Point(x: 1e9, y: 1e9)
    public var isStartingUp = false
    var ignored: Set<WindowID> = []
    var previousWorkspace: Int?
    var previousPerMonitor: [Int: Int] = [:]
    var lastActiveByMonitorName: [String: Int] = [:]
    var nextNamedID = 1_000_000
    var nextSpecialID = -98
    var spawnRules: [Int: String] = [:]
    var pidRules: [Int32: String] = [:]
    var nextSpawnToken = 1
    var dragging: WindowID?
    var dragIsResize = false
    var effects: [Effect] = []

    public init(config: Config) { self.config = config }

    public func handle(_ event: PlatformEvent) -> [Effect] {
        apply(event)
        return takeEffects()
    }

    func apply(_ event: PlatformEvent) {
        switch event {
        case .monitorsChanged(let infos): setMonitors(infos)
        case .windowAppeared(let s): addWindow(s)
        case .windowDisappeared(let id): removeWindow(id)
        default: break
        }
    }

    public func reload(_ newConfig: Config) -> [Effect] {
        config = newConfig
        refresh(Set(workspaces.keys))
        emit(.statusChanged)
        return takeEffects()
    }

    public func registerSpawn(token: Int, pid: Int32) {
        if let rules = spawnRules.removeValue(forKey: token) { pidRules[pid] = rules }
    }

    public var activeBinds: [Bind] { config.binds.filter { $0.submap == submap || $0.flags.contains(.universal) } }

    func emit(_ e: Effect) { effects.append(e) }

    func takeEffects() -> [Effect] {
        var frames: [FrameChange] = []
        var parks: [ParkRequest] = []
        var others: [Effect] = []
        var status = false, save = false
        for e in effects {
            switch e {
            case .setFrames(let list):
                for c in list {
                    frames.removeAll { $0.id == c.id }
                    parks.removeAll { $0.id == c.id }
                    frames.append(c)
                }
            case .park(let list):
                for p in list {
                    frames.removeAll { $0.id == p.id }
                    parks.removeAll { $0.id == p.id }
                    parks.append(p)
                }
            case .statusChanged: status = true
            case .saveState: save = true
            default: others.append(e)
            }
        }
        effects = []
        var out: [Effect] = []
        if !frames.isEmpty { out.append(.setFrames(frames)) }
        if !parks.isEmpty { out.append(.park(parks)) }
        out += others
        if status { out.append(.statusChanged) }
        if save { out.append(.saveState) }
        return out
    }

    func monitor(_ id: Int) -> MonitorInfo? { monitors.first { $0.id == id } }

    func monitorID(containing p: Point) -> Int? { monitors.first { $0.frame.contains(p) }?.id }

    func resolveMonitor(_ s: String) -> Int? {
        if let n = Int(s) { return monitor(n)?.id }
        if s.hasPrefix("desc:") {
            let d = String(s.dropFirst(5))
            return monitors.first { $0.name.localizedCaseInsensitiveContains(d) }?.id
        }
        return monitors.first { $0.name == s }?.id ?? monitors.first { $0.name.localizedCaseInsensitiveContains(s) }?.id
    }

    func isVisible(_ wsID: Int) -> Bool {
        activeWorkspace.values.contains(wsID) || activeSpecial.values.contains(wsID)
    }

    func facts(of ws: Workspace) -> WorkspaceFacts {
        let tiled = ws.tiledIDs.count
        let fullscreen = ws.windowIDs.compactMap { windows[$0]?.fullscreenMode }.first ?? -1
        return WorkspaceFacts(id: ws.id, name: ws.name, isSpecial: ws.isSpecial, monitorName: monitor(ws.monitor)?.name ?? "",
                              tiledCount: tiled, floatingCount: ws.floating.count, fullscreenMode: fullscreen)
    }

    func rules(for ws: Workspace) -> [WorkspaceRule] {
        let f = facts(of: ws)
        return config.workspaceRules.filter { $0.matches(f, monitorMatches: { self.resolveMonitor($0) == ws.monitor }) }
    }

    func gapsIn(for ws: Workspace) -> Edges { rules(for: ws).compactMap(\.gapsIn).last ?? config.general.gapsIn }

    func borderSize(for ws: Workspace) -> Double {
        let r = rules(for: ws)
        if r.compactMap(\.border).last == false { return 0 }
        return Double(r.compactMap(\.borderSize).last ?? config.general.borderSize)
    }

    func fullscreenArea(for ws: Workspace) -> Rect {
        guard let m = monitor(ws.monitor) else { return .zero }
        return m.visibleFrame.inset(by: config.reservedAreas[m.name] ?? config.reservedAreas[""] ?? .zero)
    }

    func workArea(for ws: Workspace) -> Rect {
        let gapsOut = rules(for: ws).compactMap(\.gapsOut).last ?? config.general.gapsOut
        var area = fullscreenArea(for: ws).inset(by: gapsOut)
        if ws.isSpecial {
            let f = ws.layout.kind == .master ? config.master.specialScaleFactor : config.dwindle.specialScaleFactor
            area = Rect(x: area.x + area.width * (1 - f) / 2, y: area.y + area.height * (1 - f) / 2,
                        width: area.width * f, height: area.height * f)
        }
        return area
    }

    func layoutContext(_ ws: Workspace, focalPoint: Point? = nil) -> LayoutContext {
        let focused = focusedWindow.flatMap { windows[$0]?.workspace == ws.id ? $0 : nil } ?? ws.lastFocused
        return LayoutContext(workArea: workArea(for: ws), focused: focused, cursor: cursor, focalPoint: focalPoint,
                             isFirstMap: true, dragging: dragging != nil, dwindle: config.dwindle, master: config.master)
    }

    func idealBoxes(_ ws: Workspace) -> [WindowID: Rect] {
        var out = ws.layout.current.tileBoxes(layoutContext(ws))
        for id in ws.floating { if let w = windows[id] { out[id] = w.floatingFrame } }
        return out
    }

    func targetFrames(_ ws: Workspace) -> [WindowID: Rect] {
        var out: [WindowID: Rect] = [:]
        let ctx = layoutContext(ws)
        let gaps = gapsIn(for: ws)
        let border = borderSize(for: ws)
        for (id, box) in ws.layout.current.tileBoxes(ctx) {
            guard let w = windows[id] else { continue }
            let b = w.props["border_size"].flatMap(Double.init) ?? border
            out[id] = WindowGeometry.frame(tile: box, workArea: ctx.workArea, gapsIn: gaps, borderSize: b, pseudoSize: w.isPseudo ? w.pseudoSize : nil)
        }
        for id in ws.floating { if let w = windows[id] { out[id] = w.floatingFrame } }
        for id in ws.windowIDs {
            guard let mode = windows[id]?.fullscreenMode else { continue }
            out[id] = mode == 0 ? fullscreenArea(for: ws) : ctx.workArea.inset(by: Edges(all: border))
        }
        return out
    }

    func refresh(_ ids: Set<Int>, reason: FrameReason = .layout, opened: WindowID? = nil, skip: WindowID? = nil) {
        var changes: [FrameChange] = []
        var parkList: [ParkRequest] = []
        for wsID in ids.sorted() {
            guard let ws = workspaces[wsID], let mon = monitor(ws.monitor) else { continue }
            if isVisible(wsID) {
                for (id, frame) in targetFrames(ws) where id != skip {
                    guard var w = windows[id] else { continue }
                    let stale = w.appliedFrame.map { !$0.isClose(to: frame) } ?? true
                    if w.isParked || stale {
                        changes.append(FrameChange(id: id, frame: frame, reason: id == opened ? .open : reason))
                        w.appliedFrame = frame
                        w.isParked = false
                        windows[id] = w
                    }
                }
            } else {
                for id in ws.windowIDs {
                    guard var w = windows[id], !w.isParked else { continue }
                    let size = (w.appliedFrame ?? w.lastFrame).size
                    parkList.append(ParkRequest(id: id, origin: Parking.origin(windowSize: size, monitor: mon, among: monitors, bundleID: w.bundleID)))
                    w.isParked = true
                    windows[id] = w
                }
            }
        }
        if !changes.isEmpty { emit(.setFrames(changes)) }
        if !parkList.isEmpty { emit(.park(parkList)) }
    }

    func lowestUnusedID() -> Int {
        var id = 1
        while workspaces[id] != nil { id += 1 }
        return id
    }

    @discardableResult
    func ensureWorkspace(_ id: Int, name: String? = nil, special: Bool = false, monitor: Int? = nil, createdEmpty: Bool = false) -> Int {
        if workspaces[id] != nil { return id }
        var ws = Workspace(id: id, name: name ?? (special ? "special" : String(id)), monitor: monitor ?? focusedMonitor,
                           homeMonitorName: "", isSpecial: special, layout: LayoutState(.dwindle))
        let matched = rules(for: ws)
        if monitor == nil, let m = matched.compactMap(\.monitor).last.flatMap(resolveMonitor) { ws.monitor = m }
        ws.homeMonitorName = self.monitor(ws.monitor)?.name ?? ""
        ws.layout = LayoutState(LayoutKind(rawValue: matched.compactMap(\.layout).last ?? config.general.layout) ?? .dwindle)
        if case .master(var m) = ws.layout, let o = matched.compactMap(\.orientation).last {
            m.orientationOverride = o
            ws.layout = .master(m)
        }
        ws.persistent = matched.compactMap(\.persistent).last ?? false
        if name == nil, !special, let dn = matched.compactMap(\.defaultName).last { ws.name = dn }
        workspaces[id] = ws
        if createdEmpty, let cmd = matched.compactMap(\.onCreatedEmpty).last { emit(.spawn(cmd, token: nil)) }
        return id
    }

    func destroyIfUnused(_ id: Int) {
        guard let ws = workspaces[id], ws.windowIDs.isEmpty, !ws.persistent, !isVisible(id) else { return }
        if windows.values.contains(where: { $0.workspace == id }) { return }
        workspaces[id] = nil
    }

    func detach(_ id: WindowID) {
        guard let w = windows[id], var ws = workspaces[w.workspace] else { return }
        ws.layout.update { $0.remove(id) }
        ws.floating.removeAll { $0 == id }
        if ws.lastFocused == id { ws.lastFocused = nil }
        workspaces[ws.id] = ws
    }

    func attach(_ id: WindowID, to wsID: Int, focalPoint: Point? = nil) {
        guard var w = windows[id], var ws = workspaces[wsID] else { return }
        w.workspace = wsID
        windows[id] = w
        if w.isFloating {
            ws.floating.append(id)
        } else {
            let ctx = layoutContext(ws, focalPoint: focalPoint)
            ws.layout.update { $0.insert(id, ctx) }
        }
        workspaces[wsID] = ws
    }

    func facts(for w: ManagedWindow) -> WindowFacts {
        let mon = workspaces[w.workspace].flatMap { monitor($0.monitor) } ?? monitors.first
        let origin = mon?.frame.origin ?? .zero
        let frame = w.appliedFrame ?? w.lastFrame
        return WindowFacts(bundleID: w.bundleID, appName: w.appName, title: w.title, initialTitle: w.initialTitle,
                           isFloating: w.isFloating, isFullscreen: w.fullscreenMode != nil, isPinned: w.isPinned,
                           isFocused: focusedWindow == w.id, isModal: w.isModal, workspaceID: w.workspace,
                           workspaceName: workspaces[w.workspace]?.name,
                           monitorSize: mon?.frame.size ?? Size(width: 0, height: 0),
                           windowFrame: Rect(x: frame.x - origin.x, y: frame.y - origin.y, width: frame.width, height: frame.height),
                           cursor: cursor - origin)
    }

    func staticOutcome(for w: ManagedWindow) -> StaticRuleOutcome {
        var rules = config.windowRules
        if let extra = pidRules[w.pid] {
            for part in extra.split(separator: ";") {
                let text = part.trimmingCharacters(in: .whitespaces) + ", match:class .*"
                if let r = WindowRuleParser.parse(keyword: "windowrule", value: text, location: SourceLocation(file: "exec", line: 0)).rule {
                    rules.append(WindowRule(name: nil, matchers: r.matchers, effects: r.effects, location: r.location))
                }
            }
        }
        return RuleEngine.staticOutcome(rules, facts(for: w))
    }

    func resolveRuleWorkspace(_ selector: String) -> Int? {
        let s = selector.trimmingCharacters(in: .whitespaces)
        if let n = Int(s), n >= 1 { return ensureWorkspace(n) }
        if s.hasPrefix("name:") {
            let name = String(s.dropFirst(5))
            if let ws = workspaces.values.first(where: { !$0.isSpecial && $0.name == name }) { return ws.id }
            let id = nextNamedID
            nextNamedID += 1
            return ensureWorkspace(id, name: name)
        }
        if s == "special" || s.hasPrefix("special:") {
            let name = s == "special" ? "special" : String(s.dropFirst(8))
            if let ws = workspaces.values.first(where: { $0.isSpecial && $0.name == name }) { return ws.id }
            let id = name == "special" ? -99 : nextSpecialID
            if name != "special" { nextSpecialID += 1 }
            return ensureWorkspace(id, name: name, special: true)
        }
        return nil
    }

    func setMonitors(_ infos: [MonitorInfo]) {
        monitors = infos.sorted { $0.id < $1.id }
        guard let primary = monitors.first?.id else { return }
        let ids = Set(monitors.map(\.id))
        for (id, var ws) in workspaces {
            if let home = monitors.first(where: { $0.name == ws.homeMonitorName }) { ws.monitor = home.id }
            else if !ids.contains(ws.monitor) { ws.monitor = primary }
            workspaces[id] = ws
        }
        activeWorkspace = activeWorkspace.filter { ids.contains($0.key) && workspaces[$0.value]?.monitor == $0.key }
        activeSpecial = activeSpecial.filter { ids.contains($0.key) && workspaces[$0.value]?.monitor == $0.key }
        for m in monitors where activeWorkspace[m.id] == nil {
            let remembered = lastActiveByMonitorName[m.name].flatMap { workspaces[$0]?.monitor == m.id ? $0 : nil }
            let ruleDefault = config.workspaceRules.first { r in
                r.isDefault == true && r.monitor.flatMap(resolveMonitor) == m.id
            }.flatMap { r -> Int? in if case .id(let n) = r.selector { return n }; return nil }
            let hidden = workspaces.values.filter { $0.monitor == m.id && !$0.isSpecial && !activeWorkspace.values.contains($0.id) }.map(\.id).min()
            let chosen = remembered ?? ruleDefault ?? hidden ?? lowestUnusedID()
            ensureWorkspace(chosen, monitor: m.id)
            workspaces[chosen]?.monitor = m.id
            activeWorkspace[m.id] = chosen
            lastActiveByMonitorName[m.name] = chosen
        }
        if !ids.contains(focusedMonitor) { focusedMonitor = primary }
        refresh(Set(workspaces.keys))
        emit(.statusChanged)
    }

    func addWindow(_ s: WindowSnapshot) {
        guard windows[s.id] == nil, !ignored.contains(s.id), let first = monitors.first else { return }
        let homeMonitor = isStartingUp ? (monitorID(containing: s.frame.center) ?? focusedMonitor) : focusedMonitor
        var target = activeWorkspace[homeMonitor] ?? ensureWorkspace(lowestUnusedID(), monitor: homeMonitor)
        var w = ManagedWindow(id: s.id, pid: s.pid, bundleID: s.bundleID, appName: s.appName, title: s.title, initialTitle: s.title,
                              isModal: s.kind == .dialog, workspace: target, isFloating: s.kind == .dialog, floatingFrame: s.frame,
                              lastFrame: s.frame)
        let outcome = staticOutcome(for: w)
        if outcome.ignore { ignored.insert(s.id); return }
        var silent = false
        if let t = outcome.workspace, let id = resolveRuleWorkspace(t.selector) {
            target = id
            silent = t.silent
        }
        if let m = outcome.monitor.flatMap(resolveMonitor), let active = activeWorkspace[m] { target = active }
        w.workspace = target
        w.isFloating = outcome.floating ?? (s.kind == .dialog)
        let mon = workspaces[target].flatMap { monitor($0.monitor) } ?? first
        var frame = s.frame
        let v = mon.visibleFrame
        frame.x = min(max(frame.x, v.minX), max(v.minX, v.maxX - frame.width))
        frame.y = min(max(frame.y, v.minY), max(v.minY, v.maxY - frame.height))
        let f = facts(for: w)
        if let size = outcome.size.flatMap({ RuleEngine.resolveSize($0, f) }) { frame.width = size.width; frame.height = size.height }
        if let move = outcome.move.flatMap({ RuleEngine.resolveMove($0, f) }) { frame.x = mon.frame.x + move.x; frame.y = mon.frame.y + move.y }
        if outcome.center, let ws = workspaces[target] {
            let area = workArea(for: ws)
            frame.x = area.x + (area.width - frame.width) / 2
            frame.y = area.y + (area.height - frame.height) / 2
        }
        w.floatingFrame = frame
        w.everFloated = w.isFloating
        if w.isFloating { w.appliedFrame = s.frame }
        if outcome.pseudo { w.isPseudo = true; w.pseudoSize = s.frame.size }
        w.isPinned = outcome.pin && w.isFloating
        if let mode = outcome.fullscreenMode {
            for other in workspaces[target]?.windowIDs ?? [] { windows[other]?.fullscreenMode = nil }
            w.fullscreenMode = mode
        }
        windows[s.id] = w
        pidRules[s.pid] = nil
        attach(s.id, to: target)
        if !isVisible(target) && !silent && outcome.workspace != nil { showWorkspace(target) }
        refresh([target], opened: s.id)
        if isVisible(target) {
            if !outcome.noInitialFocus { focusWindow(s.id, warp: false, emitEffect: true) }
        } else if let previous = focusedWindow {
            emit(.focus(previous))
        }
        emit(.statusChanged)
        emit(.saveState)
    }

    func showWorkspace(_ id: Int) {
        if workspaces[id]?.isSpecial == true {
            activeSpecial[workspaces[id]!.monitor] = id
        } else if let m = workspaces[id]?.monitor {
            let old = activeWorkspace[m]
            activeWorkspace[m] = id
            if let old { refresh([old]) }
        }
    }

    func focusCandidate(onWorkspace wsID: Int, near point: Point) -> WindowID? {
        guard let ws = workspaces[wsID] else { return nil }
        let ids = ws.windowIDs.filter { windows[$0]?.suspended == nil }
        switch config.input.focusOnClose {
        case 1:
            let boxes = targetFrames(ws)
            if let hit = ids.reversed().first(where: { boxes[$0]?.contains(cursor) == true }) { return hit }
        case 2:
            if let recent = focusHistory.reversed().first(where: ids.contains) { return recent }
        default:
            break
        }
        return ws.layout.current.nextFocusCandidate(near: point, layoutContext(ws)) ?? ws.floating.last
    }

    func removeWindow(_ id: WindowID) {
        ignored.remove(id)
        guard let w = windows[id] else { return }
        let center = (w.appliedFrame ?? w.lastFrame).center
        detach(id)
        windows[id] = nil
        focusHistory.removeAll { $0 == id }
        if focusedWindow == id {
            focusedWindow = nil
            if isVisible(w.workspace), let next = focusCandidate(onWorkspace: w.workspace, near: center) {
                focusWindow(next, warp: false, emitEffect: true)
            }
        }
        refresh([w.workspace])
        destroyIfUnused(w.workspace)
        emit(.statusChanged)
        emit(.saveState)
    }

    func focusWindow(_ id: WindowID?, warp: Bool, emitEffect: Bool = true) {
        guard let id, let w = windows[id] else {
            focusedWindow = nil
            emit(.statusChanged)
            return
        }
        focusedWindow = id
        focusHistory.removeAll { $0 == id }
        focusHistory.append(id)
        workspaces[w.workspace]?.lastFocused = id
        if let m = workspaces[w.workspace]?.monitor { focusedMonitor = m }
        if emitEffect { emit(.focus(id)) }
        if warp && !config.cursor.noWarps, let f = windows[id]?.appliedFrame, !f.contains(cursor) {
            cursor = f.center
            emit(.warpCursor(f.center))
        }
        emit(.statusChanged)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter WorldCoreTests`
Expected: PASS (the spawn test shows as skipped).

- [ ] **Step 6: Commit**

```bash
git add Sources/HyprCore/World Tests/HyprCoreTests/WorldCoreTests.swift
git commit -m "feat: add the world core with rules, layout pass and parking"
```

---
### Task 14: World workspaces, monitors and events

**Files:**
- Create: `Sources/HyprCore/World/World+Workspaces.swift`, `Sources/HyprCore/World/World+Events.swift`
- Modify: `Sources/HyprCore/World/World.swift` (the `apply` switch, the `addWindow` show call, delete `showWorkspace`)
- Test: `Tests/HyprCoreTests/WorldWorkspaceEventTests.swift`

**Interfaces:**
- Consumes: Task 13.
- Produces (used by Tasks 15 and 16):

```swift
extension World {
    func resolveMonitor(_ sel: MonitorSelector) -> Int?
    func monitorInDirection(from id: Int, _ d: Direction) -> Int?
    var currentWorkspaceID: Int? { get }
    func resolveWorkspace(_ sel: WorkspaceSelector) -> Int?
    func switchWorkspace(_ requested: Int, focusing: WindowID? = nil, emitFocus: Bool = true)
    func toggleSpecial(_ id: Int, show: Bool? = nil, on monitor: Int? = nil, focusing: WindowID? = nil, emitFocus: Bool = true)
    func moveWindow(_ id: WindowID, toWorkspace target: Int, silent: Bool, focalPoint: Point? = nil)
    func focusMonitor(_ id: Int)
    func moveWorkspace(_ wsID: Int, toMonitor target: Int)
    func swapActiveWorkspaces(_ a: Int, _ b: Int)
    func focusWorkspaceOnCurrentMonitor(_ wsID: Int)
    func setFloating(_ id: WindowID, _ floating: Bool)
    func windowAt(_ p: Point) -> WindowID?
    func closeSpecialIfEmpty(_ wsID: Int)
    func suspend(_ id: WindowID, _ reason: SuspendReason); func resume(_ id: WindowID)
}
```

Behavior (spec sections 4.2, 4.5, 5.1, 5.2, 8):
- `resolveWorkspace`: `.id(n)` gives n (n >= 1); `.relative(n)` the current id + n (at least 1); `.name` and `.special` go through `resolveRuleWorkspace` (they create); `.previous` and `.previousPerMonitor` the remembered ids; `.existing(n)` steps n through the sorted regular workspace ids from the current one, wrapping; `.existingAbsolute(n)` the nth; `.onMonitor(n, includeEmpty: false)` steps through the focused monitor's workspaces; with `includeEmpty: true` it is current + n; `.onMonitorAbsolute(n)` the nth on the focused monitor; `.empty(_, next)` the lowest id with no windows (above the current id when `next`).
- `switchWorkspace`: a switch to the current workspace goes to the previous one when `binds:workspace_back_and_forth`, else does nothing; a missing workspace is created (`createdEmpty: true`) on the focused monitor unless a rule binds it; a special workspace is shown with `toggleSpecial`; a workspace already active on another monitor only moves focus there; otherwise it becomes active on its monitor, `previousWorkspace` and the per-monitor previous are updated, pinned floating windows of the old workspace move along, `binds:hide_special_on_workspace_change` hides the monitor's special workspace, the new workspace refreshes with `.workspaceIn(leftward: new id > old id)`, the old one refreshes (parks) and is destroyed when unused; focus goes to `focusing`, else the workspace's last focused window, else its first window (none: `focusedWindow = nil`); the cursor warps only when `cursor:warp_on_change_workspace > 0`.
- `toggleSpecial`: show puts the special workspace on the monitor (moving it from another monitor if needed), hides another special shown there, refreshes it with `.workspaceIn(leftward: true)`, raises each of its windows and focuses `focusing` or its last focused or first window; hide parks it, focuses the regular workspace's last focused window and destroys it when unused.
- `moveWindow(toWorkspace:)`: clears fullscreen, detaches, attaches (with `focalPoint` when given); silent: refresh both and, if the window was focused, focus the source candidate; non-silent: show the target (special or regular) focusing the window; destroy the source when unused and close an emptied special source.
- `focusMonitor`: focus the monitor's special or regular workspace's last focused or first window, set the focused monitor, warp the cursor to the monitor center when the cursor is not on that monitor.
- `moveWorkspace`: the workspace becomes active on the target monitor (its home monitor name updates); when it was active on its old monitor, that monitor shows its lowest other workspace or a new one.
- `swapActiveWorkspaces` and `focusWorkspaceOnCurrentMonitor` as in the dispatcher table (`hyprland-config-reference.md`).
- `setFloating`: no-op when unchanged or suspended; when it becomes floating and never floated, its floating frame is the work area scaled to 60% and centered; pin is cleared for tiled windows.
- Events: `windowDisappeared` also closes an emptied special workspace (`misc:close_special_on_empty`); `windowSuspended` detaches (focus moves to the candidate), `windowResumed` re-attaches (minimized windows go to the current workspace and get focus without an effect); `appHidden(byUser: true)` with `macos:unhide_hidden_apps` emits `.unhideApp`, otherwise suspends the app's windows; `appUnhidden` resumes them; `appTerminated` removes them; `windowTitleChanged(early: true)` on a window whose initial title was empty re-runs static rules (`ignore`, float or tile, workspace); `windowFrameChanged` on a floating window stores the frame and moves the window to the workspace of the monitor under its center; on a tiled visible window a user-driven size change resizes through the layout with the moved edges as corner and the edge movement as delta (the window itself is skipped, the rest refreshes), a user-driven move only marks a drag; an app-driven change re-applies the target frame once per target (`refitTarget`); `dragEnded` snaps a resized window, drops a moved window on the tile under the cursor (dwindle: re-insert with the cursor as focal point, other layouts: swap with the tiled window under the cursor, another monitor: attach to its workspace at the cursor) or snaps it back when the cursor is inside its own tile; `focusChanged` to a window on a hidden workspace shows that workspace when `misc:focus_on_activate` (no `.focus` effect), then records the focus without an effect; `cursorMoved` stores the cursor and, with `input:follow_mouse = 1` and no drag, focuses the window under it.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/WorldWorkspaceEventTests.swift`:

```swift
import Testing
@testable import HyprCore

let ultrawide = MonitorInfo(id: 1, name: "PHL 499P9", frame: Rect(x: 1512, y: 0, width: 3440, height: 1440),
                            visibleFrame: Rect(x: 1512, y: 0, width: 3440, height: 1440))
let full = Rect(x: 0, y: 32, width: 1512, height: 950)
let leftHalf = Rect(x: 0, y: 32, width: 756, height: 950)
let rightHalf = Rect(x: 756, y: 32, width: 756, height: 950)

func reasons(_ effects: [Effect]) -> [WindowID: FrameReason] {
    var out: [WindowID: FrameReason] = [:]
    for case .setFrames(let changes) in effects { for c in changes { out[c.id] = c.reason } }
    return out
}

func hasFocusEffect(_ effects: [Effect]) -> Bool {
    effects.contains { if case .focus = $0 { return true }; return false }
}

func twoWindows(_ text: String = "") -> World {
    let w = world(text)
    _ = w.handle(.windowAppeared(snap(1)))
    _ = w.handle(.windowAppeared(snap(2, pid: 200)))
    return w
}

@Suite struct WorldWorkspaceEventTests {
    @Test func switchingParksAndRestores() {
        let w = twoWindows()
        w.switchWorkspace(2)
        let away = w.takeEffects()
        #expect(parks(away).keys.sorted() == [1, 2])
        #expect(w.focusedWindow == nil)
        w.switchWorkspace(1)
        let back = w.takeEffects()
        #expect(frames(back) == [1: leftHalf, 2: rightHalf])
        #expect(reasons(back)[1] == .workspaceIn(leftward: false))
        #expect(w.workspaces[2] == nil)
        #expect(back.contains(.focus(2)))
    }

    @Test func backAndForth() {
        let w = twoWindows("binds:workspace_back_and_forth = true")
        w.switchWorkspace(2)
        w.switchWorkspace(2)
        #expect(w.activeWorkspace[0] == 1)
    }

    @Test func selectors() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        w.switchWorkspace(3)
        _ = w.handle(.windowAppeared(snap(3, pid: 300)))
        w.switchWorkspace(5)
        _ = w.handle(.windowAppeared(snap(5, pid: 500)))
        _ = w.takeEffects()
        #expect(w.resolveWorkspace(.existing(1)) == 1)
        #expect(w.resolveWorkspace(.existing(-1)) == 3)
        #expect(w.resolveWorkspace(.empty(currentMonitorOnly: false, next: false)) == 2)
        #expect(w.resolveWorkspace(.previous) == 3)
        #expect(w.resolveWorkspace(.relative(2)) == 7)
        let web = w.resolveWorkspace(.name("web"))
        #expect(web == 1_000_000 && w.workspaces[1_000_000]?.name == "web")
    }

    @Test func moveToWorkspaceFollows() {
        let w = twoWindows()
        w.moveWindow(2, toWorkspace: 3, silent: false)
        let e = w.takeEffects()
        #expect(w.activeWorkspace[0] == 3)
        #expect(frames(e)[2] == full)
        #expect(parks(e)[1] != nil)
        #expect(w.focusedWindow == 2)
    }

    @Test func moveToWorkspaceSilent() {
        let w = twoWindows()
        w.moveWindow(2, toWorkspace: 3, silent: true)
        let e = w.takeEffects()
        #expect(w.activeWorkspace[0] == 1)
        #expect(frames(e)[1] == full)
        #expect(parks(e)[2] != nil)
        #expect(e.contains(.focus(1)))
    }

    @Test func specialWorkspaceScaleToggleAndCloseOnEmpty() {
        let w = world("dwindle:special_scale_factor = 0.8")
        _ = w.handle(.windowAppeared(snap(1)))
        let special = w.resolveWorkspace(.special("magic"))!
        w.moveWindow(1, toWorkspace: special, silent: false)
        let shown = w.takeEffects()
        #expect(w.activeSpecial[0] == special)
        #expect(frames(shown)[1] == Rect(x: 151, y: 127, width: 1210, height: 760))
        w.toggleSpecial(special)
        #expect(parks(w.takeEffects())[1] != nil)
        w.toggleSpecial(special)
        _ = w.takeEffects()
        _ = w.handle(.windowDisappeared(1))
        #expect(w.activeSpecial[0] == nil)
    }

    @Test func pinnedFloatingWindowFollowsSwitch() {
        let w = world("windowrule = float on, match:class Calculator\nwindowrule = pin on, match:class Calculator")
        _ = w.handle(.windowAppeared(snap(5, app: "Calculator", bundle: "com.apple.calculator", pid: 50)))
        w.switchWorkspace(2)
        let e = w.takeEffects()
        #expect(w.windows[5]?.workspace == 2)
        #expect(parks(e)[5] == nil)
    }

    @Test func unplugAndReplugKeepsWorkspaces() {
        let w = world("workspace = 6, monitor:1, default:true", monitors: [laptop, ultrawide])
        #expect(w.activeWorkspace[1] == 6)
        w.focusMonitor(1)
        _ = w.takeEffects()
        _ = w.handle(.windowAppeared(snap(9, pid: 900)))
        #expect(w.windows[9]?.workspace == 6)
        let unplug = w.handle(.monitorsChanged([laptop]))
        #expect(parks(unplug)[9] != nil)
        #expect(w.workspaces[6]?.monitor == 0)
        let replug = w.handle(.monitorsChanged([laptop, ultrawide]))
        #expect(w.activeWorkspace[1] == 6)
        #expect(frames(replug)[9] == ultrawide.visibleFrame)
    }

    @Test func focusMonitorWarpsAndSwapActive() {
        let w = world(monitors: [laptop, ultrawide])
        w.focusMonitor(1)
        let e = w.takeEffects()
        #expect(w.focusedMonitor == 1)
        #expect(e.contains(.warpCursor(Point(x: 3232, y: 720))))
        w.swapActiveWorkspaces(0, 1)
        #expect(w.activeWorkspace[0] == 2 && w.activeWorkspace[1] == 1)
    }

    @Test func minimizeAndRestore() {
        let w = twoWindows()
        let gone = w.handle(.windowSuspended(2, .minimized))
        #expect(frames(gone) == [1: full])
        #expect(gone.contains(.focus(1)))
        let back = w.handle(.windowResumed(2))
        #expect(frames(back) == [1: leftHalf, 2: rightHalf])
    }

    @Test func userHiddenAppIsUnhiddenWhenConfigured() {
        let w = twoWindows("macos:unhide_hidden_apps = true")
        #expect(w.handle(.appHidden(pid: 100, byUser: true)).contains(.unhideApp(100)))
        let plain = twoWindows()
        _ = plain.handle(.appHidden(pid: 100, byUser: true))
        #expect(plain.windows[1]?.suspended == .appHidden)
        _ = plain.handle(.appUnhidden(pid: 100))
        #expect(plain.windows[1]?.suspended == nil)
    }

    @Test func earlyTitleRerunsRules() {
        let w = world("windowrule = float on, match:title Picture-in-Picture")
        _ = w.handle(.windowAppeared(snap(1, title: "")))
        #expect(w.windows[1]?.isFloating == false)
        _ = w.handle(.windowTitleChanged(1, "Picture-in-Picture", early: true))
        #expect(w.windows[1]?.isFloating == true)
        _ = w.handle(.windowAppeared(snap(2, pid: 200, title: "")))
        _ = w.handle(.windowTitleChanged(2, "Picture-in-Picture", early: false))
        #expect(w.windows[2]?.isFloating == false)
    }

    @Test func userResizeMovesTheSplit() {
        let w = twoWindows()
        let e = w.handle(.windowFrameChanged(1, Rect(x: 0, y: 32, width: 856, height: 950), userDriven: true))
        #expect(frames(e) == [2: Rect(x: 856, y: 32, width: 656, height: 950)])
        let end = w.handle(.dragEnded(cursor: Point(x: 856, y: 500)))
        #expect(frames(end).isEmpty)
    }

    @Test func userMoveDropsOnAnotherTile() {
        let w = twoWindows()
        _ = w.handle(.windowFrameChanged(1, Rect(x: 300, y: 200, width: 756, height: 950), userDriven: true))
        let e = w.handle(.dragEnded(cursor: Point(x: 1300, y: 800)))
        #expect(frames(e) == [1: rightHalf, 2: leftHalf])
    }

    @Test func appDrivenMoveIsRefitOnce() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        let first = w.handle(.windowFrameChanged(1, Rect(x: 10, y: 40, width: 800, height: 600), userDriven: false))
        #expect(frames(first) == [1: full])
        let second = w.handle(.windowFrameChanged(1, Rect(x: 10, y: 40, width: 800, height: 600), userDriven: false))
        #expect(frames(second).isEmpty)
    }

    @Test func outsideActivationShowsWorkspaceWithoutFocusEffect() {
        let w = twoWindows()
        w.moveWindow(2, toWorkspace: 3, silent: true)
        _ = w.takeEffects()
        let e = w.handle(.focusChanged(2))
        #expect(w.activeWorkspace[0] == 3)
        #expect(!hasFocusEffect(e))
        #expect(w.focusedWindow == 2)
    }

    @Test func followMouse() {
        let on = twoWindows("input:follow_mouse = 1")
        #expect(on.handle(.cursorMoved(Point(x: 100, y: 500))).contains(.focus(1)))
        let off = twoWindows("input:follow_mouse = 0")
        #expect(!hasFocusEffect(off.handle(.cursorMoved(Point(x: 100, y: 500)))))
    }

    @Test func appTerminationRemovesItsWindows() {
        let w = twoWindows()
        let e = w.handle(.appTerminated(pid: 100))
        #expect(w.windows[1] == nil)
        #expect(frames(e) == [2: full])
    }

    @Test func windowClosedDuringDragLeavesWorldClean() {
        let w = twoWindows()
        _ = w.handle(.focusChanged(1))
        _ = w.handle(.windowFrameChanged(1, Rect(x: 300, y: 200, width: 756, height: 950), userDriven: true))
        let gone = w.handle(.windowDisappeared(1))
        #expect(frames(gone) == [2: full])
        #expect(w.focusedWindow == 2)
        #expect(frames(w.handle(.dragEnded(cursor: Point(x: 1300, y: 800)))).isEmpty)
        #expect(w.handle(.windowFrameChanged(1, Rect(x: 0, y: 0, width: 10, height: 10), userDriven: true)).isEmpty)
        #expect(w.handle(.windowTitleChanged(1, "late", early: true)).isEmpty)
        #expect(w.handle(.windowDisappeared(1)).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WorldWorkspaceEventTests`
Expected: FAIL, "value of type 'World' has no member 'switchWorkspace'".

- [ ] **Step 3: Implement workspaces and monitors**

`Sources/HyprCore/World/World+Workspaces.swift`:

```swift
import Foundation

extension World {
    func resolveMonitor(_ sel: MonitorSelector) -> Int? {
        switch sel {
        case .current: return focusedMonitor
        case .id(let n): return monitor(n)?.id
        case .name(let n): return resolveMonitor(n)
        case .relative(let n):
            let sorted = monitors.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
            guard let i = sorted.firstIndex(where: { $0.id == focusedMonitor }) else { return nil }
            return sorted[((i + n) % sorted.count + sorted.count) % sorted.count].id
        case .direction(let d): return monitorInDirection(from: focusedMonitor, d)
        }
    }

    func monitorInDirection(from id: Int, _ d: Direction) -> Int? {
        guard let f = monitor(id)?.frame else { return nil }
        let candidates = monitors.filter { o in
            guard o.id != id else { return false }
            let g = o.frame
            switch d {
            case .left: return g.maxX <= f.minX + 1 && g.maxY > f.minY && g.minY < f.maxY
            case .right: return g.minX >= f.maxX - 1 && g.maxY > f.minY && g.minY < f.maxY
            case .up: return g.maxY <= f.minY + 1 && g.maxX > f.minX && g.minX < f.maxX
            case .down: return g.minY >= f.maxY - 1 && g.maxX > f.minX && g.minX < f.maxX
            }
        }
        func distance(_ g: Rect) -> Double {
            let a = g.center, b = f.center
            return (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
        }
        return candidates.min { distance($0.frame) < distance($1.frame) }?.id
    }

    var currentWorkspaceID: Int? { activeWorkspace[focusedMonitor] }

    func resolveWorkspace(_ sel: WorkspaceSelector) -> Int? {
        let current = currentWorkspaceID ?? 1
        let regular = workspaces.values.filter { !$0.isSpecial }.map(\.id).sorted()
        let onMonitor = regular.filter { workspaces[$0]?.monitor == focusedMonitor }
        func step(_ list: [Int], _ n: Int) -> Int? {
            guard !list.isEmpty else { return nil }
            guard let i = list.firstIndex(of: current) else { return list.first }
            return list[((i + n) % list.count + list.count) % list.count]
        }
        switch sel {
        case .id(let n): return n >= 1 ? n : nil
        case .relative(let n): return max(1, current + n)
        case .name(let s): return resolveRuleWorkspace("name:" + s)
        case .special(let n): return resolveRuleWorkspace(n.map { "special:" + $0 } ?? "special")
        case .previous: return previousWorkspace
        case .previousPerMonitor: return previousPerMonitor[focusedMonitor]
        case .existing(let n): return step(regular, n)
        case .existingAbsolute(let n): return regular.indices.contains(n - 1) ? regular[n - 1] : nil
        case .onMonitor(let n, let includeEmpty): return includeEmpty ? max(1, current + n) : step(onMonitor, n)
        case .onMonitorAbsolute(let n, _): return onMonitor.indices.contains(n - 1) ? onMonitor[n - 1] : nil
        case .empty(_, let next):
            let used = Set(workspaces.values.filter { !$0.isSpecial && !$0.windowIDs.isEmpty }.map(\.id))
            var candidate = next ? current + 1 : 1
            while used.contains(candidate) { candidate += 1 }
            return candidate
        }
    }

    func switchWorkspace(_ requested: Int, focusing: WindowID? = nil, emitFocus: Bool = true) {
        var target = requested
        let current = currentWorkspaceID
        if target == current {
            guard config.bindsOptions.workspaceBackAndForth, let previous = previousWorkspace else { return }
            target = previous
        }
        ensureWorkspace(target, createdEmpty: workspaces[target] == nil)
        guard let ws = workspaces[target] else { return }
        if ws.isSpecial {
            toggleSpecial(target, show: true, focusing: focusing, emitFocus: emitFocus)
            return
        }
        let mon = ws.monitor
        let old = activeWorkspace[mon]
        if old == target {
            focusedMonitor = mon
            focusWindow(focusing ?? ws.lastFocused ?? ws.windowIDs.first, warp: true, emitEffect: emitFocus)
            focusedMonitor = mon
            return
        }
        previousWorkspace = current
        if let old { previousPerMonitor[mon] = old }
        activeWorkspace[mon] = target
        if let name = monitor(mon)?.name { lastActiveByMonitorName[name] = target }
        focusedMonitor = mon
        if let old {
            for id in workspaces[old]?.floating ?? [] where windows[id]?.isPinned == true {
                detach(id)
                attach(id, to: target)
            }
        }
        if config.bindsOptions.hideSpecialOnWorkspaceChange, let special = activeSpecial[mon] {
            activeSpecial[mon] = nil
            refresh([special])
        }
        refresh([target], reason: .workspaceIn(leftward: target > (old ?? target)))
        if let old {
            refresh([old])
            destroyIfUnused(old)
        }
        let next = workspaces[target]
        focusWindow(focusing ?? next?.lastFocused ?? next?.windowIDs.first, warp: config.cursor.warpOnChangeWorkspace > 0, emitEffect: emitFocus)
        focusedMonitor = mon
        emit(.saveState)
    }

    func toggleSpecial(_ id: Int, show: Bool? = nil, on monitorID: Int? = nil, focusing: WindowID? = nil, emitFocus: Bool = true) {
        guard workspaces[id] != nil else { return }
        let mon = monitorID ?? focusedMonitor
        let shown = activeSpecial[mon] == id
        if show ?? !shown {
            guard !shown else { return }
            if let other = activeSpecial.first(where: { $0.value == id })?.key { activeSpecial[other] = nil }
            if let previous = activeSpecial[mon] {
                activeSpecial[mon] = nil
                refresh([previous])
            }
            workspaces[id]?.monitor = mon
            workspaces[id]?.homeMonitorName = monitor(mon)?.name ?? ""
            activeSpecial[mon] = id
            refresh([id], reason: .workspaceIn(leftward: true))
            for w in workspaces[id]?.windowIDs ?? [] { emit(.raise(w)) }
            if let c = focusing ?? workspaces[id]?.lastFocused ?? workspaces[id]?.windowIDs.first {
                focusWindow(c, warp: false, emitEffect: emitFocus)
            }
        } else {
            guard shown else { return }
            activeSpecial[mon] = nil
            refresh([id])
            let regular = activeWorkspace[mon].flatMap { workspaces[$0] }
            focusWindow(regular?.lastFocused ?? regular?.windowIDs.first, warp: false, emitEffect: emitFocus)
            destroyIfUnused(id)
        }
        emit(.statusChanged)
    }

    func closeSpecialIfEmpty(_ wsID: Int) {
        guard config.misc.closeSpecialOnEmpty, let ws = workspaces[wsID], ws.isSpecial, ws.windowIDs.isEmpty,
              let mon = activeSpecial.first(where: { $0.value == wsID })?.key else { return }
        toggleSpecial(wsID, show: false, on: mon)
    }

    func moveWindow(_ id: WindowID, toWorkspace target: Int, silent: Bool, focalPoint: Point? = nil) {
        guard let w = windows[id], w.workspace != target else { return }
        let source = w.workspace
        let center = (w.appliedFrame ?? w.lastFrame).center
        let wasFocused = focusedWindow == id
        ensureWorkspace(target)
        windows[id]?.fullscreenMode = nil
        detach(id)
        attach(id, to: target, focalPoint: focalPoint)
        if silent {
            refresh([source, target])
            if wasFocused {
                focusWindow(isVisible(source) ? focusCandidate(onWorkspace: source, near: center) : nil, warp: false, emitEffect: true)
            }
        } else if workspaces[target]?.isSpecial == true {
            toggleSpecial(target, show: true, focusing: id)
            refresh([source])
        } else {
            switchWorkspace(target, focusing: id)
            refresh([source, target])
        }
        destroyIfUnused(source)
        closeSpecialIfEmpty(source)
        emit(.saveState)
    }

    func focusMonitor(_ id: Int) {
        guard let m = monitor(id) else { return }
        focusedMonitor = id
        let wsID = activeSpecial[id] ?? activeWorkspace[id]
        let candidate = wsID.flatMap { workspaces[$0]?.lastFocused ?? workspaces[$0]?.windowIDs.first }
        focusWindow(candidate, warp: false, emitEffect: true)
        focusedMonitor = id
        if !m.frame.contains(cursor) {
            cursor = m.frame.center
            emit(.warpCursor(m.frame.center))
        }
    }

    func moveWorkspace(_ wsID: Int, toMonitor target: Int) {
        guard var ws = workspaces[wsID], !ws.isSpecial, ws.monitor != target, let tm = monitor(target) else { return }
        let from = ws.monitor
        let wasActive = activeWorkspace[from] == wsID
        ws.monitor = target
        ws.homeMonitorName = tm.name
        workspaces[wsID] = ws
        var affected: Set<Int> = [wsID]
        if let shown = activeWorkspace[target] { affected.insert(shown) }
        activeWorkspace[target] = wsID
        lastActiveByMonitorName[tm.name] = wsID
        if wasActive {
            let others = workspaces.values.filter { $0.monitor == from && !$0.isSpecial && $0.id != wsID }.map(\.id)
            let replacement = others.min() ?? ensureWorkspace(lowestUnusedID(), monitor: from)
            activeWorkspace[from] = replacement
            affected.insert(replacement)
        }
        refresh(affected)
        emit(.statusChanged)
        emit(.saveState)
    }

    func swapActiveWorkspaces(_ a: Int, _ b: Int) {
        guard a != b, let wa = activeWorkspace[a], let wb = activeWorkspace[b], let ma = monitor(a), let mb = monitor(b) else { return }
        workspaces[wa]?.monitor = b
        workspaces[wa]?.homeMonitorName = mb.name
        workspaces[wb]?.monitor = a
        workspaces[wb]?.homeMonitorName = ma.name
        activeWorkspace[a] = wb
        activeWorkspace[b] = wa
        lastActiveByMonitorName[ma.name] = wb
        lastActiveByMonitorName[mb.name] = wa
        refresh([wa, wb])
        emit(.statusChanged)
        emit(.saveState)
    }

    func focusWorkspaceOnCurrentMonitor(_ wsID: Int) {
        ensureWorkspace(wsID, monitor: focusedMonitor)
        guard let ws = workspaces[wsID] else { return }
        if ws.monitor == focusedMonitor {
            switchWorkspace(wsID)
            return
        }
        let here = focusedMonitor
        if activeWorkspace[ws.monitor] == wsID {
            swapActiveWorkspaces(here, ws.monitor)
        } else {
            moveWorkspace(wsID, toMonitor: here)
        }
        focusWindow(workspaces[wsID]?.lastFocused ?? workspaces[wsID]?.windowIDs.first, warp: false, emitEffect: true)
        focusedMonitor = here
    }

    func setFloating(_ id: WindowID, _ floating: Bool) {
        guard var w = windows[id], w.isFloating != floating, w.suspended == nil else { return }
        let wsID = w.workspace
        detach(id)
        if floating, !w.everFloated, let ws = workspaces[wsID] {
            let area = workArea(for: ws)
            w.floatingFrame = Rect(x: area.x + area.width * 0.2, y: area.y + area.height * 0.2, width: area.width * 0.6, height: area.height * 0.6).rounded()
        }
        w.everFloated = w.everFloated || floating
        w.isFloating = floating
        if !floating { w.isPinned = false }
        windows[id] = w
        attach(id, to: wsID)
        refresh([wsID])
        emit(.saveState)
    }

    func windowAt(_ p: Point) -> WindowID? {
        guard let m = monitorID(containing: p) else { return nil }
        for wsID in [activeSpecial[m], activeWorkspace[m]].compactMap({ $0 }) {
            guard let ws = workspaces[wsID] else { continue }
            let frames = targetFrames(ws)
            if let hit = ws.floating.reversed().first(where: { frames[$0]?.contains(p) == true }) { return hit }
            if let hit = ws.tiledIDs.first(where: { frames[$0]?.contains(p) == true }) { return hit }
        }
        return nil
    }
}
```

- [ ] **Step 4: Implement the events**

`Sources/HyprCore/World/World+Events.swift`:

```swift
import Foundation

extension World {
    func suspend(_ id: WindowID, _ reason: SuspendReason) {
        guard var w = windows[id], w.suspended == nil else { return }
        let center = (w.appliedFrame ?? w.lastFrame).center
        detach(id)
        w.suspended = reason
        w.isParked = false
        w.appliedFrame = nil
        windows[id] = w
        if focusedWindow == id {
            focusedWindow = nil
            if isVisible(w.workspace) {
                focusWindow(focusCandidate(onWorkspace: w.workspace, near: center), warp: false, emitEffect: true)
            }
        }
        refresh([w.workspace])
        emit(.saveState)
    }

    func resume(_ id: WindowID) {
        guard var w = windows[id], let reason = w.suspended else { return }
        w.suspended = nil
        if reason == .minimized, let current = currentWorkspaceID { w.workspace = current }
        windows[id] = w
        ensureWorkspace(w.workspace)
        attach(id, to: w.workspace)
        refresh([w.workspace])
        if reason == .minimized { focusWindow(id, warp: false, emitEffect: false) }
        emit(.saveState)
    }

    func appHidden(_ pid: Int32, byUser: Bool) {
        if byUser && config.macos.unhideHiddenApps {
            emit(.unhideApp(pid))
            return
        }
        for id in windows.values.filter({ $0.pid == pid }).map(\.id) { suspend(id, .appHidden) }
    }

    func retitle(_ id: WindowID, _ title: String, early: Bool) {
        guard var w = windows[id] else { return }
        w.title = title
        let rerun = early && w.initialTitle.isEmpty && !title.isEmpty
        if rerun { w.initialTitle = title }
        windows[id] = w
        emit(.statusChanged)
        guard rerun else { return }
        let outcome = staticOutcome(for: w)
        if outcome.ignore {
            detach(id)
            windows[id] = nil
            ignored.insert(id)
            focusHistory.removeAll { $0 == id }
            if focusedWindow == id { focusedWindow = nil }
            refresh([w.workspace])
            return
        }
        if let floating = outcome.floating, floating != w.isFloating { setFloating(id, floating) }
        if let t = outcome.workspace, let target = resolveRuleWorkspace(t.selector), target != w.workspace {
            moveWindow(id, toWorkspace: target, silent: t.silent)
        }
    }

    func frameChanged(_ id: WindowID, _ frame: Rect, userDriven: Bool) {
        guard var w = windows[id], w.suspended == nil, !w.isParked else { return }
        w.lastFrame = frame
        if w.isFloating {
            w.floatingFrame = frame
            w.appliedFrame = frame
            windows[id] = w
            if let m = monitorID(containing: frame.center), m != workspaces[w.workspace]?.monitor,
               let target = activeSpecial[m] ?? activeWorkspace[m] {
                detach(id)
                attach(id, to: target)
            }
            emit(.saveState)
            return
        }
        windows[id] = w
        guard isVisible(w.workspace), let applied = w.appliedFrame, !applied.isClose(to: frame, tolerance: 2) else { return }
        guard userDriven else {
            if w.refitTarget.map({ !$0.isClose(to: applied) }) ?? true {
                windows[id]?.refitTarget = applied
                emit(.setFrames([FrameChange(id: id, frame: applied, reason: .layout)]))
            }
            return
        }
        let leftMoved = abs(frame.minX - applied.minX) > 2, rightMoved = abs(frame.maxX - applied.maxX) > 2
        let topMoved = abs(frame.minY - applied.minY) > 2, bottomMoved = abs(frame.maxY - applied.maxY) > 2
        let resized = abs(frame.width - applied.width) > 2 || abs(frame.height - applied.height) > 2
        dragging = id
        guard resized, var ws = workspaces[w.workspace] else {
            dragIsResize = false
            return
        }
        dragIsResize = true
        let corner: Corner = topMoved ? (leftMoved ? .topLeft : .topRight) : (leftMoved ? .bottomLeft : .bottomRight)
        let delta = Point(x: leftMoved ? frame.minX - applied.minX : (rightMoved ? frame.maxX - applied.maxX : 0),
                          y: topMoved ? frame.minY - applied.minY : (bottomMoved ? frame.maxY - applied.maxY : 0))
        let ctx = layoutContext(ws)
        ws.layout.update { $0.resize(id, by: delta, corner: corner, ctx) }
        workspaces[ws.id] = ws
        windows[id]?.appliedFrame = frame
        refresh([ws.id], skip: id)
    }

    func endDrag(at point: Point) {
        cursor = point
        guard let id = dragging else { return }
        dragging = nil
        let wasResize = dragIsResize
        dragIsResize = false
        guard var w = windows[id], !w.isFloating, let ws = workspaces[w.workspace] else { return }
        w.appliedFrame = w.lastFrame
        windows[id] = w
        let boxes = idealBoxes(ws)
        let targetMonitor = monitorID(containing: point) ?? ws.monitor
        let targetWS = activeSpecial[targetMonitor] ?? activeWorkspace[targetMonitor] ?? ws.id
        if wasResize || (targetWS == ws.id && boxes[id]?.contains(point) ?? true) {
            refresh([ws.id])
            return
        }
        if targetWS == ws.id, ws.layout.kind != .dwindle,
           let other = boxes.first(where: { $0.key != id && $0.value.contains(point) && windows[$0.key]?.isFloating == false })?.key {
            workspaces[ws.id]?.layout.update { $0.swap(id, other) }
            refresh([ws.id])
            return
        }
        detach(id)
        attach(id, to: targetWS, focalPoint: point)
        refresh([ws.id, targetWS])
        destroyIfUnused(ws.id)
        emit(.saveState)
    }

    func nativeFocusChanged(_ id: WindowID?) {
        guard let id, let w = windows[id], w.suspended == nil else {
            focusedWindow = nil
            emit(.statusChanged)
            return
        }
        if !isVisible(w.workspace) {
            guard config.misc.focusOnActivate else { return }
            if workspaces[w.workspace]?.isSpecial == true {
                toggleSpecial(w.workspace, show: true, focusing: id, emitFocus: false)
            } else {
                switchWorkspace(w.workspace, focusing: id, emitFocus: false)
            }
        }
        focusWindow(id, warp: false, emitEffect: false)
    }

    func cursorMoved(_ p: Point) {
        cursor = p
        guard config.input.followMouse == 1, dragging == nil, let id = windowAt(p), id != focusedWindow else { return }
        focusWindow(id, warp: false, emitEffect: true)
    }
}
```

- [ ] **Step 5: Route every event and use `switchWorkspace` in `addWindow`**

In `Sources/HyprCore/World/World.swift`, replace the body of `apply` with:

```swift
    func apply(_ event: PlatformEvent) {
        switch event {
        case .monitorsChanged(let infos): setMonitors(infos)
        case .windowAppeared(let s): addWindow(s)
        case .windowDisappeared(let id):
            let wsID = windows[id]?.workspace
            removeWindow(id)
            if let wsID { closeSpecialIfEmpty(wsID) }
        case .windowSuspended(let id, let reason): suspend(id, reason)
        case .windowResumed(let id): resume(id)
        case .appHidden(let pid, let byUser): appHidden(pid, byUser: byUser)
        case .appUnhidden(let pid):
            for w in windows.values where w.pid == pid && w.suspended == .appHidden { resume(w.id) }
        case .appTerminated(let pid):
            for id in windows.values.filter({ $0.pid == pid }).map(\.id) { removeWindow(id) }
        case .windowTitleChanged(let id, let title, let early): retitle(id, title, early: early)
        case .windowFrameChanged(let id, let frame, let userDriven): frameChanged(id, frame, userDriven: userDriven)
        case .dragEnded(let point): endDrag(at: point)
        case .focusChanged(let id): nativeFocusChanged(id)
        case .cursorMoved(let point): cursorMoved(point)
        }
    }
```

In `addWindow`, replace

```swift
        if !isVisible(target) && !silent && outcome.workspace != nil { showWorkspace(target) }
```

with

```swift
        if !isVisible(target) && !silent && outcome.workspace != nil {
            if workspaces[target]?.isSpecial == true { toggleSpecial(target, show: true, emitFocus: false) } else { switchWorkspace(target, emitFocus: false) }
        }
```

and delete the `showWorkspace` function.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter WorldWorkspaceEventTests` and then `swift test --filter WorldCoreTests`
Expected: both PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/HyprCore/World Tests/HyprCoreTests/WorldWorkspaceEventTests.swift
git commit -m "feat: add workspaces, monitors and platform events to the world"
```

---
### Task 15: World focus search and dispatchers

**Files:**
- Create: `Sources/HyprCore/World/World+Focus.swift`, `Sources/HyprCore/World/World+Dispatch.swift`
- Modify: `Tests/HyprCoreTests/WorldCoreTests.swift` (remove `.disabled("needs Task 15")` from `spawnRulesApplyToTheSpawnedPid`)
- Test: `Tests/HyprCoreTests/WorldDispatchTests.swift`

**Interfaces:**
- Consumes: Tasks 13 and 14.
- Produces: `public func run(_ command: Command) -> CommandResult` on `World` (reply "ok" or an error message), plus internal `matchingWindows(_:) -> [WindowID]`, `windowInDirection(from:originFloating:ignoring:_:) -> WindowID?`, `moveFocus(_:)`, `cycle(_:)`, `focusAnywhere(_:)`.

Behavior: `hyprland-algorithms.md` section 6 for `movefocus` (edge mode with `isAdjacent`, overlap > 1, winner by focus history when `binds:focus_preferred_method = 0`, by overlap when 1, never-focused windows rank below focused ones, ties to the lower window id; vector mode when the focused window floats; then the other floating preference; then the monitor in that direction when `binds:window_direction_monitor_fallback`; then, unless `general:no_focus_fallback`, a wrap search from a 1 pt strip at the opposite edge of the work area, skipped when the window spans that axis). Monocle workspaces step through the window list instead. Every focus change by a dispatcher warps the cursor (subject to `cursor:no_warps`) and raises the window. The dispatcher semantics are in spec section 9; window selectors use full-match regexes on bundle id or app name (`class`, `initialclass`), title, initial title, pid, address; `floating` and `tiled` pick the first such window on the current workspace. `exact` sizes and positions are relative to the work area. `exec` with rules allocates a spawn token (`spawnRules[token] = rules`) and emits `.spawn(command, token:)`. `workspacelayout A B` toggles between A and B; one name sets it; windows are re-inserted in their old order, each after the previous one. `setprop` accepts `border_size`, `border_color`, `no_anim`.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/WorldDispatchTests.swift`:

```swift
import Testing
@testable import HyprCore

func threeWindows(_ text: String = "") -> World {
    let w = world(text)
    for id: WindowID in 1...3 { _ = w.handle(.windowAppeared(snap(id, pid: Int32(id) * 100))) }
    return w
}

func ok(_ r: CommandResult) -> Bool { !r.isError }

@Suite struct WorldDispatchTests {
    @Test func moveFocusUsesEdgesAndHistory() {
        let w = threeWindows()
        #expect(w.run(.moveFocus(.up)).effects.contains(.focus(2)))
        #expect(w.run(.moveFocus(.left)).effects.contains(.focus(1)))
        #expect(w.run(.moveFocus(.right)).effects.contains(.focus(2)))
    }

    @Test func moveFocusFallsBackToMonitorThenWraps() {
        let two = world(monitors: [laptop, ultrawide])
        _ = two.handle(.windowAppeared(snap(1)))
        _ = two.run(.moveFocus(.right))
        #expect(two.focusedMonitor == 1)
        let single = world()
        _ = single.handle(.windowAppeared(snap(1)))
        _ = single.handle(.windowAppeared(snap(2, pid: 200)))
        _ = single.run(.focusWindow(.address(1)))
        #expect(single.run(.moveFocus(.left)).effects.contains(.focus(2)))
    }

    @Test func cycleNextAndPrevious() {
        let w = threeWindows()
        #expect(w.run(.cycleNext(CycleOptions())).effects.contains(.focus(1)))
        var prev = CycleOptions()
        prev.previous = true
        #expect(w.run(.cycleNext(prev)).effects.contains(.focus(3)))
    }

    @Test func toggleFloatingCentersAtSixtyPercent() {
        let w = threeWindows()
        let e = w.run(.floating(.toggle, .active)).effects
        #expect(frames(e)[3] == Rect(x: 302, y: 222, width: 907, height: 570))
        #expect(w.windows[3]?.isFloating == true)
        _ = w.run(.floating(.unset, .active))
        #expect(w.windows[3]?.isFloating == false)
    }

    @Test func fullscreenModes() {
        let w = world("general:gaps_out = 10")
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, pid: 200)))
        #expect(frames(w.run(.fullscreen(mode: 0, .toggle)).effects)[2] == Rect(x: 0, y: 32, width: 1512, height: 950))
        #expect(frames(w.run(.fullscreen(mode: 1, .set)).effects)[2] == Rect(x: 10, y: 42, width: 1492, height: 930))
        #expect(frames(w.run(.fullscreen(mode: 1, .toggle)).effects)[2] == Rect(x: 756, y: 42, width: 746, height: 930))
    }

    @Test func pinNeedsFloating() {
        let w = threeWindows()
        #expect(w.run(.pin(.active)).reply == "pin works only on floating windows")
        _ = w.run(.floating(.set, .active))
        #expect(ok(w.run(.pin(.active))))
        #expect(w.windows[3]?.isPinned == true)
    }

    @Test func moveWindowInLayoutToMonitorAndFloatingEdge() {
        let w = world(monitors: [laptop, ultrawide])
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, pid: 200)))
        _ = w.run(.moveWindow(.direction(.left), silent: false))
        #expect(w.workspaces[1]?.tiledIDs == [2, 1])
        _ = w.run(.moveWindow(.monitor(.id(1)), silent: false))
        #expect(w.windows[2]?.workspace == w.activeWorkspace[1])
        #expect(w.focusedMonitor == 1)
        _ = w.run(.focusWindow(.address(1)))
        _ = w.run(.floating(.set, .active))
        _ = w.run(.moveWindow(.direction(.right), silent: false))
        #expect(w.windows[1]?.floatingFrame.maxX == 1512)
    }

    @Test func swapWindowAndSwapNext() {
        let w = threeWindows()
        _ = w.run(.swapWindow(.direction(.left)))
        #expect(w.workspaces[1]?.tiledIDs == [3, 2, 1])
        _ = w.run(.swapNext(previous: false))
        #expect(w.workspaces[1]?.tiledIDs == [2, 3, 1])
    }

    @Test func resizeTiledAndExactFloatingLikeRectangle() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, pid: 200)))
        let resized = w.run(.resizeActive(.relative(.pixels(-100), .pixels(0)))).effects
        #expect(frames(resized)[1] == Rect(x: 0, y: 32, width: 656, height: 950))
        _ = w.run(.floating(.set, .active))
        _ = w.run(.resizeActive(.exact(.percent(33), .percent(100))))
        let placed = w.run(.moveActive(.exact(.percent(0), .percent(0)))).effects
        #expect(frames(placed)[2] == Rect(x: 0, y: 32, width: 499, height: 950))
        #expect(w.run(.moveActive(.relative(.pixels(1), .pixels(1)))).isError == false)
        _ = w.run(.floating(.unset, .active))
        #expect(w.run(.moveActive(.relative(.pixels(1), .pixels(1)))).reply == "moveactive works only on floating windows")
    }

    @Test func layoutMessagesAndWorkspaceLayout() {
        let w = threeWindows("dwindle:preserve_split = true")
        #expect(ok(w.run(.layoutMessage("togglesplit"))))
        #expect(w.run(.layoutMessage("bogus")).reply == "unknown dwindle layout message 'bogus'")
        #expect(ok(w.run(.workspaceLayout(["dwindle", "monocle"]))))
        #expect(w.workspaces[1]?.layout.kind == .monocle)
        let e = w.run(.workspaceLayout(["dwindle", "monocle"])).effects
        #expect(w.workspaces[1]?.layout.kind == .dwindle)
        #expect(!frames(e).isEmpty)
        _ = w.run(.workspaceLayout(["monocle"]))
        #expect(w.run(.moveFocus(.right)).effects.contains(.focus(1)))
    }

    @Test func submapsAndActiveBinds() {
        let w = world("bind = ALT, R, submap, resize\nsubmap = resize\nbinde = , H, resizeactive, -50 0\nbindu = , F1, exec, true\nsubmap = reset")
        #expect(w.activeBinds.map(\.dispatcher) == ["submap", "exec"])
        let r = w.run(.submap("resize"))
        #expect(r.effects.contains(.submapChanged("resize")))
        #expect(w.activeBinds.map(\.dispatcher) == ["resizeactive", "exec"])
        _ = w.run(.submap("reset"))
        #expect(w.submap == "")
    }

    @Test func killAndSignals() {
        let w = threeWindows()
        #expect(w.run(.killActive(force: false)).effects.contains(.close(3)))
        #expect(w.run(.killActive(force: true)).effects.contains(.signal(pid: 300, signal: 9)))
        #expect(w.run(.signal(15, .classRegex("Ghostty"))).effects.contains(.signal(pid: 100, signal: 15)))
    }

    @Test func focusWindowSwitchesToItsWorkspace() {
        let w = threeWindows()
        _ = w.run(.moveToWorkspace(.id(4), .address(1), silent: true))
        let e = w.run(.focusWindow(.address(1))).effects
        #expect(w.activeWorkspace[0] == 4)
        #expect(e.contains(.focus(1)))
        #expect(w.run(.focusCurrentOrLast).effects.contains(.focus(3)))
    }

    @Test func cursorAndRenameAndUnsupported() {
        let w = threeWindows()
        #expect(w.run(.moveCursorToCorner(3)).effects.contains(.warpCursor(Point(x: 756, y: 507))))
        #expect(ok(w.run(.renameWorkspace(1, "code"))))
        #expect(w.workspaces[1]?.name == "code")
        #expect(w.run(.unsupported("sendshortcut")).reply == "sendshortcut is not supported on macOS")
        #expect(w.run(.exit).effects.contains(.exitApp))
    }

    @Test func workspaceDispatchers() {
        let w = threeWindows()
        _ = w.run(.workspace(.id(2)))
        #expect(w.activeWorkspace[0] == 2)
        _ = w.run(.workspace(.previous))
        #expect(w.activeWorkspace[0] == 1)
        _ = w.run(.toggleSpecialWorkspace("magic"))
        #expect(w.activeSpecial[0] != nil)
        _ = w.run(.toggleSpecialWorkspace("magic"))
        #expect(w.activeSpecial[0] == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WorldDispatchTests`
Expected: FAIL, "value of type 'World' has no member 'run'".

- [ ] **Step 3: Implement focus search**

`Sources/HyprCore/World/World+Focus.swift`:

```swift
import Foundation

extension World {
    var visibleWorkspaceIDs: [Int] {
        monitors.flatMap { m in [activeSpecial[m.id], activeWorkspace[m.id]].compactMap { $0 } }
    }

    func allIdealBoxes() -> [WindowID: Rect] {
        var out: [WindowID: Rect] = [:]
        for wsID in visibleWorkspaceIDs {
            if let ws = workspaces[wsID] { out.merge(idealBoxes(ws)) { a, _ in a } }
        }
        return out
    }

    static func isAdjacent(_ aMin: Double, _ aMax: Double, _ bMin: Double, _ bMax: Double) -> Bool {
        let delta = aMin - bMax
        if abs(delta) < 2 { return true }
        if delta >= 0 { return false }
        if (aMin <= bMin && aMax >= bMax) || (bMin <= aMin && bMax >= aMax) { return false }
        return -delta <= min(aMax - aMin, bMax - bMin) * 0.5
    }

    func windowInDirection(from origin: Rect, originFloating: Bool, ignoring: WindowID?, _ dir: Direction) -> WindowID? {
        let boxes = allIdealBoxes().filter { $0.key != ignoring && windows[$0.key]?.suspended == nil }.sorted { $0.key < $1.key }
        var rank: [WindowID: Double] = [:]
        for (i, id) in focusHistory.enumerated() { rank[id] = Double(i) }
        for preference in [originFloating, !originFloating] {
            var leader: WindowID?
            var leaderValue = -1.0
            var bestAngle = 2 * Double.pi
            for (id, box) in boxes where windows[id]?.isFloating == preference {
                if originFloating {
                    let o = origin.center, c = box.center
                    let vx = c.x - o.x, vy = c.y - o.y
                    let dist = (vx * vx + vy * vy).squareRoot()
                    guard dist > 0 else { continue }
                    let (dx, dy): (Double, Double)
                    switch dir {
                    case .right: (dx, dy) = (1, 0)
                    case .left: (dx, dy) = (-1, 0)
                    case .up: (dx, dy) = (0, -1)
                    case .down: (dx, dy) = (0, 1)
                    }
                    let angle = acos(max(-1, min(1, (vx * dx + vy * dy) / dist)))
                    if angle > Double.pi / 2 { continue }
                    let threshold = 0.3 * Double.pi
                    if (bestAngle < threshold && dist < leaderValue && angle < threshold) || (angle < bestAngle && bestAngle > threshold) || leaderValue == -1 {
                        leader = id
                        leaderValue = dist
                        bestAngle = angle
                    }
                    continue
                }
                let adjacent: Bool
                let overlap: Double
                switch dir {
                case .left:
                    adjacent = World.isAdjacent(origin.minX, origin.maxX, box.minX, box.maxX)
                    overlap = min(origin.maxY, box.maxY) - max(origin.minY, box.minY)
                case .right:
                    adjacent = World.isAdjacent(box.minX, box.maxX, origin.minX, origin.maxX)
                    overlap = min(origin.maxY, box.maxY) - max(origin.minY, box.minY)
                case .up:
                    adjacent = World.isAdjacent(origin.minY, origin.maxY, box.minY, box.maxY)
                    overlap = min(origin.maxX, box.maxX) - max(origin.minX, box.minX)
                case .down:
                    adjacent = World.isAdjacent(box.minY, box.maxY, origin.minY, origin.maxY)
                    overlap = min(origin.maxX, box.maxX) - max(origin.minX, box.minX)
                }
                guard adjacent, overlap > 1 else { continue }
                let value = config.bindsOptions.focusPreferredMethod == 1 ? overlap : (rank[id] ?? -0.5)
                if value > leaderValue {
                    leader = id
                    leaderValue = value
                }
            }
            if let leader { return leader }
        }
        return nil
    }

    func focusAndRaise(_ id: WindowID) {
        focusWindow(id, warp: true, emitEffect: true)
        emit(.raise(id))
    }

    func focusAnywhere(_ id: WindowID) {
        guard let w = windows[id], w.suspended == nil else { return }
        if isVisible(w.workspace) {
            focusWindow(id, warp: true, emitEffect: true)
        } else if workspaces[w.workspace]?.isSpecial == true {
            toggleSpecial(w.workspace, show: true, focusing: id)
        } else {
            switchWorkspace(w.workspace, focusing: id)
        }
        emit(.raise(id))
    }

    func moveFocus(_ d: Direction) {
        if let f = focusedWindow, let w = windows[f], !w.isFloating, case .monocle(let m) = workspaces[w.workspace]?.layout {
            if let n = m.neighbor(of: f, forward: d == .right || d == .down) { focusAndRaise(n) }
            return
        }
        guard let f = focusedWindow, let w = windows[f], let ws = workspaces[w.workspace], let box = idealBoxes(ws)[f] else {
            if config.bindsOptions.windowDirectionMonitorFallback, let m = monitorInDirection(from: focusedMonitor, d) { focusMonitor(m) }
            return
        }
        if let target = windowInDirection(from: box, originFloating: w.isFloating, ignoring: f, d) {
            focusAndRaise(target)
            return
        }
        if config.bindsOptions.windowDirectionMonitorFallback, let m = monitorInDirection(from: ws.monitor, d) {
            focusMonitor(m)
            return
        }
        if config.general.noFocusFallback { return }
        let area = workArea(for: ws)
        if (d == .left || d == .right) && WindowGeometry.sticks(box.minX, area.minX) && WindowGeometry.sticks(box.maxX, area.maxX) { return }
        if (d == .up || d == .down) && WindowGeometry.sticks(box.minY, area.minY) && WindowGeometry.sticks(box.maxY, area.maxY) { return }
        let strip: Rect
        switch d {
        case .left: strip = Rect(x: area.maxX, y: area.minY, width: 1, height: area.height)
        case .right: strip = Rect(x: area.minX - 1, y: area.minY, width: 1, height: area.height)
        case .up: strip = Rect(x: area.minX, y: area.maxY, width: area.width, height: 1)
        case .down: strip = Rect(x: area.minX, y: area.minY - 1, width: area.width, height: 1)
        }
        if let target = windowInDirection(from: strip, originFloating: w.isFloating, ignoring: f, d) { focusAndRaise(target) }
    }

    func cycle(_ o: CycleOptions) {
        let wsIDs = o.visible ? visibleWorkspaceIDs : [focusedWindow.flatMap { windows[$0]?.workspace } ?? currentWorkspaceID].compactMap { $0 }
        var list = wsIDs.flatMap { workspaces[$0]?.windowIDs ?? [] }
        if o.tiledOnly { list = list.filter { windows[$0]?.isFloating == false } }
        if o.floatingOnly { list = list.filter { windows[$0]?.isFloating == true } }
        if o.history { list = focusHistory.reversed().filter(list.contains) + list.filter { !focusHistory.contains($0) } }
        guard !list.isEmpty else { return }
        let next: WindowID
        if let f = focusedWindow, let i = list.firstIndex(of: f) {
            next = list[(i + (o.previous ? list.count - 1 : 1)) % list.count]
        } else {
            next = list[0]
        }
        focusAndRaise(next)
    }

    func matchingWindows(_ sel: WindowSelector) -> [WindowID] {
        let ordered = windows.keys.sorted().filter { windows[$0]?.suspended == nil }
        func classes(_ w: ManagedWindow) -> [String] { w.bundleID.isEmpty ? [w.appName] : [w.bundleID, w.appName] }
        let current = focusedWindow.flatMap { windows[$0]?.workspace } ?? currentWorkspaceID
        switch sel {
        case .active: return focusedWindow.map { [$0] } ?? []
        case .classRegex(let r), .initialClass(let r):
            guard let rx = RuleRegex(r) else { return [] }
            return ordered.filter { windows[$0].map { rx.matchesAny(classes($0)) } ?? false }
        case .title(let r):
            guard let rx = RuleRegex(r) else { return [] }
            return ordered.filter { windows[$0].map { rx.matches($0.title) } ?? false }
        case .initialTitle(let r):
            guard let rx = RuleRegex(r) else { return [] }
            return ordered.filter { windows[$0].map { rx.matches($0.initialTitle) } ?? false }
        case .pid(let p): return ordered.filter { windows[$0]?.pid == p }
        case .address(let a): return ordered.filter { $0 == a }
        case .floating: return (current.flatMap { workspaces[$0]?.floating } ?? []).prefix(1).map { $0 }
        case .tiled: return (current.flatMap { workspaces[$0]?.tiledIDs } ?? []).prefix(1).map { $0 }
        case .tag: return []
        }
    }
}
```

- [ ] **Step 4: Implement the dispatchers**

`Sources/HyprCore/World/World+Dispatch.swift`:

```swift
import Foundation

extension World {
    public func run(_ command: Command) -> CommandResult {
        let error = execute(command)
        return CommandResult(reply: error ?? "ok", isError: error != nil, effects: takeEffects())
    }

    func measure(_ m: Measure, base: Double) -> Double {
        switch m {
        case .pixels(let v): return v
        case .percent(let v): return v / 100 * base
        }
    }

    func execute(_ command: Command) -> String? {
        switch command {
        case .exec(let cmd, let rules, _):
            var token: Int?
            if let rules, !rules.isEmpty {
                token = nextSpawnToken
                nextSpawnToken += 1
                spawnRules[token!] = rules
            }
            emit(.spawn(cmd, token: token))
            return nil
        case .killActive(let force):
            guard let id = focusedWindow, let w = windows[id] else { return "no active window" }
            emit(force ? .signal(pid: w.pid, signal: 9) : .close(id))
            return nil
        case .closeWindow(let sel, let force):
            guard let id = matchingWindows(sel).first, let w = windows[id] else { return "no matching window" }
            emit(force ? .signal(pid: w.pid, signal: 9) : .close(id))
            return nil
        case .signal(let sig, let sel):
            guard let id = matchingWindows(sel).first, let w = windows[id] else { return "no matching window" }
            emit(.signal(pid: w.pid, signal: sig))
            return nil
        case .workspace(let sel):
            guard let id = resolveWorkspace(sel) else { return "invalid workspace" }
            if workspaces[id]?.isSpecial == true { toggleSpecial(id, show: true) } else { switchWorkspace(id) }
            return nil
        case .moveToWorkspace(let sel, let wsel, let silent):
            guard let target = resolveWorkspace(sel) else { return "invalid workspace" }
            guard let id = matchingWindows(wsel).first else { return "no matching window" }
            moveWindow(id, toWorkspace: target, silent: silent)
            return nil
        case .floating(let action, let sel):
            guard let id = matchingWindows(sel).first, let w = windows[id] else { return "no matching window" }
            setFloating(id, action == .toggle ? !w.isFloating : action == .set)
            return nil
        case .fullscreen(let mode, let action):
            guard let id = focusedWindow, let w = windows[id] else { return "no active window" }
            let turnOn = action == .toggle ? w.fullscreenMode != mode : action == .set
            for other in workspaces[w.workspace]?.windowIDs ?? [] { windows[other]?.fullscreenMode = nil }
            windows[id]?.fullscreenMode = turnOn ? mode : nil
            if turnOn { emit(.raise(id)) }
            refresh([w.workspace])
            emit(.saveState)
            return nil
        case .pin(let sel):
            guard let id = matchingWindows(sel).first, let w = windows[id] else { return "no matching window" }
            guard w.isFloating else { return "pin works only on floating windows" }
            windows[id]?.isPinned.toggle()
            emit(.saveState)
            return nil
        case .pseudo(let sel):
            guard let id = matchingWindows(sel).first, let w = windows[id] else { return "no matching window" }
            if !w.isPseudo { windows[id]?.pseudoSize = (w.appliedFrame ?? w.lastFrame).size }
            windows[id]?.isPseudo.toggle()
            refresh([w.workspace])
            emit(.saveState)
            return nil
        case .moveFocus(let d):
            moveFocus(d)
            return nil
        case .moveWindow(let target, let silent):
            return moveActiveWindow(target, silent: silent)
        case .swapWindow(let target):
            return swapWindow(target)
        case .centerWindow:
            guard let id = focusedWindow, let w = windows[id], w.isFloating, let ws = workspaces[w.workspace] else { return "no floating active window" }
            let area = workArea(for: ws)
            var f = w.floatingFrame
            f.x = area.x + (area.width - f.width) / 2
            f.y = area.y + (area.height - f.height) / 2
            windows[id]?.floatingFrame = f.rounded()
            refresh([w.workspace])
            return nil
        case .resizeActive(let p):
            guard let id = focusedWindow else { return "no active window" }
            return resize(id, p)
        case .moveActive(let p):
            guard let id = focusedWindow else { return "no active window" }
            return move(id, p)
        case .resizeWindow(let p, let sel):
            guard let id = matchingWindows(sel).first else { return "no matching window" }
            return resize(id, p)
        case .moveWindowTo(let p, let sel):
            guard let id = matchingWindows(sel).first else { return "no matching window" }
            return move(id, p)
        case .cycleNext(let o):
            cycle(o)
            return nil
        case .swapNext(let previous):
            guard let id = focusedWindow, let w = windows[id], !w.isFloating, var ws = workspaces[w.workspace] else { return "no tiled active window" }
            let tiled = ws.tiledIDs
            guard let i = tiled.firstIndex(of: id), tiled.count > 1 else { return nil }
            let other = tiled[(i + (previous ? tiled.count - 1 : 1)) % tiled.count]
            ws.layout.update { $0.swap(id, other) }
            workspaces[ws.id] = ws
            refresh([ws.id])
            emit(.saveState)
            return nil
        case .focusWindow(let sel):
            guard let id = matchingWindows(sel).first else { return "no matching window" }
            focusAnywhere(id)
            return nil
        case .focusMonitor(let sel):
            guard let m = resolveMonitor(sel) else { return "invalid monitor" }
            focusMonitor(m)
            return nil
        case .focusCurrentOrLast, .focusUrgentOrLast:
            guard let last = focusHistory.dropLast().last else { return nil }
            focusAnywhere(last)
            return nil
        case .moveCurrentWorkspaceToMonitor(let sel):
            guard let m = resolveMonitor(sel), let current = currentWorkspaceID else { return "invalid monitor" }
            moveWorkspace(current, toMonitor: m)
            focusedMonitor = m
            return nil
        case .moveWorkspaceToMonitor(let wsel, let msel):
            guard let id = resolveWorkspace(wsel), let m = resolveMonitor(msel) else { return "invalid workspace or monitor" }
            ensureWorkspace(id)
            moveWorkspace(id, toMonitor: m)
            return nil
        case .focusWorkspaceOnCurrentMonitor(let sel):
            guard let id = resolveWorkspace(sel) else { return "invalid workspace" }
            focusWorkspaceOnCurrentMonitor(id)
            return nil
        case .swapActiveWorkspaces(let a, let b):
            guard let ma = resolveMonitor(a), let mb = resolveMonitor(b) else { return "invalid monitor" }
            swapActiveWorkspaces(ma, mb)
            return nil
        case .toggleSpecialWorkspace(let name):
            guard let id = resolveWorkspace(.special(name)) else { return "invalid workspace" }
            toggleSpecial(id)
            return nil
        case .renameWorkspace(let id, let name):
            guard workspaces[id] != nil else { return "no such workspace" }
            workspaces[id]?.name = name.isEmpty ? String(id) : name
            emit(.statusChanged)
            return nil
        case .layoutMessage(let text):
            return layoutMessage(text)
        case .submap(let name):
            submap = name == "reset" ? "" : name
            emit(.submapChanged(submap))
            emit(.statusChanged)
            return nil
        case .alterZOrder(let top):
            guard let id = focusedWindow else { return "no active window" }
            if top { emit(.raise(id)) }
            return nil
        case .moveCursorToCorner(let corner):
            guard let id = focusedWindow, let f = windows[id]?.appliedFrame else { return "no active window" }
            let points = [Point(x: f.minX, y: f.maxY - 1), Point(x: f.maxX - 1, y: f.maxY - 1), Point(x: f.maxX - 1, y: f.minY), Point(x: f.minX, y: f.minY)]
            cursor = points[corner]
            emit(.warpCursor(cursor))
            return nil
        case .moveCursor(let x, let y):
            cursor = Point(x: x, y: y)
            emit(.warpCursor(cursor))
            return nil
        case .workspaceLayout(let names):
            return setWorkspaceLayout(names)
        case .setProp(let sel, let prop, let value):
            guard ["border_size", "border_color", "no_anim"].contains(prop) else { return "setprop \(prop) is not supported on macOS" }
            guard let id = matchingWindows(sel).first, let w = windows[id] else { return "no matching window" }
            windows[id]?.props[prop] = value
            refresh([w.workspace])
            return nil
        case .exit:
            emit(.exitApp)
            return nil
        case .noop:
            return nil
        case .unsupported(let name):
            return "\(name) is not supported on macOS"
        }
    }

    func moveActiveWindow(_ target: MoveTarget, silent: Bool) -> String? {
        guard let id = focusedWindow, let w = windows[id], var ws = workspaces[w.workspace] else { return "no active window" }
        switch target {
        case .monitor(let sel):
            guard let m = resolveMonitor(sel), let dest = activeSpecial[m] ?? activeWorkspace[m] else { return "invalid monitor" }
            moveWindow(id, toWorkspace: dest, silent: silent)
            return nil
        case .direction(let d):
            if w.isFloating {
                let area = workArea(for: ws)
                var f = w.floatingFrame
                switch d {
                case .left: f.x = area.minX
                case .right: f.x = area.maxX - f.width
                case .up: f.y = area.minY
                case .down: f.y = area.maxY - f.height
                }
                windows[id]?.floatingFrame = f
                refresh([ws.id])
                return nil
            }
            let ctx = layoutContext(ws)
            let moved = ws.layout.update { $0.moveWindow(id, d, ctx) }
            workspaces[ws.id] = ws
            if moved {
                refresh([ws.id])
                emit(.saveState)
                return nil
            }
            guard config.bindsOptions.windowDirectionMonitorFallback, let m = monitorInDirection(from: ws.monitor, d),
                  let dest = activeSpecial[m] ?? activeWorkspace[m], let destWS = workspaces[dest] else { return nil }
            let area = workArea(for: destWS)
            let entry: Point
            switch d {
            case .left: entry = Point(x: area.maxX - 1, y: area.center.y)
            case .right: entry = Point(x: area.minX + 1, y: area.center.y)
            case .up: entry = Point(x: area.center.x, y: area.maxY - 1)
            case .down: entry = Point(x: area.center.x, y: area.minY + 1)
            }
            moveWindow(id, toWorkspace: dest, silent: silent, focalPoint: entry)
            return nil
        }
    }

    func swapWindow(_ target: SwapTarget) -> String? {
        guard let id = focusedWindow, let w = windows[id], !w.isFloating, var ws = workspaces[w.workspace] else { return "no tiled active window" }
        let other: WindowID?
        switch target {
        case .direction(let d): other = idealBoxes(ws)[id].flatMap { windowInDirection(from: $0, originFloating: false, ignoring: id, d) }
        case .window(let sel): other = matchingWindows(sel).first { $0 != id }
        }
        guard let other, windows[other]?.workspace == ws.id, windows[other]?.isFloating == false else { return "no window to swap with" }
        ws.layout.update { $0.swap(id, other) }
        workspaces[ws.id] = ws
        refresh([ws.id])
        emit(.saveState)
        return nil
    }

    func resize(_ id: WindowID, _ p: ResizeParam) -> String? {
        guard let w = windows[id], var ws = workspaces[w.workspace] else { return "no matching window" }
        let area = workArea(for: ws)
        let current = w.isFloating ? w.floatingFrame : (idealBoxes(ws)[id] ?? w.lastFrame)
        var size: Size
        switch p {
        case .relative(let dx, let dy):
            size = Size(width: current.width + measure(dx, base: current.width), height: current.height + measure(dy, base: current.height))
        case .exact(let width, let height):
            size = Size(width: measure(width, base: area.width), height: measure(height, base: area.height))
        }
        size = Size(width: max(20, size.width), height: max(20, size.height))
        if w.isFloating {
            windows[id]?.floatingFrame = Rect(x: current.x, y: current.y, width: size.width, height: size.height).rounded()
        } else {
            let delta = Point(x: size.width - current.width, y: size.height - current.height)
            let ctx = layoutContext(ws)
            ws.layout.update { $0.resize(id, by: delta, corner: .none, ctx) }
            workspaces[ws.id] = ws
        }
        refresh([ws.id])
        emit(.saveState)
        return nil
    }

    func move(_ id: WindowID, _ p: ResizeParam) -> String? {
        guard let w = windows[id], w.isFloating, let ws = workspaces[w.workspace] else { return "moveactive works only on floating windows" }
        let area = workArea(for: ws)
        var f = w.floatingFrame
        switch p {
        case .relative(let dx, let dy):
            f.x += measure(dx, base: f.width)
            f.y += measure(dy, base: f.height)
        case .exact(let x, let y):
            f.x = area.x + measure(x, base: area.width)
            f.y = area.y + measure(y, base: area.height)
        }
        windows[id]?.floatingFrame = f.rounded()
        refresh([ws.id])
        emit(.saveState)
        return nil
    }

    func layoutMessage(_ text: String) -> String? {
        guard let wsID = focusedWindow.flatMap({ windows[$0]?.workspace }) ?? currentWorkspaceID, var ws = workspaces[wsID] else { return "no workspace" }
        let ctx = layoutContext(ws)
        let result = ws.layout.update { $0.message(text, ctx) }
        workspaces[wsID] = ws
        switch result {
        case .ok:
            refresh([wsID])
            emit(.saveState)
            return nil
        case .focus(let id):
            refresh([wsID])
            focusAndRaise(id)
            return nil
        case .error(let message):
            return message
        }
    }

    func setWorkspaceLayout(_ names: [String]) -> String? {
        let kinds = names.compactMap(LayoutKind.init(rawValue:))
        guard kinds.count == names.count, let first = kinds.first, let wsID = currentWorkspaceID, var ws = workspaces[wsID] else { return "invalid layout" }
        let target = kinds.count > 1 && ws.layout.kind == first ? kinds[1] : first
        guard target != ws.layout.kind else { return nil }
        let ids = ws.tiledIDs
        ws.layout = LayoutState(target)
        var previous: WindowID?
        for id in ids {
            var ctx = layoutContext(ws)
            ctx.focused = previous
            ws.layout.update { $0.insert(id, ctx) }
            previous = id
        }
        workspaces[wsID] = ws
        refresh([wsID])
        emit(.saveState)
        return nil
    }
}
```

- [ ] **Step 5: Enable the spawn test and run every world suite**

In `Tests/HyprCoreTests/WorldCoreTests.swift` change `@Test(.disabled("needs Task 15")) func spawnRulesApplyToTheSpawnedPid()` to `@Test func spawnRulesApplyToTheSpawnedPid()`.

Run: `swift test --filter "World"`
Expected: PASS for `WorldCoreTests`, `WorldWorkspaceEventTests` and `WorldDispatchTests`.

- [ ] **Step 6: Commit**

```bash
git add Sources/HyprCore/World Tests/HyprCoreTests
git commit -m "feat: add directional focus and every dispatcher to the world"
```

---
### Task 16: State snapshot and IPC protocol

**Files:**
- Create: `Sources/HyprCore/World/Snapshot.swift`, `Sources/HyprCore/IPC/IPCRequest.swift`, `Sources/HyprCore/IPC/IPCResponder.swift`
- Test: `Tests/HyprCoreTests/SnapshotIPCTests.swift`

**Interfaces:**
- Consumes: Tasks 9, 13-15.
- Produces:

```swift
public struct StateSnapshot: Codable, Equatable, Sendable {
    public var version: Int; public var windows: [ManagedWindow]; public var workspaces: [Workspace]
    public var activeWorkspace: [String: Int]            // monitor name -> workspace id
    public var focusedWindow: WindowID?
}
extension World {
    public func snapshot() -> StateSnapshot
    public func restore(_ snap: StateSnapshot, alive: [WindowSnapshot]) -> [Effect]
}
public struct IPCRequest: Equatable, Sendable {
    public var json: Bool; public var commands: [String]
    public static func parse(_ raw: String) -> IPCRequest
}
public enum IPCPolicy { public static func isBlocked(_ command: String, allowExec: Bool) -> Bool }
public struct IPCReply: Equatable, Sendable { public var text: String; public var effects: [Effect] }
public enum IPCResponder {
    public static func handle(_ raw: String, world: World, version: String, configErrors: [String], perfReport: () -> String) -> IPCReply
}
```

Rules:
- `restore`: keeps saved windows whose id is alive with the same bundle id; rebuilds saved workspaces on the monitor named by `homeMonitorName` (else the first monitor) and removes dead window ids from their layouts and floating lists; restored windows take the live title and frame, `appliedFrame = nil`, `isParked = false`; a window saved as suspended is re-attached to its workspace; active workspaces come back by monitor name; named and special id counters continue after the restored ids; the saved focus is kept when alive; every alive window not in the snapshot goes through `addWindow`; finally every monitor gets an active workspace and everything refreshes (no animation reason other than `.layout`).
- Request: the text before the first `/` is a flag string when it is empty or only lowercase letters (`j` sets JSON); the body may start with `[[BATCH]]` and then holds commands separated by `;`.
- Policy (unless `allowExec`): blocked are `dispatch exec`, `dispatch execr`, and `keyword` with a key whose last component starts with `exec` or equals `source`.
- Replies: `dispatch` runs the command (reply `ok` or the error); `keyword` applies to a copy of the config and calls `world.reload` (reply `ok` or the error); `reload` emits `.reloadConfig`; `clients`, `activewindow`, `workspaces`, `activeworkspace`, `monitors`, `binds`, `getoption KEY`, `configerrors`, `version`, `cursorpos`, `perf` as in spec section 14; a blocked command replies "exec over IPC is disabled (macos:ipc_exec)"; anything else "unknown request: NAME". JSON uses `JSONSerialization` with sorted keys; text follows Hyprland's `Window 0x1a -> title:` blocks. Titles are empty when `macos:ipc_window_titles` is false. Hyprland's `fullscreen` field is 2 for mode 0, 1 for mode 1, 0 for none. Batch replies are joined by a blank line.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/SnapshotIPCTests.swift`:

```swift
import Foundation
import Testing
@testable import HyprCore

func jsonObject(_ text: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(text.utf8)) }

@Suite struct SnapshotIPCTests {
    @Test func snapshotRoundTripRestoresWorkspacesAndLayout() throws {
        let w = threeWindows()
        _ = w.run(.moveToWorkspace(.id(3), .address(2), silent: true))
        let data = try JSONEncoder().encode(w.snapshot())
        let saved = try JSONDecoder().decode(StateSnapshot.self, from: data)
        let fresh = World(config: makeConfig())
        _ = fresh.handle(.monitorsChanged([laptop]))
        let alive = [snap(1), snap(2, pid: 200), snap(3, pid: 300)]
        let e = fresh.restore(saved, alive: alive)
        #expect(fresh.windows[2]?.workspace == 3)
        #expect(fresh.workspaces[1]?.tiledIDs == [1, 3])
        #expect(fresh.activeWorkspace[0] == 1)
        #expect(frames(e)[1] == Rect(x: 0, y: 32, width: 756, height: 950))
        #expect(parks(e)[2] != nil)
    }

    @Test func restoreDropsDeadAndAddsNewWindows() throws {
        let w = threeWindows()
        let saved = w.snapshot()
        let fresh = World(config: makeConfig())
        _ = fresh.handle(.monitorsChanged([laptop]))
        _ = fresh.restore(saved, alive: [snap(1), snap(7, pid: 700)])
        #expect(fresh.windows[2] == nil && fresh.windows[3] == nil)
        #expect(fresh.windows[7] != nil)
        #expect(Set(fresh.workspaces[1]?.tiledIDs ?? []) == [1, 7])
    }

    @Test func requestParsing() {
        #expect(IPCRequest.parse("j/clients") == IPCRequest(json: true, commands: ["clients"]))
        #expect(IPCRequest.parse("/dispatch workspace 2") == IPCRequest(json: false, commands: ["dispatch workspace 2"]))
        #expect(IPCRequest.parse("dispatch exec /bin/ls") == IPCRequest(json: false, commands: ["dispatch exec /bin/ls"]))
        #expect(IPCRequest.parse("/[[BATCH]]keyword general:gaps_in 2 ; keyword general:gaps_out 3").commands == ["keyword general:gaps_in 2", "keyword general:gaps_out 3"])
        #expect(IPCRequest.parse("j/[[BATCH]]clients;workspaces") == IPCRequest(json: true, commands: ["clients", "workspaces"]))
    }

    @Test func execPolicy() {
        #expect(IPCPolicy.isBlocked("dispatch exec open -a Calculator", allowExec: false))
        #expect(IPCPolicy.isBlocked("dispatch execr ls", allowExec: false))
        #expect(IPCPolicy.isBlocked("keyword exec-once evil", allowExec: false))
        #expect(IPCPolicy.isBlocked("keyword source /tmp/x.conf", allowExec: false))
        #expect(!IPCPolicy.isBlocked("dispatch workspace 2", allowExec: false))
        #expect(!IPCPolicy.isBlocked("dispatch exec ls", allowExec: true))
        #expect(IPCPolicy.isBlocked("dispatch \texec ls", allowExec: false))
        #expect(IPCPolicy.isBlocked("dispatch  EXEC [float] ls", allowExec: false))
        #expect(IPCPolicy.isBlocked("keyword bind ALT, X, exec, evil", allowExec: false))
        #expect(IPCPolicy.isBlocked("keyword workspace 3, on-created-empty:evil", allowExec: false))
        #expect(!IPCPolicy.isBlocked("keyword bind ALT, X, workspace, 2", allowExec: false))
        #expect(!IPCPolicy.isBlocked("keyword general:gaps_in 3", allowExec: false))
    }

    @Test func dispatchKeywordAndBlockedReplies() {
        let w = threeWindows()
        let r = IPCResponder.handle("/dispatch workspace 2", world: w, version: "0.1.0", configErrors: [], perfReport: { "" })
        #expect(r.text == "ok")
        #expect(w.activeWorkspace[0] == 2)
        let blocked = IPCResponder.handle("/dispatch exec open -a Calculator", world: w, version: "0.1.0", configErrors: [], perfReport: { "" })
        #expect(blocked.text == "exec over IPC is disabled (macos:ipc_exec)")
        #expect(blocked.effects.isEmpty)
        let k = IPCResponder.handle("/keyword general:gaps_in 3", world: w, version: "0.1.0", configErrors: [], perfReport: { "" })
        #expect(k.text == "ok")
        #expect(w.config.general.gapsIn == Edges(all: 3))
        #expect(IPCResponder.handle("/frobnicate", world: w, version: "0.1.0", configErrors: [], perfReport: { "" }).text == "unknown request: frobnicate")
        #expect(IPCResponder.handle("/reload", world: w, version: "0.1.0", configErrors: [], perfReport: { "" }).effects == [.reloadConfig])
    }

    @Test func clientsJSONEscapesTitlesAndHidesThemWhenAsked() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(26, title: "メモ \"q\" \\ 🎉")))
        let r = IPCResponder.handle("j/clients", world: w, version: "0.1.0", configErrors: [], perfReport: { "" })
        let list = jsonObject(r.text) as? [[String: Any]]
        #expect(list?.first?["address"] as? String == "0x1a")
        #expect(list?.first?["title"] as? String == "メモ \"q\" \\ 🎉")
        #expect(list?.first?["class"] as? String == "com.mitchellh.ghostty")
        #expect((list?.first?["workspace"] as? [String: Any])?["id"] as? Int == 1)
        let hidden = world("macos:ipc_window_titles = false")
        _ = hidden.handle(.windowAppeared(snap(26, title: "secret")))
        let h = IPCResponder.handle("j/clients", world: hidden, version: "0.1.0", configErrors: [], perfReport: { "" })
        #expect((jsonObject(h.text) as? [[String: Any]])?.first?["title"] as? String == "")
    }

    @Test func otherQueries() {
        let w = threeWindows()
        func ask(_ q: String) -> String { IPCResponder.handle(q, world: w, version: "0.1.0", configErrors: ["a.conf:1: bad"], perfReport: { "perf!" }).text }
        #expect((jsonObject(ask("j/activewindow")) as? [String: Any])?["address"] as? String == "0x3")
        #expect((jsonObject(ask("j/workspaces")) as? [[String: Any]])?.first?["windows"] as? Int == 3)
        #expect((jsonObject(ask("j/monitors")) as? [[String: Any]])?.first?["name"] as? String == "Built-in Retina Display")
        #expect(ask("/getoption general:border_size") == "0")
        #expect(ask("/configerrors") == "a.conf:1: bad")
        #expect(ask("/version").hasPrefix("HyprOSX 0.1.0"))
        #expect(ask("/perf") == "perf!")
        #expect(ask("/clients").hasPrefix("Window 0x1 -> t:"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SnapshotIPCTests`
Expected: FAIL, "cannot find 'StateSnapshot' in scope".

- [ ] **Step 3: Implement the snapshot**

`Sources/HyprCore/World/Snapshot.swift`:

```swift
import Foundation

public struct StateSnapshot: Codable, Equatable, Sendable {
    public var version = 1
    public var windows: [ManagedWindow]
    public var workspaces: [Workspace]
    public var activeWorkspace: [String: Int]
    public var focusedWindow: WindowID?
}

extension World {
    public func snapshot() -> StateSnapshot {
        let active = Dictionary(activeWorkspace.compactMap { key, value in monitor(key).map { ($0.name, value) } }, uniquingKeysWith: { a, _ in a })
        return StateSnapshot(windows: windows.values.sorted { $0.id < $1.id }, workspaces: workspaces.values.sorted { $0.id < $1.id },
                             activeWorkspace: active, focusedWindow: focusedWindow)
    }

    public func restore(_ snap: StateSnapshot, alive: [WindowSnapshot]) -> [Effect] {
        let live = Dictionary(alive.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let kept = snap.windows.filter { live[$0.id]?.bundleID == $0.bundleID }
        let keptIDs = Set(kept.map(\.id))
        for var ws in snap.workspaces {
            ws.monitor = monitors.first { $0.name == ws.homeMonitorName }?.id ?? monitors.first?.id ?? 0
            for id in ws.tiledIDs where !keptIDs.contains(id) { ws.layout.update { $0.remove(id) } }
            ws.floating.removeAll { !keptIDs.contains($0) }
            if let last = ws.lastFocused, !keptIDs.contains(last) { ws.lastFocused = nil }
            workspaces[ws.id] = ws
            if !ws.isSpecial && ws.id >= 1_000_000 { nextNamedID = max(nextNamedID, ws.id + 1) }
            if ws.isSpecial && ws.id >= -98 { nextSpecialID = max(nextSpecialID, ws.id + 1) }
        }
        var resumed: [WindowID] = []
        for var w in kept {
            guard let l = live[w.id] else { continue }
            w.title = l.title
            w.lastFrame = l.frame
            w.appliedFrame = nil
            w.isParked = false
            if w.suspended != nil {
                w.suspended = nil
                resumed.append(w.id)
            }
            windows[w.id] = w
        }
        for id in resumed {
            if let wsID = windows[id]?.workspace {
                ensureWorkspace(wsID)
                attach(id, to: wsID)
            }
        }
        for (name, wsID) in snap.activeWorkspace {
            guard let m = monitors.first(where: { $0.name == name }), workspaces[wsID]?.monitor == m.id else { continue }
            activeWorkspace[m.id] = wsID
            lastActiveByMonitorName[name] = wsID
        }
        if let f = snap.focusedWindow, keptIDs.contains(f) { focusedWindow = f }
        for s in alive where windows[s.id] == nil { addWindow(s) }
        setMonitors(monitors)
        return takeEffects()
    }
}
```

- [ ] **Step 4: Implement the request parser and policy**

`Sources/HyprCore/IPC/IPCRequest.swift`:

```swift
import Foundation

public struct IPCRequest: Equatable, Sendable {
    public var json: Bool
    public var commands: [String]
    public init(json: Bool, commands: [String]) { self.json = json; self.commands = commands }

    public static func parse(_ raw: String) -> IPCRequest {
        var body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var flags = ""
        if let slash = body.firstIndex(of: "/") {
            let prefix = body[..<slash]
            if prefix.allSatisfy({ $0.isLowercase && $0.isLetter }) {
                flags = String(prefix)
                body = String(body[body.index(after: slash)...])
            }
        }
        var commands = [body]
        if body.hasPrefix("[[BATCH]]") {
            commands = body.dropFirst("[[BATCH]]".count).split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return IPCRequest(json: flags.contains("j"), commands: commands)
    }
}

public enum IPCPolicy {
    public static func isBlocked(_ command: String, allowExec: Bool) -> Bool {
        if allowExec { return false }
        let (name, rest) = IPCResponder.split(command)
        switch name {
        case "dispatch":
            let (dispatcher, arguments) = IPCResponder.split(rest)
            if case .success(.exec(_, _, _)) = CommandParser.parse(dispatcher: dispatcher, arguments: arguments) { return true }
            return false
        case "keyword":
            let (key, value) = IPCResponder.split(rest)
            let last = key.split(separator: ":").last.map { $0.lowercased() } ?? ""
            if last.hasPrefix("exec") || last == "source" { return true }
            let lowered = value.lowercased()
            if last.hasPrefix("bind") { return lowered.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("exec") } }
            return last == "workspace" && lowered.contains("on-created-empty")
        default:
            return false
        }
    }
}
```

- [ ] **Step 5: Implement the responder**

`Sources/HyprCore/IPC/IPCResponder.swift`:

```swift
import Foundation

public struct IPCReply: Equatable, Sendable {
    public var text: String
    public var effects: [Effect]
}

public enum IPCResponder {
    public static func handle(_ raw: String, world: World, version: String, configErrors: [String], perfReport: () -> String) -> IPCReply {
        let request = IPCRequest.parse(raw)
        var texts: [String] = []
        var effects: [Effect] = []
        for command in request.commands {
            if IPCPolicy.isBlocked(command, allowExec: world.config.macos.ipcExec) {
                texts.append("exec over IPC is disabled (macos:ipc_exec)")
                continue
            }
            let (name, rest) = split(command)
            switch name {
            case "dispatch":
                let (dispatcher, arguments) = split(rest)
                switch CommandParser.parse(dispatcher: dispatcher, arguments: arguments) {
                case .success(let cmd):
                    let r = world.run(cmd)
                    texts.append(r.reply)
                    effects += r.effects
                case .failure(let e):
                    texts.append(e.message)
                }
            case "keyword":
                let (key, value) = split(rest)
                var config = world.config
                if let error = ConfigBuilder.applyKeyword(key, value, to: &config) {
                    texts.append(error)
                } else {
                    effects += world.reload(config)
                    texts.append("ok")
                }
            case "reload":
                effects.append(.reloadConfig)
                texts.append("ok")
            case "clients": texts.append(render(world.windows.values.sorted { $0.id < $1.id }.map { client($0, world) }, json: request.json, kind: "Window"))
            case "activewindow":
                let w = world.focusedWindow.flatMap { world.windows[$0] }
                texts.append(request.json ? encode(w.map { client($0, world) } ?? [:]) : (w.map { render([client($0, world)], json: false, kind: "Window") } ?? "Invalid"))
            case "workspaces": texts.append(render(world.workspaces.values.sorted { $0.id < $1.id }.map { workspace($0, world) }, json: request.json, kind: "workspace"))
            case "activeworkspace":
                let ws = world.currentWorkspaceID.flatMap { world.workspaces[$0] }
                texts.append(request.json ? encode(ws.map { workspace($0, world) } ?? [:]) : (ws.map { render([workspace($0, world)], json: false, kind: "workspace") } ?? "Invalid"))
            case "monitors": texts.append(render(world.monitors.map { monitor($0, world) }, json: request.json, kind: "Monitor"))
            case "binds": texts.append(render(world.config.binds.map(bind), json: request.json, kind: "bind"))
            case "getoption":
                let value = ConfigBuilder.getOption(rest.trimmingCharacters(in: .whitespaces), in: world.config)
                texts.append(request.json ? encode(["option": rest, "value": value.map { $0 as Any } ?? NSNull()]) : (value ?? "no such option"))
            case "configerrors": texts.append(request.json ? encode(configErrors) : configErrors.joined(separator: "\n"))
            case "version": texts.append(request.json ? encode(["version": version]) : "HyprOSX \(version)")
            case "cursorpos": texts.append("\(Int(world.cursor.x)), \(Int(world.cursor.y))")
            case "perf": texts.append(perfReport())
            default: texts.append("unknown request: \(name)")
            }
        }
        return IPCReply(text: texts.joined(separator: "\n\n"), effects: effects)
    }

    static func split(_ s: String) -> (String, String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let i = t.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return (t, "") }
        return (String(t[..<i]), t[i...].trimmingCharacters(in: .whitespaces))
    }

    static func encode(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func render(_ items: [[String: Any]], json: Bool, kind: String) -> String {
        if json { return encode(items) }
        return items.map { item in
            let header: String
            switch kind {
            case "Window": header = "Window \(item["address"] ?? "") -> \(item["title"] ?? ""):"
            case "workspace": header = "workspace ID \(item["id"] ?? "") (\(item["name"] ?? "")) on monitor \(item["monitor"] ?? ""):"
            case "Monitor": header = "Monitor \(item["name"] ?? "") (ID \(item["id"] ?? "")):"
            default: header = "\(kind):"
            }
            let lines = item.keys.sorted().map { key -> String in
                let value = item[key]
                let text: String
                switch value {
                case let b as Bool: text = b ? "1" : "0"
                case let a as [Any]: text = a.map { "\($0)" }.joined(separator: ",")
                case let d as [String: Any]: text = "\(d["id"] ?? "") (\(d["name"] ?? ""))"
                default: text = "\(value ?? "")"
                }
                return "\t\(key): \(text)"
            }
            return ([header] + lines).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    static func client(_ w: ManagedWindow, _ world: World) -> [String: Any] {
        let frame = w.appliedFrame ?? w.lastFrame
        let ws = world.workspaces[w.workspace]
        let cls = w.bundleID.isEmpty ? w.appName : w.bundleID
        let fullscreen = w.fullscreenMode.map { $0 == 0 ? 2 : 1 } ?? 0
        let title = world.config.macos.ipcWindowTitles ? w.title : ""
        let initialTitle = world.config.macos.ipcWindowTitles ? w.initialTitle : ""
        let history = world.focusHistory.reversed().firstIndex(of: w.id).map { $0 } ?? -1
        return [
            "address": w.address, "mapped": true, "hidden": w.isParked || w.suspended != nil,
            "at": [Int(frame.x), Int(frame.y)], "size": [Int(frame.width), Int(frame.height)],
            "workspace": ["id": w.workspace, "name": ws?.name ?? ""], "floating": w.isFloating, "monitor": ws?.monitor ?? -1,
            "class": cls, "title": title, "initialClass": cls, "initialTitle": initialTitle, "pid": Int(w.pid),
            "xwayland": false, "pinned": w.isPinned, "fullscreen": fullscreen, "fullscreenClient": fullscreen,
            "grouped": [String](), "tags": [String](), "swallowing": "0x0", "focusHistoryID": history,
        ]
    }

    static func workspace(_ ws: Workspace, _ world: World) -> [String: Any] {
        let last = ws.lastFocused.flatMap { world.windows[$0] }
        return [
            "id": ws.id, "name": ws.name, "monitor": world.monitor(ws.monitor)?.name ?? "", "monitorID": ws.monitor,
            "windows": ws.windowIDs.count, "hasfullscreen": ws.windowIDs.contains { world.windows[$0]?.fullscreenMode != nil },
            "lastwindow": last?.address ?? "0x0", "lastwindowtitle": world.config.macos.ipcWindowTitles ? (last?.title ?? "") : "",
            "ispersistent": ws.persistent, "tiledLayout": ws.layout.kind.rawValue,
        ]
    }

    static func monitor(_ m: MonitorInfo, _ world: World) -> [String: Any] {
        let active = world.activeWorkspace[m.id].flatMap { world.workspaces[$0] }
        let special = world.activeSpecial[m.id].flatMap { world.workspaces[$0] }
        let r = world.config.reservedAreas[m.name] ?? world.config.reservedAreas[""] ?? .zero
        return [
            "id": m.id, "name": m.name, "description": m.name, "make": "", "model": "", "serial": "",
            "width": Int(m.frame.width), "height": Int(m.frame.height), "refreshRate": 0, "x": Int(m.frame.x), "y": Int(m.frame.y),
            "activeWorkspace": ["id": active?.id ?? 0, "name": active?.name ?? ""],
            "specialWorkspace": ["id": special?.id ?? 0, "name": special?.name ?? ""],
            "reserved": [Int(r.left), Int(r.top), Int(r.right), Int(r.bottom)], "scale": 1, "transform": 0,
            "focused": world.focusedMonitor == m.id, "dpmsStatus": true, "vrr": false, "disabled": false,
        ]
    }

    static func bind(_ b: Bind) -> [String: Any] {
        let key: String
        switch b.trigger {
        case .key(let code): key = Keysym.name(for: code) ?? "code:\(code)"
        case .mouse(let n): key = "mouse:\(n)"
        case .scroll(let d): key = "mouse_\(d.rawValue)"
        case .catchall: key = "catchall"
        }
        return [
            "locked": b.flags.contains(.locked), "mouse": b.flags.contains(.mouse), "release": b.flags.contains(.release),
            "repeat": b.flags.contains(.repeating), "non_consuming": b.flags.contains(.nonConsuming), "modmask": b.modifiers.rawValue,
            "submap": b.submap, "key": key, "description": b.description ?? "", "dispatcher": b.dispatcher, "arg": b.arguments,
        ]
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test`
Expected: every HyprCore suite PASSES.

- [ ] **Step 7: Commit**

```bash
git add Sources/HyprCore Tests/HyprCoreTests/SnapshotIPCTests.swift
git commit -m "feat: add state snapshot, IPC protocol and exec policy"
```

---
### Task 17: Window classification and the Accessibility layer

**Files:**
- Create: `Sources/HyprCore/Platform/WindowClassifier.swift`, `Sources/HyprOSX/AX/AXSupport.swift`, `Sources/HyprOSX/AX/AXAppThread.swift`, `NOTICE`
- Test: `Tests/HyprCoreTests/WindowClassifierTests.swift`

**Interfaces:**
- Consumes: `WindowSnapshot`, `WindowID`, `Rect`, `Point` (HyprCore).
- Produces:

```swift
// HyprCore
public enum WindowButton: Sendable { case close, fullscreen, zoom, minimize }
public enum WindowClassification: Equatable, Sendable { case notAWindow, dialog, normal }
public protocol WindowAttributeReader {
    func subrole() -> String?; func title() -> String?; func identifier() -> String?
    func hasButton(_ b: WindowButton) -> Bool; func isButtonEnabled(_ b: WindowButton) -> Bool?
    func isFocused() -> Bool?; func isMain() -> Bool?; func isAppFocusedWindow() -> Bool
}
public enum WindowClassifier {
    public static func classify(_ w: WindowAttributeReader, bundleID: String?, isAccessoryApp: Bool, windowLevel: Int?) -> WindowClassification
}
// HyprOSX
enum AX { static func windowID(_:) -> WindowID?; static func value/string/bool/element/elements(_:_:); static func frame(_:) -> Rect?
          static func setPosition(_:_:) -> AXError; static func setSize(_:_:) -> AXError; static func setBool(_:_:_:) -> AXError; static func perform(_:_:) -> AXError
          static func windowLevel(_ id: WindowID) -> Int? }
enum AXAppEvent { case appeared(WindowSnapshot), disappeared(WindowID), minimized(WindowID, Bool), nativeFullscreen(WindowID, Bool),
                  title(WindowID, String), frame(WindowID, Rect), focused(WindowID?), registrationDelayed, scanned }
final class AXAppThread {
    let pid: pid_t; let bundleID: String; let appName: String
    init(pid: pid_t, bundleID: String, appName: String, isAccessory: Bool, onEvent: @escaping (AXAppEvent) -> Void)
    func start(); func stop(); func rescan(); func flushDelayed(); func flush(timeout: TimeInterval); func updateScreenSizes(_ sizes: [Size])
    func setFrame(_ id: WindowID, _ frame: Rect); func setPosition(_ id: WindowID, _ p: Point)
    func focus(_ id: WindowID); func raise(_ id: WindowID); func close(_ id: WindowID)
    var averageLatencyMs: Double { get }; var callCount: Int { get }; var errorCount: Int { get }
}
extension Rect { init(_ r: CGRect) }; extension CGRect { init(_ r: Rect) }; extension CGPoint { init(_ p: Point) }
```

The classifier is a port of AeroSpace `Sources/AppBundle/model/AxUiElementWindowType.swift` (`isWindowHeuristic`, `isWindowHeuristicOld`, `isDialogHeuristic`) with one change: an unknown window level never filters a window out. `NOTICE` credits AeroSpace (MIT, Copyright (c) 2023 Nikita Bobko) for that file's logic and the corner parking logic.

The AX thread follows AeroSpace's thread-per-app model: its own `CFRunLoop` (kept alive by an `NSMachPort`), an `AXObserver` for `kAXWindowCreatedNotification` and `kAXFocusedWindowChangedNotification` on the app and destroyed, (de)miniaturized, moved, resized and title-changed on each window, a 1 s messaging timeout, and every AX call on that thread. Frame writes go through a per-window slot (newest wins), are applied size, position, size with `AXEnhancedUserInterface` off for the batch, and are timed for the latency average. Moved and resized notifications within 150 ms after our own write are ignored. A window created while the left mouse button is down waits for `flushDelayed()` and reports `.registrationDelayed`. The thread reports `.scanned` after its first window scan, which the startup restore waits for. An `invalidUIElement` result forgets the window and reports it gone. Events go to the main queue.

- [ ] **Step 1: Write the failing classifier tests**

`Tests/HyprCoreTests/WindowClassifierTests.swift`:

```swift
import Testing
@testable import HyprCore

struct FakeWindow: WindowAttributeReader {
    var sub: String? = "AXStandardWindow"
    var name: String? = "Doc"
    var ident: String?
    var buttons: [WindowButton: Bool?] = [.close: true, .fullscreen: true, .zoom: true, .minimize: true]
    var focused: Bool? = false
    var main: Bool? = false
    var appFocused = false
    func subrole() -> String? { sub }
    func title() -> String? { name }
    func identifier() -> String? { ident }
    func hasButton(_ b: WindowButton) -> Bool { buttons[b] != nil }
    func isButtonEnabled(_ b: WindowButton) -> Bool? { buttons[b] ?? nil }
    func isFocused() -> Bool? { focused }
    func isMain() -> Bool? { main }
    func isAppFocusedWindow() -> Bool { appFocused }
}

@Suite struct WindowClassifierTests {
    func classify(_ w: FakeWindow, _ bundle: String? = "com.example.app", accessory: Bool = false, level: Int? = 0) -> WindowClassification {
        WindowClassifier.classify(w, bundleID: bundle, isAccessoryApp: accessory, windowLevel: level)
    }

    @Test func standardWindowIsNormal() { #expect(classify(FakeWindow()) == .normal) }

    @Test func dialogSubroleIsDialog() { #expect(classify(FakeWindow(sub: "AXDialog")) == .dialog) }

    @Test func buttonlessUnknownPopupIsNotAWindow() {
        #expect(classify(FakeWindow(sub: "AXUnknown", name: "", buttons: [:])) == .notAWindow)
    }

    @Test func ghosttyQuickTerminalAndSettings() {
        #expect(classify(FakeWindow(ident: "com.mitchellh.ghostty.quickTerminal"), "com.mitchellh.ghostty") == .notAWindow)
        let settings = FakeWindow(buttons: [.close: true, .fullscreen: false, .zoom: true, .minimize: true])
        #expect(classify(settings, "com.mitchellh.ghostty") == .dialog)
        #expect(classify(FakeWindow(), "com.mitchellh.ghostty") == .normal)
    }

    @Test func disabledFullscreenButtonFloatsExceptKnownApps() {
        let noFullscreen = FakeWindow(buttons: [.close: true, .fullscreen: false, .zoom: true, .minimize: true])
        #expect(classify(noFullscreen, "com.apple.calculator") == .dialog)
        #expect(classify(noFullscreen, "net.kovidgoyal.kitty") == .normal)
    }

    @Test func firefoxFamilyPictureInPictureFloats() {
        let pip = FakeWindow(buttons: [.close: true, .fullscreen: true, .zoom: true])
        #expect(classify(pip, "app.zen-browser.zen") == .dialog)
        #expect(classify(FakeWindow(), "app.zen-browser.zen") == .normal)
    }

    @Test func levelSensitiveAppsAndAccessoryApps() {
        #expect(classify(FakeWindow(), "com.tinyspeck.slackmacgap", level: 3) == .notAWindow)
        #expect(classify(FakeWindow(), "com.tinyspeck.slackmacgap", level: nil) == .normal)
        #expect(classify(FakeWindow(buttons: [.fullscreen: true]), accessory: true) == .notAWindow)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WindowClassifierTests`
Expected: FAIL, "cannot find type 'WindowAttributeReader' in scope".

- [ ] **Step 3: Implement the classifier**

`Sources/HyprCore/Platform/WindowClassifier.swift`:

```swift
import Foundation

public enum WindowButton: Sendable { case close, fullscreen, zoom, minimize }
public enum WindowClassification: Equatable, Sendable { case notAWindow, dialog, normal }

public protocol WindowAttributeReader {
    func subrole() -> String?
    func title() -> String?
    func identifier() -> String?
    func hasButton(_ b: WindowButton) -> Bool
    func isButtonEnabled(_ b: WindowButton) -> Bool?
    func isFocused() -> Bool?
    func isMain() -> Bool?
    func isAppFocusedWindow() -> Bool
}

public enum WindowClassifier {
    static let standard = "AXStandardWindow"
    static let firefoxFamily: Set<String> = ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly", "app.zen-browser.zen"]
    static let levelSensitive: Set<String> = firefoxFamily.union([
        "com.tinyspeck.slackmacgap", "com.google.Chrome", "com.brave.Browser", "com.timpler.screenstudio", "pl.maketheweb.cleanshotx",
        "com.googlecode.iterm2", "com.microsoft.Outlook", "com.openai.codex", "com.electron.wispr-flow",
    ])
    static let fullscreenButtonOptional: Set<String> = [
        "org.gimp.gimp-2.10", "com.google.Chrome", "com.apple.ActivityMonitor", "org.alacritty", "net.kovidgoyal.kitty",
        "com.github.wez.wezterm", "org.qutebrowser.qutebrowser", "com.googlecode.iterm2", "org.gnu.Emacs",
        "com.microsoft.VSCode", "com.vscodium", "com.valvesoftware.steam.helper",
    ]

    public static func classify(_ w: WindowAttributeReader, bundleID: String?, isAccessoryApp: Bool, windowLevel: Int?) -> WindowClassification {
        let id = bundleID ?? ""
        guard isWindow(w, id, isAccessoryApp, windowLevel) else { return .notAWindow }
        return isDialog(w, id, windowLevel) ? .dialog : .normal
    }

    static func isWindow(_ w: WindowAttributeReader, _ id: String, _ accessory: Bool, _ level: Int?) -> Bool {
        if let level, level != 0, levelSensitive.contains(id) { return false }
        if id == "com.mitchellh.ghostty" && w.identifier() == "com.mitchellh.ghostty.quickTerminal" { return false }
        if id == "com.apple.dt.Xcode" && w.identifier() == "open_quickly" { return false }
        if id == "com.googlecode.iterm2" && !w.hasButton(.fullscreen) { return false }
        if accessory && !w.hasButton(.close) && id != "com.valvesoftware.steam.helper" { return false }
        if id == "org.gnu.Emacs" && w.subrole() == "AXFloatingWindow" { return false }
        if !firefoxFamily.contains(id) { return isWindowOld(w, id) }
        return w.hasButton(.close) || w.hasButton(.fullscreen) || w.hasButton(.zoom) || w.hasButton(.minimize)
            || w.isFocused() == true || w.isMain() == true || w.isAppFocusedWindow() || w.subrole() == standard
    }

    static func isWindowOld(_ w: WindowAttributeReader, _ id: String) -> Bool {
        let subrole = w.subrole()
        let title = w.title() ?? ""
        if !w.hasButton(.close) && !w.hasButton(.fullscreen) && !w.hasButton(.zoom) && !w.hasButton(.minimize)
            && w.isFocused() == false && w.isMain() == false && !w.isAppFocusedWindow()
            && subrole != standard && (title.isEmpty || title == "Window") {
            return false
        }
        return subrole == standard || subrole == "AXDialog" || subrole == "AXFloatingWindow" || (id == "com.apple.finder" && subrole == "Quick Look")
    }

    static func isDialog(_ w: WindowAttributeReader, _ id: String, _ level: Int?) -> Bool {
        if id == "com.1password.1password", let level, level != 0 { return true }
        if id == "com.apple.iphonesimulator" { return true }
        if w.subrole() != standard && id != "org.qutebrowser.qutebrowser" { return true }
        if firefoxFamily.contains(id) && w.isButtonEnabled(.minimize) != true { return true }
        if id == "com.apple.PhotoBooth" { return true }
        if id == "com.mitchellh.ghostty" { return w.isButtonEnabled(.fullscreen) != true && w.isButtonEnabled(.close) == true }
        if w.isButtonEnabled(.fullscreen) != true && !fullscreenButtonOptional.contains(id) { return true }
        return false
    }
}
```

- [ ] **Step 4: Run the classifier tests**

Run: `swift test --filter WindowClassifierTests`
Expected: PASS.

- [ ] **Step 5: Write the AX helpers**

`Sources/HyprOSX/AX/AXSupport.swift`:

```swift
import AppKit
import ApplicationServices
import HyprCore

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

extension Rect {
    init(_ r: CGRect) { self.init(x: Double(r.origin.x), y: Double(r.origin.y), width: Double(r.width), height: Double(r.height)) }
}

extension CGRect {
    init(_ r: Rect) { self.init(x: r.x, y: r.y, width: r.width, height: r.height) }
}

extension CGPoint {
    init(_ p: Point) { self.init(x: p.x, y: p.y) }
}

enum AX {
    static func windowID(_ e: AXUIElement) -> WindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(e, &id) == .success && id != 0 ? id : nil
    }

    static func value(_ e: AXUIElement, _ attribute: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, attribute as CFString, &v) == .success ? v : nil
    }

    static func string(_ e: AXUIElement, _ a: String) -> String? { value(e, a) as? String }

    static func bool(_ e: AXUIElement, _ a: String) -> Bool? { (value(e, a) as? NSNumber)?.boolValue }

    static func element(_ e: AXUIElement, _ a: String) -> AXUIElement? {
        guard let v = value(e, a), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elements(_ e: AXUIElement, _ a: String) -> [AXUIElement] {
        guard let array = value(e, a) as? [AnyObject] else { return [] }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    static func frame(_ e: AXUIElement) -> Rect? {
        guard let p = value(e, kAXPositionAttribute), let s = value(e, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return Rect(CGRect(origin: point, size: size))
    }

    @discardableResult
    static func setPosition(_ e: AXUIElement, _ p: CGPoint) -> AXError {
        var point = p
        guard let v = AXValueCreate(.cgPoint, &point) else { return .failure }
        return AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, v)
    }

    @discardableResult
    static func setSize(_ e: AXUIElement, _ s: CGSize) -> AXError {
        var size = s
        guard let v = AXValueCreate(.cgSize, &size) else { return .failure }
        return AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, v)
    }

    @discardableResult
    static func setBool(_ e: AXUIElement, _ a: String, _ b: Bool) -> AXError {
        AXUIElementSetAttributeValue(e, a as CFString, b as CFTypeRef)
    }

    @discardableResult
    static func perform(_ e: AXUIElement, _ action: String) -> AXError {
        AXUIElementPerformAction(e, action as CFString)
    }

    static func windowLevel(_ id: WindowID) -> Int? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]] else { return nil }
        return list.first?[kCGWindowLayer as String] as? Int
    }
}

struct AXWindowAttributes: WindowAttributeReader {
    let window: AXUIElement
    let app: AXUIElement
    let windowID: WindowID

    func attribute(_ b: WindowButton) -> String {
        switch b {
        case .close: return kAXCloseButtonAttribute
        case .fullscreen: return kAXFullScreenButtonAttribute
        case .zoom: return kAXZoomButtonAttribute
        case .minimize: return kAXMinimizeButtonAttribute
        }
    }

    func subrole() -> String? { AX.string(window, kAXSubroleAttribute) }
    func title() -> String? { AX.string(window, kAXTitleAttribute) }
    func identifier() -> String? { AX.string(window, kAXIdentifierAttribute) }
    func hasButton(_ b: WindowButton) -> Bool { AX.element(window, attribute(b)) != nil }
    func isButtonEnabled(_ b: WindowButton) -> Bool? { AX.element(window, attribute(b)).flatMap { AX.bool($0, kAXEnabledAttribute) } }
    func isFocused() -> Bool? { AX.bool(window, kAXFocusedAttribute) }
    func isMain() -> Bool? { AX.bool(window, kAXMainAttribute) }
    func isAppFocusedWindow() -> Bool { AX.element(app, kAXFocusedWindowAttribute).flatMap(AX.windowID) == windowID }
}
```

- [ ] **Step 6: Write the per-app thread**

`Sources/HyprOSX/AX/AXAppThread.swift`:

```swift
import AppKit
import ApplicationServices
import HyprCore

enum AXAppEvent {
    case appeared(WindowSnapshot)
    case disappeared(WindowID)
    case minimized(WindowID, Bool)
    case nativeFullscreen(WindowID, Bool)
    case title(WindowID, String)
    case frame(WindowID, Rect)
    case focused(WindowID?)
    case registrationDelayed
    case scanned
}

private enum FrameJob {
    case frame(Rect)
    case position(Point)
}

private let windowNotifications = [
    kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
    kAXMovedNotification, kAXResizedNotification, kAXTitleChangedNotification,
]

private func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    Unmanaged<AXAppThread>.fromOpaque(refcon).takeUnretainedValue().handle(notification as String, element)
}

final class AXAppThread {
    let pid: pid_t
    let bundleID: String
    let appName: String
    private let isAccessory: Bool
    private let onEvent: (AXAppEvent) -> Void
    private let app: AXUIElement
    private var runLoop: CFRunLoop?
    private let started = DispatchSemaphore(value: 0)
    private var observer: AXObserver?
    private var windows: [WindowID: AXUIElement] = [:]
    private var fullscreen: Set<WindowID> = []
    private var delayed: [AXUIElement] = []
    private var suppressUntil: [WindowID: UInt64] = [:]
    private let lock = NSLock()
    private var jobs: [WindowID: FrameJob] = [:]
    private var draining = false
    private var latency = 0.0
    private var calls = 0
    private var errors = 0
    private var screenSizes: [Size] = []

    init(pid: pid_t, bundleID: String, appName: String, isAccessory: Bool, onEvent: @escaping (AXAppEvent) -> Void) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.isAccessory = isAccessory
        self.onEvent = onEvent
        self.app = AXUIElementCreateApplication(pid)
    }

    var averageLatencyMs: Double { lock.lock(); defer { lock.unlock() }; return latency }
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }
    var errorCount: Int { lock.lock(); defer { lock.unlock() }; return errors }

    func start() {
        let thread = Thread { [weak self] in self?.threadMain() }
        thread.name = "AX \(appName) \(pid)"
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = started.wait(timeout: .now() + 2)
    }

    func stop() {
        perform { [weak self] in
            guard let self else { return }
            if let obs = self.observer {
                for (_, e) in self.windows { for n in windowNotifications { AXObserverRemoveNotification(obs, e, n as CFString) } }
                AXObserverRemoveNotification(obs, self.app, kAXWindowCreatedNotification as CFString)
                AXObserverRemoveNotification(obs, self.app, kAXFocusedWindowChangedNotification as CFString)
            }
            self.windows = [:]
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }

    func updateScreenSizes(_ sizes: [Size]) {
        lock.lock()
        screenSizes = sizes
        lock.unlock()
    }

    private func threadMain() {
        runLoop = CFRunLoopGetCurrent()
        started.signal()
        RunLoop.current.add(NSMachPort(), forMode: .default)
        AXUIElementSetMessagingTimeout(app, 1.0)
        var obs: AXObserver?
        if AXObserverCreate(pid, axCallback, &obs) == .success, let obs {
            observer = obs
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
            let ref = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(obs, app, kAXWindowCreatedNotification as CFString, ref)
            AXObserverAddNotification(obs, app, kAXFocusedWindowChangedNotification as CFString, ref)
        }
        scan()
        emit(.scanned)
        CFRunLoopRun()
    }

    private func perform(_ block: @escaping () -> Void) {
        guard let rl = runLoop else { return }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(rl)
    }

    private func emit(_ event: AXAppEvent) {
        let handler = onEvent
        DispatchQueue.main.async { handler(event) }
    }

    func rescan() { perform { [weak self] in self?.scan() } }

    func flush(timeout: TimeInterval) {
        let done = DispatchSemaphore(value: 0)
        perform { done.signal() }
        _ = done.wait(timeout: .now() + timeout)
    }

    func flushDelayed() {
        perform { [weak self] in
            guard let self else { return }
            let pending = self.delayed
            self.delayed = []
            for e in pending { if let id = AX.windowID(e), self.windows[id] == nil { self.register(e, id: id) } }
        }
    }

    private func scan() {
        var seen = Set<WindowID>()
        for e in AX.elements(app, kAXWindowsAttribute) {
            guard let id = AX.windowID(e) else { continue }
            seen.insert(id)
            if windows[id] == nil { register(e, id: id) }
        }
        for id in Array(windows.keys) where !seen.contains(id) { forget(id) }
        reportFocused()
    }

    private func register(_ e: AXUIElement, id: WindowID) {
        if CGEventSource.buttonState(.combinedSessionState, button: .left) {
            delayed.append(e)
            emit(.registrationDelayed)
            return
        }
        let kind = WindowClassifier.classify(AXWindowAttributes(window: e, app: app, windowID: id), bundleID: bundleID,
                                             isAccessoryApp: isAccessory, windowLevel: AX.windowLevel(id))
        guard kind != .notAWindow else { return }
        windows[id] = e
        if let obs = observer {
            let ref = Unmanaged.passUnretained(self).toOpaque()
            for n in windowNotifications { AXObserverAddNotification(obs, e, n as CFString, ref) }
        }
        let snapshot = WindowSnapshot(id: id, pid: pid, bundleID: bundleID, appName: appName, title: AX.string(e, kAXTitleAttribute) ?? "",
                                      frame: AX.frame(e) ?? .zero, kind: kind == .dialog ? .dialog : .normal)
        emit(.appeared(snapshot))
        if AX.bool(e, kAXMinimizedAttribute) == true { emit(.minimized(id, true)) }
    }

    private func forget(_ id: WindowID) {
        guard let e = windows.removeValue(forKey: id) else { return }
        if let obs = observer { for n in windowNotifications { AXObserverRemoveNotification(obs, e, n as CFString) } }
        fullscreen.remove(id)
        suppressUntil[id] = nil
        emit(.disappeared(id))
    }

    private func reportFocused() {
        guard let e = AX.element(app, kAXFocusedWindowAttribute), let id = AX.windowID(e) else {
            emit(.focused(nil))
            return
        }
        if windows[id] == nil { register(e, id: id) }
        emit(.focused(windows[id] == nil ? nil : id))
    }

    private func knownID(_ e: AXUIElement) -> WindowID? {
        if let id = AX.windowID(e), windows[id] != nil { return id }
        return windows.first { CFEqual($0.value, e) }?.key
    }

    fileprivate func handle(_ notification: String, _ element: AXUIElement) {
        switch notification {
        case kAXWindowCreatedNotification:
            if let id = AX.windowID(element), windows[id] == nil { register(element, id: id) }
        case kAXFocusedWindowChangedNotification:
            reportFocused()
        case kAXUIElementDestroyedNotification:
            if let id = windows.first(where: { CFEqual($0.value, element) })?.key { forget(id) }
        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            if let id = knownID(element) { emit(.minimized(id, notification == kAXWindowMiniaturizedNotification)) }
        case kAXMovedNotification, kAXResizedNotification:
            guard let id = knownID(element) else { return }
            if let until = suppressUntil[id], DispatchTime.now().uptimeNanoseconds < until { return }
            guard let frame = AX.frame(element) else { return }
            if notification == kAXResizedNotification {
                lock.lock()
                let sizes = screenSizes
                lock.unlock()
                let fillsScreen = sizes.contains { abs($0.width - frame.width) < 1 && abs($0.height - frame.height) < 1 }
                if fillsScreen || fullscreen.contains(id) {
                    let isFull = AX.bool(element, "AXFullScreen") == true
                    if isFull != fullscreen.contains(id) {
                        if isFull { fullscreen.insert(id) } else { fullscreen.remove(id) }
                        emit(.nativeFullscreen(id, isFull))
                        return
                    }
                }
            }
            emit(.frame(id, frame))
        case kAXTitleChangedNotification:
            if let id = knownID(element) { emit(.title(id, AX.string(element, kAXTitleAttribute) ?? "")) }
        default:
            break
        }
    }

    func setFrame(_ id: WindowID, _ frame: Rect) { enqueue(id, .frame(frame)) }

    func setPosition(_ id: WindowID, _ p: Point) { enqueue(id, .position(p)) }

    private func enqueue(_ id: WindowID, _ job: FrameJob) {
        lock.lock()
        jobs[id] = job
        let schedule = !draining
        draining = true
        lock.unlock()
        if schedule { perform { [weak self] in self?.drain() } }
    }

    private func drain() {
        let eui = AX.bool(app, "AXEnhancedUserInterface") == true
        if eui { AX.setBool(app, "AXEnhancedUserInterface", false) }
        defer { if eui { AX.setBool(app, "AXEnhancedUserInterface", true) } }
        while true {
            lock.lock()
            let batch = jobs
            jobs = [:]
            if batch.isEmpty {
                draining = false
                lock.unlock()
                return
            }
            lock.unlock()
            for (id, job) in batch {
                guard let e = windows[id] else { continue }
                let start = DispatchTime.now().uptimeNanoseconds
                var result: AXError
                switch job {
                case .frame(let r):
                    let size = CGSize(width: r.width, height: r.height)
                    AX.setSize(e, size)
                    AX.setPosition(e, CGPoint(x: r.x, y: r.y))
                    result = AX.setSize(e, size)
                case .position(let p):
                    result = AX.setPosition(e, CGPoint(p))
                }
                let end = DispatchTime.now().uptimeNanoseconds
                suppressUntil[id] = end + 150_000_000
                lock.lock()
                calls += 1
                if result != .success { errors += 1 }
                let ms = Double(end - start) / 1_000_000
                latency = calls == 1 ? ms : latency * 0.8 + ms * 0.2
                lock.unlock()
                if result == .invalidUIElement { forget(id) }
            }
        }
    }

    func focus(_ id: WindowID) {
        perform { [weak self] in
            guard let self, let e = self.windows[id] else { return }
            AX.setBool(e, kAXMainAttribute, true)
            AX.perform(e, kAXRaiseAction)
            NSRunningApplication(processIdentifier: self.pid)?.activate(options: .activateIgnoringOtherApps)
        }
    }

    func raise(_ id: WindowID) {
        perform { [weak self] in
            guard let e = self?.windows[id] else { return }
            AX.perform(e, kAXRaiseAction)
        }
    }

    func close(_ id: WindowID) {
        perform { [weak self] in
            guard let e = self?.windows[id], let button = AX.element(e, kAXCloseButtonAttribute) else { return }
            AX.perform(button, kAXPressAction)
        }
    }
}
```

- [ ] **Step 7: Write NOTICE and build**

`NOTICE`:

```
HyprOSX ports logic from AeroSpace (https://github.com/nikitabobko/AeroSpace):
the window and dialog heuristics (Sources/AppBundle/model/AxUiElementWindowType.swift),
the per-application Accessibility thread model, and the hidden-window corner choice.

AeroSpace is licensed under the MIT License:
Copyright (c) 2023 Nikita Bobko
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.

HyprOSX follows the behavior and configuration language of Hyprland (https://github.com/hyprwm/Hyprland, BSD-3-Clause).
```

Run: `swift build`
Expected: the package builds (warnings about `activateIgnoringOtherApps` deprecation are acceptable). Run `swift test` and expect all suites to pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/HyprCore/Platform Sources/HyprOSX/AX Tests/HyprCoreTests/WindowClassifierTests.swift NOTICE
git commit -m "feat: add window classification and the per-app Accessibility layer"
```

---
### Task 18: Monitors, spawning, app tracking and the effect executor

**Files:**
- Create: `Sources/HyprCore/Platform/MonitorLayout.swift`, `Sources/HyprCore/Platform/Spawner.swift`, `Sources/HyprOSX/Platform/Screens.swift`, `Sources/HyprOSX/Platform/AppTracker.swift`, `Sources/HyprOSX/Platform/EffectExecutor.swift`, `Sources/HyprOSX/Platform/MouseUpMonitor.swift`
- Test: `Tests/HyprCoreTests/MonitorLayoutTests.swift`, `Tests/HyprCoreTests/SpawnerTests.swift`

**Interfaces:**
- Consumes: `MonitorInfo`, `Rect`, `EnvVar`, `PlatformEvent`, `Effect`, `WindowID` (HyprCore); `AXAppThread`, `AXAppEvent` (Task 17).
- Produces:

```swift
// HyprCore
public struct ScreenDescription: Equatable, Sendable { public var name: String; public var frame: Rect; public var visibleFrame: Rect }   // Cocoa coordinates
public enum MonitorLayout { public static func infos(_ screens: [ScreenDescription]) -> [MonitorInfo] }                                  // first screen = menu bar screen
public struct SpawnError: Error, Equatable, Sendable { public var message: String }
public enum Spawner {
    public static var isAvailable: Bool { get }
    public static func responsiblePID(for pid: pid_t) -> pid_t?
    public static func environment(base: [String: String], extra: [EnvVar]) -> [String: String]
    public static func spawn(_ command: String, environment: [String: String]) -> Result<pid_t, SpawnError>
}
// HyprOSX
enum Screens { static func current() -> [MonitorInfo]; static func cursor() -> Point }
final class AppTracker {
    init(onEvent: @escaping (PlatformEvent) -> Void)
    var onDelayedRegistration: () -> Void; var onDragStarted: () -> Void; var onInitialScanDone: () -> Void
    var screenSizes: [Size]
    private(set) var threads: [pid_t: AXAppThread]
    func start(); func stop(); func hide(_ pid: pid_t); func unhide(_ pid: pid_t); func unhideAllHiddenByUs()
}
final class EffectExecutor {
    init(tracker: AppTracker, windowPID: @escaping (WindowID) -> pid_t?, environment: @escaping () -> [String: String])
    var onSpawned: (Int, pid_t) -> Void; var onSpawnFailed: (String) -> Void; var onAppEffect: (Effect) -> Void
    func execute(_ effects: [Effect])
}
final class MouseUpMonitor { init(onMouseUp: @escaping () -> Void); func arm() }
```

`Spawner` lives in `HyprCore` (Foundation and Darwin only) so the security behavior is unit-tested; this replaces `Sources/HyprOSX/Platform/Spawner.swift` from the file map. Monitor 0 is the first `NSScreen` (the menu bar screen); the others get ids by their top-left corner, left to right, then top to bottom. A repeated monitor name gets ` (2)`, ` (3)` in id order. AX coordinates: `y = primaryHeight - (cocoaY + height)`.

Every spawned command runs as `/bin/sh -c COMMAND` with responsibility disclaimed, a new session, stdin, stdout and stderr on `/dev/null`, no other inherited file descriptors, an empty signal mask and every signal at its default action (HyprOSX ignores SIGTERM, SIGINT, SIGHUP and SIGPIPE for its own handlers, and ignored signals would otherwise pass to the child). A process source reaps each child.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/MonitorLayoutTests.swift`:

```swift
import Testing
@testable import HyprCore

@Suite struct MonitorLayoutTests {
    @Test func builtInScreenFlipsToTopLeftOrigin() {
        let infos = MonitorLayout.infos([ScreenDescription(name: "Built-in Retina Display", frame: Rect(x: 0, y: 0, width: 1512, height: 982),
                                                           visibleFrame: Rect(x: 0, y: 0, width: 1512, height: 950))])
        #expect(infos == [MonitorInfo(id: 0, name: "Built-in Retina Display", frame: Rect(x: 0, y: 0, width: 1512, height: 982),
                                      visibleFrame: Rect(x: 0, y: 32, width: 1512, height: 950))])
    }

    @Test func laptopBelowUltrawide() {
        let infos = MonitorLayout.infos([
            ScreenDescription(name: "PHL 499P9", frame: Rect(x: 0, y: 0, width: 5120, height: 1440), visibleFrame: Rect(x: 0, y: 0, width: 5120, height: 1415)),
            ScreenDescription(name: "Built-in Retina Display", frame: Rect(x: 1804, y: -982, width: 1512, height: 982),
                              visibleFrame: Rect(x: 1804, y: -982, width: 1512, height: 982)),
        ])
        #expect(infos.map(\.id) == [0, 1])
        #expect(infos[0].visibleFrame == Rect(x: 0, y: 25, width: 5120, height: 1415))
        #expect(infos[1].frame == Rect(x: 1804, y: 1440, width: 1512, height: 982))
    }

    @Test func idsFollowPositionAndRepeatedNamesGetSuffixes() {
        let infos = MonitorLayout.infos([
            ScreenDescription(name: "DELL", frame: Rect(x: 0, y: 0, width: 2560, height: 1440), visibleFrame: Rect(x: 0, y: 0, width: 2560, height: 1415)),
            ScreenDescription(name: "DELL", frame: Rect(x: 2560, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 2560, y: 0, width: 1920, height: 1080)),
            ScreenDescription(name: "DELL", frame: Rect(x: -1920, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: -1920, y: 0, width: 1920, height: 1080)),
        ])
        #expect(infos.map(\.name) == ["DELL", "DELL (2)", "DELL (3)"])
        #expect(infos[1].frame.x == -1920)
        #expect(infos[2].frame.x == 2560)
    }

    @Test func noScreensGivesNoMonitors() {
        #expect(MonitorLayout.infos([]).isEmpty)
    }
}
```

`Tests/HyprCoreTests/SpawnerTests.swift`:

```swift
import Testing
import Foundation
@testable import HyprCore

@Suite struct SpawnerTests {
    @Test func spawnedCommandIsItsOwnResponsibleProcess() throws {
        #expect(Spawner.isAvailable)
        let pid = try Spawner.spawn("/bin/sleep 1", environment: ProcessInfo.processInfo.environment).get()
        #expect(Spawner.responsiblePID(for: pid) == pid)
        #expect(Spawner.responsiblePID(for: pid) != Spawner.responsiblePID(for: getpid()))
        kill(pid, SIGKILL)
    }

    @Test func environmentPrefixesPathAndAddsEnvValues() {
        let env = Spawner.environment(base: ["HOME": "/Users/x", "PATH": "/usr/bin:/bin"], extra: [EnvVar(name: "HYPROSX_TEST", value: "ok")])
        #expect(env["PATH"] == "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/Users/x/.local/bin:/usr/bin:/bin")
        #expect(env["HYPROSX_TEST"] == "ok")
        #expect(Spawner.environment(base: ["HOME": "/h"], extra: [])["PATH"] == "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/h/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    @Test func commandRunsThroughTheShellWithTheEnvironment() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hyprosx-spawn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("out").path
        let env = Spawner.environment(base: ProcessInfo.processInfo.environment, extra: [EnvVar(name: "HYPROSX_TEST", value: "a b")])
        _ = try Spawner.spawn("printf '%s' \"$HYPROSX_TEST\" > '\(out)'", environment: env).get()
        var text: String?
        for _ in 0..<200 where text != "a b" {
            usleep(10_000)
            text = try? String(contentsOfFile: out, encoding: .utf8)
        }
        #expect(text == "a b")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter 'MonitorLayoutTests|SpawnerTests'`
Expected: FAIL, "cannot find 'MonitorLayout' in scope".

- [ ] **Step 3: Implement the monitor layout and the spawner**

`Sources/HyprCore/Platform/MonitorLayout.swift`:

```swift
import Foundation

public struct ScreenDescription: Equatable, Sendable {
    public var name: String
    public var frame: Rect
    public var visibleFrame: Rect
    public init(name: String, frame: Rect, visibleFrame: Rect) { self.name = name; self.frame = frame; self.visibleFrame = visibleFrame }
}

public enum MonitorLayout {
    public static func infos(_ screens: [ScreenDescription]) -> [MonitorInfo] {
        guard let primary = screens.first else { return [] }
        func flip(_ r: Rect) -> Rect { Rect(x: r.x, y: primary.frame.height - (r.y + r.height), width: r.width, height: r.height) }
        let flipped = screens.map { ($0.name, flip($0.frame), flip($0.visibleFrame)) }
        let rest = flipped.dropFirst().sorted { ($0.1.x, $0.1.y) < ($1.1.x, $1.1.y) }
        var seen: [String: Int] = [:]
        return ([flipped[0]] + rest).enumerated().map { index, screen in
            seen[screen.0, default: 0] += 1
            let count = seen[screen.0]!
            return MonitorInfo(id: index, name: count == 1 ? screen.0 : "\(screen.0) (\(count))", frame: screen.1, visibleFrame: screen.2)
        }
    }
}
```

`Sources/HyprCore/Platform/Spawner.swift`:

```swift
import Foundation

public struct SpawnError: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

public enum Spawner {
    typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    typealias ResponsibleFor = @convention(c) (pid_t) -> pid_t

    private static let handle = dlopen(nil, RTLD_NOW)
    private static let setDisclaim = dlsym(handle, "responsibility_spawnattrs_setdisclaim").map { unsafeBitCast($0, to: SetDisclaim.self) }
    private static let responsibleFor = dlsym(handle, "responsibility_get_pid_responsible_for_pid").map { unsafeBitCast($0, to: ResponsibleFor.self) }
    private static let reaperQueue = DispatchQueue(label: "dev.hyprosx.reaper")
    private static var reapers: [pid_t: DispatchSourceProcess] = [:]

    public static var isAvailable: Bool { setDisclaim != nil }

    public static func responsiblePID(for pid: pid_t) -> pid_t? { responsibleFor.map { $0(pid) } }

    public static func environment(base: [String: String], extra: [EnvVar]) -> [String: String] {
        var env = base
        let home = base["HOME"] ?? NSHomeDirectory()
        env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:\(home)/.local/bin:" + (base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        for e in extra { env[e.name] = e.value }
        return env
    }

    public static func spawn(_ command: String, environment: [String: String]) -> Result<pid_t, SpawnError> {
        guard let setDisclaim else { return .failure(SpawnError("commands are disabled: responsibility_spawnattrs_setdisclaim is missing")) }
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        posix_spawnattr_setsigmask(&attr, &noSignals)
        posix_spawnattr_setsigdefault(&attr, &allSignals)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        guard setDisclaim(&attr, 1) == 0 else { return .failure(SpawnError("commands are disabled: cannot disclaim responsibility")) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        let argv: [UnsafeMutablePointer<CChar>?] = ["/bin/sh", "-c", command].map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, "/bin/sh", &actions, &attr, argv, envp)
        guard rc == 0 else { return .failure(SpawnError("cannot start command: \(String(cString: strerror(rc)))")) }
        reap(pid)
        return .success(pid)
    }

    private static func reap(_ pid: pid_t) {
        reaperQueue.async {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: reaperQueue)
            let finish = {
                var status: Int32 = 0
                guard waitpid(pid, &status, WNOHANG) == pid else { return }
                reapers.removeValue(forKey: pid)?.cancel()
            }
            source.setEventHandler(handler: finish)
            reapers[pid] = source
            source.resume()
            finish()
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter 'MonitorLayoutTests|SpawnerTests'`
Expected: PASS (7 tests).

- [ ] **Step 5: Write the platform side**

`Sources/HyprOSX/Platform/Screens.swift`:

```swift
import AppKit
import HyprCore

enum Screens {
    static func current() -> [MonitorInfo] {
        MonitorLayout.infos(NSScreen.screens.map {
            ScreenDescription(name: $0.localizedName, frame: Rect($0.frame), visibleFrame: Rect($0.visibleFrame))
        })
    }

    static func cursor() -> Point {
        let p = CGEvent(source: nil)?.location ?? .zero
        return Point(x: Double(p.x), y: Double(p.y))
    }
}
```

`Sources/HyprOSX/Platform/AppTracker.swift`:

```swift
import AppKit
import HyprCore

final class AppTracker {
    static let skippedBundleIDs: Set<String> = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine"]

    private let onEvent: (PlatformEvent) -> Void
    var onDelayedRegistration: () -> Void = {}
    var onDragStarted: () -> Void = {}
    var onInitialScanDone: () -> Void = {}
    var screenSizes: [Size] = [] {
        didSet { threads.values.forEach { $0.updateScreenSizes(screenSizes) } }
    }
    private(set) var threads: [pid_t: AXAppThread] = [:]
    private var observers: [NSObjectProtocol] = []
    private var pendingScans: Set<pid_t> = []
    private var appearedAt: [WindowID: TimeInterval] = [:]
    private var hiddenByUs: Set<pid_t> = []

    init(onEvent: @escaping (PlatformEvent) -> Void) { self.onEvent = onEvent }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let handlers: [(Notification.Name, (NSRunningApplication) -> Void)] = [
            (NSWorkspace.didLaunchApplicationNotification, { [weak self] in self?.launched($0) }),
            (NSWorkspace.didTerminateApplicationNotification, { [weak self] in self?.terminated($0) }),
            (NSWorkspace.didActivateApplicationNotification, { [weak self] in self?.activated($0) }),
            (NSWorkspace.didHideApplicationNotification, { [weak self] in self?.hidden($0) }),
            (NSWorkspace.didUnhideApplicationNotification, { [weak self] in self?.unhidden($0) }),
        ]
        observers = handlers.map { name, handler in
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { handler(app) }
            }
        }
        let apps = NSWorkspace.shared.runningApplications.filter(isTracked)
        pendingScans = Set(apps.map(\.processIdentifier))
        apps.forEach(register)
        if pendingScans.isEmpty { onInitialScanDone() }
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        threads.values.forEach { $0.stop() }
        threads = [:]
        pendingScans = []
    }

    func isTracked(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != getpid() && !Self.skippedBundleIDs.contains(app.bundleIdentifier ?? "")
    }

    private func register(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard threads[pid] == nil else { return }
        let thread = AXAppThread(pid: pid, bundleID: app.bundleIdentifier ?? "", appName: app.localizedName ?? "",
                                 isAccessory: app.activationPolicy == .accessory) { [weak self] event in self?.received(event, pid: pid) }
        thread.updateScreenSizes(screenSizes)
        threads[pid] = thread
        thread.start()
    }

    private func received(_ event: AXAppEvent, pid: pid_t) {
        guard threads[pid] != nil else { return }
        switch event {
        case .appeared(let s):
            appearedAt[s.id] = ProcessInfo.processInfo.systemUptime
            onEvent(.windowAppeared(s))
        case .disappeared(let id):
            appearedAt[id] = nil
            onEvent(.windowDisappeared(id))
        case .minimized(let id, let on):
            onEvent(on ? .windowSuspended(id, .minimized) : .windowResumed(id))
        case .nativeFullscreen(let id, let on):
            onEvent(on ? .windowSuspended(id, .nativeFullscreen) : .windowResumed(id))
        case .title(let id, let title):
            let early = appearedAt[id].map { ProcessInfo.processInfo.systemUptime - $0 < 1 } ?? false
            onEvent(.windowTitleChanged(id, title, early: early))
        case .frame(let id, let frame):
            let userDriven = CGEventSource.buttonState(.combinedSessionState, button: .left)
            if userDriven { onDragStarted() }
            onEvent(.windowFrameChanged(id, frame, userDriven: userDriven))
        case .focused(let id):
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            onEvent(.focusChanged(id))
        case .registrationDelayed:
            onDelayedRegistration()
        case .scanned:
            if pendingScans.remove(pid) != nil && pendingScans.isEmpty { onInitialScanDone() }
        }
    }

    private func launched(_ app: NSRunningApplication) {
        if isTracked(app) { register(app) }
    }

    private func terminated(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        hiddenByUs.remove(pid)
        guard let thread = threads.removeValue(forKey: pid) else { return }
        thread.stop()
        if pendingScans.remove(pid) != nil && pendingScans.isEmpty { onInitialScanDone() }
        onEvent(.appTerminated(pid: pid))
    }

    private func activated(_ app: NSRunningApplication) {
        if let thread = threads[app.processIdentifier] { thread.rescan() } else if isTracked(app) { register(app) }
    }

    private func hidden(_ app: NSRunningApplication) {
        guard threads[app.processIdentifier] != nil else { return }
        onEvent(.appHidden(pid: app.processIdentifier, byUser: !hiddenByUs.contains(app.processIdentifier)))
    }

    private func unhidden(_ app: NSRunningApplication) {
        hiddenByUs.remove(app.processIdentifier)
        guard threads[app.processIdentifier] != nil else { return }
        onEvent(.appUnhidden(pid: app.processIdentifier))
    }

    func hide(_ pid: pid_t) {
        hiddenByUs.insert(pid)
        NSRunningApplication(processIdentifier: pid)?.hide()
    }

    func unhide(_ pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.unhide()
    }

    func unhideAllHiddenByUs() {
        hiddenByUs.forEach { NSRunningApplication(processIdentifier: $0)?.unhide() }
        hiddenByUs = []
    }
}
```

`Sources/HyprOSX/Platform/EffectExecutor.swift`:

```swift
import AppKit
import HyprCore

final class EffectExecutor {
    private let tracker: AppTracker
    private let windowPID: (WindowID) -> pid_t?
    private let environment: () -> [String: String]
    var onSpawned: (Int, pid_t) -> Void = { _, _ in }
    var onSpawnFailed: (String) -> Void = { _ in }
    var onAppEffect: (Effect) -> Void = { _ in }

    init(tracker: AppTracker, windowPID: @escaping (WindowID) -> pid_t?, environment: @escaping () -> [String: String]) {
        self.tracker = tracker
        self.windowPID = windowPID
        self.environment = environment
    }

    func execute(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .setFrames(let changes):
                for c in changes { thread(c.id)?.setFrame(c.id, c.frame) }
            case .park(let parks):
                for p in parks { thread(p.id)?.setPosition(p.id, p.origin) }
            case .focus(let id):
                thread(id)?.focus(id)
            case .raise(let id):
                thread(id)?.raise(id)
            case .close(let id):
                thread(id)?.close(id)
            case .signal(let pid, let signal):
                kill(pid, signal)
            case .hideApp(let pid):
                tracker.hide(pid)
            case .unhideApp(let pid):
                tracker.unhide(pid)
            case .spawn(let command, let token):
                switch Spawner.spawn(command, environment: environment()) {
                case .success(let pid): if let token { onSpawned(token, pid) }
                case .failure(let error): onSpawnFailed(error.message)
                }
            case .warpCursor(let p):
                CGWarpMouseCursorPosition(CGPoint(p))
                CGAssociateMouseAndMouseCursorPosition(1)
            case .submapChanged, .statusChanged, .saveState, .reloadConfig, .exitApp:
                onAppEffect(effect)
            }
        }
    }

    private func thread(_ id: WindowID) -> AXAppThread? {
        windowPID(id).flatMap { tracker.threads[$0] }
    }
}
```

`Sources/HyprOSX/Platform/MouseUpMonitor.swift`:

```swift
import AppKit

final class MouseUpMonitor {
    private var monitor: Any?
    private let onMouseUp: () -> Void

    init(onMouseUp: @escaping () -> Void) { self.onMouseUp = onMouseUp }

    func arm() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.fire() }
        if !CGEventSource.buttonState(.combinedSessionState, button: .left) {
            DispatchQueue.main.async { [weak self] in self?.fire() }
        }
    }

    private func fire() {
        guard let m = monitor else { return }
        NSEvent.removeMonitor(m)
        monitor = nil
        onMouseUp()
    }
}
```

The monitor exists only while a drag or a delayed registration waits, so plain clicks cost nothing.

- [ ] **Step 6: Build and run every test**

Run: `swift build && swift test`
Expected: the build succeeds and all suites pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/HyprCore/Platform Sources/HyprOSX/Platform Tests/HyprCoreTests/MonitorLayoutTests.swift Tests/HyprCoreTests/SpawnerTests.swift
git commit -m "feat: add monitor layout, disclaimed spawning, app tracking and effect executor"
```

---
### Task 19: Hotkeys and submaps

**Files:**
- Create: `Sources/HyprCore/Input/HotkeyPlan.swift`, `Sources/HyprOSX/Input/HotkeyManager.swift`
- Test: `Tests/HyprCoreTests/HotkeyPlanTests.swift`

**Interfaces:**
- Consumes: `Bind`, `BindTrigger`, `BindFlags`, `Modifiers`, `BindParser`, `Diagnostic` (Tasks 1 and 4).
- Produces:

```swift
// HyprCore
public struct HotkeyGroup: Equatable, Sendable {
    public var modifiers: Modifiers; public var keyCode: UInt16
    public var press: [Bind]; public var release: [Bind]; public var repeats: Bool
}
public enum HotkeyPlan {
    public static func groups(_ binds: [Bind]) -> [HotkeyGroup]           // keyboard binds only, grouped by modifiers and key, file order kept
    public static func carbonModifiers(_ m: Modifiers) -> UInt32
}
// HyprOSX
final class HotkeyManager {
    init(run: @escaping ([Bind]) -> Void)
    private(set) var failures: [Diagnostic]
    func install(); func activate(_ binds: [Bind]); func deactivate()
}
```

A key press runs the group's non-release binds in file order; the caller merges their effects into one batch. A `binde` bind repeats while the key is held: first after `NSEvent.keyRepeatDelay`, then every `NSEvent.keyRepeatInterval`, only while the key is still down (checked with `CGEventSource.keyState` on each tick, so a lost release never leaves a repeat running). A release runs the `bindr` binds. `activate` replaces every registration; the app calls it at start, after a reload and on `.submapChanged`, with `world.activeBinds`. A failed registration becomes a warning at the bind's file and line.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/HotkeyPlanTests.swift`:

```swift
import Testing
import Foundation
@testable import HyprCore

@Suite struct HotkeyPlanTests {
    func bind(_ line: String) -> Bind {
        let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return BindParser.parse(keyword: parts[0], value: parts[1], submap: "", location: SourceLocation(file: "t.conf", line: 1)).bind!
    }

    @Test func groupsByKeyInFileOrder() {
        let groups = HotkeyPlan.groups([
            bind("bind = ALT, H, movefocus, l"),
            bind("bind = CTRL CMD, 1, setfloating"),
            bind("bind = CTRL CMD, 1, resizeactive, exact 33% 100%"),
            bind("bindr = ALT, H, exec, true"),
            bind("binde = ALT SHIFT, minus, resizeactive, -50 0"),
            bind("bindm = CTRL ALT, mouse:272, movewindow"),
            bind("bind = CTRL ALT, mouse_down, workspace, e+1"),
        ])
        #expect(groups.count == 3)
        #expect(groups[0].modifiers == .option && groups[0].keyCode == 0x04)
        #expect(groups[0].press.map(\.dispatcher) == ["movefocus"])
        #expect(groups[0].release.map(\.dispatcher) == ["exec"])
        #expect(!groups[0].repeats)
        #expect(groups[1].press.map(\.dispatcher) == ["setfloating", "resizeactive"])
        #expect(groups[2].keyCode == 0x1B && groups[2].repeats)
    }

    @Test func sameKeyWithOtherModifiersIsAnotherGroup() {
        let groups = HotkeyPlan.groups([bind("bind = ALT, 1, workspace, 1"), bind("bind = ALT SHIFT, 1, movetoworkspace, 1")])
        #expect(groups.map(\.modifiers) == [.option, [.option, .shift]])
    }

    @Test func carbonModifierMask() {
        #expect(HotkeyPlan.carbonModifiers([.command, .shift]) == 0x0100 | 0x0200)
        #expect(HotkeyPlan.carbonModifiers([.option, .control]) == 0x0800 | 0x1000)
        #expect(HotkeyPlan.carbonModifiers([]) == 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter HotkeyPlanTests`
Expected: FAIL, "cannot find 'HotkeyPlan' in scope".

- [ ] **Step 3: Implement the plan**

`Sources/HyprCore/Input/HotkeyPlan.swift`:

```swift
import Foundation

public struct HotkeyGroup: Equatable, Sendable {
    public var modifiers: Modifiers
    public var keyCode: UInt16
    public var press: [Bind] = []
    public var release: [Bind] = []
    public var repeats = false
}

public enum HotkeyPlan {
    public static func groups(_ binds: [Bind]) -> [HotkeyGroup] {
        var groups: [HotkeyGroup] = []
        for b in binds where !b.flags.contains(.mouse) {
            guard case .key(let code) = b.trigger else { continue }
            let index = groups.firstIndex { $0.modifiers == b.modifiers && $0.keyCode == code } ?? {
                groups.append(HotkeyGroup(modifiers: b.modifiers, keyCode: code))
                return groups.count - 1
            }()
            if b.flags.contains(.release) {
                groups[index].release.append(b)
            } else {
                groups[index].press.append(b)
                if b.flags.contains(.repeating) { groups[index].repeats = true }
            }
        }
        return groups
    }

    public static func carbonModifiers(_ m: Modifiers) -> UInt32 {
        (m.contains(.command) ? 0x0100 : 0) | (m.contains(.shift) ? 0x0200 : 0) | (m.contains(.option) ? 0x0800 : 0) | (m.contains(.control) ? 0x1000 : 0)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter HotkeyPlanTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Write the Carbon manager**

`Sources/HyprOSX/Input/HotkeyManager.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import HyprCore

final class HotkeyManager {
    private let run: ([Bind]) -> Void
    private var handler: EventHandlerRef?
    private var refs: [EventHotKeyRef] = []
    private var groups: [UInt32: HotkeyGroup] = [:]
    private var repeatTimer: Timer?
    private var heldID: UInt32?
    private(set) var failures: [Diagnostic] = []

    init(run: @escaping ([Bind]) -> Void) { self.run = run }

    func install() {
        guard handler == nil else { return }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.hotkey(id.id, pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed))
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func activate(_ binds: [Bind]) {
        deactivate()
        failures = []
        for (index, group) in HotkeyPlan.groups(binds).enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(group.keyCode), HotkeyPlan.carbonModifiers(group.modifiers),
                                             EventHotKeyID(signature: 0x4859_5052, id: id), GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                groups[id] = group
            } else if let first = group.press.first ?? group.release.first {
                failures.append(Diagnostic(first.location, "this hotkey could not be registered; another app may own it", isWarning: true))
            }
        }
    }

    func deactivate() {
        stopRepeat()
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        groups = [:]
    }

    private func hotkey(_ id: UInt32, pressed: Bool) {
        guard let group = groups[id] else { return }
        if pressed {
            stopRepeat()
            run(group.press)
            guard group.repeats else { return }
            heldID = id
            repeatTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.keyRepeatDelay, repeats: false) { [weak self] _ in
                self?.startRepeating(id, group)
            }
        } else {
            if heldID == id { stopRepeat() }
            run(group.release)
        }
    }

    private func startRepeating(_ id: UInt32, _ group: HotkeyGroup) {
        guard heldID == id else { return }
        let repeating = group.press.filter { $0.flags.contains(.repeating) }
        repeatTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.keyRepeatInterval, repeats: true) { [weak self] _ in
            guard let self, self.heldID == id else { return }
            guard CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(group.keyCode)) else {
                self.stopRepeat()
                return
            }
            self.run(repeating)
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        heldID = nil
    }
}
```

- [ ] **Step 6: Build and run every test**

Run: `swift build && swift test`
Expected: the build succeeds and all suites pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/HyprCore/Input/HotkeyPlan.swift Sources/HyprOSX/Input Tests/HyprCoreTests/HotkeyPlanTests.swift
git commit -m "feat: add Carbon hotkeys with submaps, release binds and key repeat"
```

---

### Task 20: Socket server and the hyprctl client

**Files:**
- Create: `Sources/HyprCore/IPC/Socket.swift`, `Sources/hyprctl/main.swift` (replace the Task 1 stub)
- Modify: `Package.swift` (`hyprctl` depends on `HyprCore`)
- Test: `Tests/HyprCoreTests/SocketTests.swift`

**Interfaces:**
- Consumes: nothing app-specific; `IPCResponder` is wired in Task 21.
- Produces:

```swift
public enum SocketPaths {
    public static func userTempDirectory() -> String                   // confstr(_CS_DARWIN_USER_TEMP_DIR), same folder as NSTemporaryDirectory()
    public static func directory(tmp: String = userTempDirectory()) -> String   // <tmp>/hyprosx
    public static func socket(tmp: String = userTempDirectory()) -> String      // <tmp>/hyprosx/.socket.sock
}
public enum SocketError: Error, Equatable { case pathTooLong, unsafeDirectory(String), system(String) }
public final class SocketServer {
    public init(path: String, queue: DispatchQueue, handler: @escaping (String) -> String)   // handler runs on `queue`
    public func start() throws
}
public enum SocketClient { public static func send(_ request: String, to path: String, timeoutSeconds: Int = 5) -> String? }
public enum IPCExit { public static func isError(command: String, batch: Bool, reply: String) -> Bool }
```

The socket lives in `HyprCore` (Foundation and Darwin only) so the permission and round-trip behavior is unit-tested, and `hyprctl` links `HyprCore` for the client; this replaces `Sources/HyprOSX/IPC/SocketServer.swift` from the file map. Both sides use the per-user temporary folder from `confstr`, so a changed `$TMPDIR` in a shell cannot point `hyprctl` elsewhere.

Server rules: the folder is created with mode 0700 and must be a real directory (not a symlink) owned by the current user, else `start` throws; a stale socket file is removed; the socket is chmod 0600 after `bind`; one thread accepts; each connection must pass `getpeereid` with the current uid or is closed unread; reads stop at EOF, at 64 KiB, or after a 1 s timeout with data already read; the handler runs on `queue` and the reply is written back before the connection closes. `SO_NOSIGPIPE` is set on every socket, so a client that leaves early cannot kill HyprOSX.

`hyprctl` rules: `-j` JSON, `-q` no output, `--batch "a ; b"`, `-i`/`--instance N` accepted and ignored, `-h`/`--help` usage; any other word (including negative numbers) is part of the command; the request is `[j]/BODY`; exit 1 when the socket is missing or `IPCExit.isError` says so, else 0.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/SocketTests.swift`:

```swift
import Testing
import Foundation
@testable import HyprCore

@Suite struct SocketTests {
    func freshTmp() -> String {
        let tmp = "/tmp/hyprosx-t\(getpid())-\(UInt32.random(in: 0...UInt32.max))"
        mkdir(tmp, 0o700)
        return tmp
    }

    func mode(_ path: String) -> (type: mode_t, perms: mode_t) {
        var st = stat()
        lstat(path, &st)
        return (st.st_mode & S_IFMT, st.st_mode & 0o777)
    }

    @Test func roundTripWithOwnerOnlyPermissions() throws {
        let tmp = freshTmp()
        let path = SocketPaths.socket(tmp: tmp)
        let server = SocketServer(path: path, queue: DispatchQueue(label: "socket-test-1")) { "reply to \($0)" }
        try server.start()
        #expect(SocketClient.send("j/clients", to: path) == "reply to j/clients")
        #expect(SocketClient.send("/dispatch workspace 2", to: path) == "reply to /dispatch workspace 2")
        #expect(mode(SocketPaths.directory(tmp: tmp)) == (S_IFDIR, 0o700))
        #expect(mode(path) == (S_IFSOCK, 0o600))
    }

    @Test func staleSocketFileIsReplaced() throws {
        let tmp = freshTmp()
        let path = SocketPaths.socket(tmp: tmp)
        mkdir(SocketPaths.directory(tmp: tmp), 0o755)
        FileManager.default.createFile(atPath: path, contents: Data("stale".utf8))
        try SocketServer(path: path, queue: DispatchQueue(label: "socket-test-2")) { _ in "fresh" }.start()
        #expect(SocketClient.send("version", to: path) == "fresh")
        #expect(mode(SocketPaths.directory(tmp: tmp)).perms == 0o700)
    }

    @Test func symlinkedFolderIsRefused() {
        let tmp = freshTmp()
        symlink("/tmp", SocketPaths.directory(tmp: tmp))
        let server = SocketServer(path: SocketPaths.socket(tmp: tmp), queue: DispatchQueue(label: "socket-test-3")) { $0 }
        #expect(throws: SocketError.self) { try server.start() }
    }

    @Test func largeReplyArrivesWhole() throws {
        let tmp = freshTmp()
        let path = SocketPaths.socket(tmp: tmp)
        let big = String(repeating: "x", count: 1_000_000)
        try SocketServer(path: path, queue: DispatchQueue(label: "socket-test-4")) { _ in big }.start()
        #expect(SocketClient.send("clients", to: path)?.count == 1_000_000)
    }

    @Test func missingServerGivesNil() {
        #expect(SocketClient.send("version", to: "/tmp/hyprosx-none-\(getpid())/.socket.sock") == nil)
    }

    @Test func defaultPathIsInTheUserTempFolder() {
        #expect(SocketPaths.socket().hasSuffix("/hyprosx/.socket.sock"))
        #expect(SocketPaths.userTempDirectory().hasPrefix("/var/folders/") || SocketPaths.userTempDirectory().hasPrefix("/private/var/folders/"))
    }

    @Test func exitCodes() {
        #expect(!IPCExit.isError(command: "dispatch", batch: false, reply: "ok"))
        #expect(IPCExit.isError(command: "dispatch", batch: false, reply: "no window matches"))
        #expect(IPCExit.isError(command: "keyword", batch: false, reply: "exec over IPC is disabled (macos:ipc_exec)"))
        #expect(!IPCExit.isError(command: "clients", batch: false, reply: "Window 0x1a -> Notes:"))
        #expect(IPCExit.isError(command: "frob", batch: false, reply: "unknown request: frob"))
        #expect(!IPCExit.isError(command: "dispatch", batch: true, reply: "ok\n\nno window matches"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SocketTests`
Expected: FAIL, "cannot find 'SocketPaths' in scope".

- [ ] **Step 3: Implement the socket**

`Sources/HyprCore/IPC/Socket.swift`:

```swift
import Foundation

public enum SocketPaths {
    public static func userTempDirectory() -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        return confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0 ? String(cString: buffer) : NSTemporaryDirectory()
    }

    public static func directory(tmp: String = userTempDirectory()) -> String { (tmp as NSString).appendingPathComponent("hyprosx") }

    public static func socket(tmp: String = userTempDirectory()) -> String { (directory(tmp: tmp) as NSString).appendingPathComponent(".socket.sock") }
}

public enum SocketError: Error, Equatable {
    case pathTooLong
    case unsafeDirectory(String)
    case system(String)
}

public enum IPCExit {
    public static func isError(command: String, batch: Bool, reply: String) -> Bool {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("unknown request:") || text.hasPrefix("exec over IPC is disabled") { return true }
        return !batch && ["dispatch", "keyword", "reload"].contains(command) && text != "ok"
    }
}

enum SocketIO {
    static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        return addr
    }

    static func configure(_ fd: Int32, timeoutSeconds: Int) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    static func readAll(_ fd: Int32, limit: Int, stopOnTimeout: Bool) -> [UInt8]? {
        var data: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 65536)
        while data.count < limit {
            let n = read(fd, &buffer, buffer.count)
            if n > 0 {
                data += buffer[0..<n]
            } else if n == 0 {
                break
            } else if errno == EINTR {
                continue
            } else if (errno == EAGAIN || errno == EWOULDBLOCK) && stopOnTimeout && !data.isEmpty {
                break
            } else {
                return nil
            }
        }
        return Array(data.prefix(limit))
    }

    static func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { return false }
            offset += n
        }
        return true
    }
}

public final class SocketServer {
    private let path: String
    private let queue: DispatchQueue
    private let handler: (String) -> String

    public init(path: String, queue: DispatchQueue, handler: @escaping (String) -> String) {
        self.path = path
        self.queue = queue
        self.handler = handler
    }

    public func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        if mkdir(dir, 0o700) != 0 && errno != EEXIST { throw SocketError.system("mkdir \(dir): \(String(cString: strerror(errno)))") }
        var st = stat()
        guard lstat(dir, &st) == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid() else { throw SocketError.unsafeDirectory(dir) }
        if st.st_mode & 0o777 != 0o700 { chmod(dir, 0o700) }
        guard var addr = SocketIO.address(path) else { throw SocketError.pathTooLong }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket: \(String(cString: strerror(errno)))") }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw SocketError.system("bind \(path): \(message)")
        }
        let thread = Thread { [self] in acceptLoop(fd) }
        thread.name = "hyprosx socket"
        thread.start()
    }

    private func acceptLoop(_ listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 {
                if errno == EINTR || errno == ECONNABORTED { continue }
                return
            }
            serve(client)
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { return }
        SocketIO.configure(client, timeoutSeconds: 1)
        guard let request = SocketIO.readAll(client, limit: 65536, stopOnTimeout: true) else { return }
        let text = String(decoding: request, as: UTF8.self)
        let reply = queue.sync { handler(text) }
        _ = SocketIO.writeAll(client, Array(reply.utf8))
    }
}

public enum SocketClient {
    public static func send(_ request: String, to path: String, timeoutSeconds: Int = 5) -> String? {
        guard var addr = SocketIO.address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        SocketIO.configure(fd, timeoutSeconds: timeoutSeconds)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0, SocketIO.writeAll(fd, Array(request.utf8)) else { return nil }
        shutdown(fd, SHUT_WR)
        return SocketIO.readAll(fd, limit: 64 << 20, stopOnTimeout: false).map { String(decoding: $0, as: UTF8.self) }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter SocketTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Write the client**

In `Package.swift`, change the `hyprctl` target to:

```swift
        .executableTarget(name: "hyprctl", dependencies: ["HyprCore"], swiftSettings: v5),
```

`Sources/hyprctl/main.swift`:

```swift
import Foundation
import HyprCore

let usage = """
usage: hyprctl [-j] [-q] <command> [args]
       hyprctl [-j] [-q] --batch "command ; command"
commands: dispatch, keyword, reload, clients, activewindow, workspaces, activeworkspace,
          monitors, binds, getoption, configerrors, version, cursorpos, perf
"""

var json = false
var quiet = false
var batch: String?
var words: [String] = []
var arguments = Array(CommandLine.arguments.dropFirst())
while !arguments.isEmpty {
    let word = arguments.removeFirst()
    switch word {
    case "-j": json = true
    case "-q": quiet = true
    case "--batch": batch = arguments.isEmpty ? "" : arguments.removeFirst()
    case "-i", "--instance": if !arguments.isEmpty { arguments.removeFirst() }
    case "-h", "--help":
        print(usage)
        exit(0)
    default: words.append(word)
    }
}

let body = batch.map { "[[BATCH]]" + $0 } ?? words.joined(separator: " ")
guard !body.trimmingCharacters(in: .whitespaces).isEmpty else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(1)
}
let path = SocketPaths.socket()
guard let reply = SocketClient.send((json ? "j" : "") + "/" + body, to: path) else {
    FileHandle.standardError.write(Data("HyprOSX is not running (no socket at \(path))\n".utf8))
    exit(1)
}
if !quiet && !reply.isEmpty { print(reply.hasSuffix("\n") ? String(reply.dropLast()) : reply) }
exit(IPCExit.isError(command: words.first ?? "", batch: batch != nil, reply: reply) ? 1 : 0)
```

- [ ] **Step 6: Build and check the client without a server**

Run: `swift build && swift test && .build/debug/hyprctl version; echo "exit $?"`
Expected: tests pass; the last command prints "HyprOSX is not running (no socket at …/hyprosx/.socket.sock)" and "exit 1".

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/HyprCore/IPC/Socket.swift Sources/hyprctl/main.swift Tests/HyprCoreTests/SocketTests.swift
git commit -m "feat: add the owner-only Unix socket server and the hyprctl client"
```

---
### Task 21: App lifecycle, config store, state store and menu bar

**Files:**
- Create: `Sources/HyprCore/Config/DefaultConfig.swift`, `Sources/HyprCore/Config/ConfigLoader.swift`, `Sources/HyprCore/World/World+Release.swift`, `Sources/HyprOSX/AppController.swift`, `Sources/HyprOSX/Config/ConfigStore.swift`, `Sources/HyprOSX/State/StateStore.swift`, `Sources/HyprOSX/UI/StatusItem.swift`
- Modify: `Sources/HyprOSX/main.swift` (replace the Task 1 stub)
- Test: `Tests/HyprCoreTests/ConfigLoaderTests.swift`, `Tests/HyprCoreTests/ReleaseParkedTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1-20.
- Produces:

```swift
// HyprCore
public enum DefaultConfig { public static let text: String; public static let appsText: String }
public enum ConfigLoader {
    public static func expandGlob(_ pattern: String) -> [String]
    public static func load(path: String, environment: [String: String]) -> (config: Config, diagnostics: [Diagnostic])
}
extension World { public func releaseParked() -> [Effect] }      // parked windows -> one .setFrames, centered on the focused monitor
// HyprOSX
final class ConfigStore { let path: String; var directory: String; var appsPath: String
    init(arguments: [String], environment: [String: String]); func load() -> (Config, [Diagnostic])
    func watch(sourced: Set<String>, enabled: Bool, onChange: @escaping () -> Void) }
final class StateStore { func load() -> StateSnapshot?; func schedule(_ snapshot: @escaping () -> StateSnapshot?); func saveNow(_ snapshot: StateSnapshot) }
struct StatusWorkspace { var id: Int; var name: String; var active: Bool }
struct StatusState { var title: String; var trusted: Bool; var paused: Bool; var workspaces: [StatusWorkspace]; var errors: [String] }
final class StatusItem: NSObject, NSMenuDelegate { var state: () -> StatusState; var onWorkspace: (Int) -> Void
    var onReload, onOpenConfigFolder, onTogglePause, onGrantAccessibility: () -> Void; func update() }
final class AppController: NSObject, NSApplicationDelegate
```

Startup (spec section 17), run by `AppController`:
1. Quit at once when another HyprOSX with the same bundle id runs. Ignore SIGPIPE; route SIGTERM, SIGINT and SIGHUP to `NSApp.terminate`. Ask for Accessibility with the system prompt; until trusted, the menu bar shows `HyprOSX ⚠︎` with a "Grant Accessibility Access…" item, and a 1 s timer checks again (the only polling loop).
2. One-time setup: tracker, executor, hotkeys, mouse-up monitor, socket (`SocketPaths.socket()`, handler on the main queue), screen-change and wake observers.
3. Begin managing: load the config (`ConfigStore` writes `DefaultConfig.text` and `DefaultConfig.appsText` when the main file is missing), build the world, register hotkeys, validate every keyboard bind's dispatcher (a parse error becomes a diagnostic at the bind's line), add hotkey failures, add an error when AeroSpace (`bobko.aerospace`) runs, start watching the config, set `isStartingUp`, send `monitorsChanged`, start the tracker and collect `windowAppeared` snapshots until every app reported `.scanned` or 2 s passed.
4. Finish: restore from `state.json` with the collected snapshots, else add them one by one; clear `isStartingUp`; replay the last focus report; run `exec-once` (first start only) and `exec`, both through `CommandParser` so `[rules]` prefixes work.

Every event, bind and IPC request first sets `world.cursor` from the real mouse position. Several binds on one key run in order and their effects run as one batch. `.saveState` saves 500 ms after the last request; quit and pause save at once. Reload (menu, `hyprctl reload`, file change) re-reads the config, calls `world.reload`, re-registers hotkeys, re-arms the watch and runs `exec`. The watch covers the main file, `apps.conf`, every sourced file and the config folder, debounces 150 ms and skips events that did not change any watched file's modification date or size. Pause releases parked windows, unhides apps HyprOSX hid, saves, unregisters hotkeys and stops the tracker; Resume runs "begin managing" again. Quit does what Pause does, runs `exec-shutdown`, and waits up to 1 s for the AX threads to apply the last frames. While paused, the socket answers "HyprOSX is paused".

`hyprctl perf` in M1 reports CPU time, resident memory, uptime, tracked apps, AX writes and errors, and the five slowest apps by average AX write time; M3 adds the rest of spec section 14.

- [ ] **Step 1: Write the failing tests**

`Tests/HyprCoreTests/ConfigLoaderTests.swift`:

```swift
import Testing
import Foundation
@testable import HyprCore

@Suite struct ConfigLoaderTests {
    func folder(_ files: [String: String]) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hyprosx-conf-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, text) in files { try text.write(toFile: (dir as NSString).appendingPathComponent(name), atomically: true, encoding: .utf8) }
        return dir
    }

    @Test func loadsSourcedAppsConfAndReportsErrorsWithLines() throws {
        let dir = try folder([
            "hyprland.conf": "general {\n    gaps_in = 3\n}\nsource = ./apps.conf\nbogus:option = 1\n",
            "apps.conf": "windowrule = float on, match:class .*\n",
        ])
        let (config, diagnostics) = ConfigLoader.load(path: dir + "/hyprland.conf", environment: ["HOME": dir])
        #expect(config.general.gapsIn == Edges(all: 3))
        #expect(config.windowRules.count == 1)
        #expect(diagnostics.map(\.description) == ["hyprland.conf:5: config option bogus:option does not exist."])
    }

    @Test func warnsWhenAppsConfExistsButIsNotSourced() throws {
        let dir = try folder(["hyprland.conf": "general {\n    gaps_in = 3\n}\n", "apps.conf": ""])
        let (_, diagnostics) = ConfigLoader.load(path: dir + "/hyprland.conf", environment: ["HOME": dir])
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].isWarning)
        #expect(diagnostics[0].message.contains("apps.conf is not sourced"))
    }

    @Test func globSourcesInSortedOrder() throws {
        let dir = try folder(["hyprland.conf": "source = ./conf.d/*.conf\n"])
        try FileManager.default.createDirectory(atPath: dir + "/conf.d", withIntermediateDirectories: true)
        try "general {\n    gaps_out = 7\n}\n".write(toFile: dir + "/conf.d/b.conf", atomically: true, encoding: .utf8)
        try "general {\n    gaps_out = 3\n}\n".write(toFile: dir + "/conf.d/a.conf", atomically: true, encoding: .utf8)
        let (config, diagnostics) = ConfigLoader.load(path: dir + "/hyprland.conf", environment: ["HOME": dir])
        #expect(diagnostics.isEmpty)
        #expect(config.general.gapsOut == Edges(all: 7))
    }

    @Test func defaultConfigLoadsCleanly() throws {
        let dir = try folder(["hyprland.conf": DefaultConfig.text, "apps.conf": DefaultConfig.appsText])
        let (config, diagnostics) = ConfigLoader.load(path: dir + "/hyprland.conf", environment: ["HOME": dir])
        #expect(diagnostics.isEmpty)
        #expect(config.binds.count >= 30)
        #expect(config.general.borderSize == 2)
        for bind in config.binds {
            #expect((try? CommandParser.parse(dispatcher: bind.dispatcher, arguments: bind.arguments).get()) != nil, "\(bind.dispatcher) \(bind.arguments)")
        }
    }
}
```

`Tests/HyprCoreTests/ReleaseParkedTests.swift`:

```swift
import Testing
@testable import HyprCore

@Suite struct ReleaseParkedTests {
    @Test func parkedWindowsComeBackCenteredOnTheFocusedMonitor() throws {
        let w = World(config: Config())
        _ = w.handle(.monitorsChanged([MonitorInfo(id: 0, name: "M", frame: Rect(x: 0, y: 0, width: 1000, height: 800),
                                                   visibleFrame: Rect(x: 0, y: 30, width: 1000, height: 770))]))
        _ = w.handle(.windowAppeared(WindowSnapshot(id: 1, pid: 10, bundleID: "a", appName: "A", title: "", frame: Rect(x: 0, y: 0, width: 400, height: 300), kind: .normal)))
        _ = w.handle(.windowAppeared(WindowSnapshot(id: 2, pid: 10, bundleID: "a", appName: "A", title: "", frame: Rect(x: 0, y: 0, width: 400, height: 300), kind: .normal)))
        _ = w.run(try CommandParser.parse(dispatcher: "movetoworkspacesilent", arguments: "2").get())
        #expect(w.windows.values.filter(\.isParked).count == 1)
        let effects = w.releaseParked()
        guard case .setFrames(let changes)? = effects.first else {
            Issue.record("expected one .setFrames")
            return
        }
        #expect(effects.count == 1)
        #expect(changes.count == 1)
        let frame = changes[0].frame
        #expect(abs(frame.center.x - 500) < 0.5 && abs(frame.center.y - 415) < 0.5)
        #expect(frame.width <= 1000 && frame.height <= 770)
        #expect(w.windows.values.allSatisfy { !$0.isParked })
        #expect(w.releaseParked().isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter 'ConfigLoaderTests|ReleaseParkedTests'`
Expected: FAIL, "cannot find 'ConfigLoader' in scope".

- [ ] **Step 3: Implement the HyprCore pieces**

`Sources/HyprCore/Config/ConfigLoader.swift`:

```swift
import Foundation

public enum ConfigLoader {
    public static func expandGlob(_ pattern: String) -> [String] {
        var result = glob_t()
        defer { globfree(&result) }
        guard Darwin.glob(pattern, 0, nil, &result) == 0 else { return [] }
        return (0..<Int(result.gl_pathc)).compactMap { result.gl_pathv[$0].map { String(cString: $0) } }
    }

    public static func load(path: String, environment: [String: String]) -> (config: Config, diagnostics: [Diagnostic]) {
        let parser = HyprlangParser(environment: environment, readFile: { try? String(contentsOfFile: $0, encoding: .utf8) }, glob: expandGlob)
        let parsed = parser.parse(path: path)
        let built = ConfigBuilder.build(parsed.entries)
        var diagnostics = parsed.diagnostics + built.diagnostics
        let apps = ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent("apps.conf")
        if FileManager.default.fileExists(atPath: apps), let text = try? String(contentsOfFile: path, encoding: .utf8),
           text.range(of: #"(?m)^[ \t]*source[ \t]*=[ \t]*\S*apps\.conf[ \t]*\r?$"#, options: .regularExpression) == nil {
            diagnostics.append(Diagnostic(SourceLocation(file: path, line: 1),
                                          "apps.conf is not sourced; add `source = ./apps.conf` so its app rules apply", isWarning: true))
        }
        return (built.config, diagnostics)
    }
}
```

`Sources/HyprCore/World/World+Release.swift`:

```swift
import Foundation

extension World {
    public func releaseParked() -> [Effect] {
        guard let area = monitor(focusedMonitor)?.visibleFrame ?? monitors.first?.visibleFrame else { return [] }
        var changes: [FrameChange] = []
        for id in windows.keys.sorted() {
            guard var w = windows[id], w.isParked else { continue }
            let size = (w.appliedFrame ?? w.lastFrame).size
            let width = min(size.width, area.width)
            let height = min(size.height, area.height)
            let frame = Rect(x: area.x + (area.width - width) / 2, y: area.y + (area.height - height) / 2, width: width, height: height)
            w.isParked = false
            w.appliedFrame = frame
            windows[id] = w
            changes.append(FrameChange(id: id, frame: frame, reason: .restore))
        }
        return changes.isEmpty ? [] : [.setFrames(changes)]
    }
}
```

`Sources/HyprCore/Config/DefaultConfig.swift`:

```swift
import Foundation

public enum DefaultConfig {
    public static let appsText = """
    # App rules. HyprOSX Settings writes this file; the main config sources it.
    # Example: windowrule = float on, match:class com\\.apple\\.calculator

    """

    public static let text = """
    # HyprOSX config, in Hyprland's format: https://wiki.hypr.land/Configuring/
    # HyprOSX reloads this file when you save it. Errors show in the menu bar and in `hyprctl configerrors`.

    source = ./apps.conf

    $mainMod = ALT
    $terminal = open -na Terminal
    $fileManager = open -a Finder

    general {
        gaps_in = 5
        gaps_out = 20
        border_size = 2
        col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
        col.inactive_border = rgba(595959aa)
        layout = dwindle
    }

    decoration {
        rounding = 10
    }

    animations {
        enabled = true
        bezier = easeOutQuint, 0.23, 1, 0.32, 1
        bezier = easeInOutCubic, 0.65, 0.05, 0.36, 1
        bezier = linear, 0, 0, 1, 1
        bezier = almostLinear, 0.5, 0.5, 0.75, 1
        bezier = quick, 0.15, 0, 0.1, 1
        animation = global, 1, 10, default
        animation = border, 1, 5.39, easeOutQuint
        animation = windows, 1, 4.79, easeOutQuint
        animation = windowsIn, 1, 4.1, easeOutQuint, popin 87%
        animation = windowsOut, 1, 1.49, linear, popin 87%
        animation = fadeIn, 1, 1.73, almostLinear
        animation = fadeOut, 1, 1.46, almostLinear
        animation = fade, 1, 3.03, quick
        animation = workspaces, 1, 1.94, almostLinear, fade
        animation = workspacesIn, 1, 1.21, almostLinear, fade
        animation = workspacesOut, 1, 1.94, almostLinear, fade
    }

    dwindle {
        pseudotile = true
        preserve_split = true
    }

    master {
        new_status = master
    }

    bind = $mainMod, Q, exec, $terminal
    bind = $mainMod, C, killactive,
    bind = $mainMod SHIFT, M, exit,
    bind = $mainMod, E, exec, $fileManager
    bind = $mainMod, V, togglefloating,
    bind = $mainMod, P, pseudo,
    bind = $mainMod, J, layoutmsg, togglesplit
    bind = $mainMod, F, fullscreen, 1

    bind = $mainMod, left, movefocus, l
    bind = $mainMod, right, movefocus, r
    bind = $mainMod, up, movefocus, u
    bind = $mainMod, down, movefocus, d

    bind = $mainMod, 1, workspace, 1
    bind = $mainMod, 2, workspace, 2
    bind = $mainMod, 3, workspace, 3
    bind = $mainMod, 4, workspace, 4
    bind = $mainMod, 5, workspace, 5
    bind = $mainMod, 6, workspace, 6
    bind = $mainMod, 7, workspace, 7
    bind = $mainMod, 8, workspace, 8
    bind = $mainMod, 9, workspace, 9
    bind = $mainMod, 0, workspace, 10

    bind = $mainMod SHIFT, 1, movetoworkspace, 1
    bind = $mainMod SHIFT, 2, movetoworkspace, 2
    bind = $mainMod SHIFT, 3, movetoworkspace, 3
    bind = $mainMod SHIFT, 4, movetoworkspace, 4
    bind = $mainMod SHIFT, 5, movetoworkspace, 5
    bind = $mainMod SHIFT, 6, movetoworkspace, 6
    bind = $mainMod SHIFT, 7, movetoworkspace, 7
    bind = $mainMod SHIFT, 8, movetoworkspace, 8
    bind = $mainMod SHIFT, 9, movetoworkspace, 9
    bind = $mainMod SHIFT, 0, movetoworkspace, 10

    bind = $mainMod, S, togglespecialworkspace, magic
    bind = $mainMod SHIFT, S, movetoworkspace, special:magic

    """
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter 'ConfigLoaderTests|ReleaseParkedTests'`
Expected: PASS (5 tests). If `defaultConfigLoadsCleanly` names an animation or option, fix the default text (not the parser) unless the parser contradicts `hyprland-config-reference.md`.

- [ ] **Step 5: Write the stores and the status item**

`Sources/HyprOSX/Config/ConfigStore.swift`:

```swift
import Foundation
import HyprCore

final class ConfigStore {
    let path: String
    private var sources: [DispatchSourceFileSystemObject] = []
    private var watched: [String] = []
    private var fingerprint = ""
    private var pending: DispatchWorkItem?

    init(arguments: [String] = CommandLine.arguments, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let flag = arguments.firstIndex(of: "--config").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let custom = flag ?? environment["HYPROSX_CONFIG"].flatMap { $0.isEmpty ? nil : $0 }
        path = ((custom ?? "~/.config/hyprosx/hyprland.conf") as NSString).expandingTildeInPath
    }

    var directory: String { (path as NSString).deletingLastPathComponent }
    var appsPath: String { (directory as NSString).appendingPathComponent("apps.conf") }

    func load() -> (Config, [Diagnostic]) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try? DefaultConfig.text.write(toFile: path, atomically: true, encoding: .utf8)
            if !fm.fileExists(atPath: appsPath) { try? DefaultConfig.appsText.write(toFile: appsPath, atomically: true, encoding: .utf8) }
        }
        let result = ConfigLoader.load(path: path, environment: ProcessInfo.processInfo.environment)
        return (result.config, result.diagnostics)
    }

    func watch(sourced: Set<String>, enabled: Bool, onChange: @escaping () -> Void) {
        sources.forEach { $0.cancel() }
        sources = []
        pending?.cancel()
        guard enabled else { return }
        watched = Array(sourced.union([path, appsPath])).sorted()
        fingerprint = currentFingerprint()
        for target in watched + [directory] {
            let fd = open(target, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
            source.setEventHandler { [weak self] in self?.changed(onChange) }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    private func changed(_ onChange: @escaping () -> Void) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.currentFingerprint() != self.fingerprint else { return }
            onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func currentFingerprint() -> String {
        watched.map { file in
            let attributes = try? FileManager.default.attributesOfItem(atPath: file)
            let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? -1
            return "\(file) \(modified) \(size)"
        }.joined(separator: "\n")
    }
}
```

`Sources/HyprOSX/State/StateStore.swift`:

```swift
import Foundation
import HyprCore

final class StateStore {
    let url: URL
    private var pending: DispatchWorkItem?

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HyprOSX/state.json")) {
        self.url = url
    }

    func load() -> StateSnapshot? {
        guard let data = try? Data(contentsOf: url), let snapshot = try? JSONDecoder().decode(StateSnapshot.self, from: data),
              snapshot.version == 1 else { return nil }
        return snapshot
    }

    func schedule(_ snapshot: @escaping () -> StateSnapshot?) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if let s = snapshot() { self?.saveNow(s) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow(_ snapshot: StateSnapshot) {
        pending?.cancel()
        pending = nil
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
    }
}
```

`Sources/HyprOSX/UI/StatusItem.swift`:

```swift
import AppKit

struct StatusWorkspace {
    var id: Int
    var name: String
    var active: Bool
}

struct StatusState {
    var title = "HyprOSX"
    var trusted = true
    var paused = false
    var workspaces: [StatusWorkspace] = []
    var errors: [String] = []
}

final class StatusItem: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var state: () -> StatusState = { StatusState() }
    var onWorkspace: (Int) -> Void = { _ in }
    var onReload: () -> Void = {}
    var onOpenConfigFolder: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onGrantAccessibility: () -> Void = {}

    override init() {
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        update()
    }

    func update() {
        let s = state()
        let font = NSFont.menuBarFont(ofSize: 0)
        let title = NSMutableAttributedString(string: s.trusted ? s.title : "HyprOSX ⚠︎", attributes: [.font: font])
        if !s.errors.isEmpty {
            title.append(NSAttributedString(string: " ●", attributes: [.font: font, .foregroundColor: NSColor.systemRed]))
        }
        item.button?.attributedTitle = title
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let s = state()
        menu.removeAllItems()
        if !s.trusted {
            menu.addItem(entry("Grant Accessibility Access…", #selector(grant)))
            menu.addItem(.separator())
        }
        for ws in s.workspaces {
            let item = entry("Workspace \(ws.name)", #selector(pickWorkspace(_:)))
            item.tag = ws.id
            item.state = ws.active ? .on : .off
            menu.addItem(item)
        }
        if !s.workspaces.isEmpty { menu.addItem(.separator()) }
        for error in s.errors.prefix(5) {
            menu.addItem(NSMenuItem(title: error, action: nil, keyEquivalent: ""))
        }
        if !s.errors.isEmpty { menu.addItem(.separator()) }
        menu.addItem(entry("Reload Config", #selector(reload)))
        menu.addItem(entry("Open Config Folder", #selector(openFolder)))
        menu.addItem(entry(s.paused ? "Resume HyprOSX" : "Pause HyprOSX", #selector(togglePause)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit HyprOSX", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func entry(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func pickWorkspace(_ sender: NSMenuItem) { onWorkspace(sender.tag) }
    @objc private func reload() { onReload() }
    @objc private func openFolder() { onOpenConfigFolder() }
    @objc private func togglePause() { onTogglePause() }
    @objc private func grant() { onGrantAccessibility() }
}
```

- [ ] **Step 6: Write the controller and the entry point**

`Sources/HyprOSX/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
```

`Sources/HyprOSX/AppController.swift`:

```swift
import AppKit
import ApplicationServices
import HyprCore
import os

final class AppController: NSObject, NSApplicationDelegate {
    static let version = "0.1.0"
    private let log = Logger(subsystem: "dev.hyprosx", category: "app")
    private let configStore = ConfigStore()
    private let stateStore = StateStore()
    private var status: StatusItem!
    private var world: World?
    private var tracker: AppTracker!
    private var executor: EffectExecutor!
    private var hotkeys: HotkeyManager!
    private var mouseUp: MouseUpMonitor!
    private var configErrors: [Diagnostic] = []
    private var runtimeErrors: [String] = []
    private var trustTimer: Timer?
    private var isSetUp = false
    private var paused = false
    private var ranExecOnce = false
    private var collecting = false
    private var startupWindows: [WindowSnapshot] = []
    private var startupFocus: WindowID?
    private var dragPending = false
    private var delayedPending = false
    private var signalSources: [DispatchSourceSignal] = []
    private var observers: [NSObjectProtocol] = []
    private let launched = Date()

    private var allErrors: [String] { configErrors.map(\.description) + runtimeErrors }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier, NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        installSignalHandlers()
        status = StatusItem()
        status.state = { [weak self] in self?.statusState() ?? StatusState() }
        status.onWorkspace = { [weak self] id in self?.dispatch(.workspace(.id(id))) }
        status.onReload = { [weak self] in self?.reloadConfig() }
        status.onOpenConfigFolder = { [weak self] in
            if let dir = self?.configStore.directory { NSWorkspace.shared.open(URL(fileURLWithPath: dir)) }
        }
        status.onTogglePause = { [weak self] in self?.togglePause() }
        status.onGrantAccessibility = {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            setUp()
            return
        }
        status.update()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.trustTimer = nil
            self?.setUp()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard isSetUp, !paused, let world else { return }
        execute(world.releaseParked())
        tracker.unhideAllHiddenByUs()
        stateStore.saveNow(world.snapshot())
        runExec(world.config.execShutdown)
        let threads = Array(tracker.threads.values)
        DispatchQueue.concurrentPerform(iterations: threads.count) { threads[$0].flush(timeout: 1) }
    }

    private func installSignalHandlers() {
        signal(SIGPIPE, SIG_IGN)
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    private func setUp() {
        isSetUp = true
        tracker = AppTracker { [weak self] event in self?.trackerEvent(event) }
        tracker.onDelayedRegistration = { [weak self] in
            self?.delayedPending = true
            self?.mouseUp.arm()
        }
        tracker.onDragStarted = { [weak self] in
            self?.dragPending = true
            self?.mouseUp.arm()
        }
        tracker.onInitialScanDone = { [weak self] in self?.finishStartup() }
        executor = EffectExecutor(tracker: tracker, windowPID: { [weak self] id in self?.world?.windows[id]?.pid }, environment: { [weak self] in
            Spawner.environment(base: ProcessInfo.processInfo.environment, extra: self?.world?.config.environment ?? [])
        })
        executor.onSpawned = { [weak self] token, pid in self?.world?.registerSpawn(token: token, pid: pid) }
        executor.onSpawnFailed = { [weak self] message in
            self?.runtimeErrors.append(message)
            self?.status.update()
        }
        executor.onAppEffect = { [weak self] effect in self?.appEffect(effect) }
        hotkeys = HotkeyManager { [weak self] binds in self?.runBinds(binds) }
        hotkeys.install()
        mouseUp = MouseUpMonitor { [weak self] in self?.mouseReleased() }
        do {
            try SocketServer(path: SocketPaths.socket(), queue: .main) { [weak self] raw in self?.ipc(raw) ?? "" }.start()
        } catch {
            runtimeErrors.append("hyprctl socket: \(error)")
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        })
        beginManaging()
    }

    private func beginManaging() {
        paused = false
        let (config, diagnostics) = configStore.load()
        let world = World(config: config)
        self.world = world
        applyConfig(diagnostics)
        world.isStartingUp = true
        world.cursor = Screens.cursor()
        let monitors = Screens.current()
        tracker.screenSizes = monitors.map(\.frame.size)
        execute(world.handle(.monitorsChanged(monitors)))
        collecting = true
        startupWindows = []
        startupFocus = nil
        tracker.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.finishStartup() }
        status.update()
    }

    private func finishStartup() {
        guard collecting, let world else { return }
        collecting = false
        world.cursor = Screens.cursor()
        if let saved = stateStore.load() {
            execute(world.restore(saved, alive: startupWindows))
        } else {
            for snapshot in startupWindows { execute(world.handle(.windowAppeared(snapshot))) }
        }
        startupWindows = []
        world.isStartingUp = false
        if let focus = startupFocus { execute(world.handle(.focusChanged(focus))) }
        if !ranExecOnce {
            ranExecOnce = true
            runExec(world.config.execOnce)
        }
        runExec(world.config.exec)
        status.update()
    }

    private func applyConfig(_ diagnostics: [Diagnostic]) {
        guard let world else { return }
        hotkeys.activate(world.activeBinds)
        var all = diagnostics
        for bind in world.config.binds where !bind.flags.contains(.mouse) {
            if case .failure(let error) = CommandParser.parse(dispatcher: bind.dispatcher, arguments: bind.arguments) {
                all.append(Diagnostic(bind.location, error.message))
            }
        }
        all += hotkeys.failures
        if !Spawner.isAvailable {
            all.append(Diagnostic(SourceLocation(file: configStore.path, line: 1), "commands are disabled: responsibility_spawnattrs_setdisclaim is missing"))
        }
        configErrors = all
        runtimeErrors.removeAll { $0.hasPrefix("AeroSpace") }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "bobko.aerospace").isEmpty {
            runtimeErrors.append("AeroSpace is running; quit it, or both apps will move windows")
        }
        configStore.watch(sourced: world.config.sourcedFiles, enabled: !world.config.misc.disableAutoreload) { [weak self] in self?.reloadConfig() }
    }

    private func reloadConfig() {
        guard let world, !paused else { return }
        let (config, diagnostics) = configStore.load()
        execute(world.reload(config))
        applyConfig(diagnostics)
        runExec(world.config.exec)
        status.update()
    }

    private func togglePause() {
        guard isSetUp else { return }
        if paused {
            beginManaging()
            return
        }
        guard let world else { return }
        execute(world.releaseParked())
        tracker.unhideAllHiddenByUs()
        stateStore.saveNow(world.snapshot())
        hotkeys.deactivate()
        tracker.stop()
        collecting = false
        paused = true
        status.update()
    }

    private func trackerEvent(_ event: PlatformEvent) {
        guard collecting else { return handle(event) }
        switch event {
        case .windowAppeared(let snapshot): startupWindows.append(snapshot)
        case .windowDisappeared(let id): startupWindows.removeAll { $0.id == id }
        case .focusChanged(let id): if let id { startupFocus = id }
        default: break
        }
    }

    private func handle(_ event: PlatformEvent) {
        guard let world, !paused else { return }
        world.cursor = Screens.cursor()
        execute(world.handle(event))
    }

    private func dispatch(_ command: Command) {
        guard let world, !paused else { return }
        world.cursor = Screens.cursor()
        execute(world.run(command).effects)
    }

    private func runBinds(_ binds: [Bind]) {
        guard let world, !paused, !binds.isEmpty else { return }
        world.cursor = Screens.cursor()
        var effects: [Effect] = []
        for bind in binds {
            switch CommandParser.parse(dispatcher: bind.dispatcher, arguments: bind.arguments) {
            case .success(let command): effects += world.run(command).effects
            case .failure(let error): log.error("\(bind.location.file, privacy: .public):\(bind.location.line): \(error.message, privacy: .public)")
            }
        }
        execute(effects)
    }

    private func runExec(_ commands: [ExecCommand]) {
        for c in commands {
            if case .success(let command) = CommandParser.parse(dispatcher: c.raw ? "execr" : "exec", arguments: c.command) { dispatch(command) }
        }
    }

    private func execute(_ effects: [Effect]) {
        if !effects.isEmpty { executor.execute(effects) }
    }

    private func appEffect(_ effect: Effect) {
        guard let world else { return }
        switch effect {
        case .submapChanged:
            hotkeys.activate(world.activeBinds)
            status.update()
        case .statusChanged:
            status.update()
        case .saveState:
            stateStore.schedule { [weak self] in self?.world?.snapshot() }
        case .reloadConfig:
            reloadConfig()
        case .exitApp:
            NSApp.terminate(nil)
        default:
            break
        }
    }

    private func ipc(_ raw: String) -> String {
        guard let world else { return "HyprOSX is waiting for Accessibility permission" }
        if paused { return "HyprOSX is paused" }
        world.cursor = Screens.cursor()
        let reply = IPCResponder.handle(raw, world: world, version: Self.version, configErrors: allErrors, perfReport: { perfReport() })
        execute(reply.effects)
        return reply.text
    }

    private func screensChanged() {
        guard isSetUp else { return }
        let monitors = Screens.current()
        tracker.screenSizes = monitors.map(\.frame.size)
        handle(.monitorsChanged(monitors))
    }

    private func mouseReleased() {
        if delayedPending {
            delayedPending = false
            tracker.threads.values.forEach { $0.flushDelayed() }
        }
        if dragPending {
            dragPending = false
            handle(.dragEnded(cursor: Screens.cursor()))
        }
    }

    private func statusState() -> StatusState {
        guard let world else { return StatusState(trusted: isSetUp || AXIsProcessTrusted(), errors: allErrors) }
        let current = world.activeWorkspace[world.focusedMonitor]
        let workspaces = world.workspaces.values.filter { !$0.isSpecial }.sorted { $0.id < $1.id }
            .map { StatusWorkspace(id: $0.id, name: $0.name, active: $0.id == current) }
        let name = current.flatMap { world.workspaces[$0]?.name } ?? "-"
        return StatusState(title: paused ? "\(name) ⏸" : name, trusted: true, paused: paused, workspaces: workspaces, errors: allErrors)
    }

    private func perfReport() -> String {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        let rss = result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
        let threads = (tracker?.threads.values).map { Array($0) } ?? []
        var lines = [
            String(format: "cpu time: %.2f s", cpu),
            String(format: "resident memory: %.1f MB", rss),
            String(format: "uptime: %.0f s", Date().timeIntervalSince(launched)),
            "tracked apps: \(threads.count)",
            "ax writes: \(threads.reduce(0) { $0 + $1.callCount }), errors: \(threads.reduce(0) { $0 + $1.errorCount })",
        ]
        for thread in threads.sorted(by: { $0.averageLatencyMs > $1.averageLatencyMs }).prefix(5) {
            lines.append(String(format: "  %@: %.2f ms average", thread.appName, thread.averageLatencyMs))
        }
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 7: Build and run every test**

Run: `swift build && swift test`
Expected: the build succeeds and all suites pass. Fix concurrency diagnostics with the smallest change (for example `MainActor.assumeIsolated` inside a timer block); do not raise the language mode.

- [ ] **Step 8: Commit**

```bash
git add Sources Tests
git commit -m "feat: add the app lifecycle, config watching, state saving and menu bar"
```

---
### Task 22: Bundle, install and the owner's config

**Files:**
- Create: `Resources/Info.plist`, `scripts/build-app.sh`, `scripts/make-signing-identity.sh`, `config/owner/hyprland.conf`, `config/owner/apps.conf`
- Test: `Tests/HyprCoreTests/OwnerConfigTests.swift`

**Interfaces:**
- Consumes: `ConfigLoader`, `CommandParser`, `Edges` (HyprCore); the `HyprOSX` and `hyprctl` products.
- Produces: `.build/HyprOSX.app`; with `--install`, `~/Applications/HyprOSX.app` and the link `~/.local/bin/hyprctl`.

The bundled default config is `DefaultConfig.text` (Task 21), so the file map's `config/default/hyprland.conf` is not created. `build-app.sh` signs with the "HyprOSX Local Signing" identity when the login keychain has it, else ad hoc. Do not run `make-signing-identity.sh` as part of this task: it changes the login keychain, and any process running as the owner can then call `codesign` with that identity, so a program could sign itself as `dev.hyprosx.HyprOSX` and receive HyprOSX's Accessibility grant. It runs only after the owner agrees to that trade-off (the alternative is ad hoc signing and a new Accessibility approval after each rebuild).

The owner's config mirrors `~/.aerospace.toml` and spec section 21. `apps.conf` floats everything, tiles Ghostty, Zen, Slack and kitty (dialogs stay floating), and floats Calculator, System Settings and Alfred. Workspaces 1-5 use `gapsout:20`, like AeroSpace's 20 pt outer gap on the main monitor. Mouse and scroll binds are in the file but do nothing until Milestone 2 adds the mouse tap.

- [ ] **Step 1: Write the failing test**

`Tests/HyprCoreTests/OwnerConfigTests.swift`:

```swift
import Testing
import Foundation
@testable import HyprCore

@Suite struct OwnerConfigTests {
    @Test func ownerConfigLoadsCleanly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("config/owner/hyprland.conf").path
        let (config, diagnostics) = ConfigLoader.load(path: path, environment: ["HOME": NSHomeDirectory()])
        #expect(diagnostics.map(\.description) == [])
        #expect(config.general.gapsIn == Edges(all: 4))
        #expect(config.general.gapsOut == Edges(all: 10))
        #expect(config.general.borderSize == 2)
        #expect(config.dwindle.preserveSplit && config.dwindle.forceSplit == 2)
        #expect(config.cursor.noWarps && config.input.followMouse == 0 && config.macos.unhideHiddenApps)
        #expect(config.windowRules.count == 8)
        #expect(config.workspaceRules.count == 8)
        #expect(config.binds.filter { $0.submap == "resize" }.count == 6)
        for bind in config.binds where !bind.flags.contains(.mouse) {
            #expect((try? CommandParser.parse(dispatcher: bind.dispatcher, arguments: bind.arguments).get()) != nil, "\(bind.dispatcher) \(bind.arguments)")
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter OwnerConfigTests`
Expected: FAIL; the diagnostics name the missing `config/owner/hyprland.conf`.

- [ ] **Step 3: Write the owner's config**

`config/owner/hyprland.conf`:

```
# HyprOSX config for this Mac, mirrored from ~/.aerospace.toml (Alt + vim keys).
# Rectangle has to quit, or it keeps Ctrl+Cmd+1/2/3 and Ctrl+Alt+Left/Right.

source = ./apps.conf

$mainMod = ALT

general {
    gaps_in = 4
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(89b482ee) rgba(a9b665ee) 45deg
    col.inactive_border = rgba(3c3836aa)
    layout = dwindle
}

decoration {
    rounding = 10
}

animations {
    enabled = true
    bezier = easeOutQuint, 0.23, 1, 0.32, 1
    bezier = easeInOutCubic, 0.65, 0.05, 0.36, 1
    bezier = linear, 0, 0, 1, 1
    bezier = almostLinear, 0.5, 0.5, 0.75, 1
    bezier = quick, 0.15, 0, 0.1, 1
    animation = global, 1, 10, default
    animation = border, 1, 5.39, easeOutQuint
    animation = windows, 1, 4.79, easeOutQuint
    animation = windowsIn, 1, 4.1, easeOutQuint, popin 87%
    animation = windowsOut, 1, 1.49, linear, popin 87%
    animation = fadeIn, 1, 1.73, almostLinear
    animation = fadeOut, 1, 1.46, almostLinear
    animation = fade, 1, 3.03, quick
    animation = workspaces, 1, 1.94, almostLinear, fade
    animation = workspacesIn, 1, 1.21, almostLinear, fade
    animation = workspacesOut, 1, 1.94, almostLinear, fade
}

dwindle {
    preserve_split = true
    force_split = 2
}

input {
    follow_mouse = 0
}

cursor {
    no_warps = true
}

macos {
    unhide_hidden_apps = true
}

workspace = 1, monitor:0, default:true, gapsout:20
workspace = 2, monitor:0, gapsout:20
workspace = 3, monitor:0, gapsout:20
workspace = 4, monitor:0, gapsout:20
workspace = 5, monitor:0, gapsout:20
workspace = 6, monitor:1, default:true
workspace = 7, monitor:1
workspace = 8, monitor:1

bind = $mainMod, H, movefocus, l
bind = $mainMod, J, movefocus, d
bind = $mainMod, K, movefocus, u
bind = $mainMod, L, movefocus, r
bind = $mainMod SHIFT, H, movewindow, l
bind = $mainMod SHIFT, J, movewindow, d
bind = $mainMod SHIFT, K, movewindow, u
bind = $mainMod SHIFT, L, movewindow, r
binde = $mainMod SHIFT, minus, resizeactive, -50 0
binde = $mainMod SHIFT, equal, resizeactive, 50 0
bind = $mainMod, slash, layoutmsg, togglesplit
bind = $mainMod, comma, workspacelayout, dwindle monocle
bind = $mainMod, F, fullscreen, 1
bind = $mainMod SHIFT, F, fullscreen, 0
bind = $mainMod SHIFT, space, togglefloating,
bind = $mainMod SHIFT, Q, killactive,
bind = $mainMod, P, pseudo,

bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8

bind = $mainMod, Tab, focusmonitor, +1
bind = $mainMod SHIFT, Tab, movewindow, mon:+1
bind = $mainMod, bracketleft, workspace, previous
bind = $mainMod, bracketright, workspace, e+1
bind = $mainMod SHIFT, semicolon, exec, hyprctl reload

bind = $mainMod, S, togglespecialworkspace, magic
bind = $mainMod SHIFT, S, movetoworkspace, special:magic

bind = $mainMod, R, submap, resize
submap = resize
binde = , H, resizeactive, -50 0
binde = , J, resizeactive, 0 50
binde = , K, resizeactive, 0 -50
binde = , L, resizeactive, 50 0
bind = , Escape, submap, reset
bind = , Return, submap, reset
submap = reset

bind = CTRL CMD, 1, setfloating,
bind = CTRL CMD, 1, resizeactive, exact 33.33% 100%
bind = CTRL CMD, 1, moveactive, exact 0 0
bind = CTRL CMD, 2, setfloating,
bind = CTRL CMD, 2, resizeactive, exact 33.33% 100%
bind = CTRL CMD, 2, moveactive, exact 33.33% 0
bind = CTRL CMD, 3, setfloating,
bind = CTRL CMD, 3, resizeactive, exact 33.33% 100%
bind = CTRL CMD, 3, moveactive, exact 66.67% 0
bind = CTRL ALT, left, setfloating,
bind = CTRL ALT, left, resizeactive, exact 50% 100%
bind = CTRL ALT, left, moveactive, exact 0 0
bind = CTRL ALT, right, setfloating,
bind = CTRL ALT, right, resizeactive, exact 50% 100%
bind = CTRL ALT, right, moveactive, exact 50% 0

bindm = CTRL ALT, mouse:272, movewindow
bindm = CTRL ALT, mouse:273, resizewindow
bind = CTRL ALT, mouse_down, workspace, e+1
bind = CTRL ALT, mouse_up, workspace, e-1
```

`config/owner/apps.conf`:

```
# App rules (HyprOSX Settings will write this file). Float by default, tile the apps AeroSpace tiled.
windowrule = float on, match:class .*
windowrule = tile on, match:class com\.mitchellh\.ghostty, match:modal false
windowrule = tile on, match:class app\.zen-browser\.zen, match:modal false
windowrule = tile on, match:class com\.tinyspeck\.slackmacgap, match:modal false
windowrule = tile on, match:class net\.kovidgoyal\.kitty, match:modal false
windowrule = float on, match:class com\.apple\.calculator
windowrule = float on, match:class com\.apple\.systempreferences
windowrule = float on, match:class com\.runningwithcrayons\.Alfred
```

- [ ] **Step 4: Run the test**

Run: `swift test --filter OwnerConfigTests`
Expected: PASS. A diagnostic here means the owner's file or a parser disagrees with `hyprland-config-reference.md`; fix the side that is wrong.

- [ ] **Step 5: Write the bundle files and scripts**

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>dev.hyprosx.HyprOSX</string>
    <key>CFBundleName</key>
    <string>HyprOSX</string>
    <key>CFBundleDisplayName</key>
    <string>HyprOSX</string>
    <key>CFBundleExecutable</key>
    <string>HyprOSX</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

`scripts/build-app.sh` (mode 755):

```zsh
#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

install=false
[[ "${1:-}" == "--install" ]] && install=true

swift build -c release --product HyprOSX
swift build -c release --product hyprctl
bin="$(swift build -c release --show-bin-path)"
app=".build/HyprOSX.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/HyprOSX" "$bin/hyprctl" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp NOTICE "$app/Contents/Resources/NOTICE"

identity="HyprOSX Local Signing"
if security find-identity -p codesigning | grep -q "\"$identity\""; then
    sign="$identity"
else
    sign="-"
    print -u2 "note: no \"$identity\" identity, signing ad hoc; macOS asks for Accessibility again after each rebuild"
fi
codesign --force --sign "$sign" --identifier dev.hyprosx.hyprctl "$app/Contents/MacOS/hyprctl"
codesign --force --sign "$sign" --identifier dev.hyprosx.HyprOSX "$app"
codesign --verify --strict "$app"
print "built $app (signature: $sign)"

if $install; then
    dest="$HOME/Applications/HyprOSX.app"
    running=false
    if pgrep -xq HyprOSX; then
        running=true
        pkill -TERM -x HyprOSX
        for _ in {1..50}; do pgrep -xq HyprOSX || break; sleep 0.1; done
    fi
    mkdir -p "$HOME/Applications" "$HOME/.local/bin"
    rsync -a --delete "$app/" "$dest/"
    ln -sf "$dest/Contents/MacOS/hyprctl" "$HOME/.local/bin/hyprctl"
    print "installed $dest and $HOME/.local/bin/hyprctl"
    if $running; then open "$dest"; fi
fi
```

`scripts/make-signing-identity.sh` (mode 755):

```zsh
#!/bin/zsh
set -euo pipefail
name="HyprOSX Local Signing"
if security find-identity -p codesigning | grep -q "\"$name\""; then
    print "\"$name\" already exists"
    exit 0
fi
ssl="${OPENSSL:-openssl}"
legacy=()
"$ssl" version | grep -q '^OpenSSL 3' && legacy=(-legacy)
work="$(mktemp -d)"
trap 'rm -f "$work/key.pem" "$work/cert.pem" "$work/identity.p12"; rmdir "$work"' EXIT
"$ssl" req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$work/key.pem" -out "$work/cert.pem" -subj "/CN=$name" \
    -addext "basicConstraints=critical,CA:false" -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning"
password="$("$ssl" rand -hex 16)"
"$ssl" pkcs12 -export $legacy -inkey "$work/key.pem" -in "$work/cert.pem" -name "$name" -out "$work/identity.p12" -passout "pass:$password"
security import "$work/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$password" -T /usr/bin/codesign
security find-identity -p codesigning | grep "\"$name\""
```

- [ ] **Step 6: Build and install**

Run: `chmod 755 scripts/*.sh && scripts/build-app.sh --install`
Expected: "built .build/HyprOSX.app (signature: -)" and "installed …/Applications/HyprOSX.app and …/.local/bin/hyprctl". Then:

Run: `plutil -lint ~/Applications/HyprOSX.app/Contents/Info.plist && codesign -dv ~/Applications/HyprOSX.app 2>&1 | grep -E 'Identifier|Signature' && ~/.local/bin/hyprctl version; echo "exit $?"`
Expected: "OK", `Identifier=dev.hyprosx.HyprOSX`, `Signature=adhoc`, then "HyprOSX is not running (no socket at …)" and "exit 1".

- [ ] **Step 7: Install the owner's config**

Run: `mkdir -p ~/.config/hyprosx && for f in hyprland.conf apps.conf; do if [ -e ~/.config/hyprosx/$f ]; then cp ~/.config/hyprosx/$f ~/.config/hyprosx/$f.bak; fi; cp config/owner/$f ~/.config/hyprosx/$f; done && ls -l ~/.config/hyprosx`
Expected: both files present; a `.bak` copy exists for any file that was there before.

- [ ] **Step 8: Commit**

```bash
git add Resources scripts config Tests/HyprCoreTests/OwnerConfigTests.swift
git commit -m "feat: add the app bundle build, install script and the owner's config"
```

---

### Task 23: Live verification and performance baseline

**Files:**
- Create: `docs/perf/m1-baseline.md`

**Interfaces:**
- Consumes: the installed app and `hyprctl` from Task 22.
- Produces: the measured baseline that Milestone 2 must not regress.

This task needs the owner: macOS asks for the Accessibility grant in System Settings, and HyprOSX then moves real windows. AeroSpace must not run; quit Rectangle so its hotkeys do not win.

- [ ] **Step 1: Owner starts HyprOSX and grants Accessibility**

Run: `open ~/Applications/HyprOSX.app`
Expected: the system prompt appears. The owner turns on HyprOSX in System Settings > Privacy & Security > Accessibility. Within about 1 s the menu bar title changes from `HyprOSX ⚠︎` to `1`.

- [ ] **Step 2: Check the socket and the config**

Run: `hyprctl version; echo "exit $?"; hyprctl configerrors; hyprctl monitors -j | head -20`
Expected: "HyprOSX 0.1.0", "exit 0"; no config errors (a hotkey warning names a bind that another app owns); the monitor list matches the attached screens, with the menu bar screen as id 0.

- [ ] **Step 3: Check tiling, workspaces and parking**

Run: `open -na Ghostty; open -na Ghostty; hyprctl clients -j | grep -E '"(class|at|size|floating|hidden)"'`
Expected: two `com.mitchellh.ghostty` windows, `floating: false`, side by side inside the work area with 8 pt between them and 20 pt to the screen edges (workspace 1 rule).

Run: `hyprctl dispatch movetoworkspacesilent 2; hyprctl clients -j | grep -E '"(hidden|workspace)"' -A1`
Expected: "ok"; one window on workspace 2 with `hidden: true` (parked in a corner); the other fills workspace 1.

- [ ] **Step 4: Check the security rules**

Run: `hyprctl dispatch exec open -a Calculator; echo "exit $?"; hyprctl keyword exec-once open -a Calculator; echo "exit $?"; ls -ld "$(getconf DARWIN_USER_TEMP_DIR)hyprosx" "$(getconf DARWIN_USER_TEMP_DIR)hyprosx/.socket.sock"`
Expected: "exec over IPC is disabled (macos:ipc_exec)" and "exit 1" twice; Calculator does not open; the folder is `drwx------` and the socket `srw-------`, both owned by the owner.

- [ ] **Step 5: Check restore and quit**

Run: `osascript -e 'quit app "HyprOSX"'; hyprctl clients; open ~/Applications/HyprOSX.app` and, after the menu bar shows the workspace again, `hyprctl clients -j | grep -E '"(workspace|hidden)"' -A1`
Expected: after quit, the parked Ghostty window is back in the middle of the screen and `hyprctl` says HyprOSX is not running; after relaunch, the window is on workspace 2 again and parked.

- [ ] **Step 6: Measure the baseline**

Run `hyprctl perf`, leave the Mac idle for 60 s (use the Monitor tool or a stopwatch, not a shell wait loop), and run `hyprctl perf` again.
Expected: CPU time grows by less than 0.06 s over the 60 s (below 0.1% CPU) and resident memory stays below 50 MB.

Run: `time (for i in {1..100}; do hyprctl -q activewindow; done)`
Expected: total below 1 s (below 10 ms per call).

- [ ] **Step 7: Record and commit**

Write `docs/perf/m1-baseline.md` with the date, the macOS and hardware line from `docs/research/macos-platform-notes.md`, the app count from `hyprctl perf`, idle CPU over 60 s, resident memory, the `hyprctl` latency, and the AX average write time of the five slowest apps.

```bash
git add docs/perf/m1-baseline.md
git commit -m "docs: record the M1 performance baseline"
```
