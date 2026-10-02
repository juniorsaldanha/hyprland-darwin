# Setup (sub-project 5) — Design

Date: 2026-10-02
Status: Approved. The user asked to carry on through all remaining work without approval stops.
Parent spec: `docs/superpowers/specs/2026-10-01-hyprland-darwin-design.md`, section 1 (Setup)

## Goal

`hypr init` replaces `hyprspace init` and needs no other tools.

1. It applies the macOS settings a tiling setup needs. Every previous value is saved first.
2. It writes a Hyprland-flavoured starter config if none exists.
3. It can optionally set a wallpaper.

`hypr init --undo` restores every saved setting.

The Hack Nerd Font ships inside the app and is registered for the app's own
process at startup. The bar's icons then work without installing the font.

**Success criterion:**
1. On a fresh account, `hypr init` followed by launching HyprDarwin gives tiling, borders, the bar with icons and a hidden menu bar.
2. `hypr init --undo` restores the four macOS settings to their earlier values.
3. Running `hypr init` twice keeps the *original* values in the backup.

## Settings

The same settings `hyprspace init` changed. On the user's machine they're already set.

| Domain | Key | Value | Why |
|---|---|---|---|
| `com.apple.spaces` | `spans-displays` | true | Displays share one Space. Needs a logout. |
| `com.apple.dock` | `expose-group-apps` | true | Mission Control groups windows by app |
| `NSGlobalDomain` | `NSAutomaticWindowAnimationsEnabled` | false | No window-open animation |
| `NSGlobalDomain` | `_HIHideMenuBar` | true | Hides the macOS menu bar; the HyprDarwin bar replaces it |

After applying or undoing, `init` restarts the Dock (`killall Dock`) and
posts `AppleInterfaceMenuBarHidingChangedNotification`, so the changes take
effect without a logout. `spans-displays` still needs one, and `init` says so.

## Design

- **Location:** the logic lives in `Common`, so both the CLI and the tests can use it. `hypr init` is handled in the CLI process itself, before argument parsing, so it works whether or not the app is running.
- **Pure functions:**
  - `initPlan(current:existingBackup:)` → the defaults to write, plus the backup to save.
    - A setting already at its target value isn't rewritten.
    - The backup keeps the value from the *first* init. Settings added in later versions are appended to it.
  - `undoPlan(backup)` → the defaults to write back. A setting that was unset before init is deleted instead.
- **I/O:** `DefaultsTool` wraps `/usr/bin/defaults` (`read`, `write -bool`, `delete`). For tests, `HYPR_INIT_TEST_DOMAIN` redirects every domain to a throwaway one, and the Dock restart and notification are skipped.
- **Backup file:** `${XDG_CONFIG_HOME:-~/.config}/hyprland-darwin/setup-backup.json`. This is JSON rather than the TOML the parent spec named: the CLI has no TOML dependency, and the file is only read by `init --undo`.
- **Backup first:** the backup is written before any setting changes. If writing it fails, `init` stops without changing anything. `--undo` deletes the backup once it has restored.
- **Starter config:** written to `config.toml` only if no file exists; an existing config is never overwritten. It's a generic version of the user's migrated config, with alt bindings, gaps, borders and the bar on. Personal apps are swapped for Terminal, Safari and Finder.
- **Wallpaper:** `--wallpaper <path>` sets it on every screen with `NSWorkspace.setDesktopImageURL`. No wallpaper image is bundled.
- **Font:** `bundled-fonts/HackNerdFont-Regular.ttf` and `-Bold.ttf` ship in the app's resources, with the license in `legal/`. They're registered at startup with `CTFontManagerRegisterFontsForURL(.process)`; "already registered" counts as success.

## Errors

| Situation | Behavior |
|---|---|
| Backup can't be written | `init` exits 1 and changes nothing |
| A `defaults write` fails | Reported; the other settings are still applied; exit 1 |
| `--undo` with no backup | "Nothing to undo", exit 0 |
| Wallpaper path missing or invalid | Reported, exit 1, after the settings have been applied |
| Font file missing (debug build outside the app) | Ignored; the system font fallback applies |

## Testing

- **Unit:** `initPlan` (writes only what differs; unset is recorded; an existing backup is kept; a new setting is appended), `undoPlan` (write back or delete), the starter config parses with no errors and enables bar, borders and mouse-drag, and the config-dir helper honours `XDG_CONFIG_HOME`.
- **Integration:**
  - `DefaultsToolIntegrationTest`: write, read and delete round-trip on a throwaway domain.
  - `FontRegistrationIntegrationTest`: the bundled fonts register, and `NSFont(name: "HackNerdFont-Bold")` resolves.
  - `script/test-integration.sh`: runs the real `.debug/aerospace init` and `init --undo` against a throwaway domain and a temp `XDG_CONFIG_HOME`. It checks the backup, the starter config, idempotence and undo. With `--app`, it also checks that the fonts are in the bundle.
- **Manual (the user):** `hypr init` on their machine changes nothing (Hyprspace already applied the settings), and its backup records those current values. `--undo` therefore restores what was there at the first `hypr init`, not the state before Hyprspace (Hyprspace kept no backup).
