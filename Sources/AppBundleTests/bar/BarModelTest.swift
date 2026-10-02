@testable import AppBundle
import XCTest

final class BarModelTest: XCTestCase {
    private func ws(_ name: String, focused: Bool = false) -> WorkspaceViewModel {
        WorkspaceViewModel(name: name, suffix: "", isFocused: focused, isEffectivelyEmpty: false, isVisible: focused, hasFullscreenWindows: false)
    }

    func testOrderAndBuiltins() {
        let items = barItems(
            names: ["workspaces", "chevron", "front-app", "clock"],
            workspaces: [ws("1"), ws("2", focused: true)],
            frontApp: "Arc",
            widgets: ["clock": WidgetState(icon: "C", label: "10:00")],
            statuses: ["clock": .running],
        )
        assertEquals(items, [
            .workspace(name: "1", isFocused: false), .workspace(name: "2", isFocused: true),
            .chevron, .frontApp("Arc"), .plugin(name: "clock", state: WidgetState(icon: "C", label: "10:00")),
        ])
        assertEquals(items.map(\.id), ["workspace:1", "workspace:2", "chevron", "front-app", "plugin:clock"])
    }

    /// One pill per monitor, left → right, separated; the focused monitor's pill is highlighted (`1 | 2*`)
    func testVisibleModeShowsOneWorkspacePerMonitor() {
        let monitors = [
            TrayItem(type: .mode, name: "SERVICE", isActive: true, hasFullscreenWindows: false),
            TrayItem(type: .workspace, name: "1", isActive: false, hasFullscreenWindows: false),
            TrayItem(type: .workspace, name: "6", isActive: true, hasFullscreenWindows: false),
        ]
        let items = barItems(
            names: ["workspaces", "chevron"],
            workspaces: [ws("1"), ws("2"), ws("6", focused: true)],
            monitors: monitors,
            workspacesMode: .visible,
            frontApp: nil,
            widgets: [:],
            statuses: [:],
        )
        assertEquals(items, [.workspace(name: "1", isFocused: false), .separator(1), .workspace(name: "6", isFocused: true), .chevron])
        assertEquals(Set(items.map(\.id)).count, items.count)
    }

    func testHiddenOrEmptyWidgetsAndMissingFrontAppTakeNoSpace() {
        let items = barItems(
            names: ["front-app", "a", "b", "c"],
            workspaces: [],
            frontApp: nil,
            widgets: ["a": WidgetState(label: "x", hidden: true), "b": WidgetState()],
            statuses: ["a": .running, "b": .running, "c": .starting],
        )
        assertEquals(items, [])
    }

    func testProblemsShowWarning() {
        let items = barItems(
            names: ["gone", "bad", "dead"],
            workspaces: [],
            frontApp: nil,
            widgets: ["dead": WidgetState(label: "old")],
            statuses: ["gone": .missing("no plugin folder in /p"), "bad": .invalid("missing 'api'"), "dead": .stopped("crashed 5 times within 60 s")],
        )
        assertEquals(items, [
            .problem(name: "gone", reason: "missing: no plugin folder in /p"),
            .problem(name: "bad", reason: "invalid: missing 'api'"),
            .problem(name: "dead", reason: "stopped: crashed 5 times within 60 s"),
        ])
    }

    func testAutoHideHysteresis() {
        var state = AutoHideState()
        assertFalse(state.update(distanceFromTop: 100))
        assertTrue(state.update(distanceFromTop: 8)) // hide at <= 8
        assertTrue(state.isHidden)
        assertFalse(state.update(distanceFromTop: 20)) // between 8 and 24: stays hidden, no flicker
        assertFalse(state.update(distanceFromTop: 24))
        assertTrue(state.update(distanceFromTop: 25)) // show beyond 24
        assertFalse(state.isHidden)
        assertFalse(state.update(distanceFromTop: 9))
    }

    func testNotchRect() {
        let left = CGRect(x: 0, y: 1085, width: 660, height: 32)
        let right = CGRect(x: 852, y: 1085, width: 660, height: 32)
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 1117)
        assertEquals(notchRect(screenFrame: screen, auxLeft: left, auxRight: right), CGRect(x: 660, y: 1085, width: 192, height: 32))
        assertNil(notchRect(screenFrame: screen, auxLeft: nil, auxRight: right))
    }

    func testBarFrameAtTopOfScreen() {
        assertEquals(barFrame(screenFrame: CGRect(x: 1512, y: -200, width: 2560, height: 1440), height: 40), CGRect(x: 1512, y: 1200, width: 2560, height: 40))
    }

    func testColors() {
        let c = nsColor(argb: 0x8041_4868).usingColorSpace(.sRGB)!
        XCTAssertEqual(c.alphaComponent, 0x80 / 255, accuracy: 0.001)
        XCTAssertEqual(c.redComponent, 0x41 / 255, accuracy: 0.001)
        assertEquals(widgetColor("nope", fallback: 0xFF00_0000), nsColor(argb: 0xFF00_0000))
        assertEquals(widgetColor(nil, fallback: 0xFF00_0000), nsColor(argb: 0xFF00_0000))
        assertEquals(widgetColor("0xff00ff00", fallback: 0xFF00_0000), nsColor(argb: 0xFF00_FF00))
    }

    func testTopEdgePixelBelongsToTheScreen() {
        // NSEvent.mouseLocation.y == frame.maxY at the very top: CGRect.contains excludes it
        let frames = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: -200, width: 2560, height: 1440)]
        assertEquals(screenIndex(containing: CGPoint(x: 100, y: 982), frames: frames), 0)
        assertEquals(screenIndex(containing: CGPoint(x: 2000, y: 1240), frames: frames), 1)
        assertEquals(screenIndex(containing: CGPoint(x: 100, y: 0), frames: frames), nil) // bottom edge belongs to the screen below
        assertEquals(screenIndex(containing: CGPoint(x: 9000, y: 10), frames: frames), nil)
    }

    func testFailingOrRestartingWithoutStateShowsWarning() {
        let items = barItems(
            names: ["broken", "flaky", "loop"],
            workspaces: [], frontApp: nil,
            widgets: ["flaky": WidgetState(label: "last")],
            statuses: ["broken": .failing(3), "flaky": .failing(3), "loop": .restarting(in: 2)],
        )
        assertEquals(items, [
            .problem(name: "broken", reason: "failing (3)"),
            .plugin(name: "flaky", state: WidgetState(label: "last")), // keeps its last good value
            .problem(name: "loop", reason: "restarting in 2s"),
        ])
    }

    func testNotchRectOnAnOffsetBuiltInScreen() {
        // built-in display left of / below the main one: frame is offset; aux rects only contribute sizes
        let screen = CGRect(x: -1512, y: -300, width: 1512, height: 982)
        let left = CGRect(x: 0, y: 950, width: 660, height: 32)
        let right = CGRect(x: 852, y: 950, width: 660, height: 32)
        assertEquals(notchRect(screenFrame: screen, auxLeft: left, auxRight: right), CGRect(x: -852, y: 650, width: 192, height: 32))
    }
}
