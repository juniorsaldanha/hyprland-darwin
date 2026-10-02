@testable import AppBundle
import AppKit
import XCTest

final class FontRegistrationIntegrationTest: XCTestCase {
    func testBundledFontsRegisterAndResolve() {
        let fonts = bundledFontURLs()
        assertEquals(fonts.map(\.lastPathComponent).sorted(), ["HackNerdFont-Bold.ttf", "HackNerdFont-Regular.ttf"])
        assertTrue(registerBundledFonts()) // "already registered" counts as success
        assertNotNil(NSFont(name: "HackNF-Bold", size: 14)) // PostScript name
        assertNotNil(NSFontManager.shared.availableMembers(ofFontFamily: "Hack Nerd Font")) // the name the bar uses
    }
}
