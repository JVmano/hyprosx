import Foundation

public struct IPCReply: Equatable, Sendable {
    public var text: String
    public var effects: [Effect]
    public var configChanged = false
}

public enum IPCResponder {
    public static func handle(_ raw: String, world: World, version: String, configErrors: [String], perfReport: () -> String) -> IPCReply {
        let request = IPCRequest.parse(raw)
        var texts: [String] = []
        var effects: [Effect] = []
        var configChanged = false
        let allowExec = world.config.macos.ipcExec
        for command in request.commands {
            if IPCPolicy.isReadOnly(command) {
                texts.append("option not settable over IPC")
                continue
            }
            if IPCPolicy.isBlocked(command, allowExec: allowExec) {
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
                    configChanged = true
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
                let option = rest.trimmingCharacters(in: .whitespaces)
                let value = ConfigBuilder.getOption(option, in: world.config)
                texts.append(request.json ? encode(["option": option, "value": value.map { $0 as Any } ?? NSNull()] as [String: Any]) : (value ?? "no such option"))
            case "configerrors": texts.append(request.json ? encode(configErrors) : configErrors.joined(separator: "\n"))
            case "version": texts.append(request.json ? encode(["version": version]) : "HyprOSX \(version)")
            case "cursorpos": texts.append("\(int(world.cursor.x)), \(int(world.cursor.y))")
            case "perf": texts.append(perfReport())
            default: texts.append("unknown request: \(name)")
            }
        }
        if !allowExec {
            effects.removeAll { if case .spawn = $0 { return true } else { return false } }
        }
        return IPCReply(text: texts.joined(separator: "\n\n"), effects: effects, configChanged: configChanged)
    }

    static func split(_ s: String) -> (String, String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let i = t.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return (t, "") }
        return (String(t[..<i]), t[i...].trimmingCharacters(in: .whitespaces))
    }

    static func int(_ v: Double) -> Int { v.isFinite ? Int(min(max(v, -1e9), 1e9)) : 0 }

    static func encode(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            return object is [Any] ? "[]" : "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
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
                return "\t\(key): \(oneLine(text))"
            }
            return ([oneLine(header)] + lines).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    static func client(_ w: ManagedWindow, _ world: World) -> [String: Any] {
        let frame = w.appliedFrame ?? w.lastFrame
        let ws = world.workspaces[w.workspace]
        let cls = w.bundleID.isEmpty ? w.appName : w.bundleID
        let fullscreen = w.fullscreenMode.map { $0 == 0 ? 2 : 1 } ?? 0
        let titles = world.config.macos.ipcWindowTitles
        let history = world.focusHistory.reversed().enumerated().first { $0.element == w.id }?.offset ?? -1
        return [
            "address": w.address, "mapped": true, "hidden": w.isParked || w.suspended != nil,
            "at": [int(frame.x), int(frame.y)], "size": [int(frame.width), int(frame.height)],
            "workspace": ["id": w.workspace, "name": ws?.name ?? ""] as [String: Any], "floating": w.isFloating, "monitor": ws?.monitor ?? -1,
            "class": cls, "title": titles ? w.title : "", "initialClass": cls, "initialTitle": titles ? w.initialTitle : "", "pid": Int(w.pid),
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
            "width": int(m.frame.width), "height": int(m.frame.height), "refreshRate": 0, "x": int(m.frame.x), "y": int(m.frame.y),
            "activeWorkspace": ["id": active?.id ?? 0, "name": active?.name ?? ""] as [String: Any],
            "specialWorkspace": ["id": special?.id ?? 0, "name": special?.name ?? ""] as [String: Any],
            "reserved": [int(r.left), int(r.top), int(r.right), int(r.bottom)], "scale": 1, "transform": 0,
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
