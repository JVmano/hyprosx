import Foundation
import HyprCore

final class ConfigStore {
    let path: String
    private let environment: [String: String]
    private var sources: [DispatchSourceFileSystemObject] = []
    private var watched: [String] = []
    private var fingerprint = ""
    private var stamps: [String: String] = [:]
    private var pending: DispatchWorkItem?

    init(arguments: [String] = CommandLine.arguments, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let flag = arguments.firstIndex(of: "--config").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let custom = flag ?? environment["HYPROSX_CONFIG"].flatMap { $0.isEmpty ? nil : $0 }
        path = ((custom ?? "~/.config/hyprosx/hyprland.conf") as NSString).expandingTildeInPath
        self.environment = environment
    }

    var directory: String { (path as NSString).deletingLastPathComponent }
    var appsPath: String { (directory as NSString).appendingPathComponent("apps.conf") }
    var mainFileExists: Bool { FileManager.default.fileExists(atPath: path) }

    func load(writingDefaults: Bool = false) -> (Config, [Diagnostic]) {
        let fm = FileManager.default
        if writingDefaults, !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try? DefaultConfig.text.write(toFile: path, atomically: true, encoding: .utf8)
            if !fm.fileExists(atPath: appsPath) { try? DefaultConfig.appsText.write(toFile: appsPath, atomically: true, encoding: .utf8) }
        }
        stamps = Dictionary(Set(watched + [path, appsPath]).map { ($0, stamp($0)) }, uniquingKeysWith: { a, _ in a })
        let result = ConfigLoader.load(path: path, environment: environment)
        return (result.config, result.diagnostics)
    }

    func watch(sourced: Set<String>, enabled: Bool, onChange: @escaping () -> Void) {
        sources.forEach { $0.cancel() }
        sources = []
        pending?.cancel()
        pending = nil
        let known = stamps
        stamps = [:]
        guard enabled else { return }
        watched = Array(sourced.union([path, appsPath])).sorted()
        fingerprint = currentFingerprint(known)
        for target in watched + [directory] {
            let fd = open(target, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
            source.setEventHandler { [weak self] in self?.changed(onChange) }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
        if fingerprint != currentFingerprint() { changed(onChange) }
    }

    private func changed(_ onChange: @escaping () -> Void) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.currentFingerprint() != self.fingerprint else { return }
            onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func stamp(_ file: String) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? -1
        return "\(modified) \(size)"
    }

    private func currentFingerprint(_ known: [String: String] = [:]) -> String {
        watched.map { "\($0) \(known[$0] ?? stamp($0))" }.joined(separator: "\n")
    }
}
