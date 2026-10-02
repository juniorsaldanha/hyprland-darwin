# Borders

HyprDarwin draws a ring around every tiled window: a bright one on the focused window and a dim one on the rest. It replaces JankyBorders.

```toml
[borders]
    enabled = true
    width = 5                                    # 1–50 px
    radius = 10                                  # 0–100 px, corner rounding
    active = 'gradient(0xff7aa2f7,0xffbb9af7)'   # focused window
    inactive = '0x80414868'                      # every other window
```

| Option | Default | Notes |
|---|---|---|
| `enabled` | `false` | The starter config turns it on |
| `width` | `5` | Ring thickness |
| `radius` | `10` | Match your apps' corners. macOS windows are about 10 |
| `active` | `gradient(0xff7aa2f7,0xffbb9af7)` | A colour or `gradient(a,b)`, top-left → bottom-right |
| `inactive` | `0x80414868` | A single colour. Use `0x00000000` to hide it |

## Recipes

```toml
# Cyberpunk
active = 'gradient(0xffff2bd6,0xff22e4ff)'
inactive = '0x40b44bff'

# Only the focused window
inactive = '0x00000000'

# Tokyo Night (the default)
active = 'gradient(0xff7aa2f7,0xffbb9af7)'
inactive = '0x80414868'
```

## How it behaves

- Rings follow windows as they move, resize and change workspace.
- A ring stays directly behind its window, so another window on top covers it.
- Rings are redrawn sharp when a display switches between Retina and non-Retina scaling.
- Floating windows get rings too. Windows in `fullscreen`, minimised and hidden windows don't.
