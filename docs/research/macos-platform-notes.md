# macOS platform notes for HyprOSX

Collected 2026-10-10 on macOS 27.0.1 (build 26A434), M4 MacBook Pro (Mac16,1), Swift 6.4, Xcode 27.0. Probe results come from scratch programs run on this Mac; the rest comes from web research with sources in the session log.

## Probes run on this Mac

| probe | result |
|---|---|
| `NSWindow.order(.below, relativeTo: <Ghostty window number>)` | Works across apps. Our window sat between Ghostty and Mail in `CGWindowListCopyWindowInfo` order. |
| A parked window (1 pt on screen) covered by an opaque 3 pt window | Still `occlusionState.visible`. Parked windows keep rendering; a cover does not help. |
| `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` | about 0.1 ms per call |
| SkyLight symbols present | `SLSMainConnectionID`, `SLSHWCaptureWindowList`, `SLSOrderWindow`, `SLSSetWindowAlpha`, `SLSSetWindowTransform`, `SLSMoveWindow`, `SLSRequestNotificationsForWindows`, `SLSWindowSetShadowProperties`, `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo`, `SLSCaptureWindowsContentsToRectWithOptions`; `_AXUIElementGetWindow` in ApplicationServices |
| `swift test` with Swift Testing | works with Command Line Tools and with Xcode |
| Terminal (Ghostty) Accessibility trust | not trusted; live tests run through HyprOSX.app and `hyprctl` |
| Screens | one: "Built-in Retina Display", frame 1512x982 pt, visible 1512x950, scale 2 |
| `NSScreen.screensHaveSeparateSpaces` | false (setting is off) |
| Code-signing identities | none |

## Accessibility (AX)

- Calls are synchronous IPC into the target app's main thread. A busy app blocks the caller. The default messaging timeout is about 6 s; AltTab and others set 1 s with `AXUIElementSetMessagingTimeout`.
- The first AX call to a process costs about 25 ms (handshake).
- There is no settable frame attribute; position and size are separate calls. Order for moves across screens: size, position, size (macOS fits sizes to the current display).
- `AXEnhancedUserInterface` makes AX moves animate inside the app and breaks rapid moves. Turn it off on the app element before moving and restore it afterwards (Rectangle, yabai, Hammerspoon, Glide, Rift). Restore too early and the bug returns; Glide restores at the end of the whole animation, Rift ref-counts.
- Apps can silently refuse a frame (minimum sizes). Read the frame back when exactness matters.
- `kAXUIElementDestroyedNotification` is unreliable for some close paths (AeroSpace notes close-button clicks on unfocused windows).
- `_AXUIElementGetWindow(AXUIElement, *CGWindowID)` gives the window id; it can fail transiently (Rectangle #1673). `NSWindow.windowNumber` can exceed UInt32 on Tahoe (forum report); window ids from AX are uint32.
- macOS does not let a window go fully off-screen: at least 1 pt (2 pt on Retina per OmniWM) stays visible.

## Animation techniques without SIP

- Rift, Glide, OmniWM, Loop and Hammerspoon animate with per-frame AX writes. Shared tricks: one thread per app, keep only the newest pending frame per window, display link at the screen refresh rate (Rift, OmniWM) or a 100 Hz timer (Glide), position-only frames with the size set at the midpoint and the end (Glide: "Don't animate size, too slow"; Rift: size at progress 0.5), EUI off for the whole animation, dedupe against the last applied frame, skip read-backs during the animation and verify at settle.
- yabai's snapshot proxies (`SLSHWCaptureWindowList` + own proxy windows + transforms) need the Dock scripting addition, so SIP partly off.
- Alpha, transform, level and move of other processes' windows through SkyLight need the Dock's universal-owner connection. Without SIP these calls do nothing on foreign windows.
- `SLSHWCaptureWindowList` needs Screen Recording and cannot capture partly off-screen windows. ScreenCaptureKit single captures took 233 ms to several seconds in field reports. Screen Recording has a monthly re-approval prompt since macOS 15; only the persistent-content-capture entitlement (screen sharing products) avoids it.
- No known way to mirror another app's window live (`CALayerHost` needs a context id that only the owner can share).

## Hiding windows

- AeroSpace parks windows in the bottom-right or bottom-left corner of their monitor with a 1 pt sliver, chosen so the corner is free of other monitors.
- Parked windows keep rendering. OmniWM measured WindowServer CPU 42.2% visible, 20.0% parked, 9.4% truly hidden (M1 Pro, macOS 26.5). AeroSpace issue #790: about 8% CPU for hidden-workspace windows versus 0.2% in a background Space.
- Hiding the app (`NSRunningApplication.hide()`) makes its windows truly hidden.

## Borders

- JankyBorders and OmniWM create their own windows and order them below the target with `SLSTransactionOrderWindow`; JankyBorders tracks the target through `SLSRegisterNotifyProc` events. The public `NSWindow.order(_:relativeTo:)` works across apps (probe above).
- Window corner radius: macOS 15 about 10 pt; macOS 26 Tahoe 16 pt for title-bar windows and 26 pt for toolbar windows; macOS 27 reported 20 pt default (unconfirmed). JankyBorders reads the real radius with `SLSWindowIteratorGetCornerRadii` on 26+, fallback 9.

## Hotkeys and input

- Carbon `RegisterEventHotKey`: macOS 15.0 rejected Option-only and Option+Shift-only hotkeys; 15.2 beta 2 lifted it (one later report of recurrence). AeroSpace still uses Carbon with Alt binds.
- `CGEventTap` keyboard taps need Input Monitoring; active taps need Accessibility. Secure Input (password fields, terminal Secure Keyboard Entry) blocks both Carbon hotkeys and taps. `CGSessionCopyCurrentDictionary()` exposes `kCGSSessionSecureInputPID`.
- Run an event tap on its own thread; a tap starved by a busy main thread gets disabled by timeout (yabai #2829).

## Capture and window list

- `CGWindowListCreateImage` is obsoleted in the macOS 15 SDK and returns gray images on macOS 27 beta 4+ for some cases.
- On macOS 27 `kCGWindowOwnerName` is populated without Screen Recording.

## Conflicting macOS settings

- Stage Manager (`com.apple.WindowManager GloballyEnabled`).
- Edge-drag and Option-drag tiling (`com.apple.WindowManager EnableTilingByEdgeDrag`, `EnableTopTilingByEdgeDrag`, `EnableTilingOptionAccelerator`).
- Click wallpaper to reveal desktop (`com.apple.WindowManager EnableStandardClickToShowDesktop`).
- Automatically rearrange Spaces (`com.apple.dock mru-spaces`), already 0 here.
- Displays have separate Spaces (`com.apple.spaces spans-displays`), already off here; AeroSpace recommends off.

## AeroSpace lessons (performance)

- Every AX notification, app activation and mouse-up triggers a full refresh: every regular app's `kAXWindowsAttribute`, a liveness check for every window, a layout of all visible workspaces, and a position write for every parked window.
- 0.18 introduced a thread per app and cancellable, coalesced AX jobs; heavy apps (Godot, Unity, IntelliJ, mpv) still cause delays.
- The CLI takes 100 to 300 ms because the server is single-threaded.
- Useful pieces to keep: per-app threads with a CFRunLoop, the window and dialog heuristics, the corner choice, size-position-size, EUI toggling, delaying new-window detection while the mouse button is down (tab drag-out), skipping the lock screen app and our own pid.
