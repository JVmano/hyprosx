import Testing
import Foundation
@testable import HyprCore

@Suite struct SpawnerTests {
    @Test func spawnedCommandIsItsOwnResponsibleProcess() throws {
        #expect(Spawner.isAvailable)
        let pid = try Spawner.spawn("/bin/sleep 1", environment: ProcessInfo.processInfo.environment).get()
        #expect(Spawner.responsiblePID(for: pid) == pid)
        #expect(Spawner.responsiblePID(for: pid) != Spawner.responsiblePID(for: getpid()))
        kill(pid, SIGKILL)
    }

    @Test func environmentPrefixesPathAndAddsEnvValues() {
        let env = Spawner.environment(base: ["HOME": "/Users/x", "PATH": "/usr/bin:/bin"], extra: [EnvVar(name: "HYPROSX_TEST", value: "ok")])
        #expect(env["PATH"] == "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/Users/x/.local/bin:/usr/bin:/bin")
        #expect(env["HYPROSX_TEST"] == "ok")
        #expect(Spawner.environment(base: ["HOME": "/h"], extra: [])["PATH"] == "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/h/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    @Test func commandRunsThroughTheShellWithTheEnvironment() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hyprosx-spawn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("out").path
        let env = Spawner.environment(base: ProcessInfo.processInfo.environment, extra: [EnvVar(name: "HYPROSX_TEST", value: "a b")])
        _ = try Spawner.spawn("printf '%s' \"$HYPROSX_TEST\" > '\(out)'", environment: env).get()
        var text: String?
        for _ in 0..<200 where text != "a b" {
            usleep(10_000)
            text = try? String(contentsOfFile: out, encoding: .utf8)
        }
        #expect(text == "a b")
    }

    @Test func emptyBlankAndNulCommandsAreRefused() {
        for command in ["", "   ", "\n\t ", "echo a\0b"] {
            #expect((try? Spawner.spawn(command, environment: [:]).get()) == nil)
        }
    }

    @Test func childHasNullStdioNoInheritedDescriptorsAndItsOwnSession() throws {
        let opened = open("/dev/null", O_RDONLY)
        let leaked = fcntl(opened, F_DUPFD, 200)
        close(opened)
        defer { close(leaked) }
        #expect(leaked >= 200)
        let out = try scratchFile()
        let script = "r=ok; [ -e /dev/fd/\(leaked) ] && r=leaked; "
            + "[ /dev/fd/0 -ef /dev/null ] && [ /dev/fd/1 -ef /dev/null ] && [ /dev/fd/2 -ef /dev/null ] || r=stdio; "
            + "p=$(ps -o pgid= -p $$); [ \"$(echo $p)\" = \"$$\" ] || r=\"$r+session\"; printf '%s' \"$r\" > '\(out)'"
        _ = try Spawner.spawn(script, environment: ProcessInfo.processInfo.environment).get()
        #expect(waitForText(out) == "ok")
    }

    @Test func childStartsWithDefaultSignalsAndAnEmptyMask() throws {
        signal(SIGUSR2, SIG_IGN)
        defer { signal(SIGUSR2, SIG_DFL) }
        var blocked = sigset_t()
        sigemptyset(&blocked)
        sigaddset(&blocked, SIGUSR1)
        var previous = sigset_t()
        pthread_sigmask(SIG_BLOCK, &blocked, &previous)
        defer { pthread_sigmask(SIG_SETMASK, &previous, nil) }
        let ignored = try scratchFile()
        let masked = try scratchFile()
        let env = ProcessInfo.processInfo.environment
        let a = try Spawner.spawn("kill -USR2 $$; printf survived > '\(ignored)'", environment: env).get()
        let b = try Spawner.spawn("kill -USR1 $$; printf survived > '\(masked)'", environment: env).get()
        #expect(waitForExit(a) && waitForExit(b))
        #expect(!FileManager.default.fileExists(atPath: ignored))
        #expect(!FileManager.default.fileExists(atPath: masked))
    }

    private func scratchFile() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hyprosx-spawn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("out").path
    }

    private func waitForText(_ path: String) -> String? {
        for _ in 0..<300 {
            if let text = try? String(contentsOfFile: path, encoding: .utf8), !text.isEmpty { return text }
            usleep(10_000)
        }
        return nil
    }

    private func waitForExit(_ pid: pid_t) -> Bool {
        for _ in 0..<300 {
            if kill(pid, 0) == -1 && errno == ESRCH { return true }
            usleep(10_000)
        }
        return false
    }
}
