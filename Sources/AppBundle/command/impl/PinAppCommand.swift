import AppKit
import Common

/// Toggles "this app always opens in this workspace" for the window's app
struct PinAppCommand: Command {
    let args: PinAppCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        guard let appId = pinKey(window.app) else { return .fail(io.err("The app has neither a bundle id nor a name, it can't be pinned")) }
        guard let workspace = window.nodeWorkspace else { return .fail(io.err("Window \(window.windowId) doesn't belong to any workspace")) }
        let name = window.app.name ?? appId
        var pins = pinnedApps
        if pins[appId] == workspace.name {
            pins[appId] = nil
            pinnedApps = pins
            return .succ(io.out(toast("Unpinned \(name) from workspace \(workspace.name)", "pin.slash.fill", workspace)))
        }
        pins[appId] = workspace.name
        pinnedApps = pins
        return .succ(io.out(toast("Pinned \(name) to workspace \(workspace.name)", "pin.fill", workspace)))
    }
}

/// Shows the message as a toast on the workspace's monitor (not in unit tests) and returns it
@MainActor private func toast(_ text: String, _ systemImage: String, _ workspace: Workspace) -> String {
    if !isUnitTest { ToastPanel.shared.show(text, systemImage: systemImage, on: workspace.workspaceMonitor) }
    return text
}

/// What a pin is keyed by: the bundle id, or the process name for a bare binary without one
/// (an app run from its build folder, e.g. `cargo tauri dev`)
@MainActor func pinKey(_ app: any AbstractApp) -> String? {
    app.rawAppBundleId ?? app.name?.takeIf { !$0.isEmpty }
}

/// pinKey → workspace name. Kept in UserDefaults so pins survive restarts without touching the user's config
@MainActor var pinnedApps: [String: String] {
    get { UserDefaults.standard.dictionary(forKey: "pinnedApps") as? [String: String] ?? [:] }
    set { UserDefaults.standard.set(newValue, forKey: "pinnedApps") }
}

/// Moves a newly detected window to its app's pinned workspace. Focus follows, except during startup
@MainActor func applyPinnedWorkspace(_ window: Window, _ io: CmdIo) {
    guard let appId = pinKey(window.app), let name = pinnedApps[appId], window.nodeWorkspace?.name != name else { return }
    _ = moveWindowToWorkspace(window, Workspace.get(byName: name), io, focusFollowsWindow: !isStartup, failIfNoop: false)
}

/// Menu title for pinning the focused window's app, nil when there's nothing to pin
@MainActor func pinFocusedAppMenuTitle() -> String? {
    guard let window = focus.windowOrNil, let appId = pinKey(window.app), let ws = window.nodeWorkspace else { return nil }
    let name = window.app.name ?? appId
    return pinnedApps[appId] == ws.name ? "Unpin \(name) from workspace \(ws.name)" : "Pin \(name) to workspace \(ws.name)"
}

@MainActor func unpinAppFromUi(_ appId: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task.startUnstructured {
        try await runLightSession(.menuBarButton, token) { pinnedApps[appId] = nil }
    }
}

/// "Safari" for com.apple.Safari, the bundle id itself when the app isn't installed
func appDisplayName(_ appId: String) -> String {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: appId)
        .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? appId
}

@MainActor func togglePinFocusedAppFromUi() {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task.startUnstructured {
        try await runLightSession(.menuBarButton, token) {
            _ = await PinAppCommand(args: PinAppCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)
        }
    }
}
