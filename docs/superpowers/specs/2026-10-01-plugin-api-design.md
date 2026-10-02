# Plugin API (sub-project 3) — Design

Date: 2026-10-01
Status: Approved in conversation (sections 1–3). The user asked to carry on through the remaining work without further approval stops.
Parent spec: `docs/superpowers/specs/2026-10-01-hyprland-darwin-design.md`, section 3 (Plugin protocol) and section 4 (Error handling → Plugins)

## Goal

A plugin host that runs user and bundled plugins as separate processes,
talks to them in JSON lines over stdin/stdout, and keeps each plugin's
widget state ready for the bar (sub-project 4). The user can already try
it with `hypr list-plugins`, and plugins can already drive HyprDarwin with
`{"run": "..."}`.

**Success criterion:**
1. A user plugin in `~/.config/hyprland-darwin/plugins/gpu/` that is listed in `[bar] right` shows as `running` in `hypr list-plugins`, with its latest label.
2. Killing it repeatedly shows restarts, then `stopped`.
3. Making it print `{"run":"workspace 2"}` focuses workspace 2.

## Scope

- **In:**
  - the manifest, plugin discovery, both modes (interval and stream)
  - events `workspace`, `focus`, `monitor` and `wake`
  - widget updates, `hidden` and `run`
  - the supervisor (backoff and stop), logs, process groups
  - reload sync, `hypr list-plugins`
  - one bundled `example` plugin
  - parsing of the placement lists only: `[bar] left/center/right`, `[notch] items`, `[plugins] dirs`
- **Moved to the Bar sub-project:**
  - the `click` event and `HYPR_EVENT`/`HYPR_BUTTON` for interval plugins
  - `popup` menus
  - the `power` event
  - the five bundled plugins (clock, battery, CPU, RAM, disk)
- **Built-in widget names** `workspaces` and `front-app` are reserved: the host skips them.

## Architecture

```
config.toml [bar] left/center/right, [notch] items, [plugins] dirs
        │
        ▼
PluginRegistry (pure) ── resolves names → folders (user dirs in order, then bundled); reads plugin.toml
        │
        ▼
PluginHost (@MainActor) ── one PluginProcess per resolved plugin; sync(config) on every reload
   ├─ PluginProcess : spawns the executable in its own process group, pipes, line reader (background queue)
   │     interval: run every N s, take the first line, kill after min(N, 5 s)
   │     stream:   long-lived; EventQueue (max 64, drop oldest) → stdin; stdout lines → host
   ├─ Supervisor (pure, injected clock) : restart delays 1,2,4…60 s; 5 exits within 60 s → stopped;
   │                                      interval: 3 failures in a row → failing
   └─ PluginLog : ~/Library/Logs/hyprland-darwin/<name>.log, trimmed to the newest 512 KB once over 1 MB
        │ each stdout line ──► decodePluginLine (pure) ──► .update(WidgetPatch) | .run(String) | .invalid(reason)
        │                                                     │                    └─► parseCommand → runLightSession
        │                                                     ▼
        │                                              WidgetStore (pure merge, @MainActor, observable)
        ▲
EventBus (Core) ──► encodePluginEvent (pure) ──► only to plugins that subscribe to that event
NSWorkspace.didWakeNotification ──► wake

hypr list-plugins [--json] ──► name, mode, status, restarts, current widget
```

## Formats

`plugin.toml`:

| Key | Type | Required | Rule |
|---|---|---|---|
| `api` | int | yes | must be `1` |
| `exec` | string | yes | relative to the plugin folder, or absolute; must exist and be executable |
| `mode` | `"interval"` \| `"stream"` | yes | |
| `interval` | int | interval mode only | ≥ 1 (seconds) |
| `events` | array of strings | no | each one of `workspace`, `focus`, `monitor`, `wake` (`click`/`power` arrive with the bar) |

Config (parsed now; the bar adds the rest of `[bar]` later):

```toml
[bar]
left = ['workspaces', 'front-app']
center = []
right = ['clock', 'gpu']
[notch]
items = []
[plugins]
dirs = ['~/.config/hyprland-darwin/plugins']   # default; '~' expands
```

Events on stdin (one JSON object per line):

```json
{"event":"workspace","focused":"2","prev":"1"}
{"event":"focus","app":"Arc","bundle":"company.thebrowser.Browser","workspace":"2"}
{"event":"monitor","workspace":"2","monitor":1}
{"event":"wake"}
```

Lines on stdout:
- **Widget fields:** `icon`, `label`, `color`, `icon_color`, `background` (strings) and `hidden` (bool). A line is a partial update merged into the widget.
- **Commands:** `{"run":"<command>"}`. `run` takes precedence if a line has both.

Environment given to each plugin:
- the same environment as `exec-and-forget`
- plus `HYPR_PLUGIN_NAME` and `HYPR_PLUGIN_DIR`
- the working directory is the plugin folder

Protocol rule: a stream plugin must exit when its stdin closes.

`hypr list-plugins` prints one line per plugin, `name | mode | status | restarts | label`. With `--json` it prints full objects.

Statuses:
- `running`
- `failing (n)`: an interval plugin that has failed n times in a row
- `restarting in Ns`
- `stopped: crashed 5 times within 60 s`
- `missing: no plugin folder in <dirs>`
- `invalid: <reason>`

## Error handling

As agreed in conversation (section 2), and as in the parent spec:

| Situation | Behavior |
|---|---|
| Missing folder | Status `missing` |
| Bad manifest or exec | Status `invalid: …` |
| Bad JSON or non-UTF-8 line | Line dropped, logged |
| Wrong field type | That field ignored, the rest applied |
| Unknown fields | Ignored |
| Line over 64 KB | Dropped, logged |
| `run` doesn't parse | Logged, not run |
| `run` while tiling is disabled | Not run, logged |
| Interval run too slow | Killed after `min(N, 5 s)`; 3 failures in a row → `failing`, keeps its schedule |
| Stream plugin exits | Backoff restart; 5 exits within 60 s → `stopped` until reload |
| Plugin not reading stdin | 64-event queue, oldest dropped, writes never block |
| Config reload | Removed → stopped; manifest changed → restarted; otherwise left running |
| Same name in two slots | One process |
| Quit | Every process group is killed |
| Crash | Stdin closes, and stream plugins exit by protocol |

All I/O runs off the main thread, and the main thread never waits on a
plugin.

## Testing

**Unit tests:**
- config lists
- manifest validation (each reason)
- registry resolution
- line decoding (each bad-input case)
- WidgetStore merging
- event encoding and filtering
- supervisor timing (injected clock)
- EventQueue capacity
- log trimming

**Integration tests (`PluginHostIntegrationTest`, real shell-script fixtures):**
- interval run, interval timeout
- stream echo
- crash → backoff → stopped (with a scaled-down clock)
- deaf plugin (1000 events, no blocking)
- garbage output
- `run` reaching a test hook
- stdin EOF → plugin exits
- reload (removed / changed / unchanged)

**CLI:** `hypr list-plugins --help`.

**Manual:** the success criterion steps.
