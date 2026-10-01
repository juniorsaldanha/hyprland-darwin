import AppKit
import Combine
import Common

@MainActor private let overlays = BorderOverlays()
@MainActor private let coalescer = SyncCoalescer(action: syncBorders)
@MainActor private var observers: [Any] = []

/// No Accessibility calls: AeroSpace's model + one window-list snapshot.
@MainActor func syncBorders() {
    let borders = config.borders
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
    requestBordersSync()
}
