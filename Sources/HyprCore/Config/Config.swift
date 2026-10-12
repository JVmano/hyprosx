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
            if name.hasPrefix("bind"), name.dropFirst(4).allSatisfy({ $0.isASCII && $0.isLowercase }) {
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
                if p.count > 1, p[1] == "addreserved" {
                    let n = p.dropFirst(2).compactMap { finiteDouble($0) }
                    guard p.count == 6, n.count == 4 else { diagnostics.append(Diagnostic(location, "invalid addreserved '\(value)'")); return }
                    config.reservedAreas[p[0]] = Edges(top: n[0], right: n[3], bottom: n[1], left: n[2])
                }
            case "exec", "execr":
                config.exec.append(ExecCommand(command: value, raw: name == "execr"))
            case "exec-once", "execr-once":
                config.execOnce.append(ExecCommand(command: value, raw: name == "execr-once"))
            case "exec-shutdown":
                config.execShutdown.append(ExecCommand(command: value, raw: false))
            case "env":
                guard let comma = value.firstIndex(of: ","), !value[..<comma].trimmingCharacters(in: .whitespaces).isEmpty else {
                    diagnostics.append(Diagnostic(location, "invalid env '\(value)'")); return
                }
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
        var blockFields: [Int: [(key: String, value: String)]] = [:]
        for entry in entries where entry.key.hasPrefix("windowrule:") {
            if let block = entry.block { blockFields[block, default: []].append((String(entry.key.dropFirst("windowrule:".count)), entry.value)) }
        }
        var handledBlocks: Set<Int> = []
        for entry in entries {
            b.config.sourcedFiles.insert(entry.location.file)
            if entry.key.hasPrefix("windowrule:"), let block = entry.block {
                if handledBlocks.insert(block).inserted {
                    let r = WindowRuleParser.parseBlock(blockFields[block] ?? [], location: entry.location)
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
