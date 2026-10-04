# hyprland-darwin — Design

Date: 2026-10-01
Status: Implemented (v0.2.2). Where the code differs, the sub-project specs and the README win.

## Goal

One macOS app that gives a Hyprland-like experience and replaces today's
stack of separate tools:

| Today | Replaced by |
|---|---|
| Hyprspace.app (AeroSpace fork) | Core (forked AeroSpace) |
| JankyBorders (`borders`) | Built-in borders |
| SketchyBar + 8 shell plugins | Built-in bar + bundled plugins |
| `cursor_monitor.swift` (30 ms polling) | Bar auto-hide via mouse event monitor |
| `hyprspace init` | `hypr init` setup command |

**Success criterion:** copy the current `~/.config/hyprspace/config.toml`
over, uninstall Hyprspace, SketchyBar and JankyBorders, and keybinds,
gaps, the gradient border and every bar widget work as they do today.

### Constraints

- Swift, macOS 27, arm64. Builds with the installed Xcode / Swift 6.4.
- No SIP changes and no private-framework injection (same stance as AeroSpace).
- One `.app`, one process, one config file.

### Non-goals (v1)

- Hyprland animations, blur on app windows, shaders, dwindle layout.
  macOS doesn't let third-party apps control the window compositor.
- Hyprland `.conf` syntax.
- Plugin sandboxing, marketplace or remote install.
- Reading other apps' macOS notifications (there's no public API for it).

## Decomposition

Five sub-projects, built in this order. Each gets its own implementation
plan and ends with a manual checklist.

1. **Core**: fork AeroSpace, add the EventBus and the Permissions window.
2. **Borders**: focused/unfocused window borders.
3. **Plugin API**: PluginHost and the protocol.
4. **Bar**: status bar, native widgets, bundled plugins.
5. **Setup**: the `hypr init` command and `init --undo`.

## 1. Architecture

```
┌──────────────────────── HyprDarwin.app ────────────────────────┐
│  AeroSpace core (unchanged)  ── tiling, workspaces, keybinds   │
│        │ emits                                                 │
│        ▼                                                       │
│   EventBus (new) ── workspace / focus / window-frame / monitor │
│     │            │                 │                           │
│     ▼            ▼                 ▼                           │
│  Borders      Bar (per monitor)   PluginHost ◄─stdin/stdout─► plugin executables
│  overlay      NSPanel + blur        spawns, restarts,   JSON lines
│  windows      widgets               routes events               │
│                                                                │
│  Permissions window · menu-bar icon · CLI (`hypr …`)           │
└────────────────────────────────────────────────────────────────┘
```

### Fork

- Clone AeroSpace into this repo and keep an `upstream` remote so
  upstream fixes can be merged in. Check the license is MIT at fork time
  and keep the original LICENSE and attribution.
- Hyprspace compatibility: the current config uses two Hyprspace-only
  features that upstream AeroSpace rejects (verified by parsing it):
  the `[mouse-drag]` section (modifier + drag moves a window) and the
  `new-window-or-open <app>` command. Both are added in the Core
  sub-project.
- Keep changes to AeroSpace's own files small. New code lives in new
  files and modules, so merges from upstream stay cheap.
- Working name `hyprland-darwin`. App: `HyprDarwin.app`. CLI: `hypr`.
  Config directory: `~/.config/hyprland-darwin/`.

### EventBus

The one new seam in the core. AeroSpace's existing hooks
(`exec-on-workspace-change`, `on-focus-changed`,
`on-focused-monitor-changed`, window detection) also publish typed events
in-process:

| Event | Payload |
|---|---|
| `workspace` | `focused`, `prev` |
| `focus` | `app`, `bundle`, window id, frame |
| `window-frame` | window id, frame (after layout or drag) |
| `monitor` | monitor list changed |
| `wake`, `power` | system wake; power source |

Subscribers: Borders, Bar, PluginHost. Events are delivered on the main
thread to Borders and Bar. PluginHost moves them off the main thread
immediately.

### Borders

- One transparent, click-through, borderless window per bordered app
  window. It draws a rounded stroke (solid color or two-stop gradient)
  around the target's frame.
- The overlay follows `focus` and `window-frame` events. Active and
  inactive colors come from config.
- **Risk:** keeping the overlay stacked directly above its target window
  with public APIs only. JankyBorders relies on private SkyLight APIs for
  this. The borders sub-project **starts with a spike** to test it. If
  stacking can't be made reliable, the fallback is a border on the
  focused window only, placed at a level above normal windows.

### Bar

- One non-activating panel per monitor, with `NSVisualEffectView` blur,
  at a level above normal windows. Height and colors come from config.
- `[gaps] outer.top` stays user-controlled, the same as today.
- Auto-hide uses a global mouse-move event monitor with the same
  thresholds as today (hide ≤ 8 px from the top, show > 24 px). No polling.
- Hiding the system menu bar is done by Setup, not by the bar.
- **Native widgets** (they need core state): `workspaces`, `front-app`.
- **Bundled plugins** (ported from the current shell scripts): `clock`,
  `battery`, `cpu`, `ram`, `disk`, `gpu`, `network`, `volume`.

### Notch panel

A panel that drops from the notch on screens that have one. It holds
plugin widgets listed in `[notch] items`. It uses the same widget model
as the bar. It is built in the Bar sub-project after the bar works.

### Permissions window

| Permission | Required | Why |
|---|---|---|
| Accessibility | Yes | Reading, moving and resizing windows |
| Input Monitoring | Not requested unless the `mouse-drag` event tap fails with Accessibility granted | `focus-follows-mouse` uses an `NSEvent` mouse-moved monitor, which needs no permission (verified in AeroSpace's source). `mouse-drag` uses an active event tap, which Accessibility covers. |
| Notifications | Optional | Posting the "permission missing" alert |

Screen Recording isn't requested.

Behavior:

- **First launch, or any launch with a required permission missing:**
  the window opens. Each row shows the permission name, a one-line
  reason, a live ✓/✗ status and an **Open Settings** button that
  deep-links to the matching System Settings pane.
- **Status re-check:** every 1 s, only while the window is open. When all
  required permissions are granted, the window shows "All set" and
  tiling starts. If macOS keeps reporting the old state after a grant,
  the window shows a **Relaunch** button.
- **A permission is revoked while running, or the app starts at login
  without it:** tiling pauses and windows are left where they are. A
  macOS notification says "Accessibility permission needed — click to
  fix". Clicking it opens the Permissions window.
- **Notifications denied too:** the bar shows `⚠ permissions` and the
  menu-bar icon has a "Permissions…" item. Both open the window.

### Setup (`hypr init`)

It applies what `hyprspace init` does today, minus installing other tools:

- `spans-displays=true`, `expose-group-apps=true`,
  `NSAutomaticWindowAnimationsEnabled=false`
- Hide the system menu bar
- Set the wallpaper (optional)
- Write a starter config if none exists. It never overwrites an existing
  config.

Before each change, the previous value is saved to
`~/.config/hyprland-darwin/setup-backup.json`. `hypr init --undo`
restores those values.

The Hack Nerd Font is bundled inside the app and registered for the
process only, so nothing is installed system-wide.

## 2. Configuration

A single `~/.config/hyprland-darwin/config.toml`. It uses AeroSpace's
format and parser unchanged, plus four new sections:

```toml
# ...all existing AeroSpace/Hyprspace keys work as-is...

[borders]
width = 5
radius = 10
active = 'gradient(0xff7aa2f7,0xffbb9af7)'   # or a single 0xAARRGGBB
inactive = '0x80414868'

[bar]
enabled = true
height = 40
color = '0x40000000'
blur = true
font = 'Hack Nerd Font'
auto-hide = true
left   = ['workspaces', 'front-app']
center = []
right  = ['clock', 'battery', 'cpu', 'ram', 'disk']

[notch]
items = []

[plugins]
dirs = ['~/.config/hyprland-darwin/plugins']   # searched before bundled plugins
```

The `after-startup-command` line that launches `borders` and the
`exec-on-workspace-change` line that triggers SketchyBar are no longer
needed. They still parse and run if present.

## 3. Plugin protocol

### Layout

```
~/.config/hyprland-darwin/plugins/<name>/
  plugin.toml
  <executable>
```

Bundled plugins ship in `HyprDarwin.app/Contents/Resources/plugins/`. A
user plugin with the same name overrides the bundled one.

### Manifest

```toml
api = 1                 # protocol version; unknown versions are refused
exec = "./gpu.sh"       # path relative to the plugin folder
mode = "interval"       # "interval" | "stream"
interval = 2            # seconds; interval mode only
events = ["workspace", "click"]   # optional
```

Where a plugin appears is set only in `config.toml` (`[bar] left/center/right`,
`[notch] items`), never in the manifest.

### Transport

Newline-delimited JSON over the plugin's stdin and stdout. The plugin's
stderr goes to its log file.

- **interval:** the app runs the executable every `interval` seconds and
  reads the first line of stdout. The app sends no events in this mode,
  except that a subscribed `click` triggers an extra immediate run with
  env `HYPR_EVENT=click` and `HYPR_BUTTON=<button>`.
- **stream:** the app starts the executable once and keeps it running.
  Events go in on stdin and updates come out on stdout.

### App → plugin

```json
{"event":"workspace","focused":"2","prev":"1"}
{"event":"focus","app":"Arc","bundle":"company.thebrowser.Browser"}
{"event":"click","button":"left"}
{"event":"monitor"}
{"event":"wake"}
{"event":"power","source":"ac"}
```

Only events listed in `events` are sent.

### Plugin → app

Each line is a partial update merged into the plugin's widget:

```json
{"icon":"󰢮","label":"42%","color":"0xffe1e1e1"}
{"hidden":true}
{"popup":[{"label":"GPU 42%"},{"label":"VRAM 3.1G"}]}
{"run":"workspace 2"}
```

Widget fields: `icon`, `label`, `color`, `icon_color`, `background`,
`hidden`, `popup`. `run` executes any AeroSpace command, the same as a
keybinding. The app does all drawing; plugins can't draw arbitrary UI.

### Trust

Plugins run with the user's permissions, the same as SketchyBar scripts
do today. Installing a plugin means putting its folder in place.

## 4. Error handling

**Rule:** plugins, borders and the bar never stall or crash tiling.
Plugin I/O happens off the main thread, and the core never waits on any
subscriber.

### Config

- AeroSpace's behavior is kept: a bad config is rejected, the error is
  shown and the last good config stays active. The new sections go
  through the same parser.
- If the bar or notch lists a plugin that doesn't exist, that slot shows
  `⚠ <name>` with the reason on hover. Everything else renders.

### Plugins

| Failure | Behavior |
|---|---|
| Missing/invalid `plugin.toml`, unknown `api` | Skipped; `⚠ <name>` widget; reason logged |
| Invalid JSON line | Dropped and logged; widget keeps its last value |
| Interval run too slow | Killed after `min(interval, 5s)`; last value kept; 3 consecutive failures → `⚠` |
| Stream plugin exits | Restart with backoff 1, 2, 4 … 60 s; 5 crashes within 60 s → stopped and `⚠` until config reload |
| Plugin not reading stdin | Bounded queue (64 events); oldest dropped; writes never block |
| App quits | Plugin process group terminated |

- Logs: `~/Library/Logs/hyprland-darwin/<plugin>.log`, cut down when over 1 MB.

### Borders

If the target window's frame can't be read (closed, native fullscreen,
Accessibility error), its border is hidden. It comes back on the next
`focus` or `window-frame` event. There's no retry loop.

### Permissions

See the Permissions window section above. While Accessibility is
missing, tiling and borders are paused. The bar and plugins keep
running, and the `workspaces` widget shows `⚠`.

### Setup

Each changed default is backed up before it is written. If the backup
write fails, that change is skipped.

## 5. Testing

All automated tests run with `swift test` and don't need real windows.

| Area | Tests |
|---|---|
| Inherited | AeroSpace's existing suite must pass on every change and after every upstream merge |
| Config | Parsing the new sections, valid and invalid. The user's current `config.toml` is a fixture and must keep parsing. |
| EventBus | Commands run through AeroSpace's test harness (`workspace 2`, `focus left`, `move-node-to-workspace`) emit the expected events |
| Plugin protocol | JSON-line decoding and partial-update merging (unknown fields, wrong types, `hidden`, `popup`, `run`) |
| PluginHost | Real processes from small shell-script fixtures: interval, stream, crash → backoff → stop, timeout, garbage output, plugin that never reads stdin. The clock is injected so backoff runs instantly. |
| Geometry | Border frame from window frame plus width; bar layout; conversion between Accessibility (top-left origin) and AppKit (bottom-left origin) coordinates across multiple monitors |
| Permissions | Decision logic (required set from config, all-granted → start, revoked → pause + notify) with the permission checks faked |
| Setup | `init` and `init --undo` against a throwaway `defaults` domain |

### Manual checklists (end of each sub-project)

- **Core:** fresh install → Permissions window → grant → tiling starts;
  revoke Accessibility while running → pause + notification → re-grant
  → resumes.
- **Borders:** border follows a dragged window, survives a workspace
  switch, hides in native fullscreen, works on both monitors.
- **Plugin API:** a sample GPU plugin in interval mode and in stream mode;
  killing the stream plugin shows the restart behavior.
- **Bar:** a bar on each monitor, auto-hide at the top edge, the
  workspaces widget follows `alt-1…0`, clicking a workspace switches to it.
- **Setup:** `init` then `init --undo` restores the previous defaults.

### Final acceptance

The success criterion stated in the Goal section.
