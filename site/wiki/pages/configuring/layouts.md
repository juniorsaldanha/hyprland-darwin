# Layouts

HyprDarwin uses AeroSpace's **tree** layout. Every workspace is a tree of containers. Each container lays out its children either as **tiles** (side by side) or as an **accordion** (stacked, one big, the rest peeking out).

## Tiles

New windows split the space with their siblings, horizontally or vertically:

```toml
alt-slash = 'layout tiles horizontal vertical'   # switch to tiles, or flip the orientation
```

`default-root-container-orientation = 'auto'` picks horizontal on wide monitors and vertical on tall ones.

## Accordion

Like a stack or tabbed layout: the focused window gets most of the space, and the others show a sliver of `accordion-padding` pixels.

```toml
alt-comma = 'layout accordion horizontal vertical'
accordion-padding = 30
```

## Building the tree

| Command | Does |
|---|---|
| `move left` … | Move the window. At an edge, it leaves its container. |
| `join-with left` … | Put the window and its neighbour into a new container |
| `split horizontal` / `vertical` | Split the window's container |
| `flatten-workspace-tree` | Undo all nesting on the workspace |
| `balance-sizes` | Equal shares for every window |
| `resize smart +50` | Grow along the container's direction |

## Normalisation

These keep the tree tidy (both on by default in the starter config):

```toml
enable-normalization-flatten-containers = true
enable-normalization-opposite-orientation-for-nested-containers = true
```

## Floating

```toml
alt-v = 'layout floating tiling'
```

Floating windows sit above the tiles and keep their size. Use [window rules](#/configuring/window-rules) to float apps automatically.

## Fullscreen

- `fullscreen`: the window fills the workspace, and the bar and borders stay.
- `macos-native-fullscreen`: macOS's own fullscreen, in a separate Space.
