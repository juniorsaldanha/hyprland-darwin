@testable import AppBundle
import CoreGraphics
import XCTest

final class ModifierDragTest: XCTestCase {
    func testExactModifierMatches() {
        assertTrue(modifierDragMatches([.maskAlternate], .maskAlternate))
        assertTrue(modifierDragMatches([.maskCommand, .maskAlternate], [.maskCommand, .maskAlternate]))
    }

    func testExtraModifierDoesNotMatch() {
        assertFalse(modifierDragMatches([.maskAlternate, .maskShift], .maskAlternate))
    }

    func testNonModifierFlagsAreIgnored() {
        assertTrue(modifierDragMatches([.maskAlternate, .maskAlphaShift, .maskNonCoalesced], .maskAlternate))
    }

    func testEmptyRequiredNeverMatches() {
        assertFalse(modifierDragMatches([], []))
    }
}

@MainActor
final class ModifierDragTargetTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private let box = CGRect(x: 0, y: 0, width: 100, height: 100)
    private let inside = CGPoint(x: 50, y: 50)

    func testPassesThroughOverDesktop() {
        _ = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        let onScreen = [OnScreenWindow(id: 1, layer: 0, bounds: box)]
        assertNil(modifierDragTarget(flags: .maskAlternate, required: .maskAlternate, at: CGPoint(x: 500, y: 500), onScreen: onScreen))
    }

    func testPassesThroughOverMenuBarOrDockEvenAboveAWindow() {
        _ = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        let menuBarItem = OnScreenWindow(id: 50, layer: 25, bounds: box)
        let dock = OnScreenWindow(id: 51, layer: 20, bounds: box)
        let window = OnScreenWindow(id: 1, layer: 0, bounds: box)
        assertNil(modifierDragTarget(flags: .maskAlternate, required: .maskAlternate, at: inside, onScreen: [menuBarItem, window]))
        assertNil(modifierDragTarget(flags: .maskAlternate, required: .maskAlternate, at: inside, onScreen: [dock, window]))
    }

    func testPassesThroughOverUnmanagedWindow() {
        let popup = OnScreenWindow(id: 99, layer: 0, bounds: box)
        assertNil(modifierDragTarget(flags: .maskAlternate, required: .maskAlternate, at: inside, onScreen: [popup]))
    }

    func testPassesThroughWithExtraModifier() {
        _ = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        let onScreen = [OnScreenWindow(id: 1, layer: 0, bounds: box)]
        assertNil(modifierDragTarget(flags: [.maskAlternate, .maskShift], required: .maskAlternate, at: inside, onScreen: onScreen))
    }

    func testSkipsOurOwnBorderOverlays() {
        // A border overlay of a floating window overlaps the tiled window under it by `borders.width`
        _ = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        let borderOverlay = OnScreenWindow(id: 70, layer: 0, bounds: box, ownerPid: myPid)
        let window = OnScreenWindow(id: 1, layer: 0, bounds: box)
        let target = modifierDragTarget(flags: .maskAlternate, required: .maskAlternate, at: inside, onScreen: [borderOverlay, window])
        assertEquals(target?.window.windowId, 1)
    }

    func testTargetsTopmostManagedWindow() {
        _ = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        _ = TestWindow.new(id: 2, parent: focus.workspace.rootTilingContainer)
        let front = OnScreenWindow(id: 2, layer: 0, bounds: CGRect(x: 40, y: 40, width: 100, height: 100))
        let back = OnScreenWindow(id: 1, layer: 0, bounds: box)
        let target = modifierDragTarget(flags: .maskAlternate, required: .maskAlternate, at: inside, onScreen: [front, back])
        assertEquals(target?.window.windowId, 2)
        assertEquals(target?.frame, front.bounds)
    }

    func testModifierDragCountsAsManipulatedWithoutNativeFocus() async throws {
        let window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        modifierDragWindowId = 1
        defer { modifierDragWindowId = nil }
        assertTrue(try await isManipulatedWithMouse(window))
    }
}

final class MessageMergeTest: XCTestCase {
    /// The alt+drag warning arrives right after a config reload: it must not hide the config's own errors
    func testAWarningIsAddedToAnExistingMessage() {
        let config = Message(body: "[ERROR] gaps.inner: bad value", containsWarnings: false)
        let merged = adding(Message(description: "Mouse drag", body: "alt+drag is off", containsWarnings: true), to: config)
        assertTrue(merged.body.contains("[ERROR] gaps.inner: bad value"))
        assertTrue(merged.body.contains("alt+drag is off"))
        assertTrue(merged.containsWarnings)
        let alone = Message(description: "Mouse drag", body: "alt+drag is off", containsWarnings: true)
        assertEquals(adding(alone, to: nil), alone)
    }
}
