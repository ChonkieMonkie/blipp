# Blipp

A tiny sidekick for the macOS menu bar who shows how your Mac is doing. He sweats when the
CPU works hard, sips juice while charging, juggles when memory gets tight and melts when the
battery is nearly empty. Click him for a panel with the details.

## Build and run

You only need Apple's Command Line Tools (no Xcode):

```bash
./scripts/build.sh
open build/Blipp.app
```

To keep it around, drag `build/Blipp.app` into `/Applications` and turn on
**Launch at login** in Blipp's settings.

## How Blipp decides what to show

Every metric owns one part of the figure, so several things can show at once:

| Part              | Driven by                                        |
| ----------------- | ------------------------------------------------ |
| Body color        | Heat: CPU load or thermal state, whichever is higher |
| Face              | CPU load (sleeping → chilling → working → sweating → burning) |
| Hands             | Charging, charge limit, heat, network, disk      |
| Above the head    | Memory pressure (juggling), plus Zzz, flame, clouds |

Three emergencies take over the whole figure: battery under 5 %, critical thermal state,
and heavy swapping. The CPU level uses a 5-second average so Blipp doesn't flinch at every spike.

The menu bar icon is a simplified redraw with thicker lines. It only redraws when its frame
actually changes (a blink, a drop of sweat).

## Staying light

Blipp is meant to run all day, so the work he does follows what's on screen:

- **Panel closed:** about 0.5 % of one core and ~1 wake-up per second, ~13 MB of memory.
  The panel's views don't exist; graphs aren't computed; processes, battery details and free
  space refresh every 5–60 s (battery changes still arrive instantly through IOKit notifications).
- **Panel open:** about 3 % of one core. Blipp draws into his own Core Animation layer at 24 fps,
  the charging shimmer is a Core Animation animation, and nothing re-lays out the panel per frame.
- **Displays asleep or user switched out:** sampling pauses completely.
- **Temperature:** each of the 24 die-sensor reads is a slow round trip (~0.8 ms), so they're read
  round-robin (2 per sample with the panel closed, 6 with it open) and averaged with the latest values.
- **Menu bar:** each icon change makes macOS re-snapshot the status item (~8 ms), so the icon only
  changes on real frame changes, and the tooltip text is produced lazily on hover.

Measure for yourself:

```bash
swift build -c release && "$(swift build -c release --show-bin-path)/Blipp" --benchmark
open build/Blipp.app --args --debug-panel-cycle   # opens the panel at 2 s, closes it at 32 s
```

## Where the numbers come from

| Metric        | Source |
| ------------- | ------ |
| CPU per core  | `host_processor_info` |
| Memory        | `host_statistics64`, `vm.swapusage`, `kern.memorystatus_vm_pressure_level` |
| Battery       | IOKit power sources, plus `AppleSmartBattery` for charging watts |
| Temperature   | SoC sensors via the private IOHIDEventSystem API (see `Sources/CSensors`) |
| Thermal state | `ProcessInfo.thermalState` |
| Network       | 64-bit interface counters (`NET_RT_IFLIST2`), `NWPathMonitor` for offline |
| Disk          | `IOBlockStorageDriver` statistics, free space of the boot volume |
| Top processes | `proc_pid_rusage`, counted like Activity Monitor (100 % = one core) |

The temperature reading uses a private API, which is fine for a personal app but means
Blipp couldn't ship in the Mac App Store as-is.

## Developer tools

```bash
swift build
.build/debug/Blipp --render-gallery /tmp/blipp-gallery   # PNGs of every state and the menu bar icons
.build/debug/Blipp --benchmark --sensors                  # time every sampler, list temperature sensors
```

## Project layout

```
Sources/
  CSensors/           C shim for the temperature sensors
  Blipp/
    App/              App delegate, status item, icon export, preview renderer
    Blipp/            The figure: scene model, mood engine, SVG path parser, renderers
    Monitor/          Samplers and the SystemMonitor that ties them together
    Settings/         Preferences
    UI/               Panel, settings window, graphs, menu bar icon
```

Note: the Command Line Tools don't include SwiftUI's macro plugin, so the code avoids `@State`
and keeps view state in small `ObservableObject`s instead.
