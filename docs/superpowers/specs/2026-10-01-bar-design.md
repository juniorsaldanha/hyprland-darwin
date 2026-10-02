# Bar (sub-project 4) — Design

Date: 2026-10-01
Status: Approved. The user asked to carry on through all remaining work without approval stops, so the decisions below are mine, made against the user's current SketchyBar setup.
Parent spec: `docs/superpowers/specs/2026-10-01-hyprland-darwin-design.md` (section 1: Bar, Notch panel; section 3: plugin protocol)
Builds on: `docs/superpowers/specs/2026-10-01-plugin-api-design.md`

## Goal

A built-in status bar that replaces SketchyBar and the user's 10 shell
plugins (`~/.config/sketchybar`, as of 2026-10-01 06:40). It also adds a
notch panel.

**Success criterion:**
1. With `exec-on-workspace-change` removed and a `[bar]` section added, SketchyBar quit, and HyprDarwin's menu bar hiding already in place, the bar looks and behaves like today's SketchyBar bar.
2. The left side shows workspace pills, a chevron and the front app.
3. The right side shows, left to right: disk, ram, gpu, cpu, network, volume, battery, clock.
4. Auto-hide at the top edge works.
5. Clicking a workspace pill switches to that workspace.

## What the user has today (the reference)

| Item | Source | Behavior |
|---|---|---|
| Bar | `sketchybar --bar topmost=window height=40 blur_radius=30 color=0x40000000` | On every display, above windows |
| Defaults | icon `Hack Nerd Font:Bold:17`, label `Hack Nerd Font:Bold:14`, colour `0xe1e1e1e1`, padding 5 on each side, icon padding 8/4 | |
| Workspaces | `space.<n>`: icon = name; background `0x40ffffff`, radius 5, height 25, shown only when focused; click → `workspace <n>` | |
| Chevron | icon U+F054 | static |
| Front app | label = focused app name | updated on `front_app_switched` |
| Auto-hide | Swift script polls the mouse every 30 ms; hides the bar ≤ 8 px from the top and shows it again > 24 px away | |
| clock | every 10 s, icon U+F43A, `date '+%d/%m %H:%M'` | |
| battery | every 120 s, plus `system_woke` and `power_source_change`; icon U+F240…U+F244 by level with level colours; U+F0084 on AC | |
| volume | `volume_change` (level in `$INFO`); icon U+F057E/U+F0580/U+F057F/U+F0581 by level | |
| network | every 30 s, plus `wifi_change` and `system_woke`; icon U+F05A9 Wi-Fi / U+F0200 wired / U+F05AA offline; label = IP | |
| cpu | every 2 s, icon U+F4BC, `top -l 2 -s 1` user+sys | |
| gpu | every 1 s, icon U+F08AE, `ioreg` Device Utilization % | |
| ram | every 3 s, icon U+E266, (active+wired)/memsize | |
| disk | every 30 s, icon U+F02CA, free % of the Data volume | |

## Configuration

`[bar]` grows from placement-only (Plugin API) to:

```toml
[bar]
enabled = false                 # default false; the user's config sets true
height = 40
color = '0x40000000'            # tint over the blur
blur = true
font = 'Hack Nerd Font'         # falls back to the system font if missing
icon-size = 17
label-size = 14
foreground = '0xe1e1e1e1'       # default icon/label color
auto-hide = true
left = ['workspaces', 'chevron', 'front-app']
center = []
right = ['disk', 'ram', 'gpu', 'cpu', 'network', 'volume', 'battery', 'clock']   # displayed left → right
```

- Built-in widgets: `workspaces`, `front-app` and `chevron` (a static U+F054 icon). Every other name is a plugin.
- `[notch] items = [...]`: plugin widgets for the notch panel (see below).
- The shipped default config documents `[bar]` with `enabled = false`, the same as `[borders]`.
- Limits: `height` 16–100, `icon-size` and `label-size` 6–48. Colours use `0xAARRGGBB`.

## Protocol additions (plugin API v1, backwards compatible)

- **New events:** `click`, `power`, `volume`.

  ```json
  {"event":"click","button":"left"}
  {"event":"power","source":"ac"}
  {"event":"volume","level":42}
  ```

  `source` is `ac` or `battery`. `button` is `left` or `right`.
- **Interval plugins and events:** a subscribed event triggers an immediate extra run. The run gets `HYPR_EVENT=<kind>` and `HYPR_EVENT_JSON=<the event line>`; a click also gets `HYPR_BUTTON=<button>`. A run already in progress means the trigger is skipped.
- **Popup:** `{"popup":[{"label":"…","run":"…"}]}` sets the widget's popup items; `[]` clears them.
  - Clicking a widget that has popup items opens a menu instead of sending `click`.
  - Choosing an item runs its `run` command, if it has one.

## Architecture

```
TrayMenuModel.workspaces ─┐                      PluginHost.store (widgets) ─┐
EventBus focus → frontApp ─┼─► BarModel (@MainActor, ObservableObject) ◄──────┘
config.bar ───────────────┘        │  barItems(config, workspaces, frontApp, widgets) ← pure
                                   ▼
BarController: one BarPanel per NSScreen (sync on screen change / config reload)
   BarPanel: borderless non-activating NSPanel, level .statusBar, all Spaces, top of the screen frame
             NSVisualEffectView (behind-window blur) + tint + NSHostingView(BarView)
   BarView (SwiftUI): HStack(left) · Spacer · center · Spacer · HStack(right)
             tap workspace pill → focus workspace;  tap plugin → popup menu or PluginHost.click
AutoHide: global + local mouse-moved monitors → AutoHideState (pure hysteresis 8/24 px) → panel alpha
NotchPanel: screens with a notch (safeAreaInsets.top > 0) and non-empty [notch] items:
             black panel under the notch, shown while the mouse is in the notch strip or over the panel
SystemEvents: IOKit power-source notification → power;  CoreAudio default-output volume listener → volume
```

### Units

- **Pure:**
  - `barItems(...)` → `[BarSection: [BarItem]]`
  - `parseArgb` (from Borders) and `nsColor(argb:)`
  - `AutoHideState`
  - `notchRect(screenFrame:auxLeft:auxRight:)`
  - `popup` decoding
  - interval trigger env building
- **AppKit/SwiftUI:** `BarPanel`, `BarView`, `NotchPanel`, `BarController`.
- **System:** `PowerSource` (IOKit) and `VolumeListener` (CoreAudio). Each one calls `PluginHost.shared.send`.

### Bundled plugins

`bundled-plugins/{clock,battery,volume,network,cpu,gpu,ram,disk}`: ports of the user's scripts. Each prints one JSON line (`icon`, `label`, `icon_color`), with the same intervals and events as the table above:

| Plugin | Events |
|---|---|
| battery | `wake`, `power` |
| volume | `volume`; reads `HYPR_EVENT_JSON`, and falls back to `osascript` on the first run |
| network | `wake` |

`docker_health` and `front_app.sh` aren't ported: the first is commented out in the user's config, and `front-app` is built in.

## Error handling

| Situation | Behavior |
|---|---|
| Font missing | System font at the same sizes |
| Bad colour strings in widget updates | That colour is ignored; the default is used |
| Plugin `missing`/`invalid` | The slot shows `⚠ <name>`, with the reason as a tooltip |
| Plugin `stopped` | The slot shows `⚠ <name>` with the reason |
| Plugin not reporting yet | The slot is empty, taking no width |
| Screens added or removed | One panel per screen, recreated on `didChangeScreenParameters` |
| Tiling disabled or paused | The bar stays visible: it's informational. Workspace clicks do nothing while tiling is disabled (same guard as the menu bar). |
| No notch, or `[notch]` empty | No notch panel |
| CoreAudio or IOKit registration fails | That event is never sent. Plugins still run on their intervals. Logged once. |

The bar never makes Accessibility calls. It reads model state only.

## Testing

**Unit tests:**
- `[bar]` keys and limits; the user's migrated config plus `[bar]` parses
- `barItems`: order and sections, workspace pills with focus, front app, hidden widgets skipped, empty widgets skipped, `⚠` for missing/invalid/stopped, the chevron
- colour parsing
- `AutoHideState` hysteresis
- `notchRect`
- popup decoding (valid, wrong types, clear with `[]`)
- the new event kinds in manifests and encoding
- interval trigger env

**Integration tests:**
- `PluginHostIntegrationTest` additions: click reaches a stream plugin; a subscribed event triggers an interval run with `HYPR_EVENT`/`HYPR_EVENT_JSON`/`HYPR_BUTTON`; popup items reach the store
- `BundledPluginsIntegrationTest`: every bundled plugin resolves, runs once and prints a valid JSON line with a non-empty label. Volume is checked with `HYPR_EVENT_JSON` set. Battery is skipped on machines with no battery.
- `BarPanelIntegrationTest`: one panel per screen, at the top of each screen's frame, at the configured height, level `.statusBar`, joining all Spaces, not activating

**Manual:** the success criterion steps, plus the notch panel on the built-in display.
