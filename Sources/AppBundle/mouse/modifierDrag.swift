import AppKit
import Common

private struct DragState {
    let window: Window
    let startMouse: CGPoint
    let startTopLeft: CGPoint
}

@MainActor private var eventTap: CFMachPort? = nil
@MainActor private var requiredFlags: CGEventFlags = []
@MainActor private var dragState: DragState? = nil
/// Window being moved by modifier+drag. isManipulatedWithMouse treats it as dragged right away:
/// before native focus lands, and regardless of NSEvent.pressedMouseButtons (the tap swallowed the mouse-down)
@MainActor var modifierDragWindowId: UInt32? = nil

@MainActor func syncModifierDrag(_ config: Config) {
    requiredFlags = config.mouseDrag.modifier
    if config.mouseDrag.enabled == (eventTap != nil) { return }

    if !config.mouseDrag.enabled {
        removeModifierDragTap()
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

/// A tap created before Accessibility was revoked stays dead after the re-grant
@MainActor func rebuildModifierDragTap() {
    removeModifierDragTap()
    syncModifierDrag(config)
}

@MainActor private func removeModifierDragTap() {
    if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: false)
        CFMachPortInvalidate(eventTap)
    }
    eventTap = nil
    dragState = nil
    modifierDragWindowId = nil
}

/// Exact match on alt/cmd/ctrl/shift, so alt+shift+click still reaches apps when the modifier is 'alt'
func modifierDragMatches(_ flags: CGEventFlags, _ required: CGEventFlags) -> Bool {
    let relevant: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]
    return !required.isEmpty && flags.intersection(relevant) == required
}

struct OnScreenWindow: Equatable {
    let id: UInt32
    let layer: Int
    let bounds: CGRect
    var ownerPid: pid_t = 0
}

/// Front-to-back. Bounds are global, top-left origin (same space as Accessibility frames and CGEvent.location).
/// Reads no window titles, so it needs no Screen Recording permission.
func onScreenWindows() -> [OnScreenWindow] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { info in
        guard let id = info[kCGWindowNumber as String] as? UInt32,
              let layer = info[kCGWindowLayer as String] as? Int,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { return nil }
        return OnScreenWindow(id: id, layer: layer, bounds: bounds, ownerPid: info[kCGWindowOwnerPID as String] as? pid_t ?? 0)
    }
}

/// The managed window to drag, or nil to let the click through (desktop, menu bar, Dock, popups, unmanaged windows).
/// Decided synchronously, so a click is only swallowed when there is something to drag.
@MainActor func modifierDragTarget(
    flags: CGEventFlags,
    required: CGEventFlags,
    at point: CGPoint,
    onScreen: @autoclosure () -> [OnScreenWindow],
) -> (window: Window, frame: CGRect)? {
    guard modifierDragMatches(flags, required),
          // Skip our own windows: border overlays sit at layer 0 and extend `borders.width` past their window
          let hit = onScreen().first(where: { $0.ownerPid != myPid && $0.bounds.contains(point) }),
          hit.layer == 0, // kCGNormalWindowLevel: not the menu bar, Dock, or overlays
          let window = Window.get(byId: hit.id) else { return nil }
    return (window, hit.bounds)
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
    let location = event.location
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
            guard TrayMenuModel.shared.isEnabled,
                  let target = modifierDragTarget(flags: flags, required: requiredFlags, at: location, onScreen: onScreenWindows())
            else { return false }
            target.window.nativeFocus()
            modifierDragWindowId = target.window.windowId
            dragState = DragState(window: target.window, startMouse: location, startTopLeft: target.frame.origin)
            return true
        case .leftMouseDragged:
            guard let state = dragState else { return false }
            state.window.setAxFrame(
                CGPoint(x: state.startTopLeft.x + location.x - state.startMouse.x, y: state.startTopLeft.y + location.y - state.startMouse.y),
                nil,
            )
            return true
        case .leftMouseUp:
            // Passed through on purpose: GlobalObserver's leftMouseUp monitor finishes the move
            dragState = nil
            modifierDragWindowId = nil
            return false
        default:
            return false
    }
}
