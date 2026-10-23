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

## Keybinds

These are the binds in `config/owner/hyprland.conf`. `⌥` is Option (`ALT` in the config). Change them in your `hyprland.conf`.

| Keys | Action |
|---|---|
| `⌥ H` / `J` / `K` / `L` | Focus the window to the left / down / up / right |
| `⌥ ⇧ H` / `J` / `K` / `L` | Move the window left / down / up / right |
| `⌥ =` / `⌥ -` | Grow / shrink the window by 50 pt |
| `⌥ ⇧ =` / `⌥ ⇧ -` | Make the window wider / narrower by 50 pt |
| `⌃ ⌥ H` / `L` | Make the window narrower / wider by 50 pt |
| `⌃ ⌥ K` / `J` | Make the window shorter / taller by 50 pt |
| `⌥ /` | Toggle the split direction |
| `⌥ ,` | Switch the workspace layout between dwindle and monocle |
| `⌥ F` | Maximize the window |
| `⌥ ⇧ F` | Fullscreen the window |
| `⌥ ⇧ Space` | Toggle floating |
| `⌥ P` | Toggle pseudo-tiling |
| `⌥ ⇧ Q` | Close the window |
| `⌥ 1` … `⌥ 8` | Go to workspace 1 to 8 |
| `⌥ ⇧ 1` … `⌥ ⇧ 8` | Move the window to workspace 1 to 8 |
| `⌥ [` | Go to the previous workspace |
| `⌥ ]` | Go to the next workspace |
| `⌥ Tab` | Focus the next monitor |
| `⌥ ⇧ Tab` | Move the window to the next monitor |
| `⌥ S` | Show or hide the special workspace |
| `⌥ ⇧ S` | Move the window to the special workspace |
| `⌥ ⇧ ;` | Reload the config |
| `⌃ ⌘ 1` / `2` / `3` | Place the window in the left / center / right third |
| `⌃ ⌥ ←` / `→` | Place the window in the left / right half |
| `⌃ ⌥` + left drag | Move the window |
| `⌃ ⌥` + right drag | Resize the window |
| `⌃ ⌥` + scroll | Go to the next / previous workspace |

A placed window keeps its rectangle, and the other windows tile around it.

## Uninstall

1. Quit HyprOSX from its menu bar item. It moves every window back on screen before it quits.
2. Remove the app, the CLI link and the saved state:

   ```sh
   rm -r ~/Applications/HyprOSX.app "$HOME/Library/Application Support/HyprOSX"
   rm ~/.local/bin/hyprctl
   ```

3. Remove the Accessibility grant: `tccutil reset Accessibility dev.hyprosx.HyprOSX`
4. Optional: remove your config with `rm -r ~/.config/hyprosx`.
5. If you created the signing identity: `security delete-identity -c "HyprOSX Local Signing"`

## Credits

See [NOTICE](NOTICE) for the code ported from AeroSpace (MIT) and the Hyprland reference (BSD-3-Clause).
