@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class BarPanelIntegrationTest: XCTestCase {
    override func setUp() async throws {
        try XCTSkipUnless(!NSScreen.screens.isEmpty, "needs a window server session")
        _ = NSApplication.shared
    }

    override func tearDown() async throws {
        BarController.shared.sync(BarConfig(), notch: NotchConfig()) // disabled → no panels
    }

    func testOneBarPerScreenAndResyncReplacesPanels() {
        let config = BarConfig(enabled: true, height: 32, left: ["chevron"])
        BarController.shared.sync(config, notch: NotchConfig())
        assertEquals(BarController.shared.panelFrames, NSScreen.screens.map { barFrame(screenFrame: $0.frame, height: 32) })
        assertTrue(BarController.shared.panelLevels.allSatisfy { $0 == .statusBar })

        BarController.shared.sync(config, notch: NotchConfig()) // e.g. after a screen change: replaced, not added
        assertEquals(BarController.shared.panelFrames.count, NSScreen.screens.count)

        BarController.shared.sync(BarConfig(), notch: NotchConfig())
        assertEquals(BarController.shared.panelFrames, [])
    }

    func testScreenChangeKeepsTheBarHidden() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let config = BarConfig(enabled: true, autoHide: true, left: ["chevron"])
        BarController.shared.sync(config, notch: NotchConfig())
        BarController.shared.mouseMoved(CGPoint(x: screen.frame.midX, y: screen.frame.maxY)) // cursor at the top: hide
        assertTrue(BarController.shared.panelAlphas.allSatisfy { $0 == 0 })
        BarController.shared.sync(config, notch: NotchConfig()) // e.g. a display was plugged in
        assertTrue(BarController.shared.panelAlphas.allSatisfy { $0 == 0 }) // still hidden: the cursor hasn't moved
        BarController.shared.mouseMoved(CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        assertTrue(BarController.shared.panelAlphas.allSatisfy { $0 == 1 })
    }
}
