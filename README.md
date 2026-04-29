# timerMode

Two QuickSettings tiles for the reMarkable Paper Pro (rMPP, ferrari) and
Paper Pro Move (porsche), firmware 3.26.0.68:

- **Stopwatch tile** (clock icon)
  - tap → toggle run / pause
  - long-press → reset to 00:00
- **Timer tile** (clock-arrow icon)
  - tap (idle) → opens a duration popup (5 / 15 / 25 / 45 / 60 min)
  - tap (running) → cancel countdown
  - long-press → cancel + clear remembered duration

State persists across panel re-opens AND across xochitl restarts via two
flag files; the tile re-hydrates from disk on every `Component.onCompleted`.
The QML scope is torn down whenever Quick Settings closes, so the file is
the source of truth.

## Files shipped

| Source | On-device path |
|---|---|
| `build/timerMode.qmd` | `/home/root/xovi/exthome/qt-resource-rebuilder/timerMode.qmd` |

State files (created at runtime, removed by `make uninstall`):

```
/home/root/.stopwatch-state    {"running": bool, "startMs": int, "accumulatedMs": int}
/home/root/.timer-state        {"deadlineMs": int, "durationMs": int}
```

## Install

USB cable, device on `10.11.99.1`:

```sh
make install
```

Override `DEVICE=` for WLAN:

```sh
make install DEVICE=192.168.1.112    # ferrari WLAN
make install DEVICE=192.168.1.115    # porsche WLAN
```

`make install` compiles `src/timerMode.qml-diff` to a hashed
`build/timerMode.qmd`, backs up any existing `timerMode.qmd` on the device
once, pushes the file, restarts xochitl, and greps the journal for
parse/load errors. If a parse error fires, the target exits non-zero.

`make reinstall` skips the backup churn (use this for iterating).
`make uninstall` removes the qmd AND clears state files; `make restore`
puts the `.bak` back if one was captured during the first install.

## Verify it loaded

After install:

```sh
ssh root@10.11.99.1 \
  "journalctl -u xochitl --since '30 sec ago' --no-pager | \
   grep -iE 'timerMode|ToggleColumn|ToggleGrid'"
```

You should see:

```
[qmldiff]: Loading file timerMode.qmd
[qmldiff]: Processing file /qt/qml/xofm/modules/settings/qml/quicksettings/ToggleColumn.qml...
[qmldiff]: Processing file /qt/qml/xofm/modules/settings/qml/quicksettings/ToggleGrid.qml...
```

Then swipe down from the top bar — Quick Settings opens — the two new
tiles sit at the end of the stock tile row.

## How it works

Both tiles inject as `QuickSettingsToggle` siblings of the existing
`Repeater` inside `?#root` of `ToggleColumn.qml` and `ToggleGrid.qml`
(one of which is loaded depending on screen orientation).

### Stopwatch math

```
running:  elapsedMs = accumulatedMs + (Date.now() - startMs)
paused:   elapsedMs = accumulatedMs
reset:    accumulatedMs = 0, startMs = 0, running = false
```

`startMs` is the monotonic-ish epoch when the user last tapped to
start/resume; `accumulatedMs` carries forward whatever was on the clock
when they last paused.

### Timer math

`deadlineMs` is the wall-clock time the countdown ends. The
`timerExpiryCheck` Timer polls every second while the panel is open
and the tile is `selected`; if the panel is closed when the timer
expires, the next panel-open's `Component.onCompleted` reads stale
state, notices `deadlineMs <= Date.now()`, and clears the file.

### Why no audio alarm

rMPP / Move have no built-in audio output, so timer expiry is visual
only — the tile just drops out of `selected`. (See CLAUDE.md device
hardware notes — no speaker on either device.)

## Compatibility

- **Firmware**: 3.26.0.68. Hashes will not match other firmwares — if
  you upgrade, rebuild the hashtab on-device and recompile (see
  `freeColour.plugin/reference/qmldiff-workflow.md`).
- **Devices**: rMPP 11.8" ferrari + rMPP Move porsche. Same QuickSettings
  paths on both.

## Known limits

- Tile shows running/idle visual state via `selected` only — no live
  elapsed-time text. Adding a `Text` overlay inside `QuickSettingsToggle`
  is possible if its layout permits children; not attempted in v1.
- Timer presets are hard-coded at `[5, 15, 25, 45, 60]` minutes.
  Edit `src/timerMode.qml-diff` and `make reinstall` to change.
- No alarm sound at expiry (no speaker; see above).
- Long-press threshold is whatever `QuickSettingsToggle.onPressAndHold`
  defaults to (typically Qt's 800 ms).

## Toolchain

Reuses the `qmldiff` + hashtab toolchain from `../freeColour.plugin/`:

- `bin/compile-qmd.sh` — copy of shoppingMode's; compiles plain
  `src/timerMode.qml-diff` against the hashtab.
- `reference/hashtab` — symlink to `../freeColour.plugin/reference/hashtab`
  (single source of truth, firmware 3.26.0.68).

## Reference

- `shoppingMode.plugin/` — direct precedent for the QuickSettings tile
  injection pattern (one tile + flag-file persistence).
- `freeColour.plugin/src/freeColour-twobox.qml-diff` — Popup pattern
  used by the duration picker (modal Popup parented to `Overlay.overlay`).
