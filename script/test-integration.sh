#!/usr/bin/env bash
# Integration tests: things that cross a real boundary (files, processes, binaries, the app bundle).
#   script/test-integration.sh                         XCTest *IntegrationTest classes + debug CLI binary
#   script/test-integration.sh --app <HyprDarwin.app>  also checks the built app bundle
# Expects ./build-debug.sh to have run (uses .debug/aerospace).
cd "$(dirname "$0")/.."
source ./script/setup.sh

app=""
while test $# -gt 0; do
    case $1 in
        --app) app="$2"; shift 2 ;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

fail() { echo "❌ integration: $*" > /dev/stderr; exit 1; }

if grep -rqE 'class [A-Za-z]+IntegrationTest\b' Sources/AppBundleTests; then
    swift test --filter IntegrationTest
fi

# CLI binary
cli=./.debug/aerospace
test -x "$cli" || fail "$cli missing, run ./build-debug.sh first"
"$cli" --help > /dev/null || fail "'$cli --help' failed"
"$cli" --version 2> /dev/null | grep -q "0.0.0-SNAPSHOT" || fail "'$cli --version' doesn't print the snapshot version"
"$cli" no-such-command > /dev/null 2>&1 && fail "'$cli no-such-command' must exit non-zero"

# App bundle
if test -n "$app"; then
    test -d "$app" || fail "$app doesn't exist"
    plist="$app/Contents/Info.plist"
    id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" || fail "can't read $plist"
    test "$id" = "dev.hyprdarwin" || fail "CFBundleIdentifier is '$id', expected 'dev.hyprdarwin'"
    test -x "$app/Contents/MacOS/HyprDarwin" || fail "missing executable Contents/MacOS/HyprDarwin"
    test -f "$app/Contents/Resources/default-config.toml" || fail "missing Contents/Resources/default-config.toml"
    test -x "$app/Contents/Resources/bundled-plugins/example/example.sh" || fail "missing bundled-plugins/example in the app bundle"
    codesign -v "$app" || fail "codesign verification failed for $app"
fi

echo "✅ Integration tests have passed successfully"
