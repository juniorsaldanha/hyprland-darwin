import AppKit

/// Screen coordinates (top-left origin, y down) -> AppKit window frame (bottom-left origin), grown by `width` on every side.
/// The flip always uses the primary screen (the one at origin 0,0), on every monitor.
func overlayFrame(windowFrame: CGRect, width: CGFloat, primaryScreenHeight: CGFloat) -> NSRect {
    let r = windowFrame.insetBy(dx: -width, dy: -width)
    return NSRect(x: r.minX, y: primaryScreenHeight - r.maxY, width: r.width, height: r.height)
}

/// Corner radii of the ring around a window. Clamped so CGPath(roundedRect:) never gets a radius above half the rect.
func ringRadii(size: CGSize, width: CGFloat, radius: CGFloat) -> (outer: CGFloat, inner: CGFloat) {
    let maxOuter = min(size.width, size.height) / 2
    let outer = min(radius + width, maxOuter)
    let inner = min(radius, max(0, maxOuter - width))
    return (outer, inner)
}

/// True unless the overlay sits directly behind its target in the front-to-back window order.
func needsRestack(overlayId: UInt32, targetId: UInt32, order: [UInt32]) -> Bool {
    guard let target = order.firstIndex(of: targetId), let overlay = order.firstIndex(of: overlayId) else { return true }
    return overlay != target + 1
}
