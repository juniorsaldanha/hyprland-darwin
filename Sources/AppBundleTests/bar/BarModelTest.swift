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
        assertEquals(notchRect(auxLeft: left, auxRight: right), CGRect(x: 660, y: 1085, width: 192, height: 32))
        assertNil(notchRect(auxLeft: nil, auxRight: right))
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
}
