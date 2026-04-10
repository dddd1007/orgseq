# org-focus-timer

A Vitamin-R–style focus timer for org-mode. Drop it into any buffer, let it count down to the next round clock mark, record how the slice felt, and watch your focus habits accumulate into a simple text-based dashboard over the weeks.

> **Status**: This package currently lives as a bundled subproject inside [`org-seq`](../..), an Emacs PKM configuration. Once its API and log format stabilize, it will graduate to its own standalone repository. Until then, the package source here is fully self-contained — zero org-seq-specific code, zero dependencies beyond Emacs 29+. If you want to use it today in a different Emacs setup, copy `org-focus-timer.el` anywhere on your `load-path` and `(require 'org-focus-timer)`.

## Why another timer?

Most pomodoro packages give you a fixed 25-minute slice, regardless of what time of day you start. That's fine if you're a machine, but if you glance at the clock at 14:17 and decide to focus until you finish the current thought, you probably don't want the timer to dump you out at 14:42 mid-sentence. You want it to end at 14:30 — a clean clock mark you can naturally recognize.

This package mimics the snapping behavior of [Vitamin-R](https://www.publicspace.net/Vitamin-R/) (a macOS productivity app): every slice ends on the nearest round boundary within a 10–30 minute window, so the timer works *with* the clock instead of against it. When the slice ends, you answer a one-keystroke prompt about how it felt, and the result is appended both inline in your source buffer and to a dedicated log file you can query later.

## Requirements

- Emacs 29.1 or newer
- No external dependencies

## Installation

### Inside org-seq (the current home)

Nothing to do — `lisp/init-focus.el` already references this file via `:load-path` pointing at `<user-emacs-directory>/packages/org-focus-timer/`. After running `deploy.sh` or `deploy.ps1` from the org-seq repo, the package is available as `SPC a f` (start), `SPC a F` (dashboard), and `SPC a X` (abort).

### Standalone (for use outside org-seq)

Drop `org-focus-timer.el` anywhere on your `load-path` and load it:

```elisp
(add-to-list 'load-path "~/path/to/org-focus-timer")
(require 'org-focus-timer)
(global-set-key (kbd "C-c f s") #'org-focus-start)
(global-set-key (kbd "C-c f d") #'org-focus-dashboard)
```

Or via `use-package`:

```elisp
(use-package org-focus-timer
  :load-path "~/path/to/org-focus-timer"
  :commands (org-focus-start org-focus-abort org-focus-dashboard)
  :bind (("C-c f s" . org-focus-start)
         ("C-c f d" . org-focus-dashboard)))
```

## Quick start

1. Open any org buffer (it actually works in any buffer, but org is where it's most natural).
2. Move point to where you want to record "I'm starting to focus now."
3. `M-x org-focus-start` — a line appears at point with the start timestamp, the planned duration, and the end time.
4. Work.
5. When the timer fires, Emacs beeps and asks: *"How did that feel? (u) unfocused, (n) normal, (f) flow state"* — press a single key.
6. Your answer is appended to the inline marker and saved to the log file.

`M-x org-focus-dashboard` opens a text view of the last 14 days: one row per day, a colored timeline bar showing each slice, a 14-day summary with counts and minutes per outcome.

## How the time snapping works

Given the current time `now`, the package looks for a clock boundary inside the window `[now + 10min, now + 30min]`:

```
now   = 14:17
window = [14:27, 14:47]
15-min boundaries in window: 14:30, 14:45
nearest to now = 14:30
planned duration = 13 minutes
```

If the default 15-minute alignment fails (rare, only if you set the window very small), it falls back to 5-minute alignment, and then to the raw `now + max`. You can override by running `org-focus-start` with `C-u` prefix, which prompts for a custom duration with the snapped value pre-filled.

## Customization

All settings live in the `org-focus-timer` customize group. The ones most people will want to change:

| Variable | Default | Meaning |
|---|---|---|
| `org-focus-log-file` | `~/.emacs.d/focus-log.org` | Where completed slices are persisted |
| `org-focus-min-duration` | `10` | Earliest the slice can end, in minutes from now |
| `org-focus-max-duration` | `30` | Latest the slice can end, in minutes from now |
| `org-focus-round-to` | `15` | Minute alignment (15 = :00/:15/:30/:45) |
| `org-focus-outcomes` | see source | The choices at the post-slice prompt |
| `org-focus-ring-bell-on-end` | `t` | Whether to `ding` when the slice ends |
| `org-focus-dashboard-days` | `14` | Days of history shown in the dashboard |

Example — snap to 5-minute boundaries instead of 15, and point the log file at a notes vault:

```elisp
(setq org-focus-round-to 5
      org-focus-log-file "~/NoteHQ/.orgseq/focus-log.org")
```

> When used as part of org-seq, `lisp/init-focus.el` already sets the log file and other defaults via `use-package :custom`. The values above apply if you use the package standalone.

## Log file format

Each day is a level-1 heading; each completed slice is a level-2 heading with a property drawer. The log is plain org, so you can edit it by hand, query it with `org-ql`, version it with git, or pipe it through any tool that reads text:

```org
#+title: Focus Timer Log
#+filetags: :focus:

* 2026-04-10 Fri
** 14:17 flow (13m)
:PROPERTIES:
:STARTED:  [2026-04-10 Fri 14:17]
:ENDED:    [2026-04-10 Fri 14:30]
:PLANNED:  13
:ACTUAL:   13
:OUTCOME:  flow
:CONTEXT:  /home/you/NoteHQ/Roam/daily/2026-04-10.org
:END:

** 14:45 normal (15m)
:PROPERTIES:
:STARTED:  [2026-04-10 Fri 14:45]
:ENDED:    [2026-04-10 Fri 15:00]
:PLANNED:  15
:ACTUAL:   15
:OUTCOME:  normal
:END:
```

## Dashboard

`M-x org-focus-dashboard` renders something like this inside a dedicated buffer:

```
FOCUS DASHBOARD
  log: ~/NoteHQ/.orgseq/focus-log.org
  range: last 14 days

Daily timeline
   legend: flow = █   normal = ▓   unfocused = ░

  2026-04-10 Fri  4 slices  58m total  84% focused  38m flow
    ██ ▓▓▓ █ ▓▓▓
  2026-04-09 Thu  3 slices  45m total  66% focused
    ▓▓▓ ░░░ ▓▓▓
  2026-04-08 Wed  2 slices  30m total  100% focused  30m flow
    ███ ███

Summary over 14 days
  flow          5 slices   71 min   41.0%
  normal        8 slices   85 min   49.1%
  unfocused     2 slices   17 min    9.8%
  total        15 slices  173 min
```

Inside the dashboard:

- `g` refresh
- `RET` open the raw log file in another window
- `s` start a new focus slice (useful if you came to the dashboard from a buffer you already closed)
- `q` quit

## Modeline indicator

While a slice is running, the modeline shows a live countdown: `[FOCUS 12:34]`. The tick timer updates it once per second. When the slice ends and you answer the prompt, the indicator clears automatically.

## Commands

| Command | Binding in org-seq | What it does |
|---|---|---|
| `org-focus-start` | `SPC a f` | Start a slice at point, snap to nearest boundary |
| `org-focus-start` with `C-u` | `C-u SPC a f` | Start a slice with a custom duration |
| `org-focus-abort` | `SPC a X` | Cancel the running slice without recording |
| `org-focus-dashboard` | `SPC a F` | Open the visualization buffer |

## Design notes

The package is small on purpose. There is one state variable (`org-focus--current`) holding the active slice plist, two timers (the end timer and the modeline tick timer), and a single log file. There is no database, no async worker, no minor mode — when nothing is running, the package consumes zero resources beyond the loaded bytes.

**The package knows nothing about org-seq.** All org-seq-specific defaults (log file location at `~/NoteHQ/.orgseq/`, the `SPC a f` keybinding, the 10/30/15 parameter choices) live in `lisp/init-focus.el` inside the org-seq repository, not here. This separation is intentional: when this package graduates to its own repo, `git mv packages/org-focus-timer/ ../org-focus-timer/` should work without touching a single line of code inside the package directory.

If you want to extend it:

- **Add outcome choices**: append to `org-focus-outcomes`. Each entry is `(CHAR INTERNAL-NAME DISPLAY-NAME)`.
- **Integrate with a habit tracker**: read the log file with `org-map-entries` or `org-ql`; each slice has enough properties to compute any metric you want.
- **Add an SVG chart**: `org-focus--read-entries` returns structured data that you can feed to `chart.el`, `ob-plantuml`, or any external charting tool.

## License

MIT
