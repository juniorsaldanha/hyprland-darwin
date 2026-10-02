# Troubleshooting

## Nothing tiles

1. Is HyprDarwin running? Look for its indicator in the macOS menu bar, or run `hypr list-workspaces --all`.
2. Is **Accessibility** granted? Open the menu bar icon → **Permissions…**.
3. **After an upgrade** (Homebrew releases are signed ad hoc), macOS forgets the permission. In **System Settings → Privacy & Security → Accessibility**, remove HyprDarwin with **−** and add it again, then relaunch.
4. Is it **disabled**? The menu bar icon's menu shows **Enable** if so.

## "Can't connect to HyprDarwin"

The `hypr` CLI can't reach the app. Start it with `open -a HyprDarwin`.

If you see **"hypr and HyprDarwin.app versions don't match"**, restart HyprDarwin after upgrading.

## Config changes don't apply

- Set `auto-reload-config = true`, or run `hypr reload-config`.
- Check for errors: `hypr reload-config` lists them, and so does the diagnostics window.

## Windows tile under the bar

Raise `outer.top` in [`[gaps]`](#/configuring/gaps) to at least the bar's `height` (40 by default) plus a few pixels.

## A widget shows ⚠

Click it: the menu shows why (click the reason to copy it) and **Open log**. Then:

```sh
hypr list-plugins
tail -50 ~/Library/Logs/hyprland-darwin/<name>.log
```

Common causes:

- **`missing`**: no folder with that name in your plugin directories.
- **`invalid`**: a typo in `plugin.toml`, or the executable isn't executable (`chmod +x run.sh`).
- **`stopped`**: a stream plugin crashed 5 times within a minute. Fix it, then reload the config.

## A widget stopped updating

Its output is probably invalid JSON. A common case is an icon above U+FFFF written as `"0"` instead of a surrogate pair. See [Writing plugins](#/plugins/writing). The plugin's log names the dropped lines.

## alt + drag does nothing

- `[mouse-drag] enabled = true`?
- If macOS refused the mouse hook, a warning appears with your config diagnostics. Re-grant Accessibility and reload.

## An app's windows misbehave

Some apps, especially dialogs and utilities, tile badly. Float them with a [window rule](#/configuring/window-rules):

```toml
[[on-window-detected]]
    if.app-id = 'com.example.app'
    run = 'layout floating'
```

## Where are the logs?

| Log | Path |
|---|---|
| HyprDarwin | `~/Library/Logs/hyprland-darwin/hyprdarwin.log` |
| Each plugin | `~/Library/Logs/hyprland-darwin/<name>.log` |

## Reporting a bug

[Open an issue](https://github.com/juniorsaldanha/hyprland-darwin/issues/new/choose) with:

- `hypr --version` and your macOS version
- the relevant part of your config
- `hypr debug-windows` output if it's about specific windows
