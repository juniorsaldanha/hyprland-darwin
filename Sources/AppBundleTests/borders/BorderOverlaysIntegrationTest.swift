@testable import AppBundle
import AppKit
import XCTest

/// Real windows in the test process. Needs a window server session (local machine or GitHub macOS runner).
@MainActor
final class BorderOverlaysIntegrationTest: XCTestCase {
    private var windows: [NSWindow] = []
    private let overlays = BorderOverlays()
    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    override func setUp() async throws {
        try XCTSkipUnless(NSScreen.screens.first != nil, "needs a window server session")
        _ = NSApplication.shared
    }

    override func tearDown() async throws {
        overlays.apply([], width: 5, radius: 10, primaryScreenHeight: primaryHeight)
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    private func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        windows.append(window)
        return window
    }

    private func spec(_ window: NSWindow) -> BorderSpec {
        let f = window.frame // AppKit -> screen coordinates
        let frame = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
        return BorderSpec(windowId: UInt32(window.windowNumber), frame: frame, style: .solid(0xFF00_FF00))
    }

    private func order() -> [UInt32] { onScreenWindows().map(\.id) }

    func testOverlayGoesDirectlyBehindTargetAndRecoversAfterRaise() {
        let target = makeWindow()
        let other = makeWindow() // created later, so in front of target
        pump()
        let targetId = UInt32(target.windowNumber)

        overlays.apply([spec(target)], width: 5, radius: 10, primaryScreenHeight: primaryHeight)
        overlays.restack(order: order())
        pump()
        let overlayId = overlays.overlayWindowId(for: targetId)!
        assertFalse(needsRestack(overlayId: overlayId, targetId: targetId, order: order()))

        other.orderFrontRegardless()
        target.orderFrontRegardless() // target raised; overlay left behind `other`
        pump()
        assertTrue(needsRestack(overlayId: overlayId, targetId: targetId, order: order()))

        overlays.restack(order: order())
        pump()
        assertFalse(needsRestack(overlayId: overlayId, targetId: targetId, order: order()))
    }

    func testApplyCreatesMovesAndRemovesOverlays() {
        let a = BorderSpec(windowId: 900_001, frame: CGRect(x: 0, y: 0, width: 300, height: 200), style: .solid(0xFF00_00FF))
        let b = BorderSpec(windowId: 900_002, frame: CGRect(x: 320, y: 0, width: 300, height: 200), style: .solid(0xFF00_00FF))
        let c = BorderSpec(windowId: 900_003, frame: CGRect(x: 640, y: 0, width: 300, height: 200), style: .solid(0xFF00_00FF))
        overlays.apply([a, b, c], width: 5, radius: 10, primaryScreenHeight: 1000)
        assertEquals(overlays.count, 3)

        let movedB = BorderSpec(windowId: 900_002, frame: CGRect(x: 400, y: 50, width: 300, height: 200), style: .gradient(0xFF7A_A2F7, 0xFFBB_9AF7))
        overlays.apply([a, movedB], width: 5, radius: 10, primaryScreenHeight: 1000)
        assertEquals(overlays.count, 2)
        assertNil(overlays.frame(for: 900_003))
        assertEquals(overlays.frame(for: 900_002), overlayFrame(windowFrame: movedB.frame, width: 5, primaryScreenHeight: 1000))

        overlays.apply([], width: 5, radius: 10, primaryScreenHeight: 1000) // tiling disabled -> nothing left on screen
        assertEquals(overlays.count, 0)
    }

    func testRestackAgainstClosedWindowDoesNotCrash() {
        let target = makeWindow()
        pump()
        overlays.apply([spec(target)], width: 5, radius: 10, primaryScreenHeight: primaryHeight)
        let staleOrder = order()
        target.orderOut(nil)
        target.close()
        pump()
        overlays.restack(order: staleOrder) // snapshot still lists the closed window
        overlays.restack(order: order()) // target gone: skipped
        overlays.apply([], width: 5, radius: 10, primaryScreenHeight: primaryHeight)
        assertEquals(overlays.count, 0)
    }

    func testCgColorComponents() {
        let color = cgColor(argb: 0x8041_4868)
        let c = color.components ?? []
        assertEquals(c.count, 4)
        XCTAssertEqual(c[0], 0x41 / 255, accuracy: 0.001)
        XCTAssertEqual(c[1], 0x48 / 255, accuracy: 0.001)
        XCTAssertEqual(c[2], 0x68 / 255, accuracy: 0.001)
        XCTAssertEqual(c[3], 0x80 / 255, accuracy: 0.001)
    }

    func testUnchangedOverlaysAreNotRedrawn() {
        let a = BorderSpec(windowId: 900_101, frame: CGRect(x: 0, y: 0, width: 300, height: 200), style: .solid(0xFF00_00FF))
        let b = BorderSpec(windowId: 900_102, frame: CGRect(x: 320, y: 0, width: 300, height: 200), style: .solid(0xFF00_00FF))
        overlays.apply([a, b], width: 5, radius: 10, primaryScreenHeight: 1000)
        assertEquals(overlays.redrawCount, 2)
        overlays.apply([a, b], width: 5, radius: 10, primaryScreenHeight: 1000) // e.g. another window being dragged
        assertEquals(overlays.redrawCount, 2)
        let movedB = BorderSpec(windowId: 900_102, frame: CGRect(x: 330, y: 0, width: 300, height: 200), style: .solid(0xFF00_00FF))
        overlays.apply([a, movedB], width: 5, radius: 10, primaryScreenHeight: 1000)
        assertEquals(overlays.redrawCount, 3)
        overlays.apply([a, movedB], width: 6, radius: 10, primaryScreenHeight: 1000) // config change redraws all
        assertEquals(overlays.redrawCount, 5)
    }

    func testRestackAgainstAClosedWindowLeavesNoRingOnTop() {
        let target = makeWindow()
        pump()
        overlays.apply([spec(target)], width: 5, radius: 10, primaryScreenHeight: primaryHeight)
        let staleOrder = order()
        let id = UInt32(target.windowNumber)
        target.orderOut(nil)
        target.close()
        pump()
        overlays.restack(order: staleOrder) // snapshot still lists the closed window
        pump()
        let overlayId = overlays.overlayWindowId(for: id)!
        assertFalse(order().contains(overlayId)) // not ordered in front of everything with nothing to sit behind
    }
}
