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

    @Test func hugeFiniteValuesDoNotTrapTheGetters() {
        var c = Config()
        #expect(ConfigBuilder.applyKeyword("general:gaps_in", "1e30", to: &c) == nil)
        #expect(ConfigBuilder.getOption("general:gaps_in", in: c) == "1e+30 1e+30 1e+30 1e+30")
        #expect(ConfigBuilder.applyKeyword("general:gaps_out", "1e18, 2.5", to: &c) == nil)
        #expect(ConfigBuilder.getOption("general:gaps_out", in: c) == "1000000000000000000 3 1000000000000000000 3")
        #expect(ConfigBuilder.applyKeyword("general:col.active_border", "rgba(33ccffee) 1e30deg", to: &c) == nil)
        #expect(ConfigBuilder.getOption("general:col.active_border", in: c) == "rgba(33ccffee) 1e+30deg")
        c.general.inactiveBorder = Gradient(colors: [Color(r: 1e30, g: -5, b: .nan, a: 2)], angleDegrees: .infinity)
        #expect(ConfigBuilder.getOption("general:col.inactive_border", in: c) == "rgba(ff0000ff) infdeg")
    }

    @Test func gettersFormatDefaultsAndGradients() {
        let c = Config()
        #expect(ConfigBuilder.getOption("general:gaps_out", in: c) == "20 20 20 20")
        #expect(ConfigBuilder.getOption("general:col.active_border", in: c) == "rgba(ffffffff) 0deg")
        #expect(ConfigBuilder.getOption("general:col.inactive_border", in: c) == "rgba(444444ff) 0deg")
        #expect(ConfigBuilder.getOption("master:new_status", in: c) == "slave")
        #expect(ConfigBuilder.getOption("dwindle:smart_resizing", in: c) == "true")
        #expect(ConfigBuilder.getOption("general:nope", in: c) == nil)
        let r = build("general:col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg")
        #expect(ConfigBuilder.getOption("general:col.active_border", in: r.config) == "rgba(33ccffee) rgba(00ff99ee) 45deg")
    }

    @Test func everyBindKeywordRoutesToTheBindParser() {
        let r = build("bindx = ALT, X, exec, true\nbindel = , A, exec, true\nbindm = ALT, mouse:272, movewindow")
        #expect(r.diagnostics.map(\.message) == ["invalid bind flag 'x'"])
        #expect(r.config.binds.map(\.dispatcher) == ["exec", "movewindow"])
        var c = Config()
        #expect(ConfigBuilder.applyKeyword("bindq", "ALT, X, exec, true", to: &c) == "invalid bind flag 'q'")
        #expect(c.binds.isEmpty)
        #expect(ConfigBuilder.applyKeyword("binds:nope", "1", to: &c) == "config option binds:nope does not exist.")
    }

    @Test func ruleIsKeptTogetherWithItsDiagnostics() {
        let r = build("workspace = 1, monitor:0, gapsout:abc")
        #expect(r.config.workspaceRules.count == 1)
        #expect(r.config.workspaceRules.first?.monitor == "0")
        #expect(r.diagnostics.map(\.message) == ["invalid value 'abc' for gapsout"])
        let w = build("windowrule = float on, border_size abc, match:class kitty")
        #expect(w.diagnostics.map(\.message) == ["invalid border_size 'abc'"])
        var c = Config()
        #expect(ConfigBuilder.applyKeyword("workspace", "1, gapsout:abc", to: &c) == "invalid value 'abc' for gapsout")
        #expect(c.workspaceRules.isEmpty)
    }

    @Test func malformedAndOutOfRangeBeziersAreInvalid() {
        #expect(build("bezier = x, 0, 0, 5, 5").diagnostics.map(\.message) == ["invalid bezier 'x, 0, 0, 5, 5'"])
        #expect(build("bezier = x, 0, 0, 1").diagnostics.map(\.message) == ["invalid bezier 'x, 0, 0, 1'"])
        #expect(build("bezier = x, 0, 0, nan, 1").diagnostics.map(\.message) == ["invalid bezier 'x, 0, 0, nan, 1'"])
        let r = build("bezier = x, 0, 0, 5, 5\nanimation = windows, 1, 4, x")
        #expect(r.config.beziers["x"] == nil)
        #expect(r.diagnostics.map(\.message) == ["invalid bezier 'x, 0, 0, 5, 5'", "no such bezier 'x'"])
    }

    @Test func blockRulesKeepTheirPositionAndAnimationsSeeLaterCurves() {
        let r = build("""
        windowrule = float on, match:class a
        windowrule {
            name = b
            match:class = b
        }
        windowrule = float on, match:class c
        animation = windows, 1, 4, later
        bezier = later, 0, 0, 1, 1
        """)
        #expect(r.diagnostics.isEmpty)
        #expect(r.config.windowRules.map(\.name) == [nil, "b", nil])
        #expect(r.config.animations.leaf("windowsIn").curve == "later")
    }

    @Test func submapAutoSwitchWarnsAndUnbindIsScopedToTheSubmap() {
        let r = build("""
        bind = ALT, A, exec, a
        submap = one, reset
        bind = ALT, A, exec, b
        unbind = ALT, A
        submap = reset
        """)
        #expect(r.diagnostics.map(\.message) == ["submap auto-switch is not supported on macOS"])
        #expect(r.diagnostics.first?.isWarning == true)
        #expect(r.config.binds.map(\.arguments) == ["a"])
    }

    @Test func malformedMonitorAndEnvLinesAreErrors() {
        #expect(build("monitor = , addreserved, 32, 0, 0, inf").diagnostics.map(\.message) == ["invalid addreserved ', addreserved, 32, 0, 0, inf'"])
        #expect(build("monitor = , addreserved, 32").diagnostics.map(\.message) == ["invalid addreserved ', addreserved, 32'"])
        #expect(build("env = NOCOMMA").diagnostics.map(\.message) == ["invalid env 'NOCOMMA'"])
        #expect(build("env = ,value").diagnostics.map(\.message) == ["invalid env ',value'"])
        let r = build("monitor = DP-1, addreserved, 1, 2, 3, 4")
        #expect(r.config.reservedAreas["DP-1"] == Edges(top: 1, right: 4, bottom: 2, left: 3))
    }


    @Test func ipcSecurityDefaultsArePinned() {
        let c = Config()
        #expect(c.macos.ipcExec == false)
        #expect(c.macos.ipcWindowTitles == true)
        let r = build("macos:ipc_exec = maybe")
        #expect(r.diagnostics.map(\.message) == ["invalid value 'maybe' for macos:ipc_exec"])
        #expect(r.config.macos.ipcExec == false)
        var d = Config()
        #expect(ConfigBuilder.applyKeyword("macos:ipc_exec", "maybe", to: &d) == "invalid value 'maybe' for macos:ipc_exec")
        #expect(d.macos.ipcExec == false)
    }

    @Test func ipcExecAcceptsOnlyExactBooleanWords() {
        for word in ["true", "yes", "on", "1", "TRUE", "Yes", "ON"] {
            var c = Config()
            #expect(ConfigBuilder.applyKeyword("macos:ipc_exec", word, to: &c) == nil)
            #expect(c.macos.ipcExec, "\(word) should enable")
        }
        for word in ["false", "no", "off", "0", "FALSE", "No", "Off"] {
            var c = Config()
            c.macos.ipcExec = true
            #expect(ConfigBuilder.applyKeyword("macos:ipc_exec", word, to: &c) == nil)
            #expect(c.macos.ipcExec == false, "\(word) should disable")
        }
        for word in ["online", "yes please", "truely", "nope", "2", "-1", "1.0", ""] {
            var c = Config()
            #expect(ConfigBuilder.applyKeyword("macos:ipc_exec", word, to: &c) == "invalid value '\(word)' for macos:ipc_exec")
            #expect(c.macos.ipcExec == false, "\(word) must not enable")
        }
    }

    @Test func execAndEnvKeywordsAreTopLevelOnly() {
        let r = build("""
        exec = top
        exec-once = once
        env = A,B
        plugin:x:exec = cmd
        device:exec = cmd
        decoration:blur:bind = ALT, X, exec, true
        plugin {
            x {
                exec-once = nested
                bind = ALT, Y, exec, true
            }
        }
        device {
            name = mouse
            env = C,D
            workspace = 1
        }
        general:exec-shutdown = cmd
        general:env = E,F
        """)
        #expect(r.config.exec == [ExecCommand(command: "top", raw: false)])
        #expect(r.config.execOnce == [ExecCommand(command: "once", raw: false)])
        #expect(r.config.environment == [EnvVar(name: "A", value: "B")])
        #expect(r.config.execShutdown.isEmpty)
        #expect(r.config.binds.isEmpty)
        #expect(r.config.workspaceRules.isEmpty)
        #expect(r.diagnostics.map(\.message) == ["config option general:exec-shutdown does not exist.", "config option general:env does not exist."])
        var c = Config()
        #expect(ConfigBuilder.applyKeyword("plugin:x:exec", "cmd", to: &c) == nil)
        #expect(ConfigBuilder.applyKeyword("device:exec", "cmd", to: &c) == nil)
        #expect(c.exec.isEmpty)
        #expect(ConfigBuilder.applyKeyword("exec", "cmd", to: &c) == nil)
        #expect(c.exec == [ExecCommand(command: "cmd", raw: false)])
    }

    @Test func windowRuleWithOneBadEffectIsDroppedWithADiagnostic() {
        let r = build("windowrule = float on, border_size abc, match:class kitty\nwindowrule = float on, match:class ok")
        #expect(r.diagnostics.map(\.message) == ["invalid border_size 'abc'"])
        #expect(r.config.windowRules.count == 1)
        let b = build("windowrule {\n name = bad\n match:class = kitty\n border_size = abc\n}")
        #expect(b.diagnostics.map(\.message) == ["invalid border_size 'abc'"])
        #expect(b.config.windowRules.count == 0)
    }
}
