#!/usr/bin/env bash
# Integration tests: things that cross a real boundary (files, processes, binaries, the app bundle).
#   script/test-integration.sh                         XCTest *IntegrationTest classes + debug CLI binary
#   script/test-integration.sh --app <HyprDarwin.app>  also checks the built app bundle
# Expects ./build-debug.sh to have run (uses .debug/aerospace).
cd "$(dirname "$0")/.."
source ./script/setup.sh

app=""
skip_xctest=0
while test $# -gt 0; do
    case $1 in
        --app) app="$2"; shift 2 ;;
        --skip-xctest) skip_xctest=1; shift ;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

fail() { echo "❌ integration: $*" > /dev/stderr; exit 1; }

if test $skip_xctest = 0 && grep -rqE 'class [A-Za-z]+IntegrationTest\b' Sources/AppBundleTests; then
    swift test --filter IntegrationTest
fi

# CLI binary
cli=./.debug/aerospace
test -x "$cli" || fail "$cli missing, run ./build-debug.sh first"
"$cli" --help > /dev/null || fail "'$cli --help' failed"
"$cli" --version 2> /dev/null | grep -q "0.0.0-SNAPSHOT" || fail "'$cli --version' doesn't print the snapshot version"
"$cli" no-such-command > /dev/null 2>&1 && fail "'$cli no-such-command' must exit non-zero"

# hypr init / --undo: throwaway defaults domain + temp config dir (never the real settings)
init_domain="dev.hyprdarwin.test-init-$$"
init_home="$(mktemp -d)"
cleanup_init() { /usr/bin/defaults delete "$init_domain" > /dev/null 2>&1 || true; rm -f "$HOME/Library/Preferences/$init_domain.plist"; rm -rf "$init_home"; }
trap cleanup_init EXIT
run_init() { HYPR_INIT_TEST_DOMAIN="$init_domain" XDG_CONFIG_HOME="$init_home" "$cli" init "$@" > /dev/null; }

/usr/bin/defaults write "$init_domain" expose-group-apps -bool false # an existing value to restore later
run_init || fail "'init' failed"
test -f "$init_home/hyprland-darwin/config.toml" || fail "init didn't write the starter config"
grep -q '"previous" : false' "$init_home/hyprland-darwin/setup-backup.json" || fail "backup missing the previous value"
test "$(/usr/bin/defaults read "$init_domain" _HIHideMenuBar)" = 1 || fail "init didn't apply _HIHideMenuBar"
echo "# mine" > "$init_home/hyprland-darwin/config.toml"
run_init || fail "second 'init' failed"
test "$(cat "$init_home/hyprland-darwin/config.toml")" = "# mine" || fail "init overwrote an existing config"
grep -q '"previous" : false' "$init_home/hyprland-darwin/setup-backup.json" || fail "second init lost the original backup"
run_init --undo || fail "'init --undo' failed"
test "$(/usr/bin/defaults read "$init_domain" expose-group-apps)" = 0 || fail "undo didn't restore expose-group-apps"
/usr/bin/defaults read "$init_domain" _HIHideMenuBar > /dev/null 2>&1 && fail "undo didn't delete a key that was unset"
test ! -f "$init_home/hyprland-darwin/setup-backup.json" || fail "undo didn't remove the backup"
# An unreadable backup must never be replaced: it holds the only copy of the original settings
echo '{"entries": [' > "$init_home/hyprland-darwin/setup-backup.json"
run_init 2> /dev/null && fail "init must refuse an unreadable backup"
run_init --undo 2> /dev/null && fail "init --undo must refuse an unreadable backup"
test "$(cat "$init_home/hyprland-darwin/setup-backup.json")" = '{"entries": [' || fail "init replaced an unreadable backup"
rm "$init_home/hyprland-darwin/setup-backup.json"
# A non-boolean value is left alone (not overwritten, not recorded, so undo can't delete it)
/usr/bin/defaults write "$init_domain" spans-displays -string keep-me
run_init 2> /dev/null || fail "init failed with a non-boolean value present"
test "$(/usr/bin/defaults read "$init_domain" spans-displays)" = keep-me || fail "init overwrote a non-boolean value"
grep -q spans-displays "$init_home/hyprland-darwin/setup-backup.json" && fail "init recorded a value it didn't change"
run_init --undo || fail "undo failed"
test "$(/usr/bin/defaults read "$init_domain" spans-displays)" = keep-me || fail "undo touched a non-boolean value"
# A setting stored as the integer 0/1 is a boolean to macOS: init applies it, undo restores it
/usr/bin/defaults delete "$init_domain" expose-group-apps > /dev/null 2>&1 # else the type stays boolean from the undo above
/usr/bin/defaults write "$init_domain" expose-group-apps -int 0
run_init 2> /dev/null || fail "init failed with an integer value present"
test "$(/usr/bin/defaults read "$init_domain" expose-group-apps)" = 1 || fail "init skipped a setting stored as the integer 0"
run_init --undo || fail "undo failed"
test "$(/usr/bin/defaults read "$init_domain" expose-group-apps)" = 0 || fail "undo didn't restore the integer setting"
# A missing wallpaper is an error (checked even in test mode, where the wallpaper itself is never changed)
run_init --wallpaper /nonexistent/wall.jpg 2> /dev/null && fail "init must reject a missing wallpaper"
/usr/bin/defaults read "$init_domain" _HIHideMenuBar > /dev/null 2>&1 && fail "a rejected wallpaper must not change any setting"
test ! -f "$init_home/hyprland-darwin/setup-backup.json" || fail "a rejected wallpaper must not write a backup"
# Test mode without a temp config dir must refuse: it would write the real ~/.config
HYPR_INIT_TEST_DOMAIN="$init_domain" XDG_CONFIG_HOME= "$cli" init > /dev/null 2>&1 && fail "test mode without XDG_CONFIG_HOME must refuse"
"$cli" --help | grep -q "^ *init " || fail "'init' missing from --help"

# App bundle
if test -n "$app"; then
    test -d "$app" || fail "$app doesn't exist"
    plist="$app/Contents/Info.plist"
    id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" || fail "can't read $plist"
    test "$id" = "dev.hyprdarwin" || fail "CFBundleIdentifier is '$id', expected 'dev.hyprdarwin'"
    test -x "$app/Contents/MacOS/HyprDarwin" || fail "missing executable Contents/MacOS/HyprDarwin"
    test -f "$app/Contents/Resources/default-config.toml" || fail "missing Contents/Resources/default-config.toml"
    test -x "$app/Contents/Resources/bundled-plugins/example/example.sh" || fail "missing bundled-plugins/example in the app bundle"
    test -f "$app/Contents/Resources/bundled-fonts/HackNerdFont-Bold.ttf" || fail "missing bundled-fonts in the app bundle"
    test -f "$app/Contents/Resources/bundled-fonts/LICENSE.md" || fail "the font license must ship with the font (Bitstream Vera / MIT)"
    codesign -v "$app" || fail "codesign verification failed for $app"
fi

echo "✅ Integration tests have passed successfully"
