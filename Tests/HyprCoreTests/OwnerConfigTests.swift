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
