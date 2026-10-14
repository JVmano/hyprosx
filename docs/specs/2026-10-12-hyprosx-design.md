# HyprOSX design

Date: 2026-10-12. Status: approved in conversation, pending written review.

HyprOSX is a tiling window manager for macOS that copies Hyprland's behavior, config syntax and motion as far as macOS allows, and uses fewer resources than AeroSpace. It replaces AeroSpace on the owner's MacBook (macOS 27, Apple silicon). SIP stays on. Accessibility is the only permission it needs.

Reference material in this repo:
- `docs/research/hyprland-algorithms.md`: the Hyprland formulas to port (dwindle, master, bezier, animation timing and styles, directional focus, corner parking).
- `docs/research/hyprland-config-reference.md`: the classic config syntax, options, keywords, dispatchers, rules and hyprctl output.
- `docs/research/macos-platform-notes.md`: probe results on this Mac and what macOS allows.
- `../AeroSpace` (MIT): window and dialog heuristics, per-app threads, corner parking.

## 1. Goals and success criteria

Goals, in the owner's words: replace AeroSpace because of its performance and resource use; mimic Hyprland (config, layouts, keybinds, motion); add a proper page to configure app exclusions; stay fully native; deliver a build ready for daily use.

Success criteria:
- Idle CPU below 0.1% over 60 s with no input. Resident memory below 50 MB with about ten windows open and Settings closed.
- No Accessibility call runs on the main thread. A frozen app delays only its own windows; keybinds and other apps keep working.
- Each event touches only the app or window it concerns. There is no global rescan of apps or windows after startup.
- A keybind reaches the frame request within 5 ms of main-thread work. `hyprctl clients` answers within 10 ms.
- Lines from a Hyprland 0.54 config work unchanged where macOS can do the effect, and load without errors where it cannot.
- From the Apps page or the menu bar, an app moves between Tile, Float and Ignore in two clicks, applied at once to its open windows.

## 2. Decisions

| topic | decision | reason |
|---|---|---|
| Motion | Per-frame Accessibility moves plus GPU-drawn borders | Proven by Rift, Glide and OmniWM; needs no extra permission. Snapshot animation needs Screen Recording and cannot capture parked windows. |
| Config | Classic `hyprland.conf`, Hyprland 0.54 syntax | Declarative, matches most dotfiles, easy for the Apps page to write. Lua is out of v1. |
| Hiding | Park windows in a screen corner (AeroSpace method) and hide apps whose windows are all parked | macOS has no public workspace API; parked windows still render, hidden apps do not. |
| Keys | Carbon hotkeys; an event tap only for mouse and scroll binds | Carbon needs no permission and wakes HyprOSX only for bound keys. |
| Build | SwiftPM, Swift 6.4 toolchain, Swift 5 language mode, no Xcode project, no third-party packages | Small, fast builds; AppKit and C callbacks without concurrency-checker friction. |
| Code style | No code comments unless nothing else explains the code | Owner's instruction. Port attribution goes in `NOTICE`. |

## 3. Architecture

### 3.1 Products

- `~/Applications/HyprOSX.app`: agent app (`LSUIElement`), bundle id `dev.hyprosx.HyprOSX`, menu bar item, Settings window.
- `hyprctl`: CLI inside the bundle at `Contents/MacOS/hyprctl`, linked from `~/.local/bin/hyprctl`.
- Config folder `~/.config/hyprosx/`: `hyprland.conf` (owner-edited) and `apps.conf` (written by HyprOSX, sourced by the main file). Override with `--config <path>` or `HYPROSX_CONFIG`.
- State file `~/Library/Application Support/HyprOSX/state.json`.
- Socket `$TMPDIR/hyprosx/.socket.sock` (the per-user temporary folder from `NSTemporaryDirectory()`).
- Logs through `os_log`, subsystem `dev.hyprosx`.

### 3.2 Swift package

| target | kind | imports | contents |
|---|---|---|---|
| `HyprCore` | library | Foundation only | geometry, config parser and model, keys and binds, dispatcher parsing, window and workspace rules, layouts, the world model, focus search, parking, animation math, IPC protocol and JSON, state snapshot |
| `HyprOSX` | executable | AppKit, ApplicationServices, Carbon, QuartzCore, SwiftUI, ServiceManagement | Accessibility layer, app and window tracking, effect executor, motion engine, borders, hotkeys, mouse tap, socket server, menu bar, Settings, banners, system checks |
| `hyprctl` | executable | Foundation | socket client |
| `HyprCoreTests` | tests | Swift Testing | unit and scenario tests |

`HyprCore` never imports AppKit. Every Accessibility call in `HyprOSX` goes through the per-app thread API.

### 3.3 Core model: events in, effects out

`HyprCore` owns a `World` (monitors, workspaces, windows, focus history, config). The platform layer feeds it events and executes the effects it returns:

- Events: monitors changed; app launched, terminated, activated, hidden or unhidden; window appeared (with its snapshot: id, pid, bundle id, app name, title, frame, kind normal or dialog), disappeared, minimized, native fullscreen changed, title changed; frame changed (with a flag for user drags); focused window changed by macOS; drag ended at a cursor point; keybind pressed, released or repeated; mouse bind start, move, end; scroll bind; config loaded; IPC command.
- Effects: frame transition (target frame per window plus the animation intent: leaf, style, start frame); park windows; focus a window; raise a window; close or force-close a window; hide or unhide an app; run a shell command (with optional rule prefix); warp the cursor; decoration state (border and dim per window); status state (menu bar); save state.

The world is pure and deterministic, so scenario tests drive it with events and check the effects.

### 3.4 Threads

- Main thread: the world, the effect executor, UI, the display link callbacks.
- One Accessibility thread per tracked app, each with its own `CFRunLoop`, holding that app's `AXObserver` sources and running every AX call for that app. Results return to the main thread as events.
- Socket thread: accepts connections and hands each request to the main thread, then writes the reply.
- Mouse tap thread: owns the `CGEventTap` and its run loop, installed only when the config has mouse or scroll binds.

## 4. Window tracking

### 4.1 Apps

- Tracked apps: `NSRunningApplication` with `activationPolicy == .regular`, except HyprOSX itself and the lock screen app. Accessory apps (launchers, menu bar tools) are not tracked.
- Startup: every tracked app is registered on its own thread in parallel.
- Later: `NSWorkspace` launch and terminate notifications add and remove apps.
- Per app: `AXUIElementSetMessagingTimeout(app, 1.0)`; observers for `kAXWindowCreatedNotification` and `kAXFocusedWindowChangedNotification`.

### 4.2 Windows

- Window id: `_AXUIElementGetWindow` (declared with `@_silgen_name`). The hyprctl address is `0x` plus the id in hex.
- On registration, each window gets observers for destroyed, miniaturized, deminiaturized, moved, resized and title changed.
- A new window is registered from the created notification alone. One app's window list (`kAXWindowsAttribute`) is read only at that app's registration, when that app is activated, and when an AX call on one of its windows fails with an invalid element. That last case removes the window.
- When the left mouse button is down at creation, registration waits for the button release (tab drag-out case).
- Classification ports AeroSpace's heuristics and known-bundle-id exceptions:
  - not a window (popup, tooltip, context menu, quick terminal): never managed;
  - dialog: managed, starts floating, matches `match:modal true`;
  - normal window: managed, starts tiled unless rules say otherwise.
- Native fullscreen (`AXFullScreen` true) windows leave the layout until they exit fullscreen. Minimized windows leave the layout and return to the current workspace when restored.
- Apps hidden by the user (Cmd+H) leave the layout and return on unhide. With `macos:unhide_hidden_apps = true` HyprOSX unhides them at once instead.

### 4.3 Frames

- HyprOSX keeps the last frame it applied to each window. It sends AX writes only when a target differs by at least 1 pt.
- Every frame write turns `AXEnhancedUserInterface` off for the app first and restores it when the app's batch or animation ends (ref-counted per app).
- Write order is size, position, size.
- A frame the user changes by dragging becomes the new known frame (floating windows) or starts the drag logic (tiled windows, section 8).

### 4.4 Parking (hidden workspaces)

- A window on a hidden workspace is parked once in its monitor's best corner with a 1 pt sliver on screen (corner choice in `hyprland-algorithms.md` section 7). HyprOSX then sends it nothing until its workspace is shown again.
- When an app has at least one managed window, all its windows are parked, and it is not the frontmost app, HyprOSX hides the app after 1.5 s (`macos:hide_parked_apps`, default true). macOS then stops drawing those windows. HyprOSX unhides the app before one of its workspaces is shown, and when the user activates it (Cmd+Tab, Dock). Hides done by HyprOSX are tracked separately from user hides.

### 4.5 Activation from outside

When macOS focuses a window that sits on a hidden workspace (Cmd+Tab, Dock click, notification), HyprOSX switches to that workspace. This is `misc:focus_on_activate`; HyprOSX defaults it to true because on macOS these activations come from the user.

## 5. Monitors, workspaces, focus

### 5.1 Monitors

- Monitor id 0 is the display with the menu bar; the others follow in x then y order.
- Name: `NSScreen.localizedName`. A `desc:` selector matches a substring of that name.
- The work area is the screen's visible frame (no menu bar, no Dock), minus `monitor = NAME, addreserved, T, B, L, R`, minus `gaps_out`.
- Other `monitor` forms (resolution, position, scale, transform, mirror) are accepted and ignored, because macOS owns display setup.
- Screen changes re-assign workspaces whose monitor disappeared to monitor 0 and move them back when it returns.

### 5.2 Workspaces

- Numbered workspaces (1 and up) and named workspaces (`name:web`, ids from 1000000) are created on demand and destroyed when empty, hidden and not persistent.
- Each monitor shows one workspace. A workspace rule `monitor:` binds a workspace to a monitor; without it a new workspace opens on the focused monitor.
- `workspace N` for a workspace visible on another monitor focuses that monitor. `binds:workspace_back_and_forth` turns a switch to the current workspace into a switch to the previous one.
- Special workspaces (`special` with id -99, `special:name` with ids from -98 upward) show on top of the current workspace of their monitor. Their tiled windows use the work area scaled by `special_scale_factor` and centered. `togglespecialworkspace` shows or hides them; `misc:close_special_on_empty` hides an empty one.
- Per-workspace layout: from the workspace rule `layout:`, else `general:layout`. HyprOSX adds the dispatcher `workspacelayout NAME` (set) and `workspacelayout A B` (toggle between two).

### 5.3 Focus

- The world tracks the focused window, the last focused window per workspace, and a focus history.
- HyprOSX focuses a window by setting `kAXMainAttribute`, performing `kAXRaiseAction`, then activating the app. If live tests show wrong-window focus, the fallback is the `_SLPSSetFrontProcessWithOptions` path used by AltTab.
- Focus changes made by macOS (clicks, Cmd+Tab) update the world.
- `movefocus` uses Hyprland's directional search (`hyprland-algorithms.md` section 6), including `focus_preferred_method` and the monitor fallback.
- After a window closes, focus goes to the layout's next candidate on the same workspace (`input:focus_on_close` 0, 1 or 2).
- Cursor warps: with `cursor:no_warps = false`, focus changes made by dispatchers warp the cursor to the window center unless it is already inside. With `no_warps = true` there are no window warps, but `focusmonitor` still warps to the target monitor center when the cursor is on another monitor (AeroSpace's lazy center).
- `input:follow_mouse = 1` focuses the window under the cursor when the cursor crosses into it. The mouse-move monitor exists only when this option is on.

## 6. Layouts and geometry

All layouts are ports of the Hyprland algorithms in `hyprland-algorithms.md`.

- Dwindle: insertion rules, split direction, `preserve_split`, `smart_split`, `force_split`, `split_width_multiplier`, `default_split_ratio`, `split_bias`, `permanent_direction_override`, preselect, removal, smart and plain resizing, `togglesplit`, `swapsplit`, `rotatesplit`, `movetoroot`, `splitratio`, directional `movewindow`, pseudotile.
- Master: geometry for left, right, top, bottom and center, `mfact`, `new_status`, `new_on_top`, `new_on_active`, `slave_count_for_center_master`, `center_master_fallback`, `smart_resizing`, `always_keep_position`, `allow_small_split`, and the layout messages `swapwithmaster`, `focusmaster`, `cyclenext`, `cycleprev`, `swapnext`, `swapprev`, `addmaster`, `removemaster`, `orientation*`, `mfact`, `rollnext`, `rollprev`.
- Monocle: every tiled window gets the whole work area; the focused one is raised. `movefocus l/u` and `r/d` step backward and forward through the list, as do `cyclenext` and `cyclenext prev`.
- Floating: a window keeps its own frame. A window that opens floating keeps the frame its app chose (moved inside the work area if it is off-screen). A tiled window that becomes floating returns to its remembered floating frame, or is centered at 60% of the work area if it never floated. The `center` rule and `centerwindow` center explicitly.
- Fullscreen: mode 0 fills the screen's visible frame minus reserved space, with no gaps and no border; mode 1 (maximize) fills the work area (inside `gaps_out`) with its border. The fullscreen window sits on top; the rest of the workspace keeps its layout underneath.
- Pin: a floating window that stays visible on every workspace of its monitor.
- Geometry follows Hyprland: `gaps_out` shrinks the work area, `gaps_in` applies on each inner side, and the border ring sits inside the gap, so the AX frame is inset by `border_size` on every side. Floating windows use `float_gaps`.
- `misc:size_limits_tiled` applies `min_size` and `max_size` rules to tiled windows. A window that refuses its tile size (read back at settle) is centered inside its tile.

## 7. Configuration

### 7.1 Files and loading

- Main file `~/.config/hyprosx/hyprland.conf`. On first launch, if it is missing, HyprOSX writes the bundled default (Alt as the main modifier, Hyprland look and feel).
- `apps.conf` is written by the Apps page and the menu bar quick rules. HyprOSX checks that the main file sources it and offers a one-click fix in Settings if it does not.
- Auto-reload: a `DispatchSource` watches the config folder; changes are debounced by 150 ms. `misc:disable_autoreload` stops it. `hyprctl reload` and the menu reload by hand.
- A reload applies everything that parses. Errors appear as `file:line: message` in a banner at the top of the main screen (as Hyprland does), in `hyprctl configerrors`, and as a red dot in the menu bar. The banner closes when a reload has no errors.
- After a reload, static rules are applied again only to windows of apps whose rules in `apps.conf` changed. Gaps, borders, layouts and binds update everywhere.

### 7.2 Syntax

The full hyprlang grammar from `hyprland-config-reference.md`: comments and `##`, variables with environment preload, categories and the flat `a:b:c` form, `source` with `~`, relative paths and globs, `# hyprlang if/endif/noerror`, `{{a + b}}`, line continuation, all value types (colors, gradients with angle, CSS gaps, vec2, booleans).

### 7.3 Keywords

- Supported: `bind` and its flags (section 8), `bindm`, `bindd`, `unbind`, `submap`, `bezier`, `animation`, `windowrule` (both 0.54 forms and the 0.51 effect-first form), `windowrulev2`, `workspace`, `monitor` (`addreserved` only), `exec`, `exec-once`, `exec-shutdown`, `execr`, `execr-once`, `env`, `source`.
- Accepted and ignored: `plugin`, `gesture`, `device`, `permission`, `layerrule`, `envd`, `monitorv2`.
- Commands run through `/bin/sh -c` with the user's environment plus `PATH` prefixed by `/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$HOME/.local/bin`, and the `env` values. Every command is started with `posix_spawn` and disclaimed responsibility, so it never inherits the HyprOSX Accessibility grant (section 15).

### 7.4 Options

HyprOSX reads every option listed under "Options HyprOSX reads" in `hyprland-config-reference.md`, with the Hyprland defaults, except `misc:focus_on_activate` (default true, section 4.5). All other 0.54 options are accepted and ignored, so pasted configs load cleanly. A truly unknown option is an error, as in Hyprland.

`decoration:rounding` does not round macOS windows. The border ring follows each window's real corner radius, read from the WindowServer on macOS 26 and later, with a fallback per macOS version.

HyprOSX adds a `macos` category:

| option | type | default | meaning |
|---|---|---|---|
| `unhide_hidden_apps` | bool | false | unhide apps hidden with Cmd+H at once |
| `hide_parked_apps` | bool | true | hide apps whose windows are all parked (section 4.4) |
| `animations_on_low_power` | bool | false | keep animations in Low Power Mode |
| `respect_reduce_motion` | bool | true | turn off motion when macOS Reduce Motion is on |
| `live_resize_max_latency` | float | 6 | ms; apps with a lower average AX write time get live resize (section 11.3) |
| `border_radius` | int | -1 | border ring radius; -1 reads the real window radius |
| `ipc_exec` | bool | false | allow `exec`, `execr` and `exec*` keywords through the socket |
| `ipc_window_titles` | bool | true | include window titles in `hyprctl` replies |

## 8. Keybinds and mouse

- Modifiers: `SUPER`, `WIN`, `LOGO`, `MOD4`, `CMD`, `COMMAND` map to Command; `ALT`, `MOD1`, `OPT`, `OPTION` to Option; `CTRL`, `CONTROL` to Control; `SHIFT` to Shift. `FN` is accepted for mouse and scroll binds only.
- Keys: XKB keysym names mapped to the macOS ANSI virtual key codes (letters, digits, punctuation, F1 to F20, arrows, Return, Tab, space, Escape, BackSpace, Delete, Home, End, Prior, Next, keypad keys); `code:NN` is a macOS virtual key code. Names are case-insensitive.
- Keyboard binds use `RegisterEventHotKey` with pressed and released events.
  - `bindr` fires on release.
  - `binde` repeats while the key is held, using the macOS key repeat delay and interval.
  - `bindu` is active in every submap. `bindd` adds a description.
  - `l`, `t` and `p` are accepted with no effect.
  - `n`, `i`, `s`, `o`, `c`, `g` and `k` cannot work with Carbon hotkeys; the bind loads as a plain bind and the config shows a warning.
- Several binds on the same key run in file order (needed for multi-step binds).
- Submaps: `submap = name` until `submap = reset`; `bind = ..., submap, name` enters one. The registered hotkeys switch with the active submap. `catchall` is not supported (it needs Input Monitoring) and shows a warning.
- If two apps own the same hotkey, registration fails; the config banner names the failing bind.
- Mouse and scroll binds (`bindm`, `mouse:272..276`, `mouse_up/down/left/right`): the event tap consumes an event only when its modifiers match a bind. `movewindow` drags the window under the cursor; a tiled window follows the cursor and is inserted at the drop point on release (dwindle focal point, master swap). `resizewindow` resizes floating windows directly and tiled windows through the layout's resize with the corner chosen at press. `binds:drag_threshold` and `binds:scroll_event_delay` apply.
- Title-bar drags of tiled windows: a moved notification while the left button is down and the frame differs from the target marks a drag. On button release, HyprOSX inserts the window at the cursor (same as `movewindow` with a focal point) or snaps it back. Edge drags of tiled windows resize through the layout live; neighbours follow without animation unless `misc:animate_manual_resizes` is on. The global left-mouse-up monitor does nothing unless a drag or a delayed window registration (section 4.2) is pending.
- Secure Input: when macOS Secure Input is on, the menu bar icon shows a lock and the menu names the app that enabled it (`kCGSSessionSecureInputPID`). HyprOSX checks it on app activation and when the menu opens.

## 9. Dispatchers

Supported, with Hyprland 0.54 parameters (`hyprland-config-reference.md`):

`exec` (with `[rules]` prefix), `execr`, `killactive`, `forcekillactive`, `closewindow`, `killwindow`, `signal`, `signalwindow`, `workspace` (every selector form), `movetoworkspace`, `movetoworkspacesilent`, `togglefloating`, `setfloating`, `settiled`, `fullscreen`, `fullscreenstate` (maps to the same two modes), `pin`, `pseudo`, `movefocus`, `movewindow` (direction, `mon:`, `silent`), `swapwindow`, `centerwindow`, `resizeactive`, `moveactive`, `resizewindowpixel`, `movewindowpixel`, `cyclenext` (with `prev`, `tiled`, `floating`, `visible`, `hist`), `swapnext`, `focuswindow`, `focusmonitor`, `focuscurrentorlast`, `focusurgentorlast` (no urgency on macOS, so last), `movecurrentworkspacetomonitor`, `moveworkspacetomonitor`, `focusworkspaceoncurrentmonitor`, `swapactiveworkspaces`, `togglespecialworkspace`, `renameworkspace`, `layoutmsg`, `splitratio`, `submap`, `alterzorder`, `bringactivetotop`, `movecursortocorner`, `movecursor`, `exit`, and the HyprOSX additions `workspacelayout`, `setprop` (for `border_size`, `border_color`, `no_anim`) and `placeactive W H X Y`.

`placeactive` takes four measures (pixels or percent) relative to the work area, like `exact`, where X and Y are offsets from the work-area origin. On a floating window it sets the floating frame. A tiled window keeps its tile slot, so no other window moves: it shows at the given frame until its tile box changes, focus moves into it from another window on its workspace, a dispatcher acts on its layout or state, or the user drags it, and then it returns to its slot. The override is never saved in `state.json`.

`exact` sizes and positions in `resizeactive`, `moveactive`, `resizewindowpixel` and `movewindowpixel` are relative to the work area (visible frame minus `gaps_out`), because macOS has a menu bar and Dock. Percentages use the same base.

Accepted with an error reply ("not supported on macOS"): group dispatchers, `pass`, `sendshortcut`, `sendkeystate`, `global`, `event`, `dpms`, `forceidle`, `toggleswallow`, `tagwindow`. `forcerendererreload` is a no-op.

Signals go to the window's app pid. `killactive` presses the close button; `forcekillactive` sends SIGKILL to the app.

## 10. Rules

### 10.1 Window rules

- Syntax: the 0.54 one-line and block forms with `match:` props, the 0.51 form (effects first, then `field:regex`) and `windowrulev2`. Old names map to new ones (`floating` to `float`, `noinitialfocus` to `no_initial_focus`, and the rest of the mapping in the reference).
- `class` and `initial_class` match the bundle id or the app name. `title` and `initial_title` match the window title. Regexes are full-match and case-sensitive (NSRegularExpression anchored); `negative:` inverts.
- Supported props: `class`, `title`, `initial_class`, `initial_title`, `float`, `fullscreen`, `pin`, `focus`, `modal` (dialog classification), `workspace`. `xwayland` and `group` are always false; `tag` and `content` never match.
- Static effects: `float`, `tile`, `fullscreen`, `maximize`, `move` and `size` (with the Hyprland expression variables), `center`, `pseudo`, `monitor`, `workspace` (`silent`, `unset`), `no_initial_focus`, `pin`, and the HyprOSX effect `ignore` (HyprOSX never manages the window).
- Dynamic effects: `border_color`, `border_size`, `no_anim`, `min_size`, `max_size`, `animation` (style override), `dim_around` (dims everything else while the window is visible). Other effects are accepted and ignored.
- Evaluation: the initial state comes from classification (dialogs start floating). Static rules see that initial state; matching rules run top to bottom, named before anonymous, and the last match wins per effect. Static rules run at registration and once more when a window that had an empty title gets its first title within 2 s. Dynamic rules run again when focus, float or fullscreen state changes.

### 10.2 Workspace rules

Selectors: id, `name:`, `special:`, and the filters `r[A-B]`, `s[bool]`, `n[...]`, `m[monitor]`, `w[(flags)A-B|X]` with flags `t`, `f` and `v`, `f[-1|0|1]`, combinable. Rules: `monitor:`, `default:`, `gapsin:`, `gapsout:`, `bordersize:`, `border:`, `persistent:`, `defaultName:`, `layout:`, `layoutopt:orientation:`, `on-created-empty:`. The smart-gaps rules from the Hyprland example work.

## 11. Motion

### 11.1 Animation config

- `bezier` curves are baked to 255 points and evaluated as Hyprland does; `default` is (0, 0.75, 0.15, 1) and `linear` is built in.
- The animation tree, all-or-nothing inheritance, and speed in deciseconds follow Hyprland (`hyprland-algorithms.md` section 4).
- Motion is instant when `animations:enabled` is false, when the leaf is off, when a window has `no_anim`, in Low Power Mode (unless `macos:animations_on_low_power`), or when Reduce Motion is on (unless `macos:respect_reduce_motion` is false). In the last two cases border color fades still run.

### 11.2 Engine

- A per-screen `CADisplayLink` runs only while at least one animation is active.
- Each window frame is an animated value with Hyprland retarget semantics: a new goal starts from the current value with a fresh timer.
- Every tick computes each animating window's frame and hands it to the app's thread. Each window has one pending-frame slot; a busy app skips to the newest frame and never builds a queue.
- The border window of an animating window takes the computed frame on every tick, so the outline moves smoothly even when the app lags.
- At the end, the exact goal frame is written. HyprOSX reads the real frame back once and snaps the border to it.

### 11.3 Size changes

- HyprOSX times every AX frame write per app (moving average).
- Apps whose average is below `macos:live_resize_max_latency` (6 ms default) get the size written on every tick (live resize).
- Other apps get position on every tick, the size once at progress 0.5, and the final frame at the end.

### 11.4 Styles on macOS

| leaf | Hyprland style | HyprOSX behavior |
|---|---|---|
| windowsIn | `popin N%` (and empty or unknown) | the new window starts at N% of its goal frame, centered on that frame, and grows with a live resize of that window only; an app whose measured average write time is above `macos:live_resize_max_latency` gets a glide from where the app opened it instead |
| windowsIn | `slide [side]` | position-only slide from the Hyprland offset |
| windowsIn | `gnomed` | treated as `popin 0%` |
| windowsOut | any | none (the window is already gone) |
| windowsMove | any | glide as in 11.2 |
| workspaces, specialWorkspace | `slide`, `slidevert` | old windows glide out until a 1 pt sliver remains at the screen edge, then park; new windows glide in from the opposite side; direction follows the Hyprland id rule |
| workspaces, specialWorkspace | `slidefade N%`, `slidefadevert N%` | old windows park at once; new windows glide in from N% |
| workspaces, specialWorkspace | `fade` | soft settle: old windows park at once; new windows glide in from 8% |
| border | color | Core Animation color fade between active and inactive |
| borderangle | `once`, `loop` | Core Animation rotation of the gradient |
| fade, fadeIn, fadeOut, fadeSwitch, fadeDim | any | drives the `dim_inactive` and `dim_around` overlay fades |
| layers, zoomFactor, monitorAdded, fadeShadow, fadeLayers*, fadePopups*, fadeDpms | any | ignored |

Window open happens after macOS shows the window, so the window can appear for one or two frames before the animation takes over. HyprOSX keeps the time from the created notification to the first frame write as short as possible.

## 12. Borders and dimming

- Each managed visible window has one border window: borderless, transparent, click-through, ordered directly below the target window with `order(.below, relativeTo:)`, re-ordered after the target is raised.
- The ring is a Core Animation shape: outer edge `border_size` outside the AX frame, inner radius equal to the window's corner radius. Gradients use `col.active_border` or `col.inactive_border` (or the `border_color` rule) with the angle. `border_size 0` or a fullscreen window means no border window.
- When the inactive color is fully transparent, inactive windows get no border window at all.
- `decoration:dim_inactive` adds one click-through dim window ordered directly above each inactive tiled window, with `dim_strength` as alpha. `dim_around` adds one full-screen dim window ordered directly below the target.
- Border windows of parked windows are ordered out.

## 13. User interface

### 13.1 Menu bar

- Title: the active workspace name of the focused monitor, a red dot when the config has errors, a lock during Secure Input.
- Menu:
  - The front app (name and bundle id) with Default, Tile, Float, Ignore (current choice checked). Below it, why the focused window has its state ("tiled by apps.conf line 4", "floating: dialog").
  - The workspace list (click to switch).
  - Settings…, Reload Config, Open Config Folder, Pause HyprOSX (stop managing, bring parked windows back), Quit.

### 13.2 Settings window (SwiftUI, created on open, released on close)

- Apps tab:
  - "New windows" picker: Tile or Float (the catch-all rule at the top of `apps.conf`).
  - Search field and app list: running tracked apps plus apps that already have rules, with icon, name and bundle id. Add App… opens a file picker in `/Applications`.
  - Each row has Default, Tile, Float or Ignore, and a workspace menu (Any, 1 to 10, special).
  - A change writes `apps.conf` atomically and applies to that app's open windows at once.
- General tab:
  - Launch at login (`SMAppService.mainApp`).
  - Accessibility status with a button to System Settings.
  - Config folder, Reload, and the `apps.conf` source fix.
  - System check: Stage Manager, edge-drag and Option-drag tiling, click wallpaper to reveal desktop, automatic Space rearrangement, Displays have separate Spaces. Each row shows its state; a Fix button writes the macOS preference and restarts the system agent if needed. On first launch with conflicts, the menu bar shows a one-time hint.

`apps.conf` format, sorted by app name after the policy line:

```
windowrule = float on, match:class .*
windowrule = tile on, match:class com\.mitchellh\.ghostty, match:modal false
windowrule = ignore on, match:class com\.raycast\.macos
windowrule = workspace 2 silent, match:class com\.tinyspeck\.slackmacgap
```

### 13.3 Error banner

A non-activating panel at the top center of the main screen lists up to five config errors with a dismiss button. A clean reload removes it.

## 14. hyprctl and IPC

- Protocol: Hyprland socket 1. The request is `[flags]/command args`, with `[[BATCH]]` for several commands separated by `;`. One request per connection; HyprOSX answers and closes.
- Commands: `dispatch`, `keyword`, `reload`, `clients`, `activewindow`, `workspaces`, `activeworkspace`, `monitors`, `binds`, `getoption`, `configerrors`, `version`, `cursorpos`, `perf`.
- Flags: `-j` (JSON), `--batch`, `-q`.
- JSON uses Hyprland's field names. For clients: `address`, `mapped`, `hidden` (parked), `at`, `size`, `workspace {id, name}`, `floating`, `monitor`, `class` (bundle id), `title`, `initialClass`, `initialTitle`, `pid`, `xwayland` (false), `pinned`, `fullscreen`, `fullscreenClient`, `grouped` ([]), `tags` ([]), `focusHistoryID`. Workspaces and monitors follow the reference list where a value exists on macOS.
- `perf`: process CPU time, resident memory, AX calls and errors, average and p95 AX write time per app (slowest five), frames written and skipped, events by type, layout passes, and uptime. Counters are plain integers updated on the main thread and on the app threads.
- `hyprctl` speaks POSIX sockets directly and exits within a few milliseconds. Exit code 0 on `ok` or data, 1 on an error reply or no server.
- Socket requests can never start a command unless `macos:ipc_exec` is true (section 15).

## 15. Security

HyprOSX holds the Accessibility grant, which controls every window and can drive other apps. On macOS a child process normally counts as part of the app that started it (its responsible process), so it inherits that app's permissions. Linux has no such model, so Hyprland never guards against this. HyprOSX must not hand its grant to anything else.

- Every command HyprOSX starts (`exec`, `execr`, `exec-once`, `exec-shutdown`, `on-created-empty`, rule-prefixed `exec`) uses `posix_spawn` with `responsibility_spawnattrs_setdisclaim(attr, 1)`. The child becomes its own responsible process and asks macOS for its own permissions. A probe on this Mac confirmed it: a normal child reported the parent app's responsible process; a disclaimed child reported itself. If the symbol is missing at runtime, HyprOSX refuses to run commands and shows a config error.
- This also neutralizes `exec` lines that another program writes into the auto-reloaded config.
- Socket: the folder `$TMPDIR/hyprosx` is mode 0700, the socket file 0600, and HyprOSX checks the peer uid with `getpeereid` and drops other users.
- Socket requests for `dispatch exec`, `dispatch execr`, `keyword exec*` and `keyword source` get the reply "exec over IPC is disabled (macos:ipc_exec)" unless `macos:ipc_exec` is true. Because commands are disclaimed, turning it on gives a caller no more power than running the command itself.
- HyprOSX has no dispatcher that sends keystrokes or mouse clicks to other apps (`pass`, `sendshortcut` and `sendkeystate` are refused), so the socket cannot be used to type into other apps.
- Window titles normally need Screen Recording to read. `hyprctl clients` and `activewindow` return them, as AeroSpace and yabai do; `macos:ipc_window_titles = false` removes them.
- Window management through the socket (focus, move, close) is the intended feature, as in Hyprland.

## 16. Restore after restart

- `state.json` holds, per window: id, bundle id, workspace, floating flag, floating frame, pseudo, pinned, fullscreen mode. Per workspace: id, name, monitor name, layout, dwindle tree (window ids, split direction, ratio) or master list (order, master flags, `percMaster`, `percSize`). Plus the active workspace per monitor and the focused window.
- HyprOSX writes it 500 ms after the last change and at quit.
- At launch, a window whose id and bundle id match the file goes back to its saved workspace and tree position; the rest register normally. Window ids live as long as the window, so this covers HyprOSX restarts, updates and crashes, not app restarts.
- On quit, `SIGTERM`, `SIGINT` and `SIGHUP`, HyprOSX unhides the apps it hid and moves every parked window back onto the current workspace area before exit.

## 17. Startup sequence

1. Check Accessibility. If not trusted, show the system prompt, show the state in the menu bar, and check again once per second until trusted. This is the only polling loop; every other timer in HyprOSX is a one-shot timer started by an event (debounces, key repeat, the parked-app hide delay).
2. Load the config (write the default if missing).
3. Start the socket server.
4. Register hotkeys; install the mouse tap if needed.
5. Read monitors; register apps and windows in parallel.
6. Restore from `state.json`, else assign windows by rules, else to the active workspace of the monitor they are on.
7. Lay out and write frames without animation.
8. Run `exec-once` and `exec`.

## 18. Testing

- Unit tests (Swift Testing) in `HyprCoreTests`:
  - parser: grammar, variables, categories, `source`, directives, arithmetic, value types, errors with lines;
  - keys and binds: modifier and key names, flags, submaps;
  - selectors and dispatchers: workspace, window, monitor, direction, resize params;
  - rules: every syntax, legacy name mapping, matching and evaluation order;
  - dwindle: insertion order per option, split direction, ratios, removal, both resize modes, togglesplit, swapsplit, rotatesplit, movetoroot, geometry with gaps and borders;
  - master: every orientation, insertion options, removal, every layout message;
  - monocle, directional focus, corner choice, bezier values against hand-computed points, animation tree inheritance, the style table in 11.4, IPC request parsing and JSON shape.
- Scenario tests: event sequences through the world (open, close, move to workspace, switch, special workspace, rules, Apps-page rule change, drag drop, restore from snapshot) with assertions on the effects.
- Security tests: a command started by HyprOSX reports itself as its responsible process; socket requests for `exec`, `execr`, `keyword exec*` and `keyword source` are refused while `macos:ipc_exec` is false; a connection from another uid is dropped.
- Live tests after Accessibility is granted to `HyprOSX.app`: driven from the terminal with `hyprctl` against TextEdit and Finder windows; check frames with `hyprctl clients -j`, then measure idle CPU and memory over 60 s and `hyprctl` latency.

## 19. Build, install, permissions

- `scripts/build-app.sh [--install]`: `swift build -c release`, assemble `HyprOSX.app` (Info.plist with `LSUIElement`, bundle id, version, `LSMinimumSystemVersion` 14.0), copy both executables, sign, and with `--install` copy to `~/Applications`, link `~/.local/bin/hyprctl`, and restart a running copy.
- Signing: a one-time local code-signing identity ("HyprOSX Local Signing") in the login keychain keeps the Accessibility grant across rebuilds. Creating it changes the keychain, so it runs only after the owner agrees; without it the build is signed ad hoc and macOS asks for Accessibility again after each rebuild.
- `NOTICE` credits AeroSpace (MIT) for the ported heuristics and corner logic.

## 20. Milestones

1. Core tiling (daily usable, no motion): parser and options, dwindle, master, monocle and `workspacelayout`, floating, fullscreen, workspaces and special workspaces, rules, parking, Accessibility layer, hotkeys and submaps, focus, hyprctl with the security rules, restore after restart, menu bar basics, build script, the owner's config.
2. Motion and decoration: animation tree and curves, motion engine with adaptive live resize, the style table, borders, dimming, battery-aware motion, mouse binds and drags.
3. Apps and polish: Settings (Apps and General with the system check), menu bar quick rules, error banner, Secure Input lock, hiding parked apps, `hyprctl perf`.
4. Verification: live tests, performance pass against the success criteria, install, launch at login.

Each milestone ends with green tests and a build the owner can run.

## 21. The owner's config

`~/.config/hyprosx/hyprland.conf` mirrors the AeroSpace setup:

- `$mainMod = ALT`. Alt+H/J/K/L `movefocus`; Alt+Shift+H/J/K/L `movewindow`; Alt+Shift+minus and equal `resizeactive -50 0` and `50 0`; Alt+slash `layoutmsg togglesplit`; Alt+comma `workspacelayout dwindle monocle` (the old accordion habit); Alt+F `fullscreen 1`; Alt+Shift+F `fullscreen 0`; Alt+Shift+space `togglefloating`.
- Alt+1..8 `workspace`; Alt+Shift+1..8 `movetoworkspace`; Alt+Tab `focusmonitor +1`; Alt+Shift+Tab `movewindow mon:+1`; Alt+[ `workspace previous`; Alt+] `workspace e+1`; Alt+Shift+; `exec hyprctl reload`.
- Alt+R enters the `resize` submap: H/J/K/L `binde resizeactive` by 50; Escape and Return return to `reset`.
- Rectangle replacements: Ctrl+Cmd+1/2/3 left, center and right third; Ctrl+Alt+Left/Right left and right half (each one `placeactive`, so the window keeps its tile slot). Rectangle has to quit, or its hotkeys win.
- Additions from Hyprland: Alt+Shift+Q `killactive`; Alt+S and Alt+Shift+S special workspace `magic`; Alt+P `pseudo`; Ctrl+Alt+left drag `movewindow`; Ctrl+Alt+right drag `resizewindow` (Ctrl+Alt keeps Option-click free in apps); Ctrl+Alt+scroll `workspace e+1` and `e-1`.
- Gaps: `gaps_in = 4` (8 between windows), `gaps_out = 10`. Border 2, Gruvbox Material colors to match the terminal theme: active `rgba(89b482ee) rgba(a9b665ee) 45deg`, inactive `rgba(3c3836aa)`.
- Motion: the Hyprland example curves and leaves, `dwindle:preserve_split = true`, `cursor:no_warps = true`, `input:follow_mouse = 0`, `macos:unhide_hidden_apps = true`.
- Workspace rules: 1 to 5 on monitor 0 and 6 to 8 on monitor 1 (falls back to monitor 0 when undocked).
- `apps.conf`: float by default; tile Ghostty, Zen, Slack and kitty; Calculator, System Settings and Alfred float.

## 22. Risks

| risk | mitigation |
|---|---|
| Option-only Carbon hotkeys rejected on this macOS version | Test in milestone 1. Fallback: a keyboard event tap on its own thread, which needs Input Monitoring. |
| Slow or hung apps | Per-app threads, 1 s AX timeout, newest-frame slots, adaptive resize. |
| Window appears at the app's spot before the first frame write | Keep the created-to-write path short; popin hides most of it. |
| Focus lands on the wrong window of an app | Fallback to the `_SLPSSetFrontProcessWithOptions` path. |
| Real corner radius unavailable | Per-version fallback and `macos:border_radius`. |
| Ad-hoc signing drops the Accessibility grant on rebuild | Local signing identity (with the owner's consent). |
| Window id read fails for an app | Retry on the next event for that app; skip the window meanwhile. |
| Hiding parked apps confuses an app | `macos:hide_parked_apps = false`; never hide the frontmost app. |
| Commands inherit the Accessibility grant | Disclaimed spawn for every command; refuse to run commands if the disclaim call is missing; exec over the socket off by default. |

## 23. Not in v1

Window groups and tabs, the scrolling layout, trackpad gestures, the socket 2 event stream, Lua config, plugins, snapshot effects (fade, pop-in from Screen Recording, close animation), blur, shadows, opacity and rounding of other apps' windows, `pass`, `sendshortcut`, `catchall`, per-device input, tags.
