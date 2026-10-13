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
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let (config, diagnostics) = ConfigLoader.load(path: dir + "/hyprland.conf", environment: ["HOME": dir])
        #expect(config.general.gapsIn == Edges(all: 3))
        #expect(config.windowRules.count == 1)
        #expect(diagnostics.map(\.description) == ["hyprland.conf:5: config option bogus:option does not exist."])
    }

    @Test func warnsWhenAppsConfExistsButIsNotSourced() throws {
        let dir = try folder(["hyprland.conf": "general {\n    gaps_in = 3\n}\n", "apps.conf": ""])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let (_, diagnostics) = ConfigLoader.load(path: dir + "/hyprland.conf", environment: ["HOME": dir])
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].isWarning)
        #expect(diagnostics[0].message.contains("apps.conf is not sourced"))
    }

    @Test func noWarningWhenAppsConfIsSourcedInAnyForm() throws {
        let forms = ["source = ./apps.conf # my apps\n", "source=./apps.conf\n", "source = ~/apps.conf\n", "$apps = ./apps.conf\nsource = $apps\n",
                     "source = ./conf.d/../apps.conf\n", "source = ./app*.conf\n"]
        for form in forms {
            let dir = try folder(["hyprland.conf": form, "apps.conf": "# only a comment\n"])
            defer { try? FileManager.default.removeItem(atPath: dir) }
            let (_, diagnostics) = ConfigLoader.load(path: dir + "/hyprland.conf", environment: ["HOME": dir])
            #expect(diagnostics.isEmpty, "\(form) -> \(diagnostics.map(\.description))")
        }
    }

    @Test func commentedOutSourceStillWarns() throws {
        let dir = try folder(["hyprland.conf": "# source = ./apps.conf\n", "apps.conf": ""])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let (_, diagnostics) = ConfigLoader.load(path: dir + "/hyprland.conf", environment: ["HOME": dir])
        #expect(diagnostics.map(\.isWarning) == [true])
    }

    @Test func missingMainFileReportsOnlyThatError() throws {
        let dir = try folder(["apps.conf": ""])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let (_, diagnostics) = ConfigLoader.load(path: dir + "/hyprland.conf", environment: ["HOME": dir])
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.contains("inaccessible"))
    }

    @Test func globSourcesInSortedOrder() throws {
        let dir = try folder(["hyprland.conf": "source = ./conf.d/*.conf\n"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir + "/conf.d", withIntermediateDirectories: true)
        try "general {\n    gaps_out = 7\n}\n".write(toFile: dir + "/conf.d/b.conf", atomically: true, encoding: .utf8)
        try "general {\n    gaps_out = 3\n}\n".write(toFile: dir + "/conf.d/a.conf", atomically: true, encoding: .utf8)
        let (config, diagnostics) = ConfigLoader.load(path: dir + "/hyprland.conf", environment: ["HOME": dir])
        #expect(diagnostics.isEmpty)
        #expect(config.general.gapsOut == Edges(all: 7))
    }

    @Test func defaultConfigLoadsCleanly() throws {
        let dir = try folder(["hyprland.conf": DefaultConfig.text, "apps.conf": DefaultConfig.appsText])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let (config, diagnostics) = ConfigLoader.load(path: dir + "/hyprland.conf", environment: ["HOME": dir])
        #expect(diagnostics.isEmpty, "\(diagnostics.map(\.description))")
        #expect(config.binds.count >= 30)
        #expect(config.general.borderSize == 2)
        for bind in config.binds {
            #expect((try? CommandParser.parse(dispatcher: bind.dispatcher, arguments: bind.arguments).get()) != nil, "\(bind.dispatcher) \(bind.arguments)")
        }
    }
}
