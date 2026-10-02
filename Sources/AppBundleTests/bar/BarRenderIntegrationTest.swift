@testable import AppBundle
import AppKit
import SwiftUI
import XCTest

@MainActor
final class BarRenderIntegrationTest: XCTestCase {
    private func ws(_ name: String, focused: Bool = false) -> WorkspaceViewModel {
        WorkspaceViewModel(name: name, suffix: "", isFocused: focused, isEffectivelyEmpty: !focused, isVisible: focused, hasFullscreenWindows: false)
    }

    private func snapshot(_ view: NSView) -> Data {
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])!
    }

    /// Switching to a non-persistent workspace publishes a new list: a running bar must redraw with the new pill
    func testRunningBarRedrawsWhenTheWorkspaceListChanges() {
        _ = NSApplication.shared
        let tray = TrayMenuModel.shared
        let saved = tray.workspaces
        defer { tray.workspaces = saved }
        tray.workspaces = [ws("1"), ws("2", focused: true)]
        let view = BarHostingView(rootView: BarView(tray: tray, store: WidgetStore(), model: BarModel.shared, config: BarConfig(enabled: true, left: ["workspaces"])))
        view.frame = CGRect(x: 0, y: 0, width: 600, height: 40)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        let before = snapshot(view)

        tray.workspaces = [ws("1"), ws("2"), ws("7", focused: true)]
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let after = snapshot(view)
        assertNotEquals(before, after)

        tray.workspaces = [ws("1"), ws("2", focused: true)]
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        assertEquals(snapshot(view), before) // back to the same pills: same picture
    }
}
