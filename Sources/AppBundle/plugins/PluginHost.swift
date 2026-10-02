import Combine
import Foundation

@MainActor final class WidgetStore: ObservableObject {
    @Published private(set) var widgets: [String: WidgetState] = [:]
    @Published private(set) var statuses: [String: PluginStatus] = [:]

    func apply(_ patch: WidgetPatch, to name: String) { widgets[name, default: WidgetState()].apply(patch) }
    func setStatus(_ status: PluginStatus, for name: String) { statuses[name] = status }
    func remove(_ name: String) {
        widgets[name] = nil
        statuses[name] = nil
    }
}

struct PluginSnapshot: Equatable, Encodable {
    let name: String
    let mode: String
    let status: String
    let restarts: Int
    let widget: WidgetState
}

func formatPluginLine(_ s: PluginSnapshot) -> String {
    "\(s.name) | \(s.mode) | \(s.status) | \(s.restarts) | \(s.widget.label ?? "")"
}

@MainActor final class PluginHost {
    static let shared = PluginHost()

    let store = WidgetStore()
    private let timing: PluginTiming
    private let bundledDir: String?
    private let logsDir: URL
    private let runCommand: @MainActor (String, String) -> Void
    private let initialEvents: @MainActor () -> [(PluginEventKind, String)]
    private var order: [String] = []
    private var plugins: [String: Hosted] = [:]

    @MainActor private final class Hosted {
        let resolution: PluginResolution
        let environment: [String: String]
        var process: PluginProcess? = nil
        var status: PluginStatus
        var restarts = 0

        init(_ resolution: PluginResolution, environment: [String: String], status: PluginStatus) {
            self.resolution = resolution
            self.environment = environment
            self.status = status
        }

        var isStopped: Bool {
            if case .stopped = status { return true }
            return false
        }

        var modeName: String {
            if case .ok(_, let manifest) = resolution { return manifest.mode.name }
            return "-"
        }
    }

    init(
        timing: PluginTiming = PluginTiming(),
        bundledDir: String? = bundledPluginsDir(),
        logsDir: URL = defaultPluginLogsDir,
        runCommand: @escaping @MainActor (String, String) -> Void = runPluginCommand,
        initialEvents: @escaping @MainActor () -> [(PluginEventKind, String)] = currentStateEvents,
    ) {
        self.timing = timing
        self.bundledDir = bundledDir
        self.logsDir = logsDir
        self.runCommand = runCommand
        self.initialEvents = initialEvents
    }

    /// Removed → stopped; changed resolution (dir or manifest) or environment → restarted; unchanged → left running
    func sync(names: [String], userDirs: [String], environment: [String: String]) {
        let resolved = resolvePlugins(
            names: names,
            userDirs: userDirs,
            bundledDir: bundledDir,
            readManifest: readPluginManifest,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
        )
        let wanted = Set(resolved.map(\.name))
        for (name, hosted) in plugins where !wanted.contains(name) {
            hosted.process?.stop()
            plugins[name] = nil
            store.remove(name)
        }
        for plugin in resolved {
            // Unchanged and alive: leave it running. A crash-looped (stopped) plugin is retried on reload.
            if let existing = plugins[plugin.name], existing.resolution == plugin.resolution,
               existing.environment == environment, !existing.isStopped { continue }
            plugins[plugin.name]?.process?.stop()
            store.remove(plugin.name) // no stale widget from the previous process (or a plugin that went missing)
            plugins[plugin.name] = makeHosted(plugin, environment)
        }
        order = resolved.map(\.name)
    }

    func send(_ kind: PluginEventKind, _ line: String) {
        for name in order { deliver(kind, line, button: nil, to: name) }
    }

    func click(_ name: String, button: String) {
        deliver(.click, encodePluginEvent(.click, ["button": button]), button: button, to: name)
    }

    private func deliver(_ kind: PluginEventKind, _ line: String, button: String?, to name: String) {
        guard let hosted = plugins[name], case .ok(_, let manifest) = hosted.resolution, manifest.events.contains(kind) else { return }
        switch manifest.mode {
            case .stream: hosted.process?.send(line)
            case .interval: hosted.process?.trigger(kind, line: line, button: button)
        }
    }

    func stopAll(immediately: Bool = false) {
        for hosted in plugins.values {
            if immediately { hosted.process?.stopImmediately() } else { hosted.process?.stop() }
        }
        plugins = [:]
        order = []
    }

    func snapshot() -> [PluginSnapshot] {
        order.compactMap { name in
            plugins[name].map {
                PluginSnapshot(name: name, mode: $0.modeName, status: $0.status.description, restarts: $0.restarts, widget: store.widgets[name] ?? WidgetState())
            }
        }
    }

    func pendingEventCount(_ name: String) -> Int? { plugins[name]?.process?.pendingEventCount() }

    private func makeHosted(_ plugin: ResolvedPlugin, _ environment: [String: String]) -> Hosted {
        switch plugin.resolution {
            case .missing(let searched):
                let status = PluginStatus.missing("no plugin folder in \(searched.joined(separator: ", "))")
                store.setStatus(status, for: plugin.name)
                return Hosted(plugin.resolution, environment: environment, status: status)
            case .invalid(let reason):
                store.setStatus(.invalid(reason), for: plugin.name)
                return Hosted(plugin.resolution, environment: environment, status: .invalid(reason))
            case .ok(let dir, let manifest):
                let name = plugin.name
                let log = PluginLog.shared(name: name, dir: logsDir)
                let hosted = Hosted(plugin.resolution, environment: environment, status: .starting)
                store.setStatus(.starting, for: name)
                let process = PluginProcess(
                    name: name,
                    dir: dir,
                    manifest: manifest,
                    environment: environment.merging(["HYPR_PLUGIN_NAME": name, "HYPR_PLUGIN_DIR": dir]) { _, new in new },
                    timing: timing,
                    log: log,
                    onLine: { [weak self, weak hosted] line in
                        guard let self, let hosted, plugins[name] === hosted else { return } // stale process after reload
                        handle(line, from: name, log: log)
                    },
                    onStatus: { [weak self, weak hosted] status in
                        guard let self, let hosted, plugins[name] === hosted else { return }
                        if case .restarting = status { hosted.restarts += 1 }
                        hosted.status = status
                        store.setStatus(status, for: name)
                        if status == .running, manifest.mode == .stream { // (re)started: send the current state, not only changes
                            for (kind, line) in initialEvents() where manifest.events.contains(kind) { hosted.process?.send(line) }
                        }
                    },
                )
                hosted.process = process
                process.start()
                return hosted
        }
    }

    private func handle(_ line: PluginLine, from name: String, log: PluginLog) {
        switch line {
            case .update(let patch, let ignored):
                store.apply(patch, to: name)
                for field in ignored { log.write("ignored field '\(field)': wrong type") }
            case .run(let command):
                runCommand(name, command)
            case .invalid(let reason):
                log.write("dropped line: \(reason)")
        }
    }
}

/// What a freshly started stream plugin needs to know right away (otherwise a workspace widget waits for the first switch)
@MainActor func currentStateEvents() -> [(PluginEventKind, String)] {
    let workspace = focus.workspace.name
    return [(.workspace, encodePluginEvent(.workspace, ["focused": workspace, "prev": workspace]))]
}
