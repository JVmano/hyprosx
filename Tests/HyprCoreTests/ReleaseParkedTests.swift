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
