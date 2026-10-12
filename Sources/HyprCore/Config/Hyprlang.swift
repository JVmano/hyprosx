import Foundation

public struct ConfigEntry: Equatable, Sendable {
    public var key: String
    public var value: String
    public var location: SourceLocation
    public var block: Int?
    public init(key: String, value: String, location: SourceLocation, block: Int?) {
        self.key = key; self.value = value; self.location = location; self.block = block
    }
}

public struct HyprlangParser {
    let environment: [String: String]
    let readFile: (String) -> String?
    let glob: (String) -> [String]

    public init(environment: [String: String], readFile: @escaping (String) -> String?, glob: @escaping (String) -> [String]) {
        self.environment = environment; self.readFile = readFile; self.glob = glob
    }

    public func parse(path: String) -> (entries: [ConfigEntry], diagnostics: [Diagnostic]) {
        guard let text = readFile(path) else {
            return ([], [Diagnostic(SourceLocation(file: path, line: 0), "config file \(path) is inaccessible")])
        }
        return parse(text: text, path: path)
    }

    public func parse(text: String, path: String) -> (entries: [ConfigEntry], diagnostics: [Diagnostic]) {
        var state = State(variables: environment)
        run(text: text, path: path, state: &state, stack: [path])
        return (state.entries, state.diagnostics)
    }

    private struct State {
        var variables: [String: String]
        var entries: [ConfigEntry] = []
        var diagnostics: [Diagnostic] = []
        var nextBlock = 1
    }

    private func run(text: String, path: String, state: inout State, stack: [String]) {
        var categories: [(name: String, block: Int)] = []
        var skipDepth = 0
        var ifDepth = 0
        var noError = false
        for (lineNumber, rawLine) in logicalLines(text, path: path, state: &state) {
            let diagnosticCount = state.diagnostics.count
            defer { if noError && state.diagnostics.count > diagnosticCount { state.diagnostics.removeSubrange(diagnosticCount...) } }
            let loc = SourceLocation(file: path, line: lineNumber)
            let trimmedRaw = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmedRaw.hasPrefix("# hyprlang ") {
                let words = trimmedRaw.dropFirst("# hyprlang ".count).split(separator: " ").map(String.init)
                switch words.first {
                case "if":
                    ifDepth += 1
                    if skipDepth > 0 { skipDepth += 1; continue }
                    let arg = words.count > 1 ? words[1] : ""
                    let negate = arg.hasPrefix("!")
                    let name = negate ? String(arg.dropFirst()) : arg
                    let truthy = !(state.variables[name] ?? "").isEmpty
                    if truthy == negate { skipDepth = 1 }
                case "noerror":
                    if skipDepth == 0 { noError = ["true", "yes", "on", "1"].contains((words.count > 1 ? words[1] : "").lowercased()) }
                case "endif":
                    if ifDepth == 0 { state.diagnostics.append(Diagnostic(loc, "stray endif")); continue }
                    ifDepth -= 1
                    if skipDepth > 0 { skipDepth -= 1 }
                default:
                    break
                }
                continue
            }
            if skipDepth > 0 { continue }
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line == "}" {
                if categories.isEmpty { state.diagnostics.append(Diagnostic(loc, "Stray category close")) } else { categories.removeLast() }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else {
                if line.hasSuffix("{") {
                    let name = line.dropLast().trimmingCharacters(in: .whitespaces)
                    categories.append((name, state.nextBlock))
                    state.nextBlock += 1
                } else {
                    state.diagnostics.append(Diagnostic(loc, "Invalid config line"))
                }
                continue
            }
            var key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key.isEmpty { state.diagnostics.append(Diagnostic(loc, "Empty lhs.")); continue }
            if key.hasPrefix("$") {
                state.variables[String(key.dropFirst())] = evaluate(value, state: &state, loc: loc)
                continue
            }
            key = expand(key, state: &state, loc: loc)
            value = evaluate(value, state: &state, loc: loc)
            let fullKey = (categories.map(\.name) + [key]).joined(separator: ":")
            if fullKey == "source" {
                source(value, from: path, loc: loc, state: &state, stack: stack)
                continue
            }
            state.entries.append(ConfigEntry(key: fullKey, value: value, location: loc, block: categories.last?.block))
        }
        if !categories.isEmpty {
            let lastLine = Self.physicalLines(text).count
            state.diagnostics.append(Diagnostic(SourceLocation(file: path, line: max(1, lastLine)), "Unclosed category at EOF"))
        }
    }

    private static func physicalLines(_ text: String) -> [Substring] {
        text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" }
    }

    private func logicalLines(_ text: String, path: String, state: inout State) -> [(Int, String)] {
        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        let physical = Self.physicalLines(body).map { line -> String in
            var s = String(line)
            if s.hasSuffix("\r") { s.removeLast() }
            return s
        }
        var result: [(Int, String)] = []
        var pending: (Int, String)?
        for (i, line) in physical.enumerated() {
            var current = line
            let start = pending?.0 ?? (i + 1)
            if let p = pending { current = p.1 + line; pending = nil }
            let trimmedTrailing = current.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
            if trimmedTrailing.hasSuffix("\\") && !trimmedTrailing.hasSuffix("\\\\") {
                if i == physical.count - 1 {
                    state.diagnostics.append(Diagnostic(SourceLocation(file: path, line: i + 1), "Last line ends with backslash"))
                    result.append((start, String(trimmedTrailing.dropLast())))
                } else {
                    pending = (start, String(trimmedTrailing.dropLast()))
                }
                continue
            }
            result.append((start, current))
        }
        return result
    }

    private func stripComment(_ line: String) -> String {
        var out = ""
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            if chars[i] == "#" {
                if i + 1 < chars.count && chars[i + 1] == "#" { out.append("#"); i += 2; continue }
                break
            }
            out.append(chars[i]); i += 1
        }
        return out
    }

    private func expand(_ s: String, state: inout State, loc: SourceLocation) -> String {
        guard s.contains("$") else { return s }
        let names = state.variables.keys.sorted { $0.count > $1.count }
        var current = s
        for round in 0..<100 {
            var changed = false
            for name in names where current.contains("$" + name) {
                current = current.replacingOccurrences(of: "$" + name, with: state.variables[name] ?? "")
                changed = true
            }
            if !changed { return current }
            if round == 99 { state.diagnostics.append(Diagnostic(loc, "Expanding variables exceeded max iteration limit")) }
        }
        return current
    }

    private func evaluate(_ value: String, state: inout State, loc: SourceLocation) -> String {
        let expanded = expand(value, state: &state, loc: loc)
        return arithmetic(expanded, state: state)
    }

    private func arithmetic(_ s: String, state: State) -> String {
        guard s.contains("{") else { return s }
        var out = ""
        var rest = Substring(s)
        while let open = rest.range(of: "{{") {
            let before = rest[..<open.lowerBound]
            if before.hasSuffix("\\") {
                out += before.dropLast() + "{{"
                rest = rest[open.upperBound...]
                continue
            }
            guard let close = rest[open.upperBound...].range(of: "}}") else { break }
            out += before
            let expr = rest[open.upperBound..<close.lowerBound].split(separator: " ").map(String.init)
            if expr.count == 3, let a = operand(expr[0], state), let b = operand(expr[2], state), let r = apply(expr[1], a, b) {
                out += r == r.rounded() && abs(r) < 1e15 ? String(Int(r)) : String(r)
            } else {
                out += "{{" + rest[open.upperBound..<close.lowerBound] + "}}"
            }
            rest = rest[close.upperBound...]
        }
        out += rest
        return out.replacingOccurrences(of: "{\\{", with: "{{")
    }

    private func operand(_ token: String, _ state: State) -> Double? {
        Double(token) ?? state.variables[token].flatMap { Double($0) }
    }

    private func apply(_ op: String, _ a: Double, _ b: Double) -> Double? {
        switch op {
        case "+": return a + b
        case "-": return a - b
        case "*": return a * b
        case "/": return b == 0 ? nil : a / b
        default: return nil
        }
    }

    private func source(_ raw: String, from path: String, loc: SourceLocation, state: inout State, stack: [String]) {
        var target = raw
        if target.hasPrefix("~") { target = (state.variables["HOME"] ?? environment["HOME"] ?? "") + target.dropFirst() }
        if !target.hasPrefix("/") {
            let dir = (path as NSString).deletingLastPathComponent
            target = (dir as NSString).appendingPathComponent(target)
        }
        if target.count < 2 { state.diagnostics.append(Diagnostic(loc, "source= path \(raw) bogus!")); return }
        let matches = glob(target)
        if matches.isEmpty { state.diagnostics.append(Diagnostic(loc, "source= globbing error: found no match")); return }
        for file in matches {
            if stack.contains(file) { state.diagnostics.append(Diagnostic(loc, "source= recursion detected")); continue }
            guard let text = readFile(file) else {
                state.diagnostics.append(Diagnostic(loc, "source= file \(file) is inaccessible!"))
                continue
            }
            run(text: text, path: file, state: &state, stack: stack + [file])
        }
    }
}
