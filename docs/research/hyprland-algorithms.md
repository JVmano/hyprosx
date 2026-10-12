# Hyprland algorithms to port

Source: Hyprland main (HEAD 663b29b, 2026-10-09) and hyprutils main (95983ee, 2026-09-21), read through a summarizing fetch tool. Formulas are as quoted. Items marked "verify" were only partly quoted.

Coordinates are top-left origin, y grows down. `STICKS(a, b)` is `abs(a - b) < 2`. `MIN_WINDOW_SIZE` is 20.

Direction enum: `UP=0, RIGHT=1, DOWN=2, LEFT=3, DEFAULT=-1`. Characters: `r`, `l`, `t`/`u`, `b`/`d`.

## 1. Dwindle

Node: `parent`, `children[2]`, `target`, `box`, `splitTop`, `splitRatio`, `isNode`. `splitTop == true` means a top/bottom split.

Defaults: `force_split=0`, `permanent_direction_override=false`, `preserve_split=false`, `smart_split=false`, `smart_resizing=true`, `split_width_multiplier=1` (0.1 to 3), `use_active_for_splits=true`, `default_split_ratio=1` (0.1 to 1.9), `split_bias=0`, `precise_mouse_move=false`, `special_scale_factor=1`. `pseudotile` was removed in 0.55; pseudo is per window, default pseudo size `{1280, 720}`.

### 1a. Which node is split (addTarget)

```
MOUSE = overrideFocalPoint ?? cursor
if (ws is the active workspace of the active monitor, or the active special) && !use_active_for_splits:
    OPENINGON = node(window under cursor)
    if !OPENINGON && cursor is on a reserved area: OPENINGON = closestNode(MOUSE)
else if use_active_for_splits || overrideFocalPoint:
    if overrideFocalPoint: OPENINGON = closestNode(focal)
    else if focused && !focused.floating && focused != new && focused.ws == ws: OPENINGON = node(focused)
    if !OPENINGON: OPENINGON = closestNode(MOUSE, skip = new)
else: OPENINGON = firstNode()
```

- Fail-safe: if `(!OPENINGON || OPENINGON.target == new) && nodeCount > 1`, use the first node whose target is not the new window.
- First window: `node.box = workArea`, done.
- Otherwise create `NEWPARENT` with `box = OPENINGON.box`, `parent = OPENINGON.parent`, `splitRatio = clamp(default_split_ratio, 0.1, 1.9)`.

`closestNode(point, skip)`: smallest `vecToRectDistanceSquared(point, box)`; ties keep the earlier node.

```
DX = max(0, p1.x - v.x, v.x - p2.x); DY = max(0, p1.y - v.y, v.y - p2.y); return DX*DX + DY*DY
```

### 1b. Split direction and child order

```
SIDEBYSIDE = box.w > box.h * split_width_multiplier
NEWPARENT.splitTop = !SIDEBYSIDE
if overrideDirection != DEFAULT:                 // preselect or movewindow
    vertical override if dir is UP/DOWN, horizontal if LEFT/RIGHT
    UP or LEFT: new window first; RIGHT or DOWN: new window second
    if !permanent_direction_override: overrideDirection = DEFAULT
else if smart_split || (precise_mouse_move && dragging):
    DELTA = MOUSE - center(box); SLOPE = DELTA.y / DELTA.x; PROP = box.h / box.w
    if abs(SLOPE) < PROP: splitTop = false; new first if DELTA.x <= 0 else second
    else:                 splitTop = true;  new first if DELTA.y <= 0 else second
else if force_split == 0 || overrideFocalPoint || dragging:
    new first if (SIDEBYSIDE && MOUSE.x < box.x + box.w/2) || (!SIDEBYSIDE && MOUSE.y < box.y + box.h/2)
    else new second
else if force_split == 1: new first
else: new second
if split_bias && children[0] == new: splitRatio = 2 - splitRatio
```

`DELTA.x == 0` makes the slope test fail, so the top/bottom branch runs.

### 1c. Recalc (box propagation)

```
recalc(node, hOverride, vOverride):
  if node has children:
    if !preserve_split && !smart_split && !precise_mouse_move:
        splitTop = box.h * split_width_multiplier > box.w      // re-evaluated on every recalc
    if vOverride: splitTop = true else if hOverride: splitTop = false
    if !splitTop: FIRST = box.w/2 * splitRatio; c0 = {x, y, FIRST, h}; c1 = {x+FIRST, y, w-FIRST, h}
    else:         FIRST = box.h/2 * splitRatio; c0 = {x, y, w, FIRST}; c1 = {x, y+FIRST, w, h-FIRST}
    recurse into children (overrides not propagated)
  else: window box = node.box
```

### 1d. Ratio changes

- `layoutmsg splitratio V [exact]`: `ratio = exact ? V : parent.ratio + V`, clamp 0.1 to 1.9, acts on the focused window's parent, then recalc parent.
- `resizeactive dx dy` calls `resizeTarget(delta, corner = NONE)`. Exact sizes become `delta = size - currentSize`.

```
WA = monitor box minus reserved; BOX = tile box (before gaps)
DISPLAYLEFT = STICKS(BOX.x, WA.x); DISPLAYRIGHT = STICKS(BOX.x+BOX.w, WA.x+WA.w); same for TOP/BOTTOM
allowed = delta; if DISPLAYLEFT && DISPLAYRIGHT: allowed.x = 0; if DISPLAYTOP && DISPLAYBOTTOM: allowed.y = 0
```

Smart resizing (default):

```
LEFT = edgeLeft(corner) || DISPLAYRIGHT; RIGHT = edgeRight(corner) || DISPLAYLEFT
TOP = edgeTop(corner) || DISPLAYBOTTOM;  BOTTOM = edgeBottom(corner) || DISPLAYTOP; NONE = corner == NONE
for cur = node; cur.parent; cur = cur.parent:
    p = cur.parent
    if      !VOUTER && p.splitTop && (NONE || (TOP && p.c1 == cur) || (BOTTOM && p.c0 == cur)): VOUTER = cur
    else if !VOUTER && !VINNER && p.splitTop: VINNER = cur
    else if !HOUTER && !p.splitTop && (NONE || (LEFT && p.c1 == cur) || (RIGHT && p.c0 == cur)): HOUTER = cur
    else if !HOUTER && !HINNER && !p.splitTop: HINNER = cur
    if VOUTER && HOUTER: break
if HOUTER:
    HOUTER.parent.ratio = clamp(r + allowed.x * 2 / HOUTER.parent.box.w, 0.1, 1.9)
    if HINNER:
        ORIGINAL = HINNER.box.w; recalc(HOUTER.parent)
        HINNER.parent.ratio = HINNER is c0 ? clamp((ORIGINAL - allowed.x) / HINNER.parent.box.w * 2, 0.1, 1.9)
                                           : clamp(2 - (ORIGINAL + allowed.x) / HINNER.parent.box.w * 2, 0.1, 1.9)
        recalc(HINNER.parent)
    else recalc(HOUTER.parent)
if VOUTER: same with y and h
```

Non-smart: `PPARENT = parent`; walk up to the first ancestor whose `splitTop` differs. With none, only one axis changes: `ratio = clamp(r + allowed.x * 2 / PPARENT.box.w, 0.1, 1.9)` (y/h for stacked). With one, `SIDECONTAINER` is the side-by-side one and `TOPCONTAINER` the other; `allowed.x *= 2 / SIDECONTAINER.box.w`, `allowed.y *= 2 / TOPCONTAINER.box.h`, both ratios clamped.

Pseudo resize: `fixed = delta` (negated on left/top corners), `pseudo = clamp(pseudo + fixed, 20, tileSize)`.

### 1e. Removal

- Single node: erase, no recalc.
- Otherwise `SIB` = other child; `SIB.parent = parent.parent`; replace the parent in the grandparent's slot (or SIB becomes root); erase both; recalc. SIB keeps its own `splitTop` and `splitRatio`.
- Next focus candidate: `closestNode(old.center)`, else the first node.

### 1f. Geometry (per window)

```
workArea = monitor box with reserved area applied, then shrunk by gaps_out (per side)
nodeBox = round(tile box)
L = STICKS(nodeBox.x, workArea.x); R = STICKS(nodeBox.maxX, workArea.maxX); T, B likewise
offTL = (L ? 0 : gaps_in.left, T ? 0 : gaps_in.top); offBR = (R ? 0 : gaps_in.right, B ? 0 : gaps_in.bottom)
pos = nodeBox.pos + offTL; size = nodeBox.size - offTL - offBR
pseudo (if set): scale down to fit keeping aspect, then center inside (pos, size)
border: pos += border_size; size -= 2 * border_size   (border ring drawn in that inset)
window frame = round(pos, size)
```

Neighbours are `2 * gaps_in` apart at their border outer edges. A lone window gets no `gaps_in`. Floating work area uses `float_gaps` (falls back to `gaps_out` if negative).

### 1g. Directional move and swap

Focal point for a direction from the window's tile box BB: UP `(BB.x + BB.w/2, BB.y - 1)`, DOWN `(BB.x + BB.w/2, BB.maxY + 1)`, LEFT `(BB.x - 1, BB.y + BB.h/2)`, RIGHT `(BB.maxX + 1, BB.y + BB.h/2)`.

`movewindow dir`:
```
FOCAL = focalPoint(dir); MON = monitor containing FOCAL
if MON != current monitor: if window_direction_monitor_fallback: move to MON's active workspace at FOCAL; return
if parent && ((UP && parent.splitTop && node is c1 && c0 is a leaf) || (DOWN && parent.splitTop && node is c0 && c1 is a leaf)
           || (LEFT && !parent.splitTop && node is c1 && c0 is a leaf) || (RIGHT && !parent.splitTop && node is c0 && c1 is a leaf)):
    overrideDirection = dir
remove(window); add(window, overrideFocalPoint = FOCAL)
```

`swapwindow dir`: target from directional focus search; dwindle swaps the window pointers of the two nodes (tree shape and ratios unchanged).

Layout messages on the focused window's node:
- `togglesplit`: `parent.splitTop = !parent.splitTop`; recalc parent. Needs a parent and no fullscreen.
- `swapsplit`: swap parent's children; recalc.
- `rotatesplit [angle=90]`: `n = ((angle/90 % 4) + 4) % 4`; n=1: swap if splitTop, toggle; n=2: swap; n=3: swap if !splitTop, toggle; recalc.
- `preselect u|t|d|b|l|r`: sets `overrideDirection`; anything else clears it.
- `movetoroot [window] [unstable]`: exchange the window with the root's other subtree; when stable (default), swap the root's children afterwards; recalc root. Fails when the node is already a root child, fullscreen, or has no parent.

## 2. Master

Orientation enum `LEFT=0, TOP=1, RIGHT=2, BOTTOM=3, CENTER=4`. Node: `isMaster`, `percMaster` (starts at `mfact`), `percSize` (1.0). The node list order drives everything.

Defaults: `mfact=0.55`, `new_status=slave`, `new_on_top=false`, `new_on_active=none`, `orientation=left`, `slave_count_for_center_master=2`, `center_master_fallback=left`, `smart_resizing=true`, `drop_at_cursor=true`, `always_keep_position=false`, `allow_small_split=false`, `special_scale_factor=1`, `focus_master_on_close=false`.

### Geometry

```
M masters, S slaves, N = M + S, W/H = workArea size, P = workArea origin
orientation = explicitOrientation ?? config; CENTER needs S >= slave_count_for_center_master, else use center_master_fallback
totalSize = (TOP||BOTTOM) ? W : H; masterAvg = totalSize/M; slaveAvg = totalSize/S
smart: masterAcc = sum(totalSize/M * percSize over masters); slaveAcc likewise
```

- Single window (N == 1, no center master): full work area; with `always_keep_position`, width `W * percMaster` placed right/center/left by orientation.
- Masters TOP/BOTTOM: `masterH = S ? H * percMaster : H`; y = BOTTOM ? H - masterH : 0; widths left to right: `w = mastersLeft > 1 ? widthLeft / mastersLeft * percSize : widthLeft`, capped at `0.9 * widthLeft` while more remain; smart: `percSize *= W / masterAcc; w = masterAvg * percSize`.
- Masters LEFT/RIGHT/CENTER: `w = W * percMaster` if S > 0 or center, else W; x = RIGHT ? W - w : (center ? (W - w)/2 : 0); heights top to bottom with the same formula on H.
- Slaves TOP/BOTTOM: `h = H - masterH`, y = TOP ? masterH : 0, widths as above.
- Slaves LEFT/RIGHT: `w = W - masterW`, x = LEFT ? masterW : 0, heights as above.
- Slaves CENTER: `colW = (W - masterW) / 2`; slaves alternate sides starting on the right when `center_master_fallback == right`, else on the left; left column count `1 + (n-1)/2` (integer) when starting left; each column stacks heights as above.

Non-smart `percSize` is a weight with a 90% cap; smart mode renormalizes `percSize` each pass so the sum equals the count.

### New windows

```
OPENINGON = focused tiled window's node on this workspace, else the master
becomesMaster = new_status == master || nodeCount == 1
             || (nodeCount > 2 && !firstMap && OPENINGON?.isMaster)
             || (new_status == inherit && OPENINGON?.isMaster)
insertion: if new_on_active != none && !becomesMaster && focused node exists
              && !(focused.isMaster && (masterCount == 1 || new_status == slave)):
               insert before focused if new_on_active == before, else after
           else insert at start if new_on_top, else at end
master branch: demote one existing master (last master if new_on_active == before, else first);
               new.percMaster = demoted.percMaster
slave branch: new.percMaster = lastSplitPercent
```

### Removal

```
if node.isMaster && (masterCount <= 1 || allow_small_split): first slave becomes master, inherits percMaster
erase node
if all remaining nodes are masters and there were more than one: demote the last node
if one node left: it becomes master
```

Next focus: master if `focus_master_on_close`, else the closest node to the old center, else the master.

### Layout messages

- `swapwithmaster [master|child|auto] [ignoremaster]`: non-master focused: swap with master; `child` focuses the old master, else focus stays on the moved window (now master). Master focused: `ignoremaster` does nothing; else swap with the first slave; `master` focuses the new master, else focus stays on the old master.
- `focusmaster [master|previous|auto]`: not on master: focus master (store previous for `previous`). On master: `master` nothing, `previous` back to the stored window, `auto` first slave.
- `cyclenext|cycleprev [loop|noloop]` and `swapnext|swapprev [loop|noloop]`: next in list order within the same group (masters, then slaves); when the group ends, wrap to the other group; `noloop` stops at the ends.
- `addmaster`: needs `M + 2 <= N` unless `allow_small_split`; promote the focused slave, or the first slave if the master is focused.
- `removemaster`: needs `N >= 2 && M >= 2`; demote the focused master, else the last master.
- `rollnext|rollprev`: rotate the list one step forward or back; the new first master gets focus.
- `mfact [exact] V`: `percMaster = clamp(exact ? V : first.percMaster + V, 0.05, 0.95)` on the first master.
- `orientationleft|right|top|bottom|center|next|prev|cycle <list>`: set or step the workspace orientation (enum order left, top, right, bottom, center).

Resize: horizontal delta changes every master's `percMaster` by `dx / monitorW` (sign by orientation, doubled for center with enough slaves), clamp 0.05 to 0.95. The stack-axis delta changes `percSize` (non-smart: `clamp(percSize + d/SIZE, 0.05, 1.95)`; smart: neighbours share the change, verify).

Master `movewindow dir`: find the neighbour with directional focus; same workspace: swap; else move to that workspace at the focal point.

## 3. Bezier

- Control points P1, P2 with fixed P0 = (0,0), P3 = (1,1).
- 255 baked points at `t = (i + 1) / 255` for i in 0..<255, each `(x(t), y(t))` of the cubic.
- `y(x)`: x >= 1 gives 1, x <= 0 gives 0; otherwise find the baked segment around x (halving walk or binary search), then linear interpolation; zero-width segment returns the lower y.
- Built-ins: `default` = P1 (0.0, 0.75), P2 (0.15, 1.0); `linear` = (0,0), (1,1). Unknown names fall back to `default`.
- Control point values must be in -1 to 2 (Lua binding); y outside 0..1 means overshoot.

## 4. Animation timing and tree

- Duration = `speed * 100 ms`. `percent = clamp(elapsed / duration, 0, 1)`; `value = begun + (goal - begun) * bezier.y(percent)`.
- Retarget: a new goal sets `begun = current value` and restarts the timer. Same goal is a no-op.
- Disabled leaf, `animations:enabled = false` or `no_anim`: jump to the goal.
- Tree: `global` > `windows` (`windowsIn`, `windowsOut`, `windowsMove`), `layers` (...), `fade` (`fadeIn`, `fadeOut`, `fadeSwitch`, `fadeShadow`, `fadeDim`, `fadeLayers*`, `fadePopups*`, `fadeDpms`), `border`, `borderangle`, `zoomFactor`, `monitorAdded`, `workspaces` (`workspacesIn`, `workspacesOut`, `specialWorkspace` (`specialWorkspaceIn`, `specialWorkspaceOut`)).
- Code defaults: `global` on, speed 8, `default`; `borderangle` off, speed 1, `default`.
- Inheritance is all or nothing per node: a node takes enabled, speed, curve and style from its nearest overridden ancestor.

## 5. Animation styles

Window open (`windowsIn`) and close (`windowsOut`). The style string is split on spaces.

- `popin [N%]` (also any unknown or empty style, with N = 0): `size = clamp(goalSize * N/100, 5, goalSize)`, centered on the goal. Open animates from it; close animates to it.
- `gnomed`: zero-height line at the vertical center of the goal.
- `slide [top|bottom|left|right]`: size stays the goal size. bottom: `(goal.x, mon.maxY)`; left: `goal.pos - (goal.w, 0)`; right: `goal.pos + (goal.w, 0)`; top or other: `(goal.x, mon.y - goal.h)`. No argument: nearest monitor edge from the window middle, tie order bottom, left, right, top.
- `windowsMove`: position and size retarget independently with the same curve.

Workspace switch direction: going to a higher id slides left (old out to the left, new in from the right); lower id the reverse; `animations:workspace_wraparound` treats first and last as adjacent. Special workspace open counts as left, close as right.

Style parsing: `vert` for `slidevert`/`slidefadevert`; a side word overrides; a trailing `N%` sets the distance (default 100%).

| style | new workspace | old workspace |
|---|---|---|
| `slide` (default) | offset `±(W + gaps_workspaces) * P` to 0 | 0 to the opposite offset |
| `slidevert` | offset `±(H + gaps_workspaces) * P` to 0 | opposite |
| `slidefade N%` | alpha 0 to 1, offset `±W * P` to 0 | alpha 1 to 0, offset to opposite |
| `fade` | alpha 0 to 1 | alpha 1 to 0 |

Special workspaces always fade in addition to the style offset.

`borderangle`: on map (and on focus when not running) sweep the gradient angle by a full turn over the leaf duration; style `loop` restarts it forever.

## 6. Focus direction (movefocus)

```
L = focused window
if !L: try the monitor in that direction (window_direction_monitor_fallback)
C = movefocus_cycles_fullscreen && L fullscreen ? cycle : inDirection(L, dir)
if C: focus C; return
if monitor fallback && monitor in dir exists: focus that monitor's focus candidate; return
if no_focus_fallback: return
if L spans the whole monitor on that axis: return
wrap: search from a 1 px strip at the opposite monitor edge with inDirection
```

`inDirection` (tiled, edge mode): A = origin tile box, B = candidate box.

| dir | adjacency | overlap on the other axis |
|---|---|---|
| LEFT | `isAdjacent(A.x, A.maxX, B.x, B.maxX)` | `min(A.maxY, B.maxY) - max(A.y, B.y)` |
| RIGHT | `isAdjacent(B.x, B.maxX, A.x, A.maxX)` | same |
| UP | `isAdjacent(A.y, A.maxY, B.y, B.maxY)` | `min(A.maxX, B.maxX) - max(A.x, B.x)` |
| DOWN | `isAdjacent(B.y, B.maxY, A.y, A.maxY)` | same |

`isAdjacent(aMin, aMax, bMin, bMax)` (verify edges): `delta = aMin - bMax`; `|delta| < 2` is adjacent; `delta >= 0` is a gap (no); overlap `-delta` is adjacent if neither interval contains the other and `overlap <= 0.5 * min(sizes)`.

Reject when overlap `<= 1`. Skip floating candidates when the origin is tiled (and the reverse first, then retry with the other preference). Winner: method 0 (default) the most recently focused candidate; method 1 the longest overlap. Ties keep the first visited.

Floating origin (vector mode): candidates with `angle = acos(dot(c.mid - o.mid, dirVec) / norms) <= PI/2`; prefer the closest within a `0.3 * PI` cone, else the smallest angle.

## 7. Window placement for hidden workspaces (AeroSpace)

For each monitor compare the bottom-left and bottom-right corners: count how many monitors contain the probe points `corner + (±2, -10% h)`, `corner + (∓10% w, 2)` and `corner + (±2, 2)` (the last one weighted 10). Pick the corner with the lower score.

- Bottom-right park point: `visibleRect.bottomRight - (1, 1)` (top-left of the window).
- Bottom-left park point: `visibleRect.bottomLeft + (1, -1) - (windowWidth, 0)`.
- Zoom (`us.zoom.xos`) gets no 1 px offset.
