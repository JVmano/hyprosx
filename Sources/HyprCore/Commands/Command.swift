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
            guard words.count == 2, let x = finiteDouble(words[0]), let y = finiteDouble(words[1]) else { return nil }
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
