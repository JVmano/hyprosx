import Foundation

public enum ConfigLoader {
    private final class ReadLog {
        var paths: Set<String> = []
    }

    public static func expandGlob(_ pattern: String) -> [String] {
        var result = glob_t()
        defer { globfree(&result) }
        guard Darwin.glob(pattern, 0, nil, &result) == 0 else { return [] }
        return (0..<Int(result.gl_pathc)).compactMap { result.gl_pathv[$0].map { String(cString: $0) } }
    }

    public static func load(path: String, environment: [String: String]) -> (config: Config, diagnostics: [Diagnostic]) {
        let reads = ReadLog()
        let parser = HyprlangParser(environment: environment, readFile: { file in
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
            reads.paths.insert((file as NSString).standardizingPath)
            return text
        }, glob: expandGlob)
        let parsed = parser.parse(path: path)
        let built = ConfigBuilder.build(parsed.entries)
        var diagnostics = parsed.diagnostics + built.diagnostics
        let apps = ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent("apps.conf")
        if FileManager.default.fileExists(atPath: apps), reads.paths.contains((path as NSString).standardizingPath),
           !reads.paths.contains((apps as NSString).standardizingPath) {
            diagnostics.append(Diagnostic(SourceLocation(file: path, line: 1),
                                          "apps.conf is not sourced; add `source = ./apps.conf` so its app rules apply", isWarning: true))
        }
        return (built.config, diagnostics)
    }
}
