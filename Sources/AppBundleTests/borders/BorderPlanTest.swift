@testable import AppBundle
import XCTest

final class BorderPlanTest: XCTestCase {
    private let enabled = BordersConfig(enabled: true)
    private func w(_ id: UInt32, layer: Int = 0, _ r: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)) -> OnScreenWindow {
        OnScreenWindow(id: id, layer: layer, bounds: r)
    }

    func testFocusedGetsActiveOthersInactive() {
        let plan = borderPlan(candidates: [1, 2], focusedId: 2, onScreen: [w(2), w(1)], config: enabled, isEnabled: true)
        assertEquals(plan.map(\.windowId), [2, 1])
        assertEquals(plan.map(\.style), [enabled.active, enabled.inactive])
    }

    func testFrameComesFromOnScreenList() {
        let real = CGRect(x: 10, y: 20, width: 793, height: 601) // e.g. a terminal snapped to its character grid
        let plan = borderPlan(candidates: [1], focusedId: nil, onScreen: [w(1, real)], config: enabled, isEnabled: true)
        assertEquals(plan.first?.frame, real)
    }

    func testNoBorderWhenMissingFromOnScreenList() {
        assertEquals(borderPlan(candidates: [1], focusedId: 1, onScreen: [], config: enabled, isEnabled: true), [])
    }

    func testNoBorderForNonCandidatesOrNonZeroLayer() {
        let plan = borderPlan(candidates: [1], focusedId: nil, onScreen: [w(9), w(1, layer: 3)], config: enabled, isEnabled: true)
        assertEquals(plan, [])
    }

    func testEmptyPlanWhenTilingDisabled() {
        assertEquals(borderPlan(candidates: [1], focusedId: 1, onScreen: [w(1)], config: enabled, isEnabled: false), [])
    }

    func testEmptyPlanWhenBordersDisabled() {
        assertEquals(borderPlan(candidates: [1], focusedId: 1, onScreen: [w(1)], config: BordersConfig(), isEnabled: true), [])
    }

    // Screen coordinates: top-left origin, y grows down, primary screen top = 0. AppKit: bottom-left origin.
    func testOverlayFrameOnPrimary() {
        let frame = overlayFrame(windowFrame: CGRect(x: 100, y: 100, width: 800, height: 600), width: 5, primaryScreenHeight: 1000)
        assertEquals(frame, NSRect(x: 95, y: 295, width: 810, height: 610))
    }

    func testOverlayFrameOnMonitorToTheRight() {
        let frame = overlayFrame(windowFrame: CGRect(x: 2100, y: 100, width: 800, height: 600), width: 5, primaryScreenHeight: 1000)
        assertEquals(frame, NSRect(x: 2095, y: 295, width: 810, height: 610))
    }

    func testOverlayFrameOnMonitorAbove() {
        let frame = overlayFrame(windowFrame: CGRect(x: 100, y: -900, width: 800, height: 600), width: 5, primaryScreenHeight: 1000)
        assertEquals(frame, NSRect(x: 95, y: 1295, width: 810, height: 610))
    }

    func testOverlayFrameOnMonitorBelow() {
        let frame = overlayFrame(windowFrame: CGRect(x: 100, y: 1100, width: 800, height: 600), width: 5, primaryScreenHeight: 1000)
        assertEquals(frame, NSRect(x: 95, y: -705, width: 810, height: 610))
    }

    func testRingRadii() {
        let r = ringRadii(size: CGSize(width: 810, height: 610), width: 5, radius: 10)
        assertEquals(r.outer, 15)
        assertEquals(r.inner, 10)
    }

    func testRadiiClampedForTinyWindow() {
        // overlay 30x30 = 20x20 window + 5 px ring; CGPath(roundedRect:) traps if radius > half the rect
        let r = ringRadii(size: CGSize(width: 30, height: 30), width: 5, radius: 100)
        assertEquals(r.outer, 15)
        assertEquals(r.inner, 10)
        _ = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 30, height: 30), cornerWidth: r.outer, cornerHeight: r.outer, transform: nil)
        _ = CGPath(roundedRect: CGRect(x: 5, y: 5, width: 20, height: 20), cornerWidth: r.inner, cornerHeight: r.inner, transform: nil)
    }

    func testNeedsRestack() {
        assertFalse(needsRestack(overlayId: 50, targetId: 1, order: [7, 1, 50, 2]))
        assertTrue(needsRestack(overlayId: 50, targetId: 1, order: [1, 9, 50]))
        assertTrue(needsRestack(overlayId: 50, targetId: 1, order: [50, 1]))
        assertTrue(needsRestack(overlayId: 50, targetId: 1, order: [1]))
        assertTrue(needsRestack(overlayId: 50, targetId: 1, order: [50]))
    }
}

@MainActor
final class BorderCandidatesTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testTilingAndFloatingOnVisibleWorkspace() {
        TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        TestWindow.new(id: 2, parent: focus.workspace.floatingWindowsContainer)
        assertEquals(Set(borderCandidates()), [1, 2])
    }

    func testExcludesInvisibleWorkspaceFullscreenAndMacosContainers() {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "hidden").rootTilingContainer)
        let fullscreen = TestWindow.new(id: 2, parent: focus.workspace.rootTilingContainer)
        fullscreen.isFullscreen = true
        // Global containers aren't reset by setUpWorkspacesForTests: unbind so they don't leak into other tests
        let minimized = TestWindow.new(id: 3, parent: macosMinimizedWindowsContainer)
        let popup = TestWindow.new(id: 4, parent: macosPopupWindowsContainer)
        defer {
            minimized.unbindFromParent()
            popup.unbindFromParent()
        }
        TestWindow.new(id: 5, parent: focus.workspace.rootTilingContainer)
        assertEquals(borderCandidates(), [5])
    }
}
