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
        #expect(Set(config.binds.map(\.submap)).count == 1)
        #expect(config.binds.filter { $0.dispatcher == "resizeactive" && $0.modifiers == [.option] }.map(\.arguments) == ["50 50", "-50 -50"])
        #expect(config.binds.filter { $0.dispatcher == "placeactive" }.map(\.arguments)
            == ["33.33% 100% 0 0", "33.33% 100% 33.33% 0", "33.33% 100% 66.67% 0", "50% 100% 0 0", "50% 100% 50% 0"])
        #expect(config.binds.filter { $0.dispatcher == "setfloating" }.isEmpty)
        #expect(config.binds.filter { $0.dispatcher == "moveactive" }.isEmpty)
        #expect(abs((Motion.timing("windowsIn", config: config, environment: MotionEnvironment())?.duration ?? 0) - 0.41) < 1e-9)
        #expect(config.animations.leaf("windowsIn").style == "popin 87%")
        #expect(config.animations.leaf("workspacesIn").style == "fade")
        #expect(Motion.decorationTiming("border", config: config) != nil)
        #expect(config.binds.filter { $0.flags.contains(.mouse) }.map(\.dispatcher) == ["movewindow", "resizewindow"])
        for bind in config.binds where !bind.flags.contains(.mouse) {
            #expect((try? CommandParser.parse(dispatcher: bind.dispatcher, arguments: bind.arguments).get()) != nil, "\(bind.dispatcher) \(bind.arguments)")
        }
    }
}
