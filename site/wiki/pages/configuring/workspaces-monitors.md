# Workspaces and monitors

HyprDarwin uses **virtual workspaces**: it doesn't rely on macOS Spaces. Switching workspaces is instant, with no animation, and needs no SIP changes.

## How workspaces work

- Each monitor shows exactly one workspace at a time.
- A workspace exists while it has windows, is visible, or is **persistent**.
- Names are any string: `1`, `web`, `S`.

```toml
persistent-workspaces = ["1", "2", "3", "4", "5"]
```

Persistent workspaces always exist, so they always show in the bar, even when empty.

## Switching

```toml
alt-1 = 'workspace 1'
alt-shift-1 = 'move-node-to-workspace 1'
alt-tab = 'workspace-back-and-forth'
```

Going to a workspace that doesn't exist yet creates it.

## Monitors

macOS decides the arrangement (**System Settings → Displays**). HyprDarwin sorts monitors left to right, then top to bottom.

### Pinning workspaces to monitors

```toml
[workspace-to-monitor-force-assignment]
    1 = 'main'                       # the main display
    2 = 'secondary'                  # the other one
    3 = 'built-in'                   # the MacBook screen
    4 = '^LG'                        # a regex on the display name
    5 = ['secondary', 'main']        # the first that's connected
```

### Moving between monitors

```toml
alt-shift-tab = 'move-workspace-to-monitor --wrap-around next'
alt-o = 'focus-monitor --wrap-around next'
alt-shift-o = 'move-node-to-monitor --wrap-around next'
```

## The scratchpad ("special workspace")

Hyprland's special workspace is a hidden workspace you toggle. In HyprDarwin, any workspace can play that role:

```toml
alt-s = 'workspace S'
alt-shift-s = 'move-node-to-workspace S'
```

## In the bar

The bar's `workspaces` widget shows every workspace: persistent ones, non-empty ones and visible ones. With two monitors you may prefer only what's on screen:

```toml
[bar]
    workspaces = 'visible'   # e.g.  1 │ 2  — one per monitor, the focused one highlighted
```
