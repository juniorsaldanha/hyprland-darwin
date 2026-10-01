import AppKit
import UserNotifications

enum PermissionKind: CaseIterable {
    case accessibility, notifications

    var title: String {
        switch self {
            case .accessibility: "Accessibility"
            case .notifications: "Notifications"
        }
    }

    var reason: String {
        switch self {
            case .accessibility: "Read, move and resize windows. Needed for tiling and borders."
            case .notifications: "Tell you when a permission goes missing."
        }
    }

    var isRequired: Bool { self == .accessibility }

    var settingsUrl: URL {
        switch self {
            case .accessibility: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility").orDie()
            case .notifications: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension").orDie()
        }
    }
}

@MainActor
final class PermissionsModel: ObservableObject {
    static let shared = PermissionsModel()

    @Published var accessibility: Bool = false
    @Published var notifications: Bool = false

    func isGranted(_ kind: PermissionKind) -> Bool {
        switch kind {
            case .accessibility: accessibility
            case .notifications: notifications
        }
    }

    var allRequiredGranted: Bool {
        PermissionKind.allCases.allSatisfy { !$0.isRequired || isGranted($0) }
    }

    func refresh() async {
        accessibility = AXIsProcessTrusted()
        notifications = await notificationsAuthorized()
    }

    /// "Open Settings" button: notifications are requested in place first; anything else opens System Settings.
    func fix(_ kind: PermissionKind) async {
        if kind == .notifications {
            await requestNotificationsPermission()
            await refresh()
            if notifications { return }
        }
        NSWorkspace.shared.open(kind.settingsUrl)
    }
}

/// UNUserNotificationCenter crashes outside an .app bundle (e.g. `swift run`, unit tests)
var isAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

func notificationsAuthorized() async -> Bool {
    guard isAppBundle else { return false }
    return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
}

func requestNotificationsPermission() async {
    guard isAppBundle else { return }
    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
}
