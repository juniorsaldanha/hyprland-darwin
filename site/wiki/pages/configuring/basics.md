# Configuration basics

## Where the config lives

```text
~/.config/hyprland-darwin/config.toml
```

If `XDG_CONFIG_HOME` is set, it's `$XDG_CONFIG_HOME/hyprland-darwin/config.toml` instead.

`hypr init` writes a starter config there. Without a config, HyprDarwin runs with built-in defaults: tiling only, with the bar and borders off.

## Format

The config is [TOML](https://toml.io): AeroSpace's format plus HyprDarwin's own sections.

```toml
config-version = 2
start-at-login = true
auto-reload-config = true          # reload when the file is saved

[gaps]        # spacing around windows
[borders]     # window borders            (HyprDarwin)
[bar]         # the status bar            (HyprDarwin)
[notch]       # the notch panel           (HyprDarwin)
[plugins]     # where plugins live        (HyprDarwin)
[mouse-drag]  # alt + drag                (HyprDarwin)
[mode.main.binding]   # keybinds
```

## Reloading

- **Automatically**, on save, with `auto-reload-config = true`.
- With the command `hypr reload-config`.
- From the menu bar icon: **Reload config**.

## Errors

A config with mistakes still loads: HyprDarwin keeps the valid parts and opens a **diagnostics window** listing each problem with its key:

```text
[ERROR] bar.height: Must be in [16, 100] range
[ERROR] borders.active: Invalid color 'red'. Expected 0xAARRGGBB, e.g. 0xff7aa2f7
```

`hypr reload-config` prints the same list in the terminal.

## Colours

Every colour is a string `'0xAARRGGBB'`: alpha, red, green, blue. `0xff` alpha is opaque, `0x00` is invisible.

```toml
active = '0xffbb9af7'                           # solid
active = 'gradient(0xff7aa2f7,0xffbb9af7)'      # top-left → bottom-right (borders only)
```

## Top-level options

| Option | Default | What it does |
|---|---|---|
| `start-at-login` | `false` | Launch HyprDarwin when you log in |
| `auto-reload-config` | `false` | Reload when the config file is saved |
| `persistent-workspaces` | `[]` | Workspaces that always exist (and always show in the bar) |
| `default-root-container-layout` | `'tiles'` | `'tiles'` or `'accordion'` for new workspaces |
| `default-root-container-orientation` | `'auto'` | `'horizontal'`, `'vertical'` or `'auto'` (by monitor shape) |
| `accordion-padding` | `30` | How much of each hidden window an accordion shows |
| `automatically-unhide-macos-hidden-apps` | `false` | Undo `cmd` + `H` so hidden apps stay tiled |
| `after-startup-command` | `[]` | Commands to run once after start |
| `on-focus-changed` | `[]` | Commands to run when focus changes |
| `on-focused-monitor-changed` | `[]` | Commands to run when the focused monitor changes |
| `exec-on-workspace-change` | `[]` | A program to run on every workspace switch |

The full reference for options inherited from AeroSpace is the [AeroSpace guide](https://nikitabobko.github.io/AeroSpace/guide).
