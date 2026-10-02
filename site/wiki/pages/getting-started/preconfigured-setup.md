# Preconfigured setup

`hypr init` turns a fresh Mac into a Hyprland-style desktop in one command. It is safe to run more than once.

```sh
hypr init                              # settings + starter config
hypr init --wallpaper ~/Pictures/w.jpg # also set the wallpaper on every screen
hypr init --undo                       # restore the settings from before the first run
```

## What it changes

| Setting | Value | Why |
|---|---|---|
| `com.apple.spaces spans-displays` | `true` | Displays share one Space, which tiling across monitors needs. Takes effect after you log out. |
| `com.apple.dock expose-group-apps` | `true` | Mission Control groups windows by app, so tiled windows aren't shown tiny. |
| `NSGlobalDomain NSAutomaticWindowAnimationsEnabled` | `false` | No window-open animation, so new windows snap into place. |
| `NSGlobalDomain _HIHideMenuBar` | `true` | Hides the macOS menu bar so HyprDarwin's bar takes its place. |

It also writes the **starter config** to `~/.config/hyprland-darwin/config.toml`, but only if you don't have one. An existing config is never overwritten.

## Backups and undo

- Before changing anything, `hypr init` saves your previous values in `~/.config/hyprland-darwin/setup-backup.json`.
- Running it again keeps the first backup, so `--undo` always restores what you had *before HyprDarwin*.
- If the backup file is unreadable, `hypr init` refuses to run and changes nothing. That file holds your only copy of the original settings.
- A setting that holds something other than true/false is left alone and not recorded.
- `--wallpaper` with a missing file fails **before** anything changes.

## The starter config

The starter config is Hyprland-flavoured:

- `alt` as the mod key, with vim-style focus and move keys
- workspaces 1–5 always shown in the bar
- focus follows the mouse, and `alt` + drag moves windows
- gaps that leave room for the bar
- gradient borders and the bar with every bundled widget
- System Settings, Activity Monitor and Calculator open floating

Each section of it has a page under [Configuring](#/configuring/basics).
