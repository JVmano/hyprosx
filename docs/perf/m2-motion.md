# M2 motion and decoration baseline

Measured 2026-10-20 on macOS 27.0.1 (build 26A434), M4 MacBook Pro (Mac16,1), 16 GB, docked to a PHL 499P9 (5120x1440 at 70 Hz). Build 35abffe, installed with `scripts/build-app.sh --install`. The owner used the Mac during every measurement (a Ghostty session and Slack were active), so the CPU rows are not a quiet-machine idle.

| measure | result | target |
|---|---|---|
| tracked apps | 9 | - |
| windows in the switch test | 5 on workspace 1 (3 tiled, 2 floating), 5 border rings, 0 dim windows; workspace 2 empty | - |
| CPU over three 60 s windows | 0.10 s, 0.06 s, 0.14 s (0.17%, 0.10%, 0.23%; mean 0.17%) | below 0.1% when idle |
| CPU over a fourth 60 s window, sampler attached | 0.07 s (0.12%) | - |
| main thread in that 60 s sample | blocked in the run loop for 50141 of 50164 samples (99.95%) | - |
| resident memory (`ps`), after 60 s idle, median of 5 samples 5 s apart | 17.0 MB (range 15.3 to 18.0) | below 50 MB |
| physical footprint (`footprint`), same moment | 14 MB | - |
| resident memory (`ps`), 60 s after 42 workspace switches, median of 5 | 16.9 MB (range 16.9 to 19.0); footprint 14 MB, peak 15 MB | below 50 MB |
| resident memory in `hyprctl perf`, right after the first 10 switches | 26.8 MB; 19.4 MB at the next read, after the sampling run | below 50 MB |
| AX writes per workspace switch | 24 and 24.5 (240 and 245 writes over 10 switches 0.6 s apart, two runs); 29 in the 0.4 s loop (931 writes over 32 switches); 0 errors | - |
| CPU per workspace switch | about 23 ms (0.25 s over 10 switches, minus about 0.02 s of background) | - |
| slowest apps by average AX write time (since launch) | Zen 5.20 ms, ChatGPT 4.01 ms, kitty 3.83 ms, Ghostty 3.80 ms, Slack 3.63 ms | - |

Main-thread cost of a motion tick: a 5 s `sample HyprOSX` (1 ms interval, 3244 main-thread samples) ran while a loop sent `hyprctl dispatch workspace 2` and `1` every 0.4 s with the 5 windows and 5 rings above.

| where | main-thread samples | share |
|---|---|---|
| `MotionEngine.tick` | 79 | 2.44% |
| `BorderWindows.move` (the ring placement, inside the tick) | 78 | 2.40% |
| `NSWindow order(.below, relativeTo:)` inside `BorderWindows.move` | 76 | 2.34% |
| `BorderWindows.apply` (outside the tick, from the effect handler) | 16 | 0.49% |
| `DimWindows` | 0 | 0% (the owner config has no dim) |
| blocked in the run loop | 3132 | 96.55% |

The tick cost is almost all one call: `BorderWindows.move` orders the ring below its window on the first tick of each animation (`pending`), and that call waits for a WindowServer reply (`SLSConnectionGetHeldWindowRights`). The per-tick frame placement itself took 2 samples.

The idle samples show where the CPU goes when nothing moves. A 10 s sample caught no main-thread work. In the 60 s sample, 23 of 50164 main-thread samples were busy, all in event handling (`BorderWindows.apply`, `StatusItem.update`, `NSRunningApplication` property fetches). The remaining CPU time is spread over short wake-ups, so a quiet-machine run is still needed to confirm the 0.1% target. M1 measured 0.02% on a quiet Mac.

AX write averages are cumulative since launch (uptime 765 s at the last read), so they include the switch tests (1208 writes in total at that read). `hyprctl perf` lists only the five slowest apps. The M1 averages (Zen 42 ms, Slack 35 ms, kitty 32 ms, Ghostty 15 ms) were taken on a Mac with more window movement and a different build, so the two tables do not compare directly.
