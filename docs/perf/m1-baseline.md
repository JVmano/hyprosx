# M1 performance baseline

Measured 2026-10-15 on macOS 27.0.1 (build 26A434), M4 MacBook Pro (Mac16,1), 16 GB, docked to a PHL 499P9 (5120x1440). Build 77125b7, signed with the local identity.

| measure | result | target |
|---|---|---|
| tracked apps | 11 | - |
| CPU over 61 s (owner using the Mac, not idle) | 0.10 s, about 0.16% | - |
| CPU over 60 s idle, after the status-item fix | 0.01 s, about 0.02% | below 0.1% when idle |
| resident memory | 28.5 to 29.3 MB | below 50 MB |
| `hyprctl -q activewindow`, average of 100 calls | 7.98 ms (process start alone: 5.30 ms) | below 10 ms |
| AX writes in that window | 30, 1 error | - |
| slowest apps by average AX write time | Zen 42 ms, Slack 35 ms, kitty 32 ms, Ghostty 15 ms, OrbStack 6 ms | - |

The first idle measurement gave 0.15%. A sample showed the menu bar button redrawing on every app title change; the status item now skips unchanged titles, and idle CPU fell to 0.02%. Resident memory right after a restart was 37.6 MB.
