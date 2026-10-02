import AppKit
import Common
import SwiftUI

/// Borderless, non-activating, above windows, on every Space, never key
final class BarPanel: NSPanel {
    init(frame: CGRect, tint: UInt32, blur: Bool, content: NSView) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true // before `level`: setting it resets the level to .floating
        level = .statusBar
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        animationBehavior = .none

        let root = NSView(frame: CGRect(origin: .zero, size: frame.size))
        root.autoresizingMask = [.width, .height]
        if blur {
            let effect = NSVisualEffectView(frame: root.bounds)
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.autoresizingMask = [.width, .height]
            root.addSubview(effect)
        }
        let tintView = NSView(frame: root.bounds)
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = nsColor(argb: tint).cgColor
        tintView.autoresizingMask = [.width, .height]
        root.addSubview(tintView)
        content.frame = root.bounds
        content.autoresizingMask = [.width, .height]
        root.addSubview(content)
        contentView = root
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class BarController {
    static let shared = BarController()

    private var panels: [BarPanel] = []
    private var notchPanels: [(panel: BarPanel, notch: CGRect)] = []
    private var autoHide = AutoHideState()
    private var autoHideEnabled = false
    private var mouseMonitors: [Any] = []

    var panelFrames: [CGRect] { panels.map(\.frame) }
    var panelLevels: [NSWindow.Level] { panels.map(\.level) }

    /// Recreates every panel: one bar per current screen, plus notch panels. Disabled → none.
    func sync(_ config: BarConfig, notch: NotchConfig) {
        (panels + notchPanels.map(\.panel)).forEach { $0.orderOut(nil) }
        panels = []
        notchPanels = []
        autoHide = AutoHideState()
        autoHideEnabled = config.enabled && config.autoHide
        guard config.enabled else { return }
        for screen in NSScreen.screens {
            let view = NSHostingView(rootView: BarView(tray: TrayMenuModel.shared, store: PluginHost.shared.store, model: BarModel.shared, config: config))
            let panel = BarPanel(frame: barFrame(screenFrame: screen.frame, height: CGFloat(config.height)), tint: config.color, blur: config.blur, content: view)
            panel.orderFrontRegardless()
            panels.append(panel)

            guard !notch.items.isEmpty, let rect = notchRect(auxLeft: screen.auxiliaryTopLeftArea, auxRight: screen.auxiliaryTopRightArea) else { continue }
            let frame = CGRect(x: rect.minX - 40, y: screen.frame.maxY - rect.height - 32, width: rect.width + 80, height: rect.height + 32)
            let notchView = NSHostingView(rootView: NotchView(store: PluginHost.shared.store, names: notch.items, config: config))
            let notchPanel = BarPanel(frame: frame, tint: 0, blur: false, content: notchView)
            notchPanel.level = .statusBar + 1
            notchPanels.append((notchPanel, rect))
        }
        installMouseMonitors()
    }

    private func installMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        let handler: @MainActor () -> Void = { [weak self] in self?.mouseMoved(NSEvent.mouseLocation) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { _ in MainActor.assumeIsolated { handler() } }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in
            MainActor.assumeIsolated { handler() }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func mouseMoved(_ location: CGPoint) {
        if autoHideEnabled, let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) {
            if autoHide.update(distanceFromTop: screen.frame.maxY - location.y) {
                for panel in panels {
                    panel.alphaValue = autoHide.isHidden ? 0 : 1
                    panel.ignoresMouseEvents = autoHide.isHidden
                }
            }
        }
        for (panel, notch) in notchPanels {
            let hovering = notch.insetBy(dx: -4, dy: -4).contains(location) || (panel.isVisible && panel.frame.contains(location))
            if hovering && !panel.isVisible { panel.orderFrontRegardless() }
            if !hovering && panel.isVisible { panel.orderOut(nil) }
        }
    }
}

@MainActor private var barObservers: [Any] = []

/// Call once at startup (after startPlugins)
@MainActor func startBar() {
    barObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main,
    ) { note in
        let name = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName
        MainActor.assumeIsolated { BarModel.shared.frontApp = name }
    })
    barObservers.append(NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main,
    ) { _ in MainActor.assumeIsolated { syncBar(config) } })
    startSystemEvents()
    syncBar(config)
}

@MainActor func syncBar(_ config: Config) {
    if isUnitTest { return }
    BarController.shared.sync(config.bar, notch: config.notch)
}
