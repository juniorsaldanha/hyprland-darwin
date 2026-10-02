@testable import AppBundle
import AppKit
import SwiftUI
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

    /// The CPU chip draws 17 pt wide on a 10 pt advance: rendered, its ink must reach its right edge, not stop at the advance
    @MainActor func testRenderedIconIsNotClipped() {
        _ = NSApplication.shared
        registerBundledFonts()
        let config = BarConfig(enabled: true)
        let font = barIconNSFont(family: config.font, size: CGFloat(config.iconSize))
        for icon in ["\u{F4BC}", "\u{F43A}", "\u{E266}"] {
            let host = NSHostingView(rootView: BarIcon(icon: icon, config: config, color: .white).background(Color.black))
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let inked = (0 ..< rep.pixelsWide).filter { x in
                (0 ..< rep.pixelsHigh).contains { y in (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 0) > 0.5 }
            }
            let inkWidth = CGFloat((inked.last ?? 0) - (inked.first ?? 0) + 1) * host.bounds.width / CGFloat(rep.pixelsWide)
            XCTAssertGreaterThanOrEqual(inkWidth, barIconWidth(icon, font: font) - 3, "icon U+\(String(icon.unicodeScalars.first!.value, radix: 16)) is clipped")
        }
    }

    func testMissingFontFallsBackToSystemFont() {
        assertEquals(barIconNSFont(family: "No Such Font", size: 17).pointSize, 17)
    }
}
