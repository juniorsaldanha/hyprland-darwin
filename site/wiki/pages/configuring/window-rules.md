# Window rules

Window rules (Hyprland's `windowrule`) run commands when a window first appears. Each rule is an `[[on-window-detected]]` table.

```toml
[[on-window-detected]]
    if.app-id = 'com.apple.systempreferences'
    run = 'layout floating'
```

## Matching

| Condition | Matches |
|---|---|
| `if.app-id` | The app's bundle id, exactly |
| `if.app-name-regex-substring` | A regex anywhere in the app name |
| `if.window-title-regex-substring` | A regex anywhere in the window title |
| `if.workspace` | The workspace the window appeared on |
| `if.during-aerospace-startup` | `true` only for windows found when HyprDarwin starts, `false` only for windows opened later |

All conditions in a rule must match. Leave them all out to match every window.

> [!TIP]
> Find an app's id with `hypr list-apps`, or `osascript -e 'id of app "Arc"'`.

## Actions

`run` is one command or a list. Commands that make sense here:

```toml
[[on-window-detected]]
    if.app-id = 'com.tinyspeck.slackmacgap'
    run = 'move-node-to-workspace 9'          # always open Slack on workspace 9

[[on-window-detected]]
    if.window-title-regex-substring = 'Picture-in-Picture'
    run = 'layout floating'

[[on-window-detected]]
    if.app-name-regex-substring = 'Finder'
    run = ['layout floating', 'move-node-to-workspace 4']
```

## Order

Rules run top to bottom, and the first match wins. Add `check-further-callbacks = true` to a rule to keep checking the rules after it.
