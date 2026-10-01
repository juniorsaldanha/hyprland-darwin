import AppKit

struct BorderSpec: Equatable {
    let windowId: UInt32
    let frame: CGRect // screen coordinates, top-left origin
    let style: BorderStyle
}

/// Managed windows that may get a border: tiling or floating, on a visible workspace, not AeroSpace-fullscreen.
/// Windows of invisible workspaces are parked in a corner, so "visible workspace" also covers isHiddenInCorner.
@MainActor func borderCandidates() -> [UInt32] {
    Workspace.all.filter(\.isVisible).flatMap(\.allLeafWindowsRecursive).filter { window in
        if window.isFullscreen { return false }
        return switch window.windowParentCases {
            case .tilingContainer, .floatingWindowsContainer: true
            case .macosMinimizedWindowsContainer, .macosHiddenAppsWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .unbound: false
        }
    }.map(\.windowId)
}

/// Pure. Front-to-back like `onScreen`. Frames are the real on-screen frames, not the requested layout rects.
func borderPlan(
    candidates: [UInt32],
    focusedId: UInt32?,
    onScreen: [OnScreenWindow],
    config: BordersConfig,
    isEnabled: Bool,
) -> [BorderSpec] {
    guard config.enabled, isEnabled else { return [] }
    let candidates = Set(candidates)
    return onScreen
        .filter { $0.layer == 0 && candidates.contains($0.id) }
        .map { BorderSpec(windowId: $0.id, frame: $0.bounds, style: $0.id == focusedId ? config.active : config.inactive) }
}
