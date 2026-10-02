import AppKit
import Combine
import Common

@MainActor private let overlays = BorderOverlays()
@MainActor private let coalescer = SyncCoalescer(action: syncBorders)
@MainActor private var observers: [Any] = []

/// No Accessibility calls: AeroSpace's model + one window-list snapshot.
@MainActor func syncBorders() {
    let borders = config.borders
    guard borders.enabled, TrayMenuModel.shared.isEnabled else {
        // Off (the shipped default) or paused: no window-list snapshot on every move notification
        overlays.apply([], width: 0, radius: 0, primaryScreenHeight: 0)
        return
    }
    let onScreen = onScreenWindows()
    let plan = borderPlan(
        candidates: borderCandidates(),
        focusedId: focus.windowOrNil?.windowId,
        onScreen: onScreen,
        config: borders,
        isEnabled: TrayMenuModel.shared.isEnabled,
    )
    overlays.apply(plan, width: CGFloat(borders.width), radius: CGFloat(borders.radius), primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0)
    overlays.restack(order: onScreen.map(\.id))
}

@MainActor func requestBordersSync() {
    if isUnitTest { return } // Tests use TestWindows whose ids could collide with real on-screen windows
    coalescer.request()
}

/// Call once at startup: screen changes and enable/disable also need a sync.
@MainActor func startBorders() {
    observers.append(NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main,
    ) { _ in MainActor.assumeIsolated { requestBordersSync() } })
    observers.append(TrayMenuModel.shared.$isEnabled.sink { _ in MainActor.assumeIsolated { requestBordersSync() } })
    // .transient overlays follow you to a new Space: drop the old Space's rings at once, without waiting for the AX refresh
    observers.append(NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main,
    ) { _ in MainActor.assumeIsolated { requestBordersSync() } })
    requestBordersSync()
}
