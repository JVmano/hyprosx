import Foundation
import Testing
@testable import HyprCore

func jsonObject(_ text: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(text.utf8)) }

func ipc(_ raw: String, _ world: World, errors: [String] = []) -> IPCReply {
    IPCResponder.handle(raw, world: world, version: "0.1.0", configErrors: errors, perfReport: { "" })
}

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

    @Test func restoreDropsAWindowWhoseBundleChanged() {
        let saved = threeWindows().snapshot()
        let fresh = world()
        _ = fresh.restore(saved, alive: [snap(1), snap(2, bundle: "other.app", pid: 200), snap(3, pid: 300)])
        #expect(fresh.windows[2]?.bundleID == "other.app")
        #expect(Set(fresh.workspaces[1]?.tiledIDs ?? []) == [1, 2, 3])
    }

    @Test func restoreReattachesASuspendedWindowAndKeepsFocus() {
        let w = threeWindows()
        _ = w.handle(.windowSuspended(2, .minimized))
        let saved = w.snapshot()
        #expect(saved.windows.first { $0.id == 2 }?.suspended == .minimized)
        let fresh = world()
        _ = fresh.restore(saved, alive: [snap(1), snap(2, pid: 200), snap(3, pid: 300)])
        #expect(fresh.windows[2]?.suspended == nil)
        #expect(Set(fresh.workspaces[1]?.tiledIDs ?? []) == [1, 2, 3])
        #expect(fresh.focusedWindow == 3)
    }

    @Test func restoreUsesLiveTitlesAndLeavesNoTitlesInTheSnapshot() throws {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1, title: "bank statement")))
        let text = String(decoding: try JSONEncoder().encode(w.snapshot()), as: UTF8.self)
        #expect(!text.contains("bank statement"))
        let fresh = world()
        _ = fresh.restore(w.snapshot(), alive: [snap(1, title: "inbox")])
        #expect(fresh.windows[1]?.title == "inbox")
        #expect(fresh.windows[1]?.initialTitle == "inbox")
    }

    @Test func restoreSurvivesACorruptedSnapshot() {
        typealias Node = DwindleLayout.Node
        let w = world()
        for id: WindowID in 1...7 { _ = w.handle(.windowAppeared(snap(id, pid: Int32(id)))) }
        var saved = w.snapshot()

        var cyclic = DwindleLayout()
        cyclic.root = 1
        cyclic.nextID = Int.max
        cyclic.nodes = [
            1: Node(parent: nil, children: [2, 3], window: nil, ratio: .nan),
            2: Node(parent: 1, children: [], window: 1),
            3: Node(parent: 1, children: [4, 1], window: nil, ratio: 50),
            4: Node(parent: 3, children: [], window: 2),
        ]
        var lone = DwindleLayout()
        lone.root = 1
        lone.nodes = [1: Node(parent: nil, children: [2], window: nil), 2: Node(parent: 1, children: [], window: 3)]
        var dangling = DwindleLayout()
        dangling.root = 1
        dangling.nodes = [
            1: Node(parent: nil, children: [2, 99], window: nil),
            2: Node(parent: 1, children: [], window: 4),
            3: Node(parent: 1, children: [], window: nil),
        ]
        var stacked = MasterLayout()
        stacked.nodes = [
            MasterLayout.Node(window: 5, isMaster: true, percMaster: 40, percSize: -3),
            MasterLayout.Node(window: 5, isMaster: false, percMaster: 0.5, percSize: 1),
            MasterLayout.Node(window: 6, isMaster: false, percMaster: .nan, percSize: .infinity),
        ]

        var base = saved.workspaces[0]
        base.floating = [3, 3, 99]
        func workspace(_ id: Int, _ layout: LayoutState) -> Workspace {
            var ws = base
            ws.id = id
            ws.name = String(id)
            ws.layout = layout
            return ws
        }
        saved.workspaces = [workspace(1, .dwindle(cyclic)), workspace(2, .dwindle(lone)), workspace(3, .dwindle(dangling)),
                            workspace(4, .master(stacked)), workspace(4, .dwindle(DwindleLayout()))]
        saved.windows += [saved.windows[0]]
        for i in saved.windows.indices {
            switch saved.windows[i].id {
            case 3: saved.windows[i].workspace = 2
            case 4: saved.windows[i].workspace = 3
            case 5, 6: saved.windows[i].workspace = 4
            case 7: saved.windows[i].workspace = 77
            default: break
            }
            saved.windows[i].floatingFrame = Rect(x: .nan, y: .infinity, width: 1e300, height: -.infinity)
            saved.windows[i].fullscreenMode = 9
        }
        saved.activeWorkspace = ["Built-in Retina Display": 77, "Gone": 2]

        let fresh = world()
        let e = fresh.restore(saved, alive: (1...7).map { snap($0, pid: Int32($0)) })

        #expect(fresh.windows.count == 7)
        let placed = fresh.workspaces.values.flatMap(\.windowIDs).sorted()
        #expect(placed == [1, 2, 3, 4, 5, 6, 7])
        for (id, window) in fresh.windows { #expect(fresh.workspaces[window.workspace]?.windowIDs.contains(id) == true) }
        #expect(fresh.workspaces[77] == nil)
        #expect(fresh.windows.values.allSatisfy { $0.fullscreenMode == nil })
        #expect(fresh.windows.values.allSatisfy { $0.floatingFrame == Rect(x: 100, y: 100, width: 600, height: 400) })
        for case .setFrames(let changes) in e {
            for c in changes { #expect(([c.frame.x, c.frame.y, c.frame.width, c.frame.height] as [Double]).allSatisfy { $0.isFinite }) }
        }

        guard case .dwindle(let tree) = fresh.workspaces[1]?.layout else { Issue.record("workspace 1 is not dwindle"); return }
        #expect(tree.nodes.count == 5)
        #expect(tree.nodes.values.allSatisfy { $0.children.isEmpty || $0.children.count == 2 })
        #expect(tree.nodes.values.allSatisfy { $0.ratio >= 0.1 && $0.ratio <= 1.9 })
        #expect(Set(tree.windowIDs).isSuperset(of: [1, 2]))
        #expect(fresh.workspaces[2]?.tiledIDs == [3])
        #expect(fresh.workspaces[3]?.tiledIDs == [4])

        guard case .master(let master) = fresh.workspaces[4]?.layout else { Issue.record("workspace 4 is not master"); return }
        #expect(master.nodes.map(\.window) == [5, 6])
        #expect(master.nodes.allSatisfy { $0.percMaster >= 0.05 && $0.percMaster <= 0.95 && $0.percSize >= 0.05 && $0.percSize <= 1.95 })

        _ = fresh.handle(.windowAppeared(snap(8, pid: 8)))
        #expect(fresh.windows[8] != nil)
    }

    @Test func restoreKeepsFloatingWindowsOutOfTheTree() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, pid: 200, kind: .dialog)))
        let fresh = world()
        _ = fresh.restore(w.snapshot(), alive: [snap(1), snap(2, pid: 200, kind: .dialog)])
        #expect(fresh.workspaces[1]?.tiledIDs == [1])
        #expect(fresh.workspaces[1]?.floating == [2])
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

    @Test func policyBlocksTheKeywordsThatReachExecIndirectly() {
        #expect(IPCPolicy.isBlocked("keyword macos:ipc_exec true", allowExec: false))
        #expect(IPCPolicy.isBlocked("keyword\tmacos:ipc_exec\ttrue", allowExec: false))
        #expect(IPCPolicy.isBlocked("keyword env PATH,/tmp/evil", allowExec: false))
        #expect(IPCPolicy.isBlocked("keyword bindd ALT, X, run it, execr, evil", allowExec: false))
        #expect(IPCPolicy.isBlocked("keyword execr evil", allowExec: false))
        #expect(IPCPolicy.isBlocked("keyword exec-shutdown evil", allowExec: false))
        #expect(!IPCPolicy.isBlocked("keyword macos:ipc_exec true", allowExec: true))
        #expect(!IPCPolicy.isBlocked("keyword bind ALT, X, workspace, 2", allowExec: false))
    }

    @Test func aSocketCannotFlipTheFlagAndThenRunACommand() {
        let w = threeWindows()
        let r = ipc("/[[BATCH]]keyword macos:ipc_exec true;dispatch exec touch /tmp/pwned", w)
        #expect(r.text == "exec over IPC is disabled (macos:ipc_exec)\n\nexec over IPC is disabled (macos:ipc_exec)")
        #expect(!w.config.macos.ipcExec)
        #expect(!r.effects.contains { if case .spawn = $0 { return true } else { return false } })
    }

    @Test func execRunsOnlyWhenTheConfigAllowsIt() {
        let open = world("macos:ipc_exec = true")
        let r = ipc("/dispatch exec echo hi", open)
        #expect(r.text == "ok")
        #expect(r.effects.contains { if case .spawn = $0 { return true } else { return false } })
        let closed = ipc("/dispatch exec echo hi", world())
        #expect(closed.text == "exec over IPC is disabled (macos:ipc_exec)")
        #expect(closed.effects.isEmpty)
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

    @Test func jsonStaysValidForControlCharactersAndOddFrames() {
        let w = world()
        let title = "line\nbreak\ttab \u{1} \u{7f} e\u{301} \u{202e}rtl 漢字 \u{1F468}\u{200D}\u{1F469}"
        _ = w.handle(.windowAppeared(snap(1, title: title)))
        w.windows[1]?.appliedFrame = Rect(x: .nan, y: 1e300, width: .infinity, height: -1e300)
        w.cursor = Point(x: .nan, y: -1e300)
        for query in ["j/clients", "j/activewindow", "j/workspaces", "j/activeworkspace", "j/monitors", "j/binds"] {
            #expect(jsonObject(ipc(query, w).text) != nil, "\(query) is not valid JSON")
        }
        #expect((jsonObject(ipc("j/clients", w).text) as? [[String: Any]])?.first?["title"] as? String == title)
        #expect(!ipc("/clients", w).text.isEmpty)
        #expect(ipc("/cursorpos", w).text == "0, -1000000000")
    }

    @Test func titlesStayOutOfEveryReplyWhenDisabled() {
        let w = world("macos:ipc_window_titles = false")
        _ = w.handle(.windowAppeared(snap(1, title: "secret")))
        for query in ["/clients", "j/clients", "/activewindow", "j/activewindow", "/workspaces", "j/workspaces"] {
            #expect(!ipc(query, w).text.contains("secret"), "\(query) leaks the title")
        }
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
