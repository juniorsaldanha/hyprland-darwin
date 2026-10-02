#!/usr/bin/env bash
# Builds HyprDarwin.app (release) and the CLI into .release/, then installs them:
#   HyprDarwin.app -> /Applications
#   CLI            -> ~/.local/bin/hypr
# --no-install: only build (CI).
# --version <x.y.z>: version shown by `hypr --version` and in the app (default 0.0.0-SNAPSHOT); also stamps the git hash.
# Signing identity: $HYPRDARWIN_CODESIGN_IDENTITY, default 'hyprdarwin-codesign-certificate'.
# A stable identity keeps the Accessibility permission across rebuilds. '-' = ad-hoc (CI).
set -euo pipefail
cd "$(dirname "$0")"
source ./script/setup.sh

install=1
generate_args=(--ignore-cmd-help)
while test $# -gt 0; do
    case $1 in
        --no-install) install=0; shift ;;
        --version) generate_args+=(--build-version "$2" --generate-git-hash); shift 2 ;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

identity="${HYPRDARWIN_CODESIGN_IDENTITY:-hyprdarwin-codesign-certificate}"
if test "$identity" != "-" && ! security find-identity -p codesigning | grep -qF "\"$identity\""; then
    echo "No code-signing identity '$identity' in your keychain." > /dev/stderr
    echo "Create it: Keychain Access → Certificate Assistant → Create a Certificate… (Name: $identity, Self Signed Root, Code Signing)," > /dev/stderr
    echo "or build ad-hoc with HYPRDARWIN_CODESIGN_IDENTITY=- (Accessibility permission then resets on every rebuild)." > /dev/stderr
    exit 1
fi

./generate.sh "${generate_args[@]}"
# Universal (Apple Silicon + Intel), like the app. A plain `swift build` targets only this machine's architecture.
cli_build_args=(-c release --product aerospace --arch arm64 --arch x86_64)
swift build "${cli_build_args[@]}"
# setup.sh's swift() wrapper prints `swift --version` first; the bin path is the last line
cli_bin="$(swift build "${cli_build_args[@]}" --show-bin-path | tail -n 1)/aerospace"

(
    cd xcode
    xcodebuild -quiet clean build \
        -scheme AeroSpace \
        -destination "generic/platform=macOS" \
        -configuration Release \
        -derivedDataPath .xcode-build \
        CODE_SIGN_IDENTITY="$identity"
)

rm -rf .release && mkdir .release
cp -R xcode/.xcode-build/Build/Products/Release/HyprDarwin.app .release/
cp "$cli_bin" .release/hypr
codesign -f -s "$identity" .release/hypr

if test $install = 0; then
    echo "Built .release/HyprDarwin.app and .release/hypr"
    exit 0
fi

osascript -e 'quit app "HyprDarwin"' 2> /dev/null || true
rm -rf /Applications/HyprDarwin.app
cp -R .release/HyprDarwin.app /Applications/
mkdir -p ~/.local/bin
cp .release/hypr ~/.local/bin/hypr

echo "Installed /Applications/HyprDarwin.app and ~/.local/bin/hypr"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "Add ~/.local/bin to PATH to use 'hypr'" ;; esac
