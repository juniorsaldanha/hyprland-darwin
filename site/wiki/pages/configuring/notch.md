# Notch panel

On a MacBook with a notch, the camera housing sits where the bar's center would be. The notch panel uses that space: a black panel under the notch that shows widgets while your mouse is over the notch.

```toml
[notch]
    items = ['clock', 'battery']
```

- `items` takes [plugin](#/plugins/using) names, like the bar's sections. The built-in `workspaces` and `front-app` widgets aren't shown there.
- It needs the bar to be enabled.
- On a screen without a notch, or with `items = []`, there's no panel.
- The panel appears while the mouse is in the notch strip or over the panel itself.

> [!TIP]
> On notched screens, leave `center` empty in `[bar]`. The notch would hide it.
