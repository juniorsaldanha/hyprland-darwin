import AppKit
import Common

@MainActor private var pluginObservers: [Any] = []

/// Call once at startup: routes EventBus and system-wake events to plugins, then starts the placed plugins
@MainActor func startPlugins() {
    _ = addEventListener { event in
        if let (kind, line) = pluginEvent(for: event) { PluginHost.shared.send(kind, line) }
    }
    pluginObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification, object: nil, queue: .main,
    ) { _ in MainActor.assumeIsolated { PluginHost.shared.send(.wake, encodePluginEvent(.wake)) } })
    syncPlugins(config)
}

@MainActor func syncPlugins(_ config: Config) {
    if isUnitTest { return }
    PluginHost.shared.sync(names: config.placedPluginNames, userDirs: config.plugins.dirs, environment: config.execConfig.envVariables)
}

/// `{"run": "..."}` from a plugin: same rules as a keybinding (not run while tiling is disabled)
@MainActor func runPluginCommand(_ plugin: String, _ command: String) {
    let log = PluginLog.shared(name: plugin)
    guard let token: RunSessionGuard = .isServerEnabled else {
        log.write("run '\(command)' ignored: tiling is disabled")
        return
    }
    switch parseCommand(command, allowExecAndForget: true, allowEval: false) {
        case .cmd(let shell):
            Task.startUnstructured {
                _ = try? await runLightSession(.plugin(plugin), token) { await shell.run(.defaultEnv, .emptyStdin) }
            }
        case .failure(let error):
            log.write("run '\(command)' failed to parse: \(error.msg)")
        case .help:
            log.write("run '\(command)' printed help; nothing ran")
    }
}
