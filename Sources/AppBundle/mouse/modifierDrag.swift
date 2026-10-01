import AppKit
import Common

private struct DragState {
    let window: Window
    let startMouse: CGPoint
    let startTopLeft: CGPoint
}

@MainActor private var eventTap: CFMachPort? = nil
@MainActor private var requiredFlags: CGEventFlags = []
/// True between a swallowed mouse-down and the next mouse-up
@MainActor private var isDragging = false
@MainActor private var dragState: DragState? = nil

@MainActor func syncModifierDrag(_ config: Config) {
    requiredFlags = config.mouseDrag.modifier
    if config.mouseDrag.enabled == (eventTap != nil) { return }

    if !config.mouseDrag.enabled {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
        return
    }

    let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue)
        | (1 << CGEventType.leftMouseUp.rawValue)
    // An active (.defaultTap) tap needs Accessibility permission, which the app already requires.
    guard let tap = unsafe CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: modifierDragCallback,
        userInfo: nil,
    ) else { return }
    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    eventTap = tap
}

/// Exact match on alt/cmd/ctrl/shift, so alt+shift+click still reaches apps when the modifier is 'alt'
func modifierDragMatches(_ flags: CGEventFlags, _ required: CGEventFlags) -> Bool {
    let relevant: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]
    return !required.isEmpty && flags.intersection(relevant) == required
}

private func modifierDragCallback(
    _: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _: UnsafeMutableRawPointer?,
) -> Unmanaged<CGEvent>? {
    // The tap's run loop source is on the main run loop
    // CGEvent isn't Sendable: hand the main actor plain values
    let flags = event.flags
    let location = event.location // Global, top-left origin: same space as Accessibility frames
    let swallow = MainActor.assumeIsolated { handleModifierDragEvent(type, flags: flags, location: location) }
    return swallow ? nil : unsafe Unmanaged.passUnretained(event)
}

/// Returns true when the event must be swallowed
@MainActor private func handleModifierDragEvent(_ type: CGEventType, flags: CGEventFlags, location: CGPoint) -> Bool {
    switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        case .leftMouseDown:
            guard TrayMenuModel.shared.isEnabled, modifierDragMatches(flags, requiredFlags) else { return false }
            isDragging = true
            dragState = nil
            Task.startUnstructured { @MainActor in
                guard let window = await windowUnderPoint(location),
                      let rect = try? await window.getAxRect(.nonCancellable),
                      isDragging else { return }
                window.nativeFocus()
                dragState = DragState(window: window, startMouse: location, startTopLeft: rect.topLeftCorner)
            }
            return true
        case .leftMouseDragged:
            guard isDragging else { return false }
            if let state = dragState {
                let mouse = location
                state.window.setAxFrame(
                    CGPoint(x: state.startTopLeft.x + mouse.x - state.startMouse.x, y: state.startTopLeft.y + mouse.y - state.startMouse.y),
                    nil,
                )
            }
            return true
        case .leftMouseUp:
            // Passed through on purpose: GlobalObserver's leftMouseUp monitor finishes the move
            isDragging = false
            dragState = nil
            return false
        default:
            return false
    }
}

@concurrent
private nonisolated func windowIdUnderPoint(_ point: CGPoint) async -> UInt32? {
    let systemwide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    if unsafe AXUIElementCopyElementAtPosition(systemwide, Float(point.x), Float(point.y), &element) != .success {
        return nil
    }
    return element?.containingWindowId()
}

@MainActor private func windowUnderPoint(_ point: CGPoint) async -> Window? {
    guard let windowId = await windowIdUnderPoint(point) else { return nil }
    return Window.get(byId: windowId)
}
