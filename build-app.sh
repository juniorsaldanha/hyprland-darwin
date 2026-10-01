#!/usr/bin/env bash
# Builds HyprDarwin.app (release) and the CLI, installs them locally.
#   HyprDarwin.app -> /Applications
#   CLI            -> ~/.local/bin/hypr
# Signing identity: $HYPRDARWIN_CODESIGN_IDENTITY, default 'hyprdarwin-codesign-certificate'.
# A stable identity keeps the Accessibility permission across rebuilds.
set -euo pipefail
cd "$(dirname "$0")"
source ./script/setup.sh

identity="${HYPRDARWIN_CODESIGN_IDENTITY:-hyprdarwin-codesign-certificate}"

./generate.sh --ignore-cmd-help
swift build -c release --product aerospace
# setup.sh's swift() wrapper prints `swift --version` first; the bin path is the last line
cli_bin="$(swift build -c release --product aerospace --show-bin-path | tail -n 1)/aerospace"

(
    cd xcode
    xcodebuild -quiet clean build \
        -scheme AeroSpace \
        -destination "generic/platform=macOS" \
        -configuration Release \
        -derivedDataPath .xcode-build \
        CODE_SIGN_IDENTITY="$identity"
)

osascript -e 'quit app "HyprDarwin"' 2>/dev/null || true
rm -rf /Applications/HyprDarwin.app
cp -R xcode/.xcode-build/Build/Products/Release/HyprDarwin.app /Applications/

mkdir -p ~/.local/bin
cp "$cli_bin" ~/.local/bin/hypr
codesign -f -s "$identity" ~/.local/bin/hypr

echo "Installed /Applications/HyprDarwin.app and ~/.local/bin/hypr"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "Add ~/.local/bin to PATH to use 'hypr'";; esac
