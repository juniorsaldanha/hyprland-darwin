# Status bar

One bar per screen, drawn by HyprDarwin itself. It replaces SketchyBar.

```toml
[bar]
    enabled = true
    left = ['workspaces', 'chevron', 'front-app']
    center = []
    right = ['disk', 'ram', 'gpu', 'cpu', 'network', 'volume', 'battery', 'clock']
```

## Options

| Option | Default | Notes |
|---|---|---|
| `enabled` | `false` | The starter config turns it on |
| `left` / `center` / `right` | `[]` | Widgets per section, shown left → right |
| `workspaces` | `'all'` | `'visible'`: only the workspace on each monitor, e.g. `1 │ 2` |
| `height` | `40` | 16–100 px |
| `color` | `'0x40000000'` | Tint over the blur |
| `blur` | `true` | Frosted-glass background |
| `font` | `'Hack Nerd Font'` | Bundled with the app |
| `icon-size` | `17` | 6–48 |
| `label-size` | `14` | 6–48 |
| `foreground` | `'0xe1e1e1e1'` | Default text and icon colour |
| `auto-hide` | `true` | Hide while the mouse is at the very top of the screen, so apps' own menus can show |

## Widgets

| Name | What |
|---|---|
| `workspaces` | A pill per workspace. Click one to go there |
| `chevron` | A `›` separator |
| `front-app` | The focused app's name |
| anything else | A [plugin](#/plugins/using) with that name |

## Workspaces: all or visible

```toml
workspaces = 'all'       # 1 2 3 4 5 9  — persistent, non-empty and visible workspaces
workspaces = 'visible'   # 1 │ 6        — one per monitor, left → right, focused highlighted
```

## Clicking

- **Workspace pill:** go to that workspace.
- **Plugin widget:** sends the plugin a `click` event, or opens its popup menu if it has one. A right-click sends `button: right`.
- **⚠ widget:** a plugin that failed. Click for the reason (click it to copy) and **Open log**.

## Auto-hide

With `auto-hide = true`, the bar slides away while the mouse is within 8 px of the top edge, so you can reach apps' menus (the macOS menu bar shows instead). It comes back once the mouse is 24 px down.

## Recipes

```toml
# Minimal
left = ['workspaces']
right = ['clock']

# Centered workspaces
left = ['front-app']
center = ['workspaces']
right = ['volume', 'battery', 'clock']

# Neon
color = '0x6014052b'
foreground = '0xfff0e8ff'
```
