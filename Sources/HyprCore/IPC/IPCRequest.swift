import Foundation

public struct IPCRequest: Equatable, Sendable {
    public var json: Bool
    public var commands: [String]
    public init(json: Bool, commands: [String]) { self.json = json; self.commands = commands }

    public static func parse(_ raw: String) -> IPCRequest {
        var body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var flags = ""
        if let slash = body.firstIndex(of: "/") {
            let prefix = body[..<slash]
            if prefix.allSatisfy({ ("a" ... "z").contains($0) }) {
                flags = String(prefix)
                body = String(body[body.index(after: slash)...])
            }
        }
        var commands = [body]
        if body.hasPrefix("[[BATCH]]") {
            commands = body.dropFirst("[[BATCH]]".count).split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return IPCRequest(json: flags.contains("j"), commands: commands)
    }
}

public enum IPCPolicy {
    static let blockedKeywords: Set<String> = ["source", "env"]

    public static func isReadOnly(_ command: String) -> Bool {
        let (name, rest) = IPCResponder.split(command)
        guard name == "keyword" else { return false }
        let key = IPCResponder.split(rest).0
        return key.split(separator: ":").last?.lowercased().hasPrefix("ipc_") == true
    }

    public static func isBlocked(_ command: String, allowExec: Bool) -> Bool {
        if allowExec { return false }
        let (name, rest) = IPCResponder.split(command)
        switch name {
        case "dispatch":
            let (dispatcher, arguments) = IPCResponder.split(rest)
            if case .success(.exec) = CommandParser.parse(dispatcher: dispatcher, arguments: arguments) { return true }
            return false
        case "keyword":
            let (key, value) = IPCResponder.split(rest)
            let last = key.split(separator: ":").last.map { $0.lowercased() } ?? ""
            if last.hasPrefix("exec") || blockedKeywords.contains(last) { return true }
            let lowered = value.lowercased()
            if last.hasPrefix("bind") { return lowered.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("exec") } }
            return last == "workspace" && lowered.contains("on-created-empty")
        default:
            return false
        }
    }
}
