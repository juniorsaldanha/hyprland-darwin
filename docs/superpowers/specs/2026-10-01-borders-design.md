# Borders (sub-project 2) — Design

Date: 2026-10-01
Status: Draft, awaiting review
Parent spec: `docs/superpowers/specs/2026-10-01-hyprland-darwin-design.md` (section 1, Borders)

## Goal

Built-in window borders that replace JankyBorders, so the
`after-startup-command` that launches `borders` can be removed.

**Success criterion:** with `after-startup-command` removed, a `[borders]`
section added and JankyBorders quit, the look matches the user's current
JankyBorders setup:

```
borders style=round width=5.0 hidpi=on
        active_color="gradient(top_left=0xff7aa2f7,bottom_right=0xffbb9af7)"
        inactive_color=0x80414868
```

### Scope

- In: a gradient or solid border on the focused window, a solid border on
  every other visible managed window, rounded corners, sharp on Retina.
- Out (v1): animated gradients, fades, per-app rules. The user chose
  "just match JankyBorders".

## Spike result (2026-10-01)

Throwaway probe, run on the user's machine with real Arc and Teams windows.
The question: can a public-API overlay stay stacked relative to another
app's window?

| Step | Result |
|---|---|
| `overlay.order(.below, relativeTo: otherAppWindowId)` | ✅ Overlay directly behind the target; windows in front of the target are also in front of the overlay |
| Target raised by its app | Overlay stays where it was (expected) |
| Plain `order(.below, relativeTo:)` after the target is raised | ❌ No effect: a background app can't raise its window above another app's windows |
| `orderFrontRegardless()` then `order(.below, relativeTo: target)` | ✅ Overlay directly behind the target again (same on 2 runs) |
| Another window raised over the target | ✅ It covers both the target and its overlay; the overlay keeps its place |

**Conclusion:** borders on every window are feasible with public APIs. An
overlay sits directly behind its window and its ring is drawn outside the
window's frame. Any window in front of the target also covers the ring,
as with JankyBorders. Only overlays that end up out of place are
re-stacked, using the two-step `orderFrontRegardless` + `order(.below)`.
The spec's focused-only fallback isn't needed.

## Architecture

```
AeroSpace refresh/light session ──► layoutWorkspaces() ──► syncBorders()
AX moved/resized notification  ─────────────────────────► syncBorders()   (live drag/resize)
NSApplication screen-parameters change ─────────────────► syncBorders()
                                                              │
       borderPlan(model windows, focus, onScreenWindows(), config, isEnabled)   ← pure
                                                              │
                         BorderOverlays: create / move / restyle / remove NSWindows
                                         + restack only overlays not directly below their window
```

### Units

| Unit | Responsibility | Depends on |
|---|---|---|
| `BordersConfig` + parser | The `[borders]` TOML section and colour/gradient parsing | AeroSpace config parser |
| `borderPlan(...)` | Pure. Takes model windows, the focused window id, on-screen windows (front to back), the config and whether tiling is enabled. Returns `[BorderSpec]` (window id, frame in screen coordinates, style). | nothing |
| Geometry | Pure. Overlay frame = window frame grown by `width`; flips screen coordinates (top-left origin) to AppKit coordinates (bottom-left origin) using the primary screen's height. | nothing |
| `needsRestack(overlayId:targetId:order:)` | Pure. True unless the overlay is directly behind its target in the front-to-back order. | nothing |
| `BorderOverlays` | Owns one click-through overlay `NSWindow` per bordered window, keyed by window id. Applies a plan: create, move, restyle, remove, restack. | AppKit |
| `syncBorders()` + coalescer | Builds the plan from AeroSpace's model and applies it. Merges bursts into one sync per run-loop turn. | the units above, `onScreenWindows()` from Core |

### Which windows get a border

A window gets a border when **all** of these hold:
- It's a managed window in a tiling or floating container on a visible
  workspace (`monitor.activeWorkspace`).
- It isn't parked off-screen (`isHiddenInCorner`) and isn't in AeroSpace
  `fullscreen` (`isFullscreen`).
- It's in `onScreenWindows()` at layer 0. That list also supplies the
  frame, which is the window's real frame, not the requested layout rect.

Native-fullscreen, minimized, hidden-app and popup containers never get
borders. When tiling is disabled or paused (`TrayMenuModel.isEnabled ==
false`), the plan is empty and every overlay is hidden.

Style: the focused window (`focus.windowOrNil`) gets `active`, every other
window gets `inactive`.

### Drawing

- The overlay is a borderless, transparent, click-through `NSWindow` at
  the normal window level, without a shadow.
  - Collection behavior: `[.transient, .ignoresCycle]`, so it's hidden
    from Mission Control and window cycling.
- The ring is a `CAShapeLayer` path: a rounded rect around the window
  frame, inner radius `radius`, outer radius `radius + width`, so it lies
  entirely outside the window.
  - A gradient fills a `CAGradientLayer` masked by the ring, running top
    left → bottom right (`startPoint (0,1)` → `endPoint (1,0)` in
    bottom-left-origin layer coordinates).
  - `contentsScale` follows the overlay's screen, so it's sharp on Retina.
- Restacking: after applying a plan, each overlay whose `needsRestack` is
  true gets `orderFrontRegardless()` + `order(.below, relativeTo:
  windowId)`, at most once per sync.

### Configuration

```toml
[borders]
enabled = true                               # default false
width = 5                                    # 1–50, default 5
radius = 10                                  # 0–100, default 10: the window corner radius to hug
active = 'gradient(0xff7aa2f7,0xffbb9af7)'   # or a single 0xAARRGGBB; default the gradient shown
inactive = '0x80414868'                      # single 0xAARRGGBB; default shown
```

- `radius` is a tuning knob: window corner radii differ between macOS
  versions and apps.
- With no `[borders]` section, borders are off. The shipped
  `docs/config-examples/default-config.toml` gets a `[borders]` section
  with `enabled = true`, so new installs have borders.
- Colours use 8 hex digits, `0xAARRGGBB`, with alpha first (same as
  JankyBorders).
- `gradient(a,b)` takes exactly two colours. Spaces around the comma are
  allowed.

## Error handling

**Rule:** borders never stall tiling. A sync makes no Accessibility calls.
It reads AeroSpace's model and one `CGWindowListCopyWindowInfo` call.

| Situation | Behavior |
|---|---|
| Bad `[borders]` value | Config error naming the key (`borders.active: …`). AeroSpace keeps the last good config. |
| Window closes between plan and draw | Overlay removed on the next sync. The pool is keyed by window id, so nothing leaks. |
| Managed window missing from the on-screen list | No border until it reappears |
| App moves or resizes its own window | Move/resize notification → sync with the real frame |
| Burst of notifications (drag) | Coalesced to one sync per run-loop turn |
| Restack has no effect | Retried on the next sync only if still out of place. No loop. |
| Monitor or scaling change | Screen-parameters notification → full sync; `contentsScale` updated |
| Tiling disabled or paused | All overlays hidden |
| JankyBorders still running | Double borders. Not detected; the migration step is to remove `after-startup-command`. |

Known limits: apps whose reported frame includes custom shadows can show
the ring a few pixels out, as JankyBorders does. How the overlays look
during the Mission Control animation can only be checked by hand.

## Testing

Same convention as Core: unit tests are XCTest classes, and integration
tests are classes named `*IntegrationTest`. CI runs both.

### Unit tests

| Area | Tests |
|---|---|
| Config | Defaults; a single colour; `gradient(a,b)` with and without spaces; errors for a bad colour, a gradient with 1 or 3 colours, `width` 0 or 51, `radius` −1 or 101, each naming the key; no section means disabled. The user's migrated config plus a `[borders]` section parses with no errors. |
| `borderPlan` | Focused window gets `active`, others `inactive`. No border for: a window missing from the on-screen list, a window on a hidden workspace, `isHiddenInCorner`, `isFullscreen`, a non-zero layer, native fullscreen, minimized or popup windows. An empty plan when tiling is disabled. The frame comes from the on-screen list. |
| Geometry | The overlay frame for a window on the primary monitor; a monitor to the right; a monitor above (negative screen y); a monitor below; `width` applied on every side. |
| `needsRestack` | Directly behind means false. Separated by another window means true. Target or overlay missing from the order means true. Overlay in front of the target means true. |
| Coalescer | Many requests in one turn produce one sync; a request after the sync produces another. Scheduler injected. |

### Integration tests

- `BorderStackingIntegrationTest`: a real target `NSWindow` and a real
  overlay in the test process. After the restack, the window list shows
  the overlay directly behind the target. Raise the target, restack again,
  and it's directly behind again.
- `BorderOverlayIntegrationTest`: apply a 3-window plan, then a 2-window
  plan with one frame changed. Afterwards there are exactly 2 overlay
  windows and the frames match.

### Manual checklist (user's machine, JankyBorders stopped)

- [ ] Focused window has the gradient, the others have the dim border; looks like the current JankyBorders setup
- [ ] Focus change (alt-hjkl or a click) moves the gradient at once
- [ ] A floating window over a tiled one covers the tiled window's border
- [ ] alt+drag and title-bar drag: the border follows live
- [ ] Workspace switch leaves no stray rings
- [ ] Native fullscreen and AeroSpace `fullscreen`: no border
- [ ] Two monitors, then unplug one: borders stay correct
- [ ] Mission Control: no floating rings
- [ ] Retina and external screen: sharp edges

### Acceptance

The success criterion stated in the Goal section.
