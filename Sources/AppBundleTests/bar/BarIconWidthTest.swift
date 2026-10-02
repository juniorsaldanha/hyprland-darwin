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

    /// Icon and label must sit on the same vertical centre (the icon's ink against the digits' ink), within 1 pt
    @MainActor func testIconIsVerticallyCentredOnTheLabel() {
        _ = NSApplication.shared
        registerBundledFonts()
        let config = BarConfig(enabled: true)
        let font = barIconNSFont(family: config.font, size: CGFloat(config.iconSize))
        for icon in ["\u{F4BC}", "\u{E266}", "\u{F43A}", "\u{F0200}", "\u{F02CA}"] {
            let item = BarItem.plugin(name: "w", state: WidgetState(icon: icon, label: "42%"))
            let host = NSHostingView(rootView: BarItemView(item: item, config: config).frame(height: CGFloat(config.height)).background(Color.black))
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width
            let split = Int((5 + 8 + barIconWidth(icon, font: font) + 2) * scale) // label starts after the icon's trailing padding
            func inkCentre(_ xs: Range<Int>) -> CGFloat {
                let rows = (0 ..< rep.pixelsHigh).filter { y in xs.contains { x in (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 0) > 0.5 } }
                return CGFloat((rows.first ?? 0) + (rows.last ?? 0)) / 2 / scale
            }
            let iconCentre = inkCentre(0 ..< split)
            let labelCentre = inkCentre(split ..< rep.pixelsWide)
            XCTAssertEqual(iconCentre, labelCentre, accuracy: 1, "icon U+\(String(icon.unicodeScalars.first!.value, radix: 16)) is off-centre")
        }
    }

    func testMissingFontFallsBackToSystemFont() {
        assertEquals(barIconNSFont(family: "No Such Font", size: 17).pointSize, 17)
    }
}
