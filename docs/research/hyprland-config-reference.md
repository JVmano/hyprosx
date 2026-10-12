# Hyprland 0.54 config reference (classic hyprland.conf)

Sources: hyprland-wiki at commit ecc06f3 (2026-04-20, last hyprlang-era docs), the 0.53/0.54 wiki snapshots, hyprlang `main`, Hyprland v0.54.3 source. Hyprland 0.55 made Lua the default; the classic file still loads in 0.56 but is deprecated.

## Syntax (hyprlang)

- Every line is `COMMAND = VALUE`. The first `=` splits; both sides are trimmed. An empty left side is an error.
- A line without `=` that ends in `{` opens a category; `}` closes it. A stray `}` and an unclosed category at EOF are errors.
- Comments start with `#`. `##` is a literal `#`. There is no quoting; `col = #fff` gives an empty value.
- A line ending in `\` joins the next line (backslash and trailing blanks removed). A backslash on the last line is an error.
- Variables: `$NAME = value`. Global scope. Expansion is textual, longest name first, up to 100 rounds. It runs on values and on the left side of non-variable lines. Environment variables are preloaded and config definitions override them. Redefinition affects later lines only.
- Flat form `category:sub:key = value` equals nested blocks. Special categories use `category[key]:name`.
- Options: the last assignment wins. Keywords (handlers) such as `bind`, `bezier`, `animation`, `windowrule`, `exec`, `env`, `monitor`, `workspace`, `source` run on every occurrence. `bind` matches by prefix to allow flag letters (`binde`, `bindrl`).
- Directives at column 0: `# hyprlang noerror true|false`; `# hyprlang if VAR`, `# hyprlang if !VAR`, `# hyprlang endif` (a variable is true when it exists and is not empty; env vars count; no else).
- Arithmetic: `{{a + b}}` with `+ - * /`, exactly two operands (numbers or variable names without `$`), spaces around the operator, no nesting. `\{{` escapes.
- Unknown option in an existing category: "config option <x> does not exist." Unknown top-level keys with no `:` are ignored silently.
- `source = path`: `~` is `$HOME`; `/` absolute; otherwise relative to the current file's directory. Globs allowed. No match is an error. Parsing is linear (before lines, the file, after lines).
- Booleans: `true/false`, `yes/no`, `on/off`, `1/0` (prefix match, so `yes, please :)` is true).
- Keyword comma rule: arguments are positional; empty arguments keep their commas (`A, , C`).

## Value types

| type | syntax |
|---|---|
| int | decimal or hex `0xDEADBEEF` |
| float | number |
| bool | as above |
| color | `rgba(RRGGBBAA)`, `rgba(r,g,b,a)` (a 0..1), `rgb(RRGGBB)`, `rgb(r,g,b)`, legacy `0xAARRGGBB` |
| gradient | one or more colors then optional angle `45deg` (default 0deg) |
| vec2 | two floats separated by one space |
| css gaps | 1 to 4 ints like CSS (top right bottom left) |
| MOD | modifier names joined by any separator except `,` |

Modifier names: `SHIFT`, `CAPS`, `CTRL`/`CONTROL`, `ALT`, `MOD2`, `MOD3`, `SUPER`/`WIN`/`LOGO`/`MOD4`, `MOD5`.

## Options HyprOSX reads (name, type, default)

general: `border_size` int 1; `gaps_in` css 5; `gaps_out` css 20; `float_gaps` css 0; `gaps_workspaces` int 0; `col.active_border` gradient `0xffffffff`; `col.inactive_border` gradient `0xff444444`; `layout` str `dwindle`; `no_focus_fallback` bool false.

decoration: `rounding` int 0; `dim_inactive` bool false; `dim_strength` float 0.5.

animations: `enabled` bool true; `workspace_wraparound` bool false.

input: `follow_mouse` int 1; `focus_on_close` int 0.

binds: `workspace_back_and_forth` false; `allow_workspace_cycles` false; `focus_preferred_method` 0; `movefocus_cycles_fullscreen` false; `window_direction_monitor_fallback` true; `drag_threshold` 0; `scroll_event_delay` 300; `hide_special_on_workspace_change` false.

cursor: `no_warps` false; `warp_on_change_workspace` 0.

misc: `disable_autoreload` false; `focus_on_activate` false; `close_special_on_empty` true; `animate_manual_resizes` false; `animate_mouse_windowdragging` false; `size_limits_tiled` false.

dwindle: `pseudotile` false (0.54); `force_split` 0; `preserve_split` false; `smart_split` false; `smart_resizing` true; `permanent_direction_override` false; `special_scale_factor` 1; `split_width_multiplier` 1.0; `use_active_for_splits` true; `default_split_ratio` 1.0; `split_bias` 0; `precise_mouse_move` false.

master: `allow_small_split` false; `special_scale_factor` 1; `mfact` 0.55; `new_status` slave; `new_on_top` false; `new_on_active` none; `orientation` left; `slave_count_for_center_master` 2; `center_master_fallback` left; `smart_resizing` true; `drop_at_cursor` true; `always_keep_position` false.

Everything else in the 0.54 variable list (blur, shadow, glow, opacity, input devices, xkb, cursor theme, misc rendering, group, groupbar, debug, render, opengl, ecosystem, xwayland, gestures) is accepted and ignored.

## Keywords

- `exec-once = cmd` at launch; `exec = cmd` on every load; `exec-shutdown = cmd` at quit; `execr`, `execr-once` raw (no rules). `exec` accepts a rule prefix: `[workspace 2 silent; float] cmd`.
- `env = NAME,value` (raw value, no quotes).
- `source = path`.
- `monitor = name, resolution, position, scale[, extra...]`; `monitor = name, addreserved, TOP, BOTTOM, LEFT, RIGHT`; `monitor = name, disable`; `desc:` selects by description.
- `bezier = NAME, X0, Y0, X1, Y1`.
- `animation = NAME, ONOFF, SPEED, CURVE[, STYLE]` (ONOFF 0 allows omitting the rest; SPEED in deciseconds).
- `bind[flags] = MODS, key, dispatcher, params` (exactly 3 commas; empty MODS and empty params allowed; a trailing stray comma is part of the last argument).
- `bindd = MODS, key, description, dispatcher, params`.
- `bindm = MODS, mouse:272, movewindow` / `mouse:273, resizewindow` (`resizewindow 1` keeps aspect ratio).
- `unbind = MODS, key` (case-sensitive match).
- `submap = name` starts a block of binds; `submap = reset` ends it; `submap = name, target` auto-switches after one dispatch.
- `windowrule`, `windowrulev2`, `workspace`: see below.
- Also exist and are ignored by HyprOSX: `plugin`, `gesture`, `device`, `permission`, `layerrule`, `envd`, `monitorv2`.

Bind flags: `l` locked, `r` release, `c` click, `g` drag, `o` long press, `e` repeat, `n` non-consuming, `m` mouse, `t` transparent, `i` ignore mods, `s` keysym combos, `d` description, `p` bypass inhibit, `u` all submaps, `k` per device.

Keys: XKB keysym names (`Return`, `space`, `Tab`, `Escape`, `BackSpace`, `Delete`, `Left/Right/Up/Down`, `Home`, `End`, `Prior`, `Next`, `minus`, `equal`, `bracketleft`, `bracketright`, `backslash`, `semicolon`, `apostrophe`, `grave`, `comma`, `period`, `slash`, `F1`..`F24`, letters, digits, `KP_0`..`KP_9`), `code:NN`, `mouse:272` (left), `273` (right), `274` (middle), `275`, `276`, `mouse_up`, `mouse_down`, `mouse_left`, `mouse_right`, `catchall` (submaps only), `switch:...`.

## Dispatchers (0.54)

| name | params |
|---|---|
| exec, execr | command (exec allows `[rules]` prefix) |
| pass, sendshortcut, sendkeystate, global, event | (keyboard and portal plumbing) |
| killactive, forcekillactive | none |
| closewindow, killwindow | window |
| signal, signalwindow | signal; window,signal |
| workspace | workspace |
| movetoworkspace, movetoworkspacesilent | workspace or workspace,window |
| togglefloating, setfloating, settiled | empty, `active`, or window |
| fullscreen | mode 0 (fullscreen) or 1 (maximize), action `toggle` (default), `set`, `unset` |
| fullscreenstate | internal client [action] |
| pin | empty, `active`, or window |
| movefocus | l r u d |
| movewindow | direction, or `mon:` monitor, optional ` silent` |
| swapwindow | direction or window |
| centerwindow | none or `1` (respect reserved) |
| resizeactive, moveactive | resizeparams |
| resizewindowpixel, movewindowpixel | resizeparams,window |
| cyclenext | none, `prev`, plus `tiled`, `floating`, `visible`, `hist` |
| swapnext | none or `prev` |
| focuswindow | window |
| focusmonitor | monitor |
| movecursortocorner | 0 bottom-left, 1 bottom-right, 2 top-right, 3 top-left |
| movecursor | x y |
| renameworkspace | id name |
| exit | none |
| movecurrentworkspacetomonitor | monitor |
| focusworkspaceoncurrentmonitor | workspace |
| moveworkspacetomonitor | workspace monitor |
| swapactiveworkspaces | monitor monitor |
| bringactivetotop (deprecated), alterzorder | zheight[,window] |
| togglespecialworkspace | none or name |
| focusurgentorlast, focuscurrentorlast | none |
| togglegroup, changegroupactive, lockgroups, lockactivegroup, moveintogroup, moveoutofgroup, movewindoworgroup, movegroupwindow, denywindowfromgroup, setignoregrouplock | group features |
| submap | name or `reset` |
| setprop | window property value |
| tagwindow | tag [window] |
| toggleswallow, dpms, forceidle, forcerendererreload | misc |
| pseudo | empty, `active`, or window |
| layoutmsg | layout message (see algorithms doc) |
| splitratio | floatvalue (legacy, same as `layoutmsg splitratio`) |

Parameter types:
- window: class regex (default), `class:`, `initialclass:`, `title:`, `initialtitle:`, `tag:`, `pid:`, `address:0x...`, `activewindow`, `floating`, `tiled`.
- workspace: id; `+N`/`-N`; `m+N`, `m-N`, `m~N`; `r+N`, `r~N`; `e+N`, `e-N`, `e~N`; `name:NAME`; `previous`, `previous_per_monitor`; `empty` with `m`/`n` suffixes; `special`, `special:name` (only for movetoworkspace*). Numeric ids are 1 to 2147483647.
- direction: `l r u d`.
- monitor: direction, id, name, `current`, relative `+1`/`-1`.
- resizeparams: relative `dx dy` (or `dx% dy%` of window size), or `exact W H` (or `exact W% H%` of screen).
- floatvalue: relative `+0.2`/`-0.2` or `exact 0.5`.

## Window rules

0.53/0.54 syntax:

```
windowrule = <effect> <args>, match:<prop> <value>[, ...]     # anonymous, any order
windowrule {
  name = rule-name
  match:class = kitty
  border_size = 10
}
```

- All props must match; at least one prop; one prop of each type per rule; rules run top to bottom; named rules before anonymous; last match wins on conflict.
- Props: `match:class`, `match:title`, `match:initial_class`, `match:initial_title`, `match:xdg_tag` (RE2 regex, full match since 0.46, case-sensitive, `negative:` prefix negates); `match:tag`; bools `match:xwayland`, `match:float`, `match:fullscreen`, `match:pin`, `match:focus`, `match:group`, `match:modal`; `match:fullscreen_state_client`, `match:fullscreen_state_internal` (0..3); `match:workspace` (id, `name:x`, or selector); `match:content`.
- Static effects (evaluated once at open): `float`, `tile`, `fullscreen`, `maximize`, `fullscreen_state`, `move`, `size`, `center`, `pseudo`, `monitor`, `workspace [silent|unset]`, `no_initial_focus`, `pin`, `group`, `suppress_event`, `content`, `no_close_for`.
- Dynamic effects: `persistent_size`, `no_max_size`, `stay_focused`, `animation`, `border_color` (active [inactive]), `idle_inhibit`, `opacity`, `tag`, `max_size`, `min_size`, `border_size`, `rounding`, `rounding_power`, `allows_input`, `dim_around`, `decorate`, `focus_on_activate`, `keep_aspect_ratio`, `nearest_neighbor`, `no_anim`, `no_blur`, `no_dim`, `no_focus`, `no_follow_mouse`, `no_shadow`, `no_shortcuts_inhibit`, `no_screen_share`, `no_vrr`, `opaque`, `force_rgbx`, `sync_fullscreen`, `immediate`, `xray`, `render_unfocused`, `scroll_mouse`, `scroll_touchpad`.
- `move` and `size` take two expressions without inner spaces, using `monitor_w`, `monitor_h`, `window_x`, `window_y`, `window_w`, `window_h`, `cursor_x`, `cursor_y`, e.g. `move (monitor_w*0.5) 100`.

Older forms still in dotfiles:
- 0.51/0.52: `windowrule = float, class:kitty, title:kitty` (effects first, then `field:regex`).
- 0.45 to 0.47: `windowrulev2 = float, class:(kitty), title:(kitty)`; v1 `windowrule = float, ^(kitty)$`.
- Old matcher names: `floating`, `pinned`, `initialClass`, `initialTitle`, `fullscreenstate`, `onworkspace`, `xdgtag`. Old effect names are fused lowercase: `noinitialfocus`, `bordercolor`, `bordersize`, `noanim`, `nofocus`, `suppressevent`, `maxsize`, `minsize`, `stayfocused`, `noborder`, `norounding`.
- 0.51 `move` accepts pixels or percentages (`100%-w-`, `cursor X Y`, `onscreen`); `size` accepts pixels or `%`, `<`/`>` for max/min.

## Workspace rules

```
workspace = SELECTOR, rule:value, rule:value
```

- Selector: id, `name:x`, `special:x`, or filters (match only existing workspaces): `r[A-B]`, `s[bool]`, `n[bool|s:str|e:str]`, `m[monitor]`, `w[(flags)A-B|X]` (flags `t` tiled, `f` floating, `g` groups, `v` visible, `p` pinned), `f[-1|0|1|2]` (fullscreen state). Filters can be concatenated: `w[tv1]s[false]`.
- Rules: `monitor:`, `default:`, `gapsin:`, `gapsout:`, `bordersize:`, `border:`, `shadow:`, `rounding:`, `decorate:`, `persistent:`, `on-created-empty:`, `defaultName:`, `layoutopt:orientation:top`. Lua-era docs also show `layout:` per workspace.
- Smart gaps example: `workspace = w[tv1], gapsout:0, gapsin:0` and `workspace = f[1], gapsout:0, gapsin:0`.

## Example config (v0.54.3 example/hyprland.conf, look-and-feel part)

```
general {
    gaps_in = 5
    gaps_out = 20
    border_size = 2
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)
    resize_on_border = false
    allow_tearing = false
    layout = dwindle
}
decoration {
    rounding = 10
    rounding_power = 2
    active_opacity = 1.0
    inactive_opacity = 1.0
    shadow { enabled = true; range = 4; render_power = 3; color = rgba(1a1a1aee) }
    blur { enabled = true; size = 3; passes = 1; vibrancy = 0.1696 }
}
animations {
    enabled = yes, please :)
    bezier = easeOutQuint,   0.23, 1,    0.32, 1
    bezier = easeInOutCubic, 0.65, 0.05, 0.36, 1
    bezier = linear,         0,    0,    1,    1
    bezier = almostLinear,   0.5,  0.5,  0.75, 1
    bezier = quick,          0.15, 0,    0.1,  1
    animation = global,        1,     10,    default
    animation = border,        1,     5.39,  easeOutQuint
    animation = windows,       1,     4.79,  easeOutQuint
    animation = windowsIn,     1,     4.1,   easeOutQuint, popin 87%
    animation = windowsOut,    1,     1.49,  linear,       popin 87%
    animation = fadeIn,        1,     1.73,  almostLinear
    animation = fadeOut,       1,     1.46,  almostLinear
    animation = fade,          1,     3.03,  quick
    animation = layers,        1,     3.81,  easeOutQuint
    animation = layersIn,      1,     4,     easeOutQuint, fade
    animation = layersOut,     1,     1.5,   linear,       fade
    animation = fadeLayersIn,  1,     1.79,  almostLinear
    animation = fadeLayersOut, 1,     1.39,  almostLinear
    animation = workspaces,    1,     1.94,  almostLinear, fade
    animation = workspacesIn,  1,     1.21,  almostLinear, fade
    animation = workspacesOut, 1,     1.94,  almostLinear, fade
    animation = zoomFactor,    1,     7,     quick
}
dwindle {
    pseudotile = true
    preserve_split = true
}
master {
    new_status = master
}
```

(The real file writes `shadow` and `blur` as multi-line blocks; they are compressed here.)

Example binds: `$mainMod = SUPER`; `bind = $mainMod, Q, exec, $terminal`; `bind = $mainMod, C, killactive,`; `bind = $mainMod, V, togglefloating,`; `bind = $mainMod, P, pseudo,`; `bind = $mainMod, J, layoutmsg, togglesplit`; arrows `movefocus`; `1..0` `workspace`; `SHIFT 1..0` `movetoworkspace`; `S` `togglespecialworkspace, magic`; `SHIFT S` `movetoworkspace, special:magic`; `mouse_down`/`mouse_up` `workspace, e+1`/`e-1`; `bindm = $mainMod, mouse:272, movewindow`; `bindm = $mainMod, mouse:273, resizewindow`.

## hyprctl and IPC

- Socket 1 request: `[flags]/command args`, flags such as `j` (JSON); `[[BATCH]]` then commands separated by `;`. One request per connection; the server answers and closes.
- Commands: `dispatch`, `keyword`, `reload [config-only]`, `kill`, `notify`, `dismissnotify`, `seterror`, `getoption`, `setprop`, `getprop`, `version`, `monitors [all]`, `workspaces`, `activeworkspace`, `workspacerules`, `clients`, `devices`, `decorations`, `binds`, `activewindow`, `layers`, `splash`, `cursorpos`, `animations`, `instances`, `layouts`, `configerrors`, `rollinglog`, `locked`, `descriptions`, `submap`.
- `dispatch` and `keyword` answer `ok` or an error.
- `clients` / `activewindow` JSON fields: `address`, `mapped`, `hidden`, `at`, `size`, `workspace {id, name}`, `floating`, `monitor`, `class`, `title`, `initialClass`, `initialTitle`, `pid`, `xwayland`, `pinned`, `fullscreen`, `fullscreenClient`, `overFullscreen`, `grouped`, `tags`, `swallowing`, `focusHistoryID`, `inhibitingIdle`, `xdgTag`, `xdgDescription`, `contentType`, `stableId`.
- `workspaces` / `activeworkspace`: `id`, `name`, `monitor`, `monitorID`, `windows`, `hasfullscreen`, `lastwindow`, `lastwindowtitle`, `ispersistent`, `tiledLayout`.
- `monitors`: `id`, `name`, `description`, `make`, `model`, `serial`, `width`, `height`, `refreshRate`, `x`, `y`, `activeWorkspace {id, name}`, `specialWorkspace {id, name}`, `reserved [4]`, `scale`, `transform`, `focused`, `dpmsStatus`, `vrr`, `disabled`, and more.
- Plain text form: `Window <addr> -> <title>:` then tab-indented `key: value` lines.
- Socket 2 events (`EVENT>>DATA`): `workspace`, `workspacev2`, `focusedmon`, `activewindow`, `activewindowv2`, `fullscreen`, `monitoradded`, `monitorremoved`, `createworkspace`, `destroyworkspace`, `moveworkspace`, `renameworkspace`, `activespecial`, `openwindow`, `closewindow`, `movewindow`, `submap`, `changefloatingmode`, `urgent`, `windowtitle`, `configreloaded`, `pin`, `minimized`, and more.
