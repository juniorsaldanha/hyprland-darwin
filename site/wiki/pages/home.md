# Welcome to the HyprDarwin wiki

HyprDarwin is a tiling window manager for macOS that brings the Hyprland experience to your Mac. Tiling, a status bar, window borders and a plugin system ship in **one native app**. It is a fork of [AeroSpace](https://github.com/nikitabobko/AeroSpace), so it needs no SIP changes.

> [!TIP]
> New here? Start with the **[Master tutorial](#/getting-started/master-tutorial)**. It takes you from installing to a configured setup in about ten minutes.

## Where to go

| If you want to… | Read |
|---|---|
| Install HyprDarwin | [Installation](#/getting-started/installation) |
| Get a working setup step by step | [Master tutorial](#/getting-started/master-tutorial) |
| Know what `hypr init` changes | [Preconfigured setup](#/getting-started/preconfigured-setup) |
| Change keybinds, gaps, colours, the bar | [Configuring](#/configuring/basics) |
| Add a widget to the bar | [Using plugins](#/plugins/using) |
| Write your own widget | [Writing plugins](#/plugins/writing) |
| Drive HyprDarwin from scripts | [CLI](#/reference/cli) |
| Fix something that isn't working | [Troubleshooting](#/reference/troubleshooting) |

## Coming from Hyprland?

HyprDarwin borrows Hyprland's ideas, but the config is TOML (AeroSpace's format plus a few sections) instead of `hyprland.conf`.

| Hyprland | HyprDarwin |
|---|---|
| `hyprland.conf` | `~/.config/hyprland-darwin/config.toml` |
| `$mainMod = SUPER` | `alt` in every binding, e.g. `alt-enter` |
| `bind = $mainMod, Q, exec, kitty` | `alt-q = 'exec-and-forget open -a kitty'` |
| `workspace = 1, monitor:DP-1` | `[workspace-to-monitor-force-assignment]` |
| `windowrule = float, …` | `[[on-window-detected]]` with `run = 'layout floating'` |
| Submaps | Modes: `[mode.resize.binding]` |
| `hyprctl` | `hypr` |
| Waybar | the built-in [status bar](#/configuring/bar) |
| `general:col.active_border` | [`[borders]`](#/configuring/borders) |
| Special workspace | a workspace you toggle to, e.g. `alt-s = 'workspace S'` |
| Dwindle / master layouts | AeroSpace's tree: [tiles and accordion](#/configuring/layouts) |

## Having issues?

Check [Troubleshooting](#/reference/troubleshooting) first. If that doesn't help, [open an issue](https://github.com/juniorsaldanha/hyprland-darwin/issues/new/choose) with the output of `hypr --version`.
