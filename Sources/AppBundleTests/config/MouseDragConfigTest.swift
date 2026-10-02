@testable import AppBundle
import CoreGraphics
import XCTest

@MainActor
final class MouseDragConfigTest: XCTestCase {
    func testDisabledByDefault() {
        assertEquals(parseConfig("").config.mouseDrag, MouseDrag())
        assertFalse(MouseDrag().enabled)
    }

    func testAlt() {
        let result = parseConfig(
            """
            [mouse-drag]
                enabled = true
                modifier = 'alt'
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(result.config.mouseDrag, MouseDrag(enabled: true, modifier: .maskAlternate))
    }

    func testCombinedModifiers() {
        let result = parseConfig(
            """
            [mouse-drag]
                modifier = 'cmd-alt'
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(result.config.mouseDrag.modifier, [.maskCommand, .maskAlternate])
    }

    func testUnknownModifier() {
        let result = parseConfig(
            """
            [mouse-drag]
                modifier = 'hyper'
            """,
        )
        assertEquals(result.strErrors, [
            "[ERROR] mouse-drag.modifier: Unknown modifier 'hyper'. Possible values: alt, cmd, ctrl, shift (combine with '-', e.g. 'cmd-alt')",
        ])
    }

    func testEmptyModifier() {
        let result = parseConfig(
            """
            [mouse-drag]
                modifier = ''
            """,
        )
        assertEquals(result.strErrors, ["[ERROR] mouse-drag.modifier: Modifier must not be empty"])
    }

    func testEmptyPartsInModifierAreErrors() {
        for value in ["alt-", "-alt", "alt--cmd"] {
            assertEquals(parseConfig("mouse-drag.modifier = '\(value)'").strErrors, [
                "[ERROR] mouse-drag.modifier: Invalid modifier '\(value)'. Possible values: alt, cmd, ctrl, shift (combine with '-', e.g. 'cmd-alt')",
            ])
        }
    }
}
