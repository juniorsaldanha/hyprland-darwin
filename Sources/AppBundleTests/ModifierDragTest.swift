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
