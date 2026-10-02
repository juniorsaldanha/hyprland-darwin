# Gaps

```toml
[gaps]
    inner.horizontal = 10    # between windows, side by side
    inner.vertical =   10    # between windows, stacked
    outer.left =       14    # between windows and the screen edges
    outer.bottom =     14
    outer.right =      14
    outer.top =        [{ monitor."built-in" = 14 }, 44]
```

All values are pixels.

## Leave room for the bar

The bar is `40` px tall by default. Set `outer.top` to at least the bar's height plus a little, or windows tile under it. The starter config uses `44`.

## Per-monitor values

Any gap can be a list: rules first, then a default:

```toml
outer.top = [{ monitor."built-in" = 14 }, { monitor.'^LG' = 60 }, 44]
```

- `monitor."built-in"` matches the MacBook screen. A notched screen already reserves the menu-bar strip, so it needs less.
- `monitor.'<regex>'` matches the display name.
- `monitor.main` and `monitor.secondary` also work.
- The last item, a plain number, is the default.

## No gaps

```toml
[gaps]
    inner.horizontal = 0
    inner.vertical = 0
    outer.left = 0
    outer.bottom = 0
    outer.right = 0
    outer.top = 0
```
