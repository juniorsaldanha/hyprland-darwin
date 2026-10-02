@testable import AppBundle
import AppKit
import XCTest

final class BarIconWidthTest: XCTestCase {
    /// Nerd Font icons draw wider than their advance width. The width the bar gives an icon must cover its whole
    /// drawing, or the label after it overlaps the icon.
    func testIconWidthCoversTheDrawnGlyph() {
        registerBundledFonts()
        let font = barIconNSFont(family: "Hack Nerd Font", size: 17)
        for icon in ["\u{F02CA}", "\u{E266}", "\u{F08AE}", "\u{F4BC}", "\u{F0200}", "\u{F0580}", "\u{F0084}", "\u{F43A}", "\u{F054}"] {
            let string = NSAttributedString(string: icon, attributes: [.font: font])
            let ink = string.boundingRect(with: .zero, options: [.usesDeviceMetrics, .usesLineFragmentOrigin])
            let width = barIconWidth(icon, font: font)
            XCTAssertGreaterThanOrEqual(width, ink.maxX - min(0, ink.minX), "icon U+\(String(icon.unicodeScalars.first!.value, radix: 16)) overflows")
            XCTAssertGreaterThanOrEqual(width, string.size().width)
        }
    }

    func testMissingFontFallsBackToSystemFont() {
        assertEquals(barIconNSFont(family: "No Such Font", size: 17).pointSize, 17)
    }
}
