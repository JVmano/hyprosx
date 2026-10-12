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

    @Test func noerrorSuppressesDiagnosticsUntilSwitchedOff() {
        let r = parse("# hyprlang noerror true\nbad line\n# hyprlang noerror false\nworse line\nok = 1")
        #expect(r.diagnostics.map(\.message) == ["Invalid config line"])
        #expect(r.diagnostics.map(\.location.line) == [4])
        #expect(pairs(r) == ["ok=1"])
    }

    @Test func missingSourceIsAnError() {
        let r = parse("source = nothing/*")
        #expect(r.diagnostics.first?.message == "source= globbing error: found no match")
    }
}
