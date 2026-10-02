# Using plugins

Every bar widget except `workspaces`, `chevron` and `front-app` is a **plugin**: a small program that HyprDarwin runs and whose output it draws.

## Placing a plugin

Put its name in a bar section or the notch:

```toml
[bar]
    right = ['cpu', 'clock']

[notch]
    items = ['battery']
```

HyprDarwin starts the plugins that are placed, and only those. Removing a name stops the plugin on the next reload.

## Where plugins come from

For each name, HyprDarwin looks for a folder called `<name>` in:

1. the directories in `[plugins] dirs` (default `~/.config/hyprland-darwin/plugins`)
2. the plugins bundled with the app ([list](#/plugins/bundled))

The first match wins, so a folder of your own with the same name **overrides** a bundled plugin.

```toml
[plugins]
    dirs = ['~/.config/hyprland-darwin/plugins', '~/dotfiles/hypr-plugins']
```

## Checking on them

```sh
hypr list-plugins
```

```text
cpu | interval | running | 0 | 12%
gpu | interval | failing (3) | 0 | 4%
mine | - | missing: no plugin folder in ~/.config/hyprland-darwin/plugins | 0 |
```

Columns: `name | mode | status | restarts | label`. `--json` prints everything, including the widget's full state.

| Status | Meaning |
|---|---|
| `starting` | Just launched |
| `running` | Healthy |
| `failing (n)` | An interval plugin failed n times in a row; it keeps its schedule |
| `restarting in Ns` | A stream plugin exited and will restart |
| `stopped: …` | Crashed 5 times within 60 s. Reload the config to retry |
| `missing: …` | No folder with that name |
| `invalid: …` | Bad `plugin.toml` or the executable is missing |

A broken plugin shows as **⚠ name** in the bar. Click it for the reason.

## Logs

Each plugin's stderr and HyprDarwin's notes about it go to:

```text
~/Library/Logs/hyprland-darwin/<name>.log
```
