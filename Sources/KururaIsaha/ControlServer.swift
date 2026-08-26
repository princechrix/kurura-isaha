import Darwin
import Foundation
import KururaCore

/// Listens on a Unix domain socket so the `kurura` CLI can drive the running app.
///
/// A socket rather than a URL scheme or distributed notification because the CLI needs an
/// *answer* — `kurura status` has to print what is running, and `kurura start` has to
/// report the id it got. One JSON line in, one JSON line out, connection closed.
final class ControlServer {
    /// Invoked on the main thread. Returning is what unblocks the client.
    var handler: ((ControlCommand) -> ControlResponse)?

    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "rw.ivas.kurura.control")

    private final class Box {
        private let lock = NSLock()
        private var value: ControlResponse
        init(_ value: ControlResponse) { self.value = value }
        func set(_ new: ControlResponse) { lock.lock(); value = new; lock.unlock() }
        func get() -> ControlResponse { lock.lock(); defer { lock.unlock() }; return value }
    }

    // MARK: - Lifecycle

    @discardableResult
    func start() -> Bool {
        stop()
        let path = ControlPaths.socketPath
        try? FileManager.default.createDirectory(
            at: ControlPaths.supportDirectory, withIntermediateDirectories: true)
        // A socket file left behind by a crash would make bind() fail with EADDRINUSE.
        // Nothing else owns this path, so clearing it is safe.
        unlink(path)

        let listening = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listening >= 0 else { return false }

        var reuse: Int32 = 1
        setsockopt(listening, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(listening)
            return false
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            bytes.withUnsafeBytes { source in destination.copyMemory(from: source) }
        }

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                bind(listening, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listening, 8) == 0 else {
            close(listening)
            return false
        }
        // Only this user's processes have any business driving this app.
        chmod(path, 0o600)

        descriptor = listening
        let reader = DispatchSource.makeReadSource(fileDescriptor: listening, queue: queue)
        reader.setEventHandler { [weak self] in self?.acceptOne() }
        reader.setCancelHandler { close(listening) }
        reader.resume()
        source = reader
        return true
    }

    func stop() {
        source?.cancel()
        source = nil
        if descriptor >= 0 {
            descriptor = -1
            unlink(ControlPaths.socketPath)
        }
    }

    deinit { stop() }

    // MARK: - Serving

    private func acceptOne() {
        let client = accept(descriptor, nil, nil)
        guard client >= 0 else { return }
        queue.async { [weak self] in self?.serve(client) }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }

        // A CLI that dies mid-request must not take the app with it via SIGPIPE.
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var window = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &window, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &window, socklen_t(MemoryLayout<timeval>.size))

        guard let line = readRequest(client) else { return }
        let response: ControlResponse
        if let command = try? ControlCoding.decoder().decode(ControlCommand.self, from: line) {
            response = runOnMain(command)
        } else {
            response = .failure("this version of the app does not understand that command")
        }

        guard var data = try? ControlCoding.encoder().encode(response) else { return }
        data.append(0x0A)
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = write(client, base + offset, buffer.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }
    }

    /// Timers live on the main thread; the socket does not. Everything crosses here.
    private func runOnMain(_ command: ControlCommand) -> ControlResponse {
        let box = Box(.failure("the app did not answer in time"))
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.main.async { [weak self] in
            box.set(self?.handler?(command) ?? .failure("the app is not accepting commands"))
            done.signal()
        }
        _ = done.wait(timeout: .now() + 5)
        return box.get()
    }

    private func readRequest(_ client: Int32) -> Data? {
        var accumulated = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while accumulated.count < 1 << 20 {
            let count = read(client, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if count == 0 { break }
            accumulated.append(contentsOf: chunk[0..<count])
            if let newline = accumulated.firstIndex(of: 0x0A) {
                return accumulated[accumulated.startIndex..<newline]
            }
        }
        return accumulated.isEmpty ? nil : accumulated
    }
}
