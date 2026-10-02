# Bundled plugins

These ship inside the app, in `HyprDarwin.app/Contents/Resources/bundled-plugins/`. Put a folder with the same name in your plugins directory to override one.

| Name | Shows | Mode | Updates |
|---|---|---|---|
| `cpu` | CPU use (user + system), % | interval | every 2 s |
| `ram` | Memory in use (active + wired), % | interval | every 3 s |
| `gpu` | GPU use, % | interval | every 1 s |
| `disk` | Free space on the system volume, % | interval | every 30 s |
| `network` | IP address with a Wi-Fi or Ethernet icon, or `offline` | interval | every 30 s, and on wake |
| `volume` | Output volume, % | interval | every 60 s, and on every volume change |
| `battery` | Battery level, colour-coded; hidden on Macs without a battery | interval | every 120 s, on wake and on AC/battery change |
| `clock` | Time | interval | every 10 s |
| `example` | The focused workspace (a template for stream plugins) | stream | on every workspace change |

## The default lineup

The starter config places all of them except `example`:

```toml
[bar]
    left = ['workspaces', 'chevron', 'front-app']
    right = ['disk', 'ram', 'gpu', 'cpu', 'network', 'volume', 'battery', 'clock']
```

## Customising one

To change a bundled plugin, for example the clock format, copy it and edit your copy:

```sh
cp -R /Applications/HyprDarwin.app/Contents/Resources/bundled-plugins/clock ~/.config/hyprland-darwin/plugins/
```

Your copy wins over the bundled one, and it survives app upgrades.
