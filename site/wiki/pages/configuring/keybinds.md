# Keybinds and modes

## Syntax

Bindings live in a **mode**. The default mode is `main`:

```toml
[mode.main.binding]
    alt-enter = 'new-window-or-open Terminal'
    alt-h = 'focus left'
    alt-shift-h = 'move left'
    alt-1 = 'workspace 1'
```

- The key is `modifiers-key`: modifiers are `alt`, `cmd`, `ctrl`, `shift`, joined with `-`.
- The value is a command, or a list of commands run in order: `['layout floating tiling', 'mode main']`.
- Any [CLI command](#/reference/cli) works here, written without the `hypr` prefix.

## Keyboard layouts

Bindings use key **positions** from your layout preset:

```toml
[key-mapping]
    preset = 'qwerty'   # or 'dvorak', 'colemak'
```

## Launching apps

```toml
alt-enter = 'new-window-or-open kitty'          # focus kitty + new window, or launch it
alt-b = 'exec-and-forget open -a "Arc"'          # plain launch
alt-shift-s = 'exec-and-forget screencapture -ic' # any shell command
```

`new-window-or-open <app>` is HyprDarwin's: it activates the app and presses `cmd` + `N` if it's running, and launches it otherwise.

## Modes (Hyprland submaps)

A mode is a separate set of bindings you switch into, like Hyprland's submaps:

```toml
[mode.main.binding]
    alt-r = 'mode resize'

[mode.resize.binding]
    h = 'resize width -50'
    l = 'resize width +50'
    k = 'resize height -50'
    j = 'resize height +50'
    esc = 'mode main'
    enter = 'mode main'
```

While a mode other than `main` is active, the menu bar indicator shows its name.

## Useful commands to bind

| Command | Does |
|---|---|
| `focus left` / `down` / `up` / `right` | Move focus |
| `move left` … | Move the window in the tree |
| `workspace 3` | Go to workspace 3 |
| `move-node-to-workspace 3` | Send the window to workspace 3 |
| `workspace-back-and-forth` | Previous workspace |
| `move-workspace-to-monitor --wrap-around next` | Send the whole workspace to the next monitor |
| `fullscreen` | Toggle fullscreen (inside the tiling) |
| `macos-native-fullscreen` | macOS's own fullscreen Space |
| `layout floating tiling` | Toggle floating |
| `layout tiles horizontal vertical` | Tiles; toggle orientation |
| `layout accordion horizontal vertical` | Accordion; toggle orientation |
| `resize smart +50` | Grow the window |
| `balance-sizes` | Give every window an equal share |
| `close` | Close the window |
| `reload-config` | Reload the config |
