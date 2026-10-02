import Common
import Foundation

let defaultPluginLogsDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/hyprland-darwin")

/// One log file per plugin: the plugin's stderr plus host messages. Writes on its own serial queue.
final class PluginLog: @unchecked Sendable { // mutable state only touched on `queue`
    let url: URL
    private let queue: DispatchQueue
    private let limit: Int
    private let keep: Int
    private var writes = 0

    @MainActor private static var instances: [URL: PluginLog] = [:]

    /// One writer per file: two instances appending to the same log could overwrite each other's lines
    @MainActor static func shared(name: String, dir: URL = defaultPluginLogsDir) -> PluginLog {
        let url = dir.appending(path: "\(name).log")
        if let log = instances[url] { return log }
        let log = PluginLog(name: name, dir: dir)
        instances[url] = log
        return log
    }

    init(name: String, dir: URL = defaultPluginLogsDir, limit: Int = 1_048_576, keep: Int = 524_288) {
        url = dir.appending(path: "\(name).log")
        queue = DispatchQueue(label: "hyprdarwin.plugin-log.\(name)")
        self.limit = limit
        self.keep = keep
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        append(raw: Data(line.utf8))
    }

    func append(raw: Data) {
        queue.async { [self] in
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: raw)
            try? handle.close()
            writes += 1
            if writes % 20 == 0, let data = try? Data(contentsOf: url), let trimmed = trimmedLog(data, limit: limit, keep: keep) {
                try? trimmed.write(to: url)
            }
        }
    }

    /// Test hook: wait for queued writes, then trim once more
    func flushForTests() {
        queue.sync {
            if let data = try? Data(contentsOf: url), let trimmed = trimmedLog(data, limit: limit, keep: keep) {
                try? trimmed.write(to: url)
            }
        }
    }
}

/// HyprDarwin's own log: startup, config reloads with their errors, permission changes, and failures that would
/// otherwise be silent. ~/Library/Logs/hyprland-darwin/hyprdarwin.log (a temp dir under tests: never the real log)
let appLog = PluginLog(
    name: "hyprdarwin",
    dir: isUnitTest ? FileManager.default.temporaryDirectory.appending(path: "hyprdarwin-test-logs") : defaultPluginLogsDir,
)
