import AppKit
import Common
import UserNotifications

private let permissionsWindowShownKey = "permissionsWindowShownOnce"

/// First launch, or any launch with Accessibility missing.
@MainActor func showPermissionsWindowIfNeeded() {
    let isFirstLaunch = !UserDefaults.standard.bool(forKey: permissionsWindowShownKey)
    if isFirstLaunch || !AXIsProcessTrusted() {
        UserDefaults.standard.set(true, forKey: permissionsWindowShownKey)
        showPermissionsWindow()
    }
}

@MainActor private var watcher = PermissionWatcher()

/// Detects Accessibility being revoked or re-granted while running.
@MainActor func startPermissionMonitor() {
    Task.startUnstructured { @MainActor in
        while true {
            try? await Task.sleep(for: .seconds(2))
            let action = watcher.update(isTrusted: AXIsProcessTrusted(), isServerEnabled: TrayMenuModel.shared.isEnabled)
            await apply(action)
        }
    }
}

@MainActor private func apply(_ action: PermissionAction) async {
    switch action {
        case .none:
            return
        case .pause(let disableServer):
            TrayMenuModel.shared.axPermissionStatus = .waiting
            if disableServer {
                // No refresh session: Accessibility calls would fail. Windows stay where they are.
                _ = await EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .off)).run(.defaultEnv, .emptyStdin)
            }
            postPermissionMissingNotification()
        case .resume(let enableServer):
            TrayMenuModel.shared.axPermissionStatus = .granted
            if enableServer {
                try? await runLightSession(.permissionMonitor, .forceRun) {
                    _ = await EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .on)).run(.defaultEnv, .emptyStdin)
                }
            }
    }
}

private func postPermissionMissingNotification() {
    guard isAppBundle else { return }
    let content = UNMutableNotificationContent()
    content.title = "Accessibility permission needed"
    content.body = "\(aeroSpaceAppName) paused tiling. Click to fix."
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "permission-missing", content: content, trigger: nil))
}

private final class NotificationClickHandler: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationClickHandler()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { showPermissionsWindow() }
    }

    // Show the banner even while our app counts as active
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@MainActor func installNotificationClickHandler() {
    guard isAppBundle else { return }
    UNUserNotificationCenter.current().delegate = NotificationClickHandler.shared
}
