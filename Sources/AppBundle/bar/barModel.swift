import AppKit

enum BarItem: Equatable, Identifiable {
    case workspace(name: String, isFocused: Bool)
    case chevron
    case frontApp(String)
    case plugin(name: String, state: WidgetState)
    case problem(name: String, reason: String)

    var id: String {
        switch self {
            case .workspace(let name, _): "workspace:\(name)"
            case .chevron: "chevron"
            case .frontApp: "front-app"
            case .plugin(let name, _): "plugin:\(name)"
            case .problem(let name, _): "problem:\(name)"
        }
    }
}

/// Pure. One section's items, in config order. Empty or hidden widgets take no space; broken plugins show ⚠.
func barItems(
    names: [String],
    workspaces: [WorkspaceViewModel],
    frontApp: String?,
    widgets: [String: WidgetState],
    statuses: [String: PluginStatus],
) -> [BarItem] {
    names.flatMap { name -> [BarItem] in
        switch name {
            case "workspaces":
                return workspaces.map { .workspace(name: $0.name, isFocused: $0.isFocused) }
            case "chevron":
                return [.chevron]
            case "front-app":
                guard let frontApp, !frontApp.isEmpty else { return [] }
                return [.frontApp(frontApp)]
            default:
                if let status = statuses[name] {
                    switch status {
                        case .missing, .invalid, .stopped: return [.problem(name: name, reason: status.description)]
                        case .failing where widgets[name] == nil, .restarting where widgets[name] == nil: return [.problem(name: name, reason: status.description)]
                        case .starting, .running, .failing, .restarting: break
                    }
                }
                guard let state = widgets[name], !state.hidden, !(state.icon ?? "").isEmpty || !(state.label ?? "").isEmpty else { return [] }
                return [.plugin(name: name, state: state)]
        }
    }
}

/// Hide when the cursor is within 8 px of the top; show again only beyond 24 px (no flicker in between)
struct AutoHideState {
    var hideWithin: CGFloat = 8
    var showBeyond: CGFloat = 24
    private(set) var isHidden = false

    /// Returns true when the hidden state changed
    mutating func update(distanceFromTop distance: CGFloat) -> Bool {
        if !isHidden && distance <= hideWithin {
            isHidden = true
            return true
        }
        if isHidden && distance > showBeyond {
            isHidden = false
            return true
        }
        return false
    }
}

/// The notch: the gap between the two auxiliary top areas, in global AppKit coordinates. Nil without a notch.
/// Only the aux rects' sizes are used: their coordinate space isn't documented, the screen frame's is.
func notchRect(screenFrame: CGRect, auxLeft: CGRect?, auxRight: CGRect?) -> CGRect? {
    guard let auxLeft, let auxRight else { return nil }
    return CGRect(
        x: screenFrame.minX + auxLeft.width,
        y: screenFrame.maxY - auxLeft.height,
        width: screenFrame.width - auxLeft.width - auxRight.width,
        height: auxLeft.height,
    )
}

/// Which screen the cursor is on. Top edge closed, bottom open: at the very top pixel
/// NSEvent.mouseLocation.y == frame.maxY, which CGRect.contains excludes.
func screenIndex(containing point: CGPoint, frames: [CGRect]) -> Int? {
    frames.firstIndex { $0.minX <= point.x && point.x < $0.maxX && $0.minY < point.y && point.y <= $0.maxY }
}

/// Bar across the top edge of the screen (AppKit coordinates)
func barFrame(screenFrame: CGRect, height: CGFloat) -> CGRect {
    CGRect(x: screenFrame.minX, y: screenFrame.maxY - height, width: screenFrame.width, height: height)
}

func nsColor(argb: UInt32) -> NSColor {
    func channel(_ shift: UInt32) -> CGFloat { CGFloat((argb >> shift) & 0xFF) / 255 }
    return NSColor(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: channel(24))
}

/// A widget's colour string, or the fallback when it's missing or malformed
func widgetColor(_ string: String?, fallback: UInt32) -> NSColor {
    nsColor(argb: string.flatMap { try? parseArgb($0).get() } ?? fallback)
}

/// The bar's icon font: the configured family in bold; the system font when the family isn't available
func barIconNSFont(family: String, size: CGFloat) -> NSFont {
    NSFontManager.shared.font(withFamily: family, traits: .boldFontMask, weight: 9, size: size) ?? .boldSystemFont(ofSize: size)
}

/// Width the bar gives an icon: its whole drawing, not just its advance. Nerd Font icons draw up to ~1.7x wider than
/// their advance width; laid out by advance (SwiftUI's default), the label after the icon would overlap it.
func barIconWidth(_ icon: String, font: NSFont) -> CGFloat {
    let string = NSAttributedString(string: icon, attributes: [.font: font])
    let ink = string.boundingRect(with: .zero, options: [.usesDeviceMetrics, .usesLineFragmentOrigin])
    return ceil(max(string.size().width, ink.maxX) - min(0, ink.minX))
}

/// How far right to shift an icon whose drawing starts left of its origin, so nothing sticks out on the left either
func barIconLeadingInset(_ icon: String, font: NSFont) -> CGFloat {
    let ink = NSAttributedString(string: icon, attributes: [.font: font]).boundingRect(with: .zero, options: [.usesDeviceMetrics, .usesLineFragmentOrigin])
    return max(0, -ink.minX)
}
