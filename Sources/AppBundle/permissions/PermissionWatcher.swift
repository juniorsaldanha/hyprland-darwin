enum PermissionAction: Equatable {
    case none
    case pause(disableServer: Bool)
    case resume(enableServer: Bool)
}

/// Decides what to do when Accessibility trust changes while the app runs.
/// Fires once per revoke and once per re-grant. Only re-enables tiling if this watcher disabled it.
struct PermissionWatcher {
    private var isPaused = false
    private var didDisableServer = false

    mutating func update(isTrusted: Bool, isServerEnabled: Bool) -> PermissionAction {
        switch (isTrusted, isPaused) {
            case (false, false):
                isPaused = true
                didDisableServer = isServerEnabled
                return .pause(disableServer: isServerEnabled)
            case (true, true):
                isPaused = false
                return .resume(enableServer: didDisableServer)
            default:
                return .none
        }
    }
}
