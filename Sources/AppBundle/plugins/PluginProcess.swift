import Darwin
import Foundation

struct PluginTiming: Sendable {
    var scale: Double = 1 // tests shrink every duration
    var timeoutCap: TimeInterval { 5 * scale }
    func interval(_ seconds: Int) -> TimeInterval { Double(seconds) * scale }
}

enum PluginStatus: Equatable, Sendable, CustomStringConvertible {
    case starting
    case running
    case failing(Int)
    case restarting(in: TimeInterval)
    case stopped(String)
    case missing(String)
    case invalid(String)

    var description: String {
        switch self {
            case .starting: "starting"
            case .running: "running"
            case .failing(let n): "failing (\(n))"
            case .restarting(let delay): "restarting in \(Int(delay.rounded(.up)))s"
            case .stopped(let reason): "stopped: \(reason)"
            case .missing(let reason): "missing: \(reason)"
            case .invalid(let reason): "invalid: \(reason)"
        }
    }
}

private final class RunState: @unchecked Sendable { // touched only on the process queue
    var splitter = LineSplitter()
    var gotLine = false
    var exited = false
    var eof = false
}

/// Runs one plugin. Every mutable field is touched only on `queue`; results hop to the main actor.
final class PluginProcess: @unchecked Sendable {
    private let dir: String
    private let manifest: PluginManifest
    private let environment: [String: String]
    private let timing: PluginTiming
    private let log: PluginLog
    private let onLine: @MainActor @Sendable (PluginLine) -> Void
    private let onStatus: @MainActor @Sendable (PluginStatus) -> Void
    private let queue: DispatchQueue

    private var isStopped = false
    private var currentPid: pid_t? = nil
    private var startedAt = Date()
    private var supervisor: StreamSupervisor
    private var health = IntervalHealth()
    private var intervalTimer: DispatchSourceTimer? = nil
    private var intervalRunning = false
    private var stdinFd: Int32 = -1
    private var pending = BoundedQueue<Data>(capacity: 64)
    private var partial = Data()
    private var retryScheduled = false

    init(
        name: String,
        dir: String,
        manifest: PluginManifest,
        environment: [String: String],
        timing: PluginTiming,
        log: PluginLog,
        onLine: @escaping @MainActor @Sendable (PluginLine) -> Void,
        onStatus: @escaping @MainActor @Sendable (PluginStatus) -> Void,
    ) {
        self.dir = dir
        self.manifest = manifest
        self.environment = environment
        self.timing = timing
        self.log = log
        self.onLine = onLine
        self.onStatus = onStatus
        queue = DispatchQueue(label: "hyprdarwin.plugin.\(name)")
        supervisor = StreamSupervisor(baseDelay: 1 * timing.scale, maxDelay: 60 * timing.scale, window: 60 * timing.scale)
    }

    func start() {
        queue.async { [self] in
            switch manifest.mode {
                case .stream: startStream()
                case .interval(let seconds): startIntervalTimer(seconds)
            }
        }
    }

    /// Graceful: close stdin (protocol: stream plugins exit on EOF), SIGTERM the group, SIGKILL after 1 s
    func stop() {
        queue.async { [self] in
            shutDown(signal: SIGTERM)
            if let pid = currentPid {
                queue.asyncAfter(deadline: .now() + 1) { [self] in
                    if currentPid == pid { kill(-pid, SIGKILL) }
                }
            }
        }
    }

    /// For app termination: kill the group now, synchronously
    func stopImmediately() {
        queue.sync { shutDown(signal: SIGKILL) }
    }

    func send(_ line: String) {
        queue.async { [self] in
            guard !isStopped, stdinFd >= 0 else { return }
            pending.append(Data((line + "\n").utf8))
            flush()
        }
    }

    func pendingEventCount() -> Int { queue.sync { pending.count } }

    // MARK: queue-only

    private func shutDown(signal: Int32) {
        isStopped = true
        intervalTimer?.cancel()
        intervalTimer = nil
        closeStdin()
        if let pid = currentPid { kill(-pid, signal) }
    }

    private func report(_ status: PluginStatus) {
        let onStatus = onStatus
        DispatchQueue.main.async { MainActor.assumeIsolated { onStatus(status) } }
    }

    private func deliver(_ piece: LineSplitter.Piece) {
        let line: PluginLine = switch piece {
            case .line(let data): decodePluginLine(data)
            case .tooLong: .invalid("line longer than 64 KB")
        }
        let onLine = onLine
        DispatchQueue.main.async { MainActor.assumeIsolated { onLine(line) } }
    }

    /// Spawns with stdout/stderr pipes. Returns the read ends; the child's ends are closed here.
    private func spawn(stdin childStdin: Int32) -> (pid: pid_t, stdout: Int32, stderr: Int32)? {
        var out: [Int32] = [0, 0]
        var err: [Int32] = [0, 0]
        guard unsafe pipe(&out) == 0 else { return nil }
        guard unsafe pipe(&err) == 0 else {
            close(out[0])
            close(out[1])
            return nil
        }
        switch spawnPlugin(path: manifest.execPath, environment: environment, directory: dir, stdin: childStdin, stdout: out[1], stderr: err[1]) {
            case .success(let pid):
                close(out[1])
                close(err[1])
                currentPid = pid
                return (pid, out[0], err[0])
            case .failure(let message):
                [out[0], out[1], err[0], err[1]].forEach { close($0) }
                log.write(message)
                return nil
        }
    }

    private func readLines(_ fd: Int32, _ state: RunState, onPiece: @escaping @Sendable (LineSplitter.Piece) -> Void, onEOF: @escaping @Sendable () -> Void) {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        // The handler captures its own handle: nothing else retains it, and deallocating it would close the fd
        // (the plugin then dies of SIGPIPE). Clearing the handler at EOF breaks the cycle.
        handle.readabilityHandler = { [self, handle] _ in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            queue.async {
                if data.isEmpty {
                    state.splitter.finish().forEach(onPiece)
                    onEOF()
                } else {
                    state.splitter.feed(data).forEach(onPiece)
                }
            }
        }
    }

    private func readStderr(_ fd: Int32) {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        handle.readabilityHandler = { [log, handle] _ in // captures its own handle, see readLines
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { log.append(raw: data) }
        }
    }

    private func watchExit(_ pid: pid_t, then: @escaping @Sendable (Int32) -> Void) {
        DispatchQueue.global(qos: .utility).async { [self] in
            var status: Int32 = 0
            while unsafe waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            let exitStatus = status
            queue.async { [self] in
                if currentPid == pid { currentPid = nil }
                then(exitStatus)
            }
        }
    }

    // MARK: stream

    private func startStream() {
        guard !isStopped else { return }
        var input: [Int32] = [0, 0]
        guard unsafe pipe(&input) == 0 else { return handleStreamExit() }
        guard let child = spawn(stdin: input[0]) else {
            close(input[0])
            close(input[1])
            return handleStreamExit()
        }
        close(input[0])
        stdinFd = input[1]
        _ = fcntl(stdinFd, F_SETFL, O_NONBLOCK)
        _ = fcntl(stdinFd, F_SETNOSIGPIPE, 1)
        pending = BoundedQueue(capacity: 64)
        partial = Data()
        startedAt = Date()
        report(.running)
        let state = RunState()
        readLines(child.stdout, state, onPiece: { [self] in deliver($0) }, onEOF: {})
        readStderr(child.stderr)
        watchExit(child.pid) { [self] status in
            closeStdin()
            log.write("exited with status \(status)")
            handleStreamExit()
        }
    }

    private func handleStreamExit() {
        guard !isStopped else { return }
        switch supervisor.onExit(at: Date(), startedAt: startedAt) {
            case .stop:
                report(.stopped("crashed 5 times within 60 s"))
            case .restart(let delay):
                report(.restarting(in: delay))
                queue.asyncAfter(deadline: .now() + delay) { [self] in startStream() }
        }
    }

    private func closeStdin() {
        if stdinFd >= 0 { close(stdinFd) }
        stdinFd = -1
    }

    /// Non-blocking: on a full pipe keep the bytes and retry shortly; the bounded queue drops the oldest events
    private func flush() {
        while stdinFd >= 0 {
            if partial.isEmpty {
                guard let next = pending.popFirst() else { return }
                partial = next
            }
            let written = unsafe partial.withUnsafeBytes { unsafe write(stdinFd, $0.baseAddress, $0.count) }
            if written > 0 {
                partial.removeFirst(written)
                continue
            }
            if written < 0 && errno == EAGAIN {
                scheduleRetry()
                return
            }
            partial = Data() // EPIPE or similar: the plugin is gone; the exit watcher takes over
            return
        }
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        queue.asyncAfter(deadline: .now() + 0.05) { [self] in
            retryScheduled = false
            flush()
        }
    }

    // MARK: interval

    private func startIntervalTimer(_ seconds: Int) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: timing.interval(seconds))
        timer.setEventHandler { [self] in runOnce(seconds) }
        timer.resume()
        intervalTimer = timer
    }

    private func runOnce(_ seconds: Int) {
        guard !isStopped, !intervalRunning else { return }
        let devNull = unsafe open("/dev/null", O_RDONLY)
        defer { close(devNull) }
        guard let child = spawn(stdin: devNull) else { return finishInterval(success: false) }
        intervalRunning = true
        let state = RunState()
        let finishIfDone: @Sendable () -> Void = { [self] in
            if state.exited && state.eof { finishInterval(success: state.gotLine) }
        }
        readLines(child.stdout, state, onPiece: { [self] piece in
            guard !state.gotLine else { return }
            deliver(piece)
            if case .line = piece {
                state.gotLine = true
                kill(-child.pid, SIGKILL) // one line per run is all we take
            }
        }, onEOF: {
            state.eof = true
            finishIfDone()
        })
        readStderr(child.stderr)
        let timeout = min(timing.interval(seconds), timing.timeoutCap)
        queue.asyncAfter(deadline: .now() + timeout) { [self] in
            guard !state.exited, !state.gotLine else { return }
            log.write("timed out after \(timeout) s")
            kill(-child.pid, SIGKILL)
        }
        watchExit(child.pid) { _ in
            state.exited = true
            finishIfDone()
        }
    }

    private func finishInterval(success: Bool) {
        intervalRunning = false
        health.record(success: success)
        report(health.isFailing ? .failing(health.consecutiveFailures) : .running)
    }
}
