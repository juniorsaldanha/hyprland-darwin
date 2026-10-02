# Master tutorial

This tutorial takes you from zero to a working, riced HyprDarwin. Do the steps in order: each one builds on the last.

## Install HyprDarwin

Follow [Installation](#/getting-started/installation). Homebrew is the fastest:

```sh
brew tap juniorsaldanha/hyprland-darwin https://github.com/juniorsaldanha/hyprland-darwin
brew install --cask hyprdarwin
```

## Permissions

HyprDarwin moves and resizes other apps' windows. macOS only allows that with **Accessibility** permission.

- On first launch, a **Permissions window** lists what's missing and opens the right System Settings pane.
- Turn HyprDarwin on under **System Settings → Privacy & Security → Accessibility**.
- If HyprDarwin is on but still shows ✗, click **Relaunch** in the Permissions window.

> [!NOTE]
> Nothing else is required: no SIP changes and no Screen Recording permission.

## Multiple monitors?

They work out of the box. Each monitor shows one workspace at a time and has its own bar. The [workspaces and monitors](#/configuring/workspaces-monitors) page shows how to pin workspaces to monitors.

> [!TIP]
> `hypr init` sets "displays share one Space". Log out and back in once afterwards; macOS only applies it at login.

## Launching HyprDarwin

```sh
open -a HyprDarwin
```

The starter config sets `start-at-login = true`, so after the first run it starts with your Mac. HyprDarwin has no Dock icon. It shows a small workspace indicator in the macOS menu bar. Its menu has **Open config**, **Reload config**, **Disable**, **Permissions…** and **Quit**.

## Preconfigured setup: `hypr init`

```sh
hypr init
```

One command gets you a Hyprland-like setup:

- applies the macOS settings tiling needs (and backs up your previous values)
- writes a starter config to `~/.config/hyprland-darwin/config.toml`
- with `--wallpaper <path>`, sets your wallpaper on every screen

`hypr init --undo` restores your old settings. See [Preconfigured setup](#/getting-started/preconfigured-setup) for exactly what changes.

## In HyprDarwin with the default config

The starter config uses `alt` as the mod key, in place of Hyprland's `SUPER`. The essentials:

| Keys | Action |
|---|---|
| `alt` + `enter` | Open (or focus) Terminal |
| `alt` + `h` `j` `k` `l` | Focus left / down / up / right |
| `alt` + `shift` + `h` `j` `k` `l` | Move the focused window |
| `alt` + `1`…`0` | Go to workspace 1…10 |
| `alt` + `shift` + `1`…`0` | Send the window to workspace 1…10 |
| `alt` + `f` | Fullscreen |
| `alt` + `v` | Toggle floating |
| `alt` + `/` | Tiles layout (toggles horizontal / vertical) |
| `alt` + `,` | Accordion layout |
| `alt` + `-` / `alt` + `=` | Shrink / grow |
| `alt` + `r` | Resize mode: `h` `j` `k` `l`, `esc` to leave |
| `alt` + `tab` | Back to the previous workspace |
| `alt` + `s` | Scratchpad workspace |
| `alt` + drag | Move a window with the mouse |

Try it: open a few Terminal windows with `alt` + `enter` and watch them tile. Move between them with `alt` + `h`/`l`.

## Critical software

HyprDarwin replaces the window manager, the bar and the borders. You still want:

- **A terminal.** Terminal works; kitty, WezTerm, Ghostty or Alacritty are popular. Bind it: `alt-enter = 'new-window-or-open kitty'`.
- **A launcher.** Spotlight (`cmd` + `space`) or Raycast stand in for wofi/rofi.
- **A Nerd Font**, only for your own plugins' icons. The bar already bundles Hack Nerd Font.

## Monitors config

macOS handles resolution and arrangement in **System Settings → Displays**. HyprDarwin follows that arrangement. To keep workspaces on specific monitors:

```toml
[workspace-to-monitor-force-assignment]
    1 = 'main'
    2 = 'main'
    9 = 'secondary'
```

More in [Workspaces and monitors](#/configuring/workspaces-monitors).

## Apps and replacements

| On Hyprland you'd use | On HyprDarwin |
|---|---|
| Waybar | the built-in [bar](#/configuring/bar) |
| hyprpaper | `hypr init --wallpaper ~/Pictures/wall.jpg` |
| Hyprland's border options | the built-in [borders](#/configuring/borders) |
| eww / custom scripts | [plugins](#/plugins/using) |
| `hyprctl dispatch` | `hypr <command>` |

## Fully configure HyprDarwin

Open the config and edit away. It reloads by itself when you save.

```sh
open -e ~/.config/hyprland-darwin/config.toml
```

Work through the [Configuring](#/configuring/basics) section. Most people change these first:

1. [Keybinds](#/configuring/keybinds): your terminal and browser, your favourite apps
2. [Gaps](#/configuring/gaps): tight or roomy
3. [Window rules](#/configuring/window-rules): which apps float
4. [The bar](#/configuring/bar): which widgets, and where

## Themes

Colours are `0xAARRGGBB`: alpha first, then red, green, blue.

```toml
[borders]
    active = 'gradient(0xffff2bd6,0xff22e4ff)'   # magenta → cyan
    inactive = '0x60414868'

[bar]
    color = '0x6014052b'        # tint over the blur
    foreground = '0xfff0e8ff'
```

Want the look from this site? Set the wallpaper to something purple and neon, with the borders above.

## You're done

You have tiling, a bar and borders. Next:

- add widgets with [plugins](#/plugins/using)
- script your setup with the [CLI](#/reference/cli)
