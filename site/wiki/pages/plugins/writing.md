# Writing plugins

A plugin is a folder with a `plugin.toml` and an executable, in any language. HyprDarwin talks to it with **JSON lines**: one JSON object per line.

```text
~/.config/hyprland-darwin/plugins/mywidget/
├── plugin.toml
└── run.sh          # chmod +x
```

## The manifest

```toml
api = 1                         # protocol version: must be 1
exec = "./run.sh"               # relative to the folder, or absolute; must be executable
mode = "interval"               # "interval" or "stream"
interval = 5                    # seconds, interval mode only, ≥ 1
events = ["click", "wake"]      # optional
```

## Two modes

### `interval`: run, print, exit

HyprDarwin runs the executable every `interval` seconds, and also on each event you subscribed to. It reads what the run prints, then the process exits.

- On an event-triggered run, the event's name is in `HYPR_EVENT` and its JSON in `HYPR_EVENT_JSON`. On a timer run they're unset.
- For clicks, `HYPR_BUTTON` is `left` or `right`.
- A run is killed after `min(interval, 5)` seconds. Three failures in a row mark the plugin `failing (n)`, but it keeps its schedule.

```sh
#!/bin/sh
printf '{"icon":"\\uF43A","label":"%s"}\n' "$(date +%H:%M)"
```

### `stream`: stay running

The executable keeps running. Events arrive on **stdin**, one JSON line each, and you print updates whenever you like.

- Right after (re)starting, it receives the current state (for example the focused workspace).
- It **must exit when stdin closes**: that's how HyprDarwin stops it.
- If it exits, it's restarted with backoff. 5 exits within 60 s stop it until the next config reload.

```sh
#!/bin/sh
echo '{"label":"ws ?"}'
while IFS= read -r event; do
    ws=$(printf '%s' "$event" | sed -n 's/.*"focused":"\([^"]*\)".*/\1/p')
    [ -n "$ws" ] && printf '{"label":"ws %s"}\n' "$ws"
done
```

## Output: widget updates

Each line is a **partial update**, merged into the widget's current state:

| Field | Type | Notes |
|---|---|---|
| `icon` | string | Usually a Nerd Font glyph, e.g. `"\uF4BC"` |
| `label` | string | Text after the icon |
| `color` | string | `0xAARRGGBB`, the label (and icon, unless `icon_color`) |
| `icon_color` | string | `0xAARRGGBB` |
| `background` | string | `0xAARRGGBB`, a pill behind the widget |
| `hidden` | bool | Hide without stopping the plugin |
| `popup` | array | A click menu: `[{"label": "…", "run": "…"}]` |

```json
{"icon": "\uF4BC", "label": "12%", "color": "0xffe1e1e1"}
{"hidden": true}
{"popup": [{"label": "Activity Monitor", "run": "exec-and-forget open -a 'Activity Monitor'"}, {"label": "just text"}]}
```

A widget with an empty icon and label takes no space.

> [!IMPORTANT]
> Icons above U+FFFF need a **surrogate pair** in JSON: `"\uDB80\uDE00"`, not `"\uF0200"`. A broken escape makes the whole line invalid, and the widget stops updating. Check the plugin's log.

## Output: commands

```json
{"run": "workspace 2"}
```

`run` executes any HyprDarwin command, the same as a keybinding. If a line has both `run` and widget fields, `run` wins.

## Events

Subscribe in `events = [...]`:

| Event | When | JSON fields |
|---|---|---|
| `workspace` | The focused workspace changed | `focused`, `prev` |
| `focus` | Window focus changed | `app`, `bundle`, `workspace` |
| `monitor` | The focused monitor changed | `workspace`, `monitor` |
| `wake` | The Mac woke from sleep | — |
| `click` | The widget was clicked (without a popup) | `button`: `left` / `right` |
| `power` | Switched between AC and battery | `source`: `ac` / `battery` |
| `volume` | Output volume changed | `level`: 0–100 |

Every event line also has `"event": "<name>"`.

## Environment

Plugins run with the same environment as `exec-and-forget`, plus:

- `HYPR_PLUGIN_NAME`: the plugin's name
- `HYPR_PLUGIN_DIR`: its folder

## Limits

- Lines over 64 KB are dropped and logged.
- Invalid JSON lines are dropped and logged; the plugin keeps running.
- A field of the wrong type is ignored (and logged); the rest of the line applies.

## Start from an example

Copy a bundled plugin and edit it:

```sh
mkdir -p ~/.config/hyprland-darwin/plugins
cp -R /Applications/HyprDarwin.app/Contents/Resources/bundled-plugins/example ~/.config/hyprland-darwin/plugins/mywidget
```

Then add `'mywidget'` to a `[bar]` section and save.
