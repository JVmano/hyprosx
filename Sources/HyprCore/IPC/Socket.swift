import Foundation

public enum SocketPaths {
    public static func userTempDirectory() -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        return confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0 ? String(cString: buffer) : NSTemporaryDirectory()
    }

    public static func directory(tmp: String = userTempDirectory()) -> String { (tmp as NSString).appendingPathComponent("hyprosx") }

    public static func socket(tmp: String = userTempDirectory()) -> String { (directory(tmp: tmp) as NSString).appendingPathComponent(".socket.sock") }
}

public enum SocketError: Error, Equatable {
    case pathTooLong
    case unsafeDirectory(String)
    case system(String)
}

public enum IPCExit {
    static let refusals = ["unknown request:", "exec over IPC is disabled", "option not settable over IPC", "request too large"]

    public static func isError(command: String, batch: Bool, reply: String) -> Bool {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let refused = text.components(separatedBy: "\n\n").contains { part in
            let part = part.trimmingCharacters(in: .whitespacesAndNewlines)
            return refusals.contains { part.hasPrefix($0) }
        }
        return refused || (!batch && ["dispatch", "keyword", "reload"].contains(command) && text != "ok")
    }
}

enum SocketIO {
    static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        return addr
    }

    static func noSigPipe(_ fd: Int32) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    static func prepare(_ fd: Int32) {
        noSigPipe(fd)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }

    static func deadline(seconds: Int) -> UInt64 {
        DispatchTime.now().uptimeNanoseconds + UInt64(max(0, min(seconds, 86_400))) * 1_000_000_000
    }

    static func wait(_ fd: Int32, _ events: Int32, until deadline: UInt64) -> Bool {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return false }
            var poller = pollfd(fd: fd, events: Int16(events), revents: 0)
            let ready = poll(&poller, 1, Int32((deadline - now) / 1_000_000 + 1))
            if ready > 0 { return true }
            if ready < 0 && errno != EINTR { return false }
        }
    }

    static func readAll(_ fd: Int32, limit: Int, deadline: UInt64, partialOK: Bool) -> [UInt8]? {
        var data: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 65536)
        while data.count < limit {
            guard wait(fd, POLLIN, until: deadline) else { return partialOK && !data.isEmpty ? data : nil }
            let n = read(fd, &buffer, buffer.count)
            if n > 0 {
                data += buffer[0..<n]
            } else if n == 0 {
                break
            } else if errno != EINTR && errno != EAGAIN {
                return nil
            }
        }
        return Array(data.prefix(limit))
    }

    static func writeAll(_ fd: Int32, _ bytes: [UInt8], deadline: UInt64) -> Bool {
        var offset = 0
        while offset < bytes.count {
            guard wait(fd, POLLOUT, until: deadline) else { return false }
            let n = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                offset += n
            } else if n < 0 && errno != EINTR && errno != EAGAIN {
                return false
            }
        }
        return true
    }
}

public final class SocketServer {
    static let maxRequest = 65536
    static let readSeconds = 1
    static let writeSeconds = 2

    private let path: String
    private let queue: DispatchQueue
    private let handler: (String) -> String

    public init(path: String, queue: DispatchQueue, handler: @escaping (String) -> String) {
        self.path = path
        self.queue = queue
        self.handler = handler
    }

    public func start() throws {
        guard var addr = SocketIO.address(path) else { throw SocketError.pathTooLong }
        let dir = (path as NSString).deletingLastPathComponent
        if mkdir(dir, 0o700) != 0 && errno != EEXIST { throw SocketError.system("mkdir \(dir): \(String(cString: strerror(errno)))") }
        let dirFD = open(dir, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard dirFD >= 0 else { throw SocketError.unsafeDirectory(dir) }
        defer { close(dirFD) }
        var st = stat()
        guard fstat(dirFD, &st) == 0, st.st_uid == getuid() else { throw SocketError.unsafeDirectory(dir) }
        if st.st_mode & 0o777 != 0o700, fchmod(dirFD, 0o700) != 0 { throw SocketError.unsafeDirectory(dir) }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket: \(String(cString: strerror(errno)))") }
        SocketIO.noSigPipe(fd)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw SocketError.system("bind \(path): \(message)")
        }
        let thread = Thread { [self] in acceptLoop(fd) }
        thread.name = "hyprosx socket"
        thread.start()
    }

    private func acceptLoop(_ listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            if client >= 0 {
                serve(client)
                continue
            }
            switch errno {
            case EINTR, ECONNABORTED: continue
            case EMFILE, ENFILE, ENOBUFS, ENOMEM: usleep(100_000)
            default: return
            }
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { return }
        SocketIO.prepare(client)
        let readDeadline = SocketIO.deadline(seconds: Self.readSeconds)
        guard let request = SocketIO.readAll(client, limit: Self.maxRequest + 1, deadline: readDeadline, partialOK: true) else { return }
        let reply = request.count > Self.maxRequest ? "request too large" : queue.sync { handler(String(decoding: request, as: UTF8.self)) }
        _ = SocketIO.writeAll(client, Array(reply.utf8), deadline: SocketIO.deadline(seconds: Self.writeSeconds))
    }
}

public enum SocketClient {
    public static func send(_ request: String, to path: String, timeoutSeconds: Int = 5) -> String? {
        guard var addr = SocketIO.address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        SocketIO.noSigPipe(fd)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return nil }
        SocketIO.prepare(fd)
        let deadline = SocketIO.deadline(seconds: timeoutSeconds)
        guard SocketIO.writeAll(fd, Array(request.utf8), deadline: deadline) else { return nil }
        shutdown(fd, SHUT_WR)
        return SocketIO.readAll(fd, limit: 64 << 20, deadline: deadline, partialOK: false).map { String(decoding: $0, as: UTF8.self) }
    }
}
