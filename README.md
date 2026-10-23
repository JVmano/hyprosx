# HyprOSX

A lightweight tiling window manager for macOS that follows the behavior and config language of [Hyprland](https://github.com/hyprwm/Hyprland): dwindle, master and monocle layouts, workspaces, window rules, animated window motion, borders, dimming and mouse binds.

## Why

I used to use [AeroSpace](https://github.com/nikitabobko/AeroSpace), but the lack of performance and cool effects made me create this personal project.

## Usage

Requirements: macOS 14 or later and Xcode (Swift 6 toolchain).

```sh
scripts/build-app.sh --install
```

This builds `~/Applications/HyprOSX.app` and links the `hyprctl` CLI to `~/.local/bin/hyprctl`.

1. Copy a config: `mkdir -p ~/.config/hyprosx && cp config/owner/*.conf ~/.config/hyprosx/`
2. Open `~/Applications/HyprOSX.app` and grant Accessibility access when macOS asks.
3. Edit `~/.config/hyprosx/hyprland.conf`. HyprOSX reloads it on save.
4. Use `hyprctl` like in Hyprland, for example `hyprctl dispatch workspace 2` or `hyprctl configerrors`.

Optional: `scripts/make-signing-identity.sh` creates a local signing identity, so macOS keeps the Accessibility grant across rebuilds.

## Credits

See [NOTICE](NOTICE) for the code ported from AeroSpace (MIT) and the Hyprland reference (BSD-3-Clause).
