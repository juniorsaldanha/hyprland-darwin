# Contributing

Bug reports, ideas and pull requests are welcome.

## Reporting bugs and ideas

Open an [issue](https://github.com/juniorsaldanha/hyprland-darwin/issues/new/choose). For bugs, include:

- `hypr --version` and your macOS version
- the relevant part of your config
- `hypr debug-windows` output for window problems; `hypr list-plugins` and `~/Library/Logs/hyprland-darwin/` for the
  bar and plugins

## Code

- Requires Xcode and Swift 6.4. `make help` lists every target; `make ci` is what CI runs.
- Tests come with the change: unit tests in `Sources/AppBundleTests/`, and `*IntegrationTest` classes for anything that
  crosses a real boundary (files, processes, the CLI binary, the app bundle).
- Match the code around you: naming, comment density, file layout.
- One logical change per commit; the message says what and why.
- Tiling-core changes that aren't specific to HyprDarwin are often better sent upstream to
  [AeroSpace](https://github.com/nikitabobko/AeroSpace).

By contributing, you agree that your contributions are licensed under the MIT licence (`LICENSE.txt`).
