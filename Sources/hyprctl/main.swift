import Foundation
import HyprCore

let usage = """
usage: hyprctl [-j] [-q] <command> [args]
       hyprctl [-j] [-q] --batch "command ; command"
commands: dispatch, keyword, reload, clients, activewindow, workspaces, activeworkspace,
          monitors, binds, getoption, configerrors, version, cursorpos, perf
"""

var json = false
var quiet = false
var batch: String?
var words: [String] = []
var arguments = Array(CommandLine.arguments.dropFirst())
while !arguments.isEmpty {
    let word = arguments.removeFirst()
    switch word {
    case "-j": json = true
    case "-q": quiet = true
    case "--batch": batch = arguments.isEmpty ? "" : arguments.removeFirst()
    case "-i", "--instance": if !arguments.isEmpty { arguments.removeFirst() }
    case "-h", "--help":
        print(usage)
        exit(0)
    default: words.append(word)
    }
}

let body = batch.map { "[[BATCH]]" + $0 } ?? words.joined(separator: " ")
guard !body.trimmingCharacters(in: .whitespaces).isEmpty else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(1)
}
let path = SocketPaths.socket()
guard let reply = SocketClient.send((json ? "j" : "") + "/" + body, to: path) else {
    FileHandle.standardError.write(Data("HyprOSX is not running (no socket at \(path))\n".utf8))
    exit(1)
}
if !quiet && !reply.isEmpty { print(reply.hasSuffix("\n") ? String(reply.dropLast()) : reply) }
exit(IPCExit.isError(command: words.first ?? "", batch: batch != nil, reply: reply) ? 1 : 0)
