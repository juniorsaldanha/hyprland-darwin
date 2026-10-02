# Installation

HyprDarwin runs on **macOS 13 Ventura or newer**, on Apple Silicon and Intel Macs.

## Homebrew (recommended)

```sh
brew tap juniorsaldanha/hyprland-darwin https://github.com/juniorsaldanha/hyprland-darwin
brew install --cask hyprdarwin
```

This installs:

- `HyprDarwin.app` in `/Applications`
- the `hypr` CLI
- shell completion for zsh, bash and fish
- man pages: `man hypr`, `man hypr-workspace`, …

Upgrade with `brew upgrade --cask hyprdarwin`. Uninstall with `brew uninstall --cask hyprdarwin`. Add `--zap` to also delete your config and logs.

> [!NOTE]
> The tap needs the URL because the repository isn't named `homebrew-…`.

> [!WARNING]
> Releases are signed **ad hoc**, not with an Apple Developer ID. The cask clears macOS's quarantine flag so the app opens. Because of the ad-hoc signature, macOS asks for **Accessibility permission again after every upgrade**. Remove HyprDarwin from the Accessibility list and add it back.

## Release zip

Download `HyprDarwin-<version>.zip` from the [latest release](https://github.com/juniorsaldanha/hyprland-darwin/releases/latest) and unzip it. Then:

```sh
mv HyprDarwin.app /Applications/
xattr -dr com.apple.quarantine /Applications/HyprDarwin.app
mkdir -p ~/.local/bin && cp hypr ~/.local/bin/ && xattr -d com.apple.quarantine ~/.local/bin/hypr
```

The zip also contains `shell-completion/` and `manpage/` if you want to install those by hand.

## From source

You need Xcode and Swift 6.4.

```sh
git clone https://github.com/juniorsaldanha/hyprland-darwin
cd hyprland-darwin
make app-install   # HyprDarwin.app → /Applications, CLI → ~/.local/bin/hypr
```

`make app-install` signs with a self-signed certificate named `hyprdarwin-codesign-certificate`, so the Accessibility permission survives rebuilds. Create it once:

1. Open **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name: `hyprdarwin-codesign-certificate`, Identity Type: **Self Signed Root**, Certificate Type: **Code Signing**.

Or skip the certificate and build ad hoc with `HYPRDARWIN_CODESIGN_IDENTITY=- make app-install`. Accessibility then resets on every rebuild.

## Next

Continue with the [Master tutorial](#/getting-started/master-tutorial).
