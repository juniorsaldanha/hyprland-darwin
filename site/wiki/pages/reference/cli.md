# CLI

`hypr` talks to the running HyprDarwin app. Every command also works as a [keybinding](#/configuring/keybinds) value, without the `hypr` prefix.

```sh
hypr --help              # every command
hypr <command> --help    # one command
man hypr-workspace       # the full manual (Homebrew installs)
```

Shell completion for zsh, bash and fish is installed with Homebrew.

## HyprDarwin commands

| Command | Does |
|---|---|
| `hypr init [--undo] [--wallpaper <path>]` | Set up macOS and write a starter config. Works without the app running. See [Preconfigured setup](#/getting-started/preconfigured-setup). |
| `hypr list-plugins [--json]` | Plugin status and the latest widget state. See [Using plugins](#/plugins/using). |
| `hypr new-window-or-open <app>` | Focus the app and open a new window, or launch it |

## Windows and focus

| Command | Does |
|---|---|
| `focus left\|down\|up\|right` | Move focus |
| `focus --window-id <id>` | Focus a specific window |
| `move left\|down\|up\|right` | Move the focused window |
| `swap left\|…` | Swap with a neighbour |
| `close` | Close the window |
| `fullscreen` / `macos-native-fullscreen` | Fullscreen modes |
| `layout floating tiling` | Toggle floating |
| `resize smart +50` / `resize width -50` | Resize |
| `balance-sizes` | Equal sizes |

## Workspaces and monitors

| Command | Does |
|---|---|
| `workspace <name>` / `workspace next\|prev` | Switch workspace |
| `workspace-back-and-forth` | Previous workspace |
| `move-node-to-workspace <name>` | Send the window to a workspace |
| `summon-workspace <name>` | Bring a workspace to the current monitor |
| `focus-monitor next\|prev\|left\|…` | Focus another monitor |
| `move-node-to-monitor next\|…` | Send the window to another monitor |
| `move-workspace-to-monitor next\|…` | Send the workspace to another monitor |

## Querying

| Command | Prints |
|---|---|
| `list-workspaces --all` / `--focused` / `--monitor all` | Workspaces |
| `list-windows --all` / `--workspace focused` | Windows |
| `list-apps` | Running apps and their bundle ids |
| `list-monitors` | Monitors |
| `list-modes --current` | Binding modes |
| `config --get <key>` | A config value |
| `debug-windows` | Detailed window info, for bug reports |

Most `list-*` commands take `--format '%{window-id} %{app-name}'` and `--json`.

## Examples

```sh
# Focus the first Safari window
hypr list-windows --all --format '%{window-id} %{app-name}' | awk '/Safari/ {print $1; exit}' | xargs hypr focus --window-id

# Show the focused workspace in your prompt
hypr list-workspaces --focused

# Several commands at once
hypr workspace 2 && hypr layout accordion horizontal
```

The full command reference with every flag is in the man pages and the [AeroSpace command docs](https://nikitabobko.github.io/AeroSpace/commands).
