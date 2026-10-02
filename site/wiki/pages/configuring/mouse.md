# Mouse

## Focus follows the mouse

```toml
[focus-follows-mouse]
    enabled = true
```

Pointing at a window focuses it, without clicking, as in Hyprland's `follow_mouse = 1`.

## Drag to move (`alt` + drag)

```toml
[mouse-drag]
    enabled = true
    modifier = 'alt'      # alt, cmd, ctrl, shift, or combined: 'cmd-alt'
```

Hold the modifier and drag anywhere in a window to move it:

- **Tiled windows:** drop it over another tiled window to move it to that spot in the layout.
- **Floating windows:** they move freely.

The click itself goes to HyprDarwin, not the app, so an `alt` + click inside a window doesn't trigger anything in the app.

> [!WARNING]
> If macOS refuses HyprDarwin's mouse hook, alt + drag turns off and a warning appears with your config diagnostics. Check that HyprDarwin is enabled under **Privacy & Security → Accessibility**, then reload the config.

## Moving the mouse with focus

```toml
on-focused-monitor-changed = ['move-mouse monitor-lazy-center']
```

When focus jumps to another monitor, the mouse follows, so focus-follows-mouse doesn't pull focus straight back.
