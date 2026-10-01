import AppKit
import QuartzCore

/// One click-through overlay NSWindow per bordered window, keyed by the target's window id.
@MainActor final class BorderOverlays {
    private var overlays: [UInt32: NSWindow] = [:]

    var count: Int { overlays.count }
    func overlayWindowId(for windowId: UInt32) -> UInt32? { overlays[windowId].map { UInt32($0.windowNumber) } }
    func frame(for windowId: UInt32) -> NSRect? { overlays[windowId]?.frame }

    func apply(_ plan: [BorderSpec], width: CGFloat, radius: CGFloat, primaryScreenHeight: CGFloat) {
        let keep = Set(plan.map(\.windowId))
        for (windowId, overlay) in overlays where !keep.contains(windowId) {
            overlay.orderOut(nil)
            overlays.removeValue(forKey: windowId)
        }
        for spec in plan {
            let overlay = overlays[spec.windowId] ?? makeOverlay()
            overlays[spec.windowId] = overlay
            overlay.setFrame(overlayFrame(windowFrame: spec.frame, width: width, primaryScreenHeight: primaryScreenHeight), display: false)
            (overlay.contentView as? BorderView)?.update(style: spec.style, width: width, radius: radius, scale: overlay.backingScaleFactor)
        }
    }

    /// `order` is front-to-back. New overlays aren't in it yet, so they get placed too.
    func restack(order: [UInt32]) {
        for (windowId, overlay) in overlays {
            guard order.contains(windowId) else { continue } // target closed or off screen: next plan removes it
            guard needsRestack(overlayId: UInt32(overlay.windowNumber), targetId: windowId, order: order) else { continue }
            // A background app can't raise its window above another app's windows, but it can lower it
            overlay.orderFrontRegardless()
            overlay.order(.below, relativeTo: Int(windowId))
        }
    }

    private func makeOverlay() -> NSWindow {
        let overlay = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.ignoresMouseEvents = true
        overlay.hasShadow = false
        overlay.isReleasedWhenClosed = false
        overlay.level = .normal
        overlay.collectionBehavior = [.transient, .ignoresCycle]
        overlay.contentView = BorderView()
        return overlay
    }
}

private final class BorderView: NSView {
    private let gradient = CAGradientLayer()
    private let ring = CAShapeLayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        ring.fillRule = .evenOdd
        gradient.mask = ring
        gradient.startPoint = CGPoint(x: 0, y: 1) // top-left (layer origin is bottom-left)
        gradient.endPoint = CGPoint(x: 1, y: 0) // bottom-right
        layer?.addSublayer(gradient)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(style: BorderStyle, width: CGFloat, radius: CGFloat, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = bounds
        let radii = ringRadii(size: bounds.size, width: width, radius: radius)
        let path = CGMutablePath()
        path.addPath(unsafe CGPath(roundedRect: bounds, cornerWidth: radii.outer, cornerHeight: radii.outer, transform: nil))
        path.addPath(unsafe CGPath(roundedRect: bounds.insetBy(dx: width, dy: width), cornerWidth: radii.inner, cornerHeight: radii.inner, transform: nil))
        ring.frame = bounds
        ring.path = path
        gradient.frame = bounds
        gradient.colors = switch style {
            case .solid(let c): [cgColor(argb: c), cgColor(argb: c)]
            case .gradient(let a, let b): [cgColor(argb: a), cgColor(argb: b)]
        }
        for l in [layer, gradient, ring] { l?.contentsScale = scale }
        CATransaction.commit()
    }
}

func cgColor(argb: UInt32) -> CGColor {
    func channel(_ shift: UInt32) -> CGFloat { CGFloat((argb >> shift) & 0xFF) / 255 }
    return CGColor(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: channel(24))
}
